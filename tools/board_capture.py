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
import numpy as np


def shutdown(overlay, manifest):
    """Disable both DACs; register observations cannot prove physical RF-off.

    PG144 specifies zero reads for output DATA bits. PYNQ slice read() either
    changes direction (InOut) or reads a software shadow (Output). Avoid both.
    """
    errors, readbacks = [], {}
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
            readbacks[name] = {'data_register': data, 'tri_register': tri,
                               'command_shadow': shadow}
            if (tri >> pin._start) & pin._mask or shadow:
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


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--reference', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--frames', type=int, default=10)
    p.add_argument('--rf-mhz', type=int, default=3000)
    p.add_argument('--dac', choices=['0', '1', 'both'], default='0')
    p.add_argument('--phase1', type=int, default=0)
    p.add_argument('--sampling-freq-unit', choices=['GHz', 'MHz', 'Hz'], required=True,
                   help='Set only after inspecting the installed driver SamplingFreq units')
    p.add_argument('--exclusive-control', action='store_true', required=True)
    a = p.parse_args()
    if not 2000 <= a.rf_mhz <= 4200 or not 1 <= a.frames <= 100:
        p.error('Use 2000..4200 MHz and 1..100 frames')
    board = Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(b'\x00')
    if board != b'RFSoC4x2':
        raise RuntimeError('Wrong board identity')
    with np.load(a.reference, allow_pickle=False) as data:
        words = data['dac_words']
    if words.dtype != np.dtype('int16') or words.shape != (65536,) or np.max(np.abs(words.astype(float))) > 1200:
        raise ValueError('Initial live helper requires 65536 int16 DAC words with peak <= 1200')
    manifest = {'board': board.decode(), 'rf_mhz': a.rf_mhz, 'dac': a.dac,
                'phase1_deg': a.phase1, 'fs_assumed_hz': 125e6, 'frames': a.frames,
                'wrapper_sha256': hashlib.sha256(Path('/boot/doa_mts.py').read_bytes()).hexdigest(),
                'reference_sha256': hashlib.sha256(Path(a.reference).read_bytes()).hexdigest(),
                'dac_off_verified': False}
    # Import has OLED side effects; constructor programs FPGA, clocks and MTS.
    sys.path.insert(0, '/boot')
    from doa_mts import doaMtsOverlay
    overlay = None
    output = Path(a.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    try:
        overlay = doaMtsOverlay('/boot/doa_mts.bit')
        overlay.dacs_off()
        require_lock(overlay, manifest, 'initialization')
        manifest['sampling_freq_unit'] = a.sampling_freq_unit
        manifest['adc_rates_raw'] = [overlay.adc[n].BlockStatus['SamplingFreq'] for n in range(4)]
        manifest['adc_decimation'] = [overlay.adc[n].DecimationFactor for n in range(4)]
        manifest['dac_rates_raw'] = [overlay.dac[n].BlockStatus['SamplingFreq'] for n in (0, 2)]
        manifest['dac_interpolation'] = [overlay.dac[n].InterpolationFactor for n in (0, 2)]
        factor = {'GHz': 1e9, 'MHz': 1e6, 'Hz': 1}[a.sampling_freq_unit]
        adc_fs = np.array(manifest['adc_rates_raw'])*factor/np.array(manifest['adc_decimation'])
        dac_fs = np.array(manifest['dac_rates_raw'])*factor/np.array(manifest['dac_interpolation'])
        if not np.allclose(adc_fs, 125e6) or not np.allclose(dac_fs, 1e9):
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
        overlay.dac_data_mem_write(words, overlay.dac0_player)
        overlay.dac_data_mem_write(words, overlay.dac1_player)
        overlay.da = 0
        overlay.dacPower = [int(a.dac in ('0','both')), 0, int(a.dac in ('1','both')), 0]
        overlay.dacs_control()
        captures = []
        for _ in range(a.frames):
            raw = np.asarray(overlay.get_custom_data(131072), dtype=np.int16).reshape(-1, 8).astype(float)
            captures.append(raw[:, 0::2]-1j*raw[:, 1::2])
            time.sleep(.1)
        np.savez_compressed(output, samples=np.stack(captures), fs=125e6)
    except BaseException as exc:
        failed = True
        manifest['experiment_error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
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
