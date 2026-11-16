function report=RFSoCBeamformer(varargin)
%RFSOCBEAMFORMER Standalone entry point of the focused beamformer window.
%   RFSoCBeamformer                 simulated four-element array, no hardware
%   RFSoCBeamformer demo            the same
%   RFSoCBeamformer <settings.json> hardware session; the JSON is the one the
%                                   launcher tools/run_original_vsa.py writes,
%                                   and the launcher owns the board helper
% Optional name/value pairs after the first argument (text when deployed):
%   seconds N      close after N seconds (demo default: until the window closes)
%   snapshot DIR   save one snapshot (PNG + MAT) into DIR before closing
%   theme NAME     dark | light
%   interferer DB  demo only: add a simulated interferer DB below the wanted source
% Compiled with matlab/standalone/buildStandalone.m. A compiled window has no
% console, so a start-up failure is shown in a dialog and written to a log.
report=struct();
try
    mode='demo';rest=varargin;
    if ~isempty(rest),mode=char(string(rest{1}));rest=rest(2:end);end
    opt=struct('seconds',Inf,'snapshot','','theme','','interferer',-Inf);
    assert(mod(numel(rest),2)==0,'origapp:Standalone','Options are name/value pairs.');
    for k=1:2:numel(rest)
        name=lower(regexprep(char(string(rest{k})),'^-+',''));
        assert(isfield(opt,name),'origapp:Standalone','Unknown option "%s".',name);
        value=rest{k+1};
        if any(strcmp(name,{'seconds','interferer'})) && ~isnumeric(value),value=str2double(value);end
        opt.(name)=value;
    end
    assert(isnumeric(opt.seconds) && isscalar(opt.seconds) && opt.seconds>0,'origapp:Standalone','seconds must be positive.');
    if ~isdeployed
        root=fileparts(fileparts(mfilename('fullpath')));
        addpath(fullfile(root,'original'),fullfile(root,'original','app'),root);
    end
    if any(strcmpi(mode,{'demo','--demo','-demo'}))
        report=runDemo(opt);
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

function report=runDemo(opt)
% Simulation only: synthetic frames through the real session, DSP and view.
[setx,ref]=origapp.demoResources();
cfg=origapp.defaultConfig();
cfg.frontend="clean";cfg.visible=true;cfg.directOnly=false;cfg.allowBoardCommands=false;
cfg.dataChan=32768;cfg.ch=5;cfg.fc=3e9;cfg.fcAnt=3e9;cfg.fc_d0=3e9;cfg.fc_d1=3e9;cfg.dacPow=[1 0 0 0];
cfg.elementModel="isotropic";cfg.analyzer="integrated";cfg.periodSeconds=.05;cfg.frameTimeoutSeconds=.05;
cfg.avg_factor=3;cfg.staleSeconds=5;
cfg.arrayLabel='SIMULATION, no hardware / array model (ULA d=lambda/2 @3 GHz)';
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
