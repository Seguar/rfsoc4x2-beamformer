function validateWindowAdmission()
% Controller admission independent of VSA enable; no board, UI or VSA.
cfg=origapp.defaultConfig(); cfg.directOnly=false; cfg.dataChan=16;
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
for s={struct(),struct('candidate','fallback'),struct('candidate','none'),struct('candidate',[])}
    assert(~origapp.LegacyVsaBackend.validWindowSummary(s{1}),'Invalid selector summary accepted.');
end
disp('WINDOW_ADMISSION_PASS');
    function f=nextFrame(~)
        i=i+1;
        f=struct('samples',complex(ones(16,4)), ...
            'timestamp',origapp.Controller.nowSeconds(), 'sequence',i, ...
            'availableChannels',true(1,4),'signalChannels',true(1,4),'boundaryFree',fields{i});
    end
end
