function result = processFrame(x,cfg,ref,fixedWeights)
% Pure processing: no sockets, instruments, UI handles or persistent state.
if nargin<4, fixedWeights=[]; end
assert(isequal(size(cfg.channelCorrection),[4 4]) && ...
    all(isfinite(cfg.channelCorrection),'all'),'rfsoc:Calibration','Invalid channel correction.');
inputRms=sqrt(mean(abs(x).^2,1));
x=x*cfg.channelCorrection;
if cfg.directOnly
    keep=x(:,cfg.activeChannel); x(:)=0; x(:,cfg.activeChannel)=keep;
end
[aligned,tracking,a]=rfsoc.acquire(x,ref,cfg.fsHz);
training=aligned(1:ref.train*(ref.nfft+ref.cp),:);
angleDeg=cfg.angleDeg;
if ~cfg.directOnly && cfg.tracking
    grid=-89:cfg.scanStepDeg:89; manifold=rfsoc.steering(cfg,grid);
    score=abs(manifold'*a).^2./sum(abs(manifold).^2,1).';
    [~,best]=max(score); angleDeg=grid(best);
end
cfg.angleDeg=angleDeg;
if cfg.directOnly
    w=zeros(4,1); w(cfg.activeChannel)=1;
    info=struct('algorithm',"Single channel",'converged',true);
else
    % Pilot vector identifies wanted DAC even if a jammer has greater power.
    wanted=a;
    if ~cfg.tracking, wanted=rfsoc.steering(cfg,cfg.angleDeg); end
    [~,w,info]=rfsoc.beamform(training,cfg,wanted);
end
selected=aligned*conj(w);
[metric,constellation]=rfsoc.demodulate(selected,ref);
baselineMetric=[];
if ~isempty(fixedWeights)
    baselineMetric=rfsoc.demodulate(aligned*conj(fixedWeights),ref);
end
result=struct('metric',metric,'baselineMetric',baselineMetric, ...
    'constellation',constellation,'weights',w,'beamformer',info, ...
    'tracking',tracking,'angleDeg',angleDeg,'pilotManifold',a, ...
    'inputRmsDbfs',20*log10(inputRms/32768), ...
    'vsaSignal',selected/32768,'status',"locked");
end
