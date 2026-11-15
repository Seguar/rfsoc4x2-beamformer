import argparse
import json
from pathlib import Path
import numpy as np
from .dsp import FS, reference, dac_words, process, simulate


def save_report(frames, out, source, fs):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    reports = []
    last = None
    for index, frame in enumerate(frames):
        try:
            report, last = process(frame, fs)
            report['frame'] = index
            report['status'] = 'locked'
        except ValueError as exc:
            report = {'frame': index, 'status': 'unlocked', 'reason': str(exc)}
        reports.append(report)
    result = {'source': source, 'sample_rate_hz': fs, 'frames': reports,
              'note': 'EVM and BER use held-out payload; no spatial angle is inferred.'}
    (out/'metrics.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    locked = [r for r in reports if r['status'] == 'locked']
    if not locked:
        raise RuntimeError('No locked frames; see metrics.json')
    fig, axes = plt.subplots(1, 3, figsize=(13, 3.8))
    for name, marker in [('adc0', 'o'), ('mrc', 's'), ('mvdr', '^')]:
        axes[0].plot([r['frame'] for r in locked],
                     [r['metrics'][name]['evm_percent'] for r in locked], marker=marker, label=name)
    axes[0].set(xlabel='Capture index', ylabel='Held-out payload EVM (%)', title=source)
    axes[0].legend()
    axes[1].plot([r['frame'] for r in locked], [r['tracking']['cfo_hz']/1000 for r in locked], 'o-')
    axes[1].set(xlabel='Capture index', ylabel='Pilot CFO (kHz)', title='Independent capture tracking')
    for name in ('adc0', 'mvdr'):
        z = last[name].ravel()
        z = z/np.sqrt(np.mean(abs(z)**2))
        axes[2].scatter(z.real, z.imag, s=5, alpha=.45, label=name)
    axes[2].set(xlabel='I (normalized)', ylabel='Q (normalized)', title='Last locked payload')
    axes[2].legend()
    for ax in axes:
        ax.grid(alpha=.2)
    fig.tight_layout()
    fig.savefig(out/'demo.png', dpi=150)
    plt.close(fig)
    print(json.dumps(result, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    s = sub.add_parser('simulate')
    s.add_argument('--shared-path', action='store_true')
    s.add_argument('--frames', type=int, default=5)
    s.add_argument('--out', default='out/simulation')
    s = sub.add_parser('reference')
    s.add_argument('--out', default='out/reference.npz')
    s.add_argument('--peak', type=int, default=1200)
    s = sub.add_parser('analyze')
    s.add_argument('capture')
    s.add_argument('--fs', type=float, default=FS)
    s.add_argument('--out', default='out/analysis')
    s = sub.add_parser('capture-legacy')
    s.add_argument('--host', required=True)
    s.add_argument('--frames', type=int, default=10)
    s.add_argument('--out', default='out/capture.npz')
    a = p.parse_args()
    if a.command == 'simulate':
        if a.frames < 1:
            p.error('--frames must be positive')
        save_report([simulate(seed=7+i, shared_path=a.shared_path, cfo=42000+2000*i,
                              delay=(793+37*i)%4096) for i in range(a.frames)], a.out,
                    'SIMULATED: '+('common interference path' if a.shared_path else 'distinct interference path'), FS)
    elif a.command == 'reference':
        path = Path(a.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        wave, symbols = reference()
        np.savez(path, wave=wave, symbols=symbols, dac_words=dac_words(wave, a.peak), fs=FS)
        print(path)
    elif a.command == 'analyze':
        with np.load(a.capture, allow_pickle=False) as data:
            x = data['samples']
        if x.ndim == 2:
            x = x[None]
        save_report(x, a.out, 'HARDWARE CAPTURE (provenance supplied separately)', a.fs)
    else:
        from .transport import capture
        path = Path(a.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(path, samples=capture(a.host, a.frames), fs=FS)
        print(f'{path}: RF OFF IS UNVERIFIED; check board GPIO/state via SSH.')


if __name__ == '__main__':
    main()
