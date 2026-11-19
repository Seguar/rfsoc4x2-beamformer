#!/usr/bin/env python3
"""RFSoC4x2 beamformer session service: lets the host application start a
hardware session over plain TCP, without SSH or a launcher.

Installed once by tools/install_board_service.py and run as a systemd unit. It
touches no hardware while idle. One client at a time:

  client -> {"op":"identify"}
  board  -> {"service":"rfsoc4x2-beamformer","protocol":1,"board":"RFSoC4x2","busy":false}

  client -> {"op":"start","max_seconds":N}
  board  -> {"state":"starting","step":...,"elapsed":s}        repeated
  board  -> {"state":"ready","host":...,"stream_port":...,"control_port":...}
  ...       the client uses the stream and control ports of legacy_capture.py
  client -> {"op":"stop"}  or closes the connection
  board  -> {"state":"ended","dac_off_commanded":true,"shutdown_errors":[],...}
  board  -> {"state":"error","code":...,"message":...}         instead, on refusal

The session connection is the owner. When it closes, is lost (TCP keepalive,
about 8 s) or the service is stopped, the helper's stdin is closed: the helper
then zeroes both DAC RAMs and commands both outputs off, as with the launcher.
bootpy.service is stopped for the session and started again afterwards only if
it was running. /boot is never written. A UDP datagram b'rfsoc4x2-beamformer?'
on the same port is answered with the identify reply (address discovery).
"""
import argparse
import hashlib
import ipaddress
import json
import os
import platform
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

SERVICE = 'rfsoc4x2-beamformer'
PROTOCOL = 1
PORT = 4013
PROBE = b'rfsoc4x2-beamformer?'
MAX_SECONDS = 14400
MAX_FRAMES = 200000
# Same table as legacy_capture.RF_PROFILES (tests keep them equal; the service does not
# import the helper): start frequency in MHz -> ADC / DAC Nyquist zone.
RF_PROFILES = {3000: dict(adc_zone=2, dac_zone=1), 5200: dict(adc_zone=1, dac_zone=2)}
DEFAULT_RF_MHZ = 5200
DAC_PEAK_MAX = 9600          # equal to the helper's; it also checks ADC headroom at start
DEFAULT_DAC_PEAK = 9600          # over the air at 0.2 m: 1200 no lock, 4800 ~0.76, 9600 0.92 (2026-11-19)
KEEP_RUNS = 20
READY_LINE = 'Waiting for legacy client'
EXPECTED = {
    '/boot/doa_mts.py': '0b4991115401c759296254caea0d0f41ffdfd3edc9b7759df071186d3f01bdf4',
    '/boot/doa_mts.bit': '78e11ab2872fc3ac6252f3ec800f10d6dacd46f910e5df87446cffffee6d52d0',
    '/boot/doa_mts.hwh': '3e0c46dc4a911a0026cfc0cd22a22897acebc561816620f094a2ac5f8b2de471',
    '/boot/data.mat': '3f17e6cccef941d1bac4fefff4439472d8a6e6923b0ef7633e6184448be9eef3',
}
OWNERS = ('board_capture.py', 'legacy_capture.py', 'boot.py', 'ipykernel_launcher')
# Peers accepted without --allow-cidr: loopback, link-local, private ranges and
# the carrier-grade NAT range used by overlay networks, plus any network the
# board is directly attached to. A routed public peer is refused.
DEFAULT_NETS = [ipaddress.ip_network(n) for n in
                ('127.0.0.0/8', '169.254.0.0/16', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10')]


class Refused(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def local_networks():
    out = subprocess.run(['ip', '-4', '-o', 'addr'], capture_output=True, text=True).stdout
    nets = []
    for row in out.splitlines():
        parts = row.split()
        if 'inet' in parts:
            try:
                nets.append(ipaddress.ip_interface(parts[parts.index('inet') + 1]).network)
            except ValueError:
                pass
    return nets


def peer_allowed(peer, attached, extra=()):
    try:
        address = ipaddress.ip_address(peer)
    except ValueError:
        return False
    return any(address in net for net in [*DEFAULT_NETS, *attached, *extra])


def busy_owners(rows):
    """Running Python processes that own the converters (not stopped sudo
    parents, zombies or command text that merely mentions a script name)."""
    busy = []
    for row in rows:
        p = row.split(None, 3)
        if len(p) < 4 or 'Z' in p[2]:
            continue
        try:
            args = shlex.split(p[3])
        except ValueError:
            continue
        if not args or not Path(args[0]).name.startswith('python'):
            continue
        if any(Path(t).name in OWNERS for t in args[1:3]):
            busy.append(row)
    return busy


_HASHES = {}


def file_sha(path):
    st = os.stat(path)
    key = (path, st.st_mtime_ns, st.st_size)
    if key not in _HASHES:
        _HASHES[key] = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    return _HASHES[key]


def board_name():
    try:
        return Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(b'\x00').decode()
    except OSError:
        return ''


def preflight(ports, own_pid=None):
    rows = subprocess.check_output(['ps', '-eo', 'pid=,ppid=,stat=,args='], text=True).splitlines()
    busy = [r for r in busy_owners(rows) if own_pid is None or r.split()[0] != str(own_pid)]
    boot = subprocess.run(['systemctl', 'is-active', 'bootpy.service'], capture_output=True, text=True).stdout.strip()
    listen = subprocess.run(['ss', '-ltn'], capture_output=True, text=True).stdout.splitlines()[1:]
    taken = [n for n in ports if any(len(p.split()) >= 4 and p.split()[3].endswith(':' + str(n)) for p in listen)]
    hashes = {}
    for path in EXPECTED:
        try:
            hashes[path] = file_sha(path)
        except OSError:
            hashes[path] = None
    return dict(board=board_name(), machine=platform.machine(), busy=busy, bootpy=boot, ports_taken=taken, hashes=hashes)


def check_preflight(pre):
    """Raise Refused unless the board is the expected one and free. bootpy is
    handled by the caller: boot.py rows are its process and are not 'busy'."""
    if pre['board'] != 'RFSoC4x2' or pre['machine'] != 'aarch64':
        raise Refused('wrong_board', 'This is not an RFSoC4x2 (found "%s").' % pre['board'])
    if pre['hashes'] != EXPECTED:
        raise Refused('boot_assets', 'The FPGA image or waveform in /boot differs from the supported ones.')
    boot_running = pre['bootpy'] in ('active', 'activating', 'reloading')
    others = [r for r in pre['busy'] if not (boot_running and '/boot/boot.py' in r)]
    if any('ipykernel_launcher' in r for r in others):
        raise Refused('board_busy', 'A Jupyter notebook kernel is running on the board. Shut it down, then connect again.')
    if others:
        raise Refused('board_busy', 'Another capture program is running on the board.')
    if pre['ports_taken']:
        raise Refused('board_busy', 'Stream ports are already in use on the board: %s.' % pre['ports_taken'])
    return boot_running


def send(conn, message):
    try:
        conn.sendall(json.dumps(message, separators=(',', ':')).encode() + b'\n')
        return True
    except OSError:
        return False


def keepalive(conn):
    """Detect a lost owner (cable pulled, host off) within about 8 s."""
    conn.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    for name, value in (('TCP_KEEPIDLE', 2), ('TCP_KEEPINTVL', 2), ('TCP_KEEPCNT', 3), ('TCP_USER_TIMEOUT', 8000)):
        if hasattr(socket, name):
            conn.setsockopt(socket.IPPROTO_TCP, getattr(socket, name), value)


class Service:
    def __init__(self, a, *, preflight_fn=preflight, networks_fn=local_networks, systemctl=None):
        self.a = a
        self.root = Path(a.root)
        self.state = Path(a.state)
        self.extra = [ipaddress.ip_network(n) for n in a.allow_cidr]
        self.preflight_fn = preflight_fn
        self.networks_fn = networks_fn
        self.systemctl = systemctl or (lambda *args: subprocess.run(['systemctl', *args], capture_output=True, text=True))
        self.session = threading.Lock()
        self.stopping = threading.Event()
        self.tcp = self.udp = None
        self.port = a.port

    # -- identity -----------------------------------------------------------
    def identity(self):
        return dict(service=SERVICE, protocol=PROTOCOL, board=board_name() or self.a.board_name,
                    busy=self.session.locked(), session_port=self.port)

    def allowed(self, peer):
        return peer_allowed(peer, self.networks_fn(), self.extra)

    # -- servers ------------------------------------------------------------
    def start(self):
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.tcp.bind((self.a.bind, self.a.port))
        self.tcp.listen(8)
        self.tcp.settimeout(.5)
        self.port = self.tcp.getsockname()[1]
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp.bind((self.a.bind, self.port))
        self.udp.settimeout(.5)
        threading.Thread(target=self.discovery, daemon=True).start()
        self.acceptor = threading.Thread(target=self.accept_loop, daemon=True)
        self.acceptor.start()
        return self

    def discovery(self):
        while not self.stopping.is_set():
            try:
                data, peer = self.udp.recvfrom(256)
            except socket.timeout:
                continue
            except OSError:
                return
            if data.strip() == PROBE and self.allowed(peer[0]):
                try:
                    self.udp.sendto(json.dumps(self.identity()).encode(), peer)
                except OSError:
                    pass

    def accept_loop(self):
        while not self.stopping.is_set():
            try:
                conn, peer = self.tcp.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=self.client, args=(conn, peer), daemon=True).start()

    def close(self, wait=150):
        """Stop accepting and end a running session (DAC shutdown included)."""
        self.stopping.set()
        deadline = time.monotonic() + wait
        while self.session.locked() and time.monotonic() < deadline:
            time.sleep(.1)
        for s in (self.tcp, self.udp):
            if s is not None:
                try:
                    s.close()
                except OSError:
                    pass

    # -- one client ---------------------------------------------------------
    def client(self, conn, peer):
        with conn:
            try:
                if not self.allowed(peer[0]):
                    send(conn, dict(state='error', code='peer_refused',
                                    message='This address is not allowed to use the board service.'))
                    return
                conn.settimeout(5)
                line = b''
                while not line.endswith(b'\n') and len(line) < 4096:
                    part = conn.recv(1)
                    if not part:
                        return
                    line += part
                request = json.loads(line)
                op = request.get('op') if isinstance(request, dict) else None
                if op == 'identify':
                    send(conn, self.identity())
                elif op == 'start':
                    self.run_session(conn, request)
                else:
                    send(conn, dict(state='error', code='bad_request', message='Unknown request.'))
            except (OSError, ValueError) as exc:
                send(conn, dict(state='error', code='bad_request', message=type(exc).__name__))

    def run_session(self, conn, request):
        if not self.session.acquire(blocking=False):
            send(conn, dict(state='error', code='board_busy', message='The board is already in use by another session.'))
            return
        try:
            self._session(conn, request)
        except Refused as exc:
            send(conn, dict(state='error', code=exc.code, message=str(exc)))
        except Exception as exc:  # report, never leave the client waiting
            print('session failed: %s: %s' % (type(exc).__name__, exc), flush=True)
            send(conn, dict(state='error', code='service_error', message='%s: %s' % (type(exc).__name__, exc)))
        finally:
            self.session.release()

    def _session(self, conn, request):
        seconds = request.get('max_seconds', MAX_SECONDS)
        if not isinstance(seconds, (int, float)) or isinstance(seconds, bool) or not 1 <= seconds <= MAX_SECONDS:
            raise Refused('bad_request', 'max_seconds must be between 1 and %d.' % MAX_SECONDS)
        a = self.a
        rf_mhz = request.get('rf_mhz', a.rf_mhz)
        if isinstance(rf_mhz, bool) or rf_mhz not in RF_PROFILES:
            raise Refused('bad_request', 'rf_mhz must be one of %s.' % ', '.join(map(str, sorted(RF_PROFILES))))
        dac_peak = request.get('dac_peak', getattr(a, 'dac_peak', DEFAULT_DAC_PEAK))
        if not isinstance(dac_peak, int) or isinstance(dac_peak, bool) or not 100 <= dac_peak <= DAC_PEAK_MAX:
            raise Refused('bad_request', 'dac_peak must be an integer 100..%d.' % DAC_PEAK_MAX)
        send(conn, dict(state='starting', step='checking the board', elapsed=0))
        boot_was_running = check_preflight(self.preflight_fn([a.stream_port, a.control_port]))
        keepalive(conn)
        local = conn.getsockname()[0]
        run = self.state / 'runs' / (time.strftime('%Y%m%d-%H%M%S', time.gmtime()) + '-%04x' % (os.getpid() & 0xffff))
        run.mkdir(parents=True, exist_ok=True)
        self.prune()
        helper = None
        summary = dict(state='ended', reason='', dac_off_commanded=False, shutdown_errors=['helper did not run'], frames=0)
        t0 = time.monotonic()
        try:
            if boot_was_running:
                send(conn, dict(state='starting', step='stopping the boot service', elapsed=0))
                self.systemctl('stop', 'bootpy.service')
            args = [a.python, str(self.root / a.helper), '--exclusive-control', '--owner-stdin',
                    '--reference', str(self.root / 'legacy_ref.npz'), '--out', str(run / 'manifest.json'),
                    '--continuous', '--max-seconds', str(int(seconds)), '--max-frames', str(MAX_FRAMES),
                    '--stream-bind', local, '--stream-port', str(a.stream_port), '--request-timeout', '120',
                    '--control-port', str(a.control_port), '--dac', '0', '--rf-mhz', str(rf_mhz),
                    '--dac-peak', str(dac_peak),
                    '--sampling-freq-unit', 'GHz', '--wire-mode', 'window4']
            clock = request.get('capture_clock_mhz', getattr(a, 'capture_clock_mhz', 0))
            if clock:
                if not isinstance(clock, (int, float)) or isinstance(clock, bool) or not 125 <= clock <= 150:
                    raise Refused('bad_request', 'capture_clock_mhz must be 125..150.')
                args += ['--capture-clock-mhz', str(float(clock))]
            helper = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      cwd=str(run), env={**os.environ, 'BOARD': 'RFSoC4x2', 'XILINX_XRT': '/usr'})
            ready = threading.Event()
            # the helper reports the zones it really set (5200: DAC zone measured per session)
            rf_state = dict(rf_mhz=rf_mhz, adc_nyquist_zone=RF_PROFILES[rf_mhz]['adc_zone'],
                            dac_nyquist_zone=RF_PROFILES[rf_mhz]['dac_zone'], dac_peak=dac_peak)

            def log_output():
                with (run / 'board.log').open('wb') as log:
                    for raw in iter(helper.stdout.readline, b''):
                        log.write(raw)
                        log.flush()
                        if raw.startswith(b'RF profile '):
                            try:
                                rf_state.update(json.loads(raw[len(b'RF profile '):]))
                            except ValueError:
                                pass
                        if READY_LINE.encode() in raw:
                            ready.set()
            reader = threading.Thread(target=log_output, daemon=True)
            reader.start()
            reason = self.wait_ready(conn, helper, ready, t0)
            if reason is None:
                send(conn, dict(state='ready', host=local, stream_port=a.stream_port, control_port=a.control_port,
                                max_seconds=int(seconds), start_seconds=round(time.monotonic() - t0, 1),
                                **rf_state))
                reason = self.wait_end(conn, helper)
            summary['reason'] = reason
        finally:
            if helper is not None:
                self.stop_helper(helper)
                try:
                    manifest = json.loads((run / 'manifest.json').read_text())
                    summary.update(dac_off_commanded=bool(manifest.get('dac_off_commanded')),
                                   shutdown_errors=manifest.get('shutdown_errors', []),
                                   frames=manifest.get('frames_captured', 0),
                                   error=manifest.get('experiment_error', ''))
                except (OSError, ValueError):
                    summary['shutdown_errors'] = ['no helper manifest; see board.log in %s' % run]
                summary['helper_exit'] = helper.returncode
            if boot_was_running:
                self.systemctl('start', '--no-block', 'bootpy.service')
            summary['bootpy_restored'] = bool(boot_was_running)
            try:
                (run / 'session.json').write_text(json.dumps(summary, indent=1) + '\n')
            except OSError:
                pass
            print('session ended: ' + json.dumps(summary), flush=True)
        if summary['reason'] == 'helper_failed':
            tail = ''
            try:
                tail = (run / 'board.log').read_text(errors='replace').strip().splitlines()[-1][:300]
            except (OSError, IndexError):
                pass
            send(conn, dict(state='error', code='helper_failed', message='The board could not start the capture: ' + tail,
                            dac_off_commanded=summary['dac_off_commanded']))
        else:
            send(conn, summary)

    def client_event(self, conn, wait):
        """'gone', 'stop' or None after at most `wait` seconds."""
        try:
            ready, _, _ = select.select([conn], [], [], wait)
            if not ready:
                return None
            data = conn.recv(4096)
        except OSError:
            return 'gone'
        if not data:
            return 'gone'
        return 'stop' if b'"stop"' in data else None

    def wait_ready(self, conn, helper, ready, t0):
        last = 0
        while not ready.is_set():
            if helper.poll() is not None:
                return 'helper_failed'
            if self.stopping.is_set():
                return 'service_stopped'
            if time.monotonic() - t0 > self.a.start_timeout:
                return 'helper_failed'
            event = self.client_event(conn, .25)
            if event:
                return 'client_' + event
            if time.monotonic() - last >= 1:
                last = time.monotonic()
                if not send(conn, dict(state='starting', step='loading the FPGA image and synchronising the converters',
                                       elapsed=round(time.monotonic() - t0))):
                    return 'client_gone'
        return None

    def wait_end(self, conn, helper):
        while True:
            if helper.poll() is not None:
                return 'helper_ended'
            if self.stopping.is_set():
                return 'service_stopped'
            event = self.client_event(conn, .25)
            if event:
                return 'client_' + event

    @staticmethod
    def stop_helper(helper):
        """EOF on stdin is the orderly stop: the helper zeroes and disables the DACs."""
        try:
            helper.stdin.close()
        except OSError:
            pass
        for action, wait in ((None, 90), (helper.terminate, 30), (helper.kill, 10)):
            if action is not None:
                action()
            try:
                helper.wait(timeout=wait)
                return
            except subprocess.TimeoutExpired:
                continue

    def prune(self):
        runs = sorted(p for p in (self.state / 'runs').iterdir() if p.is_dir())
        for old in runs[:-KEEP_RUNS]:
            shutil.rmtree(old, ignore_errors=True)


def parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--root', default='/opt/rfsoc4x2-beamformer', help='installed helper files and reference')
    p.add_argument('--state', default='/var/lib/rfsoc4x2-beamformer', help='per-session logs and manifests')
    p.add_argument('--bind', default='0.0.0.0')
    p.add_argument('--port', type=int, default=PORT)
    p.add_argument('--stream-port', type=int, default=4011)
    p.add_argument('--control-port', type=int, default=4012)
    p.add_argument('--python', default=sys.executable)
    p.add_argument('--helper', default='legacy_capture.py')
    p.add_argument('--start-timeout', type=float, default=180)
    # 136.3623 MHz = PS IOPLL 1499.985 MHz / 11: the smallest available PL clock 0 above
    # the 125 MHz RF stream. At the overlay's 124.99875 MHz the capture writer, fed through
    # a clock converter from the RF fabric clock, lost one sample every ~10000 (104 ppm,
    # live); at 136.36 and 150 MHz no sample was lost in 1.97 M / 0.82 M rows.
    p.add_argument('--capture-clock-mhz', type=float, default=136.3623,
                   help='PL clock 0 for every session (0: overlay value); a client may request another')
    p.add_argument('--rf-mhz', type=int, default=DEFAULT_RF_MHZ, choices=sorted(RF_PROFILES),
                   help='start frequency of every session (measured profiles only); a client may request another')
    p.add_argument('--dac-peak', type=int, default=DEFAULT_DAC_PEAK,
                   help='DAC waveform peak code of every session (100..%d); a client may request another' % DAC_PEAK_MAX)
    p.add_argument('--allow-cidr', action='append', default=[], help='extra client network, e.g. 198.51.100.0/24')
    p.add_argument('--board-name', default='', help=argparse.SUPPRESS)
    return p


def main():
    a = parser().parse_args()
    service = Service(a).start()
    print('%s session service on port %d' % (SERVICE, service.port), flush=True)
    stop = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stop.set())
    stop.wait()
    service.close()


if __name__ == '__main__':
    main()
