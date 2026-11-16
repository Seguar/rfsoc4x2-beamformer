function report=runOriginalVsa(settingsPath)
% Original App Designer UI + owned native VSA. Hardware lifetime is launcher-owned.
root=fileparts(mfilename('fullpath')); addpath(fullfile(root,'app'),fileparts(root));
s=jsondecode(fileread(settingsPath));
assert(s.session.maxSeconds>0 && s.session.maxSeconds<=14400,'origapp:Bound','Invalid session duration.');
cfg=origapp.defaultConfig(); names=fieldnames(s.app);
for k=1:numel(names)
    assert(isfield(cfg,names{k}),'origapp:Config','Unknown app field %s',names{k});
    cfg.(names{k})=s.app.(names{k});
end
window4=isfield(s.backend,'wireMode') && string(s.backend.wireMode)=="window4";
cal=cfg.calibration;
if window4
    % Four-stream same-capture window: array DOA/pattern through the explicit
    % model, labelled as a common-feed diagnostic, uncalibrated, no coupling comp.
    assert(~cfg.directOnly && (~cfg.allowBoardCommands || (isfield(s.backend,'controlPort') && s.backend.controlPort>0)) && ~cfg.sendInitialTuning && ...
        cfg.dataChan==32768 && cfg.fsRfsoc==125e6 && cfg.staleSeconds==2 && ~cfg.coupComp && ...
        contains(string(cfg.arrayLabel),"common-feed diagnostic") && isempty(cal.couplingMatrix) && ...
        isempty(cal.steeringCorrection) && isempty(cal.powCalibration), ...
        'origapp:Profile','Native window4 launch requires the reviewed common-feed diagnostic profile.');
else
    assert(cfg.directOnly && ~cfg.allowBoardCommands && ~cfg.sendInitialTuning && ...
        cfg.dataChan==131072 && cfg.fsRfsoc==125e6 && cfg.staleSeconds==2, ...
        'origapp:Profile','Native legacy launch requires the reviewed direct-cable profile.');
end
backendCfg=s.backend;
for name={'orientation','expectSource','logFile','rawDir','wireMode'}
    if isfield(backendCfg,name{1}), backendCfg.(name{1})=string(backendCfg.(name{1})); end
end
backend=origapp.LegacyVsaBackend(backendCfg);
backendGuard=onCleanup(@()delete(backend));
app=[];
try
    app=VSA_rfsoc_refactor(cfgWithBackend(cfg,backend));
    if window4
        app.dataChanEditField.Enable='off';
        app.dataChanEditField.Tooltip='The active waveform profile has a fixed frame size; restart to change it.';
        app.RecalibrateADCsButton.Enable='off';
        app.RecalibrateADCsButton.Tooltip='Legacy automatic ADC calibration is unavailable in this controlled session.';
    end
    guard=onCleanup(@()closeAppHandle(app)); %#ok<NASGU> value-captured handle, no nested-workspace teardown
    app.startAcquisition();
    assert(app.Controller.IsOpen,'origapp:Startup','Original app backend did not open.');
    started=tic;
    while isvalid(app) && ~backend.Ended && toc(started)<s.session.maxSeconds && ~isfile(s.session.stopFile)
        pause(.1);
        if isvalid(app) && ~app.Controller.IsOpen
            assert(app.Controller.ConsecutiveErrors<cfg.maxConsecutiveErrors, ...
                'origapp:Stopped','Acquisition stopped after repeated errors: %s',app.Controller.LastError);
            break;
        end
    end
    report=struct('deliveredFrames',numel(backend.Delivered),'vsaFrames',numel(backend.Log), ...
        'ended',backend.Ended,'source',backend.SourceTag,'metrics',backend.Log);
    if isvalid(app)
        c=app.Controller; report.uiFrames=c.FramesAccepted; report.uiErrors=c.TotalErrors;
        report.uiBoundaryFrames=c.BoundaryFrames; report.uiExpiredFrames=c.ExpiredFrames;
        report.uiNoSignalFrames=c.NoSignalFrames; report.uiLastError=c.LastError;
    end
    closeAppHandle(app); backend.close();
    fid=fopen(s.session.reportFile,'w'); assert(fid>=0); fileGuard=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(report));
    disp('ORIGINAL_NATIVE_VSA_COMPLETE');
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
