"""Legacy TCP boundary. A connection is a continuous stream, not a request/frame."""
import socket
import numpy as np


def decode(payload):
    if len(payload) % 16:
        raise ValueError("Incomplete eight-int16 sample group")
    raw = np.frombuffer(payload, dtype='<i2').reshape(-1, 8).astype(float)
    return raw[:, 0::2]-1j*raw[:, 1::2]


def recv_exact(sock, count):
    out = bytearray()
    while len(out) < count:
        chunk = sock.recv(count-len(out))
        if not chunk:
            raise EOFError(f"Disconnected after {len(out)}/{count} bytes")
        out.extend(chunk)
    return bytes(out)


def capture(host, frames, timeout=10):
    """Acquire existing RF settings, without writing DACs or retuning.

    Closing the stream forces the legacy loop to notice a disconnect. A new
    control connection requests stop and DAC off, but the protocol has no ACK.
    Verify state through board access; this function cannot prove RF-off.
    """
    if frames < 1:
        raise ValueError("frames must be positive")
    try:
        with socket.create_connection((host, 4000), timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(b'dataChan 131072#dataStream 1\n')
            return np.stack([decode(recv_exact(sock, 262144)) for _ in range(frames)])
    finally:
        try:
            with socket.create_connection((host, 4000), timeout) as control:
                control.sendall(b'dataStream 0#dacPow 0/0/0/0#da 0\n')
        except OSError:
            pass  # Caller must report unverified stop, even if sendall succeeds.
