"""Launch the original RFSoC4x2 app and a new native VSA using private settings.

The launcher owns the request-driven board helper's stdin. Closing the app,
STOP file, expiry or loss of its owner shuts capture down and clears both DACs.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.legacy_reference import build, SOURCE_SHA
from tools.run_demo import executable, EXPECTED

SETUP_SHAS = {'62d4c02859b90d4fa8b9efe56425b63143dfc7e6bbd9de64491da47d8b14c8d8',
              '81acc6b652bc2303701888f8ea3af598c0c3be5fa3e05acb48473930a7c6602e'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def preflight_code(port):
    # Match actual Python executables, not the stopped sudo parent left by an
    # earlier run or the source text of this diagnostic command itself.
    return '\n'.join([
        'import hashlib,json,pathlib,platform,subprocess,shlex',
        'expected='+repr({**EXPECTED, '/boot/data.mat': SOURCE_SHA}),
        "board=pathlib.Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(bytes([0])).decode()",
        "rows=subprocess.check_output(['ps','-eo','pid=,ppid=,stat=,args='],text=True).splitlines()",
        'busy=[]',
        'for row in rows:',
        ' p=row.split(None,3)',
        " if len(p)<4 or 'Z' in p[2]: continue",
        ' try: a=shlex.split(p[3])',
        ' except ValueError: continue',
        ' if not a: continue',
        " exe=pathlib.Path(a[0]).name",
        " if not exe.startswith('python'): continue",
        " files=[pathlib.Path(t).name for t in a[1:3]]",
        " if any(t in files for t in ['board_capture.py','legacy_capture.py','boot.py','ipykernel_launcher']): busy.append(row)",
        "service=subprocess.run(['systemctl','is-active','bootpy.service'],capture_output=True,text=True).stdout.strip()",
        "ports=subprocess.run(['ss','-ltn'],capture_output=True,text=True).stdout.splitlines()",
        'listening=any(any(p.split()[3].endswith(":"+str(n)) for n in [4010,'+str(port)+']) for p in ports[1:] if len(p.split())>=4)',
        "print(json.dumps(dict(board=board,machine=platform.machine(),busy=busy,service=service,listening=listening,hashes={p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in expected})))",
    ])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', required=True)
    p.add_argument('--mode', choices=['validate', 'durable'], default='validate')
    p.add_argument('--schedule', default='wave:6,blank:3,pause:5,wave:6')
    p.add_argument('--max-seconds', type=int, default=1800)
    p.add_argument('--max-frames', type=int, default=10000)
    p.add_argument('--i-own-board', action='store_true')
    p.add_argument('--out', default='out')
    p.add_argument('--receive', choices=['window4', 'adc-d'], default='window4',
                   help='window4: all four ADC streams as one boundary-free 32768-row window of the same '
                        'capture (common-feed diagnostic DOA/pattern through the array model); '
                        'adc-d: ADC_D only, full capture (direct mode, no DOA/pattern)')
    p.add_argument('--save-windows', action='store_true',
                   help='keep every received wire frame (private run folder, windows/) for offline replay')
    p.add_argument('--save-captures', action='store_true',
                   help='validate mode: the helper keeps every full-RAM capture in its private stage folder')
    a = p.parse_args()
    if a.save_captures and a.mode != 'validate':
        p.error('--save-captures needs --mode validate (bounded schedule)')
    if not a.i_own_board:
        p.error('--i-own-board is required for exclusive live access')
    if not 0 < a.max_seconds <= 14400 or not 1 <= a.max_frames <= 200000:
        p.error('duration/frame bounds out of range')
    cfg = json.loads(Path(a.config).read_text(encoding='utf-8-sig'))
    host, user = cfg['host'], cfg.get('user', 'xilinx')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', host) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', user):
        raise ValueError('Use a plain endpoint and account name')
    port = int(cfg.get('legacy_stream_port', 4011))
    vsa_port = int(cfg.get('vsa_startup_port', 60685))
    if not 1024 <= port <= 65535 or not 1024 <= vsa_port <= 65535:
        raise ValueError('Invalid stream/VSA startup port')
    password_file = Path(cfg['password_file']).expanduser().resolve()
    if not cfg.get('host_key') or not password_file.is_file():
        raise ValueError('Pinned host key and private password file required')
    original = Path(cfg['original_repo']).resolve()
    setup = original/'Settings/ofdm_iq_100_16_4x2.setx'
    if sha(setup) not in SETUP_SHAS:
        raise ValueError('SETX is not the matched legacy FFT64 profile')
    dll = Path(cfg['vsa_dll_path']).resolve()
    if not dll.is_file():
        raise ValueError('VSA interfaces DLL missing')
    matlab = cfg.get('matlab_executable')
    if not matlab or not Path(matlab).is_file():
        raise ValueError('Set matlab_executable in private config')
    with socket.socket() as check:
        check.settimeout(.2)
        if check.connect_ex(('127.0.0.1', vsa_port)) == 0:
            raise RuntimeError('VSA startup port already occupied; choose a free port')
    plink, pscp = executable(cfg, 'plink', 'plink'), executable(cfg, 'pscp', 'pscp')
    common = ['-batch', '-hostkey', cfg['host_key'], '-l', user, '-pwfile', str(password_file)]
    ssh = [plink, '-ssh', '-noagent', *common, host]
    password = password_file.read_bytes().rstrip(b'\r\n')+b'\n'
    run = datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
    out = Path(a.out).resolve()/('original-'+run)
    out.mkdir(parents=True, exist_ok=False)
    if a.save_windows:
        (out/'windows').mkdir()
    stage = '/home/'+user+'/rfsoc-original-'+run

    def remote(command, privileged=False, timeout=60, check=True):
        if privileged:
            command = "sudo -S -p '' "+command
        r = subprocess.run([*ssh, command], input=password if privileged else None,
                           capture_output=True, timeout=timeout)
        if check and r.returncode:
            raise RuntimeError(r.stderr.decode(errors='replace') or 'Board command failed')
        return r

    pre = json.loads(remote('/usr/bin/python3 -c '+shlex.quote(preflight_code(port))).stdout)
    (out/'preflight.json').write_text(json.dumps(pre, indent=2)+'\n')
    if pre['board'] != 'RFSoC4x2' or pre['machine'] != 'aarch64' or pre['hashes'] != {**EXPECTED, '/boot/data.mat': SOURCE_SHA}:
        raise RuntimeError('Board identity or boot assets differ')
    if pre['busy'] or pre['listening'] or pre['service'] in ('active', 'activating', 'reloading'):
        raise RuntimeError('Board already has an owner/service; see private preflight.json')
    reference, reference_mat = build(original/'Signals/dac_ofdm_f_500.mat', out)
    helper = ROOT/'board/legacy_capture.py'
    remote('mkdir -p '+shlex.quote(stage))
    subprocess.run([pscp, *common, str(helper), str(reference), user+'@'+host+':'+stage+'/'], check=True, timeout=120)
    staged = remote('sha256sum '+shlex.quote(stage+'/'+helper.name)+' '+shlex.quote(stage+'/'+reference.name)).stdout.decode()
    if sha(helper) not in staged or sha(reference) not in staged:
        raise RuntimeError('Staged files failed hash verification')
    continuous = a.mode == 'durable'
    seconds = a.max_seconds if continuous else 300
    window4 = a.receive == 'window4'
    app_cfg = dict(originalRepoPath=str(original), visible=True, directOnly=True,
        allowBoardCommands=False, sendInitialTuning=False, vsaSetupFile=str(setup), vsa=1,
        ch=1, dataChan=131072, fc=3e9, fsRfsoc=125e6, staleSeconds=2, frameTimeoutSeconds=.25, outputDir=str(out))
    if window4:
        # Common splitter feed: DOA/pattern are a cable diagnostic through the explicit
        # 4-element ULA model (d = lambda/2 at 3 GHz), uncalibrated; never an arrival angle.
        app_cfg.update(directOnly=False, ch=5, dataChan=32768, fcAnt=3e9, cutterAllowed=False,
                       arrayLabel='common-feed diagnostic / array model (ULA d=lambda/2 @3 GHz)')
    settings = dict(app=app_cfg,
        backend=dict(host=host, port=port, referenceMat=str(reference_mat), orientation='IplusjQ',
        dllPath=str(dll), setupPath=str(setup), setupSha256=sha(setup), vsaPort=vsa_port,
        visible=True, allowContinuous=continuous, staleSeconds=2, expectSource='rfsoc4x2-hardware',
        logFile=str(out/'vsa_frames.jsonl'), rawDir=str(out/'windows') if a.save_windows else '',
        frameLogFile=str(out/'frames.jsonl'),
        wireMode='window4' if window4 else 'adc-d-fullram'),
        session=dict(maxSeconds=seconds, stopFile=str(out/'STOP'), reportFile=str(out/'result.json')))
    settings_path = out/'frontend.json'
    settings_path.write_text(json.dumps(settings, indent=2)+'\n')
    literal = lambda value: "'"+str(value).replace("'", "''")+"'"
    entry = out/'start.m'
    entry.write_text('addpath('+literal(ROOT/'matlab/original')+');\nrunOriginalVsa('+literal(settings_path)+');\n')
    bounds = ['--continuous', '--max-seconds', str(seconds), '--max-frames', str(a.max_frames)] if continuous else ['--schedule', a.schedule]
    args = [cfg.get('board_python', '/usr/local/share/pynq-venv/bin/python3'), stage+'/'+helper.name,
            '--exclusive-control', '--owner-stdin', '--reference', stage+'/'+reference.name,
            '--out', stage+'/manifest.json', *bounds, '--stream-bind', host, '--stream-port', str(port),
            '--request-timeout', '120', '--dac', '0', '--rf-mhz', '3000', '--sampling-freq-unit', 'GHz',
            '--wire-mode', 'window4' if window4 else 'adc-d-fullram', *(['--save-all-captures'] if a.save_captures else [])]
    command = "sudo -S -p '' env BOARD=RFSoC4x2 XILINX_XRT=/usr "+shlex.join(args)
    server = subprocess.Popen([*ssh, command], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    server.stdin.write(password); server.stdin.flush()
    ready = threading.Event()

    def log_server():
        with (out/'board.log').open('wb') as log:
            for line in iter(server.stdout.readline, b''):
                log.write(line); log.flush()
                if b'Waiting for legacy client' in line:
                    ready.set()
    reader = threading.Thread(target=log_server, daemon=True); reader.start()
    try:
        deadline = time.monotonic()+150
        while not ready.wait(.25):
            if server.poll() is not None or time.monotonic()>deadline:
                raise RuntimeError('Helper did not become ready; inspect board.log')
        subprocess.run([matlab, '-wait', '-batch', 'run('+literal(entry)+')', '-logfile', str(out/'matlab.log')],
                       check=True, timeout=seconds+600)
    finally:
        server.stdin.close()
        try:
            server.wait(timeout=90)
        except subprocess.TimeoutExpired:
            remote('pkill -TERM -f '+shlex.quote(stage+'/'+helper.name), privileged=True, check=False)
            server.wait(timeout=30)
        reader.join(timeout=5)
        subprocess.run([pscp, *common, user+'@'+host+':'+stage+'/manifest.json', str(out/'manifest.json')],
                       capture_output=True, timeout=120, check=True)
        manifest = json.loads((out/'manifest.json').read_text())
        if manifest.get('shutdown_errors') or not manifest.get('dac_off_commanded') or len(manifest.get('dac_ram_zero_writes', [])) != 2:
            raise RuntimeError('DAC shutdown not confirmed; inspect private manifest')
        if server.returncode:
            raise RuntimeError('Helper failed; inspect board.log and manifest')
        print('Private run data: '+str(out), flush=True)


if __name__ == '__main__':
    main()
