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
rf = int(args[args.index('--rf-mhz') + 1])
zones = {3000: (2, 1), 5200: (1, 2)}[rf]
# like the real helper: report the zones it set (5200: DAC zone measured per session)
print('RF profile ' + json.dumps(dict(rf_mhz=rf, adc_nyquist_zone=zones[0],
                                      dac_nyquist_zone=int(os.environ.get('FAKE_DAC_ZONE', zones[1])))), flush=True)
print('Waiting for legacy client on port %s; DACs disabled' % args[args.index('--stream-port') + 1], flush=True)
if os.environ.get('FAKE_HELPER_STATUS'):
    # like the real helper once frames flow: live status for the OLED
    with open(os.path.join(os.path.dirname(out), 'status.json'), 'w') as f:
        json.dump(dict(time=time.time(), frames=12, rf_mhz=float(rf), adc_peak_dbfs=-19.4, streaming=True,
                       evm_percent=3.88), f)
while os.read(0, 4096):
    pass
with open(out, 'w') as f:
    json.dump({'dac_off_commanded': True, 'shutdown_errors': [], 'dac_ram_zero_writes': ['dac0_player', 'dac1_player'],
               'frames_captured': 7, 'argv': args}, f)
print('Both DAC RAMs zero (readback) and enables off commanded.', flush=True)
