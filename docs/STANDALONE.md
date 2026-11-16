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
| `RFSoCBeamformer.exe` or `RFSoCBeamformer.exe demo` | **Simulation, no hardware.** A synthetic four-element array receives the reference OFDM loop from a model angle that sweeps ±20°. The real session, DSP and view run on it. |
| `RFSoCBeamformer.exe <frontend.json>` | **Hardware session.** The JSON is the one `tools/run_original_vsa.py` writes; the launcher owns the board helper and its shutdown. |

Optional name/value pairs after the first argument:

- `seconds N` closes the window after N seconds.
- `snapshot DIR` saves one snapshot (PNG and MAT) under `DIR/snapshots` before closing.
- `theme dark|light` selects the start-up theme.
- `interferer DB` (demo only) adds a simulated interferer at −50° model angle,
  `DB` below the wanted source, for example `interferer -15`. The session's
  single-source DOA estimate can then lock to either source, so it is off by default.

The first start takes longer while the runtime unpacks the application. The
window has no console: a start-up failure opens a dialog and writes
`%TEMP%\RFSoCBeamformer-error.log`.

With hardware, the launcher starts the compiled window instead of MATLAB:

```powershell
py -3 tools/run_original_vsa.py --config <private-config.json> --i-own-board --mode durable --max-seconds 1800 --standalone C:\path\RFSoCBeamformer.exe
```

The launcher still needs its private configuration, board access and the
`vsa_rfsoc` checkout; only the MATLAB installation is replaced.

## Limits

- Windows x64 only, clean layout only. The legacy App Designer layout and the
  native-VSA comparison need MATLAB.
- The Antenna Toolbox patch element cannot be deployed. The standalone uses
  isotropic model elements and adds `isotropic elements` to the scope label.
- The simulation shows the processing chain on synthetic frames. It is not a
  measurement of the board, an antenna or interference rejection.
- The application packages the `vsa_rfsoc` processing functions, the matched
  OFDM setup file and the reference loop; it contains no board address,
  credential, calibration or measurement.

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
