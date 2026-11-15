"""Export the exact Python v2 reference to MATLAB (no RNG compatibility assumed)."""
import argparse
from pathlib import Path
import numpy as np
from scipy.io import savemat
from rfsoc_demo.dsp import reference, NFFT, CP, TRAIN, BINS, PILOT_INDEX, FS

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', default='out/matlab-reference.mat')
    args = parser.parse_args()
    wave, symbols = reference()
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    savemat(path, {'wave': wave[:, None], 'symbols': symbols,
                  'nfft': NFFT, 'cp': CP, 'train': TRAIN,
                  'bins': (BINS+1)[None, :], 'pilots': (PILOT_INDEX+1)[None, :],
                  'fsHz': FS, 'waveformVersion': 2})
    print(path)
