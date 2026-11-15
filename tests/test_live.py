import io
import json
import struct
import unittest
import numpy as np
from rfsoc_demo.live import array_fixture
from rfsoc_demo.dsp import calibrate_fixed, process
from rfsoc_demo.transport import MAGIC, FRAME, receive_session, receive_frame


class ByteSocket:
    def __init__(self, body):
        self.buffer = io.BytesIO(body)
    def recv(self, n):
        return self.buffer.read(min(n, 31))


class LiveTests(unittest.TestCase):
    def test_adc0_direct_mode_ignores_unconnected_channels(self):
        x, _ = array_fixture(0)
        rng = np.random.default_rng(77)
        x[:,1:] = 1000*(rng.standard_normal(x[:,1:].shape)+1j*rng.standard_normal(x[:,1:].shape))
        result, _ = process(x, adc0_only=True)
        self.assertEqual(result['receive_mode'], 'ADC0 only')
        self.assertLess(result['metrics']['adc0']['evm_percent'], 3)
        self.assertAlmostEqual(result['metrics']['adc0']['evm_percent'],
                               result['metrics']['mvdr']['evm_percent'], places=8)

    def test_frozen_broadside_and_moving_transmitter(self):
        fixed = calibrate_fixed(array_fixture(0)[0])
        saved = fixed.copy()
        for index in [14, 62]:  # about +30 and -30 degrees; half-wave four-element array
            x, _ = array_fixture(index)
            r, _ = process(x, fixed_weights=fixed)
            self.assertGreater(r['metrics']['fixed']['evm_percent'], 30)
            self.assertLess(r['metrics']['mvdr']['evm_percent'], 2)
        np.testing.assert_array_equal(fixed, saved)

    def test_same_carrier_modulated_jammer_during_motion(self):
        fixed = calibrate_fixed(array_fixture(0)[0])
        for index in [0, 14, 62, 68]:
            x, _ = array_fixture(index, jammer=True)
            r, _ = process(x, fixed_weights=fixed)
            self.assertLess(r['metrics']['mvdr']['evm_percent'], 3)
            self.assertEqual(r['metrics']['mvdr']['ber'], 0)
            self.assertGreater(r['metrics']['fixed']['evm_percent'], 50)

    def test_versioned_stream_fragmentation_and_bad_marker(self):
        metadata = json.dumps({'format':'int16le-I-minus-jQ-4ch', 'frame_bytes':262144, 'fs_hz':125e6}).encode()
        raw = np.arange(131072, dtype='<i2').tobytes()
        header = MAGIC+struct.pack('<I', len(metadata))+metadata
        sock = ByteSocket(header+FRAME.pack(b'IQF1', 17, 123456, len(raw))+raw)
        self.assertEqual(receive_session(sock)['fs_hz'], 125e6)
        seq, stamp, x = receive_frame(sock)
        self.assertEqual((seq, stamp, x.shape), (17, 123456, (16384,4)))
        self.assertEqual(x[1,2], 12-13j)
        with self.assertRaises(ValueError):
            receive_frame(ByteSocket(FRAME.pack(b'FAIL', 0, 0, len(raw))))
