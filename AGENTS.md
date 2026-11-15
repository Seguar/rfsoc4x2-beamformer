# Agent instructions

Read README.md, PLAN.md and docs/HARDWARE.md before work. Read docs/VALIDATION.md
before describing results; docs/LIVE_DEMO.md defines the real-time antenna demo.
This repository is specifically RFSoC4x2 / xczu48dr;
ZCU216 overlays, clocks, DAC indexing and burst protocols do not apply.

MATLAB work must also read docs/MATLAB_VSA.md. Keep the original reference .mlapp
and exported .m unchanged unless both can be updated consistently. The replacement
frontend lives in matlab/. Maintain X*conj(w), training-only channel estimates and
payload/pilot separation. Do not fit payload EVM away. Do not claim VSA lock from
a completed acquisition alone. Validate the waveform/setup pair and report VSA
metrics separately from the held-out MATLAB payload metric. VSA sessions must own
their new application and never attach to unrelated instances or delete global
instrument handles. The legacy boot-loop module is staged, not deployed firmware.

## Ownership and workflow

Use one hardware owner at a time. Record claims and handovers in PLAN.md; claims
hold until released. Keep the desktop free: headless commands only unless the
user explicitly requests GUI work. No subagents unless the user requests them.
Change only your owned paths. Do not commit another session's work. Commit with
explicit paths; fetch and compare upstream before pushing. User authorized this
repository to be public, so publish reviewed code only. Never publish addresses,
credentials, raw board archives, private measurements or calibration files.

## Hardware rules

- Verify device-tree `chosen/pynq_board` is `RFSoC4x2`, not just its SSH key.
- Read the matched boot-wrapper/hardware manifest in doa_rfsoc/main before use.
  Importing the wrapper touches OLED; constructing it programs clocks and FPGA,
  restarts zocl and performs MTS. Reading code is not a hardware-free import.
- User authorized live loopback work. Stage new experiments in a new directory;
  never replace /boot, reflash, rebuild FPGA, change routes or start at boot
  without a separate explicit task. Keep original files and hashes intact.
- Stop the existing service before exclusive wrapper access; record prior state.
  An automatically restarted boot service may reload its original waveform and
  RF settings. Do not restart it blindly at experiment end. Record its end state.
- DAC output starts low (1200 integer peak); measure ADC headroom and spectrum
  before increasing. No inferred dBm from DAC codes. Shut down both DAC GPIOs
  in finally and record disable commands and direction registers. PYNQ InOut
  slice reads change direction; Output reads use a software shadow. AXI GPIO
  output DATA register reads return zero, so neither proves physical RF-off.
  Record `dac_off_commanded` separately from independent RF-off observation.
- ZAPDQ-4 is a 90-degree hybrid; calibrate DAC paths individually before both.
  The splitter/combiner band is 2.0–4.2 GHz. 3 GHz is the initial candidate;
  verify actual RF response and board front-end support before claiming it.
- Verify ADC/DAC rates and interpolation/decimation at runtime. Generated
  reference assumes 125 Mcomplex/s ADC and 500 Mcomplex/s DAC input, 4:1 ratio:
  mode3 adds IMR2 beyond interpolation10. A 16384-complex period repeats twice
  in the32768-complex DAC RAM. Regenerate old1G reference files.
- Matched HWH ORs ADC capture trigger into BOTH DAC player enables. Zero the
  entire unselected DAC memory; a low software enable alone cannot prevent its
  waveform during capture. Wait after the trigger before copying ADC RAM;
  wrapper da0 has no completion wait. Do not call get_custom_data blindly.
- Legacy TCP streams continuously and ignores controls while streaming.
  Receive exact byte counts. No ZCU216 `stream N` or `dacbf` commands.
- MXG Ethernet is control, not evidence of an RF path. Query its identity/state
  using an explicit local VISA resource. Keep it RF-off for initial loopback.
  Do not enable or raise MXG output until its RF connection and level are known.

## DSP and verification

Run `python -m unittest discover -s tests -v`, then the simulated demo. Use
`python -m rfsoc_demo.cli reference` for the reviewed waveform. Wire samples
are little-endian eight-lane int16, `I - jQ`, sample x channel. TX uses `I + jQ`;
test the receive conjugation and RF sideband. Keep DAC period exactly compatible
with RAM capacity. Training determines synchronization, steering, weights and
channel equalization. Reserved payload pilots track phase. EVM/BER exclude all
training and reserved pilots; never fit gain to evaluation payload.

Distinguish simulations, calculated values, measured data and assumptions.
Common splitter paths cannot demonstrate angle estimation or independent DAC
receive steering. A jammer entering before that splitter cannot be spatially
nulled independently of the wanted signal. Keep that negative control.
Do not label total residual reduction as jammer rejection without separate
source captures. Validate lock, clipping, stale frames, phase drift and output
state on hardware; software tests do not establish RF performance.

For the real-time demo, keep calibrated fixed-broadside weights frozen until an
explicit recalibration; frame-by-frame MRC is also adaptive and cannot serve as
the beamforming-OFF baseline. Show both metrics from each same capture. User's
antennas are labelled 5.2 GHz, spacing unknown; ±30° simulated nulls assume a
half-wave four-element ULA. Do not relabel simulation angles as live estimates.
CW versus modulated MXG waveform remains open. Constant EVM under rapid motion
and physical jammer rejection require measured validation. Stream port4010 uses
its own framed protocol, distinct from legacy4000; avoid unlimited RAM buffering.

Current user-confirmed cabling: DAC_B → BW-S20W2+ 20dB attenuator → ADC_D; DAC_A unused.
Use --adc0-only in host analyze/live until all ADC channels have wanted RF again;
this direct diagnostic cannot establish beamforming gain. The earlier combined
captures had unwanted delayed reference copies and poor EVM; keep them labelled
failed demodulation evidence. All-output GPIO cores lack a meaningful TRI register;
read C_ALL_OUTPUTS from IP parameters rather than hardcoding it.

Waveform2 uses pilot bins−21,−7,+7,+21 for phase AND timing-slope tracking;
regenerate TX reference and keep waveform_version metadata in NPZ/stream/report.
Untagged historical captures and streams use version1, with adjacent pilots and
common-phase correction only. Never reinterpret old payload with a new pilot map.
Tests must preserve nonzero error for corrupted evaluation data and a sample loss
inside an FFT window. Pilot timing tracking cannot repair arbitrary sample loss.
Live evidence currently shows~3%EVM on good single-channel frames with large
intermittent errors; hardware cause/timing fix remain unproven. Do not call it stable.
Working credential retention was explicitly authorized by user; keep it private
outside repo/evidence and reuse instead of asking again after every subtask.

Full-RAM diagnostics found~100ppm advances and a slower-sink negative control
demonstrated capture loss. Exact matched RTL is absent. Do not raise the PS
capture clock above its125MHz design constraint as a routine workaround. Lower
RF source profiles require matched LMK/LMX programming, actualRFdc-rate metadata,
NCO/MTS validation and before/after raw timing-loss measurements. Preserve failed
records. Host `reference --fs`/capture metadata specify samples, not clock commands.

The latest v2 physical run had 100 acquired live frames, zero BER and median/max
EVM of 3.79/9.98%. Raw loss persists; do not claim constant EVM or an RTL repair.
The stock 245.76/491.52 profile was switched and restored but is incompatible with
the existing fixed MMCM ratios and mixed tile clocks. Keep the validated 500/500
profile until a separately reviewed configuration is actually measured.
The direct-cable launcher is tools/run_demo.py. Private configuration stays in
ignored local/ or the user's private settings directory. It verifies board and
boot hashes, stages a new reference/helper and leaves bootpy stopped. Headless
validation must check the whole launch, finite stream and shutdown manifest.

The launcher lifecycle now passed a fresh 100-frame headless run after the
one-line output-path join fix: zero BER, all pilot locks, successful retrieval,
RAM clears and disable commands. GUI clicks are not tested. No hardware session
owns the board after validation; keep final states in the run evidence. Further
antenna/MXG tests require the user's later cabling and RF-chain decisions.

Connector correction: logical dac0/RFdc tile0 is printed DAC_B (tile228), logical
dac1/RFdc tile2 is DAC_A (tile230). Earlier direct-test DAC_A text was a labelling
error. Default launcher output is DAC_B; --dac-port A selects the other output.
The user confirmed the current receive connector is ADC_D, matching capture stream0.
Other receive connector mappings still need checking before the array demo.
EVM is normalized error, not an absolute received-power indicator. Show RX level
and capture freshness. Signal loss/staleness must clear all current good values;
keep old traces only as explicitly labelled history.

EVM must be shown in both dB and percent (user
request): EVM(dB)=20log10(EVM(%)/100). Store evm_db and evm_percent in metrics;
represent exact-zero error as null in JSON and -inf dB in the display.
Each milestone updates docs/VALIDATION.md and PLAN.md with Test / How / Results /
Conclusions / Ways to resolve. Report what is not proven. Keep access details in
ignored local/ files; use secure secret cards for credentials. Do not introduce
licensed dependencies, paid services or instrument resets without user scope.
