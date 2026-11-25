# The beamformer window

One resizable window, light theme by default (`theme dark` at start, or F7 / the
theme button live): a header, a row of readout tiles, six plots and a control
sidebar. All plots show the same captured frame. The code is
`origapp.BeamformerView` (drawing only) on top of the headless `origapp.DemoSession`.

## Header

- **☰ Controls / Hide controls** (F6) shows or hides the sidebar.
- The state pill: `LIVE`, `HELD`, `PAUSED`, `WAITING`, `STALE`, `NO DATA`,
  `STOPPED` or `IDLE`, then the frame number and its age.
- **Hold** (F3) freezes the plots on the current frame while the board keeps
  streaming. An invalid frame releases the hold and clears the display, so a held
  frame never hides a refused one. **Pause** (F8, sidebar) stops the board stream.
- **Snapshot** (F2) writes a PNG of the window and a MAT file with the shown frame,
  the accepted settings, the histories and the event log. Snapshots are
  measurements: keep them out of the repository.
- **Fit plots** (F5) restores the default limits and resets max hold. The view
  holds axis limits between redraws and changes them only when the data leaves
  them; a zoom or pan stays until Fit plots.
- **Dark / Light** (F7) switches the theme in place.

## Readout tiles

A coloured edge marks the state: green current, amber quality-flagged, red near
full scale, grey no current value.

| Tile | Value | Second line |
|---|---|---|
| Payload EVM | primary EVM over every complete burst, % | median / max of the history |
| EVM (dB) | the same in dB | header and pilot EVM |
| Output level | mean level of the analysed buffer, dBFS | highest raw ADC peak |
| Carrier offset | median training frequency offset | pilot timing drift, ppm |
| Sync peak | preamble correlation, 0..1 | training-row SNR |
| Bursts | qualified / complete | EVM of the qualified bursts only |
| Display rate | frames processed per second over the last 5 s | accepted / rejected frames |

## Plots

- **DOA spectrum** and **Receive pattern** carry a `MODEL` badge: they are
  quantities of the array model (uniform line, half a wavelength, isotropic
  elements), not calibrated directions. Markers name the beam direction and the
  other sources with their level. **Mirror** shows angle → −angle (as the antennas
  are mounted); it changes the display and the board OLED only.
- **Baseband spectrum** shades the signal bandwidth; **Max hold** keeps the
  per-bin maximum.
- **Time domain:** the selected output as a min/max envelope with burst starts
  (green complete, amber flagged), or **Stream phase** / **Stream level**: the
  frame-to-frame history of each ADC stream against ADC_D.
- **Constellation:** 16-QAM payload, BPSK header and pilots over the ideal points.
- **Payload EVM:** **History** (ringed points were flagged; the line breaks where
  frames were refused), **Per subcarrier** or **Per symbol** of the current frame;
  **%** / **dB**.

A refused, stale or paused frame blanks the current plots and writes the reason in
each. The EVM history stays and is marked as history.

## Sidebar

Always visible:

| Control | Choices | Hardware default |
|---|---|---|
| Start / Pause | start the session; stop and resume the board stream | running |
| Output | Combined beam, or one ADC (ADC_D, ADC_C, ADC_B, ADC_A) | Combined beam |
| Signal priority | OFDM (tracked), Strongest, Weaker | OFDM (tracked) |
| Beamformer | Without, Steering, OFDM pilot MVDR, MVDR, DMR, PC, PC_corr, LCMV, RVL, RAB PC, DL MVDR, DL ITER MVDR, QCB | OFDM pilot MVDR |
| DOA estimator | MVDR, MUSIC, Beamscan, MUSICR, ESPRITE, ESPRITEBS, WSFR, MVDRman, MVDRman_corr | MVDR |
| Data amount | 4096, 8192, 16384 or 32768 samples per frame | 4096 |
| Set 0° | common-feed calibration of the ADC phases and gains | not calibrated |
| Calibrate on | OFDM (wideband), CW tone | OFDM |

**OFDM (tracked)** points the beam at the direction whose signal carries the OFDM
preamble, whatever its power; **Strongest** and **Weaker** rank directions by the
power of a beam steered to each (Weaker refuses a scene with one source).
**OFDM pilot MVDR** takes the array response to the wanted signal from the
preamble and the noise and interference covariance from the quiet gaps around each
burst; without a usable preamble it uses the steering vector for that frame. The
other adaptive beamformers use the preamble-measured signature when the beam is on
the OFDM.

**Data amount:** the board sends fewer rows per frame for a higher frame rate;
4096 samples hold one complete OFDM frame. A reduced window is checked against the
transmitted loop at both ends; the full 32768-row window also gets the complete
continuity check.

**Set 0°** needs every ADC fed from the same source. It sets the ADC mixer phases
and gains until ADC_C, ADC_B and ADC_A match ADC_D (six frames, twice, then a
check) and shows the residual. The converters re-synchronise at every session
start and frequency change, so calibrate again after each. **CW tone** calibrates
on the strongest spectral line instead, for a CW fed to every ADC.

### DSP page

| Control | Default |
|---|---|
| Source count: Auto, 1, 2, 3 | 1 (Auto counts sources on every frame and shows `Auto · n`) |
| Scan width / scan step | 120° / 1° |
| Average frames | 10 |
| Signal bandwidth | 100 MHz |
| Adaptive IQ correction, static IQ correction | off |
| Phase / power correction | off (needs loaded steering and power tables) |

### RF page

ADC centre frequency, even Nyquist zone and Mirror (negative ADC mixer frequency);
DAC B and DAC A centre frequencies with their even Nyquist zones; **Apply
frequency** sends one `fc` command. DAC B power and DAC A power; **SYNC**: DAC = ADC
(the DACs play during each capture), DAC = DAC, free running. Converter paths: one
setting list (ADC/DAC mixer phase in 0.01°, ADC/DAC gain 0–1.99, ADC/DAC I/Q phase,
ADC attenuator 0–27 dB, DAC current 2.25–40.5 mA) with a field per connector and
**Apply**. **Load calibration…** reads steering and power tables. The fields start
from the values the board reports; an Apply button is highlighted while its fields
differ from what the board accepted. RF and phase changes clear the 0° calibration
and the averaging.

Streams 0..3 are ADC_D, ADC_C, ADC_B and ADC_A (RFSoC 4x2 manual rev A5; checked by
turning one ADC mixer phase at a time). DAC index 0 is DAC_B, index 2 DAC_A.

### Algorithms page

Diagonal loading, uncertainty, robust loading γ, iterations, mismatch angle,
algorithm step, IQ filter length and LMS step. The limits are the ones the session
accepts (`origapp.processingLimits`).

### Monitor page

Per stream: level (dBFS), phase and coherence against ADC_D, applied weight in dB
and degrees. Session counters by refusal type, the OFDM profile read from the setup
file, a time-stamped event log and **Clear histories**.

A refused control restores the previous value and shows the reason in the sidebar,
the status line and the event log.

## Layout

At desktop sizes the plots use three columns of stacked pairs (pattern under DOA,
time under spectrum, EVM under constellation); medium windows use two columns;
small windows scroll instead of clipping. The window opens on the primary monitor
and sizes itself correctly on monitors with another display scale.
