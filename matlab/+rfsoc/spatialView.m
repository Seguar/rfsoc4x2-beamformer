function view = spatialView(training,w,wanted,cfg,fixedWeights)
% Spatial diagnostics share the beamformer's calibrated receive convention.
% Spectral peaks may include interferers; the pilot identifies the wanted DAC.
if nargin<5, fixedWeights=[]; end
view=struct('available',false,'reason',"single-channel conducted mode", ...
    'anglesDeg',[],'spectrumDb',[],'peakAnglesDeg',[], ...
    'wantedAngleDeg',NaN,'wantedScoreDb',[], ...
    'patternDb',[],'baselinePatternDb',[],'method',string(cfg.doaMethod));
if cfg.directOnly, return; end
validateattributes(cfg.scanStepDeg,{'numeric'},{'scalar','finite','positive','<=',10});
validateattributes(cfg.sourceCount,{'numeric'},{'scalar','integer','>=',1,'<=',3});
angles=-89:cfg.scanStepDeg:89;
if ~isempty(cfg.manifold)
    angles=angles(angles>=min(cfg.manifoldAnglesDeg) & angles<=max(cfg.manifoldAnglesDeg));
end
assert(numel(angles)>=3,'rfsoc:Geometry','Insufficient calibrated scan coverage.');
a=rfsoc.steering(cfg,angles); normA=sum(abs(a).^2,1);
assert(all(normA>0),'rfsoc:Manifold','Zero calibrated steering vector.');
assert(size(training,2)==4 && ~isempty(training) && all(isfinite(training),'all'), ...
    'rfsoc:Input','DOA requires finite N-by-4 training samples.');
r=training.'*conj(training)/size(training,1); r=(r+r')/2;
scale=max(real(trace(r))/4,eps); r=r/scale;
switch string(cfg.doaMethod)
    case "Beamscan"
        spectrum=real(sum(conj(a).*(r*a),1))./normA;
    case "MVDR"
        loaded=r+max(cfg.loading,1e-8)*eye(4);
        spectrum=1./max(real(sum(conj(a).*(loaded\a),1)),eps);
    case "MUSIC"
        [u,d]=eig(r,'vector'); [~,order]=sort(real(d),'descend');
        noise=u(:,order(cfg.sourceCount+1:end));
        spectrum=normA./max(sum(abs(noise'*a).^2,1),eps);
    otherwise
        error('rfsoc:DoaMethod','Unknown DOA method: %s',cfg.doaMethod);
end
wanted=wanted(:);
score=abs(a'*wanted).^2./(normA(:)*max(real(wanted'*wanted),eps));
[~,wantedIndex]=max(score);
% Keep actual local maxima, without manufacturing sourceCount distinct peaks.
indices=find(spectrum(2:end-1)>=spectrum(1:end-2) & ...
    spectrum(2:end-1)>spectrum(3:end))+1;
if spectrum(1)>spectrum(2), indices=[1 indices]; end
if spectrum(end)>spectrum(end-1), indices=[indices numel(angles)]; end
[~,order]=sort(spectrum(indices),'descend');
indices=indices(order(1:min(cfg.sourceCount,numel(order))));
view.available=true; view.reason="geometry model; physical calibration required";
view.anglesDeg=angles; view.spectrumDb=normalizedDb(spectrum);
view.peakAnglesDeg=angles(indices); view.wantedAngleDeg=angles(wantedIndex);
view.wantedScoreDb=normalizedDb(score.');
view.patternDb=normalizedDb(abs(w(:)'*a).^2);
if ~isempty(fixedWeights)
    view.baselinePatternDb=normalizedDb(abs(fixedWeights(:)'*a).^2);
end
end
function db=normalizedDb(power)
power=max(real(power),0);
db=10*log10(max(power/max(max(power),eps),1e-8));
end
