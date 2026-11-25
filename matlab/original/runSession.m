function report=runSession(settingsPath,opt)
%RUNSESSION One hardware session of the beamformer window from a settings
% JSON written by RFSoCBeamformer (app, backend and session fields). The
% board session (helper lifetime, DAC off) is owned by the caller.
if nargin<2,opt=struct();end
% opt: seconds, snapshot folder, theme, rows, calibrate. All optional.
if ~isdeployed,root=fileparts(mfilename('fullpath')); addpath(fullfile(root,'app'),fileparts(root));end
s=jsondecode(fileread(settingsPath));
assert(s.session.maxSeconds>0 && s.session.maxSeconds<=14400,'origapp:Bound','Invalid session duration.');
cfg=origapp.defaultConfig(); names=fieldnames(s.app);
for k=1:numel(names)
    assert(isfield(cfg,names{k}),'origapp:Config','Unknown app field %s',names{k});
    cfg.(names{k})=s.app.(names{k});
end
if isfield(opt,'theme') && ~isempty(opt.theme),cfg.theme=string(opt.theme);end
limit=s.session.maxSeconds;
if isfield(opt,'seconds') && isfinite(opt.seconds),limit=min(limit,opt.seconds);end
if isdeployed
    if string(cfg.elementModel)=="patch"
        % The Antenna Toolbox patch element cannot be deployed. The compiled
        % application uses isotropic model elements and says so in the scope.
        cfg.elementModel="isotropic";cfg.arrayLabel=string(cfg.arrayLabel)+" · isotropic elements";
    end
end
window4=isfield(s.backend,'wireMode') && string(s.backend.wireMode)=="window4";
cal=cfg.calibration;
if window4
    % Four-stream same-capture window: array DOA/pattern through the explicit
    % model, labelled as a common-feed diagnostic, uncalibrated, no coupling comp.
    assert(~cfg.directOnly && (~cfg.allowBoardCommands || (isfield(s.backend,'controlPort') && s.backend.controlPort>0)) && ...
        cfg.dataChan==32768 && cfg.fsRfsoc==125e6 && cfg.staleSeconds==2 && ~cfg.coupComp && ...
        contains(string(cfg.arrayLabel),"common-feed diagnostic") && isempty(cal.couplingMatrix) && ...
        isempty(cal.steeringCorrection) && isempty(cal.powCalibration), ...
        'origapp:Profile','Native window4 launch requires the reviewed common-feed diagnostic profile.');
else
    assert(cfg.directOnly && ~cfg.allowBoardCommands && ...
        cfg.dataChan==131072 && cfg.fsRfsoc==125e6 && cfg.staleSeconds==2, ...
        'origapp:Profile','A one-stream session requires the reviewed direct-cable profile.');
end
backendCfg=s.backend;
for name={'orientation','expectSource','logFile','rawDir','wireMode'}
    if isfield(backendCfg,name{1}), backendCfg.(name{1})=string(backendCfg.(name{1})); end
end
backend=origapp.LegacyVsaBackend(backendCfg);
backendGuard=onCleanup(@()delete(backend));
app=[];
try
    app=origapp.BeamformerApp(cfgWithBackend(cfg,backend));
    guard=onCleanup(@()closeAppHandle(app)); %#ok<NASGU> value-captured handle, no nested-workspace teardown
    rows=NaN;if isfield(opt,'rows'),rows=opt.rows;end
    if isfinite(rows),app.setRows(rows);end
    app.startAcquisition();
    assert(app.Controller.IsOpen,'origapp:Startup','The board stream did not open.');
    started=tic;firstFrame=NaN;firstCount=0;
    while isvalid(app) && ~backend.Ended && toc(started)<limit && ~isfile(s.session.stopFile)
        pause(.1);
        if isvalid(app) && isnan(firstFrame) && app.Controller.FramesAccepted>0
            firstFrame=toc(started);firstCount=app.Controller.FramesAccepted;
            if isfield(opt,'calibrate') && strcmpi(char(string(opt.calibrate)),'on')
                app.calibrateZero();   % option "calibrate on": Set 0 deg once frames arrive
            end
        end
        if isvalid(app) && ~app.Controller.IsOpen
            assert(app.Controller.ConsecutiveErrors<cfg.maxConsecutiveErrors, ...
                'origapp:Stopped','Acquisition stopped after repeated errors: %s',app.Controller.LastError);
            break;
        end
    end
    report=struct('deliveredFrames',numel(backend.Delivered),'ended',backend.Ended,'source',backend.SourceTag);
    if isvalid(app) && isfield(opt,'snapshot') && ~isempty(opt.snapshot) && app.View.isOpen()
        report.snapshot=app.View.saveSnapshot(fullfile(char(opt.snapshot),'snapshots'));
    end
    if isvalid(app)
        c=app.Controller; report.uiFrames=c.FramesAccepted; report.uiErrors=c.TotalErrors;
        report.uiBoundaryFrames=c.BoundaryFrames; report.uiExpiredFrames=c.ExpiredFrames;
        report.uiNoSignalFrames=c.NoSignalFrames; report.uiLastError=c.LastError;
        % Accepted frames per second after the first one (excludes start-up).
        report.displayRateHz=(c.FramesAccepted-firstCount)/max(toc(started)-firstFrame,eps);
        report.rows=app.Session.Rows;report.boardRows=app.Session.BoardRows;
        z=app.Session.ZeroCal;if isfield(z,'acc'),z=rmfield(z,'acc');end
        report.zeroCal=z;
        last=app.Session.snapshot();   % not "s": that holds the launcher settings
        if last.valid && ~isempty(last.angles),report.modelAngleDeg=last.angles;end
    end
    closeAppHandle(app); backend.close();
    fid=fopen(s.session.reportFile,'w'); assert(fid>=0); fileGuard=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(report));
    disp('SESSION_COMPLETE');
catch err
    closeAppHandle(app); backend.close(); rethrow(err);
end
end
function closeAppHandle(app)
if ~isempty(app) && isvalid(app), delete(app); end
end
function cfg=cfgWithBackend(cfg,backend)
cfg.backend=backend;
end
