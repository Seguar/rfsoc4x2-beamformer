# Control and algorithm map: VSA_rfsoc_exported → VSA_rfsoc_refactor_exported

Reference: the original export (1796 lines, last changed in commit 7acb76d) and the
`rfsocBf.m` revision it calls. The working-tree `rfsocBf.m` (HEAD 0805c99) has a different
signature: since 1ed93ac a `num` argument comes after `ang_num`, plus calibration arguments.
With it, every argument after `ang_num` shifts by one position, so the original app does
not run against HEAD. The 29-argument call matches **45e726b** (2025-01-14), and the port
follows that revision. The parent DGX repo has no `Functions/rfsocBf.m`. On the laptop the
file sits at the repo root, not in `Functions/`.

Legend: **kept** = same behaviour; **gated** = kept but needs an explicit cfg permission;
**changed** = deliberate, documented difference; **explicit error** = original failed
silently, now shows the reason and clears the display; **unreachable** = orphan code in
the original.

## Controls (all 119 components are created by the copied original createComponents)

| Control | Original | Refactor |
|---|---|---|
| Reset (state button) | sets `reset_req` for the endless loop | **changed**: explicit start: reset + `startAcquisition`; status if no backend |
| VSA checkbox | send beamformed sum to VSA DirectDataSource | **kept** through `backend.vsaSend`; note if the backend lacks it |
| Avg spinner, Plot, Debug | averaging depth, plot on/off, timing prints | **kept** |
| Custom command | appended to command queue | **gated** (`allowBoardCommands`) |
| Main: Channel select, BF type, DOA type, DOA resolution, Signal priority | | **kept**; see algorithm tables |
| System: RFSoC Fc / Fs, Sig BW, Max signals, Scan BW | state + `fc` command / part reset | **kept**; `fc` command **gated**. Max signals now rebuilds the estimator (original left NumSignals stale until another reset) |
| System: Load VSA setup | `uigetfile` + `vsaSetup` via VISA | **gated** (`allowExternalWindows`); file goes to `backend.vsaReset` |
| System: Even Nyquist (ADC/DAC), Mirror, RFSoC Fc DAC, Angle, dataStream, SYNC, Power (DAC), Recalibrate ADCs, Sync, DAC signal / Fc / Fe | board commands `fc`, `dphase`, `dataStream`, `da`, `dacPow`, `cal 8`, `sync 1`, `source` | **gated**: same command strings, queued, sent at part reset only with `allowBoardCommands` |
| System: Resample, Filter, Orig FS, Filt BW | state for the DAC-file loader | **kept** as state; the loader buttons are **unreachable** in the original (see below) |
| System: generator Fc / Gain / Mod / Power | `genCtrl` to a hard-coded instrument name | **gated** (`allowInstrumentCommands` + `cfg.generator.address`); no address in code |
| System: SR field | no callback wired in the original | **kept** as is (does nothing) |
| Downconverter: Start phase calibrations, Start/Step angle, gauge | blocking `uiwait` inside the loop; deleted `.\phase_cal` in the repo (`rmdir 's'`); loaded angle(1) for every k; called `phase_pattern_generator` with 6 arguments (it takes 4) | **changed**: non-blocking; each press captures the next frame; writes a new stamped folder under `cfg.outputDir`; loads each angle; calls with the 4 arguments the function accepts |
| Downconverter: Arduino program | `arduino_prog` | **gated** (`allowInstrumentCommands`) |
| Debug: GetPattern, MatlabPattern + UpdRate, GetSpectrum | `plotResponse` / `plotSpectrum` new figures | **gated** (`allowExternalWindows`); figures are tracked and deleted with the app |
| Debug: Pluto, IQtools | open other apps | **gated** (`allowExternalWindows`; IQtools needs `cfg.iqtoolsPath`, not in the repo) |
| Debug: Save + Number of saved files | `uiputfile` into the repo `Signals` | **changed**: stamped file under `cfg.outputDir` |
| Debug: dataChan, Cut offset, Cutter, DLF, BW, mis_ang, alg_scan_res, gamma, alpha, iter, c1, c2, patternCorr | algorithm parameters | **kept**; c1 and patternCorr need calibration (below) |
| Window close | none (figure deleted, loop kept running) | **changed**: `CloseRequestFcn` deletes the app: timer, backend and figures |
| Unwired callbacks: `LoadSignalButton(_2)Pushed`, `PowerCheckBox_3`, `PhaseSpinner_2`, `RFSoCFcSpinner_3`, `EvenNyquistZoneCheckBox_3`, `SREditField` | no component calls them | **unreachable**: dropped; DAC custom-file upload is pending |

## DOA modes (DOA type list)

| Mode | Original | Refactor |
|---|---|---|
| MVDR, MUSIC, Beamscan | phased estimator, spectrum + angles | **kept** |
| MUSICR, ESPRITE, ESPRITEBS | angles only; spectrum zeros (plotted as NaN) | **kept**; title says "no spectrum" |
| WSFR | listed, but commented out in `doaEst`, which **silently built MVDR** | **changed**: `phased.RootWSFEstimator` (exists in R2026a) |
| MVDRman | manual MVDR needs `pow_claibration_intrp`, which the app never passed → silent error loop | **explicit error** without `cfg.calibration.powCalibration`; formula of 45e726b with it |
| MVDRman_corr | as above + `steering_correction.mat` from the current folder | **explicit error** without `powCalibration` and `steeringCorrection` |
| (all) | the 4x4 covariance is passed to the estimators as four snapshots | **kept** as an original quirk, labelled |

## Beamformer modes (BF type list), cfg.bfEngine = "original"

| Mode | Refactor outcome on the fixture | Note |
|---|---|---|
| Without, Steering, MVDR, DMR, PC, LCMV, RVL, RAB PC, DL MVDR, DL ITER MVDR, QCB | run (original `Functions/`) | see REPORT: under the app's own pattern display, only Steering, PC and DL MVDR put their maximum near the wanted angle. MVDR (same `mvdrBf` as DL MVDR plus an extra `conj`) does not. This is an original conjugation inconsistency, kept and not fixed |
| PC_corr | **explicit error** | original passes a 5th argument to `pc_beamformer(…4 args)` → failed silently |
| LCMV | needs 2 directions, else **explicit error** | |
| RAB PC, DL ITER MVDR | Optimization Toolbox; `nonconvex_rab` uses unseeded `rand`/`randn` | not deterministic |

`cfg.bfEngine = "reviewed"` (explicit, shown in the pattern title) runs all 12 names through
the reviewed `rfsoc.beamform`, with the app's own phased.ULA steering as the manifold. This
includes PC_corr (needs `reviewed.pcCorrection`). It is an alternative, not a silent
substitute.

## Calibration-dependent switches

- `c1`: in 45e726b it means "apply the phase/power calibration table" (the estimator
  indexed as a table) and works only with MVDRman_corr. Otherwise it is an **explicit
  error**.
- `patternCorr`: needs `koef` (`cfg.calibration.koef` or `originalRepoPath/koef.mat`),
  else **explicit error**.
