"""Regression: legacy stop must be consumed while streaming, with fragmented TCP."""
import importlib.util
from pathlib import Path
import socket
import threading
import time
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location('legacy_server',
    Path(__file__).resolve().parents[1]/'board'/'legacy_server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class Backend:
    dataStream = 0
    data_size = 8

    def __init__(self):
        self.stopped = threading.Event()

    def handle_commands(self, lines):
        for line in lines:
            name, value = line.split()
            setattr(self, 'data_size' if name == 'dataChan' else name, int(value))
            if name == 'dataStream' and value == '0':
                self.stopped.set()

    def get_custom_data(self, count):
        return np.arange(count, dtype=np.int16)


class LegacyServerTests(unittest.TestCase):
    def test_fragmented_start_and_in_stream_stop(self):
        host, peer = socket.socketpair()
        backend = Backend()
        errors = []
        def run():
            try:
                server.serve_client(host, backend)
            except Exception as error:
                errors.append(error)
        thread = threading.Thread(target=run)
        thread.start()
        try:
            peer.settimeout(2)
            peer.sendall(b'dataChan 8#dataStr')
            peer.sendall(b'eam 1\r\n')
            received = bytearray()
            while len(received) < 16:
                received.extend(peer.recv(16-len(received)))
            self.assertEqual(received, np.arange(8, dtype='<i2').tobytes())
            peer.sendall(b'dataStream 0\n')
            # A streaming client keeps consuming queued frames until stop takes
            # effect. Otherwise a fast fake capture can fill send buffers before
            # control arrives and intentionally hit the bounded send timeout.
            deadline = time.monotonic()+2
            peer.settimeout(.05)
            while not backend.stopped.is_set() and time.monotonic() < deadline:
                try:
                    peer.recv(65536)
                except socket.timeout:
                    pass
            self.assertTrue(backend.stopped.is_set(), 'stop was trapped behind stream loop')
        finally:
            peer.close()
            thread.join(3)
            host.close()
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])

    def test_reject_entire_invalid_batch(self):
        for line in (b'dataStream 1#dacbf 1', b'dataChan 7', b'dataChan 1048584',
                     b'dataStream 2', b'dacPow 1/0/7/0'):
            with self.assertRaises(ValueError):
                server.commands(line)


if __name__ == '__main__':
    unittest.main()
