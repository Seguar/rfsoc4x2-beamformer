import types
import unittest
from unittest.mock import patch
from board import mts_sync


class MtsSyncTests(unittest.TestCase):
    def overlay(self):
        events=[]
        conf=lambda: types.SimpleNamespace(Tiles=0,RefTile=0,SysRef_Enable=0,Target_Latency=0,
                                          Latency=[0]*4,Offset=[0]*4)
        o=types.SimpleNamespace(ACTIVE_ADC_TILES=5,ACTIVE_DAC_TILES=5,event_src=0,da=0)
        o.xrfdc=types.SimpleNamespace(mts_adc_config=conf(),mts_dac_config=conf())
        o.adc=[types.SimpleNamespace(MixerSettings={'EventSource':0}) for _ in range(4)]
        o.dac=[types.SimpleNamespace(MixerSettings={'EventSource':0}) for _ in range(4)]
        o.dacs_off=lambda:events.append('dacs_off')
        o.dacs_control=lambda:events.append('latch_selected')
        o.trig_cap=types.SimpleNamespace(off=lambda:events.append('trigger_off'),on=lambda:events.append('trigger_on'))
        def configure(kind):
            events.append('configure_'+kind)
            for b in getattr(o,kind):b.MixerSettings['EventSource']=o.event_src
        o.configure_adcs=lambda:configure('adc')
        o.configure_dacs=lambda:configure('dac')
        def sync(dacTarget,adcTarget):
            events.append('both_mts')
            for k,t in [('dac',dacTarget),('adc',adcTarget)]:
                c=getattr(o.xrfdc,'mts_'+k+'_config');c.Tiles=5;c.SysRef_Enable=1;c.Target_Latency=t
        o.sync_tiles=sync;o.verify_clock_tree=lambda:events.append('clock_lock')
        return o,events

    def test_all_active_converter_groups_and_sysref(self):
        o,e=self.overlay();s=mts_sync.enable(o)
        self.assertEqual(e,['dacs_off','trigger_off','configure_dac','configure_adc','both_mts','clock_lock'])
        for k in ('adc','dac'):
            self.assertEqual((s[k]['tiles'],s[k]['reference_tile'],s[k]['sysref_enabled'],s[k]['target_latency']),(5,2,1,-1))
        self.assertEqual(s['capture_mode'],2)
        self.assertEqual(s['adc_mixer_events']+s['dac_mixer_events'],[3]*6)

    def test_shared_edge_precedes_separate_gpio_latches(self):
        o,e=self.overlay()
        with patch.object(mts_sync.time,'sleep',side_effect=lambda t:e.append(('dwell',t))):
            mts_sync.trigger(o)
        self.assertEqual(e,['trigger_off','dacs_off','trigger_on','latch_selected',('dwell',.01),'trigger_off'])

    def test_trigger_is_lowered_if_latching_fails(self):
        o,e=self.overlay()
        o.dacs_control=lambda:(_ for _ in ()).throw(RuntimeError('GPIO error'))
        with self.assertRaisesRegex(RuntimeError,'GPIO error'):mts_sync.trigger(o)
        self.assertEqual(e[-1],'trigger_off')

    def test_wrong_board_tiles_or_short_capture_refused(self):
        o,e=self.overlay();o.ACTIVE_DAC_TILES=15
        with self.assertRaises(RuntimeError):mts_sync.enable(o)
        self.assertEqual(e,[])
        with self.assertRaises(ValueError):mts_sync.trigger(o,.00001)
        self.assertEqual(e,[])

    def test_driver_readback_without_sysref_stops_startup(self):
        o,e=self.overlay();sync=o.sync_tiles
        def broken(**kwargs):
            sync(**kwargs);o.xrfdc.mts_adc_config.SysRef_Enable=0
        o.sync_tiles=broken
        with self.assertRaisesRegex(RuntimeError,'readback differs: adc'):
            mts_sync.enable(o)
        self.assertNotIn('trigger_on',e)
