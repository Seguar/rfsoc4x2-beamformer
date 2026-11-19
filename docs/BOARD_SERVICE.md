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
   `window4` profile, DAC_B, DAC peak code 9600 by
   default (`--dac-peak`, or `dac_peak` 100..9600 in the start request; the helper
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
