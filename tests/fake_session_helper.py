"""Stand-in for board/legacy_capture.py in session-service tests: no hardware.
Becomes ready, waits for its owner (stdin EOF) and writes a shutdown manifest."""
import json
import os
import sys
import time

args = sys.argv[1:]
out = args[args.index('--out') + 1]
mode = os.environ.get('FAKE_HELPER_MODE', 'ok')
if mode == 'fail':
    print('RuntimeError: overlay did not load', flush=True)
    sys.exit(3)
time.sleep(float(os.environ.get('FAKE_HELPER_DELAY', '0.3')))
print('Waiting for legacy client on port %s; DACs disabled' % args[args.index('--stream-port') + 1], flush=True)
while os.read(0, 4096):
    pass
with open(out, 'w') as f:
    json.dump({'dac_off_commanded': True, 'shutdown_errors': [], 'dac_ram_zero_writes': ['dac0_player', 'dac1_player'],
               'frames_captured': 7, 'argv': args}, f)
print('Both DAC RAMs zero (readback) and enables off commanded.', flush=True)
