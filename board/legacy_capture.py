#!/usr/bin/env python3
"""Owned legacy-wave capture helper v2 (derived from reviewed board_capture.py
sha 41d2d619...). Run only with exclusive control.

Kept from board_capture.py / helper v1: board identity, wrapper hash record, runtime
rate/IMR/mode3 checks, clock-lock readbacks (init, after sync, every frame), inactive
DAC full-RAM zero with readback, shutdown that zeroes both DAC RAMs (readback) and
then turns both enables off, full DAC RAM written explicitly (1048576 words, peak
<= 1200, explicit truncation of the 1100250-word legacy file), full ADC RAM capture
(1048576 words = 131072 contiguous complex per stream) with sentinel + hash
freshness, request/response (one byte b'N' per wanted frame; capture only after
the request), bounded schedule <= 30 frames (wave:k, blank:k, pause:s <= 10 s).

v2 transport:
  * the wire carries ONLY the measured stream: stream0 = ADC_D, lanes 0:1 of every
    row of the full-RAM capture, i.e. all 131072 contiguous complex samples of that
    stream (524288 bytes). The full 4-stream RAM is still captured and checked.
    Metadata states the wire channels, format, byte size and availableChannels mask.
  * frame header IQL2 also carries the board-monotonic time at which the request
    byte was received, so the host can anchor acquisition time on its own clock
    (host request-send time + board delay request->capture): conservative, no
    board/host clock offset or drift.
  * owner binding: --owner-stdin (required) stops the helper when its stdin reaches
    EOF (owning launcher / plink session gone). All waits poll this every <= 0.25 s.
  * continuous mode exists ONLY with --continuous plus explicit --max-seconds
    (<= 14400) and --max-frames, and still needs --owner-stdin. There is no
    default unbounded run.
Never replaces boot files, never manages services/network/clocks beyond the wrapper
constructor (same as the reviewed helper), never touches the MXG.
"""
import argparse, hashlib, json, os, signal, socket, struct, sys, threading, time, zlib
from pathlib import Path
import numpy as np

PROFILE = 'legacy-ofdm64-truncated-v1'
SRC_SHA = '3f17e6cccef941d1bac4fefff4439472d8a6e6923b0ef7633e6184448be9eef3'
RAM = 1048576
SENTINEL = np.array([32767, -32768, 32767, -32768, 32767, -32768, 32767, -32768], dtype='<i2')
SETTLE = 0.005  # full RAM = 1.049 ms at 125 MHz
WIRE_FORMAT = 'int16le-IQ-1ch-fullram-v2'   # per sample: I, Q of the single wire stream
FRAME_HDR = '<4sQQQq8sII'                    # magic seq capture_mono req_rx_mono realtime label mask nbytes
MASK = 0b0001                                # bit k set = stream k measured; stream0 = ADC_D
WIRE_BYTES = (RAM // 8) * 2 * 2
MAX_CONTINUOUS_S = 14400
CODEC = 'byteplane-shuffle+deflate-raw-lossless'   # IQZ2 body = <I raw_len><32s sha256(raw wire)> + deflate
PAD_BYTES = 262144                                  # PAD2 link warm-up filler (zeros, not ADC data)
PAD_LIMIT = 3


def encode_wire(body):
    """Lossless: low-byte plane then high-byte plane of the int16 stream, raw deflate."""
    planes = np.frombuffer(body, np.uint8).reshape(-1, 2).T.tobytes()
    co = zlib.compressobj(1, zlib.DEFLATED, -15)
    comp = co.compress(planes) + co.flush()
    return struct.pack('<I32s', len(body), hashlib.sha256(body).digest()) + comp
OWNER_GONE = threading.Event()


def watch_owner():
    """stdin EOF means the owning launcher (or its ssh session) is gone."""
    try:   # raw fd (no buffered-reader lock held at interpreter shutdown)
        while os.read(0, 4096):
            pass
    except Exception:
        pass
    OWNER_GONE.set()


def owner_check():
    if OWNER_GONE.is_set():
        raise SystemExit('owner stdin closed: stopping')


def fixed_output_flag(overlay, name, gpio):
    description = getattr(gpio, 'description', None)
    if description and 'C_ALL_OUTPUTS' in description.get('parameters', {}):
        return int(description['parameters']['C_ALL_OUTPUTS'])
    key = 'control/gpio_control/axi_gpio_'+name.replace('_enable', '')
    metadata = getattr(overlay, 'ip_dict', {}).get(key, {}).get('parameters', {})
    if 'C_ALL_OUTPUTS' in metadata:
        return int(metadata['C_ALL_OUTPUTS'])
    import xml.etree.ElementTree as ET
    modules = [m for m in ET.parse('/boot/doa_mts.hwh').iter('MODULE') if m.get('FULLNAME') == '/'+key]
    if len(modules) != 1:
        raise RuntimeError('Ambiguous GPIO metadata: '+name)
    values = [p.get('VALUE') for p in modules[0].iter('PARAMETER') if p.get('NAME') == 'C_ALL_OUTPUTS']
    if len(values) != 1:
        raise RuntimeError('Missing GPIO fixed-output configuration: '+name)
    return int(values[0])


def shutdown(overlay, manifest):
    errors, readbacks, zeroed = [], {}, []
    for name in ('dac0_player', 'dac1_player'):
        if hasattr(overlay, name):
            try:
                getattr(overlay, name)[:] = 0
                if np.any(np.asarray(getattr(overlay, name)[:]) != 0):
                    errors.append(name+' readback not all zero')
                zeroed.append(name)
            except Exception as exc:
                errors.append(f'{name} clear: {type(exc).__name__}: {exc}')
    if zeroed:
        time.sleep(.003)
    manifest['dac_ram_zero_writes'] = zeroed
    for name in ('dac0_enable', 'dac1_enable'):
        try:
            getattr(overlay, name).off()
        except Exception as exc:
            errors.append(f'{name} off: {type(exc).__name__}: {exc}')
    for name in ('dac0_enable', 'dac1_enable'):
        try:
            pin = getattr(overlay, name)
            channel = pin._parent
            gpio = channel._parent
            data = int(gpio.read(channel._channel * 8))
            tri = int(gpio.read(channel._channel * 8 + 4))
            shadow = (int(channel._val) >> pin._start) & pin._mask
            all_outputs = fixed_output_flag(overlay, name, gpio)
            readbacks[name] = {'data_register': data, 'tri_register': tri,
                               'command_shadow': shadow, 'all_outputs': all_outputs}
            if (not all_outputs and (tri >> pin._start) & pin._mask) or shadow:
                errors.append(name+' disable command/direction inconsistent')
        except Exception as exc:
            errors.append(f'{name} read: {type(exc).__name__}: {exc}')
    manifest['dac_readbacks'] = readbacks
    manifest['shutdown_errors'] = errors
    manifest['dac_off_commanded'] = not errors and len(readbacks) == 2 and len(zeroed) == 2
    manifest['dac_off_verified'] = False
    manifest['dac_off_verification_note'] = 'RAM zero readback + enable off commanded; independent RF observation required'


def require_lock(overlay, manifest, stage):
    value = int(overlay.clocktreeMTS.MTSclkwiz.read(4))
    if len(manifest.setdefault('clock_lock_readbacks', {})) < 2000:
        manifest['clock_lock_readbacks'][stage] = value
    if value != 1:
        raise RuntimeError(f'Clock tree unlocked at {stage}: {value}')


def write_dac(overlay, words, selected):
    """Write full RAM explicitly (len == RAM: the wrapper neither tiles nor truncates)."""
    zero = np.zeros(RAM, dtype='<i2')
    a = words if selected == '0' else zero
    b = words if selected == '1' else zero
    assert len(overlay.dac0_player) == RAM and len(overlay.dac1_player) == RAM
    overlay.dac_data_mem_write(a, overlay.dac0_player)
    overlay.dac_data_mem_write(b, overlay.dac1_player)
    ok0 = np.array_equal(np.asarray(overlay.dac0_player[:]), a)
    ok1 = np.array_equal(np.asarray(overlay.dac1_player[:]), b)
    if not (ok0 and ok1):
        raise RuntimeError('DAC RAM readback mismatch')


def full_capture(overlay, previous_sha):
    """Freshness: tail sentinel must be overwritten (if RAM is PS-writable) AND the
    capture must differ from the previous one (ADC noise makes repeats impossible)."""
    overlay.adc_capture[RAM-8:RAM] = SENTINEL
    writable = np.array_equal(np.asarray(overlay.adc_capture[RAM-8:RAM]), SENTINEL)
    overlay.trigger_capture()
    time.sleep(SETTLE)
    raw = np.array(overlay.adc_capture[:RAM], dtype='<i2', copy=True)
    sha = hashlib.sha256(raw.tobytes()).hexdigest()
    refreshed = sha != previous_sha and not (writable and np.array_equal(raw[-8:], SENTINEL))
    return raw, refreshed, writable, sha


def wait_request(client, timeout, deadline, pads):
    """Wait for one frame request b'N'; check owner and deadline every 0.25 s.
    b'W' asks for one PAD2 link warm-up filler (not ADC data; at most PAD_LIMIT)."""
    t0 = time.monotonic()
    client.settimeout(0.25)
    while True:
        owner_check()
        if deadline is not None and time.monotonic() > deadline:
            raise SystemExit('max-seconds reached: stopping')
        try:
            req = client.recv(1)
        except socket.timeout:
            if time.monotonic() - t0 > timeout:
                raise
            continue
        if req == b'W' and pads[0] < PAD_LIMIT:
            pads[0] += 1
            client.settimeout(30)
            client.sendall(struct.pack(FRAME_HDR, b'PAD2', pads[0], time.monotonic_ns(), 0, time.time_ns(),
                                       b'warmup  ', 0, PAD_BYTES) + bytes(PAD_BYTES))
            client.settimeout(0.25)
            continue
        if req != b'N':
            raise ConnectionResetError('client closed or bad request')
        return time.monotonic_ns()


def parse_schedule(text):
    phases, frames = [], 0
    for item in text.split(','):
        kind, value = item.split(':')
        if kind in ('wave', 'blank'):
            n = int(value)
            if not 1 <= n <= 30:
                raise ValueError('phase frames 1..30')
            frames += n
            phases.append((kind, n))
        elif kind == 'pause':
            s = float(value)
            if not 0 < s <= 10:
                raise ValueError('pause 0..10 s')
            phases.append((kind, s))
        else:
            raise ValueError('unknown phase '+kind)
    if frames > 30 or not phases or phases[0][0] != 'wave':
        raise ValueError('schedule must start with wave and total <= 30 frames')
    return phases, frames


def main():
    def interrupted(signum, frame):
        raise SystemExit(f'Capture interrupted by signal {signum}')
    for signum in (signal.SIGTERM, getattr(signal, 'SIGHUP', signal.SIGTERM)):
        signal.signal(signum, interrupted)
    p = argparse.ArgumentParser()
    p.add_argument('--reference', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--schedule')
    p.add_argument('--continuous', action='store_true')
    p.add_argument('--max-seconds', type=float)
    p.add_argument('--max-frames', type=int)
    p.add_argument('--owner-stdin', action='store_true', required=True)
    p.add_argument('--stream-bind', required=True)
    p.add_argument('--stream-port', type=int, default=4011)
    p.add_argument('--rf-mhz', type=int, default=3000)
    p.add_argument('--dac', choices=['0', '1'], default='0')
    p.add_argument('--sampling-freq-unit', choices=['GHz'], required=True)
    p.add_argument('--request-timeout', type=float, default=30)
    p.add_argument('--wire-codec', choices=['raw', 'deflate'], default='deflate')
    p.add_argument('--exclusive-control', action='store_true', required=True)
    a = p.parse_args()
    if a.rf_mhz != 3000:
        p.error('legacy profile validated only at 3000 MHz')
    if a.continuous:
        if a.schedule or a.max_seconds is None or a.max_frames is None:
            p.error('--continuous needs --max-seconds and --max-frames, and no --schedule')
        if not (0 < a.max_seconds <= MAX_CONTINUOUS_S and 1 <= a.max_frames <= 200000):
            p.error('continuous bounds out of range')
        phases, total = [('wave', a.max_frames)], a.max_frames
    else:
        if not a.schedule or a.max_frames is not None:
            p.error('bounded mode needs --schedule (<= 30 frames) and no --max-frames')
        phases, total = parse_schedule(a.schedule)
    deadline = None if a.max_seconds is None else time.monotonic() + a.max_seconds
    threading.Thread(target=watch_owner, daemon=True).start()
    board = Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(b'\x00')
    if board != b'RFSoC4x2':
        raise RuntimeError('Wrong board identity')
    with np.load(a.reference, allow_pickle=False) as data:
        words = np.asarray(data['dac_words'])
        if (str(data['profile']) != PROFILE or str(data['source_sha256']) != SRC_SHA
                or float(data['dac_complex_fs']) != 500e6 or int(data['ram_words']) != RAM):
            raise ValueError('Reference is not the reviewed legacy truncated profile')
        dropped = int(data['dropped_complex_500'])
    if words.dtype != np.dtype('<i2') or words.shape != (RAM,) or np.max(np.abs(words.astype(int))) > 1200:
        raise ValueError('Legacy helper requires 1048576 int16 words with peak <= 1200')
    manifest = {'board': board.decode(), 'rf_mhz': a.rf_mhz, 'dac': a.dac,
                'dac_connector': {'0': 'DAC_B', '1': 'DAC_A'}[a.dac],
                'receive_stream0_connector': 'ADC_D', 'fs_assumed_hz': 125e6,
                'profile': PROFILE, 'schedule': a.schedule, 'frames_planned': total,
                'continuous': bool(a.continuous), 'max_seconds': a.max_seconds, 'owner_stdin': True,
                'wire_format': WIRE_FORMAT, 'wire_channels': [0], 'wire_bytes': WIRE_BYTES,
                'wire_codec': CODEC if a.wire_codec == 'deflate' else 'none',
                'loop_truncation': {'played_complex_500': RAM//2, 'dropped_complex_500': dropped,
                                    'boundary_loop_index': 0},
                'wrapper_sha256': hashlib.sha256(Path('/boot/doa_mts.py').read_bytes()).hexdigest(),
                'reference_sha256': hashlib.sha256(Path(a.reference).read_bytes()).hexdigest(),
                'helper_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                'dac_off_verified': False, 'frames': []}
    sys.path.insert(0, '/boot')
    from doa_mts import doaMtsOverlay
    overlay = listener = client = None
    output = Path(a.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    sequence = 0
    try:
        owner_check()
        overlay = doaMtsOverlay('/boot/doa_mts.bit')
        overlay.dacs_off()
        write_dac(overlay, np.zeros(RAM, dtype='<i2'), '0')
        require_lock(overlay, manifest, 'initialization')
        manifest['adc_rates_raw'] = [overlay.adc[n].BlockStatus['SamplingFreq'] for n in range(4)]
        manifest['adc_decimation'] = [overlay.adc[n].DecimationFactor for n in range(4)]
        manifest['dac_rates_raw'] = [overlay.dac[n].BlockStatus['SamplingFreq'] for n in (0, 2)]
        manifest['dac_interpolation'] = [overlay.dac[n].InterpolationFactor for n in (0, 2)]
        manifest['dac_datapath_mode'] = [overlay.dac[n].DataPathMode for n in (0, 2)]
        manifest['dac_imr_pass_mode'] = [overlay.dac[n].IMRPassMode for n in (0, 2)]
        adc_fs = np.array(manifest['adc_rates_raw'])*1e9/np.array(manifest['adc_decimation'])
        dac_fs = np.array(manifest['dac_rates_raw'])*1e9/np.array(manifest['dac_interpolation'])
        manifest['dac_effective_complex_fs_hz'] = (dac_fs/2).tolist()
        if (not np.allclose(adc_fs, 125e6) or not np.allclose(dac_fs/2, 500e6)
                or manifest['dac_datapath_mode'] != [3, 3]):
            raise RuntimeError('Runtime rates differ from legacy reference')
        overlay.centre_freq = a.rf_mhz
        overlay.nyquist_zone = 2
        overlay.d_centre_freq = [a.rf_mhz]*4
        overlay.d_nyquist_zone = [1]*4
        overlay.d_phases = [0, 0, 0, 0]
        overlay.configure_dacs()
        overlay.configure_adcs()
        overlay.sync_tiles()
        require_lock(overlay, manifest, 'after_sync')
        if len(overlay.adc_capture) != RAM:
            raise RuntimeError('ADC RAM size differs')
        manifest['adc_ram_words'] = RAM
        overlay.da = 0
        overlay.dacPower = [int(a.dac == '0'), 0, int(a.dac == '1'), 0]
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((a.stream_bind, a.stream_port))
        listener.listen(1)
        listener.settimeout(1)
        print(f'Waiting for legacy client on port {a.stream_port}; DACs disabled', flush=True)
        t_listen = time.monotonic()
        while client is None:
            owner_check()
            if time.monotonic() - t_listen > 120:
                raise socket.timeout('no client within 120 s')
            try:
                client, _ = listener.accept()
            except socket.timeout:
                pass
        client.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2 << 20)
        client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        header = json.dumps({'magic_version': 2, 'source': 'rfsoc4x2-hardware', 'board': board.decode(),
                             'format': WIRE_FORMAT, 'adc_ram_words': RAM,
                             'capture': 'full-ram-contiguous', 'wire_channels': [0],
                             'available_channels': [1, 0, 0, 0],
                             'channel_connectors': ['ADC_D', None, None, None],
                             'lane_convention': 'board lanes I,Q; host builds I - 1j*Q (tcpDataRec)',
                             'frame_bytes': WIRE_BYTES, 'frame_header': FRAME_HDR,
                             'compression': CODEC if a.wire_codec == 'deflate' else 'none',
                             'pad_bytes': PAD_BYTES,
                             'samples_per_channel': RAM//8, 'fs_hz': 125e6, 'rf_mhz': a.rf_mhz,
                             'profile': PROFILE, 'dac_connector': manifest['dac_connector'],
                             'frames_planned': total, 'continuous': bool(a.continuous),
                             'max_seconds': a.max_seconds,
                             'board_monotonic_ns': time.monotonic_ns(),
                             'board_realtime_ns': time.time_ns()}).encode()
        client.settimeout(30)
        client.sendall(b'R4X2IQ2\n'+struct.pack('<I', len(header))+header)
        loaded = None
        previous_sha = None
        pads = [0]
        for kind, value in phases:
            if kind == 'pause':
                manifest['frames'].append({'pause_s': value, 'at_ns': time.monotonic_ns()})
                t_end = time.monotonic() + value
                while time.monotonic() < t_end:
                    owner_check()
                    time.sleep(0.05)
                continue
            target = words if kind == 'wave' else np.zeros(RAM, dtype='<i2')
            if loaded != kind:
                write_dac(overlay, target, a.dac)
                loaded = kind
                overlay.dacs_control()  # enables the selected DAC only (dacPower)
                time.sleep(.01)
            for _ in range(value):
                req_ns = wait_request(client, a.request_timeout, deadline, pads)
                require_lock(overlay, manifest, 'frame%d' % sequence)
                raw, refreshed, writable, previous_sha = full_capture(overlay, previous_sha)
                mono = time.monotonic_ns()
                if not refreshed:
                    raise RuntimeError('ADC RAM not refreshed (sentinel kept or identical capture)')
                label = kind.encode().ljust(8, b' ')
                wire = np.ascontiguousarray(raw.reshape(-1, 8)[:, 0:2])   # stream0 = ADC_D only
                body = wire.tobytes()
                if len(body) != WIRE_BYTES:
                    raise RuntimeError('wire size differs')
                payload = encode_wire(body) if a.wire_codec == 'deflate' else body
                client.settimeout(30)
                client.sendall(struct.pack(FRAME_HDR, b'IQZ2' if a.wire_codec == 'deflate' else b'IQL2',
                                           sequence, mono, req_ns, time.time_ns(),
                                           label, MASK, len(payload))+payload)
                ch0 = wire.astype(float)
                entry = {'sequence': sequence, 'phase': kind, 'monotonic_ns': mono,
                         'request_rx_ns': req_ns, 'sha256': previous_sha,
                         'wire_sha256': hashlib.sha256(body).hexdigest(), 'payload_bytes': len(payload),
                         'sentinel_writable': bool(writable),
                         'ch0_rms': float(np.sqrt(np.mean(ch0**2))),
                         'ch0_peak': int(np.max(np.abs(ch0)))}
                if len(manifest['frames']) < 2000:
                    manifest['frames'].append(entry)
                if not a.continuous and (sequence == 0 or kind == 'blank'):
                    np.save(output.parent/f'raw_{sequence:02d}_{kind}.npy', raw)
                sequence += 1
        manifest['frames_captured'] = sequence
        manifest['pads_sent'] = pads[0]
        client.settimeout(30)
        client.sendall(struct.pack(FRAME_HDR, b'END2', sequence, time.monotonic_ns(), 0, time.time_ns(),
                                   b'end     ', MASK, 0))
        # Wait (bounded) for the client to close first: closing with unread client
        # bytes would send RST and could discard END2 before the client reads it.
        client.settimeout(15)
        try:
            while client.recv(4096):
                pass
        except OSError:
            pass
    except (BrokenPipeError, ConnectionResetError, socket.timeout) as exc:
        manifest['stream_stop'] = f'{type(exc).__name__}: {exc}'
    except SystemExit as exc:
        if str(exc).startswith(('owner stdin closed', 'max-seconds reached')):
            manifest['stream_stop'] = str(exc)   # orderly owner/bound stop; shutdown still runs
        else:
            failed = True
            manifest['experiment_error'] = f'SystemExit: {exc}'
            raise
    except BaseException as exc:
        failed = True
        manifest['experiment_error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        manifest['frames_captured'] = sequence
        for connection in (client, listener):
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass
        if overlay is not None:
            shutdown(overlay, manifest)
        else:
            manifest['shutdown_errors'] = ['Overlay construction did not return; output state unknown']
        try:
            output.write_text(json.dumps(manifest, indent=1)+'\n')
        except Exception as exc:
            print(f'Could not persist manifest: {exc}', file=sys.stderr)
        if not manifest.get('dac_off_commanded', False):
            print('DAC disable FAILED/UNVERIFIED: '+str(manifest.get('shutdown_errors')), file=sys.stderr)
            if not failed:
                raise RuntimeError('DAC disable command failed; inspect hardware state')
        else:
            print('Both DAC RAMs zero (readback) and enables off commanded.', file=sys.stderr)
    print(output)


if __name__ == '__main__':
    main()
