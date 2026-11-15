#!/usr/bin/env python3
"""Diagnostic known-reference correlation. This is NOT a payload EVM estimator.

Searches full-period reference copies using evaluation payload as well as pilots;
use only to diagnose unintended delayed sources, never as receiver performance.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from rfsoc_demo.dsp import reference, PERIOD


def inspect(frame):
    wave, _ = reference()
    z = frame[:PERIOD, 0].conj()
    corr = np.fft.ifft(np.fft.fft(z)*np.fft.fft(wave).conj())
    first = int(np.argmax(abs(corr)))
    masked = abs(corr).copy()
    indices = np.arange(PERIOD)
    separation = np.minimum((indices-first)%PERIOD, (first-indices)%PERIOD)
    masked[separation < 64] = 0
    second = int(masked.argmax())
    copies = [wave[(indices-delay)%PERIOD] for delay in (first, second)]
    a1 = np.c_[copies[0], np.ones(PERIOD)]
    a2 = np.c_[*copies, np.ones(PERIOD)]
    norm = max(np.linalg.norm(z-z.mean()), 1e-12)
    c1 = np.linalg.lstsq(a1,z,rcond=None)[0]
    c2 = np.linalg.lstsq(a2,z,rcond=None)[0]
    return {'diagnostic_only': True, 'frame_index': 0, 'adc': 0,
            'conjugation_assumed_from_prior_acquisition': True,
            'reference_delays_samples': [first,second],
            'one_copy_normalized_residual': float(np.linalg.norm(z-a1@c1)/norm),
            'two_copy_normalized_residual': float(np.linalg.norm(z-a2@c2)/norm),
            'copy_gain_magnitudes': abs(c2[:2]).tolist()}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture')
    p.add_argument('--out', required=True)
    a = p.parse_args()
    with np.load(a.capture, allow_pickle=False) as data:
        samples = data['samples']
    result = inspect(samples[0] if samples.ndim == 3 else samples)
    path = Path(a.out)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__ == '__main__':
    main()
