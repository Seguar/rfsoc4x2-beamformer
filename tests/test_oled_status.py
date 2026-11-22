"""Hardware-free tests of the board OLED texts and writer (board/oled_status.py)."""
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path

from board import oled_status as o


class Device:
    def __init__(self, fail=False, slow=0.0):
        self.texts, self.fail, self.slow = [], fail, slow

    def write(self, text):
        if self.fail:
            raise OSError('Unable to open OLED SPI file')
        time.sleep(self.slow)
        self.texts.append(text)


class InPlaceDevice(Device):
    """Models the display memory: write() clears and writes, put() moves the cursor."""
    def __init__(self):
        super().__init__()
        self.rows = [' ' * 16, ' ' * 16]
        self.bytes = 0

    def write(self, text):
        super().write(text)
        self.rows = text.split('\n')
        self.bytes += 4 + len(text)          # clear, home, display on, line 2 + characters

    def put(self, row, col, text):
        line = self.rows[row]
        self.rows[row] = line[:col] + text + line[col + len(text):]
        self.bytes += 1 + len(text)

    def shown(self):
        return '\n'.join(self.rows)


def wait_for(cond, seconds=5):
    deadline = time.monotonic() + seconds
    while not cond() and time.monotonic() < deadline:
        time.sleep(.01)
    return cond()


class TextTests(unittest.TestCase):
    def test_lines_are_16_printable_characters(self):
        self.assertEqual(o.screen('x' * 40, 'Ü\tok'), 'x' * 16 + '\n' + '??ok'.ljust(16))
        for top, bottom in [o.idle_text([], 0), o.starting_text(5200, 123.4), o.waiting_text(3000, 'B'),
                            o.ended_text(dict(dac_off_commanded=True, frames=123456)),
                            o.live_text(dict(time=1, frames=1, evm_percent=99.99, rf_mhz=-6000.0,
                                             adc_peak_dbfs=-100.0), 5200, 'AB', 1)]:
            self.assertLessEqual(len(top), 16, top)
            self.assertLessEqual(len(bottom), 16, bottom)

    def test_live_texts(self):
        now = 1000.0
        live = dict(time=now, frames=5, evm_percent=3.88, rf_mhz=5200.0, adc_peak_dbfs=-19.4)
        self.assertEqual(o.live_text(live, 5200, 'AB', now), ('EVM 3.88%   LIVE', '5200MHz -19dB AB'))
        self.assertEqual(o.live_text(dict(live, evm_percent=None), 5200, 'B', now)[0], 'EVM --      LIVE')
        self.assertEqual(o.live_text(dict(live, evm_percent=float('nan')), 5200, 'B', now)[0], 'EVM --      LIVE')
        self.assertEqual(o.live_text(live, 5200, 'AB', now + 4)[0], 'EVM 3.88%   LIVE')
        self.assertEqual(o.live_text(live, 5200, 'AB', now + 6)[0], 'no frames')
        self.assertEqual(o.live_text(dict(live, streaming=False), 5200, 'AB', now)[0], 'PAUSED')
        # retuned by the app: the helper's frequency, not the start profile
        self.assertEqual(o.live_text(dict(live, rf_mhz=3000.0), 5200, 'AB', now)[1], '3000MHz -19dB AB')

    def test_end_texts(self):
        self.assertEqual(o.ended_text(dict(reason='client_stop', dac_off_commanded=True, frames=7)),
                         ('Session ended', 'DACs off 7fr'))
        self.assertEqual(o.ended_text(dict(dac_off_commanded=True, frames=199999))[1], 'DACs off 199kfr')
        self.assertEqual(o.ended_text(dict(reason='helper_ended', dac_off_commanded=False)),
                         ('Ended', 'DAC OFF UNSURE!'))
        self.assertEqual(o.ended_text(dict(reason='helper_failed', error='')), ('Board error', 'start failed'))

    def test_status_file_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'status.json'
            self.assertEqual(o.read_status(path), {})
            o.write_status(path, dict(frames=3))
            status = o.read_status(path)
            self.assertEqual(status['frames'], 3)
            self.assertAlmostEqual(status['time'], time.time(), delta=5)
            path.write_text('{"frames": ')            # partial file: treated as none
            self.assertEqual(o.read_status(path), {})
            path.write_text(json.dumps([1]))
            self.assertEqual(o.read_status(path), {})


class WriterTests(unittest.TestCase):
    def test_newest_text_wins_and_repeats_are_skipped(self):
        device = Device(slow=.2)
        oled = o.Oled(factory=lambda: device, log=lambda *a, **k: None)
        oled.show('one')
        self.assertTrue(wait_for(lambda: device.texts))
        for n in range(5):
            oled.show('text %d' % n)               # only the last one is pending
        oled.show('text 4')
        oled.close(wait=5)
        self.assertEqual(device.texts, [o.screen('one'), o.screen('text 4')])

    def test_changes_are_written_in_place(self):
        device = InPlaceDevice()
        oled = o.Oled(factory=lambda: device, log=lambda *a, **k: None)
        texts = [('EVM 3.88%   LIVE', '5200MHz -19dB AB'), ('EVM 3.91%   LIVE', '5200MHz -19dB AB'),
                 ('EVM 12.40%  LIVE', '5200MHz -20dB AB'), ('EVM --      LIVE', '3000MHz -20dB AB')]
        for top, bottom in texts:
            oled.show(top, bottom)
            self.assertTrue(wait_for(lambda: oled.written == o.screen(top, bottom)))
            self.assertEqual(device.shown(), o.screen(top, bottom))
        self.assertEqual(oled.writes, dict(full=1, partial=3))
        self.assertEqual(len(device.texts), 1)
        before = device.bytes
        oled.show('EVM 3.90%   LIVE', '3000MHz -20dB AB')
        self.assertTrue(wait_for(lambda: oled.written.startswith('EVM 3.90')))
        self.assertLessEqual(device.bytes - before, 6)       # about 50 ms instead of 0.47 s
        oled.show('Session ended', 'DACs off 7fr', full=True)
        self.assertTrue(wait_for(lambda: oled.written.startswith('Session')))
        self.assertEqual((oled.writes['full'], device.shown()), (2, o.screen('Session ended', 'DACs off 7fr')))
        oled.close()

    def test_whole_screen_refresh_after_full_every(self):
        device = InPlaceDevice()
        oled = o.Oled(factory=lambda: device, log=lambda *a, **k: None)
        oled.show('a')
        self.assertTrue(wait_for(lambda: oled.written))
        oled.full_at -= o.FULL_EVERY
        oled.show('b')
        self.assertTrue(wait_for(lambda: oled.written == o.screen('b')))
        self.assertEqual(oled.writes, dict(full=2, partial=0))
        oled.close()

    def test_changed_runs(self):
        old = o.screen('EVM 3.88%   LIVE', '5200MHz -19dB AB')
        self.assertEqual(o.changed_runs(old, old), [])
        self.assertEqual(o.changed_runs(old, o.screen('EVM 3.91%   LIVE', '5200MHz -19dB AB')), [(0, 6, '91')])
        self.assertEqual(o.changed_runs(old, o.screen('EVM 4.88%   LIVE', '5200MHz -19dB AB')), [(0, 4, '4')])
        # one unchanged character between two changes: one piece
        self.assertEqual(o.changed_runs(old, o.screen('EVM 4.98%   LIVE', '5200MHz -19dB AB')), [(0, 4, '4.9')])
        self.assertEqual(o.changed_runs(old, o.screen('XVM 3.88%   LIVX', '5200MHz -20dB AB')),
                         [(0, 0, 'X'), (0, 15, 'X'), (1, 9, '20')])

    def test_vendor_display_refuses_a_missing_device(self):
        if os.access(o.DEVICE, os.W_OK):
            self.skipTest('device present')
        with self.assertRaises(OSError):
            o.VendorDisplay()

    def test_close_writes_a_last_text(self):
        device = Device()
        oled = o.Oled(factory=lambda: device, log=lambda *a, **k: None)
        oled.close('bye', 'now')
        self.assertEqual(device.texts[-1], o.screen('bye', 'now'))

    def test_missing_driver_turns_the_display_off(self):
        logs = []
        def factory():
            raise ImportError('No module named rfsoc4x2')
        oled = o.Oled(factory=factory, log=lambda *a, **k: logs.append(a))
        oled.show('x')
        self.assertTrue(wait_for(lambda: not oled.enabled))
        self.assertIn('ImportError', oled.error)
        oled.show('y')                              # no error, no thread
        oled.close()
        self.assertEqual(len(logs), 1)

    def test_write_failure_turns_the_display_off(self):
        oled = o.Oled(factory=lambda: Device(fail=True), log=lambda *a, **k: None)
        oled.show('x')
        self.assertTrue(wait_for(lambda: not oled.enabled))
        oled.close()

    def test_disabled_never_opens_the_device(self):
        called = []
        oled = o.Oled(factory=lambda: called.append(1), enabled=False)
        oled.show('x')
        oled.close('y')
        self.assertEqual(called, [])


if __name__ == '__main__':
    unittest.main()
