# MATLAB + VSA refactor

Target: RFSoC4x2. `VSA_rfsoc_new.mlapp` supplies the newer ZCU216 feature reference;
its overlays, rates and burst commands are not 4x2 settings. Original binary apps
and exports stay unchanged. The readable frontend is `matlab/runBeamformingDemo.m`.

## Validation status

28 Python host tests pass, including stream controls and launcher config filtering.
MATLAB differential CFO/EVM/BER, noise rejection, all twelve beamformer modes,
iterative-loading endpoint/isotropic controls and strict transport checks pass.
A fresh 100-frame physical MATLAB DAC_B → 20 dB → ADC_D run locked every frame
with zero BER. EVM min/median/p95/max: 2.88/3.31/7.30/8.30%; median −29.61 dB.
The MATLAB GUI advanced during validation and has since exited. This is conducted
single-channel evidence, not physical array tracking or jammer rejection.

New VSA startup works with explicit localhost port and Use64Bit. Matched offline
SETX replay now passes with an explicit warning policy for unnamed trace bit32;
noise and wrong-SETX controls are rejected. Live RF VSA validation remains pending.
Twenty-four simulated guarded-reader cases also pass. Tiny raw EVM without sync
remains insufficient for acceptance. The hidden localhost MATLAB GUI campaign passed clean IQ,
noise rejection, pause clearing, explicit history labelling and socket/close cleanup.

The laptop has MATLAB R2026a Update 5 and VSA interfaces 30.40.333.0. Signal,
Communications, Phased Array and Optimization licence checks passed; Instrument
Control did not. Acquisition uses .NET TCP and VSA uses its .NET assembly. Only
RAB PC in the new core requires Optimization; other core modes use linear algebra.

Use the **DirectDataSource hardware analyzer**, as specified by the user, with
`USR::Stream` input. Custom OFDM and DDC option entries report `IsValid=false`
while Educational Version is valid. Those entries alone do not establish
DirectDataSource availability. The exact-name analyzer accepted external user-input
IQ and completed acquisitions without a vendor license-denial error. Matched offline Custom OFDM synchronization/EVM is established with a trace-bit
warning; live RF synchronization remains unproven. Input consumption and measurement
completion alone do not establish synchronization or correct sample interpretation.

## Components and conventions

The repository SETX workflow is now implemented when `cfg.vsa.setupPath` is set:
create DirectDataSource, configure its input, recall the selected SETX, reacquire
the selected measurement/UserInput handles, then verify the input rate and center.
It needs `dllPath` and `setupPath`; the typed helper is not required for this path.
The experimental typed-v2 configuration remains available when no setupPath is given.

The original matched pair is `vsa_rfsoc/Settings/ofdm_iq_100_16_4x2.setx` with
`Signals/dac_ofdm_f_500.mat`. Offline preamble correlation is 0.9999. Resample its
500MHz IQ to125MHz for the 4x2 DirectDataSource input; its OFDM system rate is
100MHz, FFT64/CP16. This is a separate waveform from the current FFT256 v2 demo.
Do not apply this legacy SETX to v2 captures.

DSP validation of the SETX constructor and finite-data acquisition passed. Matched
replay produced EVM0.0523% (−65.63dB) and sync0.999996; two positive/noise/positive/
wrong-setup cycles passed. Noise and wrong setup reported SYNC NOT FOUND. Both
matched traces retain unnamed status32. The default reader remains strict; explicitly
setting `allowSetxStatus32=true` in a SETX session permits only bit32, with an
unclassified warning in the status, GUI and result quality. Every other nonzero
bit, measurement error or trace indicator is rejected. Freshness, same-summary
normalized sync correlation and percent units remain mandatory. This policy does
not assign bit32 a vendor meaning or establish live RF performance.

| Source | Responsibility |
|---|---|
| `FrameSource.m` | Exact reads, profile/rate/version/sequence checks, I−jQ decoding |
| `acquire.m`, `pilotWeights.m` | Per-capture lock, conjugation, CFO and wanted pilot manifold |
| `beamform.m`, `steering.m` | Twelve modes, explicit geometry/calibration and constraints |
| `demodulate.m` | Training-only equalization, pilot timing/phase, held-out payload EVM/BER |
| `processFrame.m` | Pure processing without socket/UI/instrument state |
| `VsaSession.m` | Newly owned VSA, explicit setup, finite input, fresh results |
| `runBeamformingDemo.m` | Mode/tracking controls, frozen baseline, EVM, constellation, phases |
| `board/legacy_server.py` | Hardware-injected replacement for the boot stream/control loop |

Convention: samples × channels, receive vector `a`, covariance `E[x xᴴ]`, output
`X*conj(w)`. Scaling is explicit at the VSA boundary. Invalid constraints/solver
failures produce unavailable results rather than silently changing algorithms.

| Original menu | Refactored algorithm |
|---|---|
| Without | Fixed broadside sum, weights 1/4 |
| Steering | Unit-response wanted vector |
| MVDR | Covariance solve with explicit absolute numerical loading |
| DMR | Dominant-mode covariance, averaged noise eigenvalues |
| PC | Rank-selected principal-component inverse |
| PC_corr | PC with four complex corrections; fixes wrong-function call |
| LCMV | Wanted response plus explicit independent jammer nulls |
| RVL | Loading `d + gamma/d`, equivalent to `R + gamma R⁻¹` |
| RAB PC | PC-derived uncertainty, real-variable worst-case constrained optimization |
| DL MVDR | Loading relative to mean covariance power |
| DL ITER MVDR | Spherical robust Capon loading with explicit uncertainty and bracketed root |
| QCB | Two-edge quadratic constraints and iterative sector loading |

Corrections include consistent conjugation/response normalization, measured
spacing instead of hard-coded half-wave geometry, scalar QCB covariance scaling,
real optimization variables and explicit iterative-loading uncertainty. These
intentionally change legacy outputs; performance equivalence is not claimed.

Iterative loading follows the scalar equation in Li, Stoica and Wang,
[On Robust Capon Beamforming and Diagonal Loading](https://doi.org/10.1109/TSP.2003.812831).
The denominator is `(1+lambda*d).^2`, not `1+lambda*d.^2`, and actual diagonal
loading is `1/lambda`. Bounds and equations are also given in the authors'
[derivation, equations 25–28 and 34](https://patents.google.com/patent/US6798380B2/en).
`uncertainty` is the absolute steering-vector error radius; squared radius is
epsilon. Output is normalized to unit nominal response, as in the other loaded
MVDR modes. Failure to bracket or satisfy the root is reported, never suppressed.

Tracking identifies the wanted DAC from its pilot instead of choosing the strongest
jammer peak. Angle needs measured spacing or a calibrated manifold describing the
corrected channels. Tracking off holds the chosen angle. Baseline calibration
freezes weights until recalibrated: wanted TX at broadside, jammer off. Direct mode
disables array controls. LCMV needs jammer angles; QCB needs geometry/sector width.
Sources sharing a splitter path cannot be spatially separated.

## Execution

Generate exact references from the repo root; MATLAB does not reproduce NumPy RNG:

```sh
python -m tools.export_matlab_reference
python -m tools.export_matlab_fixture
```

```matlab
addpath(fullfile(repoRoot,'matlab'));
addpath(fullfile(repoRoot,'matlab','tests'));
validateCore(fullfile(repoRoot,'out','matlab-fixture.mat'), ...
    fullfile(repoRoot,'out','matlab-validation.json'));
cfg = rfsoc.defaultConfig();
cfg.host = privateBoardAddress;
cfg.referencePath = fullfile(repoRoot,'out','matlab-reference.mat');
app = runBeamformingDemo(cfg);
```

The launcher now supports a finite MATLAB check and the MATLAB window:

```powershell
py -3.11 tools/run_demo.py --config PRIVATE_CONFIG --frontend matlab --headless --frames 100
py -3.11 tools/run_demo.py --config PRIVATE_CONFIG --frontend matlab
```

Set `matlab_executable` in the private config if MATLAB is absent from PATH.
`--vsa` additionally requires a complete `matlab_vsa` config with a matching
waveform/setup. SSH credentials are never forwarded to MATLAB. Headless runs
log every frame and fail their gate on missing locks or requested VSA EVM.
The graphical frontend drains queued frames and records how many it skips.
Transport validation keeps every frame by default.

The framed capture helper must be ready for one client. Orderly release of the
Python display ends its existing helper; start a fresh owned capture before MATLAB
connects. Never run simultaneous overlay owners. MATLAB does not configure RF;
the capture owner handles RAM clears/off when its stream closes. For array work
set `directOnly=false`, measured `spacingM`, corrections and manifold. The 5.2 GHz
patch label provides no spacing calibration. Keep 3 GHz for this conducted test.

VSA requires `cfg.useVsa=true` and explicit `cfg.vsa` fields `dllPath`,
`customOfdmDllPath`, `typedHelperPath`, `referencePath`, `fsHz`, `fcHz`,
`bandwidthHz`, `captureSamples`, `visible`. The launcher generates `referencePath`.
Manual MATLAB callers supply it explicitly. The adapter creates a new application
with a unique title and selects its exact-name DirectDataSource configuration. If
missing, it creates that configuration with USR::Stream. Existing groups are not
cleared; unrelated instances and global instrument handles remain untouched.
Capture size counts complex samples;
RequiredSamples counts floats, two per complex sample. No padding/repetition of
finite frames. Timeout, insufficient input or missing valid EVM gives unavailable.
The reader requires fresh acquisition, both IQ and summary statuses zero, and
normalized `Ch1SyncCorr` from that same summary ≥ configurable 0.5. A later invalid
IQ trace cannot leave an earlier good summary EVM visible. Unknown status bits,
including unnamed bit32, remain unavailable by default. The explicit SETX warning
policy above is the sole exception. Installed enum NoSync is 128.
For live streams, limit VSA measurement timeout to at most four seconds; the board
producer has a bounded send timeout. VSA starts before the capture client connects.

For the user-requested SETX path, replace the typed helper/reference fields with
`setupPath`. Input fs/center/span/capture/visibility fields remain required.
`maxInputSamples` optionally limits the finite vector supplied, independently of
`captureSamples` (the VSA gap-free window capacity). The DSP replay consumed57420
floats across requests—more than one16384-complex window—using genuinely contiguous
reference data. The adapter never pads or tiles short captures. Current live v2
captures must retain their matching profile; SETX validation does not change RF.

**Historical FFT64 Custom OFDM settings do not match current FFT256 waveform v2.**
Validate historical waveform/setup pairs independently; filenames are insufficient.
A matching VSA v2 setup is still required. Held-out MATLAB payload EVM and VSA's
configurable demodulator EVM have different equalization/reference definitions.

The source-mode probe found that selecting the USR analyzer changes the effective
measurement from Custom OFDM to VectorMeasurement. Configuration must restore
the Custom OFDM extension after analyzer selection, apply the matching settings
and verify effective mode/rate/search/result lengths. Candidate setup readback
also differed from intended 125MHz, so file contents alone cannot validate it.
The isolated vendor recording produced raw EVM0.608% and sync0.976, but both
required traces retained unnamed status32; the guarded reader rejected it.

The typed correction was exercised: Fs125MHz, FFT256, CP¼, twelve symbols,
48 active carriers and pilots±7/±21. Capacity8192 was required to retain twelve
symbols; capacity4096 clamped the result to six. Actual search readback was
48.64µs. Capacity is independent of finite input: no padding or repetition of
the aligned 4096-sample result. Additional demand returns unavailable. Actual
external-IQ operation and adequacy of a single aligned period remain unproven.

Build the included helper against the locally installed SDK:

```powershell
py -3.11 tools/build_vsa_helper.py --interfaces-dir "VSA_INSTALL/Interfaces" --out out/FinalVsa.dll
```

`dllPath` points to Agilent.SA.Vsa.Interfaces.dll, `customOfdmDllPath` to
Agilent.SA.Vsa.CustomOfdm.Interfaces.dll, and `typedHelperPath` to the locally
compiled FinalVsa.dll. Vendor assemblies are not redistributed. The helper
sets the v2 resource map/reference directly, without recalling historical setup
files or inherited hardware addresses/calibrations. This is a verified setup
correction, not a validated external-IQ measurement workflow.

## Reproduce the simulated GUI campaign

Use a fresh fixture directory and generated reference. Start this localhost
producer, then invoke MATLAB in another process:

```sh
python -m tools.gui_fixture --reference out/matlab-reference.mat --directory out/gui-check
```

```matlab
addpath(fullfile(repoRoot,'matlab'),fullfile(repoRoot,'matlab','tests'));
validateGui(fullfile(repoRoot,'out','matlab-reference.mat'), ...
    fullfile(repoRoot,'out','gui-check'));
```

The hidden test app is labelled SIMULATED and the producer never accesses hardware.
Clean IQ, noise, pause, history labelling and closure passed on the laptop. Public
scripts package the same handshake-based campaign for reproduction.

## Boot-loop integration

Original boot.py couples GPIO/clocks/overlay, waveform loading and an endless stream
loop that leaves controls unread. The replacement injects hardware and cleanup:

```python
from legacy_server import serve
serve(overlay, shutdown, bind_host=private_bind_address)
```

Supply idempotent shutdown: stop capture, zero BOTH complete DAC RAMs, command both
DACs off. Capture trigger is ORed into DAC enables; GPIO off alone is insufficient.
No waveform loads into both players automatically. Controls are read between frames;
queued bytes do not acknowledge stop. Stalled readers have a bounded send timeout.
Raw legacy frames lack sequence metadata; waveform upload is separate from bounded
control parsing. ZCU216 `stream N` and `dacbf` are rejected.

This loop is staged source, not deployed firmware. Do not overwrite `/boot`, install
startup services or create a second owner. Preserve matched FPGA/clock/wrapper assets.
Legacy raw TCP and the framed demo on port 4010 remain separate profiles.


## DOA and receive pattern

`spatialView.m` computes Beamscan, diagonally loaded MVDR or MUSIC spectra from
training samples. `sourceCount` configures MUSIC's signal-subspace rank and the
maximum number of displayed local peaks. Spectrum peaks can include interferers;
the wanted-DAC angle is independently matched to the pilot-derived receive vector.
DOA remains visible when wanted tracking is disabled; steering then uses the
configured `angleDeg`. The GUI's DOA selector is independent of its beamformer.

The pattern uses exactly the selected receive weights, `abs(w' * a(theta))^2`,
normalized to its own peak. A frozen-baseline curve appears after baseline capture.
This is an array response model, not a measured radiation pattern. Physical angles
require the actual carrier, measured element spacing, verified channel order and
calibration. Alternatively `manifold`/`manifoldAnglesDeg` provide a measured
manifold; the scan is restricted to its angular coverage. Neither 5.2GHz silkscreen
nor an assumed half-wave spacing establishes calibration.

Direct mode disables DOA selection and leaves both spatial plots unavailable.
Current curves and angle labels clear before waiting for a frame and on any
acquisition/processing failure; EVM history remains explicitly labelled history.
`validateSpatial` checks signed two-source DOA, pattern conjugation, broadside
nulls, direct-mode rejection and calibrated scan bounds with simulated data.
`validateGui(referencePath,directory,true)` checks array display and loss/pause
clearing using `tools/gui_fixture.py --angle-deg 18` as a simulated source.


## Instrument display and persistence

The app uses a dark instrument theme with large EVM dB/percent, RX-level and BER
cards. Current constellation dots are bright; dim dots retain at most two genuine
prior frames, with fixed symbol reference crosses and stable I/Q limits. EVM uses
a highlighted trace and a separate amber frozen-baseline trace. DOA and pattern
colors match the selected-versus-baseline convention.

The GUI polls complete-frame readiness at up to20Hz. The receive buffer holds at
least one entire capture, so this check does not deadlock a partial TCP frame.
Persistent graphics handles update only on genuine new data; points are not
interpolated or synthesized. Between arrivals the latest fresh frame stays steady.
`displayStaleSeconds` defaults to1s; after that, current cards, constellation
persistence, phases and spatial curves clear. Noise and disconnects also clear
current values. Acquisition rate remains limited by real capture/processing.

DSP GUI checks exercise direct and simulated-array modes, including a no-new-frame
callback which must preserve a still-fresh display, noise rejection, pause clearing
and close cleanup. Cold-render tests explicitly use a5s display stale threshold;
the production default remains1s. These are display tests, not improved RF metrics.
