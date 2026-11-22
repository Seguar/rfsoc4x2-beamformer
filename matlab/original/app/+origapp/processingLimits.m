function L = processingLimits(cfg)
%PROCESSINGLIMITS Accepted range of every numeric processing setting for cfg.
% One source for the GUI field limits (a value outside cannot be entered) and
% for DemoSession.configure (which refuses the same values from scripts).
% Each entry is [low high]; entries in L.open hold [lowOpen highOpen] when a
% bound itself is excluded. Ranges that depend on other settings (scan step vs
% width, averaging vs grid size, alpha/gamma vs beamformer) follow cfg.
f = @(name, default) fieldOr(cfg, name, default);
L.maxCells = 2e7;                       % scan points x averaged frames held in memory
L.num = [1 f('num_elements', 4) - 1];   % an N-element array resolves at most N-1 sources
bw = f('scan_bw', 120); res = f('scan_res', 1); avg = f('avg_factor', 10);
L.scan_bw = [max(2, res) min(360, res*(floor(L.maxCells/avg) - 1))];
L.scan_res = [max(1e-4, bw/(floor(L.maxCells/avg) - 1)) bw];
L.avg_factor = [1 max(1, floor(L.maxCells/(floor(bw/res) + 1)))];
L.bwMHz = [1 f('fsRfsoc', 125e6)/1e6];  % signal bandwidth up to the receive rate
L.diag = [0 Inf]; L.iter = [1 Inf]; L.mis_ang = [0.1 20]; L.alg_scan_res = [0.001 10];
L.alpha = [0 Inf]; L.gamma = [0 Inf];
L.open = struct('alpha', [false false], 'gamma', [false false]);
switch string(f('bf', 'Steering'))
    case "DL ITER MVDR", L.alpha = [0 2]; L.open.alpha = [true true];   % uncertainty in (0,2)
    case "QCB", L.open.gamma = [true false];                            % positive loading
end
end

function v = fieldOr(s, name, default)
v = default;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), v = double(s.(name)); end
if strcmp(name, 'bf') && isstruct(s) && isfield(s, name), v = s.(name); end
end
