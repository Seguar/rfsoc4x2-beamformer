import types
import unittest
from tools.board_capture import shutdown, require_lock


class Pin:
    def __init__(self, fail=False):
        self.fail, self.disabled = fail, False
        self._start, self._mask = 0, 1
        gpio = types.SimpleNamespace(read=lambda offset: 0)
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
