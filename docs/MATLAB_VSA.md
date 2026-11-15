# MATLAB + VSA refactor

Target: RFSoC4x2. `VSA_rfsoc_new.mlapp` supplies the newer ZCU216 feature reference;
its overlays, rates and burst commands are not 4x2 settings. Original binary apps
and exports stay unchanged. The readable frontend is `matlab/runBeamformingDemo.m`.

## Validation status

26 Python host tests pass, including stream controls and launcher config filtering.
MATLAB differential CFO/EVM/BER, noise rejection, all twelve beamformer modes,
iterative-loading endpoint/isotropic controls and strict transport checks pass.
A fresh 100-frame physical MATLAB DAC_B → 20 dB → ADC_D run locked every frame
with zero BER. EVM min/median/p95/max: 2.88/3.31/7.30/8.30%; median −29.61 dB.
The MATLAB GUI was left visible with advancing sequences. This is conducted
single-channel evidence, not physical array tracking or jammer rejection.

New VSA startup works with explicit localhost port and Use64Bit, but valid VSA
EVM/lock remains unproven. Fresh replay can return tiny raw EVM even with NoSync.
Seven simulated guarded-reader cases pass; they do not establish a real VSA
positive control. The hidden localhost MATLAB GUI campaign passed clean IQ,
noise rejection, pause clearing, explicit history labelling and socket/close cleanup.

The laptop has MATLAB R2026a Update 5 and VSA interfaces 30.40.333.0. Signal,
Communications, Phased Array and Optimization licence checks passed; Instrument
Control did not. Acquisition uses .NET TCP and VSA uses its .NET assembly. Only
RAB PC in the new core requires Optimization; other core modes use linear algebra.

Use the **DirectDataSource hardware analyzer**, as specified by the user, with
`USR::Stream` input. Custom OFDM and DDC option entries report `IsValid=false`
while Educational Version is valid. Those entries alone do not establish
DirectDataSource availability. The exact-name analyzer accepted external user-input
IQ and completed acquisitions without a vendor license-denial error. Valid Custom
OFDM synchronization/EVM remains unproven. Input consumption and measurement
completion alone do not establish synchronization or correct sample interpretation.

## Components and conventions

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
including unnamed bit32, remain unavailable. Installed enum NoSync is 128.
For live streams, limit VSA measurement timeout to at most four seconds; the board
producer has a bounded send timeout. VSA starts before the capture client connects.

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
