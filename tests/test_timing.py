import unittest
import numpy as np
from rfsoc_demo.dsp import reference, demod, NFFT, CP, TRAIN, PAYLOAD, BINS, PILOT_INDEX


class TimingPilots(unittest.TestCase):
    def make_symbols(self, flip_data=False):
        wave, expected = reference()
        body = wave[:(TRAIN+PAYLOAD)*(NFFT+CP)].reshape(-1,NFFT+CP)[:,CP:]
        freq = np.fft.fft(body,axis=1)
        signed = np.fft.fftfreq(NFFT)*NFFT
        # Unknown frequency-selective channel is common to training/payload.
        channel = (.9+.1*np.cos(signed/13))*np.exp(1j*(.31+.008*signed))
        freq *= channel
        shifts = np.linspace(0,1.25,PAYLOAD)
        for index, shift in enumerate(shifts):
            freq[TRAIN+index] *= np.exp(1j*(.2*index+2*np.pi*signed*shift/NFFT))
        if flip_data:
            self.assertNotIn(5,PILOT_INDEX)
            freq[TRAIN+3,BINS[5]] *= -1
        time = np.fft.ifft(freq,axis=1)
        return np.concatenate([time[:,-CP:],time],axis=1).ravel(), expected, shifts

    def test_distributed_pilots_track_fractional_timing_and_common_phase(self):
        samples, expected, shifts = self.make_symbols()
        result, _ = demod(samples,expected)
        self.assertLess(result['evm_percent'], 1e-8)
        self.assertEqual(result['ber'], 0)
        np.testing.assert_allclose(result['payload_timing_shift_samples'],shifts,atol=1e-10)

    def test_payload_errors_are_not_fit_away(self):
        samples, expected, shifts = self.make_symbols(flip_data=True)
        result, _ = demod(samples,expected)
        self.assertGreater(result['evm_percent'], 5)
        self.assertGreater(result['ber'], 0)
        np.testing.assert_allclose(result['payload_timing_shift_samples'],shifts,atol=1e-10)

    def test_loss_inside_fft_window_retains_nonzero_error(self):
        samples, expected, _ = self.make_symbols()
        gap = (TRAIN+3)*(NFFT+CP)+CP+NFFT//2
        samples[gap:-1] = samples[gap+1:]
        result, _ = demod(samples,expected)
        self.assertGreater(result['evm_percent'], 1)
