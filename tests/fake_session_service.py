"""Run board/session_service.py without hardware: fake preflight and the fake
helper (tests/fake_session_helper.py). For the MATLAB board-link test.
Usage: python -m tests.fake_session_service --port <port> [--bind <address>]
"""
import argparse
import importlib.util
from pathlib import Path
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('session_service', ROOT/'board/session_service.py')
svc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(svc)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', type=int, required=True)
    p.add_argument('--bind', default='127.0.0.1')
    p.add_argument('--seconds', type=float, default=600)
    a = p.parse_args()
    with tempfile.TemporaryDirectory() as state:
        args = svc.parser().parse_args(['--root', str(ROOT/'tests'), '--state', state, '--bind', a.bind,
                                        '--port', str(a.port), '--helper', 'fake_session_helper.py',
                                        '--board-name', 'RFSoC4x2', '--start-timeout', '20', '--overlay', 'boot'])
        pre = dict(board='RFSoC4x2', machine='aarch64', busy=[], bootpy='failed', ports_taken=[], hashes=dict(svc.EXPECTED))
        service = svc.Service(args, preflight_fn=lambda ports: pre, networks_fn=lambda: [], systemctl=lambda *x: None).start()
        print('FAKE session service (no hardware) on %s:%d' % (a.bind, service.port), flush=True)
        try:
            time.sleep(a.seconds)
        finally:
            service.close(wait=20)


if __name__ == '__main__':
    main()
