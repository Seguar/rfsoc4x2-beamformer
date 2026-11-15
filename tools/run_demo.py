#!/usr/bin/env python3
"""Launch the direct capture-stream-0 demo using PuTTY and private board config.

Stages new files, verifies known boot assets, starts one exclusive capture session
and opens the live display (or finite headless check). Never replaces /boot.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
import uuid
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from rfsoc_demo.dsp import reference, dac_words, FS, WAVEFORM_VERSION

EXPECTED = {
    '/boot/doa_mts.py': '0b4991115401c759296254caea0d0f41ffdfd3edc9b7759df071186d3f01bdf4',
    '/boot/doa_mts.bit': '78e11ab2872fc3ac6252f3ec800f10d6dacd46f910e5df87446cffffee6d52d0',
    '/boot/doa_mts.hwh': '3e0c46dc4a911a0026cfc0cd22a22897acebc561816620f094a2ac5f8b2de471',
}


def executable(config, key, default):
    value = config.get(key) or shutil.which(default)
    if not value:
        candidate = Path('C:/Program Files/PuTTY')/(default+'.exe')
        value = str(candidate) if candidate.is_file() else None
    if not value:
        raise RuntimeError(f'Install PuTTY or set {key} in private config')
    return value


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', required=True, help='Private JSON; see examples/board.example.json')
    p.add_argument('--headless', action='store_true')
    p.add_argument('--frames', type=int, default=100)
    p.add_argument('--out', default='out')
    p.add_argument('--dac-port',choices=['A','B'],help='Printed output connector; default private config or B')
    a = p.parse_args()
    if a.frames < 1:
        p.error('--frames must be positive')
    config = json.loads(Path(a.config).read_text(encoding='utf-8-sig'))
    host, user = config['host'], config.get('user','xilinx')
    dac_port = a.dac_port or config.get('dac_port','B')
    if dac_port not in ('A','B'):
        raise ValueError('dac_port must be A or B')
    logical_dac = {'A':'1','B':'0'}[dac_port]
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*',host) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*',user):
        raise ValueError('Use a plain hostname/IPv4 and account name')
    pwfile = Path(config['password_file']).expanduser().resolve()
    if not pwfile.is_file() or not config.get('host_key'):
        raise ValueError('Private password file and pinned SSH host_key are required')
    plink, pscp = executable(config,'plink','plink'), executable(config,'pscp','pscp')
    common = ['-batch','-hostkey',config['host_key'],'-l',user,'-pwfile',str(pwfile)]
    ssh = [plink,'-ssh',*common,host]
    password_input = pwfile.read_bytes().rstrip(b'\r\n')+b'\n'
    run_id = datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
    out = Path(a.out).resolve()/('live-'+run_id)
    out.mkdir(parents=True)
    stage = '/home/'+user+'/rfsoc-demo-'+run_id
    board_python = config.get('board_python','/usr/local/share/pynq-venv/bin/python3')

    def remote(command, privileged=False, check=True):
        if privileged:
            command = "sudo -S -p '' "+command
        result = subprocess.run([*ssh,command],input=password_input if privileged else None,
                                stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
        if check and result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace').strip() or 'Board command failed')
        return result

    preflight = '\n'.join([
        'import hashlib,json,pathlib,platform,subprocess',
        "board=pathlib.Path('/proc/device-tree/chosen/pynq_board').read_bytes().strip(bytes([0])).decode()",
        'paths='+repr(list(EXPECTED)),
        "r=subprocess.run(['pgrep','-f','[i]pykernel_launcher'],capture_output=True)",
        "print(json.dumps({'board':board,'machine':platform.machine(),'kernels':r.stdout.decode().strip(),'hashes':{p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in paths}}))",
    ])
    print('Checking board identity and matched hardware...',flush=True)
    identity = json.loads(remote('/usr/bin/python3 -c '+shlex.quote(preflight)).stdout)
    (out/'preflight.json').write_text(json.dumps(identity,indent=2)+'\n')
    if identity['board'] != 'RFSoC4x2' or identity['machine'] != 'aarch64' or identity['hashes'] != EXPECTED:
        raise RuntimeError('Board identity or matched boot assets differ; see private preflight.json')
    if identity['kernels']:
        raise RuntimeError('Notebook kernels are running; release them before the exclusive demo')
    remote('systemctl stop bootpy.service',privileged=True)
    remote('mkdir -p '+shlex.quote(stage))
    wave, symbols = reference()
    ref = out/'reference.npz'
    np.savez(ref,wave=wave,symbols=symbols,dac_words=dac_words(wave),fs=FS,
             dac_complex_fs=500e6,waveform_version=WAVEFORM_VERSION)
    helper = ROOT/'tools/board_capture.py'
    subprocess.run([pscp,*common,str(helper),str(ref),user+'@'+host+':'+stage+'/'],check=True,timeout=60)
    hashes = remote('sha256sum '+shlex.quote(stage+'/board_capture.py')+' '+shlex.quote(stage+'/reference.npz')).stdout.decode()
    (out/'staged-hashes.txt').write_text(hashes)
    for path in (helper,ref):
        if hashlib.sha256(path.read_bytes()).hexdigest() not in hashes:
            raise RuntimeError('Staged file hash mismatch')
    port = 4010
    command = "sudo -S -p '' env BOARD=RFSoC4x2 XILINX_XRT=/usr "+shlex.quote(board_python)+' '+shlex.quote(stage+'/board_capture.py')
    command += ' --exclusive-control --reference '+shlex.quote(stage+'/reference.npz')+' --out '+shlex.quote(stage+'/last.npz')
    command += ' --dac '+logical_dac+' --rf-mhz 3000 --sampling-freq-unit GHz --stream-bind '+shlex.quote(host)+' --stream-port '+str(port)+' --frames 0'
    ready = threading.Event()
    server = subprocess.Popen([*ssh,command],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    server.stdin.write(password_input)
    server.stdin.close()

    def reader():
        with (out/'board.log').open('wb') as log:
            for line in iter(server.stdout.readline,b''):
                log.write(line);log.flush()
                if b'Waiting for demo client' in line:
                    ready.set()
    thread = threading.Thread(target=reader,daemon=True)
    thread.start()
    print(f'Starting direct DAC_{dac_port} -> 20 dB -> ADC stream 0 session...',flush=True)
    try:
        deadline = time.monotonic()+120
        while not ready.wait(.25):
            if server.poll() is not None or time.monotonic()>deadline:
                raise RuntimeError('Board capture did not become ready; see '+str(out/'board.log'))
        client = [sys.executable,'-m','rfsoc_demo.live','--host',host,'--port',str(port),
                  '--adc0-only','--log',str(out/'live.jsonl')]
        if a.headless:
            client += ['--headless','--frames',str(a.frames)]
        subprocess.run(client,cwd=ROOT,check=True)
    finally:
        if server.poll() is None:
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                remote('pkill -TERM -f '+shlex.quote(stage+'/board_capture.py'),privileged=True,check=False)
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.terminate()
        thread.join(timeout=3)
        for suffix in ('json','npz'):
            subprocess.run([pscp,*common,user+'@'+host+':'+stage+'/last.'+suffix,str(out/('last.'+suffix))],
                           stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
        print(f'Private run data: {out}. Boot service remains stopped; inspect last.json for shutdown status.')


if __name__ == '__main__':
    main()
