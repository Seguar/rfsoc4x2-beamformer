"""Hardware-free tests of the board session service (fake helper, fake preflight)."""
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('session_service', ROOT/'board/session_service.py')
svc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(svc)
sys.path.insert(0, str(ROOT))
from tools.run_demo import EXPECTED
from tools.legacy_reference import SOURCE_SHA


def good(**changes):
    pre = dict(board='RFSoC4x2', machine='aarch64', busy=[], bootpy='failed', ports_taken=[], hashes=dict(svc.EXPECTED))
    pre.update(changes)
    return pre


class PolicyTests(unittest.TestCase):
    def test_expected_assets_match_the_launcher(self):
        self.assertEqual(svc.EXPECTED, {**EXPECTED, '/boot/data.mat': SOURCE_SHA})

    def test_peers(self):
        attached = [ipaddress.ip_network('198.51.100.64/26')]
        for peer in ['127.0.0.1', '192.168.3.100', '192.168.2.1', '10.1.2.3', '100.100.1.1', '198.51.100.70']:
            self.assertTrue(svc.peer_allowed(peer, attached), peer)
        for peer in ['198.51.100.1', '8.8.8.8', 'not-an-address']:
            self.assertFalse(svc.peer_allowed(peer, attached), peer)
        self.assertTrue(svc.peer_allowed('8.8.8.8', attached, [ipaddress.ip_network('8.8.8.0/24')]))

    def test_busy_rows(self):
        rows = ['11648 1 T sudo -S /venv/python3 /old/board_capture.py',
                '11649 11648 Z [python3] <defunct>',
                '17 1 Sl /venv/python3 /new/legacy_capture.py',
                '18 1 Sl /venv/python3 -m ipykernel_launcher -f kernel.json',
                '20 1 S python3 -c "print(\'board_capture.py\')"']
        self.assertEqual([r.split()[0] for r in svc.busy_owners(rows)], ['17', '18'])

    def test_preflight_rules(self):
        self.assertFalse(svc.check_preflight(good()))
        self.assertTrue(svc.check_preflight(good(bootpy='activating', busy=['9 1 S python3 /boot/boot.py'])))
        for changes, code in [(dict(board='ZCU216'), 'wrong_board'),
                              (dict(hashes={**svc.EXPECTED, '/boot/doa_mts.bit': 'x'}), 'boot_assets'),
                              (dict(busy=['18 1 S python3 -m ipykernel_launcher']), 'board_busy'),
                              (dict(busy=['9 1 S python3 /boot/boot.py']), 'board_busy'),
                              (dict(ports_taken=[4011]), 'board_busy')]:
            with self.subTest(code=code, changes=list(changes)), self.assertRaises(svc.Refused) as caught:
                svc.check_preflight(good(**changes))
            self.assertEqual(caught.exception.code, code)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.calls = []
        self.pre = good()
        a = svc.parser().parse_args(['--root', str(ROOT/'tests'), '--state', self.tmp.name, '--bind', '127.0.0.1',
                                     '--port', '0', '--helper', 'fake_session_helper.py', '--board-name', 'RFSoC4x2',
                                     '--start-timeout', '10'])
        def systemctl(*args):
            self.calls.append(args)
        self.service = svc.Service(a, preflight_fn=lambda ports: self.pre, networks_fn=lambda: [],
                                   systemctl=systemctl).start()
        os.environ.pop('FAKE_HELPER_MODE', None)

    def tearDown(self):
        self.service.close(wait=20)
        self.tmp.cleanup()

    def connect(self):
        c = socket.create_connection(('127.0.0.1', self.service.port), timeout=5)
        c.settimeout(15)
        return c, c.makefile('rb')

    def start(self, **request):
        c, f = self.connect()
        c.sendall(json.dumps({'op': 'start', **request}).encode()+b'\n')
        return c, f

    def until(self, f, *states):
        while True:
            line = f.readline()
            self.assertTrue(line, 'service closed the connection')
            m = json.loads(line)
            if m.get('state') in states:
                return m

    def manifest(self):
        runs = sorted((Path(self.tmp.name)/'runs').iterdir())
        return json.loads((runs[-1]/'manifest.json').read_text())

    def test_identify_tcp_and_udp(self):
        c, f = self.connect()
        c.sendall(b'{"op":"identify"}\n')
        m = json.loads(f.readline())
        self.assertEqual((m['service'], m['protocol'], m['board'], m['busy']), ('rfsoc4x2-beamformer', 1, 'RFSoC4x2', False))
        c.close()
        u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        u.settimeout(5)
        u.sendto(b'rfsoc4x2-beamformer?', ('127.0.0.1', self.service.port))
        self.assertEqual(json.loads(u.recvfrom(1024)[0])['service'], 'rfsoc4x2-beamformer')
        u.close()

    def test_session_stop_and_owner_binding(self):
        c, f = self.start(max_seconds=600)
        ready = self.until(f, 'ready', 'error')
        self.assertEqual((ready['state'], ready['host'], ready['stream_port'], ready['control_port']),
                         ('ready', '127.0.0.1', 4011, 4012))
        # default start profile: 5.2 GHz, ADC odd / DAC second Nyquist zone, reported to the client
        self.assertEqual((ready['rf_mhz'], ready['adc_nyquist_zone'], ready['dac_nyquist_zone']), (5200, 1, 2))
        # a second client is refused while the session runs
        c2, f2 = self.start()
        self.assertEqual(self.until(f2, 'error')['code'], 'board_busy')
        c2.close()
        c.sendall(b'{"op":"stop"}\n')
        ended = self.until(f, 'ended', 'error')
        self.assertEqual((ended['state'], ended['reason'], ended['dac_off_commanded'], ended['shutdown_errors'], ended['frames']),
                         ('ended', 'client_stop', True, [], 7))
        argv = self.manifest()['argv']
        for want in ['--owner-stdin', '--exclusive-control', '--continuous', '--wire-mode', 'window4', '--max-seconds', '600']:
            self.assertIn(want, argv)
        self.assertEqual(argv[argv.index('--stream-bind')+1], '127.0.0.1')
        self.assertEqual(argv[argv.index('--rf-mhz')+1], '5200')
        self.assertEqual(self.calls, [])          # bootpy was not running: untouched
        c.close()

    def test_lost_client_shuts_the_helper_down(self):
        c, f = self.start()
        self.until(f, 'ready')
        f.close()
        c.close()                                   # application died
        deadline = time.monotonic()+15
        while self.service.session.locked() and time.monotonic() < deadline:
            time.sleep(.05)
        self.assertFalse(self.service.session.locked())
        self.assertTrue(self.manifest()['dac_off_commanded'])
        run = sorted((Path(self.tmp.name)/'runs').iterdir())[-1]
        self.assertEqual(json.loads((run/'session.json').read_text())['reason'], 'client_gone')

    def test_bootpy_is_stopped_and_restored(self):
        self.pre = good(bootpy='activating', busy=['9 1 S python3 /boot/boot.py'])
        c, f = self.start()
        self.until(f, 'ready')
        c.sendall(b'{"op":"stop"}\n')
        self.assertTrue(self.until(f, 'ended')['bootpy_restored'])
        self.assertEqual(self.calls, [('stop', 'bootpy.service'), ('start', '--no-block', 'bootpy.service')])
        c.close()

    def test_requested_rf_profile(self):
        c, f = self.start(max_seconds=60, rf_mhz=3000)
        ready = self.until(f, 'ready', 'error')
        self.assertEqual((ready['rf_mhz'], ready['adc_nyquist_zone'], ready['dac_nyquist_zone']), (3000, 2, 1))
        c.sendall(b'{"op":"stop"}\n')
        self.until(f, 'ended', 'error')
        argv = self.manifest()['argv']
        self.assertEqual(argv[argv.index('--rf-mhz')+1], '3000')
        c.close()

    def test_ready_reports_the_zone_the_helper_set(self):
        os.environ['FAKE_DAC_ZONE'] = '1'          # 5.2 GHz session where zone 1 measured stronger
        try:
            c, f = self.start(max_seconds=60)
            ready = self.until(f, 'ready', 'error')
        finally:
            os.environ.pop('FAKE_DAC_ZONE')
        self.assertEqual((ready['rf_mhz'], ready['adc_nyquist_zone'], ready['dac_nyquist_zone']), (5200, 1, 1))
        c.sendall(b'{"op":"stop"}\n')
        self.until(f, 'ended', 'error')
        c.close()

    def test_rf_tables_agree(self):
        import importlib.util
        src = (ROOT/'board/legacy_capture.py').read_text()
        # parse the helper table without importing the hardware helper
        ns = {}
        exec(src[src.index('RF_PROFILES = '):src.index('\n', src.index('DEFAULT_RF_MHZ = '))], ns)
        self.assertEqual(ns['RF_PROFILES'], svc.RF_PROFILES)
        self.assertEqual(ns['DEFAULT_RF_MHZ'], svc.DEFAULT_RF_MHZ)
        launcher = (ROOT/'tools/run_original_vsa.py').read_text()
        ns2 = {}
        exec(launcher[launcher.index('RF_ZONES = '):launcher.index('\n', launcher.index('RF_ZONES = '))], ns2)
        self.assertEqual(ns2['RF_ZONES'], {k: (v['adc_zone'], v['dac_zone']) for k, v in svc.RF_PROFILES.items()})

    def test_refusals(self):
        self.pre = good(busy=['18 1 S python3 -m ipykernel_launcher'])
        c, f = self.start()
        m = self.until(f, 'error')
        self.assertEqual(m['code'], 'board_busy')
        self.assertIn('Jupyter', m['message'])
        c.close()
        self.pre = good()
        for request in [{'max_seconds': 0}, {'max_seconds': 14401}, {'max_seconds': 'x'},
                        {'rf_mhz': 5700}, {'rf_mhz': '5200'}, {'rf_mhz': True}]:
            c, f = self.start(**request)
            self.assertEqual(self.until(f, 'error')['code'], 'bad_request')
            c.close()
        c, f = self.connect()
        c.sendall(b'{"op":"format"}\n')
        self.assertEqual(json.loads(f.readline())['code'], 'bad_request')
        c.close()
        self.assertFalse((Path(self.tmp.name)/'runs').exists() and any((Path(self.tmp.name)/'runs').iterdir()))

    def test_helper_failure_is_reported(self):
        os.environ['FAKE_HELPER_MODE'] = 'fail'
        try:
            c, f = self.start()
            m = self.until(f, 'error', 'ended', 'ready')
        finally:
            os.environ.pop('FAKE_HELPER_MODE')
        self.assertEqual((m['state'], m['code']), ('error', 'helper_failed'))
        self.assertIn('overlay did not load', m['message'])
        c.close()

    def test_service_stop_ends_the_session(self):
        c, f = self.start()
        self.until(f, 'ready')
        self.service.close(wait=20)
        self.assertEqual(self.until(f, 'ended')['reason'], 'service_stopped')
        self.assertTrue(self.manifest()['dac_off_commanded'])
        c.close()


if __name__ == '__main__':
    unittest.main()
