"""Partial capture-RAM read for reduced windows (board/legacy_capture.full_capture)."""
import unittest
import numpy as np
from board import legacy_capture as lc


class FakeOverlay:
    """Capture RAM as a numpy array; a trigger writes new noise; reads are counted."""
    def __init__(self):
        self.da = 0
        self.ram = np.zeros(lc.RAM, '<i2')
        self.rng = np.random.default_rng(5)
        self.read_words = 0
        parent = self

        class Ram:
            def __getitem__(self, k):
                part = parent.ram[k]
                parent.read_words += part.size
                return part

            def __setitem__(self, k, v):
                parent.ram[k] = v
        self.adc_capture = Ram()

    def trigger_capture(self):
        self.ram[:] = self.rng.integers(-2000, 2000, lc.RAM, dtype='<i2')


class PartialReadTests(unittest.TestCase):
    def setUp(self):
        self._settle, lc.SETTLE = lc.SETTLE, 0

    def tearDown(self):
        lc.SETTLE = self._settle

    def test_rows_needed_cover_guard_burst_and_window(self):
        burst = 27506.25
        self.assertEqual(lc.read_rows_needed(4096, burst), lc.WRAP_GUARD + 27507 + lc.FRAME_LEAD + 4096 + 256)
        self.assertLess(lc.read_rows_needed(16384, burst), lc.RAM // 8)
        self.assertEqual(lc.read_rows_needed(10**6, burst), lc.RAM // 8)

    def test_partial_read_reads_a_third_and_keeps_freshness(self):
        o = FakeOverlay()
        rows = lc.read_rows_needed(4096, 27506.25)
        raw, refreshed, writable, sha = lc.full_capture(o, None, rows)
        self.assertTrue(refreshed and writable)
        self.assertTrue(np.array_equal(raw[:rows * 8], o.ram[:rows * 8]))
        self.assertTrue(np.array_equal(raw[-8:], o.ram[-8:]))
        self.assertFalse(raw[rows * 8:-8].any())              # not read
        self.assertLess(o.read_words, lc.RAM * 0.4)
        # same RAM again (no new data): refused as not refreshed
        o.trigger_capture = lambda: None
        self.assertFalse(lc.full_capture(o, sha, rows)[1])

    def test_kept_sentinel_is_not_fresh(self):
        o = FakeOverlay()
        o.trigger_capture = lambda: o.ram.__setitem__(slice(0, lc.RAM - 8), 7)   # tail never written
        self.assertFalse(lc.full_capture(o, None, 1000)[1])

    def test_read_rest_completes_the_same_capture(self):
        o = FakeOverlay()
        raw, *_ = lc.full_capture(o, None, 1000)
        lc.read_rest(o, raw, 1000)
        self.assertTrue(np.array_equal(raw, o.ram))

    def test_full_read_unchanged(self):
        o = FakeOverlay()
        raw, refreshed, _, _ = lc.full_capture(o, None)
        self.assertTrue(refreshed and np.array_equal(raw, o.ram))


if __name__ == '__main__':
    unittest.main()
