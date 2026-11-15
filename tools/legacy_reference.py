"""Build the pinned FFT64 legacy waveform/profile; never accepts live captures."""
import hashlib
from pathlib import Path
import numpy as np
from scipy.io import loadmat, savemat

SOURCE_SHA = '3f17e6cccef941d1bac4fefff4439472d8a6e6923b0ef7633e6184448be9eef3'
PROFILE = 'legacy-ofdm64-truncated-v1'
RAM_WORDS = 1048576


def build(source, directory):
    source, directory = Path(source), Path(directory)
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise ValueError('The legacy waveform does not match the reviewed source SHA256')
    values = loadmat(source)['sigInt16'].ravel().astype(np.int64)
    if len(values) != 1100250:
        raise ValueError('Unexpected legacy waveform size')
    directory.mkdir(parents=True, exist_ok=True)
    scale = 1200 / np.abs(values).max()
    words = np.round(values[:RAM_WORDS]*scale).astype('<i2')
    loop = words[0::2].astype(float)+1j*words[1::2].astype(float)
    n = len(loop)//4
    spectrum = np.fft.fft(loop)
    ref125 = np.fft.ifft(np.r_[spectrum[:n//2], spectrum[-n//2:]])*(n/len(loop))
    # This is the correlation-group period; it is not the OFDM FFT length.
    group500 = 110025
    npz, mat = directory/'legacy_ref.npz', directory/'legacy_ref125.mat'
    np.savez(npz, dac_words=words, ref125=ref125, dac_complex_fs=500e6,
             adc_fs=125e6, profile=PROFILE, source_sha256=SOURCE_SHA,
             source_words=len(values), ram_words=RAM_WORDS,
             dropped_complex_500=len(values)//2-len(loop),
             burst_complex_500=group500, complete_bursts_in_loop=len(loop)//group500,
             scale=scale)
    savemat(mat, dict(ref125=ref125[:, None], profile=PROFILE, burst125=group500/4))
    return npz, mat
