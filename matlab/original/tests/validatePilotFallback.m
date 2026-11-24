function validatePilotFallback(referenceMat,referenceRepo)
%VALIDATEPILOTFALLBACK OFDM pilot MVDR without a usable preamble keeps the
% frame on screen (2026-11-24): the steering vector at the estimated
% direction replaces the pilot weights, the frame stays valid, and the OFDM
% analysis reports no lock. Frames: noise only, then a strong CW only.
here=fileparts(mfilename('fullpath'));addpath(fullfile(fileparts(here),'app'));
addpath(fullfile(referenceRepo,'Functions'));
n=4096;rng(11);k=0;
X={(randn(n,4)+1i*randn(n,4))*30, ...
   exp(1i*2*pi*0.0325*(0:n-1)')*exp(1i*[0 1 2 3])*3000+(randn(n,4)+1i*randn(n,4))*30};
c=origapp.defaultConfig();c.originalRepoPath=string(referenceRepo);c.visible=false;c.directOnly=false;
c.dataChan=n;c.ch=5;c.fc=5.2e9;c.fcAnt=5.2e9;c.elementModel="isotropic";c.analyzer="integrated";
c.bf='OFDM pilot MVDR';c.doa='MUSIC';c.num=1;c.ang_num=3;
c.vsaSetupFile=fullfile(referenceRepo,'Settings/ofdm_iq_100_16_4x2.setx');
c.ofdm=struct('setupSha256',origapp.LegacyVsaBackend.sha256(c.vsaSetupFile),'referenceMat',referenceMat, ...
    'orientation',"IplusjQ",'syncThreshold',.8);
c.backend=struct('open',@()[],'close',@()[],'next',@next,'availableChannels',@()true(1,4));
s=origapp.DemoSession(c);s.start();
for j=1:numel(X)
    s.step();a=s.snapshot();
    assert(a.valid,'fallback:valid','frame %d refused: %s',j,a.reason);
    assert(~isempty(a.patternDb) && all(isfinite(a.weights)),'fallback:plots','frame %d has no pattern/weights',j);
    assert(~a.analysis.valid,'fallback:lock','frame %d: OFDM analysis claims lock on no signal',j);
    fprintf('frame %d shown, analysis: %s\n',j,string(a.analysis.reason));
end
delete(s);
disp('PILOT_FALLBACK_OK')
    function f=next(~)
        k=k+1;f=struct('sequence',k,'samples',X{k},'timestamp',origapp.Controller.nowSeconds(), ...
            'availableChannels',true(1,4),'signalChannels',false(1,4),'boundaryFree',true);
    end
end
