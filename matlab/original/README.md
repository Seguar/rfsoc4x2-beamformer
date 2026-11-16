# Original RFSoC4x2 App Designer interface

This is a refactor of `vsa_rfsoc/VSA_rfsoc_exported.m`, retaining its original
119 components and controls. VSA owns constellation and EVM; this MATLAB interface
owns DOA, beam patterns and beamformer/control selection. It does not use the
replacement dashboard.

The runnable pair is `app/VSA_rfsoc_refactor.mlapp` and its matching
`app/VSA_rfsoc_refactor_exported.m`. Both pass headless model/code checks;
an App Designer editor round trip is still untested. The source repository's
original binary and export are untouched.
See [MLAPP_STATUS.md](MLAPP_STATUS.md).

```matlab
addpath('<demo>/matlab', '<demo>/matlab/original/app');
cfg = origapp.defaultConfig();
cfg.originalRepoPath = "<vsa_rfsoc checkout>"; % read-only helper dependency
cfg.backend = myBackend;                      % see BACKEND_CONTRACT.md
cfg.visible = true;
app = VSA_rfsoc_refactor_exported(cfg);
app.startAcquisition();
```

Startup is idle and performs no board, VSA or instrument I/O. Closing owns timer
and backend cleanup. `bfEngine="reviewed"` selects the reviewed twelve-mode
beamformer core by default. The explicit `original` option preserves legacy
behavior for comparisons, including known conjugation defects; it is not a
validated RF operating mode. Empty `cfg.reviewed` uses `rfsoc.defaultConfig()`.

`directOnly=true` is the default for the current single-cable diagnostic. It hides
physical DOA/patterns and passes only the selected channel to the backend's native
VSA hook. Array angles use the original configured array model; measured geometry,
channel ordering and calibration remain required for physical claims.

The native-VSA backend is `origapp.LegacyVsaBackend`. Do not feed FFT256 v2 samples to
the original FFT64 SETX. Frames need an acquisition timestamp and increasing
sequence; missing metadata is rejected. Arbitrary stream flushing was excluded
because it can lose I/Q alignment. All endpoints, setup selections and credentials
belong in private session configuration.

The original custom DAC-file upload buttons were unwired. The newer-app tab now
prepares files; actual upload remains unavailable in the current backend.
CONTROL_MAP.md documents each original control, supported behavior and limitations.

Validation (synthetic IQ only):

```matlab
addpath('<demo>/matlab/original/tests');
runAll('<vsa_rfsoc checkout>', '<demo>/matlab', '<new results folder>');
```

The tests cover hidden construction, explicit mode results, command gating,
transport failures, freshness, phase-calibration output and owned cleanup. They do
not validate live VSA/EVM or over-the-air direction finding.

## Native VSA launch

Copy `examples/original-vsa.example.json` to a private directory and fill in the
board endpoint, pinned SSH host key, password-file path, VSA DLL, MATLAB executable
and read-only `vsa_rfsoc` checkout. From the demo checkout on Windows:

```powershell
py -3.11 tools/run_original_vsa.py --config C:/private/original-vsa.json --i-own-board --mode validate
```

This starts the editable original `.mlapp` and a new owned native VSA window.
Validation schedules wanted signal, blank input, a pause and recovery. After
validation, `--mode durable --max-seconds 1800 --max-frames 10000` leaves the app
running within those bounds. Closing the app, creating the output folder's `STOP`
file, expiry or losing the launcher stops the helper. Both DAC RAM clears and off
commands must appear in the retrieved shutdown manifest. RF-off is not independently
observed. Existing VSA instances are never attached or closed.

The default `--receive window4` transports all four measured ADC streams as a
32768-row contiguous window from one capture. The helper selects the window on the
board; the host checks its digest, per-stream lock and sample-phase jumps. The
window start and full-capture digest remain in frame metadata. The plots show a
common-feed diagnostic through an explicit uncalibrated array model, rather than
physical arrival angle or measured radiation pattern. Native VSA measures the
actual weighted app output. Optional `--save-windows` keeps private raw windows.
The board can occasionally choose a bad window; host rejection remains required.

`--receive adc-d` selects the earlier 131072-sample ADC_D-only mode. Its other
columns are explicit placeholders, so array mode and unmeasured selection are
refused. Neither mode tiles or joins independent captures. The reference and setup
hashes are pinned. The responsive window fits the monitor, scrolls the controls,
and provides zoom/pan plus Autoscale/Tight; manual zoom persists across frames.

Acceptance requires independent wanted-reference lock >= 0.3, native VSA sync
>= 0.9 and acquisition age <= 2 s. Raw vendor metrics and outliers remain logged.
Unclassified vendor trace bit 32 is explicitly reported, with the SETX-profile
exception; other trace errors remain rejected. An acquisition in progress or stale
input clears current guarded validity. EVM magnitude is never an admission test.

The private predecessor passed 16 wanted / 9 blank hardware frames, with median
wanted EVM 4.61%, all blanks rejected and receipt age 0.58–1.32 s. A separate
30-frame bounded continuous run passed. Occasional 21–28% EVM outliers remain;
raw sample loss, OTA beamforming and jammer rejection remain unresolved. These
measurements precede the public launcher's final hardware validation, including
its stricter acquisition-age check at measurement completion.

## VSA_rfsoc_new port (New tab)

A fifth tab, **New**, carries the VSA_rfsoc_new (vsa_rfsoc HEAD 2d8610a) controls
that have an RFSoC4x2 meaning; the original four tabs and their 119 components
are unchanged. See `FEATURE_PARITY.md` (delivered with the candidate) for every
VSA_rfsoc_new control, its source and its state here.

- Receive IQ compensation (adaptive LMS, static), L size, MU step; coupling
  compensation; phase/power compensation from the angle calibration. Array
  processing only: the direct native-VSA feed stays the raw measured channel.
- Angle calibration (Downconverter tab button) now runs the VSA_rfsoc_new chain:
  `calibrationFramesPerAngle` frames per angle, steering + power + coupling tables
  saved under `cfg.outputDir` and installed for the session when the grid matches.
  These are model tables from operator-labelled captures, not physical DOA
  calibration; a common splitter/cable feed carries no angle information.
- EVM checkbox shows the guarded native-VSA EVM (percent and dB) only; Mirror plot
  is display-only; Print phase mismatch needs a current array-mode frame.
- DAC BF mode (MATLAB-side TX steering) needs `capabilities().txArrayElements`
  >= 4 and `dphase`; RFSoC4x2 has two DAC outputs, so it is refused by default.
- RFSoC BF mode (`dacbf`) and Burst len (`stream N`) are ZCU216 features and are
  always refused on RFSoC4x2 with a visible reason; nothing is queued.
- Channel control queues `dgain/again/phase/diqphase/aiqphase` only when the
  backend declares them; `dphase` keeps the original 4x2 behaviour.
- Prepare DAC file: original sigPrepare with 4x2 checks (RAM tiling, peak 1200,
  I + jQ int16). Upload only through a declared `uploadDacWaveform` backend op
  and `cfg.allowBoardCommands`; no current backend provides it.

Simulation fixture: `tests/runPortAll.m` (runs `runAll` and `runNewPortFixture`).

Parent review: coupling compensation is disabled with an explicit error, including
when a matrix is supplied. The ported legacy calibration demonstrably gives wrong
DOA on an ideal synthetic array; its stored coupling tables are diagnostic only.
Phase/power and IQ controls remain separate. This restriction needs an independently
validated coupling algorithm before removal.

The four-stream candidate passed a bounded 27-frame hardware run: 21/24 signal
frames passed native VSA guards, combined EVM median2.45%, with one28.1% outlier
retained. Two stale frames and one continuous window were rejected by the VSA path; the
latter was a burst-label artefact, corrected by the newer host continuity model. This is
common-feed conducted evidence. The board has also shown an intermittent stream3
dropout. A long-running four-stream session and physical array work remain pending.

The reviewed host continuity model checks the entire selected window, including
edge blocks. Boundary and expired frames clear plots/Avg with VSA on or off;
selector fallbacks are refused. VSA's separate old block analysis can still refuse
some continuous windows. Two later bounded gates passed24/24 and22/22 host wave
windows; VSA valid22/24 and19/22 with EVM medians2.255% and2.382%. These are
combined-output metrics with no same-frame single-stream gain comparison.

## Integrated Custom OFDM analyzer

`cfg.analyzer` selects the per-frame OFDM measurement:

- `integrated`: the launcher default. It runs the owned MATLAB analyzer and its owned viewer window,
  "Integrated Custom OFDM", and starts no 89600 VSA.
- `vsa`: the earlier native-VSA path, unchanged.
- `both`: the integrated analyzer, plus native VSA as a separately labelled comparison.

The VSA checkbox switches the analyzer too. Launcher option: `--analyzer integrated|vsa|both`.

The analyzer (`+origapp/ofdmProfile`, `ofdmAnalyze`, `OfdmAnalyzer`, `OfdmViewer`) reads every OFDM parameter from
the pinned SETX: FFT 64, CP 16, 100 MS/s, guard 6/5, resource map, preamble and pilot values, modulation per row,
and SymTimeAdj. It checks the pilots and the 30-symbol burst against the transmitted loop. It then demodulates the
same buffer the app hands to VSA:

- 80-point FFT per symbol at 125 MS/s, with no resampling.
- Channel estimate from the training rows only; pilot phase, timing and amplitude tracking.
- No data-aided step.

It shows:

- constellation (payload 16QAM, header BPSK and pilots, kept separate);
- spectrum;
- EVM in % and dB, per symbol and per subcarrier;
- CFO, common phase, pilot timing and an estimated sampling error;
- sync peak, reference lock and RX level;
- the profile parameters.

Guards:

- its own preamble sync threshold (0.8; not the vendor 0.9 quantity);
- reference lock ≥ 0.3;
- the 2 s age bound;
- training consistency and pilot-timing checks flag complete bursts affected by sample slips;
- incomplete bursts are counted but never padded or included in EVM.

Invalid frames clear the current values. Only a labelled history line remains.

Primary payload EVM includes **every complete detected and analyzed burst**, including bursts
flagged for training inconsistency or timing slips. The viewer shows a yellow DEGRADED
status and qualified/complete/detected counts when those bursts occur. Qualified-only
EVM is a separate, explicitly labelled diagnostic. If no burst qualifies, the frame is
unavailable; complete-burst diagnostics are still logged. Detection and partial-burst
coverage are reported, so this is not a measure of undetected or incomplete bursts.
Channel estimation uses training; tracking uses known pilots. Evaluation payload
symbols are never used to fit the equalizer, gain or phase.

Its EVM is not equivalent to vendor EVM. The pinned SETX enables data-aided equalisation
and tracking, and vendor headline EVM includes preamble/pilot cells over six symbols.
The integrated metric covers payload cells over complete 30-symbol frames. On twelve
recorded signal buffers from a separate live gate, primary inclusive EVM had a median
of 6.00%; qualified-only EVM was 4.46%. An independent NumPy implementation agreed
with MATLAB to numerical precision on all fifteen signal/blank buffers. Earlier
reported integrated medians around 4% used qualified bursts only.
Data-aided EQ and BER are not implemented.

Plots reuse graphics objects and appear before any optional vendor call; a watchdog
clears values older than two seconds. A single outstanding capture request can overlap
integrated analysis. This does not imply a particular display frame rate. The
launcher sends an end marker at bounded expiry and shuts down both DACs.

Selecting `MVDRman` or `MVDRman_corr` without matching calibration tables is now refused in the DOA list callback.
The callback reverts the value and states the reason, before `app.doa` changes. Before this fix, such a selection
stopped acquisition after 5 frames.

Controller failures append their identifier, message, stack and last received sequence
to private `outputDir/errors.jsonl`. This includes blank/boundary/expiry rejections;
sequence identifies the last received frame if a transport failure produced none.
The viewer uses actual resize events for its narrow scrollable layout.
