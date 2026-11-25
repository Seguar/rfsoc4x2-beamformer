# Live board control

Every board session has a separate command socket next to the four-stream data socket.
It remains responsive while IQ data is being captured, transmitted or paused. This
uses the legacy command names from the MATLAB/ZCU216 interface with the 4x2's own
wrapper and channel indexing. No ZCU216 overlay or burst commands are used.

The data port (4011) carries framed IQ; the control port is the data port plus
one (4012). The application sends no frequency command at start: its RF page
starts from the frequency, Nyquist zones and DACs the board reports.

## Supported commands

| Command | Meaning / units |
|---|---|
| `status` | Current revision, streaming state, ADC/DAC mixer readbacks and the path settings below |
| `fc ADC/NZ/DAC_B/NZ/DAC_A/NZ` | Integer MHz and Nyquist zones 1 or 2; wrapper configure + MTS |
| `phase p0/p1/p2/p3` | ADC mixer phases in degrees, wrapped to −180…180 |
| `dphase p0/p1/p2/p3` | Wrapper DAC phase vector; physical DAC_B is index 0, DAC_A index 2 |
| `dataStream 0` / `dataStream 1` | Pause/resume capture; commands still work while paused |
| `da 0`, `da 1`, `da 2` | Original 4x2 DAC/ADC trigger modes |
| `dacPow p0/p1/p2/p3` | Binary mask; with the session service DAC_B (index 0) and DAC_A (index 2) |
| `dataChan N` | Lane words per frame (8 per row); one of the sizes the stream declared (`window_rows_allowed`) |
| `phasec p0/p1/p2/p3` | ADC mixer phase offsets, hundredths of a degree, written on the running NCOs (no NCO reset, no tile re-sync) |
| `dphasec p0/p1/p2/p3` | DAC mixer phase offsets as `phasec`; indices 0 and 2 used |
| `again g0/g1/g2/g3` | ADC QMC gain, hundredths (0..199 = 0..1.99); index 0..3 = ADC_D, ADC_C, ADC_B, ADC_A |
| `aiqphase p0/p1/p2/p3` | ADC QMC I/Q phase correction, hundredths of a degree (±2649) |
| `adsa a0/a1/a2/a3` | ADC step attenuator, dB (0..27) |
| `dgain g0/x/g2/x` | DAC QMC gain, hundredths; index 0 = DAC_B, 2 = DAC_A |
| `diqphase p0/x/p2/x` | DAC QMC I/Q phase correction, hundredths of a degree |
| `dvop c0/x/c2/x` | DAC output current, µA (2250..40500) |
| `evm e` | Display only: the app's EVM for the board OLED, hundredths of a percent (0..100000, −1 = none). No converter is touched and the settings revision is kept. Listed in the header as `display_controls` |
| `doa a` | Display only: the beam direction for the board OLED, hundredths of a degree (99999 = none); sent with `evm` as `evm e#doa a` |

The path settings (`again` … `dvop`) are kept by the board helper and written
again after `fc`, `phase` and `dphase`, because the board wrapper rewrites QMC
gain 1.99, no I/Q phase and the maximum DAC current whenever it reconfigures the
converters. The stream header lists them in `path_controls`; the host offers only
what is listed. Live check (2026-11-17): ADC_C gain 1.00 −5.98 dB on ADC_C only,
ADC_B 6 dB attenuation −6.00 dB on ADC_B only, DAC_B gain 1.00 and half current
about −6 dB on all streams. The wrapper's own `phase` command re-synchronises the
tiles, which moved tile 226 against tile 224 by 144° in one test; use `phasec`.

A full four-stream window has 32768 complex rows per channel (`dataChan 262144`
lane words); `dataChan` selects one of the reduced sizes the stream declares
(`window_rows_allowed`: 4096, 8192, 16384). Automatic ADC calibration, waveform
upload and the ZCU216 `stream`/`dacbf` commands are not supported and are
explicitly rejected.

The trigger in this bitstream also enables both DAC players. Therefore `dacPow`
OFF zeroes the selected waveform RAM with readback before acknowledgement; ON
restores the session's pinned waveform. The unused DAC RAM stays zero. This does
not change the waveform amplitude or establish an independent RF-off measurement.

## Wire contract

Each control connection exchanges UTF-8 JSON lines, independently of the IQ stream:

```json
{"id":1,"command":"dphase 45/0/0/0#dataStream 1"}
```

An acknowledgement echoes `id`, with `ok:true` and a `result` object containing
`revision`, `streaming`, `data_words`, `da`, `dac_power`, `adc_mixers` and
`dac_mixers`. An error has `ok:false` and `error:{code,message}`. ACK means the
hardware operation and register readback finished, rather than merely being queued.
Commands are serialized with capture under one hardware lock. Parsing and
profile-specific validation cover the whole batch before mutation. If a driver
fails after a partial operation, the helper latches the fault, disables DACs and
stops capture; it never acknowledges a partial batch as successful.

Every window carries the revision held during acquisition. MATLAB discards any
buffer older than its last applied ACK and clears plot averaging when a new
revision arrives. A prefetched old capture cannot be relabelled as new settings. Regenerate any
model calibration tables after frequency/phase or MTS changes; clearing averaging
does not validate an earlier calibration.
Rejected commands leave the queue after one error; an uncertain acknowledgement
closes the control connection and requires a session restart.

Private runs save applied acknowledgements to `commands.jsonl`, per-frame
revisions to `frames.jsonl`, and failures to `errors.jsonl`. Board manifests retain
the command history. The control endpoint shares the session lifetime: owner loss,
expiry or closing the application clears both DAC RAMs and commands outputs off.

## Validation

A bounded live MATLAB/DSP + RFSoC run passed phase readback (45° then 0°), ADC
phase and same-frequency retuning, pause/resume with status during pause, selected
DAC off/on with disappearance/recovery of the wanted signal, queue/ACK handling,
and rejection of unsupported/resizing/other-DAC commands. Eleven direct commands
plus one UI-style batch were acknowledged; latency was 0.15–0.33 s over the tested
remote path. Three obsolete captures were discarded. Both DAC RAMs were zeroed
with readback at shutdown, enables were commanded off and no shutdown errors
occurred. This validates control during acquisition, not a higher acquisition
frame rate, physical DOA, coherent dual-DAC operation or jammer rejection.
