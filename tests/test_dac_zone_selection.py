"""DAC Nyquist zone selection at session start (board/legacy_capture.select_dac_zone).

Fake overlay: the received level of streams 1..3 depends on the DAC zone, as on the
bench at 5.2 GHz, where the DAC image adds constructively in one zone per session."""
import unittest
import numpy as np
import board.legacy_capture as lc


class Block:
    def __init__(self):
        self.NyquistZone = 2


class FakeOverlay:
    def __init__(self, strong_zone):
        self.strong = strong_zone
        self.dac = [Block() for _ in range(4)]
        self.dac0_player = np.zeros(lc.RAM, '<i2')
        self.dac1_player = np.zeros(lc.RAM, '<i2')
        self.adc_capture = np.zeros(lc.RAM, '<i2')
        self.enabled = False
        self.rng = np.random.default_rng(1)
        self.da = 2
        self.d_nyquist_zone = [2] * 4

    def dac_data_mem_write(self, words, mem):
        mem[:] = words

    def dacs_control(self):
        self.enabled = True

    def dacs_off(self):
        self.enabled = False

    def capture(self):
        zone = self.dac[0].NyquistZone
        amp = np.array([46, 66, 68, 58]) if zone == self.strong else np.array([46, 15, 8, 25])
        if not self.dac0_player.any():
            amp = np.zeros(4)
        x = self.rng.normal(0, 1, (lc.RAM // 8, 8)) * 11
        x += np.repeat(amp, 2) / np.sqrt(2) * self.rng.choice([-1, 1], (lc.RAM // 8, 8))
        self.adc_capture[:] = np.clip(x, -32768, 32767).astype('<i2').ravel()


class Selection(unittest.TestCase):
    def run_selection(self, strong):
        o = FakeOverlay(strong)
        orig = lc.synced_trigger
        lc.synced_trigger = lambda ov: ov.capture()
        try:
            manifest = {}
            words = np.full(lc.RAM, 1000, '<i2')
            chosen = lc.select_dac_zone(o, words, '0', 5200, manifest)
        finally:
            lc.synced_trigger = orig
        return o, chosen, manifest['dac_zone_selection']

    def test_keeps_the_profile_zone_when_it_is_the_strong_one(self):
        o, chosen, r = self.run_selection(strong=2)
        self.assertEqual(chosen, 2)
        self.assertEqual(r['readback'], [2, 2])

    def test_switches_to_the_other_zone_when_it_is_clearly_stronger(self):
        o, chosen, r = self.run_selection(strong=1)
        self.assertEqual(chosen, 1)
        self.assertEqual([o.dac[n].NyquistZone for n in (0, 2)], [1, 1])
        self.assertEqual(o.d_nyquist_zone, [1] * 4)          # later wrapper reconfiguration keeps it
        self.assertGreater(r['mean_dbfs']['1'], r['mean_dbfs']['2'] + lc.ZONE_MARGIN_DB)

    def test_output_is_off_and_ram_zero_afterwards(self):
        o, _, _ = self.run_selection(strong=1)
        self.assertFalse(o.enabled)
        self.assertFalse(o.dac0_player.any() or o.dac1_player.any())

    def test_small_difference_keeps_the_profile_zone(self):
        o, chosen, r = self.run_selection(strong=None)       # both zones weak and equal
        self.assertEqual(chosen, lc.RF_PROFILES[5200]['dac_zone'])

    def test_only_5200_selects(self):
        self.assertEqual(lc.SELECT_DAC_ZONE, {5200})


if __name__ == '__main__':
    unittest.main()
