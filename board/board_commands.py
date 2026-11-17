"""RFSoC4x2 adapter for legacy MATLAB commands; never import the hardware wrapper here."""
import threading
if __package__:
    from .control_service import parse_commands
else:
    from control_service import parse_commands


ADC_CONNECTORS = ('ADC_D', 'ADC_C', 'ADC_B', 'ADC_A')    # ADC index 0..3 (tile 224 b0/b1, 226 b0/b1)
DAC_CONNECTORS = {0: 'DAC_B', 2: 'DAC_A'}                # DAC index (tile 228, 230)
EVNT_SRC_TILE, EVENT_MIXER, EVENT_QMC = 2, 1, 4          # xrfdc constants (no xrfdc import here)
WRAPPER_QMC_GAIN = 1.99                                  # /boot wrapper writes this on every configure
WRAPPER_VOP_UA = 40500
PATH_COMMANDS = ('phasec', 'dphasec', 'again', 'dgain', 'aiqphase', 'diqphase', 'adsa', 'dvop')


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
        # Converter path settings kept here: the /boot wrapper rewrites QMC gain 1.99,
        # no I/Q phase and maximum DAC current whenever fc/phase/dphase reconfigure
        # the converters, so they are written again after every such command.
        self.adc_gain = [WRAPPER_QMC_GAIN] * 4
        self.adc_iq = [0.0] * 4
        self.adc_dsa = [None] * 4               # None: left as the board started
        self.dac_gain = {0: WRAPPER_QMC_GAIN, 2: WRAPPER_QMC_GAIN}
        self.dac_iq = {0: 0.0, 2: 0.0}
        self.dac_vop = {0: WRAPPER_VOP_UA, 2: WRAPPER_VOP_UA}

    def check(self):
        if self.fault:
            raise RuntimeError('Control operation failed; capture stopped: '+self.fault)

    def snapshot(self):
        o = self.overlay
        return dict(revision=self.revision, streaming=self.streaming,
                    data_words=self.data_words, da=int(o.da), dac_power=list(o.dacPower),
                    adc_mixers=[dict(o.adc[n].MixerSettings) for n in range(4)],
                    dac_mixers=[dict(o.dac[n].MixerSettings) for n in (0, 2)],
                    adc_phase=[float(v) for v in o.phases], dac_phase=[float(o.d_phases[n]) for n in (0, 2)],
                    adc_connectors=list(ADC_CONNECTORS), dac_connectors=[DAC_CONNECTORS[0], DAC_CONNECTORS[2]],
                    adc_gain=list(self.adc_gain), adc_iq_phase=list(self.adc_iq),
                    adc_attenuation=[self._dsa(n) for n in range(4)],
                    dac_gain=[self.dac_gain[0], self.dac_gain[2]], dac_iq_phase=[self.dac_iq[0], self.dac_iq[2]],
                    dac_current_ua=[self.dac_vop[0], self.dac_vop[2]],
                    rf_off_verified=False)

    def _dsa(self, n):
        try:
            return float(self.overlay.adc[n].DSA['Attenuation'])
        except Exception:
            return None

    def _qmc(self, block, gain, iq):
        block.QMCSettings = {'EnablePhase': 1, 'EnableGain': 1, 'GainCorrectionFactor': float(gain),
                             'PhaseCorrectionFactor': float(iq), 'OffsetCorrectionFactor': 0,
                             'EventSource': EVNT_SRC_TILE}
        block.UpdateEvent(EVENT_QMC)

    @staticmethod
    def _mixer_phase(block, degrees):
        settings = dict(block.MixerSettings)
        settings.update(PhaseOffset=float(degrees), EventSource=EVNT_SRC_TILE)
        block.MixerSettings = settings
        block.UpdateEvent(EVENT_MIXER)

    def _write_paths(self):
        """(Re)write every stored path setting to the converters."""
        o = self.overlay
        for n in range(4):
            self._qmc(o.adc[n], self.adc_gain[n], self.adc_iq[n])
            if self.adc_dsa[n] is not None:
                o.adc[n].DSA = {'DisableRTS': 0, 'Attenuation': float(self.adc_dsa[n])}
        for n in (0, 2):
            self._qmc(o.dac[n], self.dac_gain[n], self.dac_iq[n])
            o.dac[n].SetDACVOP(int(self.dac_vop[n]))

    def _path(self, name, values):
        o = self.overlay
        if name in ('phasec', 'dphasec'):
            values = [(v + 18000) % 36000 - 18000 for v in values]
        if name == 'phasec':
            # Fine mixer phase offset only, applied at once on the running NCOs: no NCO
            # reset and no tile re-synchronisation (the wrapper's phase command does both,
            # and its re-sync moved tile 226 against tile 224 by 144 deg in a live test).
            o.phases = [v / 100 for v in values]    # kept for later wrapper reconfiguration
            for n in range(4):
                self._mixer_phase(o.adc[n], o.phases[n])
        elif name == 'dphasec':
            o.d_phases = [v / 100 for v in values]
            for n in (0, 2):
                self._mixer_phase(o.dac[n], o.d_phases[n])
        elif name == 'again':
            self.adc_gain = [v / 100 for v in values]
        elif name == 'aiqphase':
            self.adc_iq = [v / 100 for v in values]
        elif name == 'adsa':
            self.adc_dsa = [float(v) for v in values]
        elif name == 'dgain':
            self.dac_gain = {n: values[n] / 100 for n in (0, 2)}
        elif name == 'diqphase':
            self.dac_iq = {n: values[n] / 100 for n in (0, 2)}
        elif name == 'dvop':
            if not all(values[n] for n in (0, 2)):
                raise ValueError('dvop needs a current for DAC index 0 (DAC_B) and 2 (DAC_A)')
            self.dac_vop = {n: values[n] for n in (0, 2)}
        self._write_paths()

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
            if name == 'dvop' and not all(values[n] for n in (0, 2)):
                raise ValueError('dvop needs a current for DAC index 0 (DAC_B) and 2 (DAC_A)')
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
                elif name in PATH_COMMANDS:
                    self._path(name, values)
                else:
                    if name in ('phase', 'dphase'):
                        values = [(v+180)%360-180 for v in values]
                    text = name+' '+ '/'.join(map(str, values))
                    self.overlay.handle_commands([text])
                    if name in ('fc', 'phase', 'dphase'):
                        self._write_paths()     # the wrapper reset QMC gain/phase and DAC current
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
