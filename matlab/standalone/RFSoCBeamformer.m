function report=RFSoCBeamformer(varargin)
%RFSOCBEAMFORMER Standalone entry point of the focused beamformer window.
%   RFSoCBeamformer                 find the board and start a hardware session:
%                                   USB first, then Ethernet; if no board
%                                   answers, a window asks for its IP address
%                                   (or starts the simulation)
%   RFSoCBeamformer demo            simulated four-element array, no hardware
%   RFSoCBeamformer <settings.json> hardware session owned by the launcher
%                                   tools/run_original_vsa.py (it writes the JSON)
% Optional name/value pairs (text when deployed):
%   board ADDRESS  skip the search and use this board address
%   dialog off     never open the address window; fail instead (automation)
%   seconds N      close after N seconds (default: until the window closes)
%   snapshot DIR   save one snapshot (PNG + MAT) into DIR before closing
%   theme NAME     dark | light
%   interferer DB  demo only: add a simulated interferer DB below the wanted source
% The automatic mode needs the session service on the board (one-time
% tools/install_board_service.py). Compiled with matlab/standalone/buildStandalone.m.
% A compiled window has no console, so a start-up failure is shown in a dialog
% and written to a log.
report=struct();
try
    opt=struct('seconds',Inf,'snapshot','','theme','','interferer',-Inf,'board','','dialog','on','rows',NaN,'record','','calibrate','off');
    optionName=@(x)lower(regexprep(char(string(x)),'^-+',''));
    mode='auto';rest=varargin;
    if ~isempty(rest) && ~isfield(opt,optionName(rest{1})),mode=char(string(rest{1}));rest=rest(2:end);end
    assert(mod(numel(rest),2)==0,'origapp:Standalone','Options are name/value pairs.');
    for k=1:2:numel(rest)
        name=optionName(rest{k});
        assert(isfield(opt,name),'origapp:Standalone','Unknown option "%s".',name);
        value=rest{k+1};
        if any(strcmp(name,{'seconds','interferer','rows'})) && ~isnumeric(value),value=str2double(value);end
        opt.(name)=value;
    end
    assert(isnumeric(opt.seconds) && isscalar(opt.seconds) && opt.seconds>0,'origapp:Standalone','seconds must be positive.');
    assert(any(strcmpi(char(string(opt.dialog)),{'on','off'})),'origapp:Standalone','dialog is on or off.');
    if ~isdeployed
        root=fileparts(fileparts(mfilename('fullpath')));
        addpath(fullfile(root,'original'),fullfile(root,'original','app'),root);
    end
    if any(strcmpi(mode,{'demo','--demo','-demo'}))
        report=runDemo(opt);
    elseif strcmpi(mode,'auto')
        report=runAuto(opt);
    else
        assert(isfile(mode),'origapp:Standalone','Settings file not found: %s',mode);
        report=runOriginalVsa(mode,opt);
    end
catch err
    text=getReport(err,'extended','hyperlinks','off'); %#ok<NASGU>
    if isdeployed
        try
            fid=fopen(fullfile(tempdir,'RFSoCBeamformer-error.log'),'w');fprintf(fid,'%s\n',text);fclose(fid);
        catch
        end
        h=errordlg(sprintf('%s\n\nDetails: %s',err.message,fullfile(tempdir,'RFSoCBeamformer-error.log')),'RFSoC Beamformer');
        uiwait(h);
    else
        rethrow(err);
    end
end
if nargout==0,clear report,end
end

function report=runAuto(opt)
% Board search: USB, then Ethernet, then the address window. Only a failed
% connection returns to the window; a failure of a running session is an error.
interactive=strcmpi(char(string(opt.dialog)),'on');
host=string(opt.board);note="";
if strlength(host)==0
    found=origapp.BoardLink.find();host=found.host;
    note="No board answered ("+strjoin(found.tried,", ")+").";
    if strlength(found.hint)>0,note=note+newline+newline+found.hint;end
else
    origapp.BoardLink.parseAddress(host);
end
while true
    if strlength(host)==0
        assert(interactive,'origapp:BoardConnect','%s',char(note));
        choice=origapp.boardDialog(note+newline+newline+"Enter the board address, or run the simulation without hardware.", ...
            origapp.BoardLink.lastAddress());
        switch choice.action
            case "demo",report=runDemo(opt);return
            case "cancel",report=struct('mode','cancelled');return
        end
        host=choice.host;
    end
    try
        session=connectBoard(host,opt);
    catch err
        if ~interactive || ~any(strcmp(err.identifier,{'origapp:BoardConnect','origapp:BoardCancelled'})),rethrow(err);end
        note="Board at "+host+": "+string(err.message);host="";
        continue
    end
    report=runBoard(session,opt);
    return
end
end

function session=connectBoard(host,opt)
% Start the board session behind a small progress window (the FPGA image
% load and converter synchronisation take a while).
link=origapp.BoardLink(host);
fig=uifigure('Name','RFSoC Beamformer','Position',[0 0 440 150],'Resize','off');movegui(fig,'center');
figGuard=onCleanup(@()delete(fig(isvalid(fig))));
dialog=uiprogressdlg(fig,'Title','Connecting to the board','Message',"Board at "+link.Host, ...
    'Indeterminate','on','Cancelable','on','CancelText','Cancel');
drawnow;
seconds=origapp.BoardLink.MAX_SECONDS;
if isfinite(opt.seconds),seconds=min(seconds,ceil(opt.seconds)+120);end
try
    ready=link.start(seconds,@(m)progress(dialog,link.Host,m));
catch err
    delete(link);rethrow(err);
end
if ~strcmp(char(link.Host),char(origapp.BoardLink.USB))
    address=link.Host;
    if link.Port~=origapp.BoardLink.PORT,address=address+":"+link.Port;end
    origapp.BoardLink.lastAddress(address);
end
session=struct('link',link,'ready',ready,'seconds',seconds);
end

function ok=progress(dialog,host,m)
text="Board at "+host;
if isfield(m,'step'),text=text+newline+string(m.step);end
if isfield(m,'elapsed') && m.elapsed>0,text=text+sprintf(' (%d s)',round(m.elapsed));end
dialog.Message=text;drawnow;
ok=~dialog.CancelRequested;
end

function report=runBoard(session,opt)
% Hardware session through the board service: the same reviewed four-stream
% profile and session loop as the launcher path (runOriginalVsa), with the
% session connection as the owner of the board helper.
link=session.link;linkGuard=onCleanup(@()delete(link));
[setx,ref]=origapp.demoResources();
base=getenv('LOCALAPPDATA');if isempty(base),base=tempdir;end
runs=fullfile(base,'RFSoCBeamformer','runs');
out=fullfile(runs,char(datetime('now','Format','yyyyMMdd-HHmmss')));
if ~isfolder(out),mkdir(out);end
old=dir(runs);old=old([old.isdir] & ~startsWith({old.name},'.'));
[~,order]=sort({old.name});old=old(order);
for k=1:numel(old)-10
    try,rmdir(fullfile(runs,old(k).name),'s');catch,end
end
sha=char(origapp.LegacyVsaBackend.sha256(setx));
host=char(string(session.ready.host));
% RF start state as reported by the board (older services: the 3 GHz profile).
rf=struct('rf_mhz',3000,'adc_nyquist_zone',2,'dac_nyquist_zone',1);
for f=string(fieldnames(rf)).'
    if isfield(session.ready,f),rf.(f)=double(session.ready.(f));end
end
fc=rf.rf_mhz*1e6;
app=struct('frontend','clean','visible',true,'directOnly',false,'allowBoardCommands',true,'sendInitialTuning',false, ...
    'da',2,'vsaSetupFile',setx,'vsa',1,'ch',5,'dataChan',32768,'fc',fc,'fc_d0',fc,'fc_d1',fc,'fcAnt',fc, ...
    'adcMirror',1,'nyquistZone',rf.adc_nyquist_zone,'nyquistZone_d0',rf.dac_nyquist_zone, ...
    'nyquistZone_d1',rf.dac_nyquist_zone,'dacPow',[1 0 0 0],'fsRfsoc',125e6, ...
    'staleSeconds',2,'periodSeconds',.02,'frameTimeoutSeconds',.05,'outputDir',out,'analyzer','integrated', ...
    'cutterAllowed',false,'elementModel','isotropic', ...
    'arrayLabel',sprintf('common-feed diagnostic / array model (ULA d=lambda/2 @%g GHz) · isotropic elements',fc/1e9), ...
    'ofdm',struct('setupSha256',sha,'referenceMat',ref,'orientation','IplusjQ','syncThreshold',.8, ...
        'lockThreshold',.3,'staleSeconds',2));
if ~isdeployed && isfolder(fullfile(fileparts(fileparts(setx)),'Functions')),app.originalRepoPath=fileparts(fileparts(setx));end
backend=struct('host',host,'port',session.ready.stream_port,'referenceMat',ref,'orientation','IplusjQ', ...
    'dllPath','unused-integrated','setupPath',setx,'setupSha256',sha,'vsaPort',60685,'visible',true, ...
    'allowContinuous',true,'staleSeconds',2,'expectSource','rfsoc4x2-hardware','logFile','','rawDir','', ...
    'frameLogFile','','controlPort',session.ready.control_port,'controlLogFile',fullfile(out,'commands.jsonl'), ...
    'wireMode','window4','prefetchWithoutVsa',true);
if ~isempty(opt.record)
    % Diagnostics: every received window (raw int16), one JSON line per frame
    % from the receiver and one per demodulated buffer. Measurements: keep them
    % out of the repository.
    rec=char(opt.record);if ~isfolder(rec),mkdir(rec);end
    backend.rawDir=rec;backend.frameLogFile=fullfile(rec,'frames.jsonl');
    app.ofdm.logFile=fullfile(rec,'ofdm.jsonl');
end
settings=struct('app',app,'backend',backend,'session',struct('maxSeconds',session.seconds, ...
    'stopFile',fullfile(out,'STOP'),'reportFile',fullfile(out,'result.json')));
settingsPath=fullfile(out,'frontend.json');
fid=fopen(settingsPath,'w');assert(fid>=0,'origapp:Standalone','Cannot write %s',settingsPath);
fprintf(fid,'%s\n',jsonencode(settings));fclose(fid);
failure=[];
try
    report=runOriginalVsa(settingsPath,opt);
catch failure
    report=struct();
end
report.mode='HARDWARE';report.host=host;report.runFolder=out;
report.board=link.finish(150);
if ~isempty(failure),rethrow(failure);end
assert(isfield(report.board,'dac_off_commanded') && logical(report.board.dac_off_commanded), ...
    'origapp:Shutdown',['The board did not confirm that the DAC outputs were switched off (%s). ' ...
    'Check the board before connecting anything to its outputs.'],char(string(report.board.reason)));
end

function report=runDemo(opt)
% Simulation only: synthetic frames through the real session, DSP and view.
[setx,ref]=origapp.demoResources();
cfg=origapp.defaultConfig();
cfg.frontend="clean";cfg.visible=true;cfg.directOnly=false;cfg.allowBoardCommands=false;
cfg.dataChan=32768;cfg.ch=5;cfg.fc=5.2e9;cfg.fcAnt=5.2e9;cfg.fc_d0=5.2e9;cfg.fc_d1=5.2e9;cfg.dacPow=[1 0 0 0];
cfg.nyquistZone=1;cfg.nyquistZone_d0=2;cfg.nyquistZone_d1=2;cfg.adcMirror=1;
cfg.elementModel="isotropic";cfg.analyzer="integrated";cfg.periodSeconds=.05;cfg.frameTimeoutSeconds=.05;
cfg.avg_factor=3;cfg.staleSeconds=5;
cfg.arrayLabel='SIMULATION, no hardware / array model (ULA d=lambda/2 @5.2 GHz)';
cfg.vsaSetupFile=setx;
cfg.ofdm=struct('setupSha256',origapp.LegacyVsaBackend.sha256(setx),'referenceMat',ref, ...
    'orientation',"IplusjQ",'syncThreshold',.8);
if ~isdeployed,cfg.originalRepoPath=string(fileparts(fileparts(setx)));end
if ~isempty(opt.theme),cfg.theme=string(opt.theme);end
if ~isempty(opt.snapshot),cfg.outputDir=string(opt.snapshot);end
assert(isnumeric(opt.interferer) && isscalar(opt.interferer) && ~isnan(opt.interferer) && opt.interferer<=0, ...
    'origapp:Standalone','interferer is a level in dB at or below the wanted source.');
sim=origapp.simulatedArrayBackend(ref,struct('fcHz',cfg.fc,'samples',cfg.dataChan,'interfererDb',opt.interferer));
cfg.backend=sim.backend;
app=origapp.BeamformerApp(cfg);guard=onCleanup(@()delete(app)); %#ok<NASGU>
app.View.Figure.Name='RFSoC 4x2 Beamformer — SIMULATION, no hardware';
if isfinite(opt.rows),app.setRows(opt.rows);end
app.startAcquisition();started=tic;
while isvalid(app) && app.View.isOpen() && toc(started)<opt.seconds
    pause(.1);
end
report=struct('mode','SIMULATION, no hardware','framesAccepted',app.Controller.FramesAccepted, ...
    'errors',app.Controller.TotalErrors,'snapshot',{{}});
if isvalid(app) && app.View.isOpen()
    a=app.Session.snapshot();t=sim.truth();
    report.simulatedAngleDeg=t.angleDeg;report.interfererDb=t.interfererDb;
    if a.valid
        report.modelAngleDeg=a.angles;report.evmPercent=a.analysis.evmPercent;
        report.analysisValid=logical(a.analysis.valid);
    end
    if ~isempty(opt.snapshot),report.snapshot=app.View.saveSnapshot(fullfile(char(opt.snapshot),'snapshots'));end
end
end
