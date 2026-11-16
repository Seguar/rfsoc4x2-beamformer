# Dependency inventory (original app and refactor)

Checked on the laptop (MATLAB R2026a Update 5) on 2026-11-15. The vsa_rfsoc checkout is
read-only: a1 did not edit, commit or stash anything there. The user's uncommitted
calibration `.mat` changes and untracked `phase_cal*` files were left as they were.

## rfsocBf (the helper the parent could not find)

- Parent DGX repo: there is no `Functions/rfsocBf.m`. The laptop checkout has it at the
  repo root (`rfsocBf.m`, tracked, sha256 9c4b3a22…).
- Signature drift: the original app (export last changed in 7acb76d) passes 29 arguments
  (`… ang_num, data_v, …, setup_v, debug`). Since 1ed93ac (2025-01-22) `rfsocBf` takes
  `… ang_num, num, data_v, …` plus calibration/IQ arguments. HEAD is therefore
  incompatible with the original app: every argument after `ang_num` shifts by one
  position. The original app's silent `catch` would hide this as an endless
  "Error in rfsocBf". The last matching revision is **45e726b** (2025-01-14), and the port
  `+origapp/processLegacyFrame.m` follows it (`rfsocBf45e726b-vs-processLegacyFrame.diff`).
- `VSA_rfsoc_new` (ZCU216 feature reference) uses the HEAD signature. It was not used.

## Original-repo functions the refactor calls (from `<originalRepoPath>/Functions`)

| Function | Used for | Toolbox / note |
|---|---|---|
| antPrep | ULA with a patch element (`cfg.elementModel="patch"`) | Phased Array, Antenna (`patchMicrostrip`, `dielectric`) |
| filtSig, steerBf, mvdrBf | pipeline | Phased Array |
| dmr_beamformer, pc_beamformer, lcmv_beamformer, rvl_beamformer | beamformers | Phased Array |
| rab_pc_beamformer → nonconvex_rab | RAB PC | Optimization (problem-based); unseeded rand/randn |
| dl_mvdr_beamformer | DL ITER MVDR | Optimization (fmincon) |
| qcb_beamformer_algo_2 (→ algo_1) | QCB | prints to the console |
| sigFinder | cutter | — |
| beamPatternCalc, avgData, guiXline | display | — |
| phase_pattern_generator | phase calibration | opens a figure (now owned by the app) |
| genCtrl | signal generator (gated) | legacy `instrfind`/`tcpip` (Instrument Control) |
| arduino_prog | Arduino (gated) | MATLAB Support Package for Arduino |
| PlutoControl (repo root app) | Pluto button (gated) | Communications / ADALM-Pluto support |
| koef.mat (repo root) | patternCorr | calibration data, private |

Not present in the repo: the `iqtools_2023_10_24` folder that the original startup added to
the path. The IQtools button needs `cfg.iqtoolsPath`.

No longer used by the refactor: `rfsocConnect` (hard-coded fallback addresses),
`tcpDataRec`, `vsaDdc`, `vsaSetup` (`delete(instrfind)`, VISA hislip), `vsaSendData`,
`doaEst` (replaced by `origapp.makeEstimator`), `plotPrep` (`clf` on uiaxes). Their
transport and VSA roles go to the injected backend (BACKEND_CONTRACT.md).

## Reviewed demo package (default, `cfg.bfEngine="reviewed"`)

`rfsoc4x2-beamformer/matlab/+rfsoc`: the refactor only adds it to the path, read-only,
and calls `rfsoc.beamform` and `rfsoc.defaultConfig` (fixture). `processFrame`, `FrameSource`,
`VsaSession` and `spatialView` are not called by this original-UI layer. Reasons: processFrame is FFT256 and cannot
demodulate the legacy FFT64 waveform; the explicit legacy transport profile needs separate stream ownership; the
VSA session is a2's.

## Toolboxes present on the laptop (checked)

Phased Array, Antenna, Signal Processing, Optimization, Communications, Instrument Control,
DSP System. `phased.RootWSFEstimator` exists (`exist` = 8).
