"""Board-local same-capture window selection (helper v3, --wire-mode window4).

Synthetic captures built from the reviewed loop reference: the received loop is
the 125 MHz reference circularly shifted (arbitrary capture start), with a
distinct complex gain per stream, noise and int16 lanes I,Q. No hardware.
"""
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import time
import unittest
import numpy as np
from board.legacy_capture import (select_window, window_candidates, frame_extension, EXT3, WIN, BLOCK,
                                  WIRE_BYTES3, encode_wire, fast_window, ref_activity, FRAME_LEAD, _FAST)
from tools.legacy_reference import build

SOURCE = Path(os.environ.get('LEGACY_SOURCE', 'C:/work/git/vsa_rfsoc/Signals/dac_ofdm_f_500.mat'))
N = 131072


def capture(ref, kk, gains, rng, noise=8.0, drop_at=None, drop=0, blank=False, slips=0):
    """Rows x 8 int16: stream k = gains[k] * loop shifted so capture row n holds loop index n - kk.
    slips: number of random one-sample advances (the measured ~100 ppm discrete loss)."""
    n = np.arange(N)
    idx = (n - kk) % N
    if drop_at is not None:            # sample loss: rows after drop_at advance by `drop` samples
        idx = np.where(n >= drop_at, (n - kk + drop) % N, idx)
    if slips:
        adv = np.zeros(N, int); adv[np.sort(rng.integers(1, N, slips))] += 1
        idx = (idx + np.cumsum(adv)) % N
    base = np.zeros(N, complex) if blank else ref[idx] * (3000 / np.abs(ref).max())
    rows = np.zeros((N, 8))
    for k, g in enumerate(gains):
        z = g * base + noise * (rng.standard_normal(N) + 1j * rng.standard_normal(N))
        rows[:, 2 * k], rows[:, 2 * k + 1] = z.real, z.imag   # lanes I, Q (I + jQ = loop sense)
    return np.clip(np.round(rows), -32768, 32767).astype('<i2').ravel(), idx


@unittest.skipUnless(SOURCE.is_file(), 'legacy source waveform not available')
class WindowSelectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        npz, _ = build(SOURCE, cls.tmp.name)
        with np.load(npz) as d:
            cls.ref = np.asarray(d['ref125'])
            cls.burst = float(d['burst_complex_500']) / 4
        cls.gains = [1.0, 0.8 * np.exp(1j * 1.1), 0.9 * np.exp(-1j * 2.0), 0.7 * np.exp(1j * 0.4)]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def check_free(self, idx, s):
        w = idx[s:s + WIN]
        # contiguous loop indices: no wrap (and no sample loss) inside the window
        self.assertTrue(np.all(np.diff(w) == 1), 'window contains the loop boundary or a jump')
        self.assertLessEqual(s + WIN, N - BLOCK)

    def test_boundary_free_for_many_shifts(self):
        rng = np.random.default_rng(5)
        times = []
        for kk in list(rng.integers(0, N, 12)) + [0, 1, N - 1, N - BLOCK, 30000, 98304]:
            raw, idx = capture(self.ref, int(kk), self.gains, rng)
            t = time.perf_counter()
            s, info = select_window(raw, self.ref, self.burst)
            times.append(time.perf_counter() - t)
            self.assertNotIn(info['candidate'], ('fallback', 'none'), info)
            self.check_free(idx, s)
            self.assertGreater(min(info['stream_locks']), 0.9, info)
            # the wrap estimate (self-similarity) is within one block of the true wrap
            true_w = int(kk) % N
            if BLOCK < true_w < N - BLOCK:
                self.assertLessEqual(min(abs(info['wrap_row'] - true_w), N - abs(info['wrap_row'] - true_w)), BLOCK, info)
        self.assertLess(max(times), 2.0)

    def test_reduced_window_starts_one_lead_before_a_complete_frame(self):
        """Reduced (display-rate) windows: for any capture alignment the window is one
        contiguous pass and its first complete OFDM frame starts FRAME_LEAD rows in."""
        rng = np.random.default_rng(7)
        act = ref_activity(self.ref)
        for kk in (0, 3, 5000, 40000, 70001, 103000, 131000):
            raw, idx = capture(self.ref, kk, self.gains, rng)
            _FAST.clear()
            for rows in (4096, 8192, 16384):
                with self.subTest(kk=kk, rows=rows):
                    s, info = fast_window(raw, self.ref, self.burst, rows)
                    self.assertEqual(info['candidate'], 'fast')
                    w = idx[s:s + rows]
                    self.assertTrue(np.all(np.diff(w) == 1))
                    a = act[w].astype(int)
                    first = int(np.flatnonzero(np.diff(a) == 1)[0]) + 1
                    self.assertLessEqual(abs(first - FRAME_LEAD), 2, 'frame starts %d rows in' % first)
                    self.assertGreaterEqual(rows - first, 3000, 'first frame incomplete')
                    self.assertGreater(min(info['stream_locks']), 0.9)

    def test_measured_100ppm_slips(self):
        # ~13 one-sample advances per capture decorrelate a full-capture correlation
        # (live lock ~0.13); block alignment must still lock and pick a window whose
        # block lags move by at most the slips inside it
        rng = np.random.default_rng(11)
        for kk in (0, 4000, 70000, 125000):
            raw, idx = capture(self.ref, kk, self.gains, rng, slips=13)
            s, info = select_window(raw, self.ref, self.burst)
            self.assertNotIn(info['candidate'], ('none', 'fallback'), info)
            w = idx[s:s + WIN]
            steps = np.diff(w)              # no modulo: the loop wrap (index N-1 -> 0) must not pass as a step
            self.assertTrue(np.all((steps == 1) | (steps == 2)), 'boundary inside window')
            self.assertLessEqual(int(np.sum(steps == 2)), 8)
            self.assertLessEqual(s + WIN, N - BLOCK)

    def test_start_avoids_host_ambiguous_pre_burst_gap(self):
        # The host refuses a window starting within the truncated-gap length (1543 rows
        # + guard) before a burst start, or <16 rows after it: a wrap there leaves no
        # trace. The board moves such starts (alignment unchanged), keeping the window
        # boundary-free.
        rng = np.random.default_rng(12)
        nudged = 0
        for kk in list(rng.integers(0, N, 24)) + [3000, 30000, 61000]:
            raw, idx = capture(self.ref, int(kk), self.gains, rng)
            s, info = select_window(raw, self.ref, self.burst)
            self.check_free(idx, s)
            ph = float(idx[s]) % self.burst
            self.assertFalse(ph > self.burst - (1543 + 16) or ph < 16, (kk, s, ph, info.get('nudged')))
            nudged += info.get('nudged', 0)
        self.assertGreater(nudged, 0)

    def test_sample_loss_inside_first_candidate_moves_window(self):
        rng = np.random.default_rng(6)
        kk = 20000
        raw0, _ = capture(self.ref, kk, self.gains, rng)
        s0, _ = select_window(raw0, self.ref, self.burst)     # the window chosen without loss
        raw, idx = capture(self.ref, kk, self.gains, rng, drop_at=s0 + 3 * BLOCK + 100, drop=40)
        s, info = select_window(raw, self.ref, self.burst)
        self.assertNotEqual(s, s0, info)
        self.check_free(idx, s)

    def test_blank_capture_is_unlocked_negative_control(self):
        rng = np.random.default_rng(7)
        raw, _ = capture(self.ref, 1234, self.gains, rng, blank=True)
        s, info = select_window(raw, self.ref, self.burst)
        self.assertEqual(s, 0)
        self.assertLess(info['lock_block'], 0.3)
        self.assertEqual(info['candidate'], 'none')

    def test_dead_stream_shows_in_stream_locks(self):
        rng = np.random.default_rng(8)
        gains = list(self.gains); gains[2] = 0
        raw, idx = capture(self.ref, 50000, gains, rng)
        s, info = select_window(raw, self.ref, self.burst)
        self.check_free(idx, s)
        self.assertLess(info['stream_locks'][2], 0.3)
        self.assertGreater(min(info['stream_locks'][:2] + info['stream_locks'][3:]), 0.9)

    def test_extension_and_window_bytes(self):
        rng = np.random.default_rng(9)
        raw, _ = capture(self.ref, 777, self.gains, rng)
        s, info = select_window(raw, self.ref, self.burst)
        full = hashlib.sha256(raw.tobytes()).hexdigest()
        body = np.ascontiguousarray(raw.reshape(-1, 8)[s:s + WIN, :]).tobytes()
        self.assertEqual(len(body), WIRE_BYTES3)
        self.assertEqual(body, raw[s * 8:(s + WIN) * 8].tobytes())   # same capture, contiguous rows
        ext = frame_extension(s, info['select_s'], full, body, info)
        start, us, fsha, wsha, jl = struct.unpack(EXT3, ext[:struct.calcsize(EXT3)])
        self.assertEqual(start, s)
        self.assertEqual(fsha.hex(), full)
        self.assertEqual(wsha, hashlib.sha256(body).digest())
        self.assertEqual(json.loads(ext[struct.calcsize(EXT3):])['start'], s)
        self.assertEqual(len(ext), struct.calcsize(EXT3) + jl)
        payload = encode_wire(body)
        self.assertLess(len(payload), WIRE_BYTES3 + 36 + 8192)

    def test_reduced_window_offset_is_reused_between_checks(self):
        """After one check the frame offset is reused without correlation until the
        next check is due; a level drop (signal gone) forces a check at once."""
        rng = np.random.default_rng(21)
        raw, idx = capture(self.ref, 5000, self.gains, rng)
        state = {}
        s0, i0 = fast_window(raw, self.ref, self.burst, 4096, state=state, now=100.0)
        self.assertEqual(i0['candidate'], 'fast')
        raw2, _ = capture(self.ref, 5000, self.gains, rng)            # next capture, same offset
        s1, i1 = fast_window(raw2, self.ref, self.burst, 4096, state=state, now=100.5)
        self.assertEqual((s1, i1['candidate']), (s0, 'fixed'))
        self.assertEqual(i1['kk'], i0['kk'])
        s2, i2 = fast_window(raw2, self.ref, self.burst, 4096, state=state, now=101.2)
        self.assertEqual(i2['candidate'], 'fast')                     # check due after 1 s
        self.assertEqual(s2, s0)
        blank, _ = capture(self.ref, 5000, self.gains, rng, blank=True)
        _, i3 = fast_window(blank, self.ref, self.burst, 4096, state=state, now=101.3)
        self.assertNotEqual(i3['candidate'], 'fixed')                 # level drop: checked, unlocked
        self.assertNotIn('fixed', state)
        _, i4 = fast_window(raw2, self.ref, self.burst, 8192, state=state, now=101.4)
        self.assertEqual(i4['candidate'], 'fast')                     # no reuse after unlock
        _, i5 = fast_window(raw2, self.ref, self.burst, 4096, state=state, now=101.5)
        self.assertEqual(i5['candidate'], 'fast')                     # other row count: checked

    def test_reused_offset_reads_fewer_rows(self):
        from board.legacy_capture import read_rows_needed, WRAP_GUARD, BLOCK
        rng = np.random.default_rng(22)
        raw, _ = capture(self.ref, 5000, self.gains, rng)
        state = {}
        full = read_rows_needed(4096, self.burst, state, now=0.0)
        s, _ = fast_window(raw, self.ref, self.burst, 4096, state=state, now=0.0)
        short = read_rows_needed(4096, self.burst, state, now=0.5)
        self.assertEqual(short, max(s + 4096, WRAP_GUARD + BLOCK) + 256)
        self.assertLess(short, full)
        self.assertEqual(read_rows_needed(4096, self.burst, state, now=1.5), full)    # check due


class WindowMetadataTests(unittest.TestCase):
    def test_truncated_summary_retains_control_revision_and_fails_closed(self):
        body = bytes(WIN * 16)
        info = {'note': 'x'*3000, 'control_revision': 12, 'candidate': 'after-wrap'}
        ext = frame_extension(0, .1, '00'*32, body, info)
        summary = json.loads(ext[struct.calcsize(EXT3):])
        self.assertEqual(summary['control_revision'], 12)
        self.assertEqual(summary['candidate'], 'fallback')


if __name__ == '__main__':
    unittest.main()
