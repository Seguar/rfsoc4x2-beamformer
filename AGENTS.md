# Agent instructions

Read README.md, PLAN.md and docs/HARDWARE.md before work. Read docs/VALIDATION.md
before describing results. This repository is specifically RFSoC4x2 / xczu48dr;
ZCU216 overlays, clocks, DAC indexing and burst protocols do not apply.

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
  reference assumes 125 Mcomplex/s ADC and 1 Gcomplex/s DAC, 8:1 ratio.
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

Each milestone updates docs/VALIDATION.md and PLAN.md with Test / How / Results /
Conclusions / Ways to resolve. Report what is not proven. Keep access details in
ignored local/ files; use secure secret cards for credentials. Do not introduce
licensed dependencies, paid services or instrument resets without user scope.
