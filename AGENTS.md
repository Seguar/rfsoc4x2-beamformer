# Agent instructions

Read README.md, matlab/README.md and the docs/ page for the part you change. This
repository is specifically the RFSoC 4x2 (xczu48dr); ZCU216 overlays, clocks, DAC
indexing and burst protocols do not apply.

## Publishing

The repository is public. Never commit addresses (other than the PYNQ defaults
192.168.3.1 and 192.168.2.99), credentials, raw captures, snapshots, calibration
files or measurement logs; keep them in ignored `local/` or outside the repository.
Commit with explicit paths. `core.autocrlf=input`: do not commit CRLF-only diffs.

A release: build with MATLAB R2025b (`win64`) and R2026a (`win64-r2026a`) from a
neutral folder outside the user profile (folder names end up in the archive), zip
each with its README.txt, publish both with SHA256SUMS, then put the R2026a exe on
the board's USB drive (`tools/usb_drive/update_app.py`) and check it live on the
laptop over USB.

## Board

- Verify the device tree `chosen/pynq_board` is `RFSoC4x2` before any board work.
- Never replace `/boot`, reflash, change routes or start things at boot without an
  explicit task. The session service (`tools/install_board_service.py`) is the one
  installed component; installing it needs sudo.
- One owner of the converters at a time: the service refuses a session while a
  notebook kernel or another capture program runs. Diagnostics that need the
  hardware go through a service session (`tools/session_client.py`).
- DAC peak code is at most 24000 (`DAC_PEAK_MAX`); the helper refuses a start-up
  capture above −6 dBFS. The capture trigger also enables both DAC players, so DAC
  off zeroes the waveform RAM. The DAC-off record is a command and readback record,
  not an RF measurement.
- Start frequencies are only the measured profiles 3000 and 5200 MHz
  (docs/RF_PROFILES.md). At 5.2 GHz the 10 GS/s DAC image folds onto the band and
  its sign changes per session: keep the DAC zone the board measured.
- Connector names: streams 0..3 = ADC_D, ADC_C, ADC_B, ADC_A; DAC index 0 = DAC_B,
  2 = DAC_A. Use `phasec`/`dphasec` for live phases (the wrapper's `phase`
  re-synchronises the tiles).
- The MXG signal generator is controlled by SCPI; raise its output only when its
  RF connection and level are known.

## Processing invariants

- Wire samples are int16 I/Q, I − jQ per stream; output = sum(X .* conj(w)).
- Window checks (`windowIntegrity`, reduced-window check, window SHA, repeated
  capture) refuse transport faults. Do not weaken them to pass frames. Missing
  stream lock is reported, never a reason to drop a frame.
- OFDM: only the pinned setup file (FFT64, CP16 at 100 MHz; 80-point FFT at the
  125 MS/s capture rate). Frequency, phase, timing and channel come from the
  preamble and pilots only; never fit anything to the payload. Primary EVM
  includes every complete burst, flagged ones too; the qualified-only EVM is
  secondary.
- Angles are angles of the uncalibrated array model; do not present them as
  measured directions. Do not call a lower EVM jammer rejection without a
  measurement that separates the sources.

## Workflow

- Headless commands only unless the user asks for GUI work. MATLAB runs on the dsp
  server (`matlab -batch`); the window fixture needs its interactive desktop.
- No subagents unless the user asks.
- Tests: `python3 -m unittest discover -s tests` (set `LEGACY_SOURCE` to the
  `vsa_rfsoc` waveform) and `matlab/original/tests/runSuite.m` with the fake
  board stream and fake session service (matlab/README.md).
- Distinguish simulation, calculation, measurement and assumption when reporting.
