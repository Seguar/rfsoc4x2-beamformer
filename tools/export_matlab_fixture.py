"""Frozen differential fixture; MATLAB cannot fit or regenerate its expected metrics."""
import argparse
from pathlib import Path
import numpy as np
from scipy.io import savemat
from rfsoc_demo.dsp import (reference, simulate, acquire, weights, demod,
                           NFFT, CP, TRAIN, BINS, PILOT_INDEX, FS)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', default='out/matlab-fixture.mat')
    args = parser.parse_args()
    wave, symbols = reference()
    capture = simulate()
    aligned, tracking = acquire(capture, wave)
    w, *_ = weights(aligned[:TRAIN*(NFFT+CP)], wave[:TRAIN*(NFFT+CP)])
    metric, _ = demod(aligned@w.conj(), symbols)
    rng = np.random.default_rng(193)
    noise = rng.normal(size=capture.shape)+1j*rng.normal(size=capture.shape)
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    savemat(path, {'wave': wave[:, None], 'symbols': symbols,
                  'nfft': float(NFFT), 'cp': float(CP), 'train': float(TRAIN),
                  'bins': (BINS+1)[None, :].astype(float),
                  'pilots': (PILOT_INDEX+1)[None, :].astype(float),
                  'fsHz': FS, 'waveformVersion': 2, 'capture': capture, 'noise': noise,
                  'pythonEvmPercent': metric['evm_percent'], 'pythonBer': metric['ber'],
                  'pythonCfoHz': tracking['cfo_hz']})
    print(path)
