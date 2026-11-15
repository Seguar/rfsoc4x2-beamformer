# Backend contract for VSA_rfsoc_refactor_exported (a1 → board/VSA owner)

Status: proposed by a1 on 2026-11-15. The board/VSA owner (a2) had not delivered
`original-app-interface.md` when this was written, so the contract is a1's proposal. The
parent reconciles the two. a1 did not run any board, VSA or instrument code.

## Construction

```matlab
addpath('<candidate>/app')
cfg = origapp.defaultConfig();          % safe defaults, no endpoints
cfg.originalRepoPath = "<vsa_rfsoc checkout>";   % read-only: Functions/, koef.mat
cfg.backend   = myBackend;              % struct of function handles OR handle object
cfg.directOnly = true;                  % conducted loopback: no physical DOA/pattern
cfg.visible   = true;                   % false (default) = hidden figure
app = VSA_rfsoc_refactor_exported(cfg); % or name-value pairs: ('backend', b, 'visible', true)
app.startAcquisition();                 % or press Reset; cfg.autoStart=true starts at once
...
delete(app)                             % or close the window: stops timer, closes backend
```

Unknown cfg field names are an error (`origapp:Config`). The constructor never opens the
backend, never sends a board command and never touches VSA or an instrument.

## Operations the backend provides

| Operation | Required | Called when | Contract |
|---|---|---|---|
| `open()` | optional | `startAcquisition` (Reset button) | Connect/attach. May throw; then nothing runs. |
| `frame = next(timeoutSeconds)` | **yes** | every timer tick (default 0.1 s, `BusyMode=drop`) | Return within `timeoutSeconds` (default 1 s). `[]` = no frame yet (not an error). Otherwise a struct: `samples` N-by-4 complex double, ADC counts, `I - 1j*Q` per channel (the original `tcpDataRec` convention), N = `cfg.dataChan`; `timestamp` POSIX seconds UTC of acquisition; `sequence` strictly increasing nonnegative integer. Both timestamp and sequence are mandatory. Throw on transport failure. |
| `send(line)` | optional | `partReset` after a control change, only if `cfg.allowBoardCommands=true` | One line of `#`-joined original commands (`fc a/b/c/d/e/f`, `dataChan n`, `da n`, `dataStream n`, `cal 8`, `dphase …`, `dacPow …`, `source …`, `sync 1`, custom). No terminator added. Without permission the commands stay in `app.Controller.Pending`. |
| `vsaSend(buffer)` | optional | each accepted frame when the VSA checkbox is on | Column vector of complex double, already scaled `/2^16` like the original. Array mode: beamformed sum (cutter applied). directOnly: raw channel `ch` (1 when "All"). |
| `vsaReset(request)` | optional | full reset (`reset_req`) with VSA on | `request.fs`, `request.dataChan`, `request.setupFile` (.setx). Replaces original `vsaDdc` + `vsaSetup`. |
| `close()` | **yes** | `stopAcquisition`, too many errors, `delete(app)`, window close | Idempotent; must not throw. |

A struct of function handles (`struct('next',@…,'close',@…)`) and a handle object with
these methods both work (`origapp.Controller.hasOp`).

## What the app does with each frame

1. Rejects (and clears the displayed DOA and pattern) when: `next` throws; samples are not
   finite N-by-4 with N = dataChan; `sequence` is not larger than the last one; the frame
   is older than `cfg.staleSeconds` (2 s). If no frame arrives for `staleSeconds` the
   display is cleared too ("no fresh frame").
2. After `cfg.maxConsecutiveErrors` (5) rejected frames in a row: the timer stops, the
   backend is closed, the status says why.
3. `directOnly=true`: no DOA, no beamforming, no pattern; titles say "unavailable"; VSA
   feed only.
4. `directOnly=false`: `origapp.processLegacyFrame` (original rfsocBf pipeline), plots,
   `vsaSend` of the beamformed sum.

## Provided backends

- `origapp.FiniteIqBackend(frames, 'FailAt',k, 'StaleAt',k, 'RepeatAt',k)`: fixture, no I/O.
- The candidate `LegacyTcpBackend` was excluded from integration: flushing arbitrary
  bytes from a continuous unframed TCP stream can lose I/Q lane alignment. The
  legacy implementation also uses receive time instead of capture time. A reviewed
  backend with acquisition metadata is required. The original candidate described a
  bounded replacement for
  `rfsocConnect` + `tcpDataRec`. **Not run by a1.** It does not send the stream-start
  command on open. Note from the board skill: the 4x2 boot service streams continuously and
  does not read commands while it streams.

## Not covered here (owned by a2 / parent)

The FFT64 legacy waveform, native VSA session/SETX, EVM read-back, live training for
legacy DOA, endpoints and calibration files.


Parent review: the integrated production default is `bfEngine="reviewed"`.
Add the demo's `matlab/` folder before constructing the app. An empty `reviewed`
struct uses `rfsoc.defaultConfig()`; explicit configuration overrides that baseline.
The `original` engine remains an explicit regression/comparison option with known
conjugation defects. It is not the default. Missing/nonfinite/future timestamps and
missing/non-scalar sequences are rejected rather than assigning receive time.
