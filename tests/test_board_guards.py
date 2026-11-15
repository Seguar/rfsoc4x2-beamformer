import types
import unittest
from tools.board_capture import shutdown, require_lock, load_selected_dacs, settled_capture, fixed_output_flag
from unittest.mock import patch
import numpy as np


class Pin:
    def __init__(self, fail=False):
        self.fail, self.disabled = fail, False
        self._start, self._mask = 0, 1
        gpio = types.SimpleNamespace(read=lambda offset: 0, description={'parameters': {'C_ALL_OUTPUTS': 0}})
        self._parent = types.SimpleNamespace(_parent=gpio, _channel=0, _val=1)

    def off(self):
        if self.fail:
            raise OSError('write failed')
        self.disabled = True
        self._parent._val = 0

    def read(self):
        raise AssertionError('PYNQ slice read must not be called')


class BoardGuards(unittest.TestCase):
    def test_both_shutdowns_attempted_after_first_fails(self):
        o = types.SimpleNamespace(dac0_enable=Pin(True), dac1_enable=Pin())
        status = {}
        shutdown(o, status)
        self.assertTrue(o.dac1_enable.disabled)
        self.assertFalse(status['dac_off_verified'])
        self.assertFalse(status['dac_off_commanded'])
        self.assertEqual(status['dac_readbacks']['dac0_enable']['command_shadow'], 1)
        self.assertEqual(status['dac_readbacks']['dac1_enable']['command_shadow'], 0)
        self.assertIn('write failed', status['shutdown_errors'][0])

    def test_shutdown_readback(self):
        o = types.SimpleNamespace(dac0_enable=Pin(), dac1_enable=Pin())
        status = {}
        shutdown(o, status)
        self.assertTrue(status['dac_off_commanded'])
        self.assertFalse(status['dac_off_verified'])  # All-output DATA reads do not prove RF-off.

    def test_unlocked_clock_aborts(self):
        clock = types.SimpleNamespace(read=lambda address: 0)
        o = types.SimpleNamespace(clocktreeMTS=types.SimpleNamespace(MTSclkwiz=clock))
        status = {}
        with self.assertRaisesRegex(RuntimeError, 'unlocked'):
            require_lock(o, status, 'after_sync')
        self.assertEqual(status['clock_lock_readbacks']['after_sync'], 0)

    def test_fixed_output_tri_ignored_without_claiming_physical_off(self):
        o = types.SimpleNamespace(dac0_enable=Pin(), dac1_enable=Pin())
        for pin in (o.dac0_enable, o.dac1_enable):
            pin._parent._parent.description['parameters']['C_ALL_OUTPUTS'] = 1
            pin._parent._parent.read = lambda offset: 0xffffffff if offset == 4 else 0
        status = {}
        shutdown(o, status)
        self.assertTrue(status['dac_off_commanded'])
        self.assertFalse(status['dac_off_verified'])

    def test_capture_trigger_cannot_play_unselected_waveform(self):
        o = types.SimpleNamespace(dac0_player=np.zeros(8, dtype=np.int16),
                                  dac1_player=np.ones(8, dtype=np.int16))
        o.dac_data_mem_write = lambda words, mem: mem.__setitem__(slice(None), words)
        words = np.arange(8, dtype=np.int16)
        load_selected_dacs(o, words, '0')
        np.testing.assert_array_equal(o.dac0_player, words)
        np.testing.assert_array_equal(o.dac1_player, 0)

    def test_ram_copy_follows_settle(self):
        events = []
        class Memory:
            def __getitem__(self, index):
                events.append('copy')
                return np.arange(16, dtype=np.int16)
        o = types.SimpleNamespace(trigger_capture=lambda: events.append('trigger'), adc_capture=Memory())
        with patch('tools.board_capture.time.sleep', side_effect=lambda delay: events.append('settle')):
            settled_capture(o)
        self.assertEqual(events, ['trigger', 'settle', 'copy'])

    def test_gpio_metadata_fallback_without_description(self):
        o = types.SimpleNamespace(ip_dict={'control/gpio_control/axi_gpio_dac0':
                                          {'parameters': {'C_ALL_OUTPUTS': '1'}}})
        gpio = types.SimpleNamespace()
        self.assertEqual(fixed_output_flag(o,'dac0_enable',gpio),1)
