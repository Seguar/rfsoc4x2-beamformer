"""RFSoC4x2 adapter for legacy MATLAB commands; never import the hardware wrapper here."""
import threading
if __package__:
    from .control_service import parse_commands
else:
    from control_service import parse_commands


class BoardCommands:
    def __init__(self, overlay, dac, data_words, check_lock, set_output=None, allowed_words=None, both_dacs=False):
        self.overlay = overlay
        self.dac = int(dac)
        self.data_words = data_words
        self.allowed_words = tuple(allowed_words or (data_words,))
        self.check_lock = check_lock
        self.set_output = set_output
        self.both_dacs = bool(both_dacs)
        self.lock = threading.RLock()
        self.streaming = True
        self.revision = 0
        self.fault = None
        self.log = []

    def check(self):
        if self.fault:
            raise RuntimeError('Control operation failed; capture stopped: '+self.fault)

    def snapshot(self):
        o = self.overlay
        return dict(revision=self.revision, streaming=self.streaming,
                    data_words=self.data_words, da=int(o.da), dac_power=list(o.dacPower),
                    adc_mixers=[dict(o.adc[n].MixerSettings) for n in range(4)],
                    dac_mixers=[dict(o.dac[n].MixerSettings) for n in (0, 2)],
                    rf_off_verified=False)

    def apply(self, line):
        """Service holds lock. Validate entire batch before any hardware operation.

        dataChan (int16 lane words per frame) may only take a size the stream
        declared (allowed_words); the capture loop reads it for the next frame
        and the revision marks the change. An identical dataChan is a no-op.
        The unused DAC stays zero and cannot be selected by dacPow, unless the
        session was created with both_dacs (set_output then gets a mask).
        Wrapper fc/phase/dphase retain the original units, indexing and MTS calls.
        """
        cmds = parse_commands(line)
        for name, values in cmds:
            if name == 'dataChan' and values[0] not in self.allowed_words:
                raise ValueError('dataChan must be one of %s lane words for this stream'
                                 % '/'.join(map(str, self.allowed_words)))
            if name == 'dacPow':
                allowed = (0, 2) if self.both_dacs else ((0,) if self.dac == 0 else (2,))
                if any(v for n, v in enumerate(values) if n not in allowed):
                    raise ValueError('Only DAC index 0 (DAC_B) and 2 (DAC_A) exist' if self.both_dacs
                                     else 'Only the session-selected DAC can be enabled')
        self.check()
        changed = any(name != 'status' and (name, values) != ('dataChan', [self.data_words])
                      for name, values in cmds)
        try:
            for name, values in cmds:
                if name == 'status':
                    continue
                if name == 'dataChan':
                    self.data_words = values[0]
                    continue
                if name == 'dataStream':
                    self.streaming = bool(values[0])
                else:
                    if name in ('phase', 'dphase'):
                        values = [(v+180)%360-180 for v in values]
                    text = name+' '+ '/'.join(map(str, values))
                    self.overlay.handle_commands([text])
                    if name == 'dacPow':
                        if self.set_output is not None:
                            # both_dacs: (DAC_B, DAC_A) mask; else the selected DAC's state
                            self.set_output((bool(values[0]), bool(values[2])) if self.both_dacs
                                            else bool(values[0 if self.dac == 0 else 2]))
                        self.overlay.dacs_control()
            self.check_lock()
            if changed:
                self.revision += 1
            result = self.snapshot()
            self.log.append(dict(command=line, ok=True, revision=self.revision))
            self.log[:] = self.log[-2000:]
            return result
        except Exception as exc:
            # A driver can fail after partially applying a batch. Never continue
            # capturing or acknowledge success with uncertain hardware settings.
            self.fault = str(exc)
            self.log.append(dict(command=line, ok=False, error=self.fault))
            try:
                self.overlay.dacs_off()
            except Exception as off_error:
                self.fault += '; DAC disable also failed: '+str(off_error)
            raise
