function report=validateCleanLive(settingsFile)
% Explicit owned LIVE test of the clean frontend, not a software regression.
s=jsondecode(fileread(settingsFile));assert(s.enableLive,'origapp:Live','Live authorization required.');
backend=origapp.LegacyVsaBackend(s.backend);
c=origapp.defaultConfig();c.frontend='clean';c.backend=backend;
c.originalRepoPath=s.referenceRepo;c.reviewedPath=fileparts(fileparts(fileparts(mfilename('fullpath'))));
c.outputDir=s.outputDir;c.visible=true;c.directOnly=false;c.dataChan=32768;c.ch=5;c.fc=3e9;c.fcAnt=3e9;
c.fc_d0=3e9;c.fc_d1=3e9;c.dacPow=[1 0 0 0];c.adcMirror=1;c.nyquistZone=2;
c.analyzer='integrated';c.periodSeconds=.02;c.frameTimeoutSeconds=.05;c.allowBoardCommands=true;
c.cutterAllowed=false;c.arrayLabel='common-feed diagnostic / array model (ULA d=lambda/2 @3 GHz)';
c.vsaSetupFile=s.backend.setupPath;
c.ofdm=struct('setupSha256',s.backend.setupSha256,'referenceMat',s.backend.referenceMat, ...
 'orientation','IplusjQ','syncThreshold',.8,'logFile',fullfile(s.outputDir,'ofdm_frames.jsonl'));
app=origapp.BeamformerApp(c);g=onCleanup(@()delete(app)); %#ok<NASGU>
app.startAcquisition();t=tic;
while app.Controller.FramesAccepted<8 && toc(t)<100,pause(.1);end
assert(app.Controller.FramesAccepted>=8,'No fresh clean-GUI frames.');
assert(numel(findall(groot,'Tag','RFSoCBeamformerDashboard'))==1 && isempty(findall(groot,'Tag','IntegratedCustomOfdm')));
fig=app.View.Figure;fig.Position=[10 10 1500 900];drawnow;
app.View.Controls.Pause.Value=true;
app.View.Controls.Pause.ValueChangedFcn(app.View.Controls.Pause,struct());
pause(.15);assert(isempty(app.View.Controls.Error.Text) && app.Session.Paused);
assert(all(isnan(app.View.Lines.payload.XData)) && all(isnan(app.View.Lines.timeI.XData)));
app.View.Controls.Pause.Value=false;
app.View.Controls.Pause.ValueChangedFcn(app.View.Controls.Pause,struct());
app.View.Controls.PhaseKind.Value='DAC';
app.View.Controls.PhaseKind.ValueChangedFcn(app.View.Controls.PhaseKind,struct());
app.View.Controls.phase1.Value=15;
app.View.Controls.ApplyPhase.ButtonPushedFcn(app.View.Controls.ApplyPhase,struct());
assert(isempty(app.View.Controls.Error.Text),'Control failed: %s',app.View.Controls.Error.Text);
app.View.Controls.phase1.Value=0;
app.View.Controls.ApplyPhase.ButtonPushedFcn(app.View.Controls.ApplyPhase,struct());
assert(isempty(app.View.Controls.Error.Text),'Control failed: %s',app.View.Controls.Error.Text);
app.View.Controls.ApplyRF.ButtonPushedFcn(app.View.Controls.ApplyRF,struct());
assert(isempty(app.View.Controls.Error.Text),'Control failed: %s',app.View.Controls.Error.Text);
app.View.Controls.bf.Value='MVDR';
app.View.Controls.bf.ValueChangedFcn(app.View.Controls.bf,struct());
assert(isempty(app.View.Controls.Error.Text) && strcmp(app.Session.Config.bf,'MVDR'));
app.View.Controls.bf.Value='Steering';
app.View.Controls.bf.ValueChangedFcn(app.View.Controls.bf,struct());
t=tic;last=app.Controller.FramesAccepted;
while app.Controller.FramesAccepted<last+5 && toc(t)<60,pause(.1);end
assert(app.Controller.FramesAccepted>=last+5);
a=app.Session.snapshot();assert(a.valid && a.analysis.valid);
for name=["doa","pattern","spectrum","timeI","payload","evmCurrent"]
    assert(any(isfinite(app.View.Lines.(name).YData)),'Live panel unavailable: %s',name);
end
v=app.View;v.Figure.Name='RFSoC4x2 clean GUI - LIVE HARDWARE';
% Readouts and per-stream diagnostics come from the same admitted capture.
for name=["evm","evmDb","rx","cfo","sync","bursts"]
    assert(~strcmp(v.Kpi.(name).value.Text,char(8212)),'Live readout unavailable: %s',name);
end
assert(isfield(a,'channels') && all(isfinite(a.channels.levelDbfs)) && all(isfinite(a.channels.relPhaseDeg)));
assert(~strcmp(v.Monitor.cell(4,2).Text,char(8212)) && size(v.ChannelPhase,1)>=3 && a.health.accepted>=13);
exportapp(fig,fullfile(s.outputDir,'live-six-panel.png'));
% View-only hold: the board keeps streaming; an invalid acquisition may release it.
t=tic;while isnan(v.LastSequence) && toc(t)<30,pause(.1);end
assert(~isnan(v.LastSequence),'No current frame to hold.');
shown=v.LastSequence;v.Controls.Hold.Value=true;v.Controls.Hold.ValueChangedFcn(v.Controls.Hold,struct());
last=app.Controller.FramesAccepted;t=tic;
while app.Controller.FramesAccepted<last+2 && toc(t)<30,pause(.1);end
holdKept=v.Held && v.LastSequence==shown && strcmp(v.StatePill.Text,'HELD');
assert(holdKept || any(contains(v.EventLog,'hold released')),'Hold neither kept its frame nor reported a release.');
if v.Held,v.Controls.Hold.Value=false;v.Controls.Hold.ValueChangedFcn(v.Controls.Hold,struct());end
% Diagnostic plot modes and the monitor page on live data, then a snapshot.
v.Controls.EvmMode.Value='subcarrier';v.Controls.EvmMode.ValueChangedFcn(v.Controls.EvmMode,struct());
v.Controls.TimeMode.Value='phase';v.Controls.TimeMode.ValueChangedFcn(v.Controls.TimeMode,struct());
v.Controls.PageButton(4).Value=true;v.Controls.PageButton(4).ValueChangedFcn(v.Controls.PageButton(4),struct());
last=app.Controller.FramesAccepted;t=tic;
while (app.Controller.FramesAccepted<last+2 || ~any(isfinite(v.Lines.evmSub.YData))) && toc(t)<40,pause(.1);end
assert(any(isfinite(v.Lines.evmSub.YData)) && any(isfinite(v.Lines.chPhase(2).YData)),'Live diagnostic modes empty.');
exportapp(fig,fullfile(s.outputDir,'live-diagnostics.png'));
files=v.saveSnapshot(fullfile(s.outputDir,'snapshots'));assert(~isempty(files) && isfile(files{1}));
P=v.ChannelPhase;P=angle(exp(1j*pi/180*(P-P(1,:))))*180/pi;  % re-wrapped against the first frame
phaseSpread=max(P,[],1)-min(P,[],1);
report=struct('source','LIVE RFSoC4x2 / DSP','framesAccepted',app.Controller.FramesAccepted, ...
 'holdKeptFrame',holdKept,'snapshotFiles',numel(files),'streamLevelDbfs',a.channels.levelDbfs, ...
 'streamPhaseDeg',a.channels.relPhaseDeg,'streamCoherence',a.channels.coherence, ...
 'streamPhaseSpreadDeg',phaseSpread,'streamHistoryFrames',size(v.ChannelPhase,1), ...
 'eventLog',{v.EventLog}, ...
 'errors',app.Controller.TotalErrors,'noSignal',app.Controller.NoSignalFrames, ...
 'lastSequence',a.sequence,'evmPercent',a.analysis.evmPercent,'evmDb',a.analysis.evmDb, ...
 'completeBursts',a.analysis.metricBursts,'qualifiedBursts',a.analysis.qualifiedBursts, ...
 'plotAge',a.age,'sixPanels',true,'pauseResumeAndControls',true);
app.close();delete(app);clear g;
assert(isempty(timerfindall) && isempty(findall(groot,'Tag','RFSoCBeamformerDashboard')));
fid=fopen(s.reportFile,'w');assert(fid>=0);fg=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report));
disp('GUI_REDESIGN_LIVE_COMPLETE');
end
