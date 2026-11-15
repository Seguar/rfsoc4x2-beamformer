import unittest
import numpy as np
import matplotlib
matplotlib.use('Agg')
from matplotlib import pyplot as plt
from rfsoc_demo.live import unavailable_display
from rfsoc_demo.dsp import process


class SignalStatus(unittest.TestCase):
    def test_signal_loss_clears_current_evm_constellation_and_cfo(self):
        fig, axes = plt.subplots(2,2)
        evm, iq, phase, cfo = axes.ravel()
        iq.set_title('EVM -28 dB (3.9%)')
        points = iq.scatter([.7],[.7])
        bars = phase.bar(range(4),[10,20,30,40])
        line, = cfo.plot([0,1],[10,10])
        try:
            unavailable_display(iq,points,bars,cfo,line,evm,'STALE DATA')
            self.assertIn('EVM unavailable',iq.get_title())
            self.assertNotIn('-28',iq.get_title())
            self.assertEqual(len(points.get_offsets()),0)
            self.assertEqual(len(line.get_xdata()),0)
            self.assertTrue(all(np.isnan(bar.get_height()) for bar in bars))
            self.assertIn('history only',evm.get_title())
        finally:
            plt.close(fig)

    def test_noise_only_does_not_report_pilot_lock(self):
        for seed in (123,456,789):
            rng = np.random.default_rng(seed)
            x = rng.standard_normal((16384,4))+1j*rng.standard_normal((16384,4))
            with self.assertRaisesRegex(ValueError,'No reliable DAC pilot lock'):
                process(x,adc0_only=True)
