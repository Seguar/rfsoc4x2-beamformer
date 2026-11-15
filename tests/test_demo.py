import socket
import unittest
import numpy as np
from rfsoc_demo.dsp import reference, dac_words, process, simulate, acquire, FS
from rfsoc_demo.transport import decode, recv_exact


class DemoTests(unittest.TestCase):
    def test_distinct_path_and_tracking(self):
        for cfo, delay in [(42000, 793), (-83000, 4001), (120000, 21)]:
            result, _ = process(simulate(cfo=cfo, delay=delay))
            self.assertEqual(result['tracking']['delay_samples'], delay)
            self.assertLess(abs(result['tracking']['cfo_hz']-cfo), 200)
            self.assertLess(result['metrics']['mvdr']['evm_percent'], 3)
            self.assertEqual(result['metrics']['mvdr']['ber'], 0)
            self.assertGreater(result['metrics']['adc0']['evm_percent'], 20)

    def test_shared_path_cannot_be_spatially_rejected(self):
        # Collinear steering vectors: preserving desired also preserves jammer.
        a = np.array([1, 1j, -1, -1j])
        from rfsoc_demo.dsp import weights, TRAIN, NFFT, CP
        wave, _ = reference()
        n = TRAIN*(NFFT+CP)
        jammer = 3*np.exp(2j*np.pi*.093*np.arange(n))
        w, _, _, _ = weights((wave[:n]+jammer)[:,None]*a, wave[:n])
        wanted = wave[:n, None]*a @ w.conj()
        unwanted = jammer[:, None]*a @ w.conj()
        self.assertGreater(abs(np.vdot(w, a)), .5)
        self.assertAlmostEqual(np.linalg.norm(wanted)/np.linalg.norm(wave[:n]),
                               np.linalg.norm(unwanted)/np.linalg.norm(jammer), places=8)

    def test_conjugate_and_zero_input(self):
        result, _ = process(simulate().conj())
        self.assertTrue(result['tracking']['conjugated'])
        self.assertLess(result['metrics']['mvdr']['evm_percent'], 3)
        with self.assertRaises(ValueError):
            acquire(np.zeros((8192,4)), reference()[0])

    def test_reference_rate_and_capacity(self):
        from scipy.signal import resample
        wave, _ = reference()
        words = dac_words(wave)
        self.assertEqual(words.shape, (65536,))
        tx = words[::2].astype(float)+1j*words[1::2]
        np.testing.assert_array_equal(words[:32768], words[32768:])
        down = resample(tx[:16384], 4096)
        gain = np.vdot(wave, down)/np.vdot(wave,wave)
        self.assertLess(np.linalg.norm(down/gain-wave)/np.linalg.norm(wave), .002)

    def test_wire_format_and_fragmentation(self):
        raw = np.arange(32, dtype='<i2')
        x = decode(raw.tobytes())
        self.assertEqual(x.shape, (4,4))
        self.assertEqual(x[1,2], 12-13j)
        class Fragmented:
            def __init__(self): self.data = bytearray(b'abcdef')
            def recv(self, n):
                block = bytes(self.data[:min(2,n)])
                del self.data[:len(block)]
                return block
        sock = Fragmented()
        self.assertEqual(recv_exact(sock, 6), b'abcdef')
        with self.assertRaises(EOFError): recv_exact(sock, 1)
        with self.assertRaises(ValueError): decode(b'abc')


if __name__ == '__main__':
    unittest.main()
