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

The live native-VSA backend is not yet integrated. Do not feed FFT256 v2 samples to
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
