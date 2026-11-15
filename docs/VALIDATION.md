# Validation — 2026-11-15

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
