"""SIMULATED localhost frames for validateGui.m; never accesses board hardware."""
import argparse
import json
from pathlib import Path
import socket
import struct
import time
import numpy as np
from scipy.io import loadmat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True)
    parser.add_argument('--directory', required=True, help='Fresh handshake/output directory')
    parser.add_argument('--angle-deg', type=float, help='SIMULATED half-wave ULA wanted angle')
    args = parser.parse_args()
    directory = Path(args.directory)
    directory.mkdir(parents=True, exist_ok=True)
    if any((directory/name).exists() for name in ('advance1', 'advance2', 'closed')):
        parser.error('Use a fresh handshake directory')
    # Repetition is solely a synthetic acquisition fixture, never captured IQ.
    wave = np.tile(loadmat(args.reference)['wave'].ravel(), 4)
    rng = np.random.default_rng(9015)

    manifold = np.ones(4) if args.angle_deg is None else np.exp(-1j*np.pi*np.arange(4)*np.sin(np.deg2rad(args.angle_deg)))

    def payload(values):
        lanes = np.empty((len(values), 8), dtype='<i2')
        lanes[:, 0::2] = np.round((values[:, None]*manifold).real*4000)
        lanes[:, 1::2] = np.round(-(values[:, None]*manifold).imag*4000)
        return lanes.tobytes()

    with socket.socket() as server:
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        server.settimeout(120)
        (directory/'port.txt').write_text(str(server.getsockname()[1]))
        client, _ = server.accept()
        with client:
            client.settimeout(10)
            meta = json.dumps(dict(format='int16le-I-minus-jQ-4ch',
                frame_bytes=len(wave)*16, fs_hz=125000000, waveform_version=2)).encode()
            client.sendall(b'R4X2IQ1\n'+struct.pack('<I', len(meta))+meta)
            noise = rng.normal(0, .15, len(wave))+1j*rng.normal(0, .15, len(wave))
            for sequence, values in ((1, wave), (2, noise)):
                client.sendall(b'IQF1'+struct.pack('<QQI', sequence, 0, len(wave)*16)+payload(values))
                deadline = time.monotonic()+30
                while not (directory/('advance'+str(sequence))).exists():
                    if time.monotonic() > deadline:
                        raise TimeoutError('MATLAB handshake deadline expired')
                    time.sleep(.05)
            # No next frame: validateGui must show unavailable, then close.
            closed = client.recv(1) == b''
            (directory/'closed').write_text('1' if closed else '0')
            if not closed:
                raise RuntimeError('Expected client EOF')
            print('SIMULATED_GUI_CLOSE_EOF_PASS')


if __name__ == '__main__':
    main()
