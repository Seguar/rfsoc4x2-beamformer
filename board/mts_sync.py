"""RFSoC4x2 MTS configuration and common DAC/ADC start.

Same active tiles, reference tile, SYSREF events and automatic target latency as
the installed rfsoc_mts library. No clock-rate changes or firmware replacement.
"""
import time


def status(overlay):
    def group(config):
        return dict(tiles=int(config.Tiles), reference_tile=int(config.RefTile),
                    sysref_enabled=int(config.SysRef_Enable), target_latency=int(config.Target_Latency),
                    latency=[int(config.Latency[n]) for n in range(4)],
                    offset=[int(config.Offset[n]) for n in range(4)])
    return dict(adc=group(overlay.xrfdc.mts_adc_config),
                dac=group(overlay.xrfdc.mts_dac_config), capture_mode=int(overlay.da),
                adc_mixer_events=[int(overlay.adc[n].MixerSettings['EventSource']) for n in range(4)],
                dac_mixer_events=[int(overlay.dac[n].MixerSettings['EventSource']) for n in (0, 2)])


def enable(overlay):
    """Enable both converter groups. Wrapper constructor already ran init_tile_sync.

    Do not call init_tile_sync after writing waveform RAM: it resets converter
    tiles. Configure their SYSREF-latched mixer/NCO changes, then run both MTS
    groups just as the library's sync_tiles does.
    """
    sysref = 3  # xrfdc.EVNT_SRC_SYSREF in the installed driver
    if overlay.ACTIVE_ADC_TILES != 0b0101 or overlay.ACTIVE_DAC_TILES != 0b0101:
        raise RuntimeError('MTS policy is for RFSoC4x2 active tiles 0 and 2 only')
    overlay.dacs_off()
    overlay.trig_cap.off()
    overlay.event_src = sysref
    overlay.xrfdc.mts_adc_config.RefTile = 2
    overlay.xrfdc.mts_dac_config.RefTile = 2
    overlay.configure_dacs()
    overlay.configure_adcs()
    overlay.sync_tiles(dacTarget=-1, adcTarget=-1)
    overlay.verify_clock_tree()
    overlay.da = 2
    result = status(overlay)
    for kind in ('adc', 'dac'):
        g = result[kind]
        if (g['tiles'], g['reference_tile'], g['sysref_enabled'], g['target_latency']) != (5, 2, 1, -1):
            raise RuntimeError('MTS configuration readback differs: '+kind)
    if any(n != sysref for n in result['adc_mixer_events']+result['dac_mixer_events']):
        raise RuntimeError('A mixer is not using the shared SYSREF event')
    return result


def trigger(overlay, dwell=.01):
    """Start both RAM players and ADC capture from the shared trigger edge.

    The matched design ORs capture trigger into both DAC enables. Assert that
    common gate first, latch the selected continuous enables while it is high,
    and only then lower the trigger. Sequential GPIO writes cannot create
    different DAC start edges during this interval. The ten-ms dwell follows
    the 4x2 wrapper's original da=2 capture wait and covers the full ADC RAM
    (131072 rows at 125 MHz = 1.05 ms); 2 ms is the shortest allowed.
    """
    if not .002 <= dwell <= .5:
        raise ValueError('Capture trigger dwell must cover the complete RAM')
    overlay.trig_cap.off()
    overlay.dacs_off()
    try:
        overlay.trig_cap.on()
        overlay.dacs_control()
        time.sleep(dwell)
    except BaseException:
        overlay.dacs_off()
        raise
    finally:
        overlay.trig_cap.off()
