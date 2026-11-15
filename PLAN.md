# Demo plan — 2026-11-15

User requested a new public repository showing RFSoC 4x2 DAC demodulation,
tracking and beamforming with the two-DAC/hybrid/splitter/four-ADC loopback,
avoiding external MXG interference; `vsa_rfsoc` is a reference. User also
requested agent instructions and authorized one laptop agent for live checks.

Claims hold until explicitly released, irrespective of timestamps.

| Part | Owner | State |
|---|---|---|
| Repository code, docs, tests, publication | Coordinator | MATLAB software and direct live path validated; VSA/array remain pending |
| Laptop and board experiments | Coordinator; no new overlay operation | Previous MATLAB frontend exited; capture child defunct, five notebook kernels present; audit before live handover |

## Initial plan and historical checkpoints

Decisions: public code repository; existing matched 4x2 overlay; no FPGA build;
low-level waveform first; hardware-free simulation clearly labelled. Initial RF
candidate 3 GHz fits passive bands; runtime/spectrum validation remains required.

Open: MXG RF connection, output state and injection topology; whether the same
receive path permits spatial separation. Laptop agent must establish access and
save private evidence before hardware claims. Do not publish private inputs.

Next: stage the reviewed helper/reference, verify board and instrument state,
run DAC0-only low-level captures, analyze results, calibrate DAC1 and then both
if headroom and signal lock permit. Record final DAC/MXG/service states.

Checkpoint: laptop evidence received privately; no capture or live verification.
Current DAC/MXG/service state unknown. Helper review fixes applied and eight
host tests pass. Hardware remains pending current secure board access and MXG
identification. No agent retains hardware ownership after this access attempt.

User update: MXG RF cable disconnected; all five notebook kernels belong to user
and may be stopped for the demo. Exclusive capture is authorized. Authenticated
preflight confirmed live board identity and matched boot hashes. New GPIO handling
records commanded shutdown without claiming physical RF-off from DATA reads.

Real-time scope clarified: fixed broadside versus adaptive EVM while moving a
wanted transmit patch, then jammer rejection through a distinct OTA path.
Live dashboard and framed board stream implemented; eleven host tests and a
headless dashboard render pass. Antennas labelled 5.2 GHz; spacing/response
unmeasured, CW versus modulated jammer undecided. Current passives specified only
to4.2GHz; keep3GHz conducted test separate from future5.2GHz OTA validation.
Authorized exclusive DAC0 capture delegated; hardware owner holds only the new
private capture evidence/staged experiment, parent owns all public code.

Latest capture checkpoint: DAC0/DAC1 each10frames obtained, no rail hits, but
poor EVM prevents a working demodulation/combining claim. Hardware owner released
claim; Jupyter0kernels, bootpy no process/failed state, DAC disables commanded.
User changed wiring to DAC_A→BW-S20W2+20dB→ADC_A. Source inspection found extra
mode3 IMR2, capture-trigger OR into both DAC players, and missing da0 settle wait.
Parent integrated500Mcomplex/s reference, inactive-RAM zeroing, settle wait and
ADC0-only analysis/live mode.15host tests pass; corrected direct capture pending.

Direct test milestone: fresh ADC_A frames and liveTCP8.62captures/s demonstrated,
but intermittent EVM errors remain (good~3%, badup65.55%).59filehashes verified.
Rootoffline sees~1sample advances insidebadpayloads. Waveform2 adds distributed
timing pilots and versioned receive behavior;19hosttests pass. Dedicated sole
laptop hardware agent owns private timing-diagnostic staging/evidence only while
running. Publiccode remains parent-owned. Credential privately retained with user
authorization; no more unnecessary repeated password requests.

V2 physical milestone: bounded30andlive100frames validated, allzeroBER/acquired;
EVMmedian/max3.79/9.98%live. Raw100ppmadvancepersists. Factoryprofilephysically
switched/restoredbutincompatiblewithfixedMMCM/mixedtileclocktopology; no lower-rate
workaround adopted. Original500/500restored, DACRAMzero, bootpystopped/Jupyteractive.
Parentverified60filehashesandreprocessed30boundedframes. Newone-command direct
launcherreadyforfinalheadlesshardwarestartup/shutdownvalidation. Array/OTA deferred
untiluserconnectsfourinputsandresolves5.2GHzRFchain; constantEVMnotpromised.

Launcher milestone complete: a fresh 100-frame headless run passed startup,
streaming, disconnect, DAC clears/off commands, retrieval and process cleanup.
One-line output-path fix applied publicly. Median/max EVM 3.89/9.73%, zero BER,
all locks. No hardware agent retains ownership. The direct demonstration is ready
to launch; graphical interactions remain untested. Physical array/MXG tests stay
open until the user's later antenna setup; raw sample loss remains documented.

User requested EVM in dB as well as percent. Live/static plots now use a dB axis
with a percent axis, current EVM shows both, and metrics include evm_db. Host tests
and headless renders pass; no new hardware run is required for the unit display.

User reported cable changes still showing good EVM, then identified DAC_B.
Confirmed naming error: logical dac0 actually feeds printed DAC_B. TX labels and
launcher selection now use printed letters; RX labels use stream numbers until
verified. Added RX RMS/freshness and current-metric clearing for stale/unlocked
states.21 host tests pass. The user's live GUI requires a controlled restart.

Connector-loss validation completed: real DAC_B RAM blanking produced unlock
and a received-level drop; capture pause cleared current metrics as STALE.
The corrected Python GUI now remains running and holds the hardware claim.

MATLAB milestone in progress: actual old/new .mlapp XML, exports, shared helpers
and matched boot.py were audited. Parent owns new MATLAB core/frontend, boot-loop
source, docs and tests. One laptop agent owns private MATLAB/VSA validation only;
it must preserve the current Python GUI and board ownership. 23 Python host tests
pass. Exact waveform reference and Python differential fixture generated privately.
MATLAB execution, new UI and VSA streaming/EVM remain pending. The first newly
owned VSA instance timed out during startup; packing tests passed. Original binary
apps and deployed boot assets remain unchanged.

MATLAB laptop gate: differential CFO/EVM/BER, noise rejection and eleven beamformers
passed; strict core gate failed DL ITER MVDR. Original root equation squared the
wrong term and used the multiplier instead of reciprocal loading. Corrected from
Li/Stoica/Wang's equations, added isotropic closed-form and residual checks; full
MATLAB rerun pending. Local TCP fragmentation/IQ/sequence/error controls passed.
Owned VSA startup succeeds with explicit port/Use64Bit and disposes normally;
replay completes fresh but trace status32 prevents a valid EVM/lock claim. Sole
laptop agent now investigates waveform/setup compatibility; no board handover yet.
Parent added MATLAB launcher/headless lifecycle and bounded UI backlog draining;
new MATLAB source is staged for its next execution check, not yet live-validated.

Latest milestone: corrected c87817f core gate passes all12 modes, differential
CFO/EVM/BER, noise and isotropic root controls; transport passes. 26 Python tests
pass. Seven simulated VSA reader cases reject stale/NoSync/unknown/low-correlation
results; actual VSA positive control remains unavailable. Reviewed reader and
headless resource-cleanup fixes integrated. A fresh100frame MATLAB physical run
has unique sequences0..99, all acquired, BER0, median/maxEVM3.31/8.30%. Both DAC
RAM clear/off records and no shutdown errors; physical RF-off not measured.
Durable MATLAB GUI left visible/advancing. That session now owns hardware, replacing
the prior Python display, and its claim remains HELD until orderly shutdown.
Sole laptop agent owns only new private VSA-source and localhost UI diagnostics;
must preserve physical MATLAB session. VSA Input.DataFrom Hardware/Recording and
effective CustomOFDM settings are the next concrete probe. Array/OTA/MXG unproven.

VSA source probe complete: selecting USR analyzer changes CustomOFDM toVector;
Hardware source readback succeeds. Candidate effective sample rate differs from
intended125MHz. Vendor recording rawEVM0.608/sync0.976 stillstatus32 and rejected.
CustomOFDM/DDC IsValid=false; effective license mode unconfirmed. Sole nextlaptop
agent must APPLY documented post-analyzer SetMeasurementExtension +typed settings,
readback rates/mode and licensing, then finish independent localhostGUIcampaign.
No physicalowner changes; actualVSApositive remains unavailable.

Typed restore/setup exercised: CustomOFDM,125MHz,FFT256,CP¼,result12,48active,
pilots±7/±21. Capacity8192 required; actualsearch48.64us,finiteinputnotextended.
HiddenlocalhostGUI clean/noise/pause/history/closecampaignPASS, socketEOFverified.
Parentintegratedmodehelper,portablebuild/GUIcampaign scriptsandtypedreference
config; 27hosttestsPASS. ExternalVSApositive remainsunproven. USER clarified
'Use DirecDataSource hardware analyzer as in gui'. Sole newlaptopagent tests
thatactualanalyzer acceptance andread-onlyinspectsrelatedexistingGUIconfiguration;
genericDDCoption IsValid=false alone isnotadecisiveDirectDataSourceblock.
PhysicalMATLABsessioncontinuesholdinghardware; no competingownerauthorized.

DirectDataSource probe: exact-nameconfiguration accepts userIQ and completes;
no vendorlicense-denialerror. V2 clean/noise/wrongCP remain guardedunavailable;
clean hascarrier-lockfailure, controlsNoSync. 60evidencehashes delivered. Parent
adapter nowselectsexistingexact-nameDirectDataSource (createsonlyifmissing,
neverclearsgroups), uniqueOWNapp title. Nextsoleagent verifiesactualsample
fidelity inVector mode, finalhandle/settingsidentity and sufficientsearch after
settling, thenisolatessync/resourceconfiguration. Physicalownerunchanged.

User requested repositorySETXworkflow+a1/a2, thenurgentremoteaccessandDSPdebug.
NativeboardTailscale+DGXkeySSH independentlyverified; laptopnolongerrequired.
DebugnowonDSP. a2 matchedFFT64ofdm_iq_100_16_4x2.setx+dac_ofdm_f_500.mat by0.9999
preamblecorrelation. DSPmatchedSETX replayrawEVM0.0523%, sync0.999996; noise/wrong
setupNoSync. Strictreaderstillquarantinesunnamedtrace32; notfullguardedVSAPASS.
ParentimplementedSETXconfigurationpath andDSPconstructor/acquisitionsmokePASS,
no typedhelperrequired when setupPath supplied. Capturecapacityvsfiniteinputlimit
separated; no short-IQpadding/repetition. Physicalcurrentv2waveunchanged.


## DSP SETX warning policy — 2026-11-15

**Test / How:** Matched repository waveform, DirectDataSource and SETX recall;
two positive/noise/positive/wrong-SETX cycles, finite contiguous offline IQ.
**Results:** Eight fresh acquisitions; four matched positives 0.0523% EVM,
−65.63dB, correlation0.999996; four negatives rejected. Twenty-four simulated
reader cases pass; default policy remains strict.
**Conclusions:** Explicit SETX-only `allowSetxStatus32` permits unnamed bit32
with warning metadata while rejecting all other status bits and fault indicators.
No live RF VSA or physical array/MXG claim.
**Ways to resolve:** Validate the complete adapter in two owned VSA instances,
then audit hardware ownership and provide a matching legacy-waveform capture path.

Full `VsaSession` follow-up: two separately owned VSA instances each completed
positive → noise → positive with fresh results, successful disposal and exit0.
Four matched positives retained the explicit bit32 warning; two noise frames
were unavailable. No disconnect reproduced in this bounded test. Independent
Python audit of the eight probe and six adapter records passed. Live RF VSA and
physical beamforming remain pending.


## DOA spectrum and receive pattern — 2026-11-15

**Test:** Add spatial diagnostics to the new MATLAB frontend, including clearing
current plots on loss/pause. No board or instrument writes.
**How:** Training-covariance Beamscan/MVDR/MUSIC spectra and independent wanted
pilot angle; normalized selected-weight/frozen-baseline array responses. Seeded
four-element half-wave ULA tests at +18/−34 degrees, scalar pattern comparison,
±30-degree broadside nulls, unknown-spacing rejection and manifold coverage bounds.
Hidden GUI campaigns exercise direct and simulated-array modes over localhost.
**Results:** `RFSOC_SPATIAL_PASS`, all existing core/12-beamformer checks pass,
both `RFSOC_SIMULATED_GUI_PASS` sentinels and final MATLAB exit0. Direct-mode
plots remain unavailable; array curves populate and clear on noise/pause. All28
Python host tests pass. Two initial GUI fixture launches failed due to Windows
script execution policy and SSH child lifetime; using a hidden scheduled task for
the private fixture resolved the launch issues without changing test criteria.
**Conclusions:** DOA and receive-pattern functions are implemented and verified
with simulation, including current-data clearing. Spectral peaks may be interferers;
the pilot identifies the wanted DAC independently. Tracking can be disabled while
DOA continues. No physical angle accuracy or antenna pattern has been measured.
**Ways to resolve:** Measure spacing, verify channel order, calibrate all four
channels and validate OTA angles before labelling geometry-model angles physical.


## VSA-style instrument display — 2026-11-15

**Test:** Dark instrument display, prominent metrics, genuine constellation
persistence and steady graphics between new captures.
**How:** Complete-frame readiness polling with a receive buffer >=one frame;
persistent plot objects; existing pure DSP unchanged. Added GUI contracts for
steady current data between arrivals and cleared metric cards on failure/staleness.
**Results:** DSP MATLAB spatial/core gates and direct+array GUI campaigns pass,
exit0 and `DSP_THEME_GUI_COMPLETE`. All28 Python tests pass. Initial cold-render
GUI test exceeded its1s stale deadline; test config now explicitly allows5s for
cold rendering, while production remains1s. No simulated samples enter live mode.
**Conclusions:** Display theme and refresh behavior validated in simulation. No
RF quality or capture-rate improvement is inferred from the visual changes.
**Ways to resolve:** Restart the laptop app through its owned launcher, verify
fresh live frames and target-window layout, retain all DAC shutdown safeguards.
