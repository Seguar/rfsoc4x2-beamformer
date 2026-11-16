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
app.View.Figure.Name='RFSoC4x2 clean GUI - LIVE HARDWARE';
exportapp(fig,fullfile(s.outputDir,'live-six-panel.png'));
report=struct('source','LIVE RFSoC4x2 / DSP','framesAccepted',app.Controller.FramesAccepted, ...
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
