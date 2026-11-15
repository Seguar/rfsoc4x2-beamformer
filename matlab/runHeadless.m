function report = runHeadless(cfg)
% Finite real-stream validation. Every received frame has a log record.
assert(isfinite(cfg.maxFrames) && cfg.maxFrames>=1 && cfg.maxFrames==fix(cfg.maxFrames), ...
    'rfsoc:Count','Headless runs need a finite positive maxFrames.');
assert(strlength(cfg.logPath)>0,'rfsoc:Log','Supply a private log path.');
ref=rfsoc.loadReference(cfg.referencePath); source=[]; vsa=[];

% Start VSA before connecting: a connected producer has a bounded send timeout.
if cfg.useVsa
    vsa=rfsoc.VsaSession(cfg.vsa);
    vsaGuard=onCleanup(@()delete(vsa)); %#ok<NASGU>
end
source=rfsoc.FrameSource(cfg);
sourceGuard=onCleanup(@()delete(source)); %#ok<NASGU>
locked=0; vsaValid=0; vsaWarnings=0; evm=nan(1,cfg.maxFrames);
fid=fopen(cfg.logPath,'a'); assert(fid>=0,'rfsoc:Log','Cannot open metrics log.');
fileGuard=onCleanup(@()fclose(fid));
for k=1:cfg.maxFrames
    frame=source.next();
    record=struct('sequence',char(string(frame.sequence)),'source',"LIVE ADC", ...
        'status',"unavailable",'skippedDisplayFrames',frame.skippedDisplayFrames);
    try
        result=rfsoc.processFrame(frame.samples,cfg,ref);
        record.status=result.status; record.metric=result.metric;
        record.tracking=result.tracking; record.inputRmsDbfs=result.inputRmsDbfs;
        locked=locked+1; evm(k)=result.metric.evmPercent;
        if ~isempty(vsa)
            record.vsa=vsa.sendFrame(result.vsaSignal);
            if isfield(record.vsa.quality,'unclassifiedBits') && record.vsa.quality.unclassifiedBits~=0
                vsaWarnings=vsaWarnings+1;
            end
            vsaValid=vsaValid+double(record.vsa.fresh && isfinite(record.vsa.evmPercent));
        end
    catch exception
        record.reason=exception.message; record.errorIdentifier=exception.identifier;
    end
    fprintf(fid,'%s\n',jsonencode(record));
end
report=struct('frames',cfg.maxFrames,'lockedFrames',locked, ...
    'allFramesLocked',locked==cfg.maxFrames,'evmPercent',evm, ...
    'vsaRequested',cfg.useVsa,'validVsaFrames',vsaValid,'vsaWarningFrames',vsaWarnings);
disp(jsonencode(report));
assert(report.allFramesLocked,'rfsoc:Validation','Some frames failed; inspect ALL log records.');
assert(~cfg.useVsa || vsaValid==cfg.maxFrames, ...
    'rfsoc:VsaValidation','Some VSA measurements are unavailable; inspect ALL log records.');
disp('RFSOC_MATLAB_LIVE_PASS');
end
