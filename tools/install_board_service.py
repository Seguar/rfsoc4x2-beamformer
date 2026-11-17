#!/usr/bin/env python3
"""Install, check or remove the beamformer session service on the RFSoC4x2.

The service (board/session_service.py) lets RFSoCBeamformer.exe start a hardware
session over plain TCP. Installing is a one-time, persistent change on the board:
files in /opt/rfsoc4x2-beamformer, logs in /var/lib/rfsoc4x2-beamformer and one
systemd unit. /boot is not written and bootpy.service is not changed.

Access is the same private configuration the launcher uses (PuTTY), or an
OpenSSH destination with key login:

  python tools/install_board_service.py --config local/board.json
  python tools/install_board_service.py --ssh <destination> --password-file <sudo password file>
  ... --status      show the unit state and ask the service to identify itself
  ... --uninstall   stop and remove the unit and its files
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.run_demo import executable

NAME = 'rfsoc4x2-beamformer'
DEST = '/opt/' + NAME
STATE = '/var/lib/' + NAME
UNIT = '/etc/systemd/system/' + NAME + '.service'
PORT = 4013
FILES = [ROOT/'board/session_service.py', ROOT/'board/legacy_capture.py', ROOT/'board/control_service.py',
         ROOT/'board/board_commands.py', ROOT/'board/mts_sync.py', ROOT/'tools/legacy_reference.py']
BOARD_PYTHON = '/usr/local/share/pynq-venv/bin/python3'


def unit_text(python, allow):
    extra = ''.join(' --allow-cidr ' + c for c in allow)
    return f"""[Unit]
Description=RFSoC4x2 beamformer session service (starts a capture session for the host application)
After=network.target

[Service]
Type=simple
Environment=BOARD=RFSoC4x2 XILINX_XRT=/usr PYTHONUNBUFFERED=1
WorkingDirectory={STATE}
ExecStart={python} {DEST}/session_service.py --root {DEST} --state {STATE}{extra}
Restart=on-failure
RestartSec=5
KillMode=mixed
TimeoutStopSec=160

[Install]
WantedBy=multi-user.target
"""


def install_script(stage, python, hashes):
    checks = '\n'.join(f'echo "{digest}  {stage}/{name}" | sha256sum -c --quiet -' for name, digest in hashes.items())
    return f"""set -e
[ "$(tr -d '\\0' < /proc/device-tree/chosen/pynq_board)" = "RFSoC4x2" ] || {{ echo "not an RFSoC4x2"; exit 2; }}
{checks}
systemctl stop {NAME}.service 2>/dev/null || true
install -d -o root -g root -m 755 {DEST} {STATE}
for f in session_service.py legacy_capture.py control_service.py board_commands.py mts_sync.py legacy_reference.py; do
  install -o root -g root -m 644 {stage}/$f {DEST}/$f
done
cd {DEST}
{python} -c "from legacy_reference import build; build('/boot/data.mat', '{DEST}')"
install -o root -g root -m 644 {stage}/{NAME}.service {UNIT}
systemctl daemon-reload
systemctl enable --now {NAME}.service
sleep 2
systemctl is-active {NAME}.service
sha256sum {DEST}/legacy_ref.npz
"""


UNINSTALL = f"""systemctl disable --now {NAME}.service 2>/dev/null || true
rm -f {UNIT}
systemctl daemon-reload
rm -rf {DEST} {STATE}
echo removed
"""


class Remote:
    """PuTTY (private launcher configuration) or OpenSSH (key login)."""
    def __init__(self, a):
        if a.ssh:
            if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._@-]*', a.ssh):
                raise ValueError('Use a plain SSH destination')
            self.host = a.ssh
            self.ssh = ['ssh', '-oBatchMode=yes', '-oConnectTimeout=10', a.ssh]
            self.copy = lambda files, target: ['scp', '-q', *files, a.ssh + ':' + target]
            password_file = a.password_file
            self.address = a.address
        else:
            cfg = json.loads(Path(a.config).read_text(encoding='utf-8-sig'))
            host, user = cfg['host'], cfg.get('user', 'xilinx')
            if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', host) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', user):
                raise ValueError('Use a plain endpoint and account name')
            if not cfg.get('host_key'):
                raise ValueError('Pinned host key required')
            common = ['-batch', '-hostkey', cfg['host_key'], '-l', user, '-pwfile', str(Path(cfg['password_file']).expanduser())]
            self.ssh = [executable(cfg, 'plink', 'plink'), '-ssh', '-noagent', *common, host]
            pscp = executable(cfg, 'pscp', 'pscp')
            self.copy = lambda files, target: [pscp, *common, *files, user + '@' + host + ':' + target]
            password_file = a.password_file or cfg['password_file']
            self.address = a.address or host
        if not password_file or not Path(password_file).expanduser().is_file():
            raise ValueError('A private sudo password file is required')
        self.password = Path(password_file).expanduser().read_bytes().rstrip(b'\r\n') + b'\n'

    def run(self, command, privileged=False, timeout=180):
        if privileged:
            command = "sudo -S -p '' " + command
        r = subprocess.run([*self.ssh, command], input=self.password if privileged else None,
                           capture_output=True, timeout=timeout)
        if r.returncode:
            raise RuntimeError((r.stdout + r.stderr).decode(errors='replace').strip() or 'Board command failed')
        return r.stdout.decode(errors='replace')

    def upload(self, files, target):
        subprocess.run(self.copy([str(f) for f in files], target), check=True, timeout=180)


def identify(address, port=PORT, timeout=5):
    with socket.create_connection((address, port), timeout=timeout) as c:
        c.sendall(b'{"op":"identify"}\n')
        return json.loads(c.makefile('rb').readline())


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--config', help='private launcher configuration (PuTTY); see examples/board.example.json')
    p.add_argument('--ssh', help='OpenSSH destination with key login, instead of --config')
    p.add_argument('--password-file', help='private file with the sudo password (default: the one in --config)')
    p.add_argument('--address', help='board address for the final identify check (default: the configured host)')
    p.add_argument('--allow-cidr', action='append', default=[],
                   help='extra client network the service accepts, besides private and directly attached ones')
    p.add_argument('--board-python', default=BOARD_PYTHON)
    p.add_argument('--status', action='store_true')
    p.add_argument('--uninstall', action='store_true')
    a = p.parse_args()
    if bool(a.config) == bool(a.ssh):
        p.error('give exactly one of --config and --ssh')
    for cidr in a.allow_cidr:
        if not re.fullmatch(r'[0-9.]+/[0-9]+', cidr):
            p.error('--allow-cidr takes an IPv4 network such as 198.51.100.0/24')
    remote = Remote(a)
    if a.status:
        print(remote.run(f'systemctl is-enabled {NAME}.service; systemctl is-active {NAME}.service; true').strip())
        if remote.address:
            print(json.dumps(identify(remote.address)))
        return
    stage = '/tmp/' + NAME + '-stage-' + uuid.uuid4().hex[:8]
    remote.run('mkdir -m 700 ' + shlex.quote(stage))
    try:
        if a.uninstall:
            local = [write_temp('uninstall.sh', UNINSTALL)]
            remote.upload(local, stage + '/')
            print(remote.run('sh ' + stage + '/uninstall.sh', privileged=True).strip())
            return
        hashes = {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in FILES}
        unit = write_temp(NAME + '.service', unit_text(a.board_python, a.allow_cidr))
        hashes[unit.name] = hashlib.sha256(unit.read_bytes()).hexdigest()
        script = write_temp('install.sh', install_script(stage, a.board_python, hashes))
        remote.upload([*FILES, unit, script], stage + '/')
        print(remote.run('sh ' + stage + '/install.sh', privileged=True).strip())
    finally:
        remote.run('rm -rf ' + shlex.quote(stage))
    if remote.address:
        reply = identify(remote.address)
        if reply.get('service') != NAME or reply.get('board') != 'RFSoC4x2':
            raise RuntimeError('Service installed but its identify reply is wrong: %r' % reply)
        print('Service answers at %s:%d: %s' % (remote.address, PORT, json.dumps(reply)))
    else:
        print('Installed. Pass --address <board address> to check the service from this machine.')


def write_temp(name, text):
    import tempfile
    path = Path(tempfile.mkdtemp(prefix=NAME + '-')) / name
    path.write_bytes(text.replace('\r\n', '\n').encode())
    return path


if __name__ == '__main__':
    main()
