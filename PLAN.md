# Demo plan — 2026-11-15

User requested a new public repository showing RFSoC 4x2 DAC demodulation,
tracking and beamforming with the two-DAC/hybrid/splitter/four-ADC loopback,
avoiding external MXG interference; `vsa_rfsoc` is a reference. User also
requested agent instructions and authorized one laptop agent for live checks.

Claims hold until explicitly released, irrespective of timestamps.

| Part | Owner | State |
|---|---|---|
| Repository code, docs, tests, publication | Coordinator | Software verified; live validation pending |
| Laptop and board experiments | Laptop agent released its claim | Access attempt complete; SSH/password and VISA blocked; no hardware changes |

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
