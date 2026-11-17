#!/usr/bin/env python3
"""Count capture sample slips in live windows (bench diagnostic, no DSP claims).

Each window is compared with the transmitted loop (ref125) in 256-row chunks of
active signal: the best integer lag around the board-reported alignment plus a
parabolic sub-sample refinement. A lag step between chunks is a slip: +1 means
one capture sample was lost, -1 one repeated. Steps are reported per stream, so
a capture-side cause (all four streams at the same row) can be told apart from
a per-converter one.

    python3 tools/slip_scan.py <board address> <legacy_ref.npz> [frames] [rows]
"""
import sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from session_client import Session


def chunk_lags(z, ref, start_idx, chunk=256, search=4):
    """Lag (samples) of each active chunk of z against ref; nan where silent."""
    n_loop = len(ref)
    ext = np.concatenate([ref, ref[:len(z) + 2 * search + chunk]])
    p = np.abs(ref) ** 2
    lags = np.full(len(z) // chunk, np.nan)
    for j in range(len(lags)):
        seg = z[j * chunk:(j + 1) * chunk]
        e = (start_idx + j * chunk) % n_loop
        if np.mean(p[np.arange(e, e + chunk) % n_loop]) < 0.3 * p.mean():
            continue
        c = np.array([abs(np.vdot(ext[(e + d) % n_loop:(e + d) % n_loop + chunk], seg)) for d in range(-search, search + 1)])
        k = int(np.argmax(c))
        if 0 < k < len(c) - 1:
            a, b, cc = c[k - 1], c[k], c[k + 1]
            frac = 0.5 * (a - cc) / (a - 2 * b + cc) if (a - 2 * b + cc) else 0.0
        else:
            frac = 0.0
        lags[j] = k - search + frac
    return lags


def main():
    host, refp = sys.argv[1], sys.argv[2]
    frames = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    rows = int(sys.argv[4]) if len(sys.argv) > 4 else 32768
    clock = float(sys.argv[5]) if len(sys.argv) > 5 else None
    ref = np.conj(np.load(refp)['ref125'].astype(np.complex128))   # host sense (I - jQ)
    steps_all, rows_seen = [], 0
    with Session(host, max_seconds=900, progress=None, capture_clock_mhz=clock) as s:
        print('stream period check: window rows', s.meta.get('window_rows'))
        if rows != 32768:
            s.command('dataChan %d' % (rows * 8)); s.frame()
        for f in range(frames):
            x = s.frame()
            kk = s.last_info.get('kk')
            if kk is None:
                print('frame', f, 'no alignment', s.last_info.get('candidate')); continue
            start_idx = (s.last_info['start'] - kk)
            per = []
            for k in range(4):
                lg = chunk_lags(x[:, k], ref, start_idx)
                good = ~np.isnan(lg)
                idx = np.flatnonzero(good)
                d = np.diff(lg[idx])
                st = [(int(idx[i + 1]) * 256, round(float(d[i]), 2)) for i in np.flatnonzero(np.abs(d) > 0.5)]
                per.append(st)
            rows_seen += len(x)
            same = all([r for r, _ in p] == [r for r, _ in per[0]] for p in per)
            steps_all.append(per[0])
            print('frame %2d rows %d steps stream0 %s | identical on all 4 streams: %s' % (f, len(x), per[0], same))
    n = sum(len(sp) for sp in steps_all)
    print('total steps %d over %d rows -> %.1f ppm; sizes %s' % (n, rows_seen, 1e6 * n / max(rows_seen, 1),
          sorted({sz for sp in steps_all for _, sz in sp})))
    print('ended', getattr(s, 'ended', None))


if __name__ == '__main__':
    main()
