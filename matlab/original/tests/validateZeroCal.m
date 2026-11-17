function report=validateZeroCal(referenceMat,referenceRepo,outDir)
% Synthetic: converter path settings and the common-feed 0 deg calibration
% against a fake board that applies ADC mixer phases and QMC gains to four
% streams of one reference (as the splitter feed). No hardware or sockets.
if ~isfolder(outDir),mkdir(outDir);end
addpath(fullfile(referenceRepo,'Functions'));
d=load(referenceMat);x=d.ref125(1:32768);rng(20261117);
% Fake board: stream k = feed * gain_k * exp(1j*(offset_k - phase_k)) (a mixer phase
% offset +p turns the stream by -p, as measured on the RFSoC4x2), noise added.
offset=[0 12 80 7];level=[0 1.1 1.4 0.5];
st=struct('adc_phase',[-90 -90 90 90],'dac_phase',[0 0],'adc_gain',1.99*ones(1,4), ...
    'adc_iq_phase',zeros(1,4),'adc_attenuation',zeros(1,4),'dac_gain',[1.99 1.99], ...
    'dac_iq_phase',[0 0],'dac_current_ua',[40500 40500],'revision',0);
p0=st.adc_phase;seq=0;sends={};closed=0;
caps=struct('commands',["fc","phase","dphase","dacPow","da","dataStream","phasec","dphasec","again", ...
    "dgain","aiqphase","diqphase","adsa","dvop"],'txArrayElements',0,'uploadDac',false);
backend=struct('open',@()[],'close',@()[],'next',@nextFrame,'availableChannels',@()true(1,4), ...
    'send',@send,'capabilities',@()caps,'controlStatus',@status);
c=origapp.defaultConfig();c.backend=backend;c.originalRepoPath=string(referenceRepo);
c.visible=false;c.directOnly=false;c.dataChan=32768;c.ch=5;c.fc=3e9;c.fcAnt=3e9;c.fc_d0=3e9;c.fc_d1=3e9;
c.elementModel="isotropic";c.analyzer="integrated";c.allowBoardCommands=true;c.dacPow=[1 0 0 0];
c.periodSeconds=.02;c.frameTimeoutSeconds=.01;
c.vsaSetupFile=fullfile(referenceRepo,'Settings/ofdm_iq_100_16_4x2.setx');
c.ofdm=struct('setupSha256',origapp.LegacyVsaBackend.sha256(c.vsaSetupFile), ...
    'referenceMat',referenceMat,'orientation',"IplusjQ",'syncThreshold',.8);
app=origapp.BeamformerApp(c);stop(app.AcqTimer);guard=onCleanup(@()delete(app));
app.startAcquisition();stop(app.AcqTimer);
V=app.View.Controls;
% The board's path state reaches the view; the full setting list is offered.
V.PhaseKind.Value='ADC';V.PhaseKind.ValueChangedFcn(V.PhaseKind,struct());
assert(isequal(app.Session.Paths.ADC,[-90 -90 90 90]) && V.phase1.Value==-90 && V.phase3.Value==90, ...
    'Board ADC phases must reach the view.');
assert(numel(V.PhaseKind.ItemsData)==8,'All converter settings must be offered.');
assert(isequal(V.ch.Items,{'Combined beam','ADC_D','ADC_C','ADC_B','ADC_A'}),'Output names');
% Path settings in display units -> board command units.
setPath('adcGain',[1.99 1.5 1.2 1]);assert(strcmp(lastCmd(),'again 199/150/120/100'),lastCmd());
setPath('dacCurrent',[20.25 0 40.5 0]);assert(strcmp(lastCmd(),'dvop 20250/0/40500/0'),lastCmd());
setPath('adcAtten',[0 3 0 27]);assert(strcmp(lastCmd(),'adsa 0/3/0/27'),lastCmd());
setPath('dacIq',[1.5 0 -2.25 0]);assert(strcmp(lastCmd(),'diqphase 150/0/-225/0'),lastCmd());
setPath('ADC',[-90 -90.25 90 90]);assert(strcmp(lastCmd(),'phasec -9000/-9025/9000/9000'),lastCmd());
assert(isequal(V.phase2.Value,-90.25) && strcmp(V.phase1Label.Text,'ADC_D') && strcmp(V.phase4Label.Text,'ADC_A'));
setPath('adcGain',[1.99 1.99 1.99 1.99]);setPath('ADC',[-90 -90 90 90]);
% Before calibration the streams disagree; "Set 0" equalises them.
for k=1:3,tick();end
V.Zero.ButtonPushedFcn(V.Zero,struct());
assert(app.Session.ZeroCal.state=="running");
for k=1:40
    tick();
    if app.Session.ZeroCal.state=="done",break,end
end
z=app.Session.ZeroCal;
assert(z.state=="done",'Calibration did not finish.');
assert(max(abs(z.residualDeg))<0.5 && max(abs(z.levelDb))<0.1,'Residual %s deg / %s dB',mat2str(z.residualDeg,3),mat2str(z.levelDb,3));
% phases moved by the stream offsets, weakest stream (ADC_D) keeps the largest gain
assert(max(abs(mod(st.adc_phase-p0-offset+180,360)-180))<0.3,'Phases %s',mat2str(st.adc_phase,4));
assert(abs(st.adc_gain(1)-1.99)<1e-9 && all(st.adc_gain(2:4)<1.99));
assert(contains(V.ZeroState.Text,'0° set'),V.ZeroState.Text);
% DOA of the combined beam now reads 0 for the common feed
tick();tick();a=app.Session.snapshot();
assert(a.valid && abs(a.angles(1))<=1,'Model angle %.1f after calibration.',a.angles(1));
% An RF change invalidates the 0 deg calibration.
V.ApplyRF.ButtonPushedFcn(V.ApplyRF,struct());
assert(app.Session.ZeroCal.state=="changed" && contains(V.ZeroState.Text,'again'));
report=struct('label','SYNTHETIC ZERO CALIBRATION — no hardware','residualDeg',z.residualDeg,'levelDb',z.levelDb, ...
    'phases',st.adc_phase,'gains',st.adc_gain,'modelAngleDeg',a.angles(1));
fid=fopen(fullfile(outDir,'zero-validation.json'),'w');fprintf(fid,'%s\n',jsonencode(report));fclose(fid);
disp('ZERO_CAL_COMPLETE');
    function setPath(kind,values)
        V.PhaseKind.Value=kind;V.PhaseKind.ValueChangedFcn(V.PhaseKind,struct());
        for j=1:4
            h=V.(sprintf('phase%d',j));
            if strcmp(h.Visible,'on'),h.Value=values(j);end   % DAC settings show DAC_B and DAC_A only
        end
        V.ApplyPhase.ButtonPushedFcn(V.ApplyPhase,struct());
        assert(isempty(V.Error.Text),'Refused: %s',V.Error.Text);
    end
    function s=status()
        s=st;   % nested: the current fake board state (an anonymous function would copy it)
    end
    function c=lastCmd()
        % last setting command (each is followed by a status read-back)
        c=sends{end};k=numel(sends);
        while strcmp(c,'status') && k>1,k=k-1;c=sends{k};end
    end
    function tick()
        app.tick();
    end
    function f=nextFrame(~)
        rot=exp(1j*(offset-(st.adc_phase-p0))*pi/180);g=10.^(level/20).*st.adc_gain/1.99;
        % host orientation (I - jQ, the conjugated reference); the measured stream
        % phase follows offset - (mixer phase change), as on the board
        iq=conj(x*2^15*.03/max(abs(x)))*(g.*rot)+2*(randn(numel(x),4)+1j*randn(numel(x),4));
        f=struct('samples',iq,'sequence',seq,'timestamp',origapp.Controller.nowSeconds(), ...
            'availableChannels',true(1,4),'signalChannels',true(1,4),'boundaryFree',true);seq=seq+1;
    end
    function send(line)
        sends{end+1}=line;
        for part=strsplit(line,'#')
            t=strsplit(strtrim(part{1}),' ');if numel(t)<2,continue,end
            v=str2double(strsplit(t{2},'/'));
            switch t{1}
                case 'phasec',st.adc_phase=v/100;
                case 'again',st.adc_gain=v/100;
                case 'adsa',st.adc_attenuation=v;
                case 'diqphase',st.dac_iq_phase=v([1 3])/100;
                case 'dvop',st.dac_current_ua=v([1 3]);
            end
        end
    end
end
