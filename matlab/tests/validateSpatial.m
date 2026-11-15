function report=validateSpatial()
% SIMULATED geometry: independent signed-angle and array-null controls.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
cfg=rfsoc.defaultConfig(); cfg.directOnly=false;
cfg.spacingM=299792458/cfg.fcHz/2; cfg.sourceCount=2;
cfg.scanStepDeg=0.25;
rng(841,'twister'); n=16384;
angles=[18 -34]; a=rfsoc.steering(cfg,angles);
s=(randn(n,2)+1j*randn(n,2))/sqrt(2);
x=s*a.'+.02*(randn(n,4)+1j*randn(n,4));
w=a(:,1)/4; baseline=ones(4,1)/4;
for method=["Beamscan" "MVDR" "MUSIC"]
    cfg.doaMethod=method;
    sp=rfsoc.spatialView(x,w,a(:,1),cfg,baseline);
    assert(sp.available && abs(sp.wantedAngleDeg-18)<=cfg.scanStepDeg);
    assert(all(isfinite(sp.spectrumDb)) && abs(max(sp.patternDb))<1e-10);
    if method~="Beamscan"
        for angle=angles
            assert(min(abs(sp.peakAnglesDeg-angle))<=1,'DOA sign or peak-resolution failure.');
        end
    end
    % Four half-wave broadside elements have exact nulls at +/-30 degrees.
    for nullAngle=[-30 30]
        [~,index]=min(abs(sp.anglesDeg-nullAngle));
        assert(sp.baselinePatternDb(index)<-70,'Broadside null is incorrect.');
    end
    % Independent scalar receive sum establishes the pattern conjugation.
    response=zeros(size(sp.anglesDeg));
    for k=1:numel(response)
        av=exp(-1j*pi*(0:3).'*sind(sp.anglesDeg(k)));
        response(k)=abs(sum(conj(w).*av))^2;
    end
    expected=10*log10(max(response/max(response),1e-8));
    assert(max(abs(expected-sp.patternDb))<1e-8,'Pattern convention mismatch.');
end
cfg.tracking=false;
sp=rfsoc.spatialView(x,w,a(:,1),cfg); assert(abs(sp.wantedAngleDeg-18)<.5);
cfg.directOnly=true;
sp=rfsoc.spatialView(x,w,a(:,1),cfg);
assert(~sp.available && isempty(sp.anglesDeg) && isnan(sp.wantedAngleDeg));
cfg.directOnly=false; cfg.spacingM=NaN; rejected=false;
try, rfsoc.spatialView(x,w,a(:,1),cfg); catch e, rejected=strcmp(e.identifier,'rfsoc:Geometry'); end
assert(rejected,'Unknown spacing produced a physical angle.');
cfg.spacingM=299792458/cfg.fcHz/2;
cfg.manifoldAnglesDeg=-45:.25:45;
cfg.manifold=rfsoc.steering(cfg,cfg.manifoldAnglesDeg);
sp=rfsoc.spatialView(x,w,a(:,1),cfg);
assert(min(sp.anglesDeg)>=-45 && max(sp.anglesDeg)<=45,'Extrapolated calibrated scan.');
report=struct('passed',true,'source',"SIMULATED four-element half-wave ULA", ...
    'methods',["Beamscan" "MVDR" "MUSIC"],'signedAnglesDeg',angles, ...
    'nullAnglesDeg',[-30 30],'physicalDoaValidated',false);
disp('RFSOC_SPATIAL_PASS');
end
