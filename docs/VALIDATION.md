# Validation — 2026-11-15

Latest: direct capture and live transport demonstrated, but payload EVM remains
intermittent. Version2 distributed timing pilots pass nineteen host tests and
await hardware validation. Earlier sections preserve the validation sequence.

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
