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

The original custom DAC-file upload buttons were unwired and remain pending.
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

Only ADC_D is transported: full contiguous 131072-complex captures, losslessly
compressed with a decoded SHA-256 check. Other columns are explicit placeholders;
unmeasured selection and array mode are refused. DOA/pattern therefore remain
unavailable in this launch. The matched FFT64 waveform is truncated to DAC RAM
capacity; VSA receives contiguous windows avoiding its loop boundary, without
padding or joining captures. The reference and setup hashes are pinned.

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
