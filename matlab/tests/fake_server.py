"""Four localhost sessions for validateTransport.m; never connects to RF hardware."""
import argparse
import json
from pathlib import Path
import socket
import struct
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port-file', required=True)
    args = parser.parse_args()
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        server.settimeout(60)
        Path(args.port_file).write_text(str(server.getsockname()[1]))
        for case in range(4):
            client, _ = server.accept()
            with client:
                client.settimeout(5)
                metadata = json.dumps(dict(format='int16le-I-minus-jQ-4ch',
                    frame_bytes=512, fs_hz=61440000, waveform_version=2)).encode()
                data = b'R4X2IQ1\n'+struct.pack('<I', len(metadata))+metadata
                sequences = [1, 2, 2] if case == 0 else [1]
                for sequence in sequences:
                    marker = b'BAD!' if case == 1 else b'IQF1'
                    count = 513 if case == 2 else 512
                    data += marker+struct.pack('<QQI', sequence, 123, count)
                    data += struct.pack('<256h', *range(256))
                if case == 3:
                    data = data[:-300]
                try:
                    for offset in range(0, len(data), 7):
                        client.sendall(data[offset:offset+7])
                        time.sleep(.001)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # Client deliberately rejects bad framing and closes.


if __name__ == '__main__':
    main()
