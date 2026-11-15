"""Host-side checks for native-VSA launch ownership and lossless wire framing."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import struct
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zlib
import numpy as np
from board.legacy_capture import encode_wire, parse_schedule
from tools.run_original_vsa import preflight_code


class OriginalLauncherTests(unittest.TestCase):
    def test_lossless_wire_reconstruction(self):
        raw = np.random.default_rng(983).integers(-1200, 1201, 4096, dtype='<i2').tobytes()
        payload = encode_wire(raw)
        size, digest = struct.unpack('<I32s', payload[:36])
        planes = np.frombuffer(zlib.decompress(payload[36:], -15), np.uint8)
        recovered = planes.reshape(2, -1).T.tobytes()
        self.assertEqual(size, len(raw))
        self.assertEqual(recovered, raw)
        self.assertEqual(digest, hashlib.sha256(raw).digest())

    def test_preflight_distinguishes_actual_owner_from_stale_sudo(self):
        rows = '\n'.join([
            '11648 1 T sudo -S /venv/python3 /old/board_capture.py',
            '11649 11648 Z [python3] <defunct>',
            '17 1 Sl /venv/python3 /new/legacy_capture.py',
            '18 1 Sl /venv/python3 -m ipykernel_launcher -f kernel.json',
            '19 1 T /venv/python3 /old/board_capture.py',
            '20 1 S python3 -c "print(\'board_capture.py\')"',
        ])
        def result(args, **kwargs):
            return SimpleNamespace(stdout='failed\n' if args[0]=='systemctl' else 'State Recv-Q Send-Q Local Address:Port Peer\n')
        output = io.StringIO()
        with patch('subprocess.check_output', return_value=rows), patch('subprocess.run', side_effect=result), \
                patch.object(Path, 'read_bytes', return_value=b'RFSoC4x2\0'), contextlib.redirect_stdout(output):
            exec(preflight_code(4011), {})
        value = json.loads(output.getvalue())
        self.assertEqual([line.split()[0] for line in value['busy']], ['17','18','19'])
        self.assertFalse(value['listening'])

    def test_validation_schedule_is_bounded(self):
        _, frames = parse_schedule('wave:6,blank:3,pause:5,wave:6')
        self.assertEqual(frames, 15)
        with self.assertRaises(ValueError):
            parse_schedule('wave:31')


if __name__ == '__main__':
    unittest.main()
