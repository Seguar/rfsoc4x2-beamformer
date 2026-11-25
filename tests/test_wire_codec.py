"""Board helper wire codec and bounded validation schedules."""
import hashlib
import struct
import unittest
import zlib
import numpy as np
from board.legacy_capture import encode_wire, parse_schedule


class WireCodecTests(unittest.TestCase):
    def test_lossless_wire_reconstruction(self):
        raw = np.random.default_rng(983).integers(-1200, 1201, 4096, dtype='<i2').tobytes()
        payload = encode_wire(raw)
        size, digest = struct.unpack('<I32s', payload[:36])
        planes = np.frombuffer(zlib.decompress(payload[36:], -15), np.uint8)
        recovered = planes.reshape(2, -1).T.tobytes()
        self.assertEqual(size, len(raw))
        self.assertEqual(recovered, raw)
        self.assertEqual(digest, hashlib.sha256(raw).digest())

    def test_validation_schedule_is_bounded(self):
        _, frames = parse_schedule('wave:6,blank:3,pause:5,wave:6')
        self.assertEqual(frames, 15)
        with self.assertRaises(ValueError):
            parse_schedule('wave:31')


if __name__ == '__main__':
    unittest.main()
