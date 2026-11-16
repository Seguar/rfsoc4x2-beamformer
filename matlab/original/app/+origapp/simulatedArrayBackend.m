function sim=simulatedArrayBackend(referenceMat,opt)
%SIMULATEDARRAYBACKEND Synthetic four-element source for the standalone demo.
% SIMULATION ONLY. The transmitted reference loop arrives from a model angle
% that sweeps slowly and receiver noise is added. opt.interfererDb (relative
% to the wanted source, default -Inf = off) adds an uncorrelated source at
% opt.interfererDeg; the session's single-source DOA estimate may then lock
% to either source, as it would with real data. Frames use the wire orientation of the
% hardware backend (conjugated), int16 scale, N-by-4. Nothing here measures
% a board, an antenna or a real interferer.
%   sim.backend   struct of handles for cfg.backend (open/close/next/...)
%   sim.truth()   the angles used for the most recent frame
if nargin<2,opt=struct();end
d=struct('fcHz',3e9,'samples',32768,'frameSeconds',.5,'sweepDeg',20,'sweepSeconds',40, ...
    'interfererDeg',-50,'interfererDb',-Inf,'noiseRms',2,'peak',983,'seed',20261116);
names=fieldnames(d);
for k=1:numel(names),if ~isfield(opt,names{k}),opt.(names{k})=d.(names{k});end,end
s=load(referenceMat,'ref125');x=s.ref125(:);x=x/max(abs(x));
assert(numel(x)>=opt.samples,'origapp:Simulation','Reference is shorter than one frame.');
lambda=physconst('LightSpeed')/opt.fcHz;
ula=phased.ULA('NumElements',4,'ElementSpacing',lambda/2);
steer=phased.SteeringVector('SensorArray',ula);
st=RandStream('mt19937ar','Seed',opt.seed);
isOpen=false;sequence=0;last=-Inf;started=tic;current=struct('angleDeg',NaN,'interfererDeg',opt.interfererDeg,'interfererDb',opt.interfererDb);
sim=struct('backend',struct('open',@openSource,'close',@closeSource,'next',@nextFrame, ...
    'availableChannels',@()true(1,4)),'truth',@truth);
    function t=truth(),t=current;end
    function openSource(),isOpen=true;started=tic;last=-Inf;end
    function closeSource(),isOpen=false;end
    function f=nextFrame(~)
        f=[];
        if ~isOpen || toc(started)-last<opt.frameSeconds,return,end
        last=toc(started);
        theta=opt.sweepDeg*sin(2*pi*last/opt.sweepSeconds);
        n=opt.samples;start=randi(st,numel(x)-n+1);
        wanted=opt.peak*x(start:start+n-1);
        jam=zeros(n,1);
        if isfinite(opt.interfererDb)
            jam=opt.peak*10^(opt.interfererDb/20)*sqrt(mean(abs(x).^2))* ...
                (randn(st,n,1)+1j*randn(st,n,1))/sqrt(2);
        end
        a=steer(opt.fcHz,[theta;0]);b=steer(opt.fcHz,[opt.interfererDeg;0]);
        % Conjugated steering: with the conjugated wire orientation below, the
        % session's model angle equals the simulated one.
        z=wanted*a'+jam*b'+opt.noiseRms*(randn(st,n,4)+1j*randn(st,n,4))/sqrt(2);
        current.angleDeg=theta;
        f=struct('samples',conj(z),'sequence',sequence,'timestamp',origapp.Controller.nowSeconds(), ...
            'availableChannels',true(1,4),'signalChannels',true(1,4),'boundaryFree',true);
        sequence=sequence+1;
    end
end
