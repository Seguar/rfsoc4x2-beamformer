# MATLAB code

## Entry points

| File | Role |
|---|---|
| `standalone/RFSoCBeamformer.m` | Application entry: board search, board session, hardware profile, `demo` simulation |
| `standalone/buildStandalone.m` | MATLAB Compiler build (packages the `vsa_rfsoc` functions, the setup file and the reference loop) |
| `original/runSession.m` | One hardware session from the settings JSON that `RFSoCBeamformer` writes |

## The application (`original/app/+origapp`)

| File | Role |
|---|---|
| `BeamformerApp` | Owns the session, the view and the acquisition timer; processes every frame, redraws at most every `displayPeriodSeconds` |
| `BeamformerView` | The window: drawing and controls only |
| `DemoSession` | Headless session: settings, DOA and beamforming per frame, OFDM analysis, Set 0°, converter commands |
| `Controller` | Backend owner: frame admission (sequence, age, boundary flag, stream locks), error policy, command queue |
| `LegacyVsaBackend` | Board stream client (window4 protocol): decode, timestamps, host window checks, control and OLED connections |
| `windowIntegrity`, `windowActivityModel` | Host continuity check of a full window against the transmitted loop |
| `BoardLink`, `boardDialog`, `BoardControl`, `commandPolicy` | Board search and session service client; JSON-line command socket; which commands a backend may get |
| `processLegacyFrame`, `makeEstimator`, `steeringVector`, `iqCompensate`, `processingLimits` | DOA and beamforming, ported from `vsa_rfsoc` `rfsocBf.m` (revision 45e726b) |
| `ofdmPilotWeights`, `ofdmSignature`, `ofdmSyncMetric` | OFDM pilot MVDR and spatially adaptive preamble detection |
| `OfdmAnalyzer`, `ofdmAnalyze`, `ofdmProfile` | OFDM demodulator and the profile read from the pinned setup file |
| `simulatedArrayBackend`, `demoResources` | Simulation backend and packaged resources |
| `defaultConfig`, `resolveConfig` | Settings and their checks; an unknown field is an error |

`+rfsoc` (`beamform`, `steering`, `defaultConfig`, `algorithmNames`) is the reviewed
beamformer engine used by `bfEngine="reviewed"` (the default).

## Backend contract

A backend is a handle object or a struct of function handles:

| Operation | Required | Contract |
|---|---|---|
| `next(timeoutSeconds)` | yes | `[]` when no frame yet; else a struct with `samples` (N-by-4 complex ADC counts, I − jQ), `timestamp` (POSIX s of the capture), `sequence` (increasing), `availableChannels`, and for four-stream windows `signalChannels` and `boundaryFree` |
| `close()` | yes | idempotent, never throws |
| `open()`, `availableChannels()` | no | connect; logical 1-by-4 measured-stream mask |
| `send(line)`, `capabilities()`, `controlStatus()` | no | board commands (only with `allowBoardCommands`) and the commands the backend declares |
| `showEvm(evm, angle)` | no | board OLED; never an error |

`Controller` refuses a frame that is not finite N-by-4, repeats a sequence, is older
than `staleSeconds`, or has `boundaryFree=false`. Missing stream lock is reported
(`unlockedChannels`, `deadChannels`), never a reason to refuse.

## Dependencies

From `<vsa_rfsoc>/Functions`: `filtSig`, `steerBf`, `mvdrBf`, the beamformers
(`dmr_beamformer`, `pc_beamformer`, `lcmv_beamformer`, `rvl_beamformer`,
`rab_pc_beamformer`, `dl_mvdr_beamformer`, `qcb_beamformer_algo_2`), `antPrep`,
`sigFinder`, `beamPatternCalc`, `avgData`. Toolboxes: Phased Array System
Toolbox; Optimization Toolbox for RAB PC and DL ITER MVDR; Antenna Toolbox only
for the patch element model, which cannot be compiled (the application uses
isotropic elements). `Settings/ofdm_iq_100_16_4x2.setx` is the OFDM profile; its
SHA-256 is pinned.

## Checks (`original/tests`)

`runSuite(referenceMat, vsaRfsocRepo, outDir, opt)` runs them all and prints one
PASS/FAIL line each:

| Check | What it covers |
|---|---|
| `validateMetadata`, `validateStreamGate`, `validateWindowAdmission`, `validateBoardCommandQueue` | frame admission, lock reporting, boundary flag, command queue |
| `validatePilotFallback` | OFDM pilot MVDR without a preamble keeps the frame |
| `validateDemoSession` | the session on synthetic frames: settings, refusals, recovery, reduced frames, the app's one figure and timer |
| `validateZeroCal` | Set 0° on synthetic phase and gain errors |
| `validateStandaloneDemo` | the entry point in simulation mode |
| `validateLegacyWire` | wire decoding (fixtures from `tests/make_wire_fixtures.py`) |
| `runWindow4Fixture` | the board stream protocol against `tests/fake_window4_server.py` |
| `validateBoardLink` | board search and session ownership against `tests/fake_session_service.py` |
| `validateBeamformerView` | the window's controls and layout (needs an interactive desktop) |
