#!/usr/bin/env python3
"""Minimal Python client of the board session service (docs/BOARD_SERVICE.md).

Starts a session, reads v3 (window4) frames and sends acknowledged board
commands. For bench checks and diagnostics; the application remains the
MATLAB/exe frontend. Closing the client ends the session: the board helper
zeroes both DAC memories and commands the DAC enables off.

    with Session('192.168.3.1') as s:
        s.command('phase 0/90/0/0')
        x = s.frame()          # rows x 4 complex (I - jQ, as the host app)
"""
import json
import socket
import struct
import time
import zlib

import numpy as np

HDR = struct.Struct('<4sQQQq8sII')
EXT = struct.Struct('<II32s32sH')


def _line(sock):
    data = b''
    while not data.endswith(b'\n'):
        part = sock.recv(1)
        if not part:
            raise ConnectionError('connection closed')
        data += part
    return json.loads(data)


def _exact(sock, n):
    buf = bytearray(n)
    view, got = memoryview(buf), 0
    while got < n:
        k = sock.recv_into(view[got:], n - got)
        if not k:
            raise ConnectionError('stream closed')
        got += k
    return bytes(buf)


class Session:
    def __init__(self, host, port=4013, max_seconds=600, timeout=180, progress=print, capture_clock_mhz=None, rf_mhz=None):
        self.host = host
        self.svc = socket.create_connection((host, port), timeout=10)
        req = {'op': 'start', 'max_seconds': max_seconds}
        if capture_clock_mhz is not None:
            req['capture_clock_mhz'] = capture_clock_mhz
        if rf_mhz is not None:
            req['rf_mhz'] = rf_mhz
        self.svc.sendall(json.dumps(req).encode() + b'\n')
        self.svc.settimeout(timeout)
        while True:
            msg = _line(self.svc)
            if msg.get('state') == 'ready':
                break
            if msg.get('state') == 'error':
                raise RuntimeError('%s: %s' % (msg.get('code'), msg.get('message')))
            if progress:
                progress('board: %s (%s s)' % (msg.get('step'), msg.get('elapsed')))
        self.ready = msg
        board = msg.get('host') or host
        self.stream = socket.create_connection((board, msg['stream_port']), timeout=30)
        self.stream.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        magic = _exact(self.stream, 8)
        if magic != b'R4X2IQ3\n':
            raise RuntimeError('unexpected stream magic %r' % magic)
        n = struct.unpack('<I', _exact(self.stream, 4))[0]
        self.meta = json.loads(_exact(self.stream, n))
        self.ctrl = socket.create_connection((board, msg['control_port']), timeout=30)
        self.next_id = 0
        self.last_info = {}

    def command(self, line):
        """Send one board command line; returns the acknowledged state."""
        self.next_id += 1
        self.ctrl.sendall(json.dumps({'id': self.next_id, 'command': line}).encode() + b'\n')
        reply = _line(self.ctrl)
        if not reply.get('ok'):
            raise RuntimeError('board refused %r: %s' % (line, reply.get('error')))
        return reply['result']

    def frame(self):
        """Request and return one window: rows x 4 complex, columns = streams 0..3."""
        self.stream.sendall(b'N')
        magic, seq, mono, req, real, label, mask, nbytes = HDR.unpack(_exact(self.stream, HDR.size))
        if magic not in (b'IQZ3', b'IQL3'):
            raise RuntimeError('unexpected frame %r' % magic)
        ext = _exact(self.stream, EXT.size)
        start, sel_us, _, win_sha, jlen = EXT.unpack(ext)
        self.last_info = json.loads(_exact(self.stream, jlen))
        payload = _exact(self.stream, nbytes)
        if magic == b'IQZ3':
            raw_len = struct.unpack('<I', payload[:4])[0]
            planes = zlib.decompress(payload[36:], -15)
            body = np.frombuffer(planes, np.uint8).reshape(2, raw_len // 2).T.tobytes()
        else:
            body = payload
        w = np.frombuffer(body, '<i2').astype(float).reshape(-1, 8)
        self.last_info.update(sequence=seq, start=start, select_us=sel_us)
        return w[:, 0::2] - 1j * w[:, 1::2]

    def close(self):
        for s in ('ctrl', 'stream'):
            try:
                getattr(self, s).close()
            except (AttributeError, OSError):
                pass
        try:
            self.svc.sendall(b'{"op":"stop"}\n')
            self.svc.settimeout(150)
            end = time.monotonic() + 150
            while time.monotonic() < end:
                msg = _line(self.svc)
                if msg.get('state') == 'ended':
                    self.ended = msg
                    break
        except (OSError, ValueError, ConnectionError):
            pass
        finally:
            self.svc.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
