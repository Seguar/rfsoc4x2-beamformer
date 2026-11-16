# Validation — 2026-11-15

Latest: waveform2 direct live demodulation measured over100frames, zeroBER/no
pilot-lock failures; median/maxEVM3.79/9.98%. Raw timing loss persists and the
factory-rate experiment did not produce a compatible workaround. Nineteen host
tests pass. Earlier sections preserve the validation sequence.

**Test:** waveform generation, four-channel tracking/demodulation, adaptive
combining, collinear-path negative control and legacy sample transport.

**How:** five host unittest cases, including positive/negative CFO, delay near
period boundary, conjugation, zero-input rejection, waveform rate/capacity,
fragmented TCP reads and premature disconnect. Five simulated captures vary
CFO from 42 to 50 kHz and delay by 37 samples per capture. A CW interferer is
20 dB above average wanted waveform power per unit-gain path; receiver noise
is 0.02 complex RMS. Training and reserved phase pilots are excluded from BER/EVM.

**Results:** all five tests pass on Python 3 with NumPy 2.3.5 / SciPy 1.17.1.
All five distinct-path simulated captures lock; MVDR payload EVM 1.36–1.48%,
zero payload bit errors; single ADC EVM 95–175%. CFO error stays below 29 Hz
in this five-frame fixture. These figures are simulated, not board measurements.
The collinear control verifies the same spatial gain for wanted and jammer
components; it cannot independently suppress the jammer.

**Conclusions:** the software chain passes the stated fixtures. Live board access,
clock/rate readbacks, RF spectrum, ADC headroom, individual DAC paths, combined
DAC performance, live EVM, long-duration tracking and MXG rejection are unproven.
The staged hardware helper has not yet been executed on this board.

**Ways to resolve:** follow HARDWARE.md, collect independent DAC-only source
captures, establish receive conjugation and frequency response, calibrate hybrid
phase, then measure held-out payload metrics and source-separated interference
power. Record local evidence hashes and publish only reviewed summaries.

## Laptop access attempt and helper corrections

**Test:** live access, generator identification and preflight helper review.

**How:** a laptop agent attempted authorized SSH keys and secure password
delivery, queried candidate VISA resources, ran the same five host tests and
compared archived boot files with the matched runtime manifest.

**Results:** SSH keys rejected; password delivery timed out. MXG queries did
not establish instrument identity or RF state. No hardware capture was made;
no board settings, services or files were changed. Current DAC, boot service
and MXG RF states remain unknown. Archived hashes matched; live hashes were
not obtained. The generated reference is transmit input, not acquired ADC data.

**Conclusions:** hardware testing remains blocked by access. Review identified
missing hard clock-lock gates and fragile shutdown reporting. The helper now
checks lock before and after sync, limits DAC words to 1200 peak, independently
attempts both shutdown writes, retains errors/readbacks and persists status
without masking an earlier experiment error. Sample-frequency units require
explicit selection after driver inspection. Eight host tests pass, including
three new mocked clock/shutdown failure checks; these do not validate driver APIs.

**Ways to resolve:** obtain the current board password using secure file delivery,
establish MXG identity and RF-off, verify installed RFdc units and AXI GPIO slice
read API, then perform the bounded DAC0 experiment. Live lock, rates, headroom,
hybrid calibration, EVM/BER and interference rejection remain unproven.

## Authenticated preflight and ownership release

**Test / How:** authenticated read-only laptop checks of live board identity,
boot hashes, service/process state and installed GPIO/RFdc source.

**Results:** RFSoC4x2/aarch64 confirmed; live boot wrapper/bit/HWH hashes match.
Eight host tests pass. Reference/helper staged without execution. Five notebook
kernels were present; no service, overlay, clock or DAC changes were made.
The original boot service remained running/starting. Credential files were
deleted and absence confirmed. No ADC capture was obtained.

**Conclusions:** the previous raw GPIO readback proposal would also overstate
physical verification: AMD PG144 says output DATA bits read zero. The helper
now avoids PYNQ direction-changing/cached reads and records register snapshots,
command shadows and `dac_off_commanded`, while keeping `dac_off_verified=false`.
Eight host tests pass with these semantics; physical DAC state remains unproven.

**Ways to resolve:** user confirmed the MXG RF cable is disconnected and authorized
stopping all five notebook kernels for the demo. Those two blockers are resolved
for the next exclusive session. Verify installed rate units, stop the authorized
kernels/service, then run bounded DAC0 capture before calibration or both-DAC tests.

## Real-time demonstration software

**Test:** frozen broadside baseline versus pilot-adaptive receive weights under
motion, including independent modulated interference, live framing and dashboard.

**How:** eleven host tests total; new cases compare the same moving half-wave
array captures with frozen and adaptive weights near ±30°, add a stronger
independent modulated jammer, and decode fragmented framed network messages.
The acquisition search whitens spatial covariance so strong modulated-jammer
correlation sidelobes do not win by total power. A fifteen-frame headless dashboard
run and an Agg PNG render exercise the live processing/display without opening
the user's desktop. The physical board stream has not yet been exercised.

**Results:** all eleven tests pass. In the moving-array fixtures the adaptive
payload EVM remains below 3% with zero payload bit errors during the tested
modulated interference cases; the fixed baseline exceeds 50%. These are
simulated, flat-channel half-wave array results, not physical RF measurements.

**Conclusions:** the dashboard now supports the requested real-time comparison
and user beamforming/calibration controls. Actual update cadence, maximum motion
speed and EVM stability remain unproven. Antenna silkscreen 5.2 GHz is user-reported;
the present 2–4.2 GHz passives have not been validated there. Array spacing and
MXG waveform choice remain open.

**Ways to resolve:** complete the initial conducted capture, validate the RF chain
for 5.2 GHz and measure antenna spacing, then follow LIVE_DEMO.md for stationary,
moving and source-separated jammer tests. Record actual frame cadence, outages,
clipping and EVM distributions rather than promising constant EVM.

## First physical captures and receiver correction

**Test:** conducted DAC0 and DAC1 paths separately, ten captures per path. This
used the common combiner/splitter wiring before the user changed to a direct cable.

**How:** authenticated exclusive board run; matched live boot hashes and clock
lock confirmed. Runtime ADC5GHz/40=125Mcomplex/s, DAC10GHz/interpolation10 with
datapath3/IMR2=500Mcomplex/s input. The first1Gcomplex/s reference was wrong.
A corrected private reference produced ten distinct acquired frames per DAC.

**Results:** no digital rail hits; maximum I/Q component peaks573 codes(DAC0),
626(DAC1). Original receiver MVDR payload EVM remained87.9–148.1%(DAC0) and
80.4–1076.2%(DAC1), with substantial bit errors. These are failed demodulation
results, not a working RF demonstration. No combined-DAC calibration/run occurred.
Jupyter ended running with zero kernels; bootpy had no process and systemd
failed/failed state. Both DAC disables were commanded; physical RF-off unverified.

**Conclusions:** IMR2 must be included in waveform generation. Further source
inspection found the matched HWH ORs ADC trigger into both DAC enables. The old
helper loaded both DAC memories; therefore low GPIO enable did not ensure a
single-waveform capture. An offline diagnostic of DAC0 frame0 finds reference
copies at914 and69samples; fitting two copies reduces normalized residual from
0.708 to0.195. This fit uses the full known waveform, including payload, ONLY for
diagnosis; it is not a valid demodulation/EVM claim. In addition, wrapper da0
reads RAM without a completion wait, so capture tearing must be excluded.

**Ways to resolve:** regenerated reference uses4:1 resampling to16384 complex
samples repeated twice in DAC RAM. Helper verifies IMR2 rates, zeros the unused
DAC memory and waits3ms after capture trigger. C_ALL_OUTPUTS is read from actual
IP parameters, handling unimplemented TRI registers. Fifteen host tests pass,
including source-selection, capture-order and ADC0-only checks. User now connected
DAC_A → BW-S20W2+20dB → ADC_A; repeat a bounded DAC0-only test and analyze with
--adc0-only. Corrected hardware EVM, streaming and OTA behavior remain unproven.

## Direct ADC_A capture and live transport

**Test:** user-connected DAC_A → BW-S20W2+20dB → ADC_A, commanded3GHz/peak1200;
DAC_B RAM zero, MXG disconnected. Three ten-frame capture runs and two thirty-frame
headless live sessions; original waveform1 and ADC0-only receiver.

**How:** runtime checks confirm ADC125Mcomplex/s and mode3 DAC500Mcomplex/s, both
clock-lock reads1. Source/capture files remain private. Coordinator independently
verified all59 delivered file hashes and reprocessed the saved capture with the
historical waveform version. Diagnostic10ms settling was also attempted.

**Results:** all bounded frames acquired the pilot. Good frames show approximately
3%EVM and zero payload bit errors. Intermittent live errors reach65.55%EVM and
BER0.159. No digital rail hits; largest observed ADC_A I/Q component333codes.
One live session records contiguous sequence0–29,8.62captures/s and47–109ms host
post-receipt age.32 instrumented raw frame hashes differ.10ms wait does not cure
payload errors. Boot service ended failed/no process, Jupyter running/zero kernels,
own server stopped, bothDAC disable commands recorded; physical RF-off unverified.

**Conclusions:** acquisition, fresh-frame transport and intermittent demodulation
work. Stable reception is unresolved. Diagnostic fits using the full known waveform
show a roughly one-sample advance within some bad payloads, with clean initial
training. These fits are for fault location, not reported EVM. The old adjacent
pilots estimate common phase but poorly constrain timing phase slope.

**Ways to resolve:** investigate the actual matched capture/playback handshake and
clock domains on hardware. Waveform2 distributes pilots at−21,−7,+7,+21 and fits
common phase plus frequency-linear phase per payload symbol, excluding pilots from
EVM/BER. Version tags prevent reinterpretation of old captures. Nineteen host tests
cover timing drift, corrupted payload remaining visible, within-symbol sample loss
remaining visible, and installed GPIO metadata fallback. The new timing tracker
does not repair arbitrary missing samples and has not yet passed a physical test.

## Full-memory timing and capture-clock control

**Test / How:** eight full-RAM records with unchanged waveform1, immediate settled
RAM rereads, full DAC memory readback and two negative controls lowering only the
PS capture clock. The original clock was restored in finally. No new FPGA build.

**Results:** every RAM reread agrees bit-for-bit. Stored DAC0 contents match the
tiled reference; DAC1 RAM is all zero. Received waveform timing advances99.4–100.8ppm
over the long records. Lowering the driver-calculated PS clock124.99875→99.999MHz
contracts a4096-sample received period to3276samples. RFdc status flags do not
measure downstream capture-converter occupancy. No improvement/EVM claim is made
from this diagnostic, and DAC physical timing was not independently scoped.

**Conclusions:** downstream capture throughput is a supported leading explanation
for sample loss; exact synthesis-matched RTL attribution remains open. A longer
settle wait or refilling an already-correct DAC RAM cannot establish a fix.

**Ways to resolve:** inspect matched capture/backpressure RTL and measure clock
relationships. A separate bounded experiment will check an installed vendor RF
clock profile with a source rate below the125MHz capture domain, preserving the
sink's original clock constraint. Clock profile compatibility, rate metadata,
locks/MTS and before/after raw timing loss must be validated before adopting it.
The host reference/analyzer now accept explicit or recorded sample rates; this
software capability does not change hardware clocks or validate a profile.

## Waveform2 physical validation

**Test:** fresh v2 reference, commanded3GHz/peak1200, direct20dB DAC_A/ADC_A path.
Thirty bounded frames,100headless live frames and four full-RAM diagnostics.

**How:** unchanged reviewed public helper atbd73eac, ADC0-only receiver, training
and distributed pilots only for channel/phase/timing; no bad-frame exclusions or
payload fit. Coordinator independently verified60file hashes, reprocessed all30
saved bounded captures and checked all100live records. Original500/500clockprofile.

**Results:** bounded min/median/p95/maxEVM2.89/3.49/8.44/8.89%, live3.34/3.79/8.55/9.98%.
All payload BER values are zero; every frame acquired; live sequences0..99 complete.
Median live interval110ms and host post-receipt age78ms. Raw full-RAM advance still
99.45–100.43ppm: DSP tracking improved finite-run payload reception, not raw capture.

**Conclusions:** live single-channel demodulation is demonstrated for the finite
run. Constant EVM, lossless raw capture, motion tracking, array gain and MXG rejection
remain unproven. Factory LMK245.76/LMX491.52was physically switched/restored with
zeroed DAC RAMs and lock asserted, but its PL routing/MMCM ratios and mixed external/
PLL converter topology do not match this overlay. No compatible lower-rate RF
capture or rate-setting workaround was validated; lock alone is insufficient.

**Ways to resolve:** keep the validated500/500profile for the conducted demo.
The host launcher packages the repeatable direct test; validate its end-to-end
startup/shutdown separately. Obtain synthesis-matched capture RTL or a supported
clock/distribution redesign before claiming lossless capture. Later array tests
need four RF inputs, measured spacing, a suitable5.2GHz chain and a separate jammer
direction. Both DAC RAMs ended zero, disable commands recorded, boot service
stopped, Jupyter running, credentials retained privately; physicalRFoff unverified.

## One-command launcher lifecycle

**Test:** complete direct-cable startup, 100-frame headless live session, disconnect,
DAC shutdown, artifact retrieval and process cleanup on the Windows laptop.

**How:** stock launcher at 1c8689e streamed correctly but failed retrieval because
of a Path/string precedence error. A private copy with the one-line parenthesized
path fix completed a fresh run, exit 0. The identical fix is now applied publicly.
No graphical interaction was performed; the dashboard has been rendered with Agg.

**Results:** 100 unique processed sequences, no pilot-lock failures, zero payload
BER and no digital rail hits. EVM min/median/p95/max: 3.30/3.89/8.27/9.73%.
Capture cadence 8.63 frames/s; median host post-receipt age 70.5 ms. Retrieval
includes the final raw capture and manifest. Both DAC RAM clears and independent
disable commands completed with no shutdown errors. No capture server remains;
Jupyter runs with zero kernels; bootpy is stopped with no process; boot hashes
are unchanged. Private configuration/password remain outside the repository.

**Conclusions:** the patched finite headless lifecycle passes. Direct live EVM is
demonstrated within the measured limits; GUI interaction, constant EVM, physical
RF-off, capture-loss repair, antenna tracking and MXG rejection are not established.

**Ways to resolve:** run the launcher from the updated laptop checkout to view
the live ADC_A display. Preserve the 20 dB direct cable and use the private config.
Close the display to end its capture session. Before array work, resolve the
5.2 GHz RF chain, connect all four receive inputs and measure antenna spacing.

## EVM units in the display

**Test:** show EVM in dB alongside percent and preserve both in saved metrics.
**How:** convert RMS error with 20log10(EVM(%)/100); render the live and static
plots headlessly with a secondary percent axis.
**Results:** all 19 host tests pass; rendered labels and JSON fields checked.
**Conclusions:** this is a display/reporting change; receiver processing is unchanged.
**Ways to resolve:** update the laptop checkout and restart the display to use it.

## Connector labels and signal-loss display

See also [MATLAB/VSA validation status](MATLAB_VSA.md). Python live results below
do not establish MATLAB frontend or VSA demodulator behavior.

**Test / How:** compare the matched HWH transmit AXIS routes and RFdc tile indices
with the board reference manual; exercise noise-only acquisition and clear a
previous good EVM in a rendered signal-loss state.
**Results:** logical dac0 maps to physical DAC_B, matching the user's correction.
All21 host tests pass. Noise-only cases reject pilot lock; stale/unlocked display
clears current EVM, constellation, phase and CFO. RX RMS level is now logged/shown.
**Conclusions:** prior transmitter letter labels were wrong, not proof of a stale
stream. Actual cable-loss behavior and the revised running GUI still need checking.
**Ways to resolve:** restart the user's live session with the corrected connector
metadata and freshness display, then compare fresh levels/lock during cable changes.

## MATLAB processing and conducted loopback

**Test:** execute the corrected MATLAB core, strict TCP boundary and complete
direct DAC_B → BW-S20W2+20dB → ADC_D lifecycle, then leave the MATLAB GUI visible.

**How:** source c87817f exported to private staging. Unchanged differential core
and transport gates, all-source MATLAB checkcode and 26 Python host tests. Private
corrections replaced a nested cleanup closure with captured per-resource cleanup
handles and guarded VSA EVM against invalid IQ, summary status and correlation.
After the cleanup correction, a fresh 100-frame physical run completed. Every
processed frame is retained in the private metrics log; no exclusions.

**Results:** all twelve beamformer software checks pass, including iterative-load
root/endpoints and isotropic closed form. Independent Python/MATLAB simulated EVM,
BER and CFO agree. Fragmented localhost TCP, exact IQ, sequences, duplicate and
framing/error controls pass. Seven SIMULATED VSA reader cases pass; these include
rejection of NoSync, unknown bit32, stale input and low/nonfinite correlation.

The fresh physical MATLAB run has 100 unique sequences0–99, all locked, zero BER.
EVM min/median/p95/max: 2.88/3.31/7.30/8.30%, or −30.82/−29.61/−22.74/−21.62dB.
RX0 RMS is −48.31 to −48.28dBFS. Saved final raw capture component peaks are
343/368 codes, with no rails; this raw headroom check covers that final capture.
Both DAC RAM clears/off commands and no shutdown errors are recorded for the
finite run. A subsequent durable MATLAB GUI was left visible with advancing
sequences; that active session holds hardware ownership until orderly closure.

**Conclusions:** MATLAB direct conducted acquisition, demodulation and finite
cleanup are validated. This does not validate physical array beamforming, OTA
angle tracking, constant EVM, MXG rejection or independently measured RF-off.
Actual VSA EVM/lock remains unavailable; its reader contract has simulated tests
only. The controlled MATLAB GUI loss/pause/close campaign remains incomplete.

**Ways to resolve:** keep the active MATLAB owner exclusive. Test the effective
VSA CustomOFDM configuration and Input.DataFrom Hardware versus Recording, then
obtain a valid positive control with noise/wrong-setup rejection. Later connect
and calibrate the array before physical beamforming claims. Raw capture timing
loss is unchanged by this host refactor.


## DSP matched SETX replay and guarded status policy — 2026-11-15

**Test:** Offline DirectDataSource synchronization with the repository FFT64 SETX
and matched 500MHz waveform resampled to125MHz; no board or RF writes.
**How:** Two positive/noise/positive/wrong-SETX cycles in a new owned VSA session,
finite original samples, no repetition or padding. Reader contract adds simulated
known-fault, unclassified-bit, indicator, measurement-error and stale controls.
**Results:** Eight fresh acquisitions. Four matched positives: EVM0.0523031%
(−65.6294dB), sync0.999996. Noise sync0.102962 and wrong-setup sync0.147488 were
rejected with NoSync. MATLAB batch exited0 with completion sentinel; 24 simulated
reader cases and 28 Python host tests pass.
**Conclusions:** Offline matched replay works under an explicit SETX warning
policy. Bit32 remains vendor-unclassified, recorded in quality/status and shown
in the GUI; it has not been redefined as a named enum. Default strict behavior
still rejects it. All other nonzero bits and vendor fault indicators are rejected.
**Ways to resolve:** Finish two-instance adapter repeatability and matching live
legacy-waveform acquisition. These results do not validate live VSA, antenna
tracking, jammer rejection, or repair capture sample loss.

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


## Original UI → native VSA: first bounded live test — 2026-11-15

**Test:** Matched legacy FFT64 waveform through conducted DAC_B →20dB→ADC_D,
full contiguous ADC RAM, original MATLAB UI and a newly owned native VSA.
**How:** Three orientation captures plus21 original-UI frames (16 wave,5 blank),
explicitly truncated DAC loop at peak1200; burst-phase analysis selects a genuine
contiguous window clear of its boundary. ADC125Mcomplex/s andDAC500Mcomplex/s.
The existing0.5 VSA summary-correlation guard was retained for the live baseline.
**Results:** All16 wave frames yielded fresh correlated summaries (sync0.991–0.992).
EVM median4.5633%; one frame reached27.5547% and remains in the record. Four blanks
were rejected, but blank sequence14 passed at sync0.541988 with EVM1687.768%.
Transfer age was2.2–4.7s with allfour full-RAM channels; the private runner needed
a6s age limit. A9s pause cleared the original UI. Both DAC RAMs were zeroed and
DACoff commanded without errors; helper and owned VSA exited, boot files unchanged.
**Conclusions:** Original-UI/native-VSA transport and live positive demodulation
work, but the noise-rejection gate FAILED and default2s freshness was not met.
Offline replay using0.9 correlation rejected the5 saved blanks; this is not a
new live validation. Raw capture sample loss remains unresolved.
**Ways to resolve:** Apply a profile-specific0.9 summary-correlation guard plus
independent wanted-reference lock, preserve vendor raw values and all failures,
reduce direct-mode payload or use a verified faster path, and repeat held-out
live wave/blank/pause controls before a durable user launch. Do not raise the
stale deadline and call that a latency improvement. No physical DOA/MXG claim.


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

## Responsive window + four-stream window transport (2026-11-16)

- **Test:** user report "app doesn't show DOA and patterns and can't scale". Causes:
  launcher forced directOnly with ADC_D only (three zero placeholders), and an
  835x949 design window with fixed 949-px reflow rows that did not fit a 1646x1029
  (175 %) or 1366x768 screen. Fix both; bounded live gates on the current common
  feed (DAC_B logical0, peak 1200, DAC_A RAM zero, ZAPDQ-4 -> ZA4PD-4 -> 4 ADCs).
- **How:** three whitelisted model changes (figure 1180x680, LeftPanel scrollable,
  left column 250) rebuilt with build_mlapp_resp and checked by verify_mlapp_resp
  (only those properties differ; export blocks, uifigure block and generated reflow
  equal the model); start-up fit to the screen; axes toolbar zoom/pan/data tips/
  restore plus Autoscale (follows data, off after zoom/pan) and Tight. Helper v3
  `--wire-mode window4`: one contiguous 32768-row window of the same full capture
  carrying all four streams (524288 bytes, same as v2), selected on the board away
  from the loop wrap; start row, full-capture and window SHA256 in every frame.
  Host re-checks per-stream lock, burst-phase jumps, window SHA and repeated
  capture SHA. Array mode feeds VSA the app's combined weighted output, labelled.
- **Results:** runScaleFixture passes 9 window sizes (incl. 1366x697 work area,
  narrow reflow) and 6 monitors; runWindow4Fixture (offline fake stream) recovers
  steered 20/20/-35/10 deg, rejects blank, dead stream, stale capture, corrupt
  window SHA, wrong-frame and zero-padded VSA input, a real loop wrap (jump
  -6459.25) and a 300-sample loss. Live gates (bounded 15/27 frames) all ended with
  both DAC RAMs zero readback and enables off commanded, clock lock 1 every frame.
  Final gate: 21/24 wave frames guarded-valid, combined-output VSA EVM median
  2.45 % (2.33-28.1 %, one outlier at sync 0.937 kept), sync >= 0.9366, ages at VSA
  done median 1.26 s; 2 frames stale (warm-up 2.82 s, 2.11 s); 1 continuous window falsely rejected by
  the old VSA block check; blanks rejected as no wanted signal. The initial replay
  also falsely classified that window as a wrap.
  **Corrected interpretation:** the seq-25 refusal came from the VSA path's own
  8192-block analysis of the combined buffer, not from the host flag (host
  `boundaryFree` was true and nothing enforced it; the frame was still plotted and
  averaged). Frame-timing analysis of the saved raw window shows no wrap: frames
  0,1,2,3,4,0 at constant timing and a 2165-row silent prefix on all four streams,
  longer than the 1543-row pre-wrap gap. The "wrap" was a burst-label artifact of the
  block analysis (block 1 aligned across the loop end). Frames stale at VSA
  completion (2.82 s, 2.11 s) were also plotted. The combined-output EVM was not
  compared with single-stream EVM on the same frames: no combining gain is shown.
  A live stream-3 dropout (RMS 75 -> 6.9 counts for 5 frames) was rejected per frame.
- **Conclusions:** DOA spectrum and pattern are measured four-stream data through
  the explicit ULA model (d = lambda/2 at 3 GHz), labelled common-feed diagnostic /
  array model and UNCALIBRATED; with a common splitter feed they are cable/path
  diagnostics, never physical arrival angles. The loop is burst-periodic, so block
  reference correlation is ambiguous by whole bursts; board selection uses self-
  similarity. The old host burst-phase check has been replaced below.
- **Ways to resolve:** measured geometry, connector mapping (streams 1-3 unverified)
  and a fresh frozen calibration before any physical DOA/OTA claim; investigate the
  stream-3 dropout cabling; durable window4 run after review. Editor round trip of
  the rebuilt .mlapp remains untested.

## Window4 host continuity check (review B1/M1/L1 follow-up)

- **Test:** close the review's blocking finding: a window4 frame whose window holds
  the loop wrap or a large sample loss must be refused by the host before Controller
  admission, VSA and the DOA/pattern plots, with VSA on or off; frames that age past
  2 s while VSA runs must not be drawn; the Cutter must not zero-fill window4 frames.
- **How:** measured reference structure: a burst is 5 OFDM frames of 5501.25 rows
  (~3000 active, ~2500 silent); frames differ, whole bursts repeat; the wrap sits in a
  shortened 1543-row silent gap. `origapp.windowIntegrity` fits one continuous
  frame-timing hypothesis to every active run (256-row chunks plus 32/16-row edge
  chunks, correlation >= 0.6, lag +-2, +-4 across a gap, spread <= 8) and every
  predicted-silent row; fail-closed edge rules (start <= 1559 rows before a burst
  start, end at the truncation phase, active edge run < 64 rows). Controller refuses
  `boundaryFree=false` (origapp:Boundary); selector fallback/none/missing/unparsable
  summaries are refused; processArray re-checks age after VSA (origapp:Expired). The
  board shifts window starts away from the host's edge rules (<= 2048 rows,
  alignment unchanged). Developed on saved gate3b/4/5 windows and three saved
  full-RAM captures; Python prototype and MATLAB agree on 256/256 real-data cases.
- **Results (software):** real wraps cut from 3 full captures at 1395 positions (incl.
  1-64 and 32704-32767 pre-wrap rows) all refused; 300-row losses at 15 positions on
  30 clean windows refused unless the loss touches no active row interior (outermost
  <= 8 active rows, or wholly in a silent prefix/suffix); ~100 ppm one-row advances
  accepted (30/30); 300 synthetic captures with 13 slips: board -> host 297 accepted,
  3 refused = the 3 windows that really held the wrap (board misjudgement), 0 false
  accepts, 0 false refusals. runWindow4Fixture: VSA off 21/21 and VSA stub 9/9
  (wrap in first/last block, 300-loss at edges, fallback/no-candidate/unparsable
  summary refused before VSA/plots, Avg reset, no stop; delayed stub -> Expired
  clears plots; recovery). Host check 0.02-0.12 s per window.
- **Results (hardware, bounded, DAC_B logical0 peak 1200, DAC_A RAM zero, common
  feed to 4 ADCs):** gate A 27 frames and held-out gate B 26 frames; every full-RAM
  capture saved: capture SHA equals the board-reported SHA, every window equals its
  capture rows; ground truth (shortened gap in the full capture) shows no wrap in any
  of the 46 wave windows, all host-accepted (0 false accepts; no live bad window
  occurred, so live refusal is shown only by fixtures and real-capture replays).
  VSA (combined input) guarded-valid 22/24 and 19/22; refused: 4 frames older than
  2 s at VSA completion (also not plotted: Expired) and one sync 0.852. Blanks
  refused as NoSignal. Both runs ended with both DAC RAMs zeroed, enables off
  commanded, clock lock 1 at every readback.
- **Conclusions:** the edge-block blind spot is closed for wraps and large losses,
  independent of VSA. The historical gate5 seq 25 window is continuous (the earlier
  "wrap" was a burst-label artifact of the 8192-block analysis); VSA's own block
  analysis can still refuse such a window (fail-closed, VSA only).
- **Ways to resolve:** VSA-side window choice still uses the burst-ambiguous block
  analysis (may refuse continuous windows); a durable window4 run after parent
  review; physical DOA needs geometry, connector mapping and calibration.

## Integrated Custom OFDM viewer — parent audit, 2026-11-16

**Test:** visualize and demodulate the original app's actual output buffer without
requiring a native VSA measurement each frame. Preserve the original controls,
DOA/pattern, current-data clearing and waveform/setup pairing.

**How:** a1 implemented a SETX-pinned FFT64/CP16 profile, using an 80-point receive
FFT at 125 MHz. Training estimates the channel; known pilots track phase, timing
and amplitude. The parent independently reimplemented synchronization and
complete-burst EVM in NumPy and replayed every one of fifteen saved G1 buffers.
Payload samples never fit the equalizer. This audit is offline replay of measured
buffers, not a new hardware run.

**Results:** MATLAB and NumPy match complete/qualified counts on every buffer;
maximum primary-EVM difference is 1.8e-14 percentage points. The twelve signal
buffers have primary median EVM 6.00%, including all 64 complete bursts, of which
51 qualify. Qualified-only median is 4.46%. Three blank buffers remain unavailable.
Primary EVM retains timing-slip/training-quality failures and reports DEGRADED.
Incomplete and undetected bursts are outside that metric; coverage is displayed.
39 Python tests pass (seven optional environment-dependent tests skipped).

Earlier a1 live results used qualified-only EVM: eleven signal frames at
4.30–5.06% in a blank/pause gate; a 200 s integrated-only run had 215/216 locked
frames, 1.29 frames/s, median plot age0.48 s and EVM age0.53 s. Those figures
predate the inclusive primary metric and the parent's one-request prefetch fix;
they are historical implementation evidence, not a benchmark of the final source.
Both runs ended with both DAC RAMs zeroed/read back and off commanded.

**Conclusions:** integrated visualization and payload metrics work on the matched
legacy waveform. Vendor EVM is a separate metric: its pinned setup enables
data-aided equalization/tracking and different symbol/cell coverage. No numerical
equivalence is claimed. BER and data-aided equalization are unimplemented.

The parent final MATLAB gate also passes: App Designer rebuild/independent verify,
original/new-port/admission/smoothing regressions, OFDM34/34, zero stray figures
or timers, process exit0 and PARENT_CUSTOM_OFDM_COMPLETE sentinel.

**Ways to resolve:** finish a bounded live run of the reviewed source, then launch
that version visibly. Physical arrival angles,
OTA motion tracking, spatial jammer rejection and capture-loss repair remain open.

### Reviewed integrated-only hardware gates

**Test/How:** frozen rebuilt source, DAC_B only (peak≤1200), common hybrid/splitter
feed to all four ADCs; integrated analyzer, unchanged integrity/.3 lock/.8 sync/2 s
guards. All windows saved; no vendor VSA started.
**Results:** blank/pause gate and 150 s continuous bound both exit0, clean RAM
zero/readback and DAC-off commands. Continuous:201 captures,192 valid integrated
measurements,169 degraded; primary EVM median4.83% (−26.3 dB), range3.86–20.3%,
qualified-only median4.08%,1026 complete/742 qualified bursts. Offline replay
reproduces all193 analyzed frames exactly. Acquisition cadence1.75Hz, median plot
age0.49s; one no-prefetch comparison1.23Hz. This is one run each, not a general
performance guarantee. Six stream0 dropouts were refused and recovered. One
unidentified runtime error remains; its buffer replays cleanly.
**Conclusions:** inclusive EVM and capture prefetch work live. No physical DOA,
combining gain, vendor equivalence, MXG rejection or independently observed RF-off.
**Ways to resolve:** viewer AutoResizeChildren is now disabled so the actual resize
callback can run; Controller failures persist to private errors.jsonl; launcher
cleanup uses a value-captured handle. Follow-up software checks pass (34/34 OFDM cases, actual resize callbacks,
three persisted error records, zero stray figures/timers, exit0 and completion
sentinel). A visible launch checks the final launcher lifecycle. Investigate physical stream0 dropout separately.

## Live MATLAB-to-board commands, 2026-11-16

**Test:** separate control socket while the same RFSoC4x2 captures four-stream IQ.
**How:** native MATLAB client/backend on DSP; staged helper owned over SSH by DGX.
Legacy command names use the 4x2 wrapper. Capture and settings share a hardware
lock; applied acknowledgements and acquisition revisions prevent old buffered data
from entering plots after a settings change. No notebook kernel is required.
**Results:** live test exits0 with BOARD_CONTROL_LIVE_COMPLETE and DSP sentinel.
Eleven direct commands plus a queued batch pass: DAC phase45°/0° readback, ADC
phase, same-frequency retuning/readback, fixed-size acknowledgement, pause/status/
resume, DAC RAM off/on with signal disappearance/recovery. Four invalid commands
are rejected; three obsolete captures are discarded. ACK0.15–0.33s. Both DAC RAMs
zeroed/read back and enables commanded off, shutdown_errors empty. No helper left.
61 Python cases pass with the reference supplied (no skips); DSP command-queue,
admission and original/new-port MATLAB regression suites pass with completion
sentinels and exit0, zero leaked figures/timers.
**Conclusions:** commands work during acquisition; no FPS improvement, physical
DOA, coherent dual-DAC gain, jammer rejection or independent RF-off claim.
**Ways to resolve:** publish the reviewed control path. Fixed frame size, automatic
ADC calibration, waveform upload and ZCU216-only commands remain explicitly
unavailable in this session. Capture/transport optimization remains separate.

## Focused six-panel GUI, 2026-11-16

**Test:** retain DOA/pattern/spectrum/time/constellation/EVM and main RF/DSP controls
in one responsive window, removing unused/debug/device controls from the default.
**How:** code-based BeamformerView plus headless DemoSession reuse the existing
Controller, transport, processLegacyFrame and inclusive OfdmAnalyzer. Synthetic
fixtures verify actual resizing, user zoom, fixed graphics counts, callback rollback,
calibration guards, reviewed-loading weight changes, immediate pause clearing,
command strings, same-buffer vendor feed and zero leaked figures/timers.
**Results:** GUI/session fixtures exit0 with completion sentinels;61 Python tests
pass with no skips. A DSP-hosted bounded live run accepted16 frames, exercised
pause/resume,15°→0° DAC phase, same-frequency apply and beamformer selection; all
six panels displayed actual samples. Final frame5.23%/−25.63dB,6complete5qualified
bursts; the EVM history retained its~18% outlier. Four rejections were stale/expiry
and settings-revision clearing. Earlier failed pause/callback checks were fixed and
retained. Both DAC RAMs zeroed/read back and enables off commanded, no shutdown
errors. No old hidden GUI or separate integrated-viewer window was created.
**Conclusions:** the redesigned layout works on hardware and retains metric guards.
This is not a throughput benchmark or proof of physical angles/gain/jammer rejection.
**Ways to resolve:** publish as launcher default; use --layout legacy for the earlier
App Designer interface. Capture-loss/speed work and physical-array validation remain
separate. The old .mlapp/export are unchanged; the clean frontend is code-based.

## ADC/DAC MTS and shared playback start, 2026-11-16

**Test:** enable all active ADC/DAC synchronization as in the installed MTS library,
then verify real waveform timing and the live MATLAB frontend.
**How:** explicit masks5 (tiles0/2), reference tile2, SYSREF enabled, automatic
latency−1 and all six physical mixer SYSREF events. Mode2 starts both RAM players
with the shared ADC trigger before separate GPIO enables are latched. Two fresh
initializations each captured20 full-RAM frames: blank2, DAC_B4, DAC_A4, both8,
blank2,600 peak per DAC and aggregate bound1200. Host analysis retains every frame.
A separate DSP MATLAB gate used the final helper, DAC_B≤1200 and inactive DAC_A
full-RAM zero/readback. Original age/lock/integrity and metric guards unchanged.
**Results:** both converter groups reported SYSREF1/ref2/mask5. ADC active-tile
latencies280/280 in both runs; DAC1460/1460 then1500/1500. ADC offsets were0/0 then
0/1; DAC offsets0/0. All40 captures refreshed, no clipping, maximum component220
codes. A-versus-B recorded waveform lag was0 in the first initialization and
−1..0 ADC samples in the second. Same-kind repeated-capture lags stayed within
±1 sample. Both-DAC reference locks ranged0.660–0.929; blanks0.032–0.037.
The large prior asynchronous RAM-player offset was not seen in these runs.
The MATLAB gate exited0 with completion sentinel:23 accepted frames, all six
panels, pause/resume, phase15°→0°, RF reapply and beamformer selection; final
primary EVM5.55%/−25.12dB,5 complete/4 qualified bursts. All rejected frames are
retained.66 Python tests pass, plus4-frame simulation and syntax/diff checks.
Both full RAMs were zeroed/read back and DAC-off commanded after every run,
without shutdown errors. No boot files, clock rates, FPGA images or services changed.
**Conclusions:** converter MTS and common playback/capture start are enabled and
measured on this topology. This is not exact fractional-sample alignment, a
capture-loss repair, combining-gain proof or an independent RF-off observation.
**Ways to resolve:** default original-app launches now use mode2 and stage the
MTS module. Recalibrate paths after reinitialization; automatic latency changes
between inits. Known sample loss and precise cross-DAC phase/timing remain separate
hardware work. No hardware or MATLAB session is left running.
