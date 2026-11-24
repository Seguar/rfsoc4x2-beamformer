function validateStreamGate
%VALIDATESTREAMGATE Controller per-stream lock gate (origapp.Controller.acquire).
% Lock is reported, never a reason to drop a frame (2026-11-24): every frame
% passes; unlockedChannels lists streams without lock and deadChannels the
% near-silent ones among them.
here=fileparts(mfilename('fullpath'));addpath(fullfile(fileparts(here),'app'));
n=4096;rng(7);
sig=@(a)(randn(n,1)+1i*randn(n,1))*a;
frames={};
% 1 all locked
frames{end+1}=mk([sig(100) sig(100) sig(100) sig(100)],true(1,4));
% 2 stream 0 jammed: 10x the power, no lock
frames{end+1}=mk([sig(1000) sig(100) sig(100) sig(100)],[false true true true]);
% 3 stream 2 dead: noise only, 30 dB below, no lock
frames{end+1}=mk([sig(100) sig(100) sig(3) sig(100)],[true true false true]);
% 4 blank: nothing locks
frames{end+1}=mk([sig(3) sig(3) sig(3) sig(3)],false(1,4));
% 5 weak but alive stream without lock (12 dB below): not dead, passes
frames{end+1}=mk([sig(25) sig(100) sig(100) sig(100)],[false true true true]);
k=0;
cfg=origapp.defaultConfig();cfg.dataChan=n;cfg.directOnly=false;cfg.staleSeconds=5;
cfg.backend=struct('next',@next,'close',@()[]);
c=origapp.Controller(cfg);
expect={'ok','ok','ok','ok','ok'};
unl={false(1,4),[true false false false],[false false true false],true(1,4),[true false false false]};
dd={false(1,4),false(1,4),[false false true false],false(1,4),false(1,4)};
for j=1:numel(frames)
    try
        f=c.acquire();got='ok';
        assert(isequal(f.unlockedChannels,unl{j}),'gate:mask','frame %d: unlocked mask %s',j,mat2str(f.unlockedChannels));
        assert(isequal(f.deadChannels,dd{j}),'gate:dead','frame %d: dead mask %s',j,mat2str(f.deadChannels));
    catch e
        got=e.identifier;
    end
    assert(strcmp(got,expect{j}),'gate:result','frame %d: expected %s, got %s',j,expect{j},got);
    fprintf('frame %d: %s\n',j,got);
end
disp('STREAM_GATE_OK')
    function f=next(~)
        k=k+1;f=frames{k};f.sequence=k;f.timestamp=origapp.Controller.nowSeconds();
    end
end
function f=mk(x,sc)
f=struct('samples',x,'availableChannels',true(1,4),'signalChannels',sc,'boundaryFree',true);
end
