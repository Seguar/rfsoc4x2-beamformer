# FEATURE_PARITY: VSA_rfsoc_new → RFSoC4x2 original app (integrated software port)

Source of truth for the comparison (read-only):

- **old** = public refactor `matlab/original/app/VSA_rfsoc_refactor_exported.m` at
  Seguar/rfsoc4x2-loopback-demo **8133baa** (119 components, 65 callbacks), itself a
  refactor of `vsa_rfsoc/VSA_rfsoc_exported.m` (118 typed components + UIFigure).
- **new** = `vsa_rfsoc/VSA_rfsoc_new_exported.m` (3703 lines, sha256 6c879b42…, last
  changed bce5641) + `VSA_rfsoc_new.mlapp` (sha256 1dcc97ff…), `rfsocBf.m` (HEAD
  2d8610a, sha256 9c4b3a22…) and HEAD `Functions/`. Line numbers `new:L…` refer to that
  export; `cand:` to the candidate export.
- Method: component lists were extracted from both exports' declarations (new has 164
  typed components, old 118; 63 only in new, 17 only in old), every callback body
  and every block of the new `startupFcn` loop was read, and the HEAD `rfsocBf.m`
  signature/body and the new helper functions were compared with the refactor's
  `processLegacyFrame` (port of rfsocBf 45e726b). Parity is claimed only where a
  test exercises behaviour; names alone are not counted.

State legend: **IMPL+TEST** implemented in the software port and exercised by the headless
simulation fixture; **GATED** implemented, refused unless the backend declares the
capability (tested both ways in simulation); **UNSUPPORTED** explicit visible refusal on
RFSoC4x2 (tested); **NOT PORTED** deliberately absent, reason given; **COVERED** an
existing 8133baa feature already provides it. No state here is a hardware claim.

## 1. Algorithms (rfsocBf HEAD vs refactor 45e726b port)

| Capability | new source | old coverage | Candidate | RFSoC4x2 adaptation | State |
|---|---|---|---|---|---|
| Adaptive receive IQ compensation (LMS, L taps, MU) | rfsocBf.m L12-23; Functions/adaptiveIQCompensation.m; new:L2454,L2480,L2486 | none | `origapp.iqCompensate("adaptive")`, filter state carried frame to frame (`correct_filter`) | array processing only; never applied to the direct native-VSA feed (raw vendor EVM preserved, tested) | IMPL+TEST: max diff vs original 6.4e-13; image tone −21.9 → −66.1 dBc (simulation) |
| Static IQ compensation (conv with conj) | rfsocBf.m L24-29; new:L2448 | none | `iqCompensate("static")` after adaptive (HEAD order) | all-zero filter (HEAD silent no-op) is an explicit error | IMPL+TEST (diff 0) |
| Coupling compensation `(C*X.').'` | rfsocBf.m L30-32; new:L2474 | none | `processLegacyFrame` `p.coupComp` | needs `cfg.calibration.couplingMatrix` (4×4), else explicit error | DISABLED by parent review; see finding F1 |
| Phase/power compensation at estimated angle | rfsocBf.m L72-83; new:L2460 (PhasecompCheckBox) | c1 (45e726b semantics, MVDRman_corr only) | `p.phComp`: steering table from manual estimator or `calibration.steeringCorrection`, power table; c1+phComp together is an explicit error | tables must be on the current scan grid | IMPL+TEST |
| MVDRman via `m_mvdr` (power-weighted manifold, linear) | Functions/m_mvdr.m; rfsocBf.m L38-44 | 45e726b loop (dB, data/√pow) | `cfg.manualMvdrFormula="head"`; default stays "45e726b" | config only (no new control) | IMPL+TEST: same DOA as 45e726b at unit calibration |
| `num` (max signals) passed to rfsocBf | rfsocBf signature | estimator `NumSignals` already from `num`; angles capped at 2 | unchanged | — | COVERED (partial: HEAD truncates to `num`, refactor caps at 2) |
| NaN weights → "No signal", weights=0, continue | new:L627-631 | explicit `origapp:NoSignal` rejection | unchanged (stricter) | — | COVERED (stricter) |
| PC_corr with estimator table | rfsocBf.m case 'PC_corr' | original engine explicit error; reviewed engine supports it | unchanged | — | COVERED (reviewed engine) |

## 2. Calibration and tracking controls

| Capability | new source | old coverage | Candidate | RFSoC4x2 adaptation | State |
|---|---|---|---|---|---|
| Angle calibration: averaging per angle, steering + power + coupling tables, live install | new:L1062-1124 (loop), L1929 button; phase_pattern_generator, power_pattern_generator, adaptiveCouplingMatrixCalculation | steering table only, 1 frame/angle, saved, not installed | `origapp.angleCalibration` (figure-free), `calibrationFramesPerAngle`, 3 tables saved under `cfg.outputDir`, installed for the session only if finite and on the scan grid; existing Downconverter button | refused in directOnly (visible message); labelled model calibration: operator-labelled angles, a common splitter feed carries no angle information | IMPL+TEST: steering/power/coupling identical to originals (diff 0) |
| Stepper/rotator-driven calibration (`stepper` app) | new:L1068-1074, L2441 | none | not ported; manual press per angle | external rotator not in 4x2 scope | NOT PORTED |
| RX DC-leakage autocal (Arduino rxBoardControl) | new:L748-838, L2361 | Arduino program button (gated) | not ported | mmW RX board + Arduino absent on 4x2 path | NOT PORTED |
| RX amplitude autocal (`again` binary search) | new:L840-897, L2384 | none | not ported (algorithm); `again` is GATED in Channel control | no 4x2 backend declares `again`; staged parser rejects it | NOT PORTED |
| RX phase autocal (genCtrl + PAcheck) | new:L899-917, L2399 (callback unbound in new) | none | not ported | unbound in new; instrument at hard-coded address | NOT PORTED |
| TX amplitude / phase autocal (`dgain`/`dphase` sweeps) | new:L919-1060, L2413/L2423 | none | not ported | needs 4 TX chains + per-DAC gain; RFSoC4x2 has 2 DAC outputs | NOT PORTED |
| DAC BF mode GUI/Random/Scaning/Rescaning/Tracking/Retracking | new:L1504-1535, L2051, list L2698 | DAC angle spinner state only | `origapp.dacBeamSteering`; New tab list; DAC angle line on both axes; correct phase wrap; seeded Random | GATED: `capabilities().txArrayElements>=4` and `dphase`; Tracking/Retracking refused in directOnly | GATED (tested refused by default and accepted with simulated capability) |
| RFSoC (on-board) BF mode `dacbf`/`dacbfcorr` | new:L2539-2569, list L2726 | none | New tab list; selecting Tracking/Retracking shows refusal, reverts to Off, queues nothing | ZCU216 notebook/overlay feature | UNSUPPORTED (even if a backend declares it) |
| Channel control: DAC gain/phase/I phase, ADC gain/phase/I phase, DAC phase corr | new:L2068-2276, L2967-3030 | none | New tab dropdown + Ch1-4 spinners; refused change reverts the spinner | `dphase` keeps original 4x2 behaviour; `dgain/again/phase/diqphase/aiqphase` only if declared | GATED (tested) |
| DAC channel enable checkboxes (CheckBox…_4) | new:L2510, L3032 | dacPow (PowerCheckBox_2) | not ported | DAC enables on 4x2 are dacPow | NOT PORTED (COVERED by dacPow) |
| Print phase mismatch (PAcheck/cphase) | new:L530-549, L2339 | none | New tab button, text result | needs a current array-mode frame with 4 measured channels | IMPL+TEST (diff 0 vs cphase) |

## 3. Display and measurement

| Capability | new source | old coverage | Candidate | State |
|---|---|---|---|---|
| EVM checkbox (SCPI `:TRACe4:DATA:TABLe?` fields) | new:L648-664, L2492 | native VSA guarded status (directOnly) | EVM in DOA title from guarded `vsaStatus` only, % and dB; "unavailable" otherwise; no raw SCPI read | IMPL+TEST (changed source: guarded native VSA) |
| Plot mirror (MirrorCheckBox_3) | new:L677-682, L2344 | none | display-only flip, `[mirrored]` in titles; data unmirrored | IMPL+TEST |
| Meas tab: coupling scan, VSA TX scan, TX power sweep, leakage | new:L1126-1502, L3450-3496 | none | not ported | NOT PORTED: 4 TX chains, per-DAC gain, `w_mat_cal.mat`, raw SCPI VSA queries conflicting with owned native VSA |
| Devices tab (visadevlist, LO RX/TX models, IP field) | new:L2278-2359, L3383-3448 | single generator via `cfg.generator.address` (gated) | not ported | NOT PORTED: instrument discovery/connection out of scope; hard-coded instrument addresses must not enter code |
| DAC mirror (MirrorCheckBox_2, negative DAC NCO) | new:L2036 | ADC mirror only | not ported | NOT PORTED: 4x2 DAC NCO sign semantics unverified |
| Burst length `stream N`, TCP burst/drain | new:L457-528, L2571 | backend-owned transport | New tab spinner; value ≠1 shows refusal and reverts | UNSUPPORTED (ZCU216) |
| Debug timing print every N frames | new:L1539-1552 | Debug checkbox status print | not ported | NOT PORTED (cosmetic) |
| Limit changes (ScanBW [2 180], Angle [-90 90], AntennaFc ≤Inf) and DacSignal 'Off' item | new createComponents | original limits/items | existing components left unchanged | NOT PORTED (cosmetic; avoids editing original components) |

## 4. TX / upload / stream

| Capability | new source | old coverage | Candidate | State |
|---|---|---|---|---|
| Custom DAC file (sigPrepare; LoadSignal buttons unwired in both apps) | Functions/sigPrepare.m; new:L1867-1883 (unbound) | unreachable | `origapp.prepareDacWaveform`: resample/filter from System tab state, peak 1200, RAM tiling check, I + jQ int16, SHA-256; New tab DAC port + button; upload only via declared `uploadDacWaveform` + `allowBoardCommands` | IMPL+TEST (prep, corr 0.99999997 with sigPrepare); upload GATED, no current backend implements it |
| `source` command (DAC signal type) | new:L1992 | queued (gated) | unchanged | COVERED (note: staged 4x2 parser rejects `source`) |

## Findings from the comparison

- **F1 (original-algorithm defect, ported unchanged and recorded):** on ideal simulated
  single-source ULA captures, `adaptiveCouplingMatrixCalculation` does not return ≈
  identity (‖C/C11 − I‖F = 3.27) and applying it moves an MVDR DOA from 20° to −41°.
  It least-squares fits eigenvectors whose per-angle phase is arbitrary. Coupling comp is disabled by an explicit runtime error pending independent review;
  the generated tables remain diagnostic only.
- **F2:** new `PhasecompCheckBoxValueChanged` writes `app.PowercompCheckBox`, which does
  not exist in the new component model (new:L2463), so the original control errors.
- **F3:** new DAC-BF phase fold (new:L1532-1533) maps e.g. 200° to −21° instead of −160°.
  The candidate wraps with `mod(x+180,360)-180`.
- **F4:** HEAD `rfsocBf` static IQ comp with the initial all-zero filter is a silent no-op.

## Preserved (unchanged files/behaviour)

`LegacyVsaBackend.m`, `makeEstimator.m`, `runAll.m`, `runOriginalUiFixture.m` and the
Controller acquisition path are byte-unchanged: stale 2 s, refLock ≥ 0.3, sync ≥ 0.9,
available-channel guard, `X*conj(w)`, training/payload separation and raw vendor EVM are
not touched. The 119 original components keep identical property fingerprints.

## Parent integration restriction

The helper refuses every coupling-compensation request, including identity or
supplied matrices, pending an independently validated coupling method. This
restriction is covered by negative fixtures. Phase/power compensation remains
separate. Neither these simulation fixtures nor the generated angle tables prove
physical array calibration. The common-feed hardware check is a distinct dataset.
The App Designer editor round trip and live runtime of this extended UI are pending.
