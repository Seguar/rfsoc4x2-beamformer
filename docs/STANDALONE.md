# Standalone application

`RFSoCBeamformer.exe` is the focused MATLAB interface ([GUI.md](GUI.md)) compiled
with MATLAB Compiler. It needs no MATLAB licence, only the free
[MATLAB Runtime R2025b](https://www.mathworks.com/products/compiler/matlab-runtime.html)
for Windows. Download it from the repository's Releases page. Two builds are
attached: `win64` (MATLAB Runtime R2025b) and `win64-r2026a` (MATLAB Runtime
R2026a, or an installed MATLAB R2026a with its `bin\win64` folder first on PATH
for the launched process).

## Run

| Command | What it does |
|---|---|
| `RFSoCBeamformer.exe` (double-click) | **Hardware session, board found automatically.** The search order is below. Needs the [board session service](BOARD_SERVICE.md), installed once. |
| `RFSoCBeamformer.exe demo` | **Simulation, no hardware.** A synthetic four-element array receives the reference OFDM loop from a model angle that sweeps ±20°. The real session, DSP and view run on it. |
| `RFSoCBeamformer.exe <frontend.json>` | **Hardware session owned by the launcher.** The JSON is the one `tools/run_original_vsa.py` writes; the launcher owns the board helper and its shutdown. |

Board search, in this order; the first address whose service answers is used:

1. **USB:** `192.168.3.1`, the board's USB network address.
2. **Ethernet:** the last address that worked, then `192.168.2.99` (the board's
   static address), then a broadcast on every local network of the PC.
3. **Address window:** if no board answers, a window asks for the board's IP
   address. It also offers the simulation. A failed connection returns to this
   window with the board's message, for example that a notebook kernel is running.

Starting the session takes about 10 s (FPGA image load and converter
synchronisation); a progress window with Cancel is shown. The session then
transmits the reference loop from DAC_B at 5.2 GHz by default at DAC peak code
24000 (the board checks ADC headroom at start); the RF page starts with the frequencies and Nyquist zones
the board reports ([RF_PROFILES.md](RF_PROFILES.md)). Closing the window stops the board session and
switches the DAC outputs off; the application reports an error if the board does
not confirm it. A session ends by itself after 4 hours or 200000 frames.

An address that worked, other than the USB one, is stored in
`%APPDATA%\RFSoCBeamformer\board.txt`. Each hardware run keeps its settings and
command log in `%LOCALAPPDATA%\RFSoCBeamformer\runs` (newest 10 kept).

Optional name/value pairs:

- `board ADDRESS` skips the search and uses this address.
- `dialog off` never opens the address window; the application fails instead.
- `seconds N` closes the window after N seconds.
- `rows N` starts with N samples per frame (32768, 16384, 8192 or 4096; default 4096), as the
  Data amount control.
- `calibrate on` runs Set 0° once the first frame arrives (common-feed calibration).
- `record <folder>` writes every received window, a frame log and a per-frame
  demodulation log there (diagnostics; keep them out of the repository).
- `snapshot DIR` saves one snapshot (PNG and MAT) under `DIR/snapshots` before closing.
- `theme dark|light` selects the start-up theme (light by default).
- `interferer DB` (demo only) adds a simulated interferer at −50° model angle,
  `DB` below the wanted source, for example `interferer -15`. The session's
  single-source DOA estimate can then lock to either source, so it is off by default.

The first start takes longer while the runtime unpacks the application. The
window has no console: a start-up failure opens a dialog and writes
`%TEMP%\RFSoCBeamformer-error.log`.

With the launcher instead of the board service, the compiled window replaces MATLAB:

```powershell
py -3 tools/run_original_vsa.py --config <private-config.json> --i-own-board --mode durable --max-seconds 1800 --standalone C:\path\RFSoCBeamformer.exe
```

The launcher needs its private configuration, board access and the `vsa_rfsoc`
checkout.

## OFDM pilot MVDR

For a four-channel capture, select **Combined beam**, **OFDM (tracked)** and
**OFDM pilot MVDR**. This receive mode measures the relative amplitude and phase
of the wanted signal at the four ADCs using the known OFDM preamble. It estimates
the noise and interference covariance from short gaps beside synchronized bursts.
The same complex weights apply to the complete frame, including its payload.
A frame with insufficient gap samples or no synchronized preamble is refused.
The preamble is found with a spatially adaptive correlation (the best receive
beam at each position), so a jammer stronger than the wanted signal no longer
hides it.

## Adaptive beamformers on an uncalibrated array

MVDR, DMR, PC, PC_corr, LCMV, RVL, RAB PC, DL MVDR and DL ITER MVDR keep a unit
response to a wanted array signature and suppress everything else. With the
model steering vector of an uncalibrated over-the-air array (per-ADC phases tens
of degrees and gains several dB apart), they cancelled the strong wanted signal:
MVDR, DMR, RAB PC and DL ITER MVDR never locked on real 4.85 GHz frames. When the
beam direction carries the OFDM preamble, these modes now use the signature
measured on the preamble (training samples only), if it agrees with the model at
the beam angle (|cos| >= 0.7). A beam on another source (Strongest on a jammer)
keeps the model vector. Steering, Without and QCB are unchanged.

Replay of 40 real frames (dmasync image, 4.85 GHz OTA, one OFDM source near 0°)
with an injected CW, median EVM of locked frames, 2026-11-23:

| Beamformer | One source | CW +10 dB at −42° | CW −10 dB at −42° | CW +10 dB at +30° |
|---|---|---|---|---|
| Steering | 7.1 % | 50.0 % | 10.2 % | 23.0 % |
| OFDM pilot MVDR | 6.8 % | 6.9 % (was refused) | 6.9 % | 6.8 % (was refused) |
| LCMV | needs a second direction | 6.9 % (was 8.2) | 7.1 % (was 27.7) | 6.8 % (was 9.6) |
| DL MVDR | 7.1 % (was 40.7) | 7.4 % (was 11.0) | 7.4 % (was 39.2) | 7.2 % (was 11.3) |
| DL ITER MVDR | 6.9 % (never locked) | 7.4 % | 7.3 % | 7.2 % |
| MVDR | 13.6 % (never locked) | 11.6 % | 11.8 % | 11.6 % |

Unloaded MVDR and DMR stay near 12 %: the wideband over-the-air signal is not
exactly one narrowband signature, and without loading they suppress part of it.
Use DL MVDR, LCMV or OFDM pilot MVDR against a jammer.

## Signal priority

**Strongest** and **Weaker** rank the detected directions by the band power of a
beam steered to each (Source count 2). **Weaker** needs a real second source: with
one source the estimators still return a second direction on its own sidelobe
(about −14 dB), so a frame whose second covariance eigenvalue is less than 3 dB
above the noise ones is refused ("only one source present"). One OFDM source alone
measured 1.7-2.1 dB; a CW 20 dB below it 4.4 dB. **OFDM (tracked)** picks the
direction carrying the OFDM preamble whatever its power. Beamscan cannot resolve a
weak source near a strong one (its second direction can be a sidelobe even with a
real jammer); use MUSIC or MVDR for the DOA with two sources.

## Frame rate

Every frame the board sends is processed (beamforming, DOA, EVM, the board OLED,
the EVM and channel histories); the window is redrawn at most every
`displayPeriodSeconds` (0.1 s, so up to 10 redraws per second). The frames/s
tile counts processed frames.

A redraw is rendering time in MATLAB's app window, not app code. Measured with
synthetic 4096-sample frames on the laptop (R2026a, 175 % display): about 17 ms
processing and 7 ms of view code per frame, then about 60 ms of rendering per
redraw. A third of that rendering was MATLAB recomputing automatic axis limits:
on average one axis limit changed on every other redraw. The view now sets the
time, spectrum and EVM limits itself and changes them only when the data leaves
them or uses less than half of them (once in 50 redraws). A limit you zoom or pan
stays until **Fit plots**.

| Synthetic frames | Render per redraw (median) | Frames/s, redraw every 0.1 s | Frames/s, redraw every 0.2 s |
|---|---|---|---|
| Laptop, automatic limits (v0.6.7) | 61 ms | 29 | 43 |
| Laptop, all limits fixed (experiment) | 40 ms | 42 | 52 |
| Build server, automatic limits, 2 runs | 72 and 76 ms | 17, 18 | 19, 24 |
| Build server, limits held by the view, 2 runs | 50 and 54 ms | 17, 18 | 24, 26 |

The build server processes frames more slowly, so its frame rates are lower and
noisier. With the limits held, ten redraws per second cost about what five did
before; the redraw interval is now 0.1 s. The live rate is lower than these
numbers: frames also have to arrive and be decoded. Hiding the axes toolbars or
turning off zoom and pan saved under 4 ms per redraw and is not done.

## Limits

- Windows x64 only, clean layout only. The legacy App Designer layout and the
  native-VSA comparison need MATLAB.
- The Antenna Toolbox patch element cannot be deployed. The standalone uses
  isotropic model elements and adds `isotropic elements` to the scope label.
- The simulation shows the processing chain on synthetic frames. It is not a
  measurement of the board, an antenna or interference rejection.
- The application packages the `vsa_rfsoc` processing functions, the matched
  OFDM setup file and the reference loop. It contains no credential, calibration
  or measurement; the only addresses in it are the two PYNQ defaults above.
- The automatic hardware session uses isotropic model elements and the
  common-feed diagnostic scope, as the launcher's `--standalone` path does.

## Build

Needs MATLAB with MATLAB Compiler on Windows. Build from a neutral folder,
because folder names end up inside the application archive.

```matlab
addpath('matlab/standalone');
buildStandalone('<vsa_rfsoc checkout>','<legacy_ref125.mat>','<build folder outside the repository>');
```

`legacy_ref125.mat` is written by `tools/legacy_reference.py`. From source, the
same entry point runs with `RFSOC_DEMO_SETX` and `RFSOC_DEMO_REFERENCE` set and
the `vsa_rfsoc/Functions` folder on the path; `validateStandaloneDemo` checks it.

## Validation

**Test / How:** `validateStandaloneDemo` runs the entry point from source in
simulation mode and checks accepted frames, demodulation, that the model angle
follows the simulated angle, the snapshot and refusal of bad arguments. The
compiled v0.1.0 binary was then started twice on the MATLAB host: in simulation
mode, and against the RFSoC4x2 with the existing board helper at the usual low
DAC level.

**Results:** from source the model angle matched the simulated angle within 1°
at 0.45 % EVM. The compiled simulation run exited 0 and wrote its snapshot. The
compiled hardware run exited 0 with 38 accepted frames and 4 logged rejections
(stale or expired frames), wrote its snapshot, and the helper then cleared both
DAC RAMs and commanded both outputs off without shutdown errors.

**Conclusions / Ways to resolve:** the compiled window works with simulated and
real board samples on the build host, which has MATLAB installed. A machine with
only the MATLAB Runtime was not tested. The R2026a build also ran in simulation
mode on a second Windows machine against its installed MATLAB R2026a, with no
runtime: window up within about 3 minutes on first start, plots updating, no
errors. The launcher's `--standalone` option was
exercised only through its settings format, not by a full launcher run.

The automatic board search and the board session service were validated
separately; see [BOARD_SERVICE.md](BOARD_SERVICE.md).
