"""Refactored legacy boot.py stream loop; hardware is injected by its sole owner.

No PYNQ import, overlay programming, clock setup or waveform loading on import.
The wire format remains CR/LF commands and little-endian raw int16 frames.
"""
import select
import socket
import numpy as np


def commands(line):
    """Validate a whole batch before any hardware mutation."""
    parsed = []
    lengths = {'fc': 6, 'cal': 1, 'phase': 4, 'dphase': 4,
               'dataChan': 1, 'dataStream': 1, 'da': 1, 'dacPow': 4}
    for item in line.decode('ascii').strip().split('#'):
        name, values = item.split()
        values = [int(value) for value in values.split('/')]
        if name not in lengths or len(values) != lengths[name]:
            raise ValueError('Unsupported command or argument count: '+name)
        if name == 'dataChan' and (values[0] % 8 or not 8 <= values[0] <= 1048576):
            raise ValueError('dataChan must be a bounded eight-lane word count')
        if name == 'dataStream' and values[0] not in (0, 1):
            raise ValueError('dataStream must be zero or one')
        if name == 'dacPow' and any(v not in (0, 1) for v in values):
            raise ValueError('dacPow values must be zero or one')
        if name == 'da' and values[0] not in (0, 1, 2):
            raise ValueError('da must be zero, one or two')
        parsed.append(name+' '+'/'.join(map(str, values)))
    return parsed


def serve_client(client, overlay, *, should_stop=lambda: False):
    """Check control input between captures, rather than trapping in a stream loop.

    Stop takes effect at a frame boundary. Already queued bytes remain queued.
    Backpressure has a bounded socket timeout, including a non-reading client.
    Caller MUST provide hardware cleanup in a finally block around this call.
    """
    pending = bytearray()
    client.settimeout(1)
    while not should_stop():
        ready, _, _ = select.select([client], [], [], 0 if overlay.dataStream else .1)
        if ready:
            incoming = client.recv(65536)
            if not incoming:
                return
            pending.extend(incoming)
            if len(pending) > 65536:
                raise ValueError('Oversized command line; waveform upload is separate')
            while b'\n' in pending or b'\r' in pending:
                end = min(i for i, b in enumerate(pending) if b in (10, 13))
                line = bytes(pending[:end])
                del pending[:end+1]
                if line.strip():
                    overlay.handle_commands(commands(line))
        if overlay.dataStream:
            count = overlay.data_size
            data = np.asarray(overlay.get_custom_data(count), dtype='<i2').reshape(-1)
            if data.size != count:
                raise ValueError('Capture size does not match command')
            client.sendall(data.tobytes())


def serve(overlay, shutdown, *, bind_host, port=4000, should_stop=lambda: False):
    """Explicit backend + shutdown callback replace boot.py's implicit globals.

    shutdown must stop capture, clear BOTH complete DAC RAMs, and disable both
    DACs. GPIO off alone is insufficient for the matched trigger-OR design.
    This module never loads the old waveform into both DACs automatically.
    """
    with socket.socket() as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((bind_host, port))
        server.listen(1)
        server.settimeout(.2)
        try:
            while not should_stop():
                try:
                    client, _ = server.accept()
                except socket.timeout:
                    continue
                try:
                    with client:
                        serve_client(client, overlay, should_stop=should_stop)
                except (OSError, ValueError) as error:
                    print(type(error).__name__+': '+str(error), flush=True)
                finally:
                    overlay.dataStream = 0
                    shutdown()
        finally:
            overlay.dataStream = 0
            shutdown()
