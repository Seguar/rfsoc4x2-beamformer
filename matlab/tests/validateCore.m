function report = validateCore(fixturePath,outputPath)
% Independent Python-to-MATLAB acquisition/EVM and spatial constraint checks.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
fixture=load(fixturePath); ref=rfsoc.loadReference(fixturePath);
cfg=rfsoc.defaultConfig();
cfg.directOnly=false; cfg.tracking=false; cfg.spacingM=299792458/cfg.fcHz/2;
cfg.angleDeg=20; cfg.nullAnglesDeg=-35; cfg.maxIterations=200;
% Compare independently implemented MATLAB against frozen Python calculations.
[aligned,tracking]=rfsoc.acquire(fixture.capture,ref,cfg.fsHz);
[w,~]=rfsoc.pilotWeights(aligned(1:ref.train*(ref.nfft+ref.cp),:),ref.wave(1:ref.train*(ref.nfft+ref.cp)));
[metric,~]=rfsoc.demodulate(aligned*conj(w),ref);
assert(abs(metric.evmPercent-fixture.pythonEvmPercent)<1e-6,'Cross-language EVM mismatch.');
assert(abs(metric.ber-fixture.pythonBer)<1e-12,'Cross-language BER mismatch.');
assert(abs(tracking.cfoHz-fixture.pythonCfoHz)<1e-5,'Cross-language CFO mismatch.');
% Noise-only negative control must not retain a prior lock or EVM.
failed=false;
try
    rfsoc.acquire(fixture.noise,ref,cfg.fsHz);
catch exception
    failed=strcmp(exception.identifier,'rfsoc:Lock');
end
assert(failed,'Noise-only negative control unexpectedly acquired.');
% Each named algorithm is exercised, never silently substituted by MVDR.
a=rfsoc.steering(cfg,cfg.angleDeg); jammer=rfsoc.steering(cfg,cfg.nullAnglesDeg);
rng(17); n=8192;
s=(randn(n,1)+1j*randn(n,1))/sqrt(2);
j=(randn(n,1)+1j*randn(n,1))/sqrt(2);
x=s*a.'+10*j*jammer.'+0.1*(randn(n,4)+1j*randn(n,4));
rows=struct([]);
for algorithm=rfsoc.algorithmNames()
    cfg.algorithm=algorithm;
    [y,w,info]=rfsoc.beamform(x,cfg,a);
    assert(all(isfinite(y)) && numel(w)==4,'Invalid output: %s',algorithm);
    if ~any(algorithm==["Without","QCB","RAB PC"])
        assert(abs(w'*a-1)<1e-7,'Conjugation/desired-gain failure: %s',algorithm);
    end
    if algorithm=="LCMV", assert(abs(w'*jammer)<1e-7,'LCMV null constraint failed.'); end
    rows(end+1)=struct('algorithm',algorithm,'desiredGain',abs(w'*a), ...
        'jammerGain',abs(w'*jammer),'iterations',info.iterations); %#ok<AGROW>
end
assert(rows(3).jammerGain<rows(1).jammerGain/10,'MVDR failed jammer suppression.');
% Geometry and invalid constraints cannot be hidden behind a fallback.
bad=cfg; bad.spacingM=NaN; rejected=false;
try, rfsoc.steering(bad,0); catch, rejected=true; end
assert(rejected,'Unmeasured geometry produced a physical angle.');
cfg.algorithm="LCMV"; cfg.nullAnglesDeg=cfg.angleDeg; rejected=false;
try, rfsoc.beamform(x,cfg,a); catch, rejected=true; end
assert(rejected,'Dependent LCMV constraints accepted.');
report=struct('passed',true,'source',"SIMULATION / Python differential fixture", ...
    'evmPercent',metric.evmPercent,'evmDb',metric.evmDb,'ber',metric.ber, ...
    'cfoHz',tracking.cfoHz,'algorithms',rows);
if nargin>1
    fid=fopen(outputPath,'w'); cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(report));
end
disp('RFSOC_MATLAB_CORE_PASS');
end
