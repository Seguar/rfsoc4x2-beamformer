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
