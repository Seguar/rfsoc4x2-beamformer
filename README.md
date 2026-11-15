# RFSoC 4x2 loopback beamforming demo

Pilot-locked OFDM demodulation, frequency/phase tracking and four-channel
adaptive combining for the RFSoC4x2. Uses the existing `doa_rfsoc/main` matched
boot overlay and `vsa_rfsoc` sample conventions; no FPGA build is required.

**Status: software tests pass; board captures obtained, payload demodulation still
under repair.** Initial hardware EVM is poor. The simulated distinct-path jammer
is rejected; no working physical beamforming or interference rejection is claimed.
See [validation](docs/VALIDATION.md) and [agent instructions](AGENTS.md).

The [real-time demo](docs/LIVE_DEMO.md) adds live fixed-versus-adaptive EVM,
beamforming ON/OFF, broadside calibration and a moving-array simulation:

```sh
python -m rfsoc_demo.live --simulate
python -m rfsoc_demo.live --host BOARD_ADDRESS
```

Target antenna silkscreen is 5.2 GHz; spacing and RF response are unmeasured.
The current 2–4.2 GHz passives need replacement or characterization for that
later antenna test. Initial conducted loopback and OTA validation are separate.

```text
DAC0 ─┐
      ZAPDQ-4 (90° hybrid) ── ZA4PD-4 ── ADC0, ADC1, ADC2, ADC3
DAC1 ─┘                                  │
                         pilot lock → MRC / MVDR → OFDM EVM + BER
```

This cable setup demonstrates calibrated coherent combining and signal tracking.
The shared splitter gives both DACs the same receive steering vector. It cannot
demonstrate an arrival angle or independently steer the two DAC sources. An MXG
signal entering before the splitter shares that limitation. External interference
needs a distinct spatial path for spatial rejection; frequency separation can
instead support filtering. Ethernet control does not establish an RF connection.

## Run the software demo

Python 3.10+ on the host (Linux or Windows). No MATLAB licence is required.

```sh
python -m pip install -e .
python -m unittest discover -s tests -v
rfsoc-demo simulate --out out/simulation
rfsoc-demo reference --out out/reference.npz
```

Open `out/simulation/demo.png` and `metrics.json`. The plot compares single ADC,
matched combining (MRC) and residual-covariance MVDR; the other panels show pilot
frequency tracking and held-out payload constellations. The fixture varies CFO
and capture delay across frames with a fixed, distinct-path CW interferer.
The tests also check the collinear-path impossibility and receive conjugation.

Use `python -m rfsoc_demo.cli` instead of `rfsoc-demo` without installing.
`simulate --shared-path` intentionally challenges acquisition with a strong
collinear jammer; it may produce only unlocked frames and return failure.
That is a useful negative control, not a promised working cancellation case.

## Run on the board

Follow [the hardware procedure](docs/HARDWARE.md). A bounded board capture stages
the reference and helper in a new directory, takes exclusive control from the
legacy service, verifies runtime rates, captures four ADCs, then disables both
DACs with disable-command and direction-register records. These do not prove
physical RF-off: AXI GPIO output DATA reads return zero. It changes volatile overlay/clock/RF settings and leaves
the boot files intact. Do not run it beside the existing RF process.

Analyze the returned capture on the laptop:

```sh
rfsoc-demo analyze local/capture.npz --out out/hardware
```

Alternatively, `capture-legacy --host BOARD_ADDRESS` reads the existing continuous
TCP stream. It does not upload this reference or retune the board, so a pilot lock
requires the matching waveform already running. Its stop command has no ACK;
RF-off must be checked separately through board access.

## Signal and metrics

- ADC 125 Mcomplex/s; mode3 DAC input 500 Mcomplex/s: 10 GS/s / interpolation10 /
  additional IMR2. Runtime checks include that extra stage. The old 1 Gcomplex/s
  reference was incorrect; regenerate it. Fourier interpolation uses a 4:1 ratio.
- A 4096-sample ADC period becomes 16384 complex DAC samples, repeated twice to
  fill 32768 complex RAM samples / 65536 int16 words.
  OFDM uses 256-point FFT, 64-sample cyclic prefix, 48 occupied bins, four training
  symbols and eight QPSK payload symbols, with four phase pilots per payload symbol.
- Pilot-only delay/CFO acquisition searches ±150 kHz and both conjugations.
  Each triggered capture reacquires; there is no assumed continuous sample time.
- Training fits the steering vector and residual covariance. Regularized MVDR
  weights stay fixed through payload. Training also supplies per-bin equalization;
  reserved payload pilots track common phase. Payload EVM and BER exclude pilots.
- EVM is reference RMS error, with training-derived gain. It is not WLAN-standard
  compliance, decision-directed EVM, dBm, or a direct jammer-suppression measurement.
  Initial receiver model assumes a flat spatial response over the occupied band.

## References and provenance

- [vsa_rfsoc](https://github.com/Seguar/vsa_rfsoc), reference commit
  `94145663665da25ba1d7dd4b74ce8878d8b49960`: `Functions/tcpDataRec.m`
  (eight int16 lanes, I − jQ), `Functions/sigPrepare.m` (TX I + jQ), MVDR work.
- [doa_rfsoc/main](https://github.com/Seguar/doa_rfsoc/tree/main), reference commit
  `6759b3916d7bddb18e998c2734a1db0d9d88efc4`: matched boot wrapper/hardware
  and `runtime/rfsoc4x2/manifest.json`. These assets are not copied here.
- [ZAPDQ-4 datasheet](https://www.minicircuits.com/pdfs/ZAPDQ-4.pdf): 2–4.2 GHz,
  two-way 90° hybrid; calibrate relative DAC phase rather than assuming zero.
- [ZA4PD-4+ datasheet](https://www.minicircuits.com/pdfs/ZA4PD-4%2B.pdf):
  2–4.2 GHz, four-way nominal 0° splitter.

Instrument endpoints, credentials and raw measurements stay in ignored `local/`.
The AD936x bridge MXG interface is a reference for explicit VISA/SCPI control;
this demo does not enable or reconfigure the MXG automatically.
