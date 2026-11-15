"""Conventions: samples x channels, x = I - jQ, output y = X @ conj(w)."""
import numpy as np

FS = 125e6  # HWH: ADC 5 GS/s / 40; verify runtime before hardware use.
NFFT, CP, TRAIN, PAYLOAD, PERIOD = 256, 64, 4, 8, 4096
BINS = np.r_[np.arange(-24, 0), np.arange(1, 25)] % NFFT


def reference(seed=42):
    rng = np.random.default_rng(seed)
    q = lambda shape: ((2*rng.integers(0, 2, shape)-1) +
                       1j*(2*rng.integers(0, 2, shape)-1))/np.sqrt(2)
    pilot = q((len(BINS),))
    symbols = np.vstack([np.tile(pilot, (TRAIN, 1)), q((PAYLOAD, len(BINS)))])
    symbols[TRAIN:, :4] = pilot[:4]  # Reserved pilots track payload common phase.
    freq = np.zeros((TRAIN+PAYLOAD, NFFT), complex)
    freq[:, BINS] = symbols
    time = np.fft.ifft(freq, axis=1)
    wave = np.r_[np.concatenate([time[:, -CP:], time], axis=1).ravel(),
                 np.zeros(PERIOD-(TRAIN+PAYLOAD)*(NFFT+CP))]
    scale = np.max(np.abs(wave))
    return wave/scale, symbols/scale


def dac_words(wave, peak=1200):
    """DAC is 1 Gcomplex/s (10 GS/s / 10), eight times ADC rate.

    Periodic Fourier interpolation preserves a seamless 32768-complex-sample
    RAM loop. TX positive Q follows vsa_rfsoc Functions/sigPrepare.m.
    Actual RF sideband/conjugation must be established from live correlation.
    """
    from scipy.signal import resample
    if not 0 < peak <= 16383:
        raise ValueError("DAC peak must be in 1..16383")
    tx = resample(wave, len(wave)*8)
    tx *= peak/max(np.max(np.abs(tx.real)), np.max(np.abs(tx.imag)))
    out = np.empty(tx.size*2, dtype='<i2')
    out[0::2], out[1::2] = np.rint(tx.real), np.rint(tx.imag)
    return out


def acquire(x, wave, fs=FS, cfo_limit=150e3):
    """Search periodic pilot only; payload never participates in acquisition.

    Each frame reacquires delay and CFO; there is no assumed continuity between
    separately triggered BRAM captures. Also tests conjugation explicitly.
    """
    if x.ndim != 2 or x.shape[1] != 4 or len(x) < 2*PERIOD:
        raise ValueError("Need at least 8192 samples x four channels")
    if not np.isfinite(x).all() or np.linalg.norm(x) == 0:
        raise ValueError("Empty, zero or nonfinite capture")
    pre = wave.copy()
    pre[TRAIN*(NFFT+CP):] = 0
    template = np.fft.fft(pre)
    t = np.arange(len(x))/fs
    best = None
    grid = np.linspace(-cfo_limit, cfo_limit,
                       max(3, int(np.ceil(4*cfo_limit*PERIOD/fs))+1))
    for conjugated in (False, True):
        z = x.conj() if conjugated else x
        for f in grid:
            block = z[:PERIOD]*np.exp(-2j*np.pi*f*t[:PERIOD, None])
            corr = np.fft.ifft(np.fft.fft(block, axis=0)*template.conj()[:, None], axis=0)
            score = np.sum(abs(corr)**2, axis=1)
            delay = int(np.argmax(score))
            candidate = (float(score[delay]), delay, float(f), conjugated)
            if best is None or candidate[0] > best[0]:
                best = candidate
    _, delay, coarse, conjugated = best
    z = x.conj() if conjugated else x.copy()
    z = z*np.exp(-2j*np.pi*coarse*t[:, None])
    aligned = z[delay:delay+PERIOD]
    span = NFFT+CP
    # Strong uncorrelated interferers can dominate a raw lag-product CFO
    # estimator. Use provisional pilot-trained spatial suppression first.
    provisional, _, _, _ = weights(aligned[:TRAIN*span], wave[:TRAIN*span])
    combined = aligned @ provisional.conj()
    a, b = combined[:(TRAIN-1)*span], combined[span:TRAIN*span]
    residual = np.angle(np.sum(a.conj()*b))*fs/(2*np.pi*span)
    total = coarse+residual
    aligned *= np.exp(-2j*np.pi*residual*np.arange(PERIOD)[:, None]/fs)
    pilot = wave[:TRAIN*span]
    steering = pilot.conj() @ aligned[:len(pilot)]/np.vdot(pilot, pilot).real
    final_w, _, _, _ = weights(aligned[:len(pilot)], pilot)
    combined = aligned[:len(pilot)] @ final_w.conj()
    coherence = float(abs(np.vdot(pilot, combined))**2 /
                      max(np.vdot(pilot, pilot).real*np.vdot(combined, combined).real, 1e-30))
    if coherence < 0.1:
        raise ValueError("No reliable DAC pilot lock (post-combining coherence < 0.1)")
    return aligned, {"delay_samples": delay, "cfo_hz": total,
                     "conjugated": conjugated, "pilot_coherence": coherence}


def weights(x, pilot, loading=0.01):
    """Supervised residual-covariance MVDR; train once, freeze for payload."""
    a = pilot.conj() @ x/np.vdot(pilot, pilot).real
    residual = x-pilot[:, None]*a
    r = residual.T @ residual.conj()/len(x)
    r += np.eye(4)*max(np.trace(r).real/4*loading, 1e-12)
    w = np.linalg.solve(r, a)
    w /= np.vdot(a, w)
    mrc = a/np.vdot(a, a).real
    return w, mrc, a, float(np.linalg.cond(r))


def demod(y, expected):
    span = NFFT+CP
    blocks = y[:(TRAIN+PAYLOAD)*span].reshape(-1, span)[:, CP:]
    bins = np.fft.fft(blocks, axis=1)[:, BINS]
    h = np.mean(bins[:TRAIN]/expected[:TRAIN], axis=0)
    if np.min(abs(h)) < 1e-12:
        raise ValueError("Pilot channel estimate has a zero")
    equalized = bins[TRAIN:]/h
    target = expected[TRAIN:]
    phase = np.angle(np.sum(equalized[:, :4]*target[:, :4].conj(), axis=1))
    equalized *= np.exp(-1j*phase[:, None])
    equalized, target = equalized[:, 4:], target[:, 4:]
    # Training gain only: no fit to payload, no decision-directed EVM reduction.
    error = equalized-target
    evm = float(np.sqrt(np.mean(abs(error)**2)/np.mean(abs(target)**2)))
    ber = float(np.mean(np.stack([equalized.real > 0, equalized.imag > 0]) !=
                        np.stack([target.real > 0, target.imag > 0])))
    return {"evm_percent": 100*evm, "ber": ber,
            "payload_phase_deg": np.rad2deg(phase).tolist()}, equalized


def process(x, fs=FS):
    wave, symbols = reference()
    aligned, tracking = acquire(x, wave, fs)
    count = TRAIN*(NFFT+CP)
    w, mrc, a, condition = weights(aligned[:count], wave[:count])
    metrics, constellations = {}, {}
    for name, vector in {"adc0": np.eye(4)[0], "mrc": mrc, "mvdr": w}.items():
        metrics[name], constellations[name] = demod(aligned @ vector.conj(), symbols)
    tracking.update(channel_gain=abs(a).tolist(),
                    channel_phase_deg=np.rad2deg(np.angle(a/a[0])).tolist(),
                    covariance_condition=condition,
                    weight_norm=float(np.linalg.norm(w)))
    return {"tracking": tracking, "metrics": metrics,
            "input_peak_components": np.maximum(abs(x.real).max(axis=0), abs(x.imag).max(axis=0)).tolist(),
            "input_rail_fraction": np.mean((abs(x.real) >= 32767) | (abs(x.imag) >= 32767), axis=0).tolist()}, constellations


def simulate(seed=7, shared_path=False, cfo=42000, delay=793):
    """Four-channel fixture, 20 dB jammer, 0.02 rms independent receiver noise."""
    rng = np.random.default_rng(seed)
    wave, _ = reference()
    a = np.array([1, .9*np.exp(.4j), 1.1*np.exp(-.7j), .95*np.exp(1j)])
    b = a if shared_path else np.array([1, -1, 1j, -1j])
    n = np.arange(4*PERIOD)
    desired = np.roll(np.tile(wave, 4), delay)*np.exp(2j*np.pi*cfo*n/FS)
    jammer = 10*np.sqrt(np.mean(abs(wave)**2))*np.exp(2j*np.pi*.0973*n)
    noise = .02*(rng.standard_normal((len(n),4))+1j*rng.standard_normal((len(n),4)))/np.sqrt(2)
    return desired[:,None]*a+jammer[:,None]*b+noise
