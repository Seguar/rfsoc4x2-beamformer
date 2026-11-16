"""Hardware-free admission, state and fault tests for the control adapter."""
import unittest
from board.board_commands import BoardCommands


class Block:
    def __init__(self):
        self.MixerSettings = {'Freq': 3000, 'PhaseOffset': 0}


class Overlay:
    def __init__(self):
        self.adc = [Block() for _ in range(4)]
        self.dac = [Block() for _ in range(4)]
        self.da = 0
        self.dacPower = [1, 0, 0, 0]
        self.calls = []
        self.failure = None

    def handle_commands(self, commands):
        for line in commands:
            self.calls.append(line)
            name, text = line.split()
            if name == self.failure:
                raise RuntimeError('injected ' + name + ' driver error')
            values = list(map(int, text.split('/')))
            if name == 'da':
                self.da = values[0]
            elif name == 'dacPow':
                self.dacPower = values
            elif name == 'phase':
                for block, phase in zip(self.adc, values):
                    block.MixerSettings['PhaseOffset'] = phase
            elif name == 'dphase':
                for block, phase in zip(self.dac, values):
                    block.MixerSettings['PhaseOffset'] = phase
            elif name == 'fc':
                for block in self.adc:
                    block.MixerSettings['Freq'] = values[0]
                self.dac[0].MixerSettings['Freq'] = values[2]
                self.dac[2].MixerSettings['Freq'] = values[4]

    def dacs_control(self):
        self.calls.append('dacs_control')

    def dacs_off(self):
        self.calls.append('dacs_off')


class BoardCommandTests(unittest.TestCase):
    def setUp(self):
        self.overlay = Overlay()
        self.lock_checks = []
        self.adapter = BoardCommands(self.overlay, 0, 262144,
                                     lambda: self.lock_checks.append('lock'))

    def test_profile_batch_prevalidated_before_any_effect(self):
        for line in ['phase 0/10/20/30#dataChan 131072',
                     'phase 0/10/20/30#dacPow 1/0/1/0',
                     'phase 0/10/20/30#cal 4',
                     'phase 0/10/20/30#da 3']:
            with self.subTest(command=line), self.assertRaises(ValueError):
                self.adapter.apply(line)
            self.assertEqual(self.overlay.calls, [])
            self.assertEqual(self.lock_checks, [])
            self.assertEqual(self.adapter.revision, 0)
            self.assertIsNone(self.adapter.fault)

    def test_status_pause_resume_and_revision(self):
        initial = self.adapter.apply('status')
        self.assertEqual(initial['revision'], 0)
        self.assertTrue(initial['streaming'])
        self.assertFalse(initial['rf_off_verified'])
        paused = self.adapter.apply('dataStream 0')
        self.assertFalse(paused['streaming'])
        self.assertEqual(paused['revision'], 1)
        self.assertFalse(self.adapter.apply('status')['streaming'])
        resumed = self.adapter.apply('dataStream 1#status')
        self.assertTrue(resumed['streaming'])
        self.assertEqual(resumed['revision'], 2)
        self.assertEqual(self.overlay.calls, [])
        self.assertEqual(len(self.lock_checks), 4)

    def test_fixed_frame_size_noop(self):
        result = self.adapter.apply('dataChan 262144#status')
        self.assertEqual(result['data_words'], 262144)
        self.assertEqual(result['revision'], 0)
        self.assertEqual(self.overlay.calls, [])

    def test_phase_and_frequency_readback_and_one_batch_revision(self):
        command = 'fc -3000/1/3000/1/2999/2#phase 0/90/-90/180#dphase 10/20/30/40#da 1'
        result = self.adapter.apply(command)
        self.assertEqual(self.overlay.calls,
                         ['fc -3000/1/3000/1/2999/2', 'phase 0/90/-90/-180',
                          'dphase 10/20/30/40', 'da 1'])
        self.assertEqual(result['revision'], 1)
        self.assertEqual(result['da'], 1)
        self.assertEqual([v['Freq'] for v in result['adc_mixers']], [-3000]*4)
        self.assertEqual([v['Freq'] for v in result['dac_mixers']], [3000, 2999])
        self.assertEqual([v['PhaseOffset'] for v in result['adc_mixers']], [0, 90, -90, -180])
        self.assertEqual([v['PhaseOffset'] for v in result['dac_mixers']], [10, 30])
        self.assertEqual(self.lock_checks, ['lock'])
        self.assertEqual(self.adapter.log[-1], {'command': command, 'ok': True, 'revision': 1})

    def test_phase_is_wrapped_before_driver_write(self):
        result = self.adapter.apply('phase 200/-200/360/-360#dphase 540/-540/720/-720')
        self.assertEqual(self.overlay.calls, ['phase -160/160/0/0', 'dphase -180/-180/0/0'])
        self.assertEqual([x['PhaseOffset'] for x in result['adc_mixers']], [-160, 160, 0, 0])

    def test_selected_dac_power_and_explicit_driver_control(self):
        off = self.adapter.apply('dacPow 0/0/0/0')
        self.assertEqual(off['dac_power'], [0, 0, 0, 0])
        self.assertEqual(self.overlay.calls, ['dacPow 0/0/0/0', 'dacs_control'])
        self.adapter.apply('dacPow 1/0/0/0')
        self.assertEqual(self.overlay.dacPower, [1, 0, 0, 0])

    def test_dac_a_uses_driver_index_two(self):
        self.adapter = BoardCommands(self.overlay, 1, 262144, lambda: None)
        self.assertEqual(self.adapter.apply('dacPow 0/0/1/0')['dac_power'], [0, 0, 1, 0])
        count = len(self.overlay.calls)
        with self.assertRaises(ValueError):
            self.adapter.apply('dacPow 1/0/0/0')
        self.assertEqual(len(self.overlay.calls), count)

    def test_partial_driver_failure_latches_fault_and_stops_later_commands(self):
        self.overlay.failure = 'dphase'
        with self.assertRaisesRegex(RuntimeError, 'injected dphase'):
            self.adapter.apply('phase 1/2/3/4#dphase 10/20/30/40#da 1')
        self.assertEqual(self.overlay.calls,
                         ['phase 1/2/3/4', 'dphase 10/20/30/40', 'dacs_off'])
        self.assertEqual(self.adapter.revision, 0)
        self.assertIn('dphase', self.adapter.fault)
        self.assertFalse(self.adapter.log[-1]['ok'])
        self.assertEqual(self.lock_checks, [])
        with self.assertRaisesRegex(RuntimeError, 'capture stopped'):
            self.adapter.check()
        for command in ['status', 'phase 0/0/0/0', 'dataStream 1']:
            with self.assertRaisesRegex(RuntimeError, 'capture stopped'):
                self.adapter.apply(command)
        self.assertEqual(len(self.overlay.calls), 3)

    def test_output_disable_clears_ram_and_restore_callback(self):
        enabled = []
        self.adapter.set_output = enabled.append
        self.adapter.apply('dacPow 0/0/0/0')
        self.adapter.apply('dacPow 1/0/0/0')
        self.assertEqual(enabled, [False, True])

    def test_disable_error_does_not_mask_original_fault(self):
        self.overlay.handle_commands = lambda _: (_ for _ in ()).throw(RuntimeError('original failure'))
        self.overlay.dacs_off = lambda: (_ for _ in ()).throw(RuntimeError('disable failure'))
        with self.assertRaisesRegex(RuntimeError, 'original failure'):
            self.adapter.apply('phase 0/0/0/0')
        self.assertEqual(self.adapter.log[-1]['error'], 'original failure')
        self.assertIn('disable failure', self.adapter.fault)

    def test_lock_readback_failure_latches_fault_and_disables_dacs(self):
        def failed_lock():
            raise RuntimeError('clock lock lost')
        self.adapter.check_lock = failed_lock
        with self.assertRaisesRegex(RuntimeError, 'clock lock lost'):
            self.adapter.apply('phase 1/2/3/4')
        self.assertEqual(self.overlay.calls, ['phase 1/2/3/4', 'dacs_off'])
        self.assertEqual(self.adapter.revision, 0)
        self.assertIn('clock lock lost', self.adapter.fault)


if __name__ == '__main__':
    unittest.main()
