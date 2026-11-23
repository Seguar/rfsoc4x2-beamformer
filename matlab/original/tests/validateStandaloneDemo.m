function report=validateStandaloneDemo(outDir)
% Standalone entry in its SIMULATION mode, run from source: no hardware.
% Needs RFSOC_DEMO_SETX / RFSOC_DEMO_REFERENCE and the vsa_rfsoc Functions path.
figures0=numel(findall(groot,'Type','figure'));timers0=numel(timerfindall);
r=RFSoCBeamformer('demo','seconds','14','snapshot',outDir,'theme','dark');
assert(contains(r.mode,'SIMULATION') && r.framesAccepted>=8,'Simulated session accepted too few frames.');
assert(isfield(r,'analysisValid') && r.analysisValid && r.evmPercent<25,'Simulated demodulation failed: %s',jsonencode(rmfield(r,'snapshot')));
assert(numel(r.snapshot)>=1 && isfile(r.snapshot{1}),'No snapshot written.');
% The session's model angle follows the simulated arrival angle (simulation only).
assert(abs(r.modelAngleDeg(1)-r.simulatedAngleDeg)<=3,'Model angle %.1f vs simulated %.1f.',r.modelAngleDeg(1),r.simulatedAngleDeg);
saved=load(r.snapshot{1});assert(contains(string(saved.data.scope),"SIMULATION") && strcmp(saved.settings.theme,'dark'));
% Unknown options and missing settings are refused before any window opens.
for bad={{'demo','speed','3'},{'no-such-settings.json'}}
    refused=false;try,RFSoCBeamformer(bad{1}{:});catch,refused=true;end
    assert(refused,'Invalid standalone arguments were accepted.');
end
assert(numel(findall(groot,'Type','figure'))==figures0 && numel(timerfindall)==timers0,'Standalone demo leaked resources.');
report=rmfield(r,'snapshot');report.label='SIMULATION ONLY — standalone entry from source';
disp('STANDALONE_DEMO_COMPLETE');
end
