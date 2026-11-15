# Bounded live loopback procedure

Current direct test: DAC_A → BW-S20W2+ (20dB) → ADC_A, DAC_B unused. Generate
the corrected mode3/IMR2 reference and analyze with `--adc0-only`; this is a
single-channel demodulation test, not array evidence.

One operator owns the board and instruments. Keep a local run log with UTC time,
RF cable diagram, attenuators, RF centre, generator state, file hashes, actual
runtime rates and service/process state before and after. Never publish endpoints
or credentials. Raw captures and run logs belong in ignored `local/`.

1. Verify SSH board identity using `/proc/device-tree/chosen/pynq_board` and
   architecture. Confirm RFSoC4x2 / aarch64. Ethernet and USB are alternative
   network paths; neither identifies the board alone.
2. Read current `bootpy.service` status, its command, listeners and overlay hashes.
   Compare bit/HWH with the matched `doa_rfsoc/main` boot manifest. Confirm no
   notebook or other session controls RF hardware. Preserve startup state.
3. Inspect the MXG with explicit local VISA resource and `*IDN?`, `:OUTP?`,
   `:FREQ?`, `:POW?`. Keep RF off for initial DAC loopback. Do not enable it until
   its RF connection and safe level are known. The AD936x bridge project used
   N5182B VISA over Ethernet; do not inherit its frequency, power or waveform.
4. Confirm cabling, safe ADC input level and board front-end band. Both passive
   devices specify 2–4.2 GHz; the old wrapper default 5.7 GHz is outside that
   specified band. Candidate 3 GHz is ADC Nyquist zone 2 at 5 GS/s and DAC zone 1
   at 10 GS/s. Runtime registers and the observed spectrum must verify this.
5. Generate `out/reference.npz` on the host. Stage it and `tools/board_capture.py`
   under a NEW board experiment directory; compare SHA-256 after transfer.
6. Stop the legacy service under exclusive control. Run the helper as the
   appropriate privileged account, with NumPy and the existing `/boot` wrapper
   available. Do not edit `/boot` or install a new startup service.

```sh
sudo -n systemctl stop bootpy.service
sudo -n python3 board_capture.py --exclusive-control \
  --reference reference.npz --out dac0.npz --dac 0 --frames 10 \
  --sampling-freq-unit GHz
```

The unit above is an example only: inspect the installed RFdc implementation
before choosing GHz, MHz or Hz. The helper requires this explicit selection
and still rejects sample rates inconsistent with the generated waveform.

7. The helper reinitializes FPGA/clocks/MTS using the existing wrapper. It checks
   runtime ADC/DAC rates against reference generation, loads low-amplitude words,
   requires clock lock before and after MTS, verifies the additional IMR2 stage
   (500Mcomplex/s DAC input), accepts at most 1200 peak DAC words,
   takes bounded captures and independently attempts both DAC disables in
   `finally`. It saves shutdown errors, direction registers and command shadows
   even after a failure. It never calls PYNQ slice read(), which can change pin
   direction. AXI GPIO output DATA reads return zero and cannot prove RF-off;
   the manifest distinguishes `dac_off_commanded` from physical verification.
   All-output cores may have no implemented TRI register; C_ALL_OUTPUTS controls
   that check. The matched design ORs capture trigger into both DAC enables:
   unused DAC RAM is zeroed, and the helper waits3ms after trigger before RAM copy.
   The old helper loaded both buffers and read immediately; its poor-EVM captures
   are not validation of the corrected method.
   If construction
   fails before returning an overlay, GPIO state is unknown; inspect it manually.
   If rate fields differ from the installed driver API, stop and inspect rather
   than bypassing rate validation. Do not interpret config as a frequency measurement.
8. Transfer NPZ plus manifest back; verify hashes. Analyze ADC headroom and clipping
   before increasing the DAC amplitude. Confirm the pilot is present, sideband and
   conjugation are correct, all channels lock, and new captures differ. Record
   hardware EVM/BER separately from simulation. Each frame has 16384 complex
   samples per channel; frames are independently triggered and may have gaps.
9. Capture DAC0 and DAC1 separately. Estimate their complex path gains from pilots;
   compensate hybrid/cable phase, then compare both-DAC output versus DAC0 only.
   Use `--phase1 DEGREES --dac both` after individual path calibration. Do not
   assume the datasheet's +90° label fixes the assembled path sign.
10. With known MXG RF injection, measure DAC-only, MXG-only and mixed captures.
    If paths are collinear, report that spatial rejection is unavailable. For a
    distinct path compare single ADC, calibrated MRC and MVDR with independent
    payload EVM/BER and separately measured interference power. Source-on/off
    controls and topology must accompany any rejection number.
11. Record both disable commands and obtain independent RF-off evidence when
    available; output-register zeros are not that evidence. Record service state. Restarting bootpy can reload
    its previous waveform/settings; restore it only if that RF state is intended.
    Keep MXG off. Record any unverified RF state prominently.

Legacy acquisition is optional. The old service only reads commands before its
stream loop. A disconnect and a fresh control connection can request stop but
cannot prove it. No bounded-stream or DAC-beamforming commands from ZCU216 apply.

Register semantics: [AMD PG144 GPIO DATA](https://docs.amd.com/api/khub/documents/0c0ItRCmnYkoHpcYUCPkEA/content).
