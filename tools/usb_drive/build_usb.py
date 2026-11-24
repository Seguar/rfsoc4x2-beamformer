"""Board-side (root): rebuild the board's PYNQ-USB drive with the application.

Fills a new FAT32 image with the old drive's files (serial driver and the Windows/Mac
marker that /usr/local/bin/usbgadget reads at boot), the RFSoCBeamformer app and the
MATLAB Runtime R2026a installer. The installer is unpacked from MathWorks' zip read over
HTTP range requests, so the 5.7 GB zip is never stored (the SD card has room for the
image only; FAT32 cannot hold the zip, whose largest member is 1.67 GB). The board's
own image must stay FAT (the gadget script mounts it at boot; exFAT is not in this kernel).

Stage in /tmp/usbbuild (from a PC with dosfstools):
  empty.img.gz  mkfs.vfat -F 32 -n PYNQ-USB -C empty.img 6963200 ; gzip -1 empty.img
  app/          RFSoCBeamformer.exe (R2026a build), README.txt, start.cmd
  README.txt    drive README
Then: sudo python3 build_usb.py   (about 12 min at ~9 MB/s; the capture runs slower meanwhile)
The PYNQ original stays as /usr/local/share/fatfs.pynq-orig. The medium is swapped by
writing the configfs lun file (empty, then the image); the USB network stays up.
"""
import io, os, json, shutil, subprocess, sys, time, zipfile, http.client, urllib.parse
from pathlib import Path

U = 'https://ssd.mathworks.com/supportfiles/downloads/R2026a/Release/5/deployment_files/installer/complete/win64/MATLAB_Runtime_R2026a_Update_5_win64.zip'
STAGE = Path('/tmp/usbbuild'); NEW = Path('/usr/local/share/fatfs.new'); CUR = Path('/usr/local/share/fatfs')
BACKUP = Path('/usr/local/share/fatfs.pynq-orig'); MNT = Path('/mnt/pynqusb-new'); OLD = Path('/mnt/pynqusb-old')
LUN = Path('/sys/kernel/config/usb_gadget/g/functions/mass_storage.ms0/lun.0')
RT = 'MATLAB_Runtime_R2026a_Update_5_win64'
def log(**k):
    k['t'] = time.strftime('%H:%M:%S'); print(json.dumps(k), flush=True)
def run(*a):
    subprocess.run(a, check=True)

class HttpRange(io.RawIOBase):
    """Seekable read-only view of a URL (one keep-alive HTTPS connection, Range requests)."""
    def __init__(self, url):
        self.u = urllib.parse.urlsplit(url); self.p = 0; self.c = None
        r = self.req('HEAD', {}); r.read(); self.n = int(r.getheader('Content-Length'))
    def req(self, method, headers):
        for attempt in range(5):
            try:
                if self.c is None:
                    self.c = http.client.HTTPSConnection(self.u.netloc, timeout=60)
                self.c.request(method, self.u.path, headers=headers); return self.c.getresponse()
            except Exception as e:
                log(ev='http_retry', error=str(e)); self.c = None; time.sleep(2 + 3 * attempt)
        raise RuntimeError('HTTP failed')
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.p
    def seek(self, o, w=0):
        self.p = {0: o, 1: self.p + o, 2: self.n + o}[w]; return self.p
    def readinto(self, b):
        if self.p >= self.n: return 0
        e = min(self.n, self.p + len(b)) - 1
        for attempt in range(5):
            r = self.req('GET', {'Range': 'bytes=%d-%d' % (self.p, e)})
            d = r.read()
            if r.status == 206 and len(d) == e - self.p + 1: break
            log(ev='range_retry', status=r.status, got=len(d)); self.c = None
        else:
            raise RuntimeError('range read failed')
        b[:len(d)] = d; self.p += len(d); return len(d)

if not NEW.exists():
    run('sh', '-c', 'gunzip -c %s/empty.img.gz | cp --sparse=always /dev/stdin %s' % (STAGE, NEW))
log(ev='image', size=NEW.stat().st_size)
MNT.mkdir(exist_ok=True); OLD.mkdir(exist_ok=True)
run('mount', '-o', 'loop', str(NEW), str(MNT))
try:
    run('mount', '-o', 'loop,ro', str(CUR), str(OLD))
    try:
        for name in ('serial_driver', 'delete-for-mac.txt', 'delete-for-windows.txt'):
            s = OLD / name
            if s.is_dir(): shutil.copytree(s, MNT / name, dirs_exist_ok=True)
            elif s.exists(): shutil.copy2(s, MNT / name)
    finally:
        run('umount', str(OLD))
    shutil.copytree(STAGE / 'app', MNT / 'RFSoCBeamformer', dirs_exist_ok=True)
    shutil.copy2(STAGE / 'README.txt', MNT / 'README.txt')
    z = zipfile.ZipFile(io.BufferedReader(HttpRange(U), buffer_size=32 << 20))
    infos = sorted(z.infolist(), key=lambda i: i.header_offset)
    total = sum(i.file_size for i in infos); done = 0; t0 = time.time(); nextlog = 0
    for i in infos:
        dest = MNT / RT / i.filename
        if i.is_dir():
            dest.mkdir(parents=True, exist_ok=True); continue
        if dest.exists() and dest.stat().st_size == i.file_size:
            done += i.file_size; continue                        # resumed run
        dest.parent.mkdir(parents=True, exist_ok=True)
        with z.open(i) as src, open(dest, 'wb') as out:           # zipfile checks each CRC
            shutil.copyfileobj(src, out, 8 << 20)
        done += i.file_size
        if time.time() > nextlog:
            log(ev='progress', gb=round(done / 1e9, 2), of=round(total / 1e9, 2), mbps=round(done / 1e6 / (time.time() - t0 + 1e-9), 1)); nextlog = time.time() + 60
    log(ev='extracted', files=len(infos), gb=round(total / 1e9, 2), seconds=round(time.time() - t0))
    run('sync')
    st = os.statvfs(MNT); log(ev='free_on_drive_mb', mb=st.f_bavail * st.f_frsize // 2**20)
finally:
    run('umount', str(MNT))
# swap: keep the PYNQ original, eject the medium, point the gadget at the new image (RNDIS stays up)
if not BACKUP.exists():
    shutil.copy2(CUR, BACKUP)
(LUN / 'file').write_text('\n')            # detach the medium (this kernel has no forced_eject)
os.replace(NEW, CUR); os.chmod(CUR, 0o644)
(LUN / 'file').write_text(str(CUR) + '\n')
log(ev='swapped', lun_file=(LUN / 'file').read_text().strip(), backup=str(BACKUP))
log(ev='done')
