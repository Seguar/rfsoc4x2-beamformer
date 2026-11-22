"""Status on the RFSoC4x2 board's 2x16 character OLED (NHD-0216AW, /dev/spidev1.0).

The session service owns the display; nothing else writes it while the service runs.
The vendor driver (rfsoc4x2.oled, PYNQ board package) is loaded on the first write,
in a background thread: a full two-line write takes about 0.5 s on the board, so
writes never block a session. Only the newest text is written; an unchanged text is
not written again. Without the driver or the device (a host test, another board)
the display is off and the service runs as before. This module touches no RF
hardware and is imported without the board package.
"""
import json
import math
import threading
import time

WIDTH = 16


def fit(line):
    """One display line: printable ASCII, cut or padded to 16 characters."""
    text = ''.join(c if 32 <= ord(c) < 127 else '?' for c in str(line))
    return text[:WIDTH].ljust(WIDTH)


def screen(top, bottom=''):
    return fit(top) + '\n' + fit(bottom)


def vendor_display():
    from rfsoc4x2 import oled   # board package; needs root for /dev/spidev1.0
    return oled.oled_display()


class Oled:
    """Latest-text-wins writer. ``factory`` returns an object with write(text)."""

    def __init__(self, factory=vendor_display, enabled=True, log=print):
        self.factory = factory
        self.enabled = enabled
        self.log = log
        self.error = ''
        self.written = None
        self._next = None
        self._wake = threading.Condition()
        self._stop = False
        self._thread = None
        if enabled:
            self._thread = threading.Thread(target=self._run, name='oled', daemon=True)
            self._thread.start()

    def show(self, top, bottom=''):
        if not self.enabled:
            return
        with self._wake:
            self._next = screen(top, bottom)
            self._wake.notify()

    def close(self, top=None, bottom='', wait=3):
        """Optionally write a last text, then stop the writer."""
        if top is not None:
            self.show(top, bottom)
        with self._wake:
            self._stop = True
            self._wake.notify()
        if self._thread is not None:
            self._thread.join(timeout=wait)

    def _run(self):
        device = None
        while True:
            with self._wake:
                while not self._stop and (self._next is None or self._next == self.written):
                    self._wake.wait()
                text = self._next
                if text is None or text == self.written:
                    return
            try:
                if device is None:
                    device = self.factory()
                device.write(text)
                self.written = text
            except Exception as exc:  # no driver, no device, no permission: display off
                self.error = '%s: %s' % (type(exc).__name__, exc)
                self.log('OLED off: ' + self.error, flush=True)
                self.enabled = False
                return
            with self._wake:
                if self._stop and self._next == self.written:
                    return


# -- texts -----------------------------------------------------------------
def idle_text(addresses, tick=0):
    """Idle: service name and one board address (rotating when there are several)."""
    address = addresses[tick % len(addresses)] if addresses else 'no network'
    return 'RFSoC4x2 BF idle', address


def starting_text(rf_mhz, elapsed):
    return 'Starting %dMHz' % rf_mhz, 'load+sync %4ds' % elapsed


def waiting_text(rf_mhz, dacs):
    return 'Ready %dMHz %s' % (rf_mhz, dacs), 'waiting for app'


def live_text(status, rf_mhz, dacs, now):
    """Streaming: EVM reported by the app (if any), RF, ADC peak and the DACs on."""
    age = now - status.get('time', 0)
    frames = status.get('frames', 0)
    if not status.get('streaming', True):
        top = 'PAUSED'
    elif age > 3 or not frames:
        top = 'no frames'
    else:
        evm = status.get('evm_percent')
        top = 'EVM %.2f%%' % evm if isinstance(evm, (int, float)) and math.isfinite(evm) else 'EVM --'
        top = top.ljust(12) + 'LIVE'
    rf = status.get('rf_mhz', rf_mhz)
    peak = status.get('adc_peak_dbfs')
    level = '%+.0fdB' % peak if isinstance(peak, (int, float)) and math.isfinite(peak) else '--dB'
    bottom = '%dMHz %s %s' % (round(rf), level, dacs)
    if len(bottom) > WIDTH:                     # e.g. -6000 MHz or -100 dB
        bottom = '%dM %s %s' % (round(rf), level, dacs)
    return top, bottom


def ended_text(summary):
    if summary.get('reason') == 'helper_failed' or summary.get('error'):
        return 'Board error', str(summary.get('error') or 'start failed')
    if not summary.get('dac_off_commanded'):
        return 'Ended', 'DAC OFF UNSURE!'
    frames = summary.get('frames', 0)
    count = '%d' % frames if frames < 100000 else '%dk' % (frames // 1000)
    return 'Session ended', 'DACs off %sfr' % count


def read_status(path):
    """The helper's status.json, or {} while it has none (or a partial one)."""
    try:
        status = json.loads(path.read_text())
        return status if isinstance(status, dict) else {}
    except (OSError, ValueError):
        return {}


def write_status(path, status):
    """Atomic write of the helper's live status (read by the service for the OLED)."""
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(dict(status, time=time.time())))
    tmp.replace(path)
