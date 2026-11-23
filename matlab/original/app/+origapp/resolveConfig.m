function cfg = resolveConfig(varargin)
%RESOLVECONFIG Merge a user cfg struct and/or name-value pairs over defaultConfig.
% Unknown field names are an error, so a typo cannot silently fall back.
cfg = origapp.defaultConfig();
args = varargin;
if ~isempty(args) && isstruct(args{1})
    cfg = mergeStruct(cfg, args{1});
    args(1) = [];
end
assert(mod(numel(args),2)==0, 'origapp:Config', 'Name-value pairs expected.');
for k = 1:2:numel(args)
    cfg = mergeStruct(cfg, struct(char(args{k}), {args{k+1}}));
end
assert(any(string(cfg.frontend)==["legacy","clean"]), 'origapp:Config', 'Unknown frontend.');
assert(any(string(cfg.bfEngine)==["original","reviewed"]), 'origapp:Config', ...
    'bfEngine must be "original" or "reviewed".');
assert(any(string(cfg.elementModel)==["patch","isotropic"]), 'origapp:Config', ...
    'elementModel must be "patch" or "isotropic".');
if ~isfield(cfg,'displayPeriodSeconds'),cfg.displayPeriodSeconds=0.1;end
assert(isnumeric(cfg.displayPeriodSeconds) && isscalar(cfg.displayPeriodSeconds) && cfg.displayPeriodSeconds>=0 && ...
    cfg.displayPeriodSeconds<=5,'origapp:Config','displayPeriodSeconds must be 0..5 s.');
assert(cfg.periodSeconds>0 && cfg.frameTimeoutSeconds>0 && cfg.staleSeconds>0 && ...
    cfg.maxConsecutiveErrors>=1, 'origapp:Config', 'Timing bounds must be positive.');
assert(isscalar(cfg.uiProbePeriodSeconds) && (cfg.uiProbePeriodSeconds==0 || ...
    (cfg.uiProbePeriodSeconds>=0.01 && cfg.uiProbePeriodSeconds<=1)), 'origapp:Config', ...
    'uiProbePeriodSeconds must be 0 (off) or in [0.01, 1].');
cfg.analyzer = string(cfg.analyzer);
assert(isscalar(cfg.analyzer) && any(cfg.analyzer==["integrated","vsa","both"]), 'origapp:Config', ...
    'analyzer must be "integrated", "vsa" or "both".');
assert(isstruct(cfg.ofdm), 'origapp:Config', 'cfg.ofdm must be a struct.');
d = origapp.defaultConfig(); d = d.ofdm;
for f = string(fieldnames(cfg.ofdm)).'
    assert(isfield(d, f), 'origapp:Config', 'Unknown cfg.ofdm field "%s".', f);
end
for f = string(fieldnames(d)).'
    if ~isfield(cfg.ofdm, f), cfg.ofdm.(f) = d.(f); end
end
cfg.ofdm.staleSeconds = cfg.staleSeconds;   % one freshness bound for the whole app
% VSA_rfsoc_new port fields (same limits as its App Designer controls)
for f = ["powCalibration","steeringCorrection","koef","couplingMatrix"]
    if ~isfield(cfg.calibration, f), cfg.calibration.(f) = []; end
end
assert(isscalar(cfg.sizeL) && cfg.sizeL==fix(cfg.sizeL) && cfg.sizeL>=1 && cfg.sizeL<=50, ...
    'origapp:Config', 'sizeL must be an integer in [1, 50].');
assert(isscalar(cfg.stepMU) && cfg.stepMU>=1e-31 && cfg.stepMU<=1, 'origapp:Config', ...
    'stepMU must be in [1e-31, 1].');
assert(any(string(cfg.manualMvdrFormula)==["45e726b","head"]), 'origapp:Config', ...
    'manualMvdrFormula must be "45e726b" or "head".');
assert(any(string(cfg.dacBF)==["GUI","Random","Scaning","Rescaning","Tracking","Retracking","Off"]), ...
    'origapp:Config', 'Unknown dacBF mode "%s".', string(cfg.dacBF));
assert(isnumeric(cfg.dphaseCorr) && numel(cfg.dphaseCorr)==cfg.num_elements, 'origapp:Config', ...
    'dphaseCorr needs one entry per array element.');
assert(cfg.calibrationFramesPerAngle>=1 && cfg.couplingIterations>=0, 'origapp:Config', ...
    'Calibration frame/iteration counts must be positive.');
end

function out = mergeStruct(out, in)
names = fieldnames(in);
for k = 1:numel(names)
    assert(isfield(out, names{k}), 'origapp:Config', 'Unknown config field "%s".', names{k});
    out.(names{k}) = in.(names{k});
end
end
