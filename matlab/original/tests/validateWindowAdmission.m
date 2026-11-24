function validateWindowAdmission()
% Controller admission independent of VSA enable; no board, UI or VSA.
cfg=origapp.defaultConfig(); cfg.directOnly=false; cfg.dataChan=16;
cfg.outputDir=string(tempname); mkdir(cfg.outputDir);
folderGuard=onCleanup(@()rmdir(cfg.outputDir,'s')); %#ok<NASGU>
i=0; fields={false,1,true};
cfg.backend=struct('open',@()[],'close',@()[], 'next',@nextFrame, ...
    'availableChannels',@()true(1,4));
c=origapp.Controller(cfg); cleanup=onCleanup(@()delete(c)); c.open();
for k=1:2
    rejected=false;
    try, c.acquire(); catch e
        if k==1, rejected=strcmp(e.identifier,'origapp:Boundary');
        else, rejected=strcmp(e.identifier,'origapp:Channels'); end
    end
    assert(rejected,'Invalid boundary flag admitted to DOA with VSA disabled.');
end
[f,~]=c.acquire(); assert(f.boundaryFree && f.sequence==3,'Clean recovery failed.');
assert(~c.recordFailure(MException('origapp:NoSignal','missing stream')) && ...
    c.NoSignalFrames==1 && c.ConsecutiveErrors==0, 'Missing signal stopped capture.');
assert(~c.recordFailure(MException('origapp:Boundary','wrap')) && c.BoundaryFrames==1);
assert(~c.recordFailure(MException('origapp:Expired','stale draw')) && c.ExpiredFrames==1);
assert(origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','after-wrap')));
for s={struct(),struct('candidate','fallback'),struct('candidate',[])}
    assert(~origapp.LegacyVsaBackend.validWindowSummary(s{1}),'Invalid selector summary accepted.');
end
% Nothing locked ("none"; reduced also "held": last alignment) is shown unverified (2026-11-24).
assert(origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','none')) && ...
    origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','none'),true) && ...
    origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','held'),true),'Unlocked window refused.');
assert(~origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','held')),'Full window accepted a reduced-only label.');
% Reduced windows: the reduced selector's searched ("fast") and reused ("fixed")
% offsets are accepted, the full selector's names and fallbacks are not.
assert(origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','fast'),true) && ...
    origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','fixed'),true),'Reduced window refused.');
for s={struct('candidate','after-wrap'),struct('candidate','fallback'),struct()}
    assert(~origapp.LegacyVsaBackend.validWindowSummary(s{1},true),'Invalid reduced summary accepted.');
end
assert(~origapp.LegacyVsaBackend.validWindowSummary(struct('candidate','fixed')),'Reduced name accepted for a full window.');
records=splitlines(strtrim(fileread(fullfile(cfg.outputDir,'errors.jsonl'))));
assert(numel(records)==3,'Each failure type must be persisted.');
entry=jsondecode(records{3});
assert(string(entry.identifier)=="origapp:Expired" && entry.lastReceivedSequence==3 && ...
    isfield(entry,'stack') && isfield(entry,'timestamp'),'Error diagnostics incomplete.');
% A burst of the same rejection writes one line per second, not one per frame;
% the counter still counts every frame and the next line says how many were left out.
b0=c.BoundaryFrames;
for k=1:20,c.recordFailure(MException('origapp:Boundary','wrap'));end
assert(c.BoundaryFrames==b0+20,'Rejections not all counted.');
records=splitlines(strtrim(fileread(fullfile(cfg.outputDir,'errors.jsonl'))));
assert(numel(records)<=5,'A burst of rejections wrote one line per frame (%d lines).',numel(records));
pause(1.05);c.recordFailure(MException('origapp:Boundary','wrap'));
records=splitlines(strtrim(fileread(fullfile(cfg.outputDir,'errors.jsonl'))));last=jsondecode(records{end});
assert(string(last.identifier)=="origapp:Boundary" && last.notWrittenSincePrevious>=19,'Left-out count missing.');
disp('WINDOW_ADMISSION_PASS');
    function f=nextFrame(~)
        i=i+1;
        f=struct('samples',complex(ones(16,4)), ...
            'timestamp',origapp.Controller.nowSeconds(), 'sequence',i, ...
            'availableChannels',true(1,4),'signalChannels',true(1,4),'boundaryFree',fields{i});
    end
end
