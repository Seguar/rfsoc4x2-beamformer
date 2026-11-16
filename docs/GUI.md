# Focused MATLAB interface

The default launcher layout is one resizable dark window: a header with the
acquisition state, a row of readout tiles, six measured views and a control
sidebar. The six views are DOA spectrum, receive pattern, baseband spectrum,
time domain, constellation and payload EVM. All panels use the same admitted
capture and the selected combined/channel buffer.

## Readouts

Seven tiles show numbers the analyzer and session already compute; none is new
DSP. A coloured edge marks state only (green current, amber quality-flagged, red
near full scale, grey no current value).

| Tile | Value | Second line |
|---|---|---|
| Payload EVM | primary EVM, all complete bursts, % | median / max of the retained history |
| EVM (dB) | same metric in dB | header and pilot EVM |
| Output level | mean level of the analysed buffer, dBFS | highest raw ADC peak; count of samples at full scale |
| Carrier offset | median training CFO | pilot timing drift along the burst, ppm |
| Sync peak | own preamble correlation, 0..1 | median training-row SNR estimate |
| Bursts | qualified / complete | clean-only EVM (secondary metric) |
| Display rate | fresh frames drawn per second | accepted / rejected acquisition counters |

In the shared-clock loopback the timing drift is a slip indicator, not an
oscillator offset. The sync peak is this repository's metric, not the vendor's.

## Plots

- **DOA spectrum / receive pattern** carry a permanent `MODEL` badge and dashed
  markers labelled `model x°` at the estimated angles. They are array-model
  quantities; no beamwidth, null depth or gain number is derived.
- **Baseband spectrum** shades the configured signal bandwidth, reports the 99 %
  power width and has an optional **Max hold** trace (reset by Fit plots, a
  cleared display or Clear histories).
- **Time domain** draws a min/max envelope per display bin, so no peak is lost to
  decimation, with markers at detected burst starts (green complete and
  qualified, amber flagged or incomplete). Its selector switches to **Stream
  phase** or **Stream level**: frame-to-frame history of each raw receive stream
  against the first measured one. This is the view for checking ADC alignment
  after an initialization; it describes the conducted path, not arrival angles.
- **Constellation** separates payload, header and pilots by colour and shape over
  ideal 16QAM rings and decision boundaries.
- **Payload EVM** has a **% / dB** switch for the graph (the same stored values,
  20·log10) and a selector: **History** (ringed points were quality-flagged, the
  dotted line is the median, and the line is broken wherever an acquisition was
  rejected or skipped), **Per subcarrier** or **Per symbol** of the current frame.

A rejected, stale or paused acquisition blanks the current plots and writes the
reason inside each one; the EVM history stays and is labelled history only.

## Header actions

- **Hold** (F3) freezes the plots on the current frame for inspection while the
  board keeps streaming. The state pill, status line and window title say `HELD`
  / `NOT LIVE`, and any invalid acquisition releases the hold and clears the
  display, so a held frame can never mask a rejected one. Pause, by contrast,
  stops the board stream.
- **Snapshot** (F2) writes a PNG of the window and a MAT file with the displayed
  snapshot struct, accepted settings, histories and event log. It goes to
  `<outputDir>/snapshots` when the launcher sets an output folder, otherwise to a
  folder chosen once. Snapshots are measurements: keep them out of the repository.
- **Fit plots** (F5) restores default limits; F6 toggles the sidebar, F8 pauses.
- **Light / Dark** (F7) switches the theme live; `cfg.theme` selects the start-up
  theme. Every object is recoloured in place, nothing is rebuilt.

## Sidebar

Four pages, switched by the segmented control:

- **RF:** ADC/DAC center frequency, selected-DAC waveform enable, real ADC/DAC
  mixer phases and calibration-file loading. An Apply button is highlighted while
  its fields differ from the last values the board accepted.
- **DSP:** output channel, beamformer, DOA estimator, source count/priority, scan
  width/step, averaging, filter bandwidth, IQ and phase/power correction, and an
  optional native-VSA comparison.
- **Algorithms:** diagonal/robust loading, uncertainty, iteration count, mismatch
  width/step and IQ filter length/step. Reviewed-engine parameter controls map to
  the actual processing fields; changing loading is covered by a weight-change test.
- **Monitor:** per-stream table (level, phase and coherence against the first
  measured stream, applied weight in dB and degrees), acquisition counters by
  rejection type, native-VSA comparison, OFDM profile and a time-stamped event log
  of state changes, applied or refused controls and quality-flagged frames.

Start/Pause stay above the pages. A refused control restores the previous value
and shows the reason in the sidebar, the status line and the event log.

Correction modes requiring data refuse activation until their filter or matching
calibration exists. RF/phase changes clear model calibration and plot averaging.
Automatic ADC calibration, ZCU216 controls, device/Arduino/generator launchers,
raw commands, debug switches, capture-memory size, converter clocks, cutter,
waveform upload and duplicate plot windows are omitted from this layout.

At normal desktop sizes the plots use three columns of stacked pairs: receive
pattern under the DOA spectrum, time domain under the baseband spectrum and
payload EVM under the constellation. Medium windows
use two columns; compact/short windows scroll rather than clip the plots, and the
tiles wrap to two rows. Controls can be collapsed. Every axes has zoom/pan/data
tips; **Fit plots** restores limits, including constellation outliers. All curves,
markers and labels are persistent objects updated per acquisition, with no
interpolated or duplicate measurement frames; switching a plot mode creates none.

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

**Test / How:** synthetic GUI/session fixtures on a MATLAB host exercise real
resize events and the stacked-pair layout, persistent graphics (constant object
count across frames, plot modes and theme switches), readout tiles, per-stream
table, model-angle and burst markers, EVM percent/dB and per-subcarrier/per-row
modes, broken history lines, view-only hold and its release on an invalid
acquisition, function keys, exact dark/light/dark colour round trip, snapshot
contents, stale/blank rejection, callback rollback, calibration readiness and
cleanup. Three design advisers and four reviewers with independent verification
checked the change; every confirmed finding was fixed and given an assertion.
A bounded DSP-hosted live run then exercised the same view with RFSoC4x2 samples.

**Results:** both software fixtures pass with zero leaked figures/timers; a full
redraw of a 32768-sample frame took about 61 ms on the fixture host. The live run
accepted 51 frames and passed pause/resume, DAC phase 15°→0°, same-frequency RF
apply, beamformer selection, hold (kept its frame while two more were accepted),
diagnostic plot modes, monitor page and snapshot. Displayed EVM was about 4.8 %
(−26.3 dB) on typical frames; the last frame of the run was quality-flagged at
11.1 % with 2 of 5 bursts qualified, and such frames stay in the history. Eight
rejections were logged (5 expired, 2 no signal, 1 stale); the event log names the
timing-step burst behind each flagged frame. Per-stream phase against stream 0
stayed within 0.9° over 48 retained frames of that one initialization. Both DAC
RAMs were cleared/read back, outputs commanded off and shutdown reported no errors.

**Conclusions / Ways to resolve:** the redesigned interface works with real board
data and makes the known capture sample slips visible per frame. This is
GUI/control validation, not a throughput benchmark, and one initialization says
nothing about phase repeatability across initializations. Current common
splitter wiring still provides uncalibrated model DOA/pattern, not physical angles,
beamforming gain or jammer rejection. Raw capture sample loss and streaming-speed
optimization remain separate work.
