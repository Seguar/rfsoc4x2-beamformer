# Demo plan — 2026-11-15

User requested a new public repository showing RFSoC 4x2 DAC demodulation,
tracking and beamforming with the two-DAC/hybrid/splitter/four-ADC loopback,
avoiding external MXG interference; `vsa_rfsoc` is a reference. User also
requested agent instructions and authorized one laptop agent for live checks.

Claims hold until explicitly released, irrespective of timestamps.

| Part | Owner | State |
|---|---|---|
| Repository code, docs, tests, publication | Coordinator | MATLAB software and direct live path validated; VSA/array remain pending |
| Laptop and board experiments | Coordinator; no new overlay operation | Previous MATLAB frontend exited; capture child defunct, five notebook kernels present; audit before live handover |

## Initial plan and historical checkpoints

Decisions: public code repository; existing matched 4x2 overlay; no FPGA build;
low-level waveform first; hardware-free simulation clearly labelled. Initial RF
candidate 3 GHz fits passive bands; runtime/spectrum validation remains required.

Open: MXG RF connection, output state and injection topology; whether the same
receive path permits spatial separation. Laptop agent must establish access and
save private evidence before hardware claims. Do not publish private inputs.

Next: stage the reviewed helper/reference, verify board and instrument state,
run DAC0-only low-level captures, analyze results, calibrate DAC1 and then both
if headroom and signal lock permit. Record final DAC/MXG/service states.

Checkpoint: laptop evidence received privately; no capture or live verification.
Current DAC/MXG/service state unknown. Helper review fixes applied and eight
host tests pass. Hardware remains pending current secure board access and MXG
identification. No agent retains hardware ownership after this access attempt.

User update: MXG RF cable disconnected; all five notebook kernels belong to user
and may be stopped for the demo. Exclusive capture is authorized. Authenticated
preflight confirmed live board identity and matched boot hashes. New GPIO handling
records commanded shutdown without claiming physical RF-off from DATA reads.

Real-time scope clarified: fixed broadside versus adaptive EVM while moving a
wanted transmit patch, then jammer rejection through a distinct OTA path.
Live dashboard and framed board stream implemented; eleven host tests and a
headless dashboard render pass. Antennas labelled 5.2 GHz; spacing/response
unmeasured, CW versus modulated jammer undecided. Current passives specified only
to4.2GHz; keep3GHz conducted test separate from future5.2GHz OTA validation.
Authorized exclusive DAC0 capture delegated; hardware owner holds only the new
private capture evidence/staged experiment, parent owns all public code.

Latest capture checkpoint: DAC0/DAC1 each10frames obtained, no rail hits, but
poor EVM prevents a working demodulation/combining claim. Hardware owner released
claim; Jupyter0kernels, bootpy no process/failed state, DAC disables commanded.
User changed wiring to DAC_A→BW-S20W2+20dB→ADC_A. Source inspection found extra
mode3 IMR2, capture-trigger OR into both DAC players, and missing da0 settle wait.
Parent integrated500Mcomplex/s reference, inactive-RAM zeroing, settle wait and
ADC0-only analysis/live mode.15host tests pass; corrected direct capture pending.

Direct test milestone: fresh ADC_A frames and liveTCP8.62captures/s demonstrated,
but intermittent EVM errors remain (good~3%, badup65.55%).59filehashes verified.
Rootoffline sees~1sample advances insidebadpayloads. Waveform2 adds distributed
timing pilots and versioned receive behavior;19hosttests pass. Dedicated sole
laptop hardware agent owns private timing-diagnostic staging/evidence only while
running. Publiccode remains parent-owned. Credential privately retained with user
authorization; no more unnecessary repeated password requests.

V2 physical milestone: bounded30andlive100frames validated, allzeroBER/acquired;
EVMmedian/max3.79/9.98%live. Raw100ppmadvancepersists. Factoryprofilephysically
switched/restoredbutincompatiblewithfixedMMCM/mixedtileclocktopology; no lower-rate
workaround adopted. Original500/500restored, DACRAMzero, bootpystopped/Jupyteractive.
Parentverified60filehashesandreprocessed30boundedframes. Newone-command direct
launcherreadyforfinalheadlesshardwarestartup/shutdownvalidation. Array/OTA deferred
untiluserconnectsfourinputsandresolves5.2GHzRFchain; constantEVMnotpromised.

Launcher milestone complete: a fresh 100-frame headless run passed startup,
streaming, disconnect, DAC clears/off commands, retrieval and process cleanup.
One-line output-path fix applied publicly. Median/max EVM 3.89/9.73%, zero BER,
all locks. No hardware agent retains ownership. The direct demonstration is ready
to launch; graphical interactions remain untested. Physical array/MXG tests stay
open until the user's later antenna setup; raw sample loss remains documented.

User requested EVM in dB as well as percent. Live/static plots now use a dB axis
with a percent axis, current EVM shows both, and metrics include evm_db. Host tests
and headless renders pass; no new hardware run is required for the unit display.

User reported cable changes still showing good EVM, then identified DAC_B.
Confirmed naming error: logical dac0 actually feeds printed DAC_B. TX labels and
launcher selection now use printed letters; RX labels use stream numbers until
verified. Added RX RMS/freshness and current-metric clearing for stale/unlocked
states.21 host tests pass. The user's live GUI requires a controlled restart.

Connector-loss validation completed: real DAC_B RAM blanking produced unlock
and a received-level drop; capture pause cleared current metrics as STALE.
The corrected Python GUI now remains running and holds the hardware claim.

MATLAB milestone in progress: actual old/new .mlapp XML, exports, shared helpers
and matched boot.py were audited. Parent owns new MATLAB core/frontend, boot-loop
source, docs and tests. One laptop agent owns private MATLAB/VSA validation only;
it must preserve the current Python GUI and board ownership. 23 Python host tests
pass. Exact waveform reference and Python differential fixture generated privately.
MATLAB execution, new UI and VSA streaming/EVM remain pending. The first newly
owned VSA instance timed out during startup; packing tests passed. Original binary
apps and deployed boot assets remain unchanged.

MATLAB laptop gate: differential CFO/EVM/BER, noise rejection and eleven beamformers
passed; strict core gate failed DL ITER MVDR. Original root equation squared the
wrong term and used the multiplier instead of reciprocal loading. Corrected from
Li/Stoica/Wang's equations, added isotropic closed-form and residual checks; full
MATLAB rerun pending. Local TCP fragmentation/IQ/sequence/error controls passed.
Owned VSA startup succeeds with explicit port/Use64Bit and disposes normally;
replay completes fresh but trace status32 prevents a valid EVM/lock claim. Sole
laptop agent now investigates waveform/setup compatibility; no board handover yet.
Parent added MATLAB launcher/headless lifecycle and bounded UI backlog draining;
new MATLAB source is staged for its next execution check, not yet live-validated.

Latest milestone: corrected c87817f core gate passes all12 modes, differential
CFO/EVM/BER, noise and isotropic root controls; transport passes. 26 Python tests
pass. Seven simulated VSA reader cases reject stale/NoSync/unknown/low-correlation
results; actual VSA positive control remains unavailable. Reviewed reader and
headless resource-cleanup fixes integrated. A fresh100frame MATLAB physical run
has unique sequences0..99, all acquired, BER0, median/maxEVM3.31/8.30%. Both DAC
RAM clear/off records and no shutdown errors; physical RF-off not measured.
Durable MATLAB GUI left visible/advancing. That session now owns hardware, replacing
the prior Python display, and its claim remains HELD until orderly shutdown.
Sole laptop agent owns only new private VSA-source and localhost UI diagnostics;
must preserve physical MATLAB session. VSA Input.DataFrom Hardware/Recording and
effective CustomOFDM settings are the next concrete probe. Array/OTA/MXG unproven.

VSA source probe complete: selecting USR analyzer changes CustomOFDM toVector;
Hardware source readback succeeds. Candidate effective sample rate differs from
intended125MHz. Vendor recording rawEVM0.608/sync0.976 stillstatus32 and rejected.
CustomOFDM/DDC IsValid=false; effective license mode unconfirmed. Sole nextlaptop
agent must APPLY documented post-analyzer SetMeasurementExtension +typed settings,
readback rates/mode and licensing, then finish independent localhostGUIcampaign.
No physicalowner changes; actualVSApositive remains unavailable.

Typed restore/setup exercised: CustomOFDM,125MHz,FFT256,CP¼,result12,48active,
pilots±7/±21. Capacity8192 required; actualsearch48.64us,finiteinputnotextended.
HiddenlocalhostGUI clean/noise/pause/history/closecampaignPASS, socketEOFverified.
Parentintegratedmodehelper,portablebuild/GUIcampaign scriptsandtypedreference
config; 27hosttestsPASS. ExternalVSApositive remainsunproven. USER clarified
'Use DirecDataSource hardware analyzer as in gui'. Sole newlaptopagent tests
thatactualanalyzer acceptance andread-onlyinspectsrelatedexistingGUIconfiguration;
genericDDCoption IsValid=false alone isnotadecisiveDirectDataSourceblock.
PhysicalMATLABsessioncontinuesholdinghardware; no competingownerauthorized.

DirectDataSource probe: exact-nameconfiguration accepts userIQ and completes;
no vendorlicense-denialerror. V2 clean/noise/wrongCP remain guardedunavailable;
clean hascarrier-lockfailure, controlsNoSync. 60evidencehashes delivered. Parent
adapter nowselectsexistingexact-nameDirectDataSource (createsonlyifmissing,
neverclearsgroups), uniqueOWNapp title. Nextsoleagent verifiesactualsample
fidelity inVector mode, finalhandle/settingsidentity and sufficientsearch after
settling, thenisolatessync/resourceconfiguration. Physicalownerunchanged.

User requested repositorySETXworkflow+a1/a2, thenurgentremoteaccessandDSPdebug.
NativeboardTailscale+DGXkeySSH independentlyverified; laptopnolongerrequired.
DebugnowonDSP. a2 matchedFFT64ofdm_iq_100_16_4x2.setx+dac_ofdm_f_500.mat by0.9999
preamblecorrelation. DSPmatchedSETX replayrawEVM0.0523%, sync0.999996; noise/wrong
setupNoSync. Strictreaderstillquarantinesunnamedtrace32; notfullguardedVSAPASS.
ParentimplementedSETXconfigurationpath andDSPconstructor/acquisitionsmokePASS,
no typedhelperrequired when setupPath supplied. Capturecapacityvsfiniteinputlimit
separated; no short-IQpadding/repetition. Physicalcurrentv2waveunchanged.


## DSP SETX warning policy — 2026-11-15

**Test / How:** Matched repository waveform, DirectDataSource and SETX recall;
two positive/noise/positive/wrong-SETX cycles, finite contiguous offline IQ.
**Results:** Eight fresh acquisitions; four matched positives 0.0523% EVM,
−65.63dB, correlation0.999996; four negatives rejected. Twenty-four simulated
reader cases pass; default policy remains strict.
**Conclusions:** Explicit SETX-only `allowSetxStatus32` permits unnamed bit32
with warning metadata while rejecting all other status bits and fault indicators.
No live RF VSA or physical array/MXG claim.
**Ways to resolve:** Validate the complete adapter in two owned VSA instances,
then audit hardware ownership and provide a matching legacy-waveform capture path.

Full `VsaSession` follow-up: two separately owned VSA instances each completed
positive → noise → positive with fresh results, successful disposal and exit0.
Four matched positives retained the explicit bit32 warning; two noise frames
were unavailable. No disconnect reproduced in this bounded test. Independent
Python audit of the eight probe and six adapter records passed. Live RF VSA and
physical beamforming remain pending.


## DOA spectrum and receive pattern — 2026-11-15

**Test:** Add spatial diagnostics to the new MATLAB frontend, including clearing
current plots on loss/pause. No board or instrument writes.
**How:** Training-covariance Beamscan/MVDR/MUSIC spectra and independent wanted
pilot angle; normalized selected-weight/frozen-baseline array responses. Seeded
four-element half-wave ULA tests at +18/−34 degrees, scalar pattern comparison,
±30-degree broadside nulls, unknown-spacing rejection and manifold coverage bounds.
Hidden GUI campaigns exercise direct and simulated-array modes over localhost.
**Results:** `RFSOC_SPATIAL_PASS`, all existing core/12-beamformer checks pass,
both `RFSOC_SIMULATED_GUI_PASS` sentinels and final MATLAB exit0. Direct-mode
plots remain unavailable; array curves populate and clear on noise/pause. All28
Python host tests pass. Two initial GUI fixture launches failed due to Windows
script execution policy and SSH child lifetime; using a hidden scheduled task for
the private fixture resolved the launch issues without changing test criteria.
**Conclusions:** DOA and receive-pattern functions are implemented and verified
with simulation, including current-data clearing. Spectral peaks may be interferers;
the pilot identifies the wanted DAC independently. Tracking can be disabled while
DOA continues. No physical angle accuracy or antenna pattern has been measured.
**Ways to resolve:** Measure spacing, verify channel order, calibrate all four
channels and validate OTA angles before labelling geometry-model angles physical.


## VSA-style instrument display — 2026-11-15

**Test:** Dark instrument display, prominent metrics, genuine constellation
persistence and steady graphics between new captures.
**How:** Complete-frame readiness polling with a receive buffer >=one frame;
persistent plot objects; existing pure DSP unchanged. Added GUI contracts for
steady current data between arrivals and cleared metric cards on failure/staleness.
**Results:** DSP MATLAB spatial/core gates and direct+array GUI campaigns pass,
exit0 and `DSP_THEME_GUI_COMPLETE`. All28 Python tests pass. Initial cold-render
GUI test exceeded its1s stale deadline; test config now explicitly allows5s for
cold rendering, while production remains1s. No simulated samples enter live mode.
**Conclusions:** Display theme and refresh behavior validated in simulation. No
RF quality or capture-rate improvement is inferred from the visual changes.
**Ways to resolve:** Restart the laptop app through its owned launcher, verify
fresh live frames and target-window layout, retain all DAC shutdown safeguards.


## Original interface selected; source integration — 2026-11-15

**Test:** Refactor the user's original App Designer interface while delegating
constellation/EVM to native VSA, preserving DOA/pattern and original controls.
**How:** Integrate the exported AppBase class under `matlab/original`, retain119
components, replace the startup infinite loop with an owned timer and injected
backend. Parent review made the reviewed twelve-mode beamformer core the default,
required finite acquisition timestamps/increasing sequences, and excluded the
candidate unframed TCP flushing backend because it could lose lane alignment.
**Results:** DSP MATLAB batch exit0 and completion sentinel. Hidden UI construction,
transport/stale/repeated-frame clearing, recovery, command gating, phase-calibration
output and zero leaked figures/timers passed. All twelve reviewed modes execute.
Six metadata rejection controls pass. An independent JSON audit confirms these
checks. Explicit legacy comparison modes retain documented failures and are not
the production default. All original source-repo files remain untouched.
**Conclusions:** Original-UI source integration is validated with synthetic data;
no live native-VSA/EVM, physical DOA or editable refactored `.mlapp` is established.
**Ways to resolve:** Finish the native matched-FFT64 backend, integrate it with this
interface, run and screenshot original MATLAB UI plus owned native VSA, and create
an editable App Designer artifact consistently if needed. a2 restarted after its
advertised quota reset; only a2 owns board/VSA writes.


Original UI/nativeVSA firstlive path demonstrated, but firstbaseline noise gate
FAILED (blank14 correlation0.542 passed0.5). Positive medianEVM4.5633%, one27.5547%
frame retained; all-channel fullRAMtransfer2.2–4.7s failsdefault2sfreshness.
a2solehardware/VSAowner follow-up validatesprofile0.9+reference-lock andsmaller
actual-channelpayload. Parentdoesnotintegratethisbackendasvalidatedyet. a1bounded
privateAppDesignerpackagingresearchindependent, noboard/VSA. See latestVALIDATION.


## Editable original app artifact — 2026-11-15

**Test:** Package the original119-component model and refactored controller into
a consistent `.mlapp` plus generated export, without opening the editor.
**How:** Full R2026a App Designer serialization writes code, model and metadata
together. Parent-reviewed generated differences move resource cleanup into a
figure-destruction listener. A fresh process deserializes and independently parses
the artifact; a second DSP rebuild/readback also checks LF-export compatibility.
**Results:**119 components,65 callback bindings,99 methods and212 properties agree
between model/code/export. All consistency gates exit0 with sentinels. The original
UI fixture passes with no leaked timers/figures; both deletion paths were checked.
Headless runtime uses a disposable export differing only in its generated show
line, avoiding the brief window flash that real generated code permits before
startup applies `visible=false`.
**Conclusions:** Editable `.mlapp` and matching export are included; original source
repo files are untouched. App Designer editor open/save/export is untested. This
uses internal R2026a APIs and does not establish live VSA or physical array results.
**Ways to resolve:** Validate an editor round trip when editing the component
layout; use full-model rebuild/readback after code-only changes. Live blank-input
rejection and transfer-latency work remains with the separate backend campaign.


## Original app + native VSA integration (2026-11-15)

- **Test:** matched legacy FFT64 native VSA, blank rejection, freshness and original
  App Designer integration. No array or MXG test.
- **How:** private predecessor frozen guards lock>=0.3 and sync>=0.9; lossless
  ADC_D-only full-RAM transport; 25-frame wanted/blank/pause hardware gate and
  separate 30-frame continuous smoke test. Public integration then rebuilt the
  complete `.mlapp`/export pair and checked model/code agreement independently.
- **Results:** hardware gate: 16/16 wanted valid, 9/9 blanks unavailable, wanted
  median EVM4.61%, receipt age0.58–1.32s. Outlier24.95% retained. Continuous run:
  30/30 valid, max receipt age1.65s, outlier21.24% retained. Earlier failed gates
  remain in private evidence. Public software: 31 Python tests pass; MATLAB
  original UI/12-mode fixtures, wire negative controls and fresh model/code checks
  pass (119 components, 65 callbacks, no resource leaks).
- **Conclusions:** matched native VSA can demodulate conducted hardware with
  meaningful blank rejection. Public integration additionally bounds decompression,
  clears current validity during acquisition and expires metrics using acquisition
  time at measurement completion. Those final changes and the new public launcher
  still require a fresh exact-source hardware gate. No helper/VSA claim is held
  after the predecessor tests; nothing continuous was left running.
- **Ways to resolve:** validate the public one-command launch with wanted/blank/
  pause/recovery before a durable visible session. Preserve all outliers. Raw
  sample loss, physical beamforming/DOA, jammer rejection and observed RF-off remain
  unproven. App Designer editor round trip remains untested.


## Newer-app feature port (2026-11-16)

- **Test:** compatible VSA_rfsoc_new functions in the original App Designer UI;
  simulation and full-model serialization only, no hardware.
- **How:** explicit32-component extension on a fifth tab; regenerate binary/export
  together; independent fresh-process readback verifies original119 fingerprints,
  new spec and83 callback bindings. Reference helper comparisons and negative controls.
- **Results:**151 components, zero load warnings, deterministic export and passing
  original/new fixtures in the delivered candidate and independent parent rebuild.
  Review disabled known-bad coupling compensation, corrected custom-waveform RAM
  capacity to524288 complex samples and capped preparation peak at1200. Final
  independent fixture rerun passes (MATLAB exit0 and completion sentinel); all31
  Python tests pass. Coupling refusals and32 periods per524288-sample RAM verified.
- **Conclusions:** IQ compensation, phase/power compensation, guarded EVM percent/dB,
  mirror display, phase diagnostics and custom-file preparation are software ports.
  Upload remains unavailable in current backend. Coupling tables are diagnostic:
  the legacy method moved20degrees to-41 in simulation. ZCU216 burst/on-board BF
  commands are explicitly refused; the native acquisition guards are unchanged.
- **Ways to resolve:** validate extended UI on hardware after final software gates.
  Editor round trip, measured antenna calibration, live IQ-comp benefit and physical
  DOA remain unproven. Remaining unported mmW/device/autocal features and hardware
  dependencies are listed in docs/NEW_APP_PORT.md.


## Responsive four-stream integration (2026-11-16)

Test / How: user scaling and missing-plot reports; s candidate replaces forced
one-channel diagnostics with four measured same-capture32768-row windows, board
selection plus independent host lock/jump/SHA checks. Full App Designer model
rebuild changes only three intentional layout properties. Parent verified175
manifest hashes,37 Python tests and primary MATLAB layout/transport results.

Results / Conclusions: bounded gate5 has21/24 guarded-valid signal frames,
combined-output EVM median2.45%, outlier28.1% kept; two stale frames rejected by VSA and one continuous window falsely refused
by the old VSA block check (seq25; historical review corrected below). Model DOA/pattern now visible and labelled common-feed/uncalibrated.
All candidate hardware runs ended RAMzero/readback and offcommands; no helper left.
No physicalarrivalangle or spatialjammergain claim. Intermittent stream3 loss persists.

Ways to resolve: parent added Controller admission of the host boundaryFree flag
so rejected windows clear plots even with VSA off; parent MATLAB gates and a1 cold
review are pending. Publish after gates and review, then run an exact-head bounded
live check before leaving the updated app visible. No RF/clock/route changes.


## Reviewed window4 resolution (2026-11-16)

- Test / How: separate Controller boundary admission and post-VSA display-age gate;
  strongest-stream continuous frame-timing model checks active chunks and silent
  gaps independently of VSA. Invalid or ambiguous edge windows and selector
  fallbacks clear plots and averaging without terminating capture. Cutter is
  disabled for window4 before zero-filling. Responsive model/export rebuilt together.
- Results: final candidate passes38 Python tests; VSA-off21/21 and VSA-stub9/9
  fixtures;256 real-data Python/MATLAB verdicts agree,1395 real-wrap cuts refused.
  Two bounded hardware gates saved and hash-verified every full capture/window:
  parent independently matched all27/26 wire windows to same-capture rows and all
  full-capture hashes. Host accepted24/24 and22/22 wave windows; native combined
  VSA valid22/24 and19/22, EVM medians2.255% and2.382%. Four stale-at-completion
  frames were not plotted; one VSA sync0.852 rejected. Both shutdowns passed.
- Conclusions: real four-stream common-feed diagnostics and responsive plots work.
  Historical seq25 was continuous: old block analysis/replay falsely called it a
  wrap. This corrects both earlier report and review; no frame was forced to fail.
  No same-frame single-stream comparison exists, so no combining-gain claim.
- Ways to resolve: parent independent rebuild/15-case continuity/regression gate
  passes (MATLAB exit0 and completion sentinel, rebuilt export identical).38 host
  tests pass; publication and exact-head launcher check follow. A long live session,
  physical DOA, OTA motion tracking and MXG rejection remain pending. VSA's separate
  old block check can still refuse continuous windows; it fails closed. The host
  model has finite edge resolution and is restricted to the pinned legacy profile.

## Integrated OFDM viewer — parent review, 2026-11-16

Claim: parent owns repository integration; no hardware claim is held.
Test/How: review a1's integrated viewer and compare every recorded buffer with
an independent NumPy implementation. Primary EVM now retains timing-slip bursts;
qualified-only results remain diagnostic. Rebuild the editable app/export together.
Results: fifteen replay buffers agree to 1.8e-14 EVM percentage points, including
complete/qualified coverage. Twelve signal buffers: primary median6.00%,
qualified-only4.46%. Final MATLAB gate passes (exit0, completion sentinel, OFDM34/34, no
stray figures/timers); revised bounded hardware run is delegated to a1.
Conclusions: own OFDM visualization is implemented, with no vendor-equivalence
claim. Parent also fixed failed-startup figure cleanup, viewer sizing/age checks
and enabled one-request prefetch explicitly for integrated mode.
Ways to resolve: complete final gates, then publish and launch exact source.
Physical DOA, OTA tracking, MXG rejection and capture-loss repair remain open.

## Reviewed integrated live result and release

Claim: parent owns release; a1 hardware claim released after bounded checks.
Both gates exit0, shutdown RAMzero/readback/offcommand. G2:201 captures,192valid,
primary EVM4.83% median,1026complete742qualified; median plotage0.49s,1.75Hz.
Blank/pause clear/recover; stream0 dropout sixframes safely refused. One runtime
error unidentified; all193 analyzed frames replay exactly. Parent fixes actual
resize callback (AutoResizeChildren off), append-only Controller error logging
and launcher cleanup capture. Core analyzer/board/guards unchanged. Confirm fixes,
publish, launch visible exact head. Capture loss/OTA/MXG remain separate open tasks.

## Live command path — 2026-11-16

Claim: parent owns integration; hardware test has ended and released the board.
Test/How: separate acknowledged control socket, original command names, 4x2
wrapper operations serialized with capture. MATLAB handles ACKs, logs readbacks,
and rejects old capture revisions. Fixed-size/unsupported actions are explicit.
Results: DSP live test exit0/sentinels;11 direct commands plus a queued batch;
phase45/0 readbacks, same-frequency retuning, pause/status/resume and DAC RAM
off/on recover. Four invalid requests refused. Three obsolete frames discarded.
ACKs0.15–0.33s; shutdown RAMzero/readback/offcommands, no errors.
Conclusions: controls now work during acquisition; this does not improve FPS.
Ways to resolve: software regression and uncertain-ACK closure gates pass; publish. Speed optimization,
physical array calibration, OTA and MXG remain separate pending work.

## Focused GUI redesign — 2026-11-16

Claim: parent owns release; live run ended and board released.
Test/How: one code-based six-panel view and headless session, reusing guarded
Controller/backend/processLegacyFrame/OfdmAnalyzer. Default launcher clean,
legacy App Designer pair unchanged. Main RF/DSP/algorithm controls retained;
unused/debug/device controls omitted.
Results: synthetic resize/stale/callback/persistence/cleanup fixtures pass;
reviewed loading changes actual weights. Live16 accepted frames, six real plots,
pause/resume/phase/RF/beamformer actions pass. Final5.23%/−25.63dB,6complete5qualified,
EVM outlier18% retained. Four expected stale/expiry/settings rejections.
Both RAMs zero/readback, offcommands, no shutdown errors. Failed pause/callback
attempts retained/fixed. Final Fit/short-window checks pass.
Conclusions: redesigned GUI works with actual samples, no claimed FPS gain.
Ways to resolve: publish default layout. Speed, physical array calibration/DOA,
OTA tracking and MXG rejection remain separate open work.

## ADC/DAC MTS and common start — 2026-11-16

Claim: parent completed the bounded hardware checks; board released. User requested all
ADC/DAC sync as in the installed MTS library. Both tile groups were already
MTS-enabled; the helper had forced free-running da=0 afterward. The new helper
explicitly verifies active masks 0b0101, reference tile2, SYSREF enabled, automatic
target latency and SYSREF mixer events on all4 ADC / both physical DAC blocks.
Mode2 now starts both RAM players and ADC capture from the common capture edge,
then latches selected continuous GPIO enables while that common gate stays high.
No boot, firmware, clock-rate, installed-library or routing changes.

Test/How: two fresh initializations,20 full-RAM captures each, blank/B/A/both/blank;
600 peak per DAC, both aggregate bound1200. Preserve every capture; check rates,
clock lock, clipping, driver MTS latencies and host waveform alignment. Then run
the six-panel MATLAB control/capture regression from DSP with the new helper.
Results:40/40 captures fresh, no clipping; MTS masks5/ref2/SYSREF1 read back.
Within-group active-tile latencies match; A/B waveform lag−1..0 ADC samples,
repeated same-kind captures within±1. No exact-phase/loss-repair claim. DSP MATLAB
live gate exits0,23 accepted frames,6 panels and controls; final5.55%/−25.12dB.
Rejected frames retained.66 Python tests and4-frame simulation pass. Shutdowns
zero/read back both RAMs and command both DACs off, no errors. Board idle.
Conclusions: all active converter MTS plus shared RAM-player/capture start enabled.
Ways to resolve: publish default mode2; recalibrate after re-init, investigate
capture loss separately. No running capture or MATLAB session remains.

## GUI: readouts, diagnostics, themes — 2026-11-16

Claim: parent completed software and one bounded live run; board released. User
asked for a more beautiful and more useful GUI, a light/dark switch, an EVM %/dB
graph switch and stacked pairs (pattern under DOA, time under spectrum, EVM under
constellation). View-only change plus display-only snapshot fields
(`channels`, `health`); acquisition, thresholds, DSP and board helper unchanged.

Test/How: extended synthetic view/session fixtures on DSP MATLAB, design and
review passes with independent verification, then the owned live gate with the
existing helper at the usual low DAC level.
Results: fixtures pass, no leaked figures/timers. Live gate exit0,51 accepted,
8 rejected frames retained, hold/modes/monitor/snapshot exercised; typical EVM
about4.8%, last frame flagged11.1% (2/5 bursts). Stream phase vs stream0 within
0.9° over48 frames of one initialization. Shutdown zeroed/read back both RAMs,
both DACs commanded off, no errors. 66 Python tests pass.
Conclusions: GUI shows existing metrics and makes timing-slip frames visible;
no new RF or beamforming claim. Ways to resolve: sample-loss work stays separate;
phase repeatability across initializations needs its own multi-init run.

## Standalone application — 2026-11-16

Claim: parent completed build and one bounded live run; board released. User asked
for a standalone application published to releases. New entry point
`matlab/standalone/RFSoCBeamformer.m` (simulation with no argument, hardware with
the launcher's settings JSON), simulated four-element source, build script and
launcher option `--standalone`. Deployed sessions use isotropic model elements
because the patch element cannot be deployed. Details: docs/STANDALONE.md.
Results: source demo test passes; compiled v0.1.0 simulation run exit0; compiled
hardware run exit0,38 accepted,4 rejections retained; RAMs zeroed/read back, both
DACs commanded off, no shutdown errors. Runtime-only machine and a full launcher
run with `--standalone` remain untested.
