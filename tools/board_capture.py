#!/usr/bin/env python3
"""Bounded board experiment. Run only with exclusive control; see docs/HARDWARE.md.

Uses the existing matched /boot wrapper and overlay, including its clock/MTS init.
Never replaces boot files. Does not manage services or MXG automatically.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import socket
import struct
import itertools
import signal
import numpy as np


def fixed_output_flag(overlay, name, gpio):
    description = getattr(gpio, 'description', None)
    if description and 'C_ALL_OUTPUTS' in description.get('parameters', {}):
        return int(description['parameters']['C_ALL_OUTPUTS'])
    key = 'control/gpio_control/axi_gpio_'+name.replace('_enable','')
    metadata = getattr(overlay, 'ip_dict', {}).get(key, {}).get('parameters', {})
    if 'C_ALL_OUTPUTS' in metadata:
        return int(metadata['C_ALL_OUTPUTS'])
    # Installed AxiGPIO lacks description on this board. Use the matched HWH,
    # which was independently hash-checked before the experiment.
    import xml.etree.ElementTree as ET
    modules = [m for m in ET.parse('/boot/doa_mts.hwh').iter('MODULE') if m.get('FULLNAME') == '/'+key]
    if len(modules) != 1:
        raise RuntimeError('Ambiguous GPIO metadata: '+name)
    values = [p.get('VALUE') for p in modules[0].iter('PARAMETER') if p.get('NAME') == 'C_ALL_OUTPUTS']
    if len(values) != 1:
        raise RuntimeError('Missing GPIO fixed-output configuration: '+name)
    return int(values[0])


def shutdown(overlay, manifest):
    """Disable both DACs; register observations cannot prove physical RF-off.

    PG144 specifies zero reads for output DATA bits. PYNQ slice read() either
    changes direction (InOut) or reads a software shadow (Output). Avoid both.
    """
    errors, readbacks = [], {}
    zeroed = []
    for name in ('dac0_player','dac1_player'):
        if hasattr(overlay,name):
            try:
                getattr(overlay,name)[:] = 0
                zeroed.append(name)
            except Exception as exc:
                errors.append(f'{name} clear: {type(exc).__name__}: {exc}')
    if zeroed:
        time.sleep(.003)  # Allow an active player to consume zeros before disable.
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
    manifest['dac_off_commanded'] = not errors and len(readbacks) == 2
    manifest['dac_off_verified'] = False
    manifest['dac_off_verification_note'] = 'AXI GPIO output DATA reads return zero; independent RF observation required'


def require_lock(overlay, manifest, stage):
    value = int(overlay.clocktreeMTS.MTSclkwiz.read(4))
    manifest.setdefault('clock_lock_readbacks', {})[stage] = value
    if value != 1:
        raise RuntimeError(f'Clock tree unlocked at {stage}: {value}')


def load_selected_dacs(overlay, words, selected):
    """Capture trigger also enables both DAC players in the matched HWH.

    Zero the unselected player's entire RAM, not just its software enable.
    """
    zero = np.zeros_like(words)
    overlay.dac_data_mem_write(words if selected in ('0', 'both') else zero, overlay.dac0_player)
    overlay.dac_data_mem_write(words if selected in ('1', 'both') else zero, overlay.dac1_player)


def settled_capture(overlay):
    """The wrapper's da=0 capture has no completion wait before reading RAM."""
    overlay.trigger_capture()
    time.sleep(.003)  # > 131 us for returned frame; verify full-RAM duration on board.
    return np.array(overlay.adc_capture[:131072], dtype='<i2', copy=True)


def main():
    def interrupted(signum, frame):
        raise SystemExit(f'Capture interrupted by signal {signum}')
    for signum in (signal.SIGTERM, getattr(signal,'SIGHUP',signal.SIGTERM)):
        signal.signal(signum,interrupted)
    p = argparse.ArgumentParser()
    p.add_argument('--reference', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--frames', type=int, default=10)
    p.add_argument('--stream-bind', help='Explicit local bind address for versioned live TCP stream')
    p.add_argument('--stream-port', type=int, default=4010)
    p.add_argument('--rf-mhz', type=int, default=3000)
    p.add_argument('--dac', choices=['0', '1', 'both'], default='0')
    p.add_argument('--phase1', type=int, default=0)
    p.add_argument('--sampling-freq-unit', choices=['GHz', 'MHz', 'Hz'], required=True,
                   help='Set only after inspecting the installed driver SamplingFreq units')
    p.add_argument('--exclusive-control', action='store_true', required=True)
    a = p.parse_args()
    if not 2000 <= a.rf_mhz <= 4200 or not 0 <= a.frames <= 10000:
        p.error('Use 2000..4200 MHz and 0..10000 frames')
    if a.frames == 0 and not a.stream_bind:
        p.error('--frames 0 requires --stream-bind (stream until disconnect)')
    board = Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(b'\x00')
    if board != b'RFSoC4x2':
        raise RuntimeError('Wrong board identity')
    with np.load(a.reference, allow_pickle=False) as data:
        words = data['dac_words']
        if 'dac_complex_fs' not in data or float(data['dac_complex_fs']) != 500e6:
            raise ValueError('Regenerate reference with mode3 IMR2, 500 Mcomplex/s input metadata')
        if 'waveform_version' not in data or int(data['waveform_version']) != 2:
            raise ValueError('Regenerate version2 reference with distributed timing pilots')
    if words.dtype != np.dtype('int16') or words.shape != (65536,) or np.max(np.abs(words.astype(float))) > 1200:
        raise ValueError('Initial live helper requires 65536 int16 DAC words with peak <= 1200')
    manifest = {'board': board.decode(), 'rf_mhz': a.rf_mhz, 'dac': a.dac,
                'dac_connector': {'0':'DAC_B','1':'DAC_A','both':'DAC_A + DAC_B'}[a.dac],
                'receive_stream0_connector': 'ADC_D',
                'phase1_deg': a.phase1, 'fs_assumed_hz': 125e6, 'frames': a.frames,
                'wrapper_sha256': hashlib.sha256(Path('/boot/doa_mts.py').read_bytes()).hexdigest(),
                'reference_sha256': hashlib.sha256(Path(a.reference).read_bytes()).hexdigest(),
                'dac_off_verified': False, 'waveform_version': 2}
    # Import has OLED side effects; constructor programs FPGA, clocks and MTS.
    sys.path.insert(0, '/boot')
    from doa_mts import doaMtsOverlay
    overlay = None
    listener, client = None, None
    output = Path(a.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    try:
        overlay = doaMtsOverlay('/boot/doa_mts.bit')
        overlay.dacs_off()
        load_selected_dacs(overlay, np.zeros_like(words), '0')
        require_lock(overlay, manifest, 'initialization')
        manifest['sampling_freq_unit'] = a.sampling_freq_unit
        manifest['adc_rates_raw'] = [overlay.adc[n].BlockStatus['SamplingFreq'] for n in range(4)]
        manifest['adc_decimation'] = [overlay.adc[n].DecimationFactor for n in range(4)]
        manifest['dac_rates_raw'] = [overlay.dac[n].BlockStatus['SamplingFreq'] for n in (0, 2)]
        manifest['dac_interpolation'] = [overlay.dac[n].InterpolationFactor for n in (0, 2)]
        manifest['dac_datapath_mode'] = [overlay.dac[n].DataPathMode for n in (0, 2)]
        manifest['dac_imr_pass_mode'] = [overlay.dac[n].IMRPassMode for n in (0, 2)]
        factor = {'GHz': 1e9, 'MHz': 1e6, 'Hz': 1}[a.sampling_freq_unit]
        adc_fs = np.array(manifest['adc_rates_raw'])*factor/np.array(manifest['adc_decimation'])
        dac_fs = np.array(manifest['dac_rates_raw'])*factor/np.array(manifest['dac_interpolation'])
        manifest['dac_effective_complex_fs_hz'] = (dac_fs/2).tolist()
        if (not np.allclose(adc_fs, 125e6) or not np.allclose(dac_fs/2, 500e6)
                or manifest['dac_datapath_mode'] != [3, 3]):
            raise RuntimeError('Runtime rates differ from generated reference')
        overlay.centre_freq = a.rf_mhz
        overlay.nyquist_zone = 2
        overlay.d_centre_freq = [a.rf_mhz]*4
        overlay.d_nyquist_zone = [1]*4  # 10 GS/s DAC: 3 GHz is first Nyquist zone.
        overlay.d_phases = [0, 0, a.phase1, a.phase1]
        overlay.configure_dacs()
        overlay.configure_adcs()
        overlay.sync_tiles()
        require_lock(overlay, manifest, 'after_sync')
        load_selected_dacs(overlay, words, a.dac)
        manifest['inactive_dac_ram_zeroed'] = True
        manifest['capture_settle_seconds'] = .003
        manifest['adc_ram_words'] = len(overlay.adc_capture)
        manifest['dac_ram_words'] = [len(overlay.dac0_player), len(overlay.dac1_player)]
        overlay.da = 0
        overlay.dacPower = [int(a.dac in ('0','both')), 0, int(a.dac in ('1','both')), 0]
        if a.stream_bind:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind((a.stream_bind, a.stream_port))
            listener.listen(1)
            listener.settimeout(120)
            print(f'Waiting for demo client on port {a.stream_port}; DACs disabled', flush=True)
            client, _ = listener.accept()
            client.settimeout(5)
            client.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 262144)
            header = json.dumps({'format': 'int16le-I-minus-jQ-4ch', 'frame_bytes': 262144,
                                 'fs_hz': 125e6, 'rf_mhz': a.rf_mhz,
                                 'waveform_version': 2,
                                 'dac_connector': manifest['dac_connector'],
                                 'receive_stream0_connector': 'ADC_D',
                                 'timestamp': 'board monotonic ns; not synchronized with host'}).encode()
            client.sendall(b'R4X2IQ1\n'+struct.pack('<I', len(header))+header)
        overlay.dacs_control()
        captures = []
        for sequence in (range(a.frames) if a.frames else itertools.count()):
            raw_words = settled_capture(overlay)
            captured_ns = time.monotonic_ns()
            raw = raw_words.reshape(-1, 8).astype(float)
            if client is not None:
                body = raw_words.tobytes()
                client.sendall(struct.pack('<4sQQI', b'IQF1', sequence, captured_ns, len(body))+body)
                captures.clear()  # Live operation retains only the latest capture.
            captures.append(raw[:, 0::2]-1j*raw[:, 1::2])
            manifest['frames_captured'] = sequence+1
            # Bounded diagnostics even for an indefinitely running live demo.
            recent = manifest.setdefault('recent_captures', [])
            recent.append({'sequence': sequence, 'monotonic_ns': captured_ns,
                           'sha256': hashlib.sha256(raw_words.tobytes()).hexdigest()})
            del recent[:-64]
            if client is not None:
                # Save one current capture on disconnect as well as clean completion.
                last_capture = captures[-1]
            time.sleep(.1)
        np.savez_compressed(output, samples=np.stack(captures), fs=125e6, waveform_version=2)
    except (BrokenPipeError, ConnectionResetError) as exc:
        manifest['stream_stop'] = type(exc).__name__
        if 'last_capture' in locals():
            np.savez_compressed(output, samples=last_capture[None], fs=125e6, waveform_version=2)
    except BaseException as exc:
        failed = True
        manifest['experiment_error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        for connection in (client, listener):
            if connection is not None:
                connection.close()
        if overlay is not None:
            shutdown(overlay, manifest)
        else:
            manifest['shutdown_errors'] = ['Overlay construction did not return; output state unknown']
        try:
            output.with_suffix('.json').write_text(json.dumps(manifest, indent=2)+'\n')
        except Exception as exc:
            print(f'Could not persist manifest: {exc}; status: {manifest}', file=sys.stderr)
            if not failed:
                raise
        if not manifest.get('dac_off_commanded', False):
            print('DAC disable command FAILED/UNVERIFIED: '+str(manifest.get('shutdown_errors')), file=sys.stderr)
            if not failed:
                raise RuntimeError('DAC disable command failed; inspect hardware state')
        else:
            print('DAC disable commanded; physical RF-off requires independent observation.', file=sys.stderr)
    print(output)


if __name__ == '__main__':
    main()
