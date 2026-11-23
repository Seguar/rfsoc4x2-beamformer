function report=validateDemoSession(referenceMat,referenceRepo,outDir)
% Synthetic reference IQ, no hardware, sockets or real VSA.
if ~isfolder(outDir),mkdir(outDir);end
addpath(fullfile(referenceRepo,'Functions'));
d=load(referenceMat);x=d.ref125(1:32768);rng(20261116);
q={};closed=0;sends={};vendorBuffers={};shown={};showFails=false;
backend=struct('open',@()[],'close',@closeBackend,'next',@nextFrame, ...
    'availableChannels',@()true(1,4),'send',@send,'vsaSend',@sendVsa,'showEvm',@showEvm, ...
    'vsaStatus',@()struct('valid',true,'evmPercent',9,'sequence',2));
c=origapp.defaultConfig();c.backend=backend;c.originalRepoPath=string(referenceRepo);
c.visible=false;c.directOnly=false;c.dataChan=32768;c.ch=5;c.fc=3e9;c.fcAnt=3e9;
c.elementModel="isotropic";c.analyzer="integrated";c.periodSeconds=.02;c.frameTimeoutSeconds=.01;
c.vsaSetupFile=fullfile(referenceRepo,'Settings/ofdm_iq_100_16_4x2.setx');
c.ofdm=struct('setupSha256',origapp.LegacyVsaBackend.sha256(c.vsaSetupFile), ...
    'referenceMat',referenceMat,'orientation',"IplusjQ",'syncThreshold',.8);
figures0=numel(findall(groot,'Type','figure'));timers0=numel(timerfindall);
assert(isequal(origapp.DemoSession.mixerPhaseCode([-180 180 179.999 -90 90 540 12.345]), ...
    [17999 17999 17999 -9000 9000 17999 1235]),'Mixer phase codes must stay inside (-180, 180).');
% The kept steering object gives exactly what a new phased.SteeringVector gives.
ula=phased.ULA('NumElements',4,'ElementSpacing',0.0288);
for ang=[-37.5 0 12.25 60]
    ref=phased.SteeringVector('SensorArray',ula);
    assert(isequal(origapp.steeringVector(ula,5.2e9,ang),ref(5.2e9,ang)),'Cached steering vector differs at %g deg.',ang);
end
ref=phased.SteeringVector('SensorArray',ula);grid=-90:.25:90;
assert(isequal(origapp.steeringVector(ula,3e9,grid),ref(3e9,grid)),'Cached manifold differs.');
ula2=phased.ULA('NumElements',4,'ElementSpacing',0.05);ref=phased.SteeringVector('SensorArray',ula2);
assert(isequal(origapp.steeringVector(ula2,5.2e9,10),ref(5.2e9,10)),'Another geometry reused the first object.');
s=origapp.DemoSession(c);s.start();
enqueue(0,0,true);s.step();a=s.snapshot();
assert(a.valid,'First frame refused: %s',string(a.reason));
assert(a.valid && a.analysis.valid && ~isempty(a.doaSpectrum) && ~isempty(a.patternDb));
assert(numel(a.samples)==32768 && numel(a.spectrum.freqHz)>0 && isempty(sends));
assert(numel(findall(groot,'Type','figure'))==figures0,'Headless session constructed a GUI.');
% The board OLED gets the EVM of each analysed frame; a display failure is never a frame error.
assert(numel(shown)==1 && isequaln(shown{1},a.analysis.evmPercent),'EVM was not passed to the board display.');
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
% A beamformer that refuses the scene (LCMV needs a second source) rejects each
% frame with its reason but never stops acquisition.
s.configure(struct('bf','LCMV'));
for k=1:c.maxConsecutiveErrors+2
    enqueue(100+k,0,true);s.step();a=s.snapshot();
    assert(~a.valid && s.Controller.IsOpen,'LCMV stopped acquisition: %s',string(a.reason));
end
assert(contains(string(a.reason),"LCMV"),'LCMV refusal not shown: %s',string(a.reason));
assert(s.Controller.ModeRefusals==c.maxConsecutiveErrors+2 && s.Controller.ConsecutiveErrors==0);
% Original-app ranges: a source count above what 4 elements resolve, or a scan
% grid too large to hold, is refused at configure time or per frame, never fatal.
s.configure(struct('bf','Steering'));
for n=[4 5]
    refused=false;try,s.configure(struct('num',n));catch e,refused=contains(e.message,'at most 3 sources');end
    assert(refused && s.Config.num==1,'Source count %d was not refused.',n);
    enqueue(300+n,0,true);s.step();a=s.snapshot();
    assert(s.Controller.IsOpen && a.valid,'After refusing source count %d: %s',n,string(a.reason));
end
s.configure(struct('num',1));
refused=false;try,s.configure(struct('scan_res',1e-4,'scan_bw',360,'avg_factor',1000));catch e,refused=contains(e.message,'too large');end
assert(refused,'Huge scan grid was not refused.');
s.configure(struct('bf','Steering'));enqueue(400,0,true);s.step();a=s.snapshot();
assert(a.valid,'Steering after refusals: %s',string(a.reason));
n=numel(shown);errs=s.Controller.TotalErrors;
showFails=true;enqueue(401,0,true);s.step();a=s.snapshot();showFails=false;
assert(a.valid && s.Controller.TotalErrors==errs && numel(shown)==n+1,'A display failure affected acquisition.');
% A busy window makes frames stale (requested ahead, processed late): they are
% rejected and counted, never a reason to stop the session.
e0=s.Controller.ExpiredFrames;
for k=402:409,enqueue(k,3,true);s.step();a=s.snapshot();assert(~a.valid && s.Controller.IsOpen,'Stale frames stopped acquisition.');end
assert(s.Controller.ExpiredFrames==e0+8 && s.Controller.ConsecutiveErrors==0);
enqueue(410,0,true);s.step();a=s.snapshot();assert(a.valid,'No recovery after stale frames: %s',string(a.reason));
s.close();delete(s);assert(closed==1);
% Full clean frontend uses one figure and one timer, no hidden legacy app.
closed=0;c.analyzer="integrated";c.allowBoardCommands=true;
app=origapp.BeamformerApp(c);assert(numel(findall(groot,'Type','figure'))==figures0+1);
assert(numel(timerfindall)==timers0+1 && isempty(sends));
app.Controller.open();enqueue(5,0,true);app.tick();
a=app.Session.snapshot();assert(a.valid,'Frontend frame refused: %s',string(a.reason));
assert(app.View.LastSequence==5);
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
% Original ADC/DAC controls: power per DAC, SYNC mode, Nyquist zones, mirror, DAC A frequency.
V=app.View.Controls;
assert(isempty(V.Error.Text) && strcmp(sends{end},'dacPow 0/0/1/0'),'DAC B off must keep DAC A: %s',sends{end});
V.DacA.Value=false;V.DacA.ValueChangedFcn(V.DacA,struct());
assert(isempty(V.Error.Text) && strcmp(sends{end},'dacPow 0/0/0/0'));
V.Sync.Value=1;V.Sync.ValueChangedFcn(V.Sync,struct());
assert(isempty(V.Error.Text) && strcmp(sends{end},'da 1') && app.Session.Config.da==1);
V.adcEven.Value=true;V.dac1MHz.Value=2900;V.ApplyRF.ButtonPushedFcn(V.ApplyRF,struct());
assert(isempty(V.Error.Text) && strcmp(sends{end},'fc -3000/2/5100/1/2900/1'),'RF command: %s',sends{end});
assert(app.Session.Config.nyquistZone==2 && app.Session.Config.fc_d1==2900e6);
% Data amount: this backend declares no dataChan command, so the frame is cropped
% here to one complete OFDM frame; nothing is sent to the board.
n0=numel(sends);V.rows.Value=4096;V.rows.ValueChangedFcn(V.rows,struct());
assert(isempty(V.Error.Text) && app.Session.Rows==4096 && ~app.Session.BoardRows && numel(sends)==n0);
enqueue(8,0,true);app.tick();a=app.Session.snapshot();
assert(a.valid && numel(a.samples)==4096 && a.analysis.valid && a.analysis.metricBursts==1, ...
    'Reduced frame must hold one complete OFDM frame: %s',jsonencode(struct('n',numel(a.samples),'state',string(a.analysis.state),'reason',string(a.analysis.reason),'bursts',a.analysis.metricBursts)));
refused=false;try,app.Session.configure(struct('analyzer','both'));catch e,refused=string(e.identifier)=='origapp:Config';end
assert(refused,'Native VSA comparison must need the full frame.');
% Every frame is processed and recorded; the window is redrawn at most every
% displayPeriodSeconds (0.1 s): the EVM history stays per frame, without false gaps.
pause(.25);acc0=app.Controller.FramesAccepted;shown0=app.View.FramesShown;
for k=9:20,enqueue(k,0,true);app.tick();end
assert(app.Controller.FramesAccepted-acc0==12,'Frames were not all processed.');
assert(app.View.FramesShown-shown0<12,'Every frame was drawn: no display throttling.');
h=app.View.HistorySequence;b=app.View.HistoryBreak;
assert(all(ismember(9:20,h)) && ~any(b(ismember(h,10:20))),'EVM history lost frames or broke between drawn frames.');
pause(.25);enqueue(21,0,true);app.tick();
assert(app.View.LastSequence==21,'The newest frame was not drawn after the display period.');
% Pinned controls stay outside the pages; DSP is the first page.
assert(strcmp(V.PageButton(1).Text,'DSP') && isequal(V.ch.Parent,V.QuickGrid) && isequal(V.bf.Parent,V.QuickGrid) && ...
    isequal(V.doa.Parent,V.QuickGrid) && isequal(V.ang_num.Parent,V.QuickGrid) && isequal(V.rows.Parent,V.QuickGrid));
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
    function showEvm(v)
        shown{end+1}=v;
        if showFails,error('test:display','display failed');end
    end
end
