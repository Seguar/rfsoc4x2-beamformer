function a = steering(cfg, anglesDeg)
% a is the physical receive vector: X = s*a.'; y = X*conj(w).
if ~isempty(cfg.manifold)
    assert(size(cfg.manifold,1)==4 && ...
        size(cfg.manifold,2)==numel(cfg.manifoldAnglesDeg), ...
        'rfsoc:Manifold','Expected 4-by-angle calibration manifold.');
    a = interp1(cfg.manifoldAnglesDeg,cfg.manifold.',anglesDeg,'linear').';
    assert(all(isfinite(a),'all'),'rfsoc:Manifold','Angle outside calibration.');
else
    assert(isfinite(cfg.spacingM) && cfg.spacingM>0, ...
        'rfsoc:Geometry','Set measured element spacing before angular processing.');
    a = exp(-1j*2*pi*cfg.fcHz/299792458*cfg.spacingM*(0:3).'*sind(anglesDeg(:).'));
end
end
