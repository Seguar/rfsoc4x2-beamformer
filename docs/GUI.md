# Focused MATLAB interface

The default launcher layout is one resizable window with six measured views:
DOA spectrum, receive pattern, baseband spectrum, time-domain I/Q, constellation
and payload EVM. EVM is prominent in both percent and dB; its history retains
outliers and labels old values as history when the current acquisition is invalid.
All panels use the same admitted capture and the selected combined/channel buffer.

The sidebar has three groups:

- **RF:** acquisition start/pause, ADC/DAC center frequency, selected-DAC waveform
  enable, real ADC/DAC mixer phases and calibration-file loading.
- **DSP:** output channel, beamformer, DOA estimator, source count/priority, scan
  width/step, averaging, filter bandwidth, IQ and phase/power correction, and an
  optional native-VSA comparison.
- **Algorithms:** diagonal/robust loading, uncertainty, iteration count, mismatch
  width/step and IQ filter length/step. Reviewed-engine parameter controls map to
  the actual processing fields; changing loading is covered by a weight-change test.

Correction modes requiring data refuse activation until their filter or matching
calibration exists. RF/phase changes clear model calibration and plot averaging.
Automatic ADC calibration, ZCU216 controls, device/Arduino/generator launchers,
raw commands, debug switches, capture-memory size, converter clocks, cutter,
waveform upload and duplicate plot windows are omitted from this layout.

At normal desktop sizes the plots use three columns and two rows. Medium windows
use two columns; compact/short windows scroll rather than clip the plots. Controls
can be collapsed. Every axes has zoom/pan/data tips; **Fit plots** restores limits,
including constellation outliers. Curves are persistent objects updated per
acquisition, with no interpolated or duplicate measurement frames.

```powershell
py -3 tools/run_original_vsa.py --config <private-config.json> --i-own-board --layout clean --mode durable --max-seconds 1800
```

`clean` is the default. `--layout legacy` keeps the earlier original App Designer
interface available. The new view is code-based MATLAB (`BeamformerView`), backed
by a headless `DemoSession`; it does not instantiate a hidden old GUI. The legacy
`.mlapp` and matching export remain unchanged. Both layouts share the guarded
`Controller`, `LegacyVsaBackend`, `processLegacyFrame` and `OfdmAnalyzer` core.
The clean view always plots integrated OFDM metrics. `--analyzer both` or `vsa`
adds a separately labelled vendor comparison; native-only operation remains in
the legacy layout.

The acquisition format, thresholds and primary-EVM definition are unchanged.
Invalid/stale captures clear all current plots and values. OFDM-only failures
clear constellation/current EVM while admitted waveform/spatial diagnostics can
remain. Pause and applied settings clear current data immediately. Closing the
window closes its backend and releases the launcher's board session.

## Validation

**Test / How:** synthetic GUI/session fixtures exercise real resize events,
persistent graphics, user zoom, stale/blank rejection, callback rollback,
calibration readiness, applied command strings, DSP loading and cleanup. A bounded
DSP-hosted live run exercised the same view with RFSoC4x2 samples and real controls.

**Results:** both software fixtures pass with zero leaked figures/timers. The live
run accepted 16 frames, displayed all six panels and passed pause/resume, DAC phase
15°→0°, same-frequency RF apply and beamformer selection. Its final frame measured
5.23% EVM (−25.63 dB), six complete bursts including one quality-flagged burst.
An 18% history outlier was retained. Four frame rejections included startup stale/
expiry and settings-revision clearing. Earlier failed pause/callback checks were
retained and fixed before the passing run. Both DAC RAMs were cleared/read back,
outputs commanded off and shutdown reported no errors.

**Conclusions / Ways to resolve:** the redesigned interface works with real board
data. This is GUI/control validation, not a throughput benchmark. Current common
splitter wiring still provides uncalibrated model DOA/pattern, not physical angles,
beamforming gain or jammer rejection. Raw capture sample loss and streaming-speed
optimization remain separate work.
