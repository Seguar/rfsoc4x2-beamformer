"""Live EVM dashboard. Hardware acquisition runs independently of GUI updates."""
import argparse
from collections import deque
import json
from pathlib import Path
import queue
import socket
import threading
import time
import numpy as np
from .dsp import FS, PERIOD, reference, process, calibrate_fixed, WAVEFORM_VERSION
from .transport import receive_session, receive_frame


def unavailable_display(iq_ax, scatter, bars, cfo_ax, cfo_line, evm_ax, reason):
    """Remove last-good CURRENT values; historical EVM may remain as history."""
    scatter.set_offsets(np.empty((0,2)))
    iq_ax.set_title('EVM unavailable | '+reason)
    for bar in bars:
        bar.set_height(np.nan)
    cfo_line.set_data([],[])
    cfo_ax.set_title('CFO unavailable | '+reason)
    evm_ax.set_title('No current EVM — history only')


def array_fixture(index, jammer=False):
    """SIMULATED half-wave ULA. Four elements null at +/-30 degrees broadside sum."""
    angle = 38*np.sin(index*.065)
    rng = np.random.default_rng(100+index)
    n = np.arange(4*PERIOD)
    steering = np.exp(-1j*np.pi*np.arange(4)*np.sin(np.deg2rad(angle)))
    wave = np.tile(reference()[0], 4)
    x = wave[:, None]*steering
    if jammer:
        other = np.tile(reference(seed=717)[0], 4)*np.exp(2j*np.pi*35000*n/FS)
        a = np.exp(-1j*np.pi*np.arange(4)*np.sin(np.deg2rad(-55)))
        x += 5*other[:, None]*a
    x += .012*(rng.standard_normal(x.shape)+1j*rng.standard_normal(x.shape))/np.sqrt(2)
    return x, angle


class Receiver:
    def __init__(self, host, port):
        self.frames = queue.Queue(maxsize=2)
        self.stop = threading.Event()
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(5)
        self.metadata = receive_session(self.sock)
        self.error = None
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()

    def read(self):
        try:
            while not self.stop.is_set():
                seq, stamp, samples = receive_frame(self.sock)
                item = (seq, stamp, time.monotonic(), samples)
                if self.frames.full():
                    try:
                        self.frames.get_nowait()
                    except queue.Empty:
                        pass
                self.frames.put_nowait(item)
        except (OSError, EOFError, ValueError) as exc:
            if not self.stop.is_set():
                self.error = str(exc)

    def latest(self):
        item = None
        while True:
            try:
                item = self.frames.get_nowait()
            except queue.Empty:
                return item

    def close(self):
        self.stop.set()
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        self.thread.join(timeout=2)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--simulate', action='store_true')
    p.add_argument('--host')
    p.add_argument('--port', type=int, default=4010)
    p.add_argument('--adc0-only', action='store_true', help='Direct capture stream 0; disables other receive channels in DSP')
    p.add_argument('--log', default='out/live.jsonl')
    p.add_argument('--headless', action='store_true', help='Finite processing smoke test without opening a window')
    p.add_argument('--snapshot', help='Render dashboard to PNG with Agg, without opening a window')
    p.add_argument('--frames', type=int, default=30, help='Headless test capture count')
    a = p.parse_args()
    if not a.simulate and not a.host:
        p.error('Choose --simulate or an explicit --host')
    if a.frames < 1:
        p.error('--frames must be positive')
    receiver = None if a.simulate else Receiver(a.host, a.port)
    fs = FS if receiver is None else float(receiver.metadata['fs_hz'])
    waveform_version = WAVEFORM_VERSION if receiver is None else int(receiver.metadata.get('waveform_version',1))
    log_path = Path(a.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    state = {'fixed': None, 'adaptive': False, 'jammer': False, 'index': 0,
             'calibrate': False, 'received': time.monotonic(), 'calibrated': None}
    if a.simulate:
        state['fixed'] = calibrate_fixed(array_fixture(0)[0], adc0_only=a.adc0_only)
        state['calibrated'] = 'simulated broadside'
    start = time.monotonic()
    history = deque(maxlen=300)

    def next_result():
        if receiver is None:
            x, angle = array_fixture(state['index'], state['jammer'])
            seq, received = state['index'], time.monotonic()
            state['index'] += 1
        else:
            item = receiver.latest()
            if item is None:
                return None
            seq, _, received, x = item
            angle = None  # Physical angle requires geometry/calibration; never inferred here.
        state['received'] = received
        try:
            if state['calibrate']:
                state['fixed'] = calibrate_fixed(x, fs, a.adc0_only, waveform_version)
                state['calibrated'] = f'capture {seq}'
                state['calibrate'] = False
            report, constellation = process(x, fs, state['fixed'], a.adc0_only, waveform_version)
            report.update(sequence=seq, elapsed_s=time.monotonic()-start,
                          host_age_ms=1000*(time.monotonic()-received), status='locked',
                          source='SIMULATION' if a.simulate else 'LIVE ADC',
                          active='adc0' if a.adc0_only else ('mvdr' if state['adaptive'] else 'fixed'),
                          fixed_calibration=state['calibrated'])
            if angle is not None:
                report['simulated_angle_deg'] = angle
            return report, constellation
        except ValueError as exc:
            rms = np.sqrt(np.mean(abs(x)**2,axis=0))
            return {'sequence': seq, 'elapsed_s': time.monotonic()-start,
                    'input_rms_dbfs': [float(20*np.log10(v/32768)) if v>0 else None for v in rms],
                    'status': 'unlocked', 'reason': str(exc)}, None

    with log_path.open('a', buffering=1) as log:
        if a.headless:
            try:
                count, deadline = 0, time.monotonic()+max(15, a.frames*3)
                while count < a.frames:
                    result = next_result()
                    if result is None:
                        if receiver.error or time.monotonic() > deadline:
                            raise RuntimeError(receiver.error or 'Frame deadline expired')
                        receiver.stop.wait(.02)
                        continue
                    log.write(json.dumps(result[0], allow_nan=False)+'\n')
                    count += 1
            finally:
                if receiver:
                    receiver.close()
            print(log_path)
            return

        if a.snapshot:
            import matplotlib
            matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        from matplotlib.animation import FuncAnimation
        from matplotlib.widgets import Button
        fig, axes = plt.subplots(2, 2, figsize=(12, 7))
        fig.subplots_adjust(bottom=.18, top=.86, hspace=.45, wspace=.45)
        source = 'SIMULATION — half-wave array' if a.simulate else 'LIVE ADC — geometry not inferred'
        if a.adc0_only:
            source += ' | RX ADC_D (stream 0): no beamforming gain'
        if receiver:
            source += ' | TX '+receiver.metadata.get('dac_connector','DAC connector unverified')
        title = fig.suptitle(source+' | waiting for pilot lock', fontsize=12)
        evm_ax, iq_ax, phase_ax, cfo_ax = axes.ravel()
        lines = {name: evm_ax.plot([], [], label=label)[0] for name, label in
                 [('fixed','Fixed broadside'), ('mvdr','Adaptive MVDR'), ('adc0','ADC0')]}
        evm_ax.set(xlabel='Time (s)', ylabel='Payload RMS EVM (dB)', title='Same capture, separate receive weights')
        evm_percent_axis = evm_ax.secondary_yaxis('right', functions=(
            lambda db: 100*np.power(10., np.asarray(db)/20),
            lambda pct: 20*np.log10(np.maximum(np.asarray(pct),1e-300)/100)))
        evm_percent_axis.set_ylabel('EVM (%)')
        evm_ax.legend()
        scatter = iq_ax.scatter([], [], s=6, alpha=.6)
        iq_ax.set(xlim=(-2,2), ylim=(-2,2), xlabel='I / reference RMS', ylabel='Q / reference RMS')
        bars = phase_ax.bar(np.arange(4), np.zeros(4))
        phase_ax.set(ylim=(-180,180), xticks=np.arange(4), xlabel='ADC channel', ylabel='Relative pilot phase (degrees)')
        cfo_line, = cfo_ax.plot([], [])
        cfo_ax.set(xlabel='Time (s)', ylabel='Pilot CFO (kHz)', title='Reacquired per capture')
        for ax in axes.ravel():
            ax.grid(alpha=.2)
        calibrate = Button(fig.add_axes([.08,.065,.23,.055]), 'Calibrate broadside')
        toggle = Button(fig.add_axes([.37,.065,.23,.055]), 'Beamforming: OFF')
        jammer = Button(fig.add_axes([.66,.065,.25,.055]), 'Simulated jammer: OFF' if a.simulate else 'MXG: external control')
        if a.adc0_only:
            calibrate.label.set_text('Direct ADC_D (RX0)')
            toggle.label.set_text('Single-channel mode')
        fig.text(.08,.015, 'Direct cable: stream 0 EVM and received level shown; no array gain is measured.' if a.adc0_only else
                 'Calibrate with wanted TX at broadside and MXG RF OFF. Fixed weights remain frozen until recalibrated.', fontsize=9)

        def request_calibration(event):
            if not a.adc0_only:
                state['calibrate'] = True
        def toggle_beam(event):
            if a.adc0_only:
                return
            state['adaptive'] = not state['adaptive']
            toggle.label.set_text('Beamforming: '+('ON' if state['adaptive'] else 'OFF'))
        def toggle_jammer(event):
            if a.simulate:
                state['jammer'] = not state['jammer']
                jammer.label.set_text('Simulated jammer: '+('ON' if state['jammer'] else 'OFF'))
        calibrate.on_clicked(request_calibration)
        toggle.on_clicked(toggle_beam)
        jammer.on_clicked(toggle_jammer)

        def update(_):
            result = next_result()
            if result is None:
                age = time.monotonic()-state['received']
                if age > 1:
                    title.set_text(source+f' | STALE {age:.1f}s | '+(receiver.error or 'no new frame'))
                    unavailable_display(iq_ax,scatter,bars,cfo_ax,cfo_line,evm_ax,'STALE DATA')
                return
            report, constellations = result
            log.write(json.dumps(report, allow_nan=False)+'\n')
            if report['status'] != 'locked':
                title.set_text(source+f' | Capture {report["sequence"]} | UNLOCKED: '+report['reason'])
                unavailable_display(iq_ax,scatter,bars,cfo_ax,cfo_line,evm_ax,'NO PILOT LOCK')
                history.append(report)
                return
            history.append(report)
            evm_ax.set_title('Same capture, separate receive weights')
            cfo_ax.set_title('Reacquired per capture')
            for name, line in lines.items():
                rows = list(history)
                line.set_data([r['elapsed_s'] for r in rows],
                              [r.get('metrics',{}).get(name,{}).get('evm_db',np.nan) for r in rows])
            now = report['elapsed_s']
            evm_ax.set_xlim(max(0,now-25),max(5,now))
            evm_ax.relim(); evm_ax.autoscale_view(scalex=False)
            active = report['active']
            if active in constellations:
                z = constellations[active].ravel()
                scale = np.sqrt(np.mean(abs(reference()[1][4:,4:])**2))
                scatter.set_offsets(np.c_[z.real,z.imag]/scale)
                metric = report['metrics'][active]
                timing = metric['payload_timing_shift_samples']
                db_text = f'{metric["evm_db"]:.2f}' if metric['evm_db'] is not None else '-inf'
                iq_ax.set_title(f'{active}: EVM {db_text} dB ({metric["evm_percent"]:.2f}%) | BER {metric["ber"]:.4g}\nPilot timing {min(timing):+.2f}…{max(timing):+.2f} samples')
            else:
                scatter.set_offsets(np.empty((0,2)))
                iq_ax.set_title('Calibrate broadside before fixed-beam comparison')
            for bar, phase in zip(bars, report['tracking']['channel_phase_deg']):
                bar.set_height(phase)
            cfo_line.set_data([r['elapsed_s'] for r in history],
                              [r.get('tracking',{}).get('cfo_hz',np.nan)/1000 for r in history])
            cfo_ax.relim(); cfo_ax.autoscale_view()
            angle = f' | simulated angle {report["simulated_angle_deg"]:+.1f}°' if a.simulate else ''
            improvement = ''
            if 'fixed' in report['metrics']:
                ratio = report['metrics']['fixed']['evm_percent']/max(report['metrics']['mvdr']['evm_percent'], 1e-12)
                improvement = f' | EVM improvement {20*np.log10(max(ratio,1e-12)):+.1f} dB'
            clipped = ' | ADC RAIL HIT' if max(report['input_rail_fraction']) > 0 else ''
            level = report['input_rms_dbfs'][0]
            level_text = f'{level:.1f} dBFS' if level is not None else '-inf dBFS'
            title.set_text(source+'\n'+f'Capture {report["sequence"]} | age {report["host_age_ms"]:.0f} ms | RX0 {level_text}'+angle+improvement+clipped)
        try:
            if a.snapshot:
                for _ in range(15):
                    update(None)
                snapshot = Path(a.snapshot)
                snapshot.parent.mkdir(parents=True, exist_ok=True)
                fig.savefig(snapshot, dpi=130)
                plt.close(fig)
            else:
                animation = FuncAnimation(fig, update, interval=100, cache_frame_data=False)
                plt.show()
        finally:
            if receiver:
                receiver.close()


if __name__ == '__main__':
    main()
