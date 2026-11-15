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
assert(any(string(cfg.bfEngine)==["original","reviewed"]), 'origapp:Config', ...
    'bfEngine must be "original" or "reviewed".');
assert(any(string(cfg.elementModel)==["patch","isotropic"]), 'origapp:Config', ...
    'elementModel must be "patch" or "isotropic".');
assert(cfg.periodSeconds>0 && cfg.frameTimeoutSeconds>0 && cfg.staleSeconds>0 && ...
    cfg.maxConsecutiveErrors>=1, 'origapp:Config', 'Timing bounds must be positive.');
end

function out = mergeStruct(out, in)
names = fieldnames(in);
for k = 1:numel(names)
    assert(isfield(out, names{k}), 'origapp:Config', 'Unknown config field "%s".', names{k});
    out.(names{k}) = in.(names{k});
end
end
