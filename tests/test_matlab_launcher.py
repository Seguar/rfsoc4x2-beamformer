"""The frontend receives explicit DSP settings, never the SSH credential config."""
import json
from pathlib import Path
import tempfile
import unittest
from scipy.io import loadmat
import numpy as np
from tools.matlab_frontend import command, literal
from rfsoc_demo.dsp import reference, FS


class MatlabLauncherTests(unittest.TestCase):
    def test_exact_reference_and_private_config_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            args = command(out, out, {'host': 'example.invalid',
                'matlab_executable': 'matlab-test', 'password_file': 'DO_NOT_FORWARD',
                'host_key': 'DO_NOT_FORWARD'}, headless=True, frames=12, use_vsa=False)
            self.assertEqual(args[0], 'matlab-test')
            self.assertIn('-noFigureWindows', args)
            self.assertEqual(args[-2], '-batch')
            settings = json.loads((out/'matlab-frontend.json').read_text())
            self.assertEqual(settings['maxFrames'], 12)
            self.assertEqual(settings['fsHz'], FS)
            self.assertTrue(settings['directOnly'])
            self.assertNotIn('DO_NOT_FORWARD', (out/'matlab-frontend.json').read_text())
            self.assertNotIn('DO_NOT_FORWARD', (out/'run_matlab.m').read_text())
            saved = loadmat(out/'matlab-reference.mat')
            wave, symbols = reference()
            np.testing.assert_array_equal(saved['wave'][:, 0], wave)
            np.testing.assert_array_equal(saved['symbols'], symbols)

    def test_typed_vsa_reference_does_not_mutate_config(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            sdk = {}
            for name in ('dllPath', 'customOfdmDllPath', 'typedHelperPath'):
                path = out/(name+'.dll')
                path.write_bytes(b'test-placeholder')
                sdk[name] = str(path)
            sdk.update(fsHz=FS, fcHz=3e9, bandwidthHz=FS,
                       captureSamples=4096, visible=False)
            original = dict(sdk)
            command(out, out, {'host': 'example.invalid',
                'matlab_executable': 'matlab-test', 'matlab_vsa': sdk},
                headless=True, frames=1, use_vsa=True)
            settings = json.loads((out/'matlab-frontend.json').read_text())
            self.assertEqual(settings['vsa']['referencePath'], str(out/'matlab-reference.mat'))
            self.assertEqual(settings['vsa']['measurementTimeoutSeconds'], 3)
            self.assertNotIn('setupPath', settings['vsa'])
            self.assertEqual(sdk, original)

    def test_literal_quotes_and_line_rejection(self):
        self.assertEqual(literal("a'b"), "'a''b'")
        for value in ('a\nb', 'a\rb', 'a\0b'):
            with self.assertRaises(ValueError):
                literal(value)

    def test_setx_config_needs_no_typed_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            dll=out/'Interfaces.dll'; dll.write_bytes(b'placeholder')
            setup=out/'test.setx'; setup.write_text('<setup/>')
            command(out,out,{'host':'example.invalid','matlab_executable':'matlab-test',
                'matlab_vsa':{'dllPath':str(dll),'setupPath':str(setup),'fsHz':FS,
                    'fcHz':0,'bandwidthHz':FS,'captureSamples':16384,'visible':False}},
                headless=True,frames=1,use_vsa=True)
            cfg=json.loads((out/'matlab-frontend.json').read_text())['vsa']
            self.assertEqual(cfg['setupPath'],str(setup))
            self.assertNotIn('typedHelperPath',cfg)

    def test_vsa_requires_explicit_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'requires explicit'):
                command(Path(directory), Path(directory),
                    {'host': 'example.invalid', 'matlab_executable': 'matlab-test'},
                    headless=True, frames=1, use_vsa=True)


if __name__ == '__main__':
    unittest.main()
