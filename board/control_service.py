"""Bounded JSON-line control connection, separate from the IQ data socket.

This module imports no hardware. ``apply`` runs under the same lock the owner
uses around capture, so converter changes cannot race a capture. The callback
must be bounded and returns the applied hardware state (including its revision,
if used). An acknowledgement is sent only after that callback returns.
"""
import json
import re
import socket
import threading

MAX_LINE_BYTES = 8192
MAX_COMMAND_CHARS = 4096
MAX_COMMANDS = 16
MAX_ID = 2**53 - 1  # exact in MATLAB double, as well as Python/JSON
MAX_CLIENTS = 4


class ControlError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def parse_commands(line):
    """Validate an entire legacy ``#`` batch before any hardware is touched.

    Integers retain the existing MHz/degree conventions. RF frequency and phase
    bounds are syntax-level limits; the hardware adapter can impose a narrower
    current profile. ``dataChan`` is int16 lane words, not complex samples.
    """
    if not isinstance(line, str) or not line.strip() or len(line) > MAX_COMMAND_CHARS:
        raise ControlError('BadCommand', 'command must be a nonempty string of at most 4096 characters')
    if any(c in line for c in '\r\n\0'):
        raise ControlError('BadCommand', 'command must occupy one line')
    parts = line.split('#')
    if len(parts) > MAX_COMMANDS or any(not p.strip() for p in parts):
        raise ControlError('BadCommand', 'batch must contain 1 to 16 nonempty commands')
    counts = {'status': 0, 'fc': 6, 'phase': 4, 'dphase': 4,
              'dataStream': 1, 'da': 1, 'dacPow': 4, 'dataChan': 1,
              # converter path settings (RFSoC4x2 adapter; per ADC index 0..3 = ADC_D, ADC_C,
              # ADC_B, ADC_A, per DAC index 0 = DAC_B, 2 = DAC_A; 1 and 3 unused)
              'phasec': 4, 'dphasec': 4,          # mixer phase, hundredths of a degree
              'again': 4, 'dgain': 4,             # QMC gain, hundredths (0..199 = 0..1.99)
              'aiqphase': 4, 'diqphase': 4,       # QMC I/Q phase correction, hundredths of a degree
              'adsa': 4,                          # ADC step attenuator, dB
              'dvop': 4}                          # DAC output current, microamperes
    result = []
    for part in parts:
        tokens = part.split()
        name = tokens[0]
        if name not in counts:
            raise ControlError('UnsupportedCommand', 'unsupported RFSoC4x2 command: ' + name)
        if len(tokens) != (1 if counts[name] == 0 else 2):
            raise ControlError('BadArguments', name + ' has the wrong argument count')
        words = [] if len(tokens) == 1 else tokens[1].split('/')
        if len(words) != counts[name] or any(not re.fullmatch(r'[+-]?[0-9]{1,10}', x) for x in words):
            raise ControlError('BadArguments', name + ' requires ' + str(counts[name]) + ' integer arguments')
        values = [int(x) for x in words]
        if name == 'fc' and (any(abs(values[k]) > 6000 for k in (0, 2, 4))
                             or any(values[k] not in (1, 2) for k in (1, 3, 5))):
            raise ControlError('OutOfRange', 'fc requires |MHz| <= 6000 and Nyquist zones 1 or 2')
        if name in ('phase', 'dphase') and any(abs(x) > 360000 for x in values):
            raise ControlError('OutOfRange', 'phase magnitude must be <= 360000 degrees')
        if name in ('dataStream', 'dacPow') and any(x not in (0, 1) for x in values):
            raise ControlError('OutOfRange', name + ' requires binary values')
        if name == 'da' and values[0] not in (0, 1, 2):
            raise ControlError('OutOfRange', 'da must be 0, 1 or 2')
        if name in ('phasec', 'dphasec') and any(abs(x) > 36000 for x in values):
            raise ControlError('OutOfRange', name + ' requires |hundredths of a degree| <= 36000')
        if name in ('again', 'dgain') and any(not 0 <= x <= 199 for x in values):
            raise ControlError('OutOfRange', name + ' requires 0..199 (gain 0..1.99)')
        if name in ('aiqphase', 'diqphase') and any(abs(x) > 2649 for x in values):
            raise ControlError('OutOfRange', name + ' requires |hundredths of a degree| <= 2649')
        if name == 'adsa' and any(not 0 <= x <= 27 for x in values):
            raise ControlError('OutOfRange', 'adsa requires 0..27 dB')
        if name == 'dvop' and any(x and not 2250 <= x <= 40500 for x in values):
            raise ControlError('OutOfRange', 'dvop requires 2250..40500 uA (0 for an unused index)')
        if name == 'dataChan' and not (0 < values[0] <= 1048576 and values[0] % 8 == 0):
            raise ControlError('OutOfRange', 'dataChan requires 8..1048576 lane words in multiples of eight')
        result.append((name, values))
    return result


class ControlService:
    """One owned listener and persistent clients; hardware callback serialized.

    ``peer`` optionally restricts control connections to one source IP. Port zero
    is useful for software tests; read ``port`` after ``start``. Repeated start
    before close is harmless; a closed service cannot be restarted.
    """
    def __init__(self, bind, port, apply, lock=None, peer=None):
        if not callable(apply):
            raise TypeError('apply must be callable')
        self.bind, self.port, self.apply, self.peer = bind, port, apply, peer
        self.lock = lock if lock is not None else threading.RLock()
        self._stop = threading.Event()
        self._guard = threading.Lock()
        self._listener = None
        self._clients = set()
        self._threads = set()
        self._accept_thread = None

    def start(self):
        with self._guard:
            if self._stop.is_set():
                raise RuntimeError('closed control service cannot restart')
            if self._listener is not None:
                return self
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind((self.bind, self.port))
                listener.listen(4)
                listener.settimeout(.2)
            except BaseException:
                listener.close()
                raise
            self.port = listener.getsockname()[1]
            self._listener = listener
            self._accept_thread = threading.Thread(target=self._accept, name='rfsoc-control-listener', daemon=True)
            self._accept_thread.start()
        return self

    def _accept(self):
        while not self._stop.is_set():
            try:
                client, address = self._listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            client.settimeout(.2)
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            with self._guard:
                if self._stop.is_set():
                    client.close()
                    break
                if len(self._clients) >= MAX_CLIENTS:
                    # Keep the accept thread and memory bounded even if a
                    # controller disconnects badly and leaves idle sockets.
                    try:
                        self._send(client, self._error(None, 'Busy', 'control client limit reached'))
                    except OSError:
                        pass
                    client.close()
                    continue
                self._clients.add(client)
                worker = threading.Thread(target=self._serve, args=(client, address[0]),
                                          name='rfsoc-control-client', daemon=True)
                self._threads.add(worker)
                worker.start()

    @staticmethod
    def _error(request_id, code, message):
        return {'id': request_id, 'ok': False, 'error': {'code': code, 'message': message}}

    def _request(self, raw):
        request_id = None
        try:
            # Reject duplicate JSON keys, including duplicate id/command fields.
            def unique(items):
                result = {}
                for key, value in items:
                    if key in result:
                        raise ControlError('BadRequest', 'duplicate JSON field: ' + key)
                    result[key] = value
                return result
            request = json.loads(raw.decode('utf-8'), object_pairs_hook=unique,
                                 parse_constant=lambda _: (_ for _ in ()).throw(
                                     ControlError('BadRequest', 'nonfinite JSON numbers are forbidden')))
            if not isinstance(request, dict) or set(request) != {'id', 'command'}:
                raise ControlError('BadRequest', 'request must contain only id and command')
            candidate = request['id']
            if type(candidate) is not int or not 0 < candidate <= MAX_ID:
                raise ControlError('BadRequest', 'id must be a positive integer <= 2^53-1')
            request_id = candidate
            parse_commands(request['command'])
            while not self._stop.is_set():
                if self.lock.acquire(timeout=.1):
                    try:
                        if self._stop.is_set():
                            raise ControlError('Closing', 'control service is closing')
                        result = self.apply(request['command'])
                        if not isinstance(result, dict):
                            raise ControlError('CallbackError', 'apply must return a hardware-state object')
                        # Preflight encoding while still serialized; reject NaN state.
                        json.dumps(result, allow_nan=False)
                        return {'id': request_id, 'ok': True, 'result': result}
                    finally:
                        self.lock.release()
            raise ControlError('Closing', 'control service is closing')
        except ControlError as exc:
            return self._error(request_id, exc.code, str(exc))
        except (UnicodeError, json.JSONDecodeError) as exc:
            return self._error(request_id, 'BadJSON', str(exc))
        except Exception as exc:
            return self._error(request_id, 'ApplyError', str(exc))

    @staticmethod
    def _send(client, response):
        data = json.dumps(response, allow_nan=False, separators=(',', ':')).encode('utf-8') + b'\n'
        client.settimeout(1)
        client.sendall(data)
        client.settimeout(.2)

    def _serve(self, client, peer):
        try:
            if self.peer is not None and peer != self.peer:
                self._send(client, self._error(None, 'PeerDenied', 'control peer is not the stream owner'))
                return
            pending = bytearray()
            while not self._stop.is_set():
                try:
                    block = client.recv(4096)
                except socket.timeout:
                    continue
                if not block:
                    break
                pending.extend(block)
                while b'\n' in pending:
                    line, _, tail = pending.partition(b'\n')
                    pending = bytearray(tail)
                    if len(line) > MAX_LINE_BYTES:
                        self._send(client, self._error(None, 'LineTooLong', 'control line exceeds 8192 bytes'))
                        return
                    self._send(client, self._request(line))
                if len(pending) > MAX_LINE_BYTES:
                    self._send(client, self._error(None, 'LineTooLong', 'control line exceeds 8192 bytes'))
                    return
        except (OSError, ValueError):
            pass  # disconnect or owned shutdown, never a hardware callback retry
        finally:
            client.close()
            with self._guard:
                self._clients.discard(client)
                self._threads.discard(threading.current_thread())

    def close(self):
        self._stop.set()
        with self._guard:
            listener = self._listener
            clients = list(self._clients)
            workers = list(self._threads)
            accept = self._accept_thread
        if listener is not None:
            listener.close()
        for client in clients:
            try:
                client.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            client.close()
        for worker in [accept, *workers]:
            if worker is not None and worker is not threading.current_thread():
                worker.join(timeout=2)

    @property
    def alive(self):
        with self._guard:
            return bool((self._accept_thread and self._accept_thread.is_alive())
                        or any(t.is_alive() for t in self._threads))
