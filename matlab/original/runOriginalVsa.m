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
assert(cfg.directOnly && ~cfg.allowBoardCommands && ~cfg.sendInitialTuning && ...
    cfg.dataChan==131072 && cfg.fsRfsoc==125e6 && cfg.staleSeconds==2, ...
    'origapp:Profile','Native legacy launch requires the reviewed direct-cable profile.');
backendCfg=s.backend;
for name={'orientation','expectSource','logFile','rawDir'}
    if isfield(backendCfg,name{1}), backendCfg.(name{1})=string(backendCfg.(name{1})); end
end
backend=origapp.LegacyVsaBackend(backendCfg);
backendGuard=onCleanup(@()delete(backend));
app=[]; guard=onCleanup(@closeApp);
try
    app=VSA_rfsoc_refactor(cfgWithBackend(cfg,backend));
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
    if isvalid(app), report.uiFrames=app.Controller.FramesAccepted; report.uiErrors=app.Controller.TotalErrors; end
    closeApp(); backend.close();
    fid=fopen(s.session.reportFile,'w'); assert(fid>=0); fileGuard=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(report));
    disp('ORIGINAL_NATIVE_VSA_COMPLETE');
catch err
    closeApp(); backend.close(); rethrow(err);
end
    function closeApp()
        if ~isempty(app) && isvalid(app), delete(app); end
    end
end
function cfg=cfgWithBackend(cfg,backend)
cfg.backend=backend;
end
