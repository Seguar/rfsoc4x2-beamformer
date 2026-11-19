# RF profiles

A board session starts at one of two measured profiles. **5.2 GHz is the default**
(the patch antennas' frequency); 3 GHz is the original validated profile. The
application's RF page can retune within a session; the start profile comes from
the board (`--rf-mhz` of the board service, or `rf_mhz` in a client's start
request) and the application takes its RF fields from the board's ready message.

| Start | ADC mixer | ADC Nyquist zone | DAC mixer | DAC Nyquist zone |
|---|---|---|---|---|
| **5200 MHz** (default) | +5200 MHz, no mirror | 1 (odd: 5.0–7.5 GHz at 5 GS/s) | 5200 MHz | measured per session: 1 or 2 |
| 3000 MHz | +3000 MHz, no mirror | 2 (2.5–5.0 GHz) | 3000 MHz | 1 |

Unchanged in both: ADC attenuation 0 dB, DAC current 40.5 mA (maximum), QMC gain
1.99, DAC_B waveform peak code 9600 (since 2026-11-19; the
conducted measurements below used 1200), Steering beamformer.

## Why the DAC zone is measured at 5.2 GHz

The DAC runs at 10 GS/s and the ADC at 5 GS/s, exactly twice. The DAC's output at
f always has an image at 10 GHz − f, and the ADC folds f and 10 GHz − f onto the
same band with the same spectral orientation. At 3 GHz the image is at 7 GHz,
outside the passives' band, and does not matter. At 5.2 GHz the image is at
4.8 GHz with nearly the same amplitude (NRZ sinc 0.66 vs 0.61, mix mode 0.62 vs
0.65), so the received signal is the coherent sum of both.

NRZ (DAC zone 1) and mix mode (zone 2) give the image opposite signs. Which of the
two adds constructively changes from session to session; it was not tied to the
start frequency, the multi-tile sync latency or the DAC mixer phase (a DAC phase
sweep moved nothing, as expected: the image is conjugated twice). In the wrong
zone three of the four streams were 10–18 dB weaker and two no longer demodulated.

So at 5.2 GHz the board, right after start-up synchronisation, plays the waveform,
captures with each DAC zone (only the zone register changes: no retune, no tile
resynchronisation), keeps the zone with more received power (margin 3 dB, else
zone 2), turns the DAC off again and reports the zone in its ready message. The
manifest records both measurements (`dac_zone_selection`).

When you retune by hand to 5.2 GHz, keep the DAC zone the board reported for this
session; the other one is the weak state.

## Measurements (conducted loopback, 2026-11-17)

DAC_B → ZAPDQ-4 → ZA4PD-4 → four ADCs, the 2–4.2 GHz passives used out of band.

**Settings sweep at 5.2 GHz** (one session started at 3 GHz, then retuned):
DAC zone 1 was about 11 dB weaker than zone 2 in that session, and the ADC pairs
(+5200, odd) and (−5200, even) were equivalent. Repeating sessions later showed
that the strong DAC zone changes between sessions (zone 1 in 7 of 8 sessions,
zone 2 in the others), which led to the selection above.

**Default sessions with the selection** (6 sessions): every session came up in the
strong state, choosing zone 1 five times and zone 2 once, with 7.3 dB between the
zones each time. Stream levels 45 / 65 / 68 / 57 rms codes, locks 0.97–0.99,
start-up about 10 s.

**Payload EVM** (app session code, 12 full frames each, all bursts qualified):

| | Combined (Steering) | Stream 0 / 1 / 2 / 3 |
|---|---|---|
| 5.2 GHz default, session A | 5.30 % (−25.5 dB) | 14.3 / 10.0 / 9.5 / 11.1 % |
| 5.2 GHz default, session B | 5.41 % (−25.3 dB) | 14.5 / 10.1 / 9.5 / 11.1 % |
| 5.2 GHz, wrong DAC zone | 14.8 % (−16.6 dB) | 14.1 % / no sync / no sync / 23.3 % |
| 3 GHz | 4.40 % (−27.1 dB) | 8.8 / 8.7 / 8.4 / 9.2 % |

Beamformers on the same 5.2 GHz frames: Steering 5.33 %, PC 5.25 % (within the
frame-to-frame spread), RVL 7.1 %, QCB 13.3 %; MVDR, DL MVDR, DL ITER MVDR and DMR
did not reach preamble sync on this common feed (as at 3 GHz).

## Over the air (2026-11-19)

DAC_B → ZN2PD-9G-S+ combiner → AKF-1252 band-pass filter (5170–5330 MHz, about
40 dB at 4.8 GHz) → single 5.2 GHz patch; four patches of one row of the 4×4
board → ADC_A–D.

| Distance | DAC peak | ADC peak | Stream locks |
|---|---|---|---|
| 0.5 m | 1200 | about −54 dBFS | none |
| 0.2 m | 1200 | −61 dBFS | 0.24–0.28, mostly none |
| 0.2 m | 4800 | −56 dBFS | 0.72–0.79 |
| 0.2 m | 9600 | −50 dBFS | 0.91–0.92, every frame |

So sessions now start at peak 9600; the helper's start-up capture refuses a
session whose ADC peak exceeds −6 dBFS. With the filter, the DAC zone measurement
at start no longer shows the 7 dB difference (0.1–2.4 dB at the noise floor).

Both DACs into the 0° combiner are not usable yet: every DAC mixer phase update
(`dphasec`, even to the same value) lands DAC_A at a different phase relative to
DAC_B, so the sum is either about +6 dB or a full cancellation. Sessions play
DAC_B only.

## Limits

- The link is noise limited: the ADC peak is about −41 dBFS and each stream's EVM
  follows its level. The DAC is already at maximum current and QMC gain; the
  remaining lever was the waveform peak, now 9600 codes by default (below).
- Stream 0 (ADC_D) is about 3 dB weaker than the others at 5.2 GHz in both zones.
- The passives are specified for 2–4.2 GHz; these numbers characterize this cable
  set only.
- Over the air the 4.8 GHz image also radiates. Its phase relative to the wanted
  signal then depends on the propagation path, so the per-session zone choice
  measured at start-up does not guarantee constructive addition for every element
  and angle. A 5.2 GHz band-pass filter at the DAC output removes the image and
  the zone dependence; changing converter sample rates would too, but needs a new
  clocking and FPGA configuration.
