"""Status on the RFSoC4x2 board's 2x16 character OLED (NHD-0216AW, /dev/spidev1.0).

The session service owns the display; nothing else writes it while the service runs.
The vendor driver (rfsoc4x2.oled, PYNQ board package) is loaded on the first write,
in a background thread, so writes never block a session. The driver waits 10 ms
after every byte and its string write clears the display first (about 0.47 s for
two lines, with a blink); a change is therefore written in place: cursor to the
first changed character, then only the changed characters (an EVM digit change
takes about 40 ms). A whole-screen write is used for the first text, when the
caller asks for it (a new state) and every FULL_EVERY seconds, in case another
program (boot.py, /boot/doa_mts.py on import) wrote or cleared the display. Only
the newest text is written; an unchanged text is not written again. Without the driver or the device (a host test, another board)
the display is off and the service runs as before. This module touches no RF
hardware and is imported without the board package.
"""
import json
import math
import os
import threading
import time

WIDTH = 16
DEVICE = '/dev/spidev1.0'
FULL_EVERY = 15.0      # s
LINE_ADDRESS = (0x00, 0x40)   # DDRAM address of each line (US2066, 2-line mode)


def fit(line):
    """One display line: printable ASCII, cut or padded to 16 characters."""
    text = ''.join(c if 32 <= ord(c) < 127 else '?' for c in str(line))
    return text[:WIDTH].ljust(WIDTH)


def screen(top, bottom=''):
    return fit(top) + '\n' + fit(bottom)


class VendorDisplay:
    """rfsoc4x2.oled with in-place writes through its own command/data calls."""

    def __init__(self):
        # The driver's init calls exit(2) when it cannot open the device, which would
        # end the whole service: check first and raise instead.
        if not os.access(DEVICE, os.R_OK | os.W_OK):
            raise OSError('%s is missing or not writable' % DEVICE)
        import ctypes
        from rfsoc4x2 import oled   # board package
        self.display = oled.oled_display()
        # the package's cffi declarations cannot call the byte functions (u_int8_t);
        # ctypes on the same library shares the device handle its init opened
        self.lib = ctypes.CDLL(oled._lib_location)
        for name in ('send_oled_cmd', 'send_oled_data'):
            getattr(self.lib, name).argtypes = [ctypes.c_uint8]
            getattr(self.lib, name).restype = None

    def write(self, text):
        self.display.write(text)

    def put(self, row, col, text):
        self.lib.send_oled_cmd(0x80 | (LINE_ADDRESS[row] + col))
        for c in text:
            self.lib.send_oled_data(ord(c))


def vendor_display():
    return VendorDisplay()


def changed_runs(old, new):
    """(row, col, text) pieces that turn screen ``old`` into ``new``. Changes one
    character apart are joined: rewriting it costs what a new cursor command costs."""
    runs = []
    for row, (a, b) in enumerate(zip(old.split('\n'), new.split('\n'))):
        diff = [k for k in range(WIDTH) if a[k] != b[k]]
        start = None
        for k in diff:
            if start is None:
                start = end = k
            elif k - end <= 2:
                end = k
            else:
                runs.append((row, start, b[start:end + 1]))
                start = end = k
        if start is not None:
            runs.append((row, start, b[start:end + 1]))
    return runs


class Oled:
    """Latest-text-wins writer. ``factory`` returns an object with write(text) and,
    optionally, put(row, col, text) for in-place writes."""

    def __init__(self, factory=vendor_display, enabled=True, log=print):
        self.factory = factory
        self.enabled = enabled
        self.log = log
        self.error = ''
        self.written = None
        self.full_at = -math.inf
        self.writes = dict(full=0, partial=0)
        self._next = None
        self._full = False
        self._wake = threading.Condition()
        self._stop = False
        self._thread = None
        if enabled:
            self._thread = threading.Thread(target=self._run, name='oled', daemon=True)
            self._thread.start()

    def show(self, top, bottom='', full=False):
        """Queue a text; ``full`` asks for a whole-screen write (a new state)."""
        if not self.enabled:
            return
        with self._wake:
            self._next = screen(top, bottom)
            self._full = self._full or full
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
                text, full = self._next, self._full
                self._full = False
                if text is None or text == self.written:
                    return
            try:
                if device is None:
                    device = self.factory()
                now = time.monotonic()
                if (full or self.written is None or not hasattr(device, 'put')
                        or now - self.full_at >= FULL_EVERY):
                    device.write(text)
                    self.full_at = now
                    self.writes['full'] += 1
                else:
                    for row, col, piece in changed_runs(self.written, text):
                        device.put(row, col, piece)
                    self.writes['partial'] += 1
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
    """Streaming: EVM and main (wanted) DOA reported by the app (if any), RF and the
    DACs on. The DOA took the place of the ADC peak level (user, 2026-11-23)."""
    age = now - status.get('time', 0)
    frames = status.get('frames', 0)
    if not status.get('streaming', True):
        top = 'PAUSED'
    elif age > 5 or not frames:
        top = 'no frames'
    else:
        evm = status.get('evm_percent')
        top = 'EVM %.2f%%' % evm if isinstance(evm, (int, float)) and math.isfinite(evm) else 'EVM --'
        top = top.ljust(12) + 'LIVE'
    rf = status.get('rf_mhz', rf_mhz)
    doa = status.get('doa_deg')
    known = isinstance(doa, (int, float)) and math.isfinite(doa) and status.get('streaming', True) and top != 'no frames'
    bottom = 'DOA%+.1f %d %s' % (doa, round(rf), dacs) if known else 'DOA -- %d %s' % (round(rf), dacs)
    if len(bottom) > WIDTH:                     # e.g. -6000 MHz or -100.0 deg
        bottom = 'DOA%+.0f %d %s' % (doa, round(rf), dacs) if known else 'DOA -- %d' % round(rf)
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
