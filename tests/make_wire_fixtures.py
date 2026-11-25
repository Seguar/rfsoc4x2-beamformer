"""Write the synthetic wire fixtures of matlab/original/tests/validateLegacyWire.m.

  python3 tests/make_wire_fixtures.py <folder>

wire-raw.bin       random int16 I/Q bytes (one 4096-row, 4-stream window)
wire-valid.bin     the board helper's lossless encoding of wire-raw.bin
wire-oversize.bin  a stream that inflates past the declared length (must be refused)
"""
import hashlib
from pathlib import Path
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from board.legacy_capture import encode_wire  # noqa: E402


def main(folder):
    out = Path(folder)
    out.mkdir(parents=True, exist_ok=True)
    raw = np.random.default_rng(20261125).integers(-1200, 1201, 4096 * 8, dtype='<i2').tobytes()
    (out / 'wire-raw.bin').write_bytes(raw)
    (out / 'wire-valid.bin').write_bytes(encode_wire(raw))
    longer = raw + raw[:4096]
    planes = np.frombuffer(longer, np.uint8).reshape(-1, 2).T.tobytes()
    co = zlib.compressobj(1, zlib.DEFLATED, -15)
    body = co.compress(planes) + co.flush()
    (out / 'wire-oversize.bin').write_bytes(struct.pack('<I32s', len(raw), hashlib.sha256(raw).digest()) + body)
    print('wrote', out)


if __name__ == '__main__':
    main(sys.argv[1])
