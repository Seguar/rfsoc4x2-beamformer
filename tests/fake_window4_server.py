"""Offline v3 (window4) stream for host/MATLAB fixtures. NOT hardware.

Serves the helper v3 protocol (R4X2IQ3 header, IQZ3 frames with extension,
PAD2 warm-up, END3) on localhost with source "offline-fake". Each capture is
the reviewed 125 MHz loop reference, circularly shifted (random capture start),
steered to a known angle on a half-wavelength 4-element ULA in the host
convention (host samples I - jQ = conj(loop) * exp(1j*pi*m*sin(theta))), plus
noise. The board's own select_window/frame_extension/encode_wire are used.

Scenario items (comma separated): wave:<deg>, blank, dead:<stream>, stale,
badsha, wave_unsorted ... e.g. "wave:20,wave:20,blank,dead:2,stale,wave:-35".
Board-misjudgement items (the window start is forced, the selector summary still
claims a good candidate, so only the host check can refuse them; all at 20 deg):
  wrapfirst:<j>   window starts j rows before the real loop wrap (wrap in block 1)
  wraplast:<j>    window ends j rows after the real loop wrap (wrap in block 4)
  loss:<pos>:<n>  n samples lost at window row pos
  slips           ~100 ppm one-row advances (legitimate, must be accepted)
  clean           forced start at a verifiable burst phase (control)
  fallback / nocand / badjson   clean window, selector summary fallback / no
                  candidate field / unparsable JSON (summary must fail closed)
Board-clock fields use time.perf_counter_ns (Windows monotonic_ns ticks ~15 ms,
which can put a fake capture timestamp after host receipt).
Usage: python -m tests.fake_window4_server <port> <scenario> [--mask 1111]
"""
import argparse
import hashlib
import json
import socket
import struct
import sys
import tempfile
import time
from pathlib import Path
import numpy as np
from board.legacy_capture import (select_window, frame_extension, encode_wire, FRAME_HDR, EXT3, EXT3_JSON_MAX,
                                  WIN, WIRE_BYTES3, WIRE_FORMAT3, CODEC, PAD_BYTES)
from tools.legacy_reference import build

N = 131072


def capture(ref, theta, rng, kk, dead=None, blank=False, noise=6.0, idx=None):
    n = np.arange(N)
    loop = ref[(n - kk) % N if idx is None else idx] * (2500 / np.abs(ref).max())
    rows = np.zeros((N, 8))
    for k in range(4):
        a = np.exp(1j * np.pi * k * np.sin(np.deg2rad(theta)))
        z = (0 if blank or dead == k else 1) * loop * np.conj(a)       # lanes I + jQ
        z = z + noise * (rng.standard_normal(N) + 1j * rng.standard_normal(N))
        rows[:, 2 * k], rows[:, 2 * k + 1] = z.real, z.imag
    return np.clip(np.round(rows), -32768, 32767).astype('<i2').ravel()


FORCED = ('wrapfirst', 'wraplast', 'loss', 'slips', 'clean', 'fallback', 'nocand', 'badjson')
SAFE_PHASE = 2000          # burst phase of a verifiable window start (inside frame 1's active part)


def forced_capture(ref, burst, rng, kind, arg):
    """Capture (20 deg) and a forced window start. The loop wrap is at capture row kk
    (loop index 0); clean starts sit at SAFE_PHASE of the second burst."""
    kk = 40000
    n = np.arange(N)
    idx = (n - kk) % N
    if kind == 'wrapfirst':
        start = kk - int(arg)                  # int(arg) pre-wrap rows, then the wrap
    elif kind == 'wraplast':
        start = kk + int(arg) - WIN            # int(arg) post-wrap rows at the end
    else:
        start = int(round(kk + SAFE_PHASE + burst))
        if kind == 'loss':
            pos, cnt = (int(v) for v in arg.split(':'))
            idx = np.where(n >= start + pos, (n - kk + cnt) % N, idx)
        elif kind == 'slips':
            adv = np.zeros(N, int)
            adv[np.arange(start + 3000, start + WIN, 10000)] = 1     # 100 ppm
            idx = (idx + np.cumsum(adv)) % N
    assert 0 <= start and start + WIN <= N
    return capture(ref, 20.0, rng, kk, idx=idx), start


def main():
    p = argparse.ArgumentParser()
    p.add_argument('port', type=int)
    p.add_argument('scenario')
    p.add_argument('--source', default='C:/work/git/vsa_rfsoc/Signals/dac_ofdm_f_500.mat')
    p.add_argument('--mask', default='1111')
    p.add_argument('--seed', type=int, default=20261116)
    a = p.parse_args()
    items = a.scenario.split(',')
    with tempfile.TemporaryDirectory() as tmp:
        npz, _ = build(a.source, tmp)
        with np.load(npz) as d:
            ref = np.asarray(d['ref125']); burst = float(d['burst_complex_500']) / 4
    rng = np.random.default_rng(a.seed)
    avail = [int(c) for c in a.mask]
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', a.port)); srv.listen(1); srv.settimeout(120)
    print('FAKE_READY', flush=True)
    c, _ = srv.accept()
    header = json.dumps({'magic_version': 3, 'source': 'offline-fake', 'board': 'offline-fake',
                         'format': WIRE_FORMAT3, 'adc_ram_words': 8 * N, 'capture': 'full-ram-contiguous',
                         'window': 'same-capture-contiguous', 'window_rows': WIN, 'capture_rows': N,
                         'wire_channels': [0, 1, 2, 3], 'available_channels': avail,
                         'frame_bytes': WIRE_BYTES3, 'frame_header': FRAME_HDR, 'frame_extension': EXT3,
                         'extension_json_max': EXT3_JSON_MAX, 'compression': CODEC, 'pad_bytes': PAD_BYTES,
                         'samples_per_channel': WIN, 'fs_hz': 125e6, 'rf_mhz': 3000,
                         'profile': 'legacy-ofdm64-truncated-v1', 'frames_planned': len(items),
                         'continuous': False, 'max_seconds': 300,
                         'board_monotonic_ns': time.perf_counter_ns(), 'board_realtime_ns': time.time_ns()}).encode()
    c.sendall(b'R4X2IQ3\n' + struct.pack('<I', len(header)) + header)
    log = []
    prev = None
    seq = 0
    c.settimeout(60)
    while seq < len(items):
        req = c.recv(1)
        if req == b'W':
            c.sendall(struct.pack(FRAME_HDR, b'PAD2', 1, time.perf_counter_ns(), 0, time.time_ns(), b'warmup  ', 0,
                                  PAD_BYTES) + bytes(PAD_BYTES))
            continue
        if req != b'N':
            break
        req_ns = time.perf_counter_ns()
        kind, _, arg = items[seq].partition(':')
        forced = None
        if kind == 'stale' and prev is not None:
            raw = prev                                          # same capture again
        elif kind in FORCED:
            raw, forced = forced_capture(ref, burst, rng, kind, arg)
        else:
            theta = float(arg) if kind == 'wave' and arg else 20.0
            raw = capture(ref, theta, rng, int(rng.integers(0, N)), dead=int(arg) if kind == 'dead' else None,
                          blank=kind == 'blank')
        prev = raw
        full = hashlib.sha256(raw.tobytes()).hexdigest()
        start, info = select_window(raw, ref, burst)
        if forced is not None:                                  # board misjudgement / summary faults
            start = forced
            info.update(start=start, candidate='after-wrap')
            if kind == 'fallback':
                info['candidate'] = 'fallback'
            elif kind == 'nocand':
                info.pop('candidate')
        body = np.ascontiguousarray(raw.reshape(-1, 8)[start:start + WIN, :]).tobytes()
        ext = frame_extension(start, info['select_s'], full, body, info)
        if kind == 'badjson':                                   # same length, unparsable JSON
            j0 = struct.calcsize(EXT3)
            ext = ext[:j0] + b'{' * (len(ext) - j0)
        if kind == 'badsha':
            ext = ext[:40] + bytes(32) + ext[72:]
        payload = encode_wire(body)
        label = ('blank' if kind == 'blank' else 'wave').encode().ljust(8, b' ')
        c.sendall(struct.pack(FRAME_HDR, b'IQZ3', seq, time.perf_counter_ns(), req_ns, time.time_ns(), label, 15,
                              len(payload)) + ext + payload)
        log.append({'seq': seq, 'item': items[seq], 'start': start, 'select_s': info['select_s'],
                    'candidate': info.get('candidate'), 'stream_locks': info.get('stream_locks')})
        seq += 1
    c.sendall(struct.pack(FRAME_HDR, b'END3', seq, time.perf_counter_ns(), 0, time.time_ns(), b'end     ', 15, 0))
    try:
        c.settimeout(10)
        while c.recv(4096):
            pass
    except OSError:
        pass
    c.close(); srv.close()
    print('FAKE_LOG ' + json.dumps(log), flush=True)


if __name__ == '__main__':
    sys.exit(main())
