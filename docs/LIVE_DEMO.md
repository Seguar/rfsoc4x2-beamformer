# Real-time moving-antenna demonstration

## Connector naming correction

The loaded overlay's `dac0` / `/dac_0/ram_play_0` feeds RFdc tile index0
(physical tile228), which is the printed **DAC_B** connector. Its `dac1` player
feeds tile index2 (physical230), printed **DAC_A**. Earlier DAC_A labels in the
direct-loopback reports were incorrect: the default selected transmitter was
DAC_B. The user has confirmed the cable is on DAC_B. See the
[board manual, page6](https://www.realdigital.org/downloads/d6a7543b5033e5dadde272a48bcb5090.pdf).

The launcher now accepts `--dac-port B` (default) or `--dac-port A`, matching the
printed transmit labels. It adds the selected connector to stream metadata and
the live title. Receive channels are labelled by captured stream number until
their printed connector mapping is independently checked.

Fresh capture number, age and RX0 RMS level in dBFS accompany EVM. This digital
level is relative to32768codes, not calibrated RF dBm. EVM normalizes channel gain,
so a weaker but decodable coupled signal can still have good EVM. On pilot loss
or stale data, current EVM/constellation/CFO/phase are cleared; past EVM is explicitly
labelled history. No stale good value should remain labelled as current.

The target is a four-patch linear receive array on the ADCs, both DACs combined
into one moving wanted-transmitter patch, and a separate MXG-driven jammer patch.
The user identifies the patch silkscreen as 5.2 GHz; the antenna response and
centre spacing remain to be measured. Jammer waveform (CW or modulated) is open.

The present ZAPDQ-4 hybrid and ZA4PD-4 splitter are specified for 2–4.2 GHz.
The initial conducted loopback uses a 3 GHz candidate; that does not validate the
later 5.2 GHz antenna chain. Use a suitable 5.2 GHz combiner, or characterize the
current hardware out of band before interpreting an antenna demonstration.
Do not assume the RF converter Nyquist settings for 3 GHz apply at 5.2 GHz.
The existing helper intentionally limits the current passive-chain experiment
to 2–4.2 GHz. Extending RF range needs a reviewed hardware configuration change.

## Host dashboard

Direct cable launcher (PuTTY and installed host dependencies required):

```sh
python tools/run_demo.py --config local/board.json
```

Copy `examples/board.example.json` into ignored `local/board.json` and fill the
board address, pinned SSH host key and private password-file path. The launcher
verifies RFSoC4x2 identity and exact matched boot hashes, refuses active notebook
kernels, stops bootpy, stages new helper/reference files and opens the display.
It uses DAC_A only at3GHz/peak1200; requires the confirmed20dB direct connection.
Password values never enter the repository or command arguments. Run logs, last raw
capture, staging hashes and shutdown manifest stay in ignored `out/live-.../`.
The hardware helper clears both DAC RAMs and attempts both disables on normal
exit, client disconnect, SIGTERM or SIGHUP. Physical RF-off still needs independent
observation. The launcher leaves bootpy stopped and never modifies /boot.

A finite check without opening a desktop window:

```sh
python tools/run_demo.py --config local/board.json --headless --frames 100
```

The patched launcher completed this full headless lifecycle on the laptop:
100 acquired frames, zero BER, median/max EVM 3.89/9.73%, successful raw/manifest
retrieval and DAC shutdown commands. The graphical display has been rendered
headlessly; interactive clicking and actual antenna behavior are not validated.

```sh
python -m rfsoc_demo.live --simulate
```

This opens a Matplotlib dashboard with moving-angle simulation, live EVM traces,
selected output constellation, channel phases and CFO. Buttons calibrate a fixed
broadside beam, switch the displayed receiver between fixed and adaptive, and
toggle a simulated independent modulated jammer. It does not control the MXG.
The simulator assumes a four-element half-wave ULA, which has broadside-sum
nulls at ±30°. Those angles are a model assumption, not a measured antenna fact.

For actual ADC samples from the new versioned stream:

```sh
python -m rfsoc_demo.live --host BOARD_ADDRESS --port 4010
```

For the current direct DAC_A/20dB/ADC_A diagnostic add `--adc0-only`; all array
channels must be connected before claiming beamforming improvement. Regenerate
reference NPZ files after the mode3 IMR fix (500Mcomplex/s DAC input) and distributed
pilot update (waveform_version2). Stream metadata selects the matching receiver;
untagged historical streams use waveform1, never a silent new pilot layout.

The default log is `out/live.jsonl`. EVM is shown in dB and percent.
The time plot uses dB on the left and percent on the
right; the current constellation title shows both. JSON metrics include `evm_db`
and `evm_percent`, with EVM(dB)=20log10(EVM(%)/100); more-negative dB means less
error. Exact zero error is displayed as -inf dB and serialized as null in JSON.
Live RF samples are labelled LIVE ADC, with no inferred angle.
The receive worker drains the socket and keeps at most two
complete frames, dropping old display frames. The dashboard processes the newest
frame every nominal 100 ms. Actual cadence depends on acquisition, network, DSP
and rendering; host age is measured after receipt and excludes unknown network
and board delay. Stalled streams show STALE; failed pilot acquisition shows
UNLOCKED and clears the constellation. Logs preserve individual capture metrics.

## Board stream

After the exclusive-ownership and RF-chain checks in HARDWARE.md, stage the
reviewed helper and reference. Stop the prior RF process before constructing an
overlay. A session runs until client disconnect, Ctrl+C, failure or finite limit:

```sh
sudo -n python3 board_capture.py --exclusive-control \
  --reference reference.npz --out last-live.npz --dac 0 --rf-mhz 3000 \
  --sampling-freq-unit GHz --stream-bind BOARD_INTERFACE_ADDRESS \
  --stream-port 4010 --frames 0
```

This is a separate versioned TCP session, not the old boot server's port 4000.
Use only a trusted/direct board link: there is no application authentication or
TLS. DACs stay disabled while waiting for a client (120-second accept deadline).
The socket has a five-second send timeout; disconnect/failure exits through
independent DAC-disable attempts and persists a manifest. Continuous streaming
keeps the last capture, not an unbounded array of captures. The manifest records
disable commands; GPIO DATA zeros do not establish physical RF-off.

Session bytes: `R4X2IQ1\n`, uint32 little-endian JSON byte length, JSON metadata.
Each frame starts with `<4sQQI`: `IQF1`, uint64 sequence, uint64 board monotonic
nanoseconds after capture, uint32 payload bytes (262144), then eight-lane int16
little-endian samples. Receive complex convention remains I−jQ. Captures are
individually triggered and are not a phase-continuous RF recording.

## Demonstration sequence

1. Start wanted transmission with jammer RF off/disconnected. Keep the moving
   TX at broadside, check all four ADCs, signal lock and safe headroom. Click
   **Calibrate broadside**. Fixed baseline weights now remain frozen.
2. With **Beamforming OFF**, move the TX. The fixed broadside trace should degrade
   near array nulls. EVM is an error, so poorer reception usually means a higher
   percentage and less-negative EVM in dB. A single-ADC trace gives context.
3. Enable **Beamforming ON** and repeat the motion. Pilot-trained steering and
   residual-covariance MVDR update once per capture; reserved OFDM pilots track
   phase within payload. Compare fixed and adaptive traces from the same captures,
   the active constellation/BER, and the EVM ratio in dB.
4. Place the jammer at a distinct arrival direction and a known safe input level.
   Run wanted-only, jammer-only and mixed cases. CW and same-carrier modulated
   interference are separate tests. A same-angle/coherent jammer, ADC clipping,
   insufficient SNR or rapid channel variation can defeat spatial separation.
5. Measure update cadence, lock losses and payload EVM distribution during known
   motion. Set an EVM target from measured stationary performance; do not claim
   constant EVM or a maximum motion speed from the simulator.

## Validation boundaries

Training supplies synchronization, channel response and beam weights. Per-payload
phase pilots are excluded from reported payload EVM/BER. A shared synchronizer
uses the four channels to find the wanted pilot even when the fixed output has a
deep fade; the fixed receiver still uses frozen spatial weights. This compares
beam quality under common timing assistance, not two independently acquiring
receiver implementations. EVM improvement is not direct jammer-power suppression.

The tests cover frozen-weight null behavior near ±30° in the half-wave simulation,
tracking with an independent modulated interferer, and fragmented versioned TCP
frames. The dashboard renders headlessly with `--simulate --snapshot out/live.png`;
finite processing checks use `--simulate --headless --frames 30`. No physical
antenna results or real-time speed bound are established by those checks.

Current physical milestone: the direct ADC_A path has demonstrated approximately
9captures/s with waveform2 over100liveframes, medianEVM3.79%, maximum9.98%, zeroBER
and no acquisition failures or missing processed sequences. Distributed pilots
estimate timing slope as well as phase, and the selected output panel shows the
estimated timing range. Raw~100ppm sample loss still exists, so constantEVM and
lossless capture are not claimed. The standard245.76/491.52 profile did not match
the overlay's fixedclock ratios/mixed converter topology;500/500was restored.
