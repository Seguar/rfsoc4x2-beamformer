#!/usr/bin/env python3
"""Owned legacy-wave capture helper v2 (derived from reviewed board_capture.py
sha 41d2d619...). Run only with exclusive control.

Kept from board_capture.py / helper v1: board identity, wrapper hash record, runtime
rate/IMR/mode3 checks, clock-lock readbacks (init, after sync, every frame), inactive
DAC full-RAM zero with readback, shutdown that zeroes both DAC RAMs (readback) and
then turns both enables off, full DAC RAM written explicitly (1048576 words, peak
<= 1200, explicit truncation of the 1100250-word legacy file), full ADC RAM capture
(1048576 words = 131072 contiguous complex per stream) with sentinel + hash
freshness, request/response (one byte b'N' per wanted frame; capture only after
the request), bounded schedule <= 30 frames (wave:k, blank:k, pause:s <= 10 s).

v2 transport:
  * the wire carries ONLY the measured stream: stream0 = ADC_D, lanes 0:1 of every
    row of the full-RAM capture, i.e. all 131072 contiguous complex samples of that
    stream (524288 bytes). The full 4-stream RAM is still captured and checked.
    Metadata states the wire channels, format, byte size and availableChannels mask.
  * frame header IQL2 also carries the board-monotonic time at which the request
    byte was received, so the host can anchor acquisition time on its own clock
    (host request-send time + board delay request->capture): conservative, no
    board/host clock offset or drift.
  * owner binding: --owner-stdin (required) stops the helper when its stdin reaches
    EOF (owning launcher / plink session gone). All waits poll this every <= 0.25 s.
  * continuous mode exists ONLY with --continuous plus explicit --max-seconds
    (<= 14400) and --max-frames, and still needs --owner-stdin. There is no
    default unbounded run.
v3 transport (--wire-mode window4, magic R4X2IQ3, frames IQZ3/IQL3):
  * ALL FOUR measured streams, as one contiguous 32768-row window of the SAME
    full-RAM capture (8 lanes = 4 x I,Q per row, 524288 bytes: the v2 byte size).
    No resampling, tiling, joining of captures or sample modification.
  * the window is selected on the board so it does not contain the legacy DAC
    loop boundary. The loop is burst-periodic (bursts correlate ~0.98), so a
    reference correlation cannot locate the wrap (live gate: 4/22 windows
    crossed it); the wrap is found reference-free as the burst after which
    rows no longer repeat the rows one burst earlier (self-similarity), and the
    window keeps 12288 rows clear of it and of the capture's last 8192 rows.
    Its 4096-row sub-blocks must lock to the staged ref125 (wanted signal) with
    lag steps <= 4 and spread <= 16: the ~100 ppm one-sample slips are kept,
    larger loss is refused. A blank/noise capture is flagged unlocked.
    Selection never looks at EVM. Unlocked frames (blank/noise) get start 0.
  * each frame carries the window start row, the SHA256 of the full capture and
    of the selected raw window bytes, the board selection time and a bounded
    JSON summary (per-stream lock, alignment, block lags, candidate note).
Never replaces boot files, never manages services/network/clocks beyond the wrapper
constructor (same as the reviewed helper), never touches the MXG.
"""
import argparse, hashlib, json, os, signal, socket, struct, sys, threading, time, zlib
from pathlib import Path
import numpy as np
if __package__:
    from .mts_sync import enable as enable_mts, trigger as synced_trigger
else:
    from mts_sync import enable as enable_mts, trigger as synced_trigger

PROFILE = 'legacy-ofdm64-truncated-v1'
# Measured RF profiles (MHz -> ADC / DAC Nyquist zone; ADC 5 GS/s, DAC 10 GS/s with
# the wrapper's IMR datapath). 3000: the original validated profile. 5200: ADC odd
# zone (5.0-7.5 GHz) with a positive mixer frequency ((-5200, even) is equivalent).
# At 5200 the DAC's image at 10 GS/s - 5200 = 4800 MHz folds at the 5 GS/s ADC onto
# the wanted band with the same orientation and nearly equal amplitude, so the two add
# coherently. NRZ (zone 1) and mix mode (zone 2) give the image opposite signs, and
# which of them adds constructively changes from session to session (converter clock
# start-up; not the MTS latency): 3 of 4 streams were 10-18 dB weaker in the wrong one.
# select_dac_zone measures both once per session (bench 2026-11-17, 13 sessions).
RF_PROFILES = {3000: dict(adc_zone=2, dac_zone=1), 5200: dict(adc_zone=1, dac_zone=2)}
SELECT_DAC_ZONE = {5200}
DEFAULT_RF_MHZ = 5200
ZONE_MARGIN_DB = 3.0
# DAC waveform peak (int16 code per I/Q rail). The reviewed reference is stored at 1200;
# --dac-peak rescales it on the board. Over the air (2026-11-19, 0.5 m, AKF-1252 filter)
# 1200 left every stream near the noise floor. Before any frame, a start-up capture must
# show the ADC peak below ADC_PEAK_LIMIT_DBFS, else the session is refused.
REFERENCE_PEAK = 1200
DAC_PEAK_MAX = 24000
ADC_PEAK_LIMIT_DBFS = -6.0
SRC_SHA = '3f17e6cccef941d1bac4fefff4439472d8a6e6923b0ef7633e6184448be9eef3'
RAM = 1048576
SENTINEL = np.array([32767, -32768, 32767, -32768, 32767, -32768, 32767, -32768], dtype='<i2')
SETTLE = 0.005  # full RAM = 1.049 ms at 125 MHz
WIRE_FORMAT = 'int16le-IQ-1ch-fullram-v2'   # per sample: I, Q of the single wire stream
FRAME_HDR = '<4sQQQq8sII'                    # magic seq capture_mono req_rx_mono realtime label mask nbytes
MASK = 0b0001                                # bit k set = stream k measured; stream0 = ADC_D
WIRE_BYTES = (RAM // 8) * 2 * 2
MAX_CONTINUOUS_S = 14400
CODEC = 'byteplane-shuffle+deflate-raw-lossless'   # IQZ2 body = <I raw_len><32s sha256(raw wire)> + deflate
PAD_BYTES = 262144                                  # PAD2 link warm-up filler (zeros, not ADC data)
PAD_LIMIT = 3
# v3 window4
WIN = 32768                                          # rows (complex samples per stream) in the window
WIRE_FORMAT3 = 'int16le-IQ-4ch-window-v3'            # per row: I0,Q0,I1,Q1,I2,Q2,I3,Q3
WIRE_BYTES3 = WIN * 8 * 2
MASK3 = 0b1111
EXT3 = '<II32s32sH'                                  # start_row select_us sha(full) sha(window) json_len
EXT3_JSON_MAX = 1024
BLOCK = 8192
SUB = 4096                                           # window check sub-block
WRAP_GUARD = 12288                                   # rows kept clear of the wrap estimate (block resolution)
LOCK_MIN = 0.3
# Host window-integrity edge rules (matlab origapp.windowIntegrity), mirrored with margins so
# the board does not hand the host a window it must refuse for lack of evidence:
HOST_TRUNC_GAP, HOST_GUARD, HOST_MINRUN = 1543, 16, 64
EDGE_MARGIN = 48
NUDGES = [0] + [d * m for m in range(1, 17) for d in (128, -128)]   # start shifts tried, <= 2048 rows
# Reduced windows (display rate): fewer rows of the same capture, sent raw, with a
# cheap selection (see fast_window). 4096 rows hold one complete OFDM frame.
ROWS_ALLOWED = (4096, 8192, 16384, WIN)
FRAME_LEAD = 256                                     # rows sent before the frame start


def _corr_fft():
    try:
        import scipy.fft as sf
        return (lambda x, n=None: sf.fft(x, n, workers=-1)), (lambda x, n=None: sf.ifft(x, n, workers=-1))
    except Exception:
        return np.fft.fft, np.fft.ifft


def self_similarity(z, burst, block=BLOCK, slip=6):
    """Normalised correlation of each block with the rows one burst earlier (sm)
    and one burst later (sp), best over +-slip lags. The legacy loop repeats
    with the burst period except at the loop wrap (truncated last burst), so
    sm is low for the burst after the wrap and sp for the burst before it.
    NaN where the shifted block falls outside the capture."""
    n = len(z); bi = int(round(burst)); nb = n // block
    sm = np.full(nb, np.nan); sp = np.full(nb, np.nan)
    prev = {-1: None, 1: None}                  # tracked lag per side (slips move it slowly)
    for j in range(nb):
        a = z[j * block:(j + 1) * block]
        na = np.sqrt(np.vdot(a, a).real) + 1e-30
        for sign, out in ((-1, sm), (1, sp)):
            s0 = j * block + sign * bi
            if s0 - slip < 0 or s0 + block + slip > n:
                continue
            lags = range(-slip, slip + 1) if prev[sign] is None else                 range(max(-slip, prev[sign] - 1), min(slip, prev[sign] + 1) + 1)
            best, bd = 0.0, 0
            for d in lags:
                b = z[s0 + d:s0 + d + block]
                v = abs(np.vdot(b, a)) / (na * np.sqrt(np.vdot(b, b).real) + 1e-30)
                if v > best:
                    best, bd = v, d
            out[j] = best
            prev[sign] = bd if best > 0.6 else None   # re-search fully after a low block
    return sm, sp


def find_wrap(sm, sp, burst, block=BLOCK, rel=0.85):
    """Wrap row estimate from the self-similarity profiles (None if not seen):
    first block of the low sm run, or the end of the low sp run. 'Low' is
    relative to the median repeat similarity (a block only partly after the
    wrap is partly low)."""
    v = np.concatenate([sm[~np.isnan(sm)], sp[~np.isnan(sp)]])
    low = rel * float(np.median(v)) if len(v) else 0.5
    lm = np.where(np.isnan(sm), False, sm < low)
    lp = np.where(np.isnan(sp), False, sp < low)
    if lm.any():
        j = int(np.flatnonzero(lm)[0])
        if j > 0 and not np.isnan(sm[j - 1]):
            return j * block, 'sm'                 # wrap inside block j-1 .. j
        # low from the first defined block: the wrap is earlier, use sp if possible
    if lp.any():
        j = int(np.flatnonzero(lp)[-1])
        return (j + 1) * block, 'sp'
    if lm.any():
        return int(np.flatnonzero(lm)[0]) * block, 'sm-edge'
    return None, 'none'


def window_candidates(w, n_loop, n=WIN, guard=WRAP_GUARD, block=BLOCK):
    """Start rows of windows that end before the capture's last block and stay
    `guard` rows clear of the wrap estimate w on both sides; the run right after
    the wrap first, then the run before it."""
    usable = n_loop - block
    if w is None:
        # not seen by the self-similarity: the wrap is at the very start (or in the
        # excluded last block), so keep the guard after row 0
        return [('nowrap', guard + k * SUB) for k in range(3) if guard + k * SUB + n <= usable]
    out = []
    for k in range(3):                          # a few starts per side (a loss jump may hit one)
        a = w + guard + k * SUB
        if a + n <= usable:
            out.append(('after-wrap', int(a)))
        b = w - guard - n - k * SUB
        if b >= 0:
            out.append(('before-wrap', int(b)))
    if w + guard < 0 or w - guard > usable:     # wrap outside the usable rows
        out.append(('clear', 0))
    return out


def ref_activity(ref, gap=256):
    """Frame-level activity of the loop reference (same model as the host's
    windowActivityModel): silent only inside a smoothed-quiet run >= gap rows."""
    p = np.abs(np.asarray(ref, complex)) ** 2
    n = len(p)
    sm = np.convolve(np.concatenate([p[-16:], p, p[:15]]), np.ones(32) / 32, 'valid')[:n]
    quiet = sm < 0.01 * np.mean(p[p > 0.1 * p.max()])
    act = np.ones(n, bool)
    d = np.diff(np.concatenate([[0], quiet.astype(np.int8), [0]]))
    for a, b in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)):
        if b - a >= gap:
            act[a:b] = False
    return act


def host_edges_ok(ph, n, burst, act, tail):
    """True if a window starting at burst phase ph passes the host's edge rules
    with EDGE_MARGIN rows to spare (start not in the pre-burst gap that could hide
    a wrap, end not at the truncation phase, no short active run at either edge)."""
    m = EDGE_MARGIN
    ps = ph % burst
    pe = (ph + n - 1) % burst
    if ps > burst - (HOST_TRUNC_GAP + HOST_GUARD + m) or ps < HOST_GUARD + m:
        return False
    if tail - HOST_GUARD - m <= pe < tail + HOST_GUARD + m:
        return False
    i0, i1 = int(ps), int(pe) + int(burst)          # index both edges inside full bursts
    if act[i0] and act[i0:i0 + HOST_MINRUN + m].sum() < HOST_MINRUN + m:
        return False
    if act[i1] and act[i1 - HOST_MINRUN - m + 1:i1 + 1].sum() < HOST_MINRUN + m:
        return False
    return True


def block_lags(z, start, kk, ref, n_loop, n=WIN, block=BLOCK, search=32, hint=None, track=False):
    """Per-block normalised correlation with the loop reference around the
    alignment kk (loop index of row r = r - kk); returns (locks, lags). Without
    hint: +-4 around the tracked lag, FFT +-search to (re)acquire; with hint
    (lags of another stream of the same rows): hint-1..hint+1 only."""
    fft, ifft = _corr_fft()
    locks, lags = [], []
    m = 1 << int(np.ceil(np.log2(block + 2 * search)))
    pad = block + 2 * abs(search) + 2 * 64 + 64
    ext = ref if len(ref) >= n_loop + pad else np.concatenate([ref[:n_loop], ref[:pad]])   # circular, sliceable
    sl = lambda a, length: ext[a % n_loop:a % n_loop + length]
    centre = 0
    def near(seg, e, d):
        c = np.array([abs(np.vdot(sl(e + int(x), block), seg)) for x in d])
        i = int(np.argmax(c))
        r = sl(e + int(d[i]), block)
        return float(c[i] / (np.sqrt(np.vdot(r, r).real * np.vdot(seg, seg).real) + 1e-30)), int(d[i])
    for j in range(n // block):
        r0 = start + j * block
        seg = z[r0:r0 + block]
        e = (r0 - kk) % n_loop
        if hint is not None:
            lk, lg = near(seg, e, np.arange(hint[j] - 1, hint[j] + 2))
        else:
            lk, lg = (near(seg, e, np.arange(centre - 4, centre + 5)) if track and j else (0.0, 0))
            if lk < LOCK_MIN:
                d = np.arange(centre - search, centre + search + 1)
                c = np.abs(ifft(fft(sl(e + centre - search, block + 2 * search), m) * np.conj(fft(seg, m)))[:2 * search + 1])
                lk, lg = near(seg, e, [int(d[int(np.argmax(c))])])
        locks.append(lk); lags.append(lg)
        if track and lk >= LOCK_MIN:
            centre = lg
    return locks, lags


_ACT = {}                                          # activity model cache per reference array


def select_window(raw, ref, burst, ref_fft_conj=None, n=WIN):
    """Board-local window selection on ONE full-RAM capture (raw: 8*N int16).
    Returns (start_row, info). Never resamples or modifies samples; never uses EVM.

    The legacy loop is burst-periodic (bursts correlate ~0.98 with each other),
    so a reference correlation cannot tell which burst a block is; the loop
    wrap (truncated last burst -> first burst) is the only discontinuity.
    1. strongest stream; wanted-signal check by reference correlation of an
       8192-row block (lock >= 0.3, else unlocked negative control).
    2. wrap: self-similarity one burst apart (reference-free); rows after the
       wrap do not repeat the rows one burst earlier.
    3. window: 32768 rows clear of the wrap by WRAP_GUARD and before the last
       block; its 4096-row sub-blocks must lock to the reference (alignment from
       the window's first block, burst chosen so the window does not cross the
       reference's own end) with lag steps <= 4 and spread <= 16 (slips only)."""
    fft, ifft = _corr_fft()
    t0 = time.perf_counter()
    rows = raw.reshape(-1, 8)
    n_loop = rows.shape[0]
    assert len(ref) == n_loop
    stream = lambda k: (rows[:, 2*k].astype(np.float32) + 1j * rows[:, 2*k+1].astype(np.float32)).astype(np.complex64)
    rms = [float(np.sqrt(np.mean(rows[::4, 2*k:2*k+2].astype(np.float32) ** 2) * 2)) for k in range(4)]
    ch = int(np.argmax(rms))
    z = stream(ch)                                                  # I + jQ, the reference sense
    if ref_fft_conj is None:
        ref_fft_conj = np.conj(fft(ref.astype(np.complex64)))
    refc = ref.astype(np.complex64)
    refc = np.concatenate([refc, refc[:BLOCK + 256]])               # circular extension for slicing

    def coarse(r0):
        x = np.zeros(n_loop, np.complex64)
        x[r0:r0 + BLOCK] = z[r0:r0 + BLOCK]
        c = np.abs(ifft(fft(x) * ref_fft_conj))
        k = int(np.argmax(c))
        rr = refc[(np.arange(r0, r0 + BLOCK) - k) % n_loop]
        return k, float(c[k] / (np.linalg.norm(z[r0:r0 + BLOCK]) * np.linalg.norm(rr) + 1e-30))

    kk, lock = coarse(0)
    if lock < LOCK_MIN:
        kk, lock = coarse(BLOCK)
    info = {'det_stream': ch, 'rms_sub4': [round(v, 2) for v in rms], 'lock_block': round(lock, 4)}
    if lock < LOCK_MIN:
        info.update(note='unlocked: start 0, boundary unknown (negative control)', start=0, candidate='none')
        info['select_s'] = time.perf_counter() - t0
        return 0, info
    sm, sp = self_similarity(z, burst)
    w, how = find_wrap(sm, sp, burst)
    info.update(wrap_row=w, wrap_from=how, self_sim_prev=[None if np.isnan(v) else round(float(v), 2) for v in sm],
                self_sim_next=[None if np.isnan(v) else round(float(v), 2) for v in sp])
    tried = []
    tail = n_loop - 4 * burst                         # truncated-burst length: phase change at the wrap
    key = hashlib.sha256(np.ascontiguousarray(ref).tobytes()).hexdigest()
    act = _ACT.get(key)
    if act is None:
        act = _ACT[key] = ref_activity(ref)
    def align(s):
        # the window's first block matches the loop at kk + m*burst (bursts alike)
        # in the pass of block 0, or shifted by the wrap phase in the other pass
        # scored on the window's first and last 4096 rows (exact burst ~0.98,
        # an alike burst ~0.85); each part searches its own lag (slips)
        parts = (s, s + n - SUB)
        def score(k1, lags):
            tot, first = 0.0, 0
            for pi, p0 in enumerate(parts):
                seg = z[p0:p0 + SUB]; ns = np.sqrt(np.vdot(seg, seg).real) + 1e-30
                top, top_d = 0.0, 0
                for d_ in lags:
                    a0 = (p0 - k1 + d_) % n_loop
                    r = refc[a0:a0 + SUB]
                    v = abs(np.vdot(r, seg)) / (np.sqrt(np.vdot(r, r).real) * ns + 1e-30)
                    if v > top:
                        top, top_d = v, d_
                tot += top
                if pi == 0:
                    first = top_d
            return tot, first
        cands = [int(round(kk + m_ * burst + c_ * tail)) % n_loop for m_ in range(5) for c_ in (0, 1)]
        coarse_scores = [score(k1, range(-12, 13))[0] for k1 in cands]      # (peaks are 1 sample wide)
        k1 = cands[int(np.argmax(coarse_scores))]
        sc, lag_first = score(k1, range(-12, 13))
        return (k1 - lag_first) % n_loop, sc / 2
    usable = n_loop - BLOCK
    for name, s in window_candidates(w, n_loop, n):
        k1, l1 = align(s)
        # The host refuses (fail closed) windows whose edges cannot show a wrap or
        # loss (see host_edges_ok). Shift such a start by <= 2048 rows; the alignment
        # is unchanged and the sub-block lag check below still runs on the new start.
        ph = ((s - k1) % n_loop) % burst
        for d_ in NUDGES:
            if 0 <= s + d_ <= usable - n and host_edges_ok(ph + d_, n, burst, act, tail):
                if d_:
                    s += d_
                    info['nudged'] = info.get('nudged', 0) + 1
                break
        # bursts are interchangeable: pick the burst whose loop range holds the whole window
        base = (s - k1) % n_loop
        shift = 0
        while base + n > n_loop - 64 and shift < 6:
            base = (base - burst) % n_loop; shift += 1
        kk = int(round(s - base)) % n_loop
        wl, wg = block_lags(z, s, kk, refc, n_loop, n, block=SUB, search=48, track=True)
        tried.append(name)
        steps = np.abs(np.diff(wg))
        if (min(wl) >= LOCK_MIN and (steps.max() if len(steps) else 0) <= 4 and max(wg) - min(wg) <= 16):
            info.update(start=int(s), candidate=name, kk=kk, sub_locks=[round(v, 3) for v in wl], sub_lags=wg,
                        tried=len(tried), note='clear of the self-similarity wrap; sub-block lags consistent (slips only)')
            break
    if 'start' not in info:
        info.update(start=0, candidate='fallback', kk=kk, tried=len(tried),
                    note='no window clear of the wrap with consistent sub-block lags (sample loss or wrap unknown)')
    hint = info.get('sub_lags') or block_lags(z, info['start'], info['kk'], refc, n_loop, n, block=SUB, search=48, track=True)[1]
    sl = []
    for k in range(4):
        lk, _ = block_lags(z if k == ch else stream(k), info['start'], info['kk'], refc, n_loop, n, block=SUB, hint=hint)
        sl.append(round(float(np.median(lk)), 4))
    info['stream_locks'] = sl
    info['select_s'] = time.perf_counter() - t0
    return info['start'], info


_FAST = {}                                         # per-reference cache and the last alignment


def fast_window(raw, ref, burst, n, ref_fft_conj=None, state=_FAST):
    """Reduced window: n < WIN rows of ONE capture that start FRAME_LEAD rows before
    an OFDM frame, so 4096 rows hold one complete frame. Made for display rate.

    The start is taken after WRAP_GUARD rows: with the shared player/capture
    start the DAC loop wrap is at the capture start, so these rows are one
    contiguous pass. That is assumed here, not searched (select_window searches
    it and costs ~0.25 s); the host checks every stream against the reference
    and refuses a window that does not match. The alignment of the previous
    capture is tried first (+-8 rows), an FFT search only when it fails."""
    t0 = time.perf_counter()
    rows = raw.reshape(-1, 8)
    n_loop = rows.shape[0]
    r0 = WRAP_GUARD
    if state.get('ref') is not ref:
        refc = ref.astype(np.complex64)
        act = ref_activity(ref)
        edges = np.flatnonzero(np.diff(np.concatenate([[0], act.astype(np.int8)])) == 1)   # frame starts, incl. row 0
        state.clear()
        state.update(ref=ref, refc=np.concatenate([refc, refc[:WIN + 256]]),
                     edges=edges[edges < burst].astype(float), kk=None)
    refc, edges = state['refc'], state['edges']
    seg = lambda k, a, m: (rows[a:a + m, 2*k].astype(np.float32) + 1j * rows[a:a + m, 2*k+1].astype(np.float32))
    rms = [float(np.sqrt(np.mean(np.abs(seg(k, r0, BLOCK)[::4]) ** 2))) for k in range(4)]
    ch = int(np.argmax(rms))
    z = seg(ch, r0, BLOCK)
    nz = np.sqrt(np.vdot(z, z).real) + 1e-30

    def lock_at(k, x=z, a=r0, norm=nz):
        r = refc[(a - k) % n_loop:(a - k) % n_loop + len(x)]
        return float(abs(np.vdot(r, x)) / (np.sqrt(np.vdot(r, r).real) * norm + 1e-30))

    kk, lock = None, 0.0
    if state['kk'] is not None:
        c = [(lock_at(state['kk'] + d), state['kk'] + d) for d in range(-8, 9)]
        lock, kk = max(c)
    if lock < 0.6:                                   # first capture, or the alignment moved
        fft, ifft = _corr_fft()
        if ref_fft_conj is None:
            ref_fft_conj = np.conj(fft(ref.astype(np.complex64)))
        x = np.zeros(n_loop, np.complex64)
        x[r0:r0 + BLOCK] = z
        k2 = int(np.argmax(np.abs(ifft(fft(x) * ref_fft_conj))))
        l2 = lock_at(k2)
        if l2 > lock:
            lock, kk = l2, k2
    info = {'det_stream': ch, 'rms_sub4': [round(v, 2) for v in rms], 'lock_block': round(lock, 4), 'rows': int(n)}
    if lock < LOCK_MIN:
        state['kk'] = None
        info.update(note='unlocked: no wanted signal in the reduced window', start=r0, candidate='none',
                    select_s=time.perf_counter() - t0)
        return r0, info
    state['kk'] = kk % n_loop
    # next frame start at or after r0 + FRAME_LEAD (burst phase; bursts are alike)
    # loop index first: the loop (131072 rows) is not a whole number of bursts
    ph = ((r0 - kk) % n_loop) % burst
    start = r0 + int(round(min((e - FRAME_LEAD - ph) % burst for e in edges)))
    # bursts are interchangeable: use the one whose loop range holds the whole window
    base = (start - kk) % n_loop
    shift = 0
    while base + n > n_loop - 64 and shift < 6:
        base = (base - burst) % n_loop; shift += 1
    kw = int(round(start - base)) % n_loop
    m = min(n, SUB)
    locks = []
    for k in range(4):
        x = seg(k, start, m)
        nx = np.sqrt(np.vdot(x, x).real) + 1e-30
        locks.append(round(max(lock_at(kw + d, x, start, nx) for d in range(-3, 4)), 4))
    info.update(start=int(start), candidate='fast', kk=kw, stream_locks=locks,
                note='reduced window after the capture start; wrap assumed at the shared start, not searched',
                select_s=time.perf_counter() - t0)
    return int(start), info


def frame_extension(start, select_s, full_sha_hex, window_bytes, info):
    js = json.dumps(info, separators=(',', ':')).encode()
    if len(js) > EXT3_JSON_MAX:
        js = json.dumps({'note': 'summary truncated', 'start': start, 'candidate': 'fallback',
                         'control_revision': info.get('control_revision', 0)}).encode()
    return struct.pack(EXT3, start, int(round(select_s * 1e6)), bytes.fromhex(full_sha_hex),
                       hashlib.sha256(window_bytes).digest(), len(js)) + js


def encode_wire(body):
    """Lossless: low-byte plane then high-byte plane of the int16 stream, raw deflate."""
    planes = np.frombuffer(body, np.uint8).reshape(-1, 2).T.tobytes()
    co = zlib.compressobj(1, zlib.DEFLATED, -15)
    comp = co.compress(planes) + co.flush()
    return struct.pack('<I32s', len(body), hashlib.sha256(body).digest()) + comp
OWNER_GONE = threading.Event()


def watch_owner():
    """stdin EOF means the owning launcher (or its ssh session) is gone."""
    try:   # raw fd (no buffered-reader lock held at interpreter shutdown)
        while os.read(0, 4096):
            pass
    except Exception:
        pass
    OWNER_GONE.set()


def owner_check():
    if OWNER_GONE.is_set():
        raise SystemExit('owner stdin closed: stopping')


def fixed_output_flag(overlay, name, gpio):
    description = getattr(gpio, 'description', None)
    if description and 'C_ALL_OUTPUTS' in description.get('parameters', {}):
        return int(description['parameters']['C_ALL_OUTPUTS'])
    key = 'control/gpio_control/axi_gpio_'+name.replace('_enable', '')
    metadata = getattr(overlay, 'ip_dict', {}).get(key, {}).get('parameters', {})
    if 'C_ALL_OUTPUTS' in metadata:
        return int(metadata['C_ALL_OUTPUTS'])
    import xml.etree.ElementTree as ET
    modules = [m for m in ET.parse('/boot/doa_mts.hwh').iter('MODULE') if m.get('FULLNAME') == '/'+key]
    if len(modules) != 1:
        raise RuntimeError('Ambiguous GPIO metadata: '+name)
    values = [p.get('VALUE') for p in modules[0].iter('PARAMETER') if p.get('NAME') == 'C_ALL_OUTPUTS']
    if len(values) != 1:
        raise RuntimeError('Missing GPIO fixed-output configuration: '+name)
    return int(values[0])


def shutdown(overlay, manifest):
    errors, readbacks, zeroed = [], {}, []
    for name in ('dac0_player', 'dac1_player'):
        if hasattr(overlay, name):
            try:
                getattr(overlay, name)[:] = 0
                if np.any(np.asarray(getattr(overlay, name)[:]) != 0):
                    errors.append(name+' readback not all zero')
                zeroed.append(name)
            except Exception as exc:
                errors.append(f'{name} clear: {type(exc).__name__}: {exc}')
    if zeroed:
        time.sleep(.003)
    manifest['dac_ram_zero_writes'] = zeroed
    for name in ('dac0_enable', 'dac1_enable'):
        try:
            getattr(overlay, name).off()
        except Exception as exc:
            errors.append(f'{name} off: {type(exc).__name__}: {exc}')
    for name in ('dac0_enable', 'dac1_enable'):
        try:
            pin = getattr(overlay, name)
            channel = pin._parent
            gpio = channel._parent
            data = int(gpio.read(channel._channel * 8))
            tri = int(gpio.read(channel._channel * 8 + 4))
            shadow = (int(channel._val) >> pin._start) & pin._mask
            all_outputs = fixed_output_flag(overlay, name, gpio)
            readbacks[name] = {'data_register': data, 'tri_register': tri,
                               'command_shadow': shadow, 'all_outputs': all_outputs}
            if (not all_outputs and (tri >> pin._start) & pin._mask) or shadow:
                errors.append(name+' disable command/direction inconsistent')
        except Exception as exc:
            errors.append(f'{name} read: {type(exc).__name__}: {exc}')
    manifest['dac_readbacks'] = readbacks
    manifest['shutdown_errors'] = errors
    manifest['dac_off_commanded'] = not errors and len(readbacks) == 2 and len(zeroed) == 2
    manifest['dac_off_verified'] = False
    manifest['dac_off_verification_note'] = 'RAM zero readback + enable off commanded; independent RF observation required'


def stream_power_dbfs(raw):
    """Mean power of each of the 4 complex streams in a full capture, dBFS."""
    w = raw.reshape(-1, 8).astype(float)
    p = (w[:, 0::2] ** 2 + w[:, 1::2] ** 2).mean(0) / 32767.0 ** 2
    return [round(float(10 * np.log10(v + 1e-30)), 2) for v in p]


def select_dac_zone(overlay, words, dac, rf_mhz, manifest, captures=2):
    """Pick the DAC Nyquist zone whose image adds constructively in this session.

    Plays the waveform, captures with the profile zone and with the other zone (only
    the DAC NyquistZone register changes: no NCO, mixer or tile resynchronisation),
    keeps the zone with clearly more received power (ZONE_MARGIN_DB, else the profile
    zone), then turns the DAC output off and zeroes its RAM again."""
    first = RF_PROFILES[rf_mhz]['dac_zone']
    blocks = (0, 2)
    result = dict(rf_mhz=rf_mhz, power_dbfs={}, margin_db=ZONE_MARGIN_DB)
    try:
        write_dac(overlay, words, dac)
        overlay.dacs_control()
        time.sleep(.01)
        sha = None
        for zone in (first, 3 - first):
            for n in blocks:
                overlay.dac[n].NyquistZone = zone
            time.sleep(.02)
            powers = []
            for _ in range(captures):
                raw, refreshed, _, sha = full_capture(overlay, sha)
                if not refreshed:
                    raise RuntimeError('DAC zone selection capture was not fresh')
                powers.append(stream_power_dbfs(raw))
            result['power_dbfs'][zone] = np.mean(powers, 0).round(2).tolist()
        mean = {z: float(10 * np.log10(np.mean(10 ** (np.array(v) / 10)))) for z, v in result['power_dbfs'].items()}
        chosen = 3 - first if mean[3 - first] > mean[first] + ZONE_MARGIN_DB else first
        for n in blocks:
            overlay.dac[n].NyquistZone = chosen
        overlay.d_nyquist_zone = [chosen] * 4      # kept by later wrapper reconfiguration
        result.update(chosen=chosen, mean_dbfs={str(k): round(v, 2) for k, v in mean.items()},
                      readback=[int(overlay.dac[n].NyquistZone) for n in blocks])
        if result['readback'] != [chosen] * 2:
            raise RuntimeError('DAC Nyquist zone readback %s' % result['readback'])
    finally:
        overlay.dacs_off()
        write_dac(overlay, np.zeros(RAM, dtype='<i2'), dac)
    manifest['dac_zone_selection'] = result
    return result['chosen']


def check_adc_headroom(overlay, words, dac, manifest, captures=2):
    """Play the (scaled) waveform, capture, and refuse the session when any ADC stream
    peaks above ADC_PEAK_LIMIT_DBFS. The DAC is off and its RAM zero afterwards."""
    peaks = []
    try:
        write_dac(overlay, words, dac)
        overlay.dacs_control()
        time.sleep(.01)
        sha = None
        for _ in range(captures):
            raw, refreshed, _, sha = full_capture(overlay, sha)
            if not refreshed:
                raise RuntimeError('ADC headroom capture was not fresh')
            peaks.append(int(np.max(np.abs(raw.astype(int)))))
    finally:
        overlay.dacs_off()
        write_dac(overlay, np.zeros(RAM, dtype='<i2'), dac)
    peak_dbfs = round(float(20 * np.log10(max(peaks) / 32767.0 + 1e-12)), 2)
    manifest['adc_headroom'] = dict(peak_codes=peaks, peak_dbfs=peak_dbfs, limit_dbfs=ADC_PEAK_LIMIT_DBFS)
    if peak_dbfs > ADC_PEAK_LIMIT_DBFS:
        raise RuntimeError('ADC peak %.1f dBFS above %.1f dBFS: lower the DAC peak' % (peak_dbfs, ADC_PEAK_LIMIT_DBFS))
    return peak_dbfs


def require_lock(overlay, manifest, stage):
    value = int(overlay.clocktreeMTS.MTSclkwiz.read(4))
    if len(manifest.setdefault('clock_lock_readbacks', {})) < 2000:
        manifest['clock_lock_readbacks'][stage] = value
    if value != 1:
        raise RuntimeError(f'Clock tree unlocked at {stage}: {value}')


def write_dac(overlay, words, selected):
    """Write full RAM explicitly (len == RAM: the wrapper neither tiles nor truncates).
    selected: '0' (DAC_B), '1' (DAC_A) or a (DAC_B, DAC_A) mask; the rest is zeroed."""
    zero = np.zeros(RAM, dtype='<i2')
    mask = {'0': (True, False), '1': (False, True)}.get(selected, selected)
    a = words if mask[0] else zero
    b = words if mask[1] else zero
    assert len(overlay.dac0_player) == RAM and len(overlay.dac1_player) == RAM
    overlay.dac_data_mem_write(a, overlay.dac0_player)
    overlay.dac_data_mem_write(b, overlay.dac1_player)
    ok0 = np.array_equal(np.asarray(overlay.dac0_player[:]), a)
    ok1 = np.array_equal(np.asarray(overlay.dac1_player[:]), b)
    if not (ok0 and ok1):
        raise RuntimeError('DAC RAM readback mismatch')


def full_capture(overlay, previous_sha):
    """Freshness: tail sentinel must be overwritten (if RAM is PS-writable) AND the
    capture must differ from the previous one (ADC noise makes repeats impossible)."""
    overlay.adc_capture[RAM-8:RAM] = SENTINEL
    writable = np.array_equal(np.asarray(overlay.adc_capture[RAM-8:RAM]), SENTINEL)
    if overlay.da == 2:
        synced_trigger(overlay)
    else:
        overlay.trigger_capture()
    time.sleep(SETTLE)
    raw = np.array(overlay.adc_capture[:RAM], dtype='<i2', copy=True)
    sha = hashlib.sha256(raw.tobytes()).hexdigest()
    refreshed = sha != previous_sha and not (writable and np.array_equal(raw[-8:], SENTINEL))
    return raw, refreshed, writable, sha


def wait_request(client, timeout, deadline, pads, controls=None):
    """Wait for one frame request b'N'; check owner and deadline every 0.25 s.
    b'W' asks for one PAD2 link warm-up filler (not ADC data; at most PAD_LIMIT)."""
    t0 = time.monotonic()
    client.settimeout(0.25)
    while True:
        owner_check()
        if deadline is not None and time.monotonic() > deadline:
            raise SystemExit('max-seconds reached: stopping')
        if controls is not None:
            controls.check()
            if not controls.streaming:
                t0 = time.monotonic()  # a deliberate pause is not a request timeout
                time.sleep(.05)
                continue
        try:
            req = client.recv(1)
        except socket.timeout:
            if time.monotonic() - t0 > timeout:
                raise
            continue
        if req == b'W' and pads[0] < PAD_LIMIT:
            pads[0] += 1
            client.settimeout(30)
            client.sendall(struct.pack(FRAME_HDR, b'PAD2', pads[0], time.monotonic_ns(), 0, time.time_ns(),
                                       b'warmup  ', 0, PAD_BYTES) + bytes(PAD_BYTES))
            client.settimeout(0.25)
            continue
        if req != b'N':
            raise ConnectionResetError('client closed or bad request')
        return time.monotonic_ns()


def parse_schedule(text):
    phases, frames = [], 0
    for item in text.split(','):
        kind, value = item.split(':')
        if kind in ('wave', 'blank'):
            n = int(value)
            if not 1 <= n <= 30:
                raise ValueError('phase frames 1..30')
            frames += n
            phases.append((kind, n))
        elif kind == 'pause':
            s = float(value)
            if not 0 < s <= 10:
                raise ValueError('pause 0..10 s')
            phases.append((kind, s))
        else:
            raise ValueError('unknown phase '+kind)
    if frames > 30 or not phases or phases[0][0] != 'wave':
        raise ValueError('schedule must start with wave and total <= 30 frames')
    return phases, frames


def main():
    def interrupted(signum, frame):
        raise SystemExit(f'Capture interrupted by signal {signum}')
    for signum in (signal.SIGTERM, getattr(signal, 'SIGHUP', signal.SIGTERM)):
        signal.signal(signum, interrupted)
    p = argparse.ArgumentParser()
    p.add_argument('--reference', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--schedule')
    p.add_argument('--continuous', action='store_true')
    p.add_argument('--max-seconds', type=float)
    p.add_argument('--max-frames', type=int)
    p.add_argument('--owner-stdin', action='store_true', required=True)
    p.add_argument('--stream-bind', required=True)
    p.add_argument('--stream-port', type=int, default=4011)
    p.add_argument('--control-port', type=int, default=0, help='separate acknowledged command socket; window4 only')
    p.add_argument('--rf-mhz', type=int, default=DEFAULT_RF_MHZ, choices=sorted(RF_PROFILES))
    p.add_argument('--dac', choices=['0', '1'], default='0')
    p.add_argument('--dac-peak', type=int, default=REFERENCE_PEAK,
                   help='DAC waveform peak code, %d..%d (reference is scaled from %d)' % (100, DAC_PEAK_MAX, REFERENCE_PEAK))
    p.add_argument('--sampling-freq-unit', choices=['GHz'], required=True)
    p.add_argument('--request-timeout', type=float, default=30)
    p.add_argument('--wire-codec', choices=['raw', 'deflate'], default='deflate')
    p.add_argument('--capture-clock-mhz', type=float, default=0.0,
                   help='set PL clock 0 (ADC capture writer side of the stream clock converter) after loading '
                        'the overlay; 0 keeps the overlay value. The RF stream runs on the RF fabric clock; a '
                        'capture clock even slightly slower loses samples (~100 ppm measured at 124.99875 MHz).')
    p.add_argument('--wire-mode', choices=['adc-d-fullram', 'window4'], default='adc-d-fullram')
    p.add_argument('--exclusive-control', action='store_true', required=True)
    p.add_argument('--save-all-captures', action='store_true',
                   help='bounded mode only: keep every full-RAM capture (raw_<seq>_<phase>.npy, 1 MiB each) '
                        'next to the manifest for offline diagnosis of host-refused windows')
    a = p.parse_args()
    if a.control_port and (a.wire_mode != 'window4' or not 1024 <= a.control_port <= 65535 or a.control_port == a.stream_port):
        p.error('control port must be a distinct unprivileged port in window4 mode')
    if a.continuous:
        if a.schedule or a.max_seconds is None or a.max_frames is None:
            p.error('--continuous needs --max-seconds and --max-frames, and no --schedule')
        if not (0 < a.max_seconds <= MAX_CONTINUOUS_S and 1 <= a.max_frames <= 200000):
            p.error('continuous bounds out of range')
        phases, total = [('wave', a.max_frames)], a.max_frames
    else:
        if not a.schedule or a.max_frames is not None:
            p.error('bounded mode needs --schedule (<= 30 frames) and no --max-frames')
        phases, total = parse_schedule(a.schedule)
    if a.save_all_captures and a.continuous:
        p.error('--save-all-captures is for bounded schedules only')
    deadline = None if a.max_seconds is None else time.monotonic() + a.max_seconds
    threading.Thread(target=watch_owner, daemon=True).start()
    board = Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(b'\x00')
    if board != b'RFSoC4x2':
        raise RuntimeError('Wrong board identity')
    with np.load(a.reference, allow_pickle=False) as data:
        words = np.asarray(data['dac_words'])
        if (str(data['profile']) != PROFILE or str(data['source_sha256']) != SRC_SHA
                or float(data['dac_complex_fs']) != 500e6 or int(data['ram_words']) != RAM):
            raise ValueError('Reference is not the reviewed legacy truncated profile')
        dropped = int(data['dropped_complex_500'])
        ref125 = np.asarray(data['ref125']).astype(np.complex128) if 'ref125' in data.files else None
        burst125 = float(data['burst_complex_500']) / 4 if 'burst_complex_500' in data.files else None
    v3 = a.wire_mode == 'window4'
    if v3 and (ref125 is None or ref125.shape != (RAM // 8,) or not burst125):
        raise ValueError('window4 needs the reference ref125 (131072 complex) and burst length')
    if words.dtype != np.dtype('<i2') or words.shape != (RAM,) or np.max(np.abs(words.astype(int))) > 1200:
        raise ValueError('Legacy helper requires 1048576 int16 words with peak <= 1200')
    if not 100 <= a.dac_peak <= DAC_PEAK_MAX:
        raise ValueError('--dac-peak must be 100..%d' % DAC_PEAK_MAX)
    if a.dac_peak != REFERENCE_PEAK:
        words = np.clip(np.rint(words.astype(float) * (a.dac_peak / REFERENCE_PEAK)), -32767, 32767).astype('<i2')
    manifest = {'board': board.decode(), 'rf_mhz': a.rf_mhz, 'dac': a.dac,
                'dac_connector': {'0': 'DAC_B', '1': 'DAC_A'}[a.dac],
                'dac_peak': a.dac_peak, 'dac_words_peak': int(np.max(np.abs(words.astype(int)))),
                'receive_stream0_connector': 'ADC_D', 'fs_assumed_hz': 125e6,
                'profile': PROFILE, 'schedule': a.schedule, 'frames_planned': total,
                'continuous': bool(a.continuous), 'max_seconds': a.max_seconds, 'owner_stdin': True,
                'wire_format': WIRE_FORMAT3 if v3 else WIRE_FORMAT,
                'wire_channels': [0, 1, 2, 3] if v3 else [0], 'wire_bytes': WIRE_BYTES3 if v3 else WIRE_BYTES,
                'wire_mode': a.wire_mode,
                'wire_codec': CODEC if a.wire_codec == 'deflate' else 'none',
                'loop_truncation': {'played_complex_500': RAM//2, 'dropped_complex_500': dropped,
                                    'boundary_loop_index': 0},
                'wrapper_sha256': hashlib.sha256(Path('/boot/doa_mts.py').read_bytes()).hexdigest(),
                'reference_sha256': hashlib.sha256(Path(a.reference).read_bytes()).hexdigest(),
                'helper_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                'dac_off_verified': False, 'frames': []}
    sys.path.insert(0, '/boot')
    from doa_mts import doaMtsOverlay
    overlay = listener = client = None
    control_service = controls = None
    hardware_lock = threading.RLock()
    output = Path(a.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    sequence = 0
    try:
        owner_check()
        overlay = doaMtsOverlay('/boot/doa_mts.bit')
        if a.capture_clock_mhz:
            if not 125.0 <= a.capture_clock_mhz <= 150.0:
                raise ValueError('capture clock must be 125..150 MHz')
            from pynq import Clocks
            Clocks.fclk0_mhz = a.capture_clock_mhz
            time.sleep(0.1)
        from pynq import Clocks
        manifest['capture_clock_mhz'] = round(float(Clocks.fclk0_mhz), 6)
        print('capture clock (PL clock 0) %.5f MHz' % Clocks.fclk0_mhz, flush=True)
        overlay.dacs_off()
        write_dac(overlay, np.zeros(RAM, dtype='<i2'), '0')
        require_lock(overlay, manifest, 'initialization')
        manifest['adc_rates_raw'] = [overlay.adc[n].BlockStatus['SamplingFreq'] for n in range(4)]
        manifest['adc_decimation'] = [overlay.adc[n].DecimationFactor for n in range(4)]
        manifest['dac_rates_raw'] = [overlay.dac[n].BlockStatus['SamplingFreq'] for n in (0, 2)]
        manifest['dac_interpolation'] = [overlay.dac[n].InterpolationFactor for n in (0, 2)]
        manifest['dac_datapath_mode'] = [overlay.dac[n].DataPathMode for n in (0, 2)]
        manifest['dac_imr_pass_mode'] = [overlay.dac[n].IMRPassMode for n in (0, 2)]
        adc_fs = np.array(manifest['adc_rates_raw'])*1e9/np.array(manifest['adc_decimation'])
        dac_fs = np.array(manifest['dac_rates_raw'])*1e9/np.array(manifest['dac_interpolation'])
        manifest['dac_effective_complex_fs_hz'] = (dac_fs/2).tolist()
        if (not np.allclose(adc_fs, 125e6) or not np.allclose(dac_fs/2, 500e6)
                or manifest['dac_datapath_mode'] != [3, 3]):
            raise RuntimeError('Runtime rates differ from legacy reference')
        rf = RF_PROFILES[a.rf_mhz]
        overlay.centre_freq = a.rf_mhz
        overlay.nyquist_zone = rf['adc_zone']
        overlay.d_centre_freq = [a.rf_mhz]*4
        overlay.d_nyquist_zone = [rf['dac_zone']]*4
        manifest.update(adc_nyquist_zone=rf['adc_zone'], dac_nyquist_zone=rf['dac_zone'])
        overlay.d_phases = [0, 0, 0, 0]
        manifest['sync'] = enable_mts(overlay)
        require_lock(overlay, manifest, 'after_sync')
        if len(overlay.adc_capture) != RAM:
            raise RuntimeError('ADC RAM size differs')
        manifest['adc_ram_words'] = RAM
        overlay.da = 2
        overlay.dacPower = [int(a.dac == '0'), 0, int(a.dac == '1'), 0]
        if a.rf_mhz in SELECT_DAC_ZONE:
            manifest['dac_nyquist_zone'] = select_dac_zone(overlay, words, a.dac, a.rf_mhz, manifest)
            require_lock(overlay, manifest, 'after_dac_zone_selection')
        check_adc_headroom(overlay, words, a.dac, manifest)
        rf_state = dict(rf_mhz=a.rf_mhz, adc_nyquist_zone=manifest['adc_nyquist_zone'],
                        dac_nyquist_zone=manifest['dac_nyquist_zone'], dac_peak=a.dac_peak,
                        adc_peak_dbfs=manifest['adc_headroom']['peak_dbfs'])
        print('RF profile ' + json.dumps(rf_state), flush=True)
        if a.control_port:
            from board_commands import BoardCommands
            from control_service import ControlService
            controls = BoardCommands(overlay, a.dac, WIN*8,
                                     lambda: require_lock(overlay, manifest, 'control'),
                                     lambda mask: write_dac(overlay, words, mask),
                                     allowed_words=[r*8 for r in ROWS_ALLOWED], both_dacs=True)
            hardware_lock = controls.lock
            control_service = ControlService(a.stream_bind, a.control_port, controls.apply, lock=hardware_lock)
            control_service.start()
            manifest['control_port'] = a.control_port
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((a.stream_bind, a.stream_port))
        listener.listen(1)
        listener.settimeout(1)
        print(f'Waiting for legacy client on port {a.stream_port}; DACs disabled', flush=True)
        t_listen = time.monotonic()
        while client is None:
            owner_check()
            if time.monotonic() - t_listen > 120:
                raise socket.timeout('no client within 120 s')
            try:
                client, _ = listener.accept()
            except socket.timeout:
                pass
        client.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2 << 20)
        client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        if v3:
            fft3, _ = _corr_fft()
            ref_fft_conj = np.conj(fft3(ref125.astype(np.complex64)))
            header = json.dumps({'magic_version': 3, 'sync': manifest['sync'], 'control_port': a.control_port, 'control_protocol': 'jsonline-v1', 'source': 'rfsoc4x2-hardware', 'board': board.decode(),
                                 'format': WIRE_FORMAT3, 'adc_ram_words': RAM,
                                 'capture': 'full-ram-contiguous', 'window': 'same-capture-contiguous',
                                 'window_rows': WIN, 'capture_rows': RAM // 8,
                                 'window_rows_allowed': list(ROWS_ALLOWED) if a.control_port else [WIN],
                                 'wire_channels': [0, 1, 2, 3], 'available_channels': [1, 1, 1, 1],
                                 # stream k = ADC index k (verified by per-ADC mixer phase steps);
                                 # connector names per the RFSoC 4x2 manual rev A5 / PYNQ base design
                                 'channel_connectors': ['ADC_D', 'ADC_C', 'ADC_B', 'ADC_A'],
                                 'dac_connectors': {'0': 'DAC_B', '2': 'DAC_A'},
                                 'path_controls': ['phasec', 'dphasec', 'again', 'dgain', 'aiqphase', 'diqphase',
                                                   'adsa', 'dvop'] if a.control_port else [],
                                 'lane_convention': 'board lanes I,Q per stream; host builds I - 1j*Q (tcpDataRec)',
                                 'frame_bytes': WIRE_BYTES3, 'frame_header': FRAME_HDR, 'frame_extension': EXT3,
                                 'extension_json_max': EXT3_JSON_MAX,
                                 'compression': CODEC if a.wire_codec == 'deflate' else 'none',
                                 'pad_bytes': PAD_BYTES,
                                 'samples_per_channel': WIN, 'fs_hz': 125e6, **rf_state,
                                 'profile': PROFILE, 'dac_connector': manifest['dac_connector'],
                                 'selection': 'board-reported self-similarity wrap estimate; guarded window with reference sub-block lag checks',
                                 'frames_planned': total, 'continuous': bool(a.continuous),
                                 'max_seconds': a.max_seconds,
                                 'board_monotonic_ns': time.monotonic_ns(),
                                 'board_realtime_ns': time.time_ns()}).encode()
            client.settimeout(30)
            client.sendall(b'R4X2IQ3\n'+struct.pack('<I', len(header))+header)
        header = json.dumps({'magic_version': 2, 'sync': manifest['sync'], 'source': 'rfsoc4x2-hardware', 'board': board.decode(),
                             'format': WIRE_FORMAT, 'adc_ram_words': RAM,
                             'capture': 'full-ram-contiguous', 'wire_channels': [0],
                             'available_channels': [1, 0, 0, 0],
                             'channel_connectors': ['ADC_D', None, None, None],
                             'lane_convention': 'board lanes I,Q; host builds I - 1j*Q (tcpDataRec)',
                             'frame_bytes': WIRE_BYTES, 'frame_header': FRAME_HDR,
                             'compression': CODEC if a.wire_codec == 'deflate' else 'none',
                             'pad_bytes': PAD_BYTES,
                             'samples_per_channel': RAM//8, 'fs_hz': 125e6, **rf_state,
                             'profile': PROFILE, 'dac_connector': manifest['dac_connector'],
                             'frames_planned': total, 'continuous': bool(a.continuous),
                             'max_seconds': a.max_seconds,
                             'board_monotonic_ns': time.monotonic_ns(),
                             'board_realtime_ns': time.time_ns()}).encode()
        if not v3:
            client.settimeout(30)
            client.sendall(b'R4X2IQ2\n'+struct.pack('<I', len(header))+header)
        loaded = None
        previous_sha = None
        pads = [0]
        bound_stop = False
        for kind, value in phases:
            if bound_stop:
                break
            if kind == 'pause':
                manifest['frames'].append({'pause_s': value, 'at_ns': time.monotonic_ns()})
                t_end = time.monotonic() + value
                while time.monotonic() < t_end:
                    owner_check()
                    time.sleep(0.05)
                continue
            target = words if kind == 'wave' else np.zeros(RAM, dtype='<i2')
            if loaded != kind:
                with hardware_lock:
                    enabled = overlay.dacPower[0 if a.dac=='0' else 2]
                    write_dac(overlay, target if enabled else np.zeros(RAM, dtype='<i2'), a.dac)
                    loaded = kind
                    overlay.dacs_control()  # enables the selected DAC only (dacPower)
                time.sleep(.01)
            for _ in range(value):
                try:
                    req_ns = wait_request(client, a.request_timeout, deadline, pads, controls)
                except SystemExit as exc:
                    if not str(exc).startswith('max-seconds reached'):
                        raise
                    # Orderly time bound: fall through to END3/END2 so the client
                    # sees a normal end of stream (not a disconnect); shutdown as usual.
                    manifest['stream_stop'] = str(exc)
                    bound_stop = True
                    break
                while True:
                    owner_check()
                    if deadline is not None and time.monotonic()>deadline:
                        raise SystemExit('max-seconds reached: stopping')
                    with hardware_lock:
                        if controls is not None:
                            controls.check()
                        if controls is None or controls.streaming:
                            require_lock(overlay, manifest, 'frame%d' % sequence)
                            raw, refreshed, writable, previous_sha = full_capture(overlay, previous_sha)
                            mono = time.monotonic_ns()
                            control_revision = controls.revision if controls else 0
                            rows_now = controls.data_words // 8 if controls else WIN
                            break
                    time.sleep(.05)
                if not refreshed:
                    raise RuntimeError('ADC RAM not refreshed (sentinel kept or identical capture)')
                label = kind.encode().ljust(8, b' ')
                ext = b''
                reduced = v3 and rows_now != WIN
                if v3:
                    if reduced:
                        start, sel = fast_window(raw, ref125, burst125, rows_now, ref_fft_conj)
                    else:
                        start, sel = select_window(raw, ref125, burst125, ref_fft_conj)
                    wire = np.ascontiguousarray(raw.reshape(-1, 8)[start:start + rows_now, :])   # all 4 streams
                    body = wire.tobytes()
                    if len(body) != rows_now * 16 or wire.shape != (rows_now, 8):
                        raise RuntimeError('window wire size differs')
                    sel['control_revision'] = control_revision
                    ext = frame_extension(start, sel['select_s'], previous_sha, body, sel)
                    # a reduced window is small: sent raw (IQL3), no deflate time
                    magic = b'IQZ3' if a.wire_codec == 'deflate' and not reduced else b'IQL3'
                    mask = MASK3
                else:
                    wire = np.ascontiguousarray(raw.reshape(-1, 8)[:, 0:2])   # stream0 = ADC_D only
                    body = wire.tobytes()
                    if len(body) != WIRE_BYTES:
                        raise RuntimeError('wire size differs')
                    magic = b'IQZ2' if a.wire_codec == 'deflate' else b'IQL2'
                    mask = MASK
                payload = encode_wire(body) if a.wire_codec == 'deflate' and not reduced else body
                client.settimeout(30)
                client.sendall(struct.pack(FRAME_HDR, magic, sequence, mono, req_ns, time.time_ns(),
                                           label, mask, len(payload)) + ext + payload)
                ch0 = wire[:, 0:2].astype(float)
                entry = {'sequence': sequence, 'phase': kind, 'monotonic_ns': mono,
                         'request_rx_ns': req_ns, 'sha256': previous_sha,
                         'wire_sha256': hashlib.sha256(body).hexdigest(), 'payload_bytes': len(payload),
                         'sentinel_writable': bool(writable),
                         'ch0_rms': float(np.sqrt(np.mean(ch0**2))),
                         'ch0_peak': int(np.max(np.abs(ch0)))}
                if v3:
                    entry.update(rows=rows_now, window_start=int(sel['start']), select_s=round(sel['select_s'], 4),
                                 candidate=sel.get('candidate'), lock_block=sel.get('lock_block'), wrap_row=sel.get('wrap_row'), wrap_from=sel.get('wrap_from'),
                                 stream_locks=sel.get('stream_locks'), sub_lags=sel.get('sub_lags'),
                                 stream_rms=sel.get('rms_sub4'))
                if len(manifest['frames']) < 2000:
                    manifest['frames'].append(entry)
                if not a.continuous and (sequence == 0 or kind == 'blank' or a.save_all_captures):
                    np.save(output.parent/f'raw_{sequence:02d}_{kind}.npy', raw)
                sequence += 1
        manifest['frames_captured'] = sequence
        manifest['pads_sent'] = pads[0]
        client.settimeout(30)
        client.sendall(struct.pack(FRAME_HDR, b'END3' if v3 else b'END2', sequence, time.monotonic_ns(), 0,
                                   time.time_ns(), b'end     ', MASK3 if v3 else MASK, 0))
        # Wait (bounded) for the client to close first: closing with unread client
        # bytes would send RST and could discard END2 before the client reads it.
        client.settimeout(15)
        try:
            while client.recv(4096):
                pass
        except OSError:
            pass
    except (BrokenPipeError, ConnectionResetError, socket.timeout) as exc:
        manifest['stream_stop'] = f'{type(exc).__name__}: {exc}'
    except SystemExit as exc:
        if str(exc).startswith(('owner stdin closed', 'max-seconds reached')):
            manifest['stream_stop'] = str(exc)   # orderly owner/bound stop; shutdown still runs
        else:
            failed = True
            manifest['experiment_error'] = f'SystemExit: {exc}'
            raise
    except BaseException as exc:
        failed = True
        manifest['experiment_error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        if control_service is not None:
            control_service.close()
            manifest['control_commands'] = controls.log
        manifest['frames_captured'] = sequence
        for connection in (client, listener):
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass
        if overlay is not None:
            with hardware_lock:
                shutdown(overlay, manifest)
        else:
            manifest['shutdown_errors'] = ['Overlay construction did not return; output state unknown']
        try:
            output.write_text(json.dumps(manifest, indent=1)+'\n')
        except Exception as exc:
            print(f'Could not persist manifest: {exc}', file=sys.stderr)
        if not manifest.get('dac_off_commanded', False):
            print('DAC disable FAILED/UNVERIFIED: '+str(manifest.get('shutdown_errors')), file=sys.stderr)
            if not failed:
                raise RuntimeError('DAC disable command failed; inspect hardware state')
        else:
            print('Both DAC RAMs zero (readback) and enables off commanded.', file=sys.stderr)
    print(output)


if __name__ == '__main__':
    main()
