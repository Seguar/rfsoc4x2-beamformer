function report=validateDemoSession(referenceMat,referenceRepo,outDir)
% Synthetic reference IQ, no hardware, sockets or real VSA.
if ~isfolder(outDir),mkdir(outDir);end
addpath(fullfile(referenceRepo,'Functions'));
d=load(referenceMat);x=d.ref125(1:32768);rng(20261116);
q={};closed=0;sends={};vendorBuffers={};
backend=struct('open',@()[],'close',@closeBackend,'next',@nextFrame, ...
    'availableChannels',@()true(1,4),'send',@send,'vsaSend',@sendVsa, ...
    'vsaStatus',@()struct('valid',true,'evmPercent',9,'sequence',2));
c=origapp.defaultConfig();c.backend=backend;c.originalRepoPath=string(referenceRepo);
c.visible=false;c.directOnly=false;c.dataChan=32768;c.ch=5;c.fc=3e9;c.fcAnt=3e9;
c.elementModel="isotropic";c.analyzer="integrated";c.periodSeconds=.02;c.frameTimeoutSeconds=.01;
c.vsaSetupFile=fullfile(referenceRepo,'Settings/ofdm_iq_100_16_4x2.setx');
c.ofdm=struct('setupSha256',origapp.LegacyVsaBackend.sha256(c.vsaSetupFile), ...
    'referenceMat',referenceMat,'orientation',"IplusjQ",'syncThreshold',.8);
figures0=numel(findall(groot,'Type','figure'));timers0=numel(timerfindall);
s=origapp.DemoSession(c);s.start();
enqueue(0,0,true);s.step();a=s.snapshot();
assert(a.valid && a.analysis.valid && ~isempty(a.doaSpectrum) && ~isempty(a.patternDb));
assert(numel(a.samples)==32768 && numel(a.spectrum.freqHz)>0 && isempty(sends));
assert(numel(findall(groot,'Type','figure'))==figures0,'Headless session constructed a GUI.');
s.configure(struct('avg_factor',2));a=s.snapshot();assert(s.Config.avg_factor==2 && ~a.valid);
old=s.Config.doa;refused=false;
try,s.configure(struct('doa','MVDRman'));catch e,refused=string(e.identifier)=='origapp:Calibration';end
assert(refused && strcmp(s.Config.doa,old));
refused=false;try,s.configure(struct('IQcomp',true));catch e,refused=string(e.identifier)=='origapp:Calibration';end
assert(refused);
s.configure(struct('analyzer','both'));enqueue(1,0,true);s.step();a=s.snapshot();
assert(a.valid && numel(vendorBuffers)==1 && isequal(conj(vendorBuffers{1}),a.samples), ...
    'Vendor and integrated display must use the same physical buffer.');
enqueue(2,3,true);s.step();a=s.snapshot();assert(~a.valid && s.Controller.TotalErrors==1);
enqueue(3,0,true);s.step();a=s.snapshot();assert(a.valid);
enqueue(4,0,false);s.step();a=s.snapshot();assert(~a.valid && s.Controller.NoSignalFrames==1);
s.configure(struct('bf','DL MVDR','diag',1e-6,'analyzer','integrated'));
enqueue(6,0,true);same=q{1};s.step();a=s.snapshot();assert(a.valid);w1=a.weights;
s.configure(struct('diag',1e6));same.sequence=7;q={same};s.step();a=s.snapshot();assert(a.valid);
assert(norm(w1-a.weights)>1e-5,'Loading control did not reach the reviewed DSP engine.');
s.close();delete(s);assert(closed==1);
% Full clean frontend uses one figure and one timer, no hidden legacy app.
closed=0;c.analyzer="integrated";c.allowBoardCommands=true;
app=origapp.BeamformerApp(c);assert(numel(findall(groot,'Type','figure'))==figures0+1);
assert(numel(timerfindall)==timers0+1 && isempty(sends));
app.Controller.open();enqueue(5,0,true);app.tick();
a=app.Session.snapshot();assert(app.View.LastSequence==5 && a.valid);
% The snapshot carries display-only stream diagnostics and acquisition counters.
assert(isequal(a.channels.available,true(1,4)) && all(isfinite(a.channels.levelDbfs)) && ...
    abs(a.channels.relPhaseDeg(1))<1e-9 && all(a.channels.coherence>.5) && a.health.accepted>=1);
assert(contains(app.View.Kpi.rate.sub.Text,sprintf('%d accepted',app.Controller.FramesAccepted)) && app.Controller.FramesAccepted>=1 && ~strcmp(app.View.Monitor.cell(2,2).Text,'—') && ...
    ~strcmp(app.View.Kpi.sync.value.Text,'—') && any(isfinite(app.View.Lines.burstOk.XData)));
save(fullfile(outDir,'last.mat'),'a');app.View.Figure.Visible='on';app.View.Figure.Name='SYNTHETIC SESSION — reference IQ, no hardware';
drawnow;try,exportapp(app.View.Figure,fullfile(outDir,'session-reference.png'));catch,end
app.View.Controls.Pause.Value=true;app.View.Controls.Pause.ValueChangedFcn(app.View.Controls.Pause,struct());
assert(app.Session.Paused && all(isnan(app.View.Lines.timeI.XData)) && all(isnan(app.View.Lines.payload.XData)));
app.View.Controls.Pause.Value=false;app.View.Controls.Pause.ValueChangedFcn(app.View.Controls.Pause,struct());
assert(~app.Session.Paused);
app.View.Controls.PhaseKind.Value='DAC';app.View.Controls.PhaseKind.ValueChangedFcn(app.View.Controls.PhaseKind,struct());
app.View.Controls.phase1.Value=45;app.View.Controls.ApplyPhase.ButtonPushedFcn(app.View.Controls.ApplyPhase,struct());
assert(isempty(app.View.Controls.Error.Text) && strcmp(sends{end},'dphase 45/0/0/0'));
app.View.Controls.Dac.Value=false;app.View.Controls.Dac.ValueChangedFcn(app.View.Controls.Dac,struct());
assert(isempty(app.View.Controls.Error.Text) && strcmp(sends{end},'dacPow 0/0/0/0'));
delete(app);
assert(closed==1 && numel(findall(groot,'Type','figure'))==figures0 && numel(timerfindall)==timers0);
report=struct('label','SYNTHETIC SESSION/VIEW — no hardware', 'headlessCreatesNoFigures',true, ...
    'sameCombinedBuffer',true,'staleAndMissingClear',true,'manualModesRefuseWithoutCalibration',true, ...
    'singleWindow',true,'leakedFigures',0,'leakedTimers',0);
fid=fopen(fullfile(outDir,'session-validation.json'),'w');fprintf(fid,'%s\n',jsonencode(report));fclose(fid);
disp('DEMO_SESSION_COMPLETE');
    function f=nextFrame(~)
        f=[];if isempty(q),return,end
        f=q{1};q(1)=[];f.timestamp=origapp.Controller.nowSeconds()-f.timestamp;
    end
    function enqueue(seq,age,signal)
        z=repmat(conj(x)*2^15*.03/max(abs(x)),1,4)+2*(randn(numel(x),4)+1j*randn(numel(x),4));
        q{end+1}=struct('samples',z,'sequence',seq,'timestamp',age,'availableChannels',true(1,4), ...
            'signalChannels',repmat(logical(signal),1,4),'boundaryFree',true);
    end
    function closeBackend(),closed=closed+1;end
    function send(line),sends{end+1}=line;end
    function sendVsa(z),vendorBuffers{end+1}=z;end
end
