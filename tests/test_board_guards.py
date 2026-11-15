import types
import unittest
from tools.board_capture import shutdown, require_lock


class Pin:
    def __init__(self, fail=False):
        self.fail, self.disabled = fail, False

    def off(self):
        if self.fail:
            raise OSError('write failed')
        self.disabled = True

    def read(self):
        return int(not self.disabled)


class BoardGuards(unittest.TestCase):
    def test_both_shutdowns_attempted_after_first_fails(self):
        o = types.SimpleNamespace(dac0_enable=Pin(True), dac1_enable=Pin())
        status = {}
        shutdown(o, status)
        self.assertTrue(o.dac1_enable.disabled)
        self.assertFalse(status['dac_off_verified'])
        self.assertEqual(status['dac_readbacks'], {'dac0_enable': 1, 'dac1_enable': 0})
        self.assertIn('write failed', status['shutdown_errors'][0])

    def test_shutdown_readback(self):
        o = types.SimpleNamespace(dac0_enable=Pin(), dac1_enable=Pin())
        status = {}
        shutdown(o, status)
        self.assertTrue(status['dac_off_verified'])

    def test_unlocked_clock_aborts(self):
        clock = types.SimpleNamespace(read=lambda address: 0)
        o = types.SimpleNamespace(clocktreeMTS=types.SimpleNamespace(MTSclkwiz=clock))
        status = {}
        with self.assertRaisesRegex(RuntimeError, 'unlocked'):
            require_lock(o, status, 'after_sync')
        self.assertEqual(status['clock_lock_readbacks']['after_sync'], 0)
