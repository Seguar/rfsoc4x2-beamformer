"""Build an owned MATLAB frontend command; no RF actions or shell interpolation."""
import json
from pathlib import Path
import shutil
from scipy.io import savemat
from rfsoc_demo.dsp import reference, FS, NFFT, CP, TRAIN, BINS, PILOT_INDEX


def literal(value):
    value = str(value)
    if any(c in value for c in ('\n', '\r', '\0')):
        raise ValueError('MATLAB paths must not contain line breaks or NUL')
    return "'"+value.replace("'", "''")+"'"


def command(root, out, config, *, headless, frames, use_vsa):
    """Write only selected frontend settings, never the SSH password/config."""
    matlab = config.get('matlab_executable') or shutil.which('matlab')
    if not matlab:
        raise RuntimeError('Set matlab_executable in private config or add MATLAB to PATH')
    wave, symbols = reference()
    ref_path = out/'matlab-reference.mat'
    savemat(ref_path, dict(wave=wave[:, None], symbols=symbols,
        nfft=float(NFFT), cp=float(CP), train=float(TRAIN), fsHz=FS,
        bins=(BINS+1)[None, :].astype(float),
        pilots=(PILOT_INDEX+1)[None, :].astype(float), waveformVersion=2))
    settings = dict(host=config['host'], profile='demo-framed', port=4010,
        fsHz=FS, referencePath=str(ref_path), directOnly=True,
        activeChannel=1, useVsa=use_vsa, logPath=str(out/'matlab-live.jsonl'))
    if headless:
        settings['maxFrames'] = frames
    if use_vsa:
        settings['vsa'] = dict(config.get('matlab_vsa', {}))
        required = ('dllPath','customOfdmDllPath','typedHelperPath','fsHz','fcHz',
                    'bandwidthHz','captureSamples','visible')
        if any(key not in settings['vsa'] for key in required):
            raise ValueError('matlab_vsa requires explicit SDK/helper DLLs, rates, capture size and visibility')
        if settings['vsa']['fsHz'] != FS:
            raise ValueError('VSA setup must match the actual 125 Mcomplex/s input')
        for key in ('dllPath', 'customOfdmDllPath', 'typedHelperPath'):
            if not Path(settings['vsa'][key]).is_file():
                raise ValueError('VSA '+key+' does not exist')
        settings['vsa'].setdefault('measurementTimeoutSeconds', 3)
        settings['vsa']['referencePath'] = str(ref_path)
        if settings['vsa']['measurementTimeoutSeconds'] > 4:
            raise ValueError('Live VSA processing timeout must be <=4s for bounded board streaming')
    settings_path = out/'matlab-frontend.json'
    settings_path.write_text(json.dumps(settings, indent=2)+'\n')
    entry = out/'run_matlab.m'
    lines = [f'addpath({literal(root/"matlab")});',
        'cfg=rfsoc.defaultConfig();',
        f'overrides=jsondecode(fileread({literal(settings_path)}));',
        'names=fieldnames(overrides);',
        'for k=1:numel(names), cfg.(names{k})=overrides.(names{k}); end',
        'cfg.host=string(cfg.host); cfg.profile=string(cfg.profile);']
    lines += ['runHeadless(cfg);'] if headless else [
        'app=runBeamformingDemo(cfg);', 'waitfor(app.Figure);']
    entry.write_text('\n'.join(lines)+'\n')
    args = [str(matlab), '-wait']
    if headless:
        args.append('-noFigureWindows')
    args += ['-logfile', str(out/'matlab.log'), '-batch', 'run('+literal(entry)+')']
    return args
