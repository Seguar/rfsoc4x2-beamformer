"""Put a new RFSoCBeamformer release on the board's PYNQ-USB drive (part of every release).

Copies the R2026a RFSoCBeamformer.exe and its README.txt into the RFSoCBeamformer folder
of /usr/local/share/fatfs (built by build_usb.py), checks the SHA256 on the board, and
writes VERSION.txt. Only the medium is detached for a few seconds (configfs lun file);
the USB network and a running session stay up. The MATLAB Runtime installer is not
touched (rebuild with build_usb.py only when the runtime release changes).

  python3 tools/usb_drive/update_app.py --ssh <board> --password-file <file> \
      --folder RFSoCBeamformer-v0.7.4-win64-r2026a --version v0.7.4
"""
import argparse, hashlib, shlex, subprocess, sys
from pathlib import Path

LUN = '/sys/kernel/config/usb_gadget/g/functions/mass_storage.ms0/lun.0/file'
IMAGE = '/usr/local/share/fatfs'


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--ssh', required=True, help='OpenSSH destination of the board (key login)')
    p.add_argument('--password-file', required=True, help='private file with the sudo password')
    p.add_argument('--folder', required=True, help='unpacked R2026a release folder (RFSoCBeamformer.exe, README.txt)')
    p.add_argument('--version', required=True)
    a = p.parse_args()
    folder = Path(a.folder)
    exe, readme = folder / 'RFSoCBeamformer.exe', folder / 'README.txt'
    sha = hashlib.sha256(exe.read_bytes()).hexdigest()
    stage = '/tmp/usbapp'
    subprocess.run(['ssh', a.ssh, 'rm -rf %s && mkdir -m 700 %s' % (stage, stage)], check=True)
    subprocess.run(['scp', '-q', str(exe), str(readme), '%s:%s/' % (a.ssh, stage)], check=True)
    note = '%s  RFSoCBeamformer.exe (R2026a) sha256 %s\r\n' % (a.version, sha)
    script = f"""set -e
printf %s {shlex.quote(note)} > {stage}/VERSION.txt
echo > {LUN}
mkdir -p /mnt/pynqusb-app
mount -o loop {IMAGE} /mnt/pynqusb-app
trap 'umount /mnt/pynqusb-app 2>/dev/null; echo {IMAGE} > {LUN}' EXIT
cp {stage}/RFSoCBeamformer.exe {stage}/README.txt {stage}/VERSION.txt /mnt/pynqusb-app/RFSoCBeamformer/
sync
sha256sum /mnt/pynqusb-app/RFSoCBeamformer/RFSoCBeamformer.exe
"""
    pw = Path(a.password_file).read_text().strip()
    r = subprocess.run(['ssh', a.ssh, "sudo -S -p '' sh -c %s; cat %s; rm -rf %s" % (shlex.quote(script), LUN, stage)],
                       input=pw + '\n', capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode or sha not in r.stdout or IMAGE not in r.stdout.splitlines()[-1]:
        print(r.stderr.strip(), file=sys.stderr)
        sys.exit('USB drive update failed or not verified')
    print('PYNQ-USB drive: %s RFSoCBeamformer.exe %s' % (a.version, sha))


if __name__ == '__main__':
    main()
