# Board session service

`RFSoCBeamformer.exe` starts a hardware session by itself when the RFSoC4x2 runs
the session service (`board/session_service.py`). The service replaces the SSH
launcher for this use: the application needs only a TCP connection to the board.

## Install (once per board)

Installing is a persistent change on the board: files in
`/opt/rfsoc4x2-beamformer`, logs in `/var/lib/rfsoc4x2-beamformer` and one systemd
unit, `rfsoc4x2-beamformer.service`, enabled at boot. `/boot` is not written and
`bootpy.service` is not changed. The board must carry the matched `doa_rfsoc/main`
boot overlay and waveform; the installer builds the DAC reference from
`/boot/data.mat` on the board.

With the private launcher configuration (PuTTY, see `examples/board.example.json`):

```sh
python tools/install_board_service.py --config local/board.json
```

With an OpenSSH destination that logs in by key:

```sh
python tools/install_board_service.py --ssh <destination> --password-file <sudo password file> --address <board address>
```

`--status` shows the unit state and the service's identity reply. `--uninstall`
stops the unit and removes it with its files. `--allow-cidr <network>` adds a
client network (see Access).

## What a session does

1. The application connects to TCP port 4013 and asks for a session.
2. The service checks the board: RFSoC4x2 identity, the SHA-256 of the boot
   overlay and waveform, no notebook kernel or other capture program running, the
   stream ports free. A failed check is reported to the application and nothing
   on the board changes.
3. If `bootpy.service` is running, the service stops it for the session.
4. The service starts the capture helper (`legacy_capture.py`, four-stream
   `window4` profile, DAC_B and DAC_A (`--dacs AB`, DAC_A phase `--dac-a-phase 40`;
   `dacs` "B" or "AB" and `dac_a_phase_deg` in the start request), DAC peak code 24000 by
   default (`--dac-peak`, or `dac_peak` 100..24000 in the start request; the helper
   scales the 1200-peak reference and refuses the session if a start-up capture
   peaks above −6 dBFS at the ADC), bounded to at most 4 hours
   and 200000 frames) at the start frequency: 5.2 GHz by default (service option
   `--rf-mhz`, or `rf_mhz` 3000 or 5200 in the start request; see
   [RF_PROFILES.md](RF_PROFILES.md)). The helper loads the overlay and synchronises
   the converters; on the tested board this took about 10 s. At 5.2 GHz it then
   measures which DAC Nyquist zone adds constructively in this session (well under
   1 s) and reports the profile it set in the ready message (`rf_mhz`,
   `adc_nyquist_zone`, `dac_nyquist_zone`).
   It then sets PL clock 0 to 136.36 MHz (service option `--capture-clock-mhz`,
   0 keeps the overlay's 124.99875 MHz; a client may request another value with
   `capture_clock_mhz` in its start request). See "Capture sample loss" below.
5. The application receives the stream port (4011) and control port (4012) and
   runs as it does with the launcher ([BOARD_CONTROL.md](BOARD_CONTROL.md)).
6. When the window closes, the service stops the helper. The helper zeroes both
   DAC RAMs with readback and commands both outputs off; the application shows an
   error if the board does not confirm this. `bootpy.service` is started again
   only if it was running before.

The session connection is the owner of the helper. If the application crashes,
the cable is pulled (TCP keepalive, about 8 s) or the service is stopped, the
helper shuts down the same way. As with the launcher, the DAC-off record is a
command and readback record, not an independent RF measurement.

## Capture read time

The FPGA image writes each capture into on-chip RAM (2 MB, about 1 ms of signal);
the PS reads it word by word through an AXI BRAM controller (no DMA in the
image). Reading all of it takes about 69 ms per frame. A reduced window (Data
amount below 32768) reads only the rows its window search can use (the wrap
guard, one burst and the window: 44403 of 131072 rows for 4096) and the
sentinel tail; if a window ever ends beyond them, the rest of the same capture
is read. Measured on the board with a client one request ahead (4096 rows):
11.7 frames/s with the full read, 19.3 frames/s with the partial read. A start
request with `"full_read": true` (or the service option `--full-read`) restores
the full read. Capturing the next frame ahead on the board gave nothing more,
because the application already keeps one request ahead.

## DMA capture image

`doa_mts_dma` is the boot design plus an AXI CDMA that copies the capture RAM
into PS DDR (doa_rfsoc branch `dma-capture`, Vivado 2025.2; its files go in
`/opt/rfsoc4x2-beamformer/dma`, never in `/boot`; the service checks their
SHA-256). Board measurements, 2026-11-22:

| | Boot image | DMA image |
|---|---|---|
| Read all 2 MB | 45-49 ms (MMIO) | 1.1-1.2 ms copy, 4.5-6 ms with the Python call |
| Read 44403 rows (4096 window) | about 23 ms | 0.5 ms copy, 1.3-2 ms call |
| Frames/s at 4096, trigger hold 10 ms / 2 ms | 19.4 / 26.2 | 30.2 / 40.3 |
| Same capture read both ways | | identical in 20 of 20 |
| Slips at 136.36 MHz | 0 in 1.31 M rows | 0 in 1.31 M rows |

Levels, stream locks and the MTS start behaviour are the same with both
images. With either image, ADC tile 226 (streams 2 and 3) came up about 115 deg
off against tile 224 in 3 of 20 sessions; a stored 0 deg calibration is valid
only for sessions that start the same way (open issue).

The synced capture trigger is held 2 ms (the RAM fills in 1.09 ms and is full
when the trigger returns; the wrapper's original wait was 10 ms). Per session:
`"overlay": "boot"` and `"trigger_dwell_ms": 10` restore the original behaviour;
the service options `--overlay` and `--trigger-dwell-ms` change the defaults.

## Synchronised DAC starts (`dmasync`, default since 2026-11-23)

In the boot and DMA images the capture trigger, synchronised only to the PS clock
`pl_clk0`, was ORed with each DAC's GPIO enable and fed straight into the two DAC
waveform players, which run on the asynchronous RF fabric clock. Each player
sampled the edge on its own, so in a few per cent of captures one DAC started one
fabric cycle (8 ns, 4 DAC samples) after the other. With both DACs on, the two equal
copies then summed with a notch at the band centre on all four ADCs: whole frames
at about 10 % EVM instead of 7.6 % (OTA, 4.85 GHz). Vivado's CDC report showed the
crossing as 40 unknown endpoints.

`dmasync` is the DMA image plus `dac_start_sync` (doa_rfsoc branch `dma-capture`,
`PL/dma/src/dac_start_sync.v`, build variant `dmasync`): the trigger is synchronised
once into the RF fabric clock and both player enables are registered from that one
bit. Same file names as `dma`, installed in `/opt/rfsoc4x2-beamformer/dma-sync`
(SHA-256 checked). Timing met (WNS +0.175 ns, WHS +0.010 ns); the crossing now has
4 unknown endpoints (pre-existing), the new synchronisers are safe.

Board A/B, 2026-11-23, same settings (4.85 GHz OTA, both DACs, DAC A 40 deg, peak
24000, 4096 rows, client on the board), 1500 consecutive frames each:

| | `dma` | `dmasync` |
|---|---|---|
| Frames in the skewed-start state | 44 (2.9 %) | 0 |
| EVM median / p99 / max | 7.38 / 9.76 / 10.90 % | 6.83 / 7.77 / 8.26 % |
| Frames above 8.5 % EVM | 54 | 0 |
| Frames/s | 100.5 | 100.6 |

`"overlay": "dma"` or `"boot"` per session still selects the older images.

## Reduced-window frame offset

A reduced window starts 256 rows before an OFDM frame. Where the frames sit in
the capture is set by the shared player/capture start and the DAC to ADC
latency, so it hardly moves: live sessions on 2026-11-22 put it at row 16285 or
16286 in every frame of four sessions (a few rows of drift at most, which the
256-row lead covers). The helper therefore finds the offset with the correlation
search (about 14 ms) only on the first frame, once per second after that, at
once when the level at the window falls below 0.3 of the level at the last check
(signal gone or moved), and after a lost lock. In between it reuses the offset
(`candidate: "fixed"` in the frame summary, about 0.3 ms) and reads only the
rows up to the end of that window (20736 instead of 44403 for 4096 rows). The
application still checks every stream against the reference and refuses a
window that does not match. On the board, DMA image, 4096 rows, client one
request ahead: 106 frames/s (40 with a search on every frame).

## Board display (OLED)

The service writes the board's 2x16 character OLED (NHD-0216AW, `/dev/spidev1.0`,
driver `rfsoc4x2.oled` from the PYNQ board package) once per second:

| State | Line 1 | Line 2 |
|---|---|---|
| idle, `boot.py` running | left to `boot.py` (its address and TCP server state) | |
| idle, no `boot.py` | `RFSoC4x2 BF idle` | a board address (rotates every 4 s when there are several) |
| starting | `Starting 5200MHz` | `load+sync   12s` |
| ready, no frame yet | `Ready 5200MHz AB` | `waiting for app` |
| streaming | `EVM 3.88%   LIVE` (`EVM --` until the app reports one) | `5200MHz -19dB AB`: current RF, ADC peak of the last frame (dBFS), DACs |
| paused / no frame for 5 s | `PAUSED` / `no frames` | as above |
| ended (20 s) | `Session ended` | `DACs off 1234fr`, or `DAC OFF UNSURE!` |
| refused or failed (20 s) | `Board error` | the code, e.g. `board_busy` |

The helper writes `status.json` (frames, RF, ADC peak, the app's EVM) in the run
folder at most once per second; the application (v0.6.5 and later) sends its EVM
with the display-only `evm` command every 2 s over a second control connection,
so a display failure never stops acquisition. Older applications work unchanged
and show `EVM --`. Writes run in a background thread. A change is written in
place (cursor to the first changed character, then only those characters: an
EVM digit change takes 31 ms on the board instead of 466 ms for the driver's
clear-and-rewrite, and the screen does not blink); a new state, every start
second and every 15 s are whole-screen writes. Without the driver the display
stays off. `--no-oled` leaves it alone.
`boot.py` is stopped during a session; `/boot/doa_mts.py` clears the display
when the helper loads it, and the next one-second update writes it again.

## Capture sample loss

In the overlay the ADC streams run on the RF fabric clock (125 MHz from the RF
clocking) and reach the capture RAM writer through an AXI-Stream clock
converter into PL clock 0, which the processor derives from its own crystal
(124.99875 MHz). The RF ADC stream cannot be stalled, so a capture clock even
slightly slower than the stream overflows the converter and drops samples. The DAC
players run on the RF fabric clock and are not affected.

Measured live with `tools/slip_scan.py` (one-sample timing steps against the
transmitted loop, all four streams):

| PL clock 0 | Rows checked | Lost samples | Rate |
|---|---|---|---|
| 124.99875 MHz (overlay) | 819200 | 85, identical on all four streams | 104 ppm, one every ~10000 rows |
| 136.36227 MHz (IOPLL / 11, service default) | 1966080 | 0 | 0 |
| 149.9985 MHz (IOPLL / 10) | 819200 | 0 | 0 |

At 104 ppm about every third 3000-row OFDM burst contained a one-sample timing
step: the EVM spikes and the refused bursts ("pilot timing step 1.0 samples").
The capture writer waits for valid data, so a faster clock adds no samples (the
stream locks stayed 0.98). 136.36 MHz is the smallest available value above the
RF rate; it runs the PL clock 0 logic (capture writer, AXI interconnect, BRAM
controllers, RF data converter register port) 9 % above the 125 MHz the overlay
was built for. A rebuilt overlay with the capture writer on the RF fabric clock
would remove the clock crossing; that is a separate FPGA task.

## Access

The service has no login. It accepts clients from loopback, link-local and
private addresses, the 100.64.0.0/10 range, and any network the board is directly
attached to. A routed public address is refused unless the installer was given
`--allow-cidr`. One session runs at a time; a second client is told the board is
in use. Do not install it on a board whose network you do not control.

## Protocol

JSON lines on TCP port 4013. `{"op":"identify"}` returns
`{"service":"rfsoc4x2-beamformer","protocol":1,"board":"RFSoC4x2","busy":false}`.
`{"op":"start","max_seconds":N}` is answered by `starting` progress messages,
then `ready` with `host`, `stream_port` and `control_port`, or `error` with `code`
and `message`. `{"op":"stop"}` or closing the connection ends the session; the
service answers `ended` with `dac_off_commanded`, `shutdown_errors` and `frames`.
A UDP datagram `rfsoc4x2-beamformer?` on port 4013 is answered with the identity
reply; the application uses it to find the board on the local network.

Each session keeps `board.log`, `manifest.json` and `session.json` under
`/var/lib/rfsoc4x2-beamformer/runs/`; the newest 20 are kept.

## Validation

**Test / How:** `tests/test_session_service.py` runs the service with a fake
helper: identity over TCP and UDP, session start and stop, a second client, a
lost client, a stopped service, refusals and a failing helper.
`validateBoardLink` runs the MATLAB side against the same fake service: address
parsing, search order, the remembered address, session ownership, cancel and the
address window. The service was then installed on the RFSoC4x2 and the compiled
application was started on the MATLAB host over a routed private link: the
R2025b build once with `board <address>` and once with no arguments, the R2026a
build once with no arguments.

**Results:** 11 Python tests and the MATLAB test passed. The board-built DAC
reference equals the host-built one (identical DAC words). The three compiled
runs exited 0 with 39, 27 and 36 captured frames; the snapshot checked showed
4.2 % payload EVM. Each time the board reported both DAC RAMs zeroed and outputs
commanded off, with no shutdown errors and no helper left running. The runs
without arguments found the board through the remembered address after the USB
address did not answer. Both builds also still pass in simulation mode.

**Conclusions / Ways to resolve:** the service path works end to end with the
compiled application. Not tested: the USB link itself and the broadcast search
(the test host has neither a USB link nor a shared local network with the board;
the service does answer on the board's USB and static Ethernet addresses),
stopping and restoring a running `bootpy.service` on hardware (it was not
running; covered by the fake-helper test only), and a machine with only the
MATLAB Runtime.
