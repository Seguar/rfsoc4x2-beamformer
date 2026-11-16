"""Hardware-free tests of the separate RFSoC4x2 command socket."""
import importlib.util
import json
from pathlib import Path
import socket
import threading
import unittest

SPEC = importlib.util.spec_from_file_location('control_service', Path(__file__).resolve().parents[1]/'board/control_service.py')
control = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control)


class ParserTests(unittest.TestCase):
    def test_legacy_batch(self):
        self.assertEqual(control.parse_commands(' fc -3000/1/3000/1/3000/1 # phase 0/90/-90/180 #status'),
                         [('fc', [-3000, 1, 3000, 1, 3000, 1]), ('phase', [0, 90, -90, 180]), ('status', [])])
        for cmd in ['dataStream 0', 'dataStream 1', 'da 2', 'dacPow 1/0/0/0',
                    'dataChan 262144', 'dphase 0/0/90/90']:
            self.assertTrue(control.parse_commands(cmd))

    def test_reject_whole_batch_and_bounds(self):
        for cmd in ['status#stream 4', 'cal 4', 'dac0 1/2', 'phase 1/2/3', 'fc 3000/3/3000/1/3000/1',
                    'fc 6001/1/3000/1/3000/1', 'phase 360001/0/0/0', 'dataStream 2', 'dacPow 1/0/2/0',
                    'da -1', 'dataChan 7', 'dataChan 1048584', 'phase nan/0/0/0', 'da 1.0', 'status x',
                    'status#', 'status\nstatus', '#'.join(['status']*17), 'x'*4097, None, True]:
            with self.subTest(command=cmd), self.assertRaises(control.ControlError):
                control.parse_commands(cmd)


class SocketTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.lock = threading.RLock()
        def apply(command):
            self.calls.append(command)
            return {'commands': control.parse_commands(command), 'revision': len(self.calls)}
        self.service = control.ControlService('127.0.0.1', 0, apply, lock=self.lock).start()
        self.client = socket.create_connection(('127.0.0.1', self.service.port), timeout=2)
        self.client.settimeout(2)
        self.reader = self.client.makefile('rb')

    def tearDown(self):
        self.reader.close()
        self.client.close()
        self.service.close()
        self.assertFalse(self.service.alive)

    def read(self):
        return json.loads(self.reader.readline())

    def request(self, obj):
        self.client.sendall(json.dumps(obj).encode()+b'\n')
        return self.read()

    def test_fragmented_and_multiple_lines(self):
        self.client.sendall(b'{"id":1,"com')
        self.client.sendall(b'mand":"phase 0/1/2/3"}\n{"id":2,"command":"status"}\n')
        a, b = self.read(), self.read()
        self.assertTrue(a['ok'] and b['ok'])
        self.assertEqual([a['id'], b['id']], [1, 2])
        self.assertEqual(b['result']['revision'], 2)

    def test_malformed_and_rejected_requests_recover(self):
        for raw in [b'not json\n', b'\xff\n', b'{"id":1,"id":2,"command":"status"}\n',
                    b'{"id":NaN,"command":"status"}\n']:
            self.client.sendall(raw)
            self.assertFalse(self.read()['ok'])
        for obj in [{'id': x, 'command': 'status'} for x in [0, -1, True, 1.5, 2**53]] + [
            {'id': 1, 'command': 'status', 'extra': 0}, {'id': 1, 'command': 'status#stream 4'},
            {'id': 2, 'command': 'dataChan 7'}, {'id': 3}, []]:
            self.assertFalse(self.request(obj)['ok'])
        self.assertEqual(self.calls, [])
        self.assertTrue(self.request({'id': 4, 'command': 'status'})['ok'])
        self.assertEqual(self.calls, ['status'])

    def test_capture_lock_serializes_hardware_access(self):
        self.lock.acquire()
        try:
            self.client.sendall(b'{"id":1,"command":"dataStream 0"}\n')
            self.client.settimeout(.15)
            with self.assertRaises(socket.timeout):
                self.client.recv(1)
            self.assertEqual(self.calls, [])
        finally:
            self.lock.release()
            self.client.settimeout(2)
        self.assertTrue(self.read()['ok'])
        self.assertEqual(self.calls, ['dataStream 0'])

    def test_oversize_line_disconnects_but_listener_recovers(self):
        self.client.sendall(b'x'*(control.MAX_LINE_BYTES+1))
        self.assertEqual(self.read()['error']['code'], 'LineTooLong')
        self.assertEqual(self.reader.readline(), b'')
        with socket.create_connection(('127.0.0.1', self.service.port), timeout=2) as other:
            other.sendall(b'{"id":1,"command":"status"}\n')
            self.assertTrue(json.loads(other.makefile('rb').readline())['ok'])

    def test_callback_error_does_not_stop_control(self):
        self.service.apply = lambda _: (_ for _ in ()).throw(RuntimeError('driver readback failed'))
        r = self.request({'id': 12, 'command': 'status'})
        self.assertFalse(r['ok'])
        self.assertEqual(r['id'], 12)
        self.assertEqual(r['error']['code'], 'ApplyError')
        self.service.apply = lambda _: {'revision': 0}
        self.assertTrue(self.request({'id': 13, 'command': 'status'})['ok'])

    def test_idle_connections_are_bounded(self):
        extras = []
        try:
            # The fixture's persistent client consumes one of four slots.
            for k in range(control.MAX_CLIENTS - 1):
                c = socket.create_connection(('127.0.0.1', self.service.port), timeout=2)
                c.sendall(json.dumps({'id': k+1, 'command': 'status'}).encode()+b'\n')
                r = c.makefile('rb')
                self.assertTrue(json.loads(r.readline())['ok'])
                r.close()
                extras.append(c)
            with socket.create_connection(('127.0.0.1', self.service.port), timeout=2) as c:
                r = c.makefile('rb')
                self.assertEqual(json.loads(r.readline())['error']['code'], 'Busy')
                r.close()
        finally:
            for c in extras:
                c.close()

    def test_close_while_waiting_for_capture_lock(self):
        self.lock.acquire()
        try:
            self.client.sendall(b'{"id":1,"command":"status"}\n')
            self.service.close()
            self.service.close()
            self.assertFalse(self.service.alive)
            self.assertEqual(self.calls, [])
        finally:
            self.lock.release()

    def test_unauthorized_peer(self):
        s = control.ControlService('127.0.0.1', 0, lambda _: {}, peer='192.0.2.1').start()
        try:
            with socket.create_connection(('127.0.0.1', s.port), timeout=2) as client:
                r = json.loads(client.makefile('rb').readline())
                self.assertEqual(r['error']['code'], 'PeerDenied')
        finally:
            s.close()
        self.assertFalse(s.alive)


if __name__ == '__main__':
    unittest.main()
