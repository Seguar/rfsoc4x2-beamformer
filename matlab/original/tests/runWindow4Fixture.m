function results = runWindow4Fixture(port, referenceMat, originalRepoPath, outDir, appPath, mode)
%RUNWINDOW4FIXTURE v3 (window4) transport + array UI fixture against the
% OFFLINE fake stream tests/fake_window4_server.py (source "offline-fake",
% NOT hardware), started by the caller with the scenario of the chosen mode:
%   mode "vsa-off" (default):
%     wave:20,wave:20,wave:-35,blank,dead:2,stale,badsha,wave:10,
%     wrapfirst:16,wrapfirst:3000,wraplast:8,wraplast:3000,loss:32740:300,loss:16000:300,
%     fallback,nocand,badjson,clean,slips,loss:16000:1,wave:-35
%   mode "vsa-stub":
%     wave:20,wave:20,wrapfirst:3000,wave:20,wraplast:8,fallback,wave:20,wave:20,wave:-35
% Checks: known steered angles through the real LegacyVsaBackend decode
% (bounded inflate, window SHA) and the app's DOA/pattern; blank, dead-stream,
% stale (repeated capture SHA) and corrupted-window frames are rejected and
% clear the plots. Board-misjudgement items (wrapfirst/wraplast/loss and the
% selector-summary faults fallback/nocand/badjson) claim a good candidate, so
% only the host check can refuse them: they must be refused before Controller
% admission, VSA and the plots (titles "unavailable", no current DOA/pattern,
% Avg history reset), counted as Boundary, and never stop acquisition; clean
% windows, ~100 ppm one-row advances and a single one-row loss are accepted.
% In "vsa-stub" mode the backend is wrapped in a struct whose vsaSend is an
% offline stub (no VSA): host-refused windows must never reach it, and a 2.3 s
% stub delay pushes one frame past the 2 s age bound while VSA runs: it was
% drawn while fresh, and origapp:Expired clears the plots when VSA returns (the
% struct stub has no idle hook; the native backend clears it inside the call),
% no stop. The Cutter is refused for
% window4 (cfg.cutterAllowed=false) before any zero-filled buffer exists.
% No VSA session, board or instrument. Prints WINDOW4_FIXTURE_COMPLETE.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 5 || isempty(appPath), appPath = fullfile(root, 'app'); end
if nargin < 6, mode = "vsa-off"; end
mode = string(mode);
addpath(appPath);
if ~isfolder(outDir), mkdir(outDir); end
oldVis = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis)); %#ok<NASGU>

bc = struct('host', "127.0.0.1", 'port', port, 'referenceMat', referenceMat, 'orientation', "IplusjQ", ...
    'dllPath', "unused-offline", 'setupPath', "unused-offline", 'setupSha256', "unused", 'vsaPort', 60999, ...
    'visible', false, 'expectSource', "offline-fake", 'wireMode', "window4", 'prefetch', false, 'warmup', false, ...
    'connectTimeoutSeconds', 60, 'frameLogFile', string(fullfile(outDir, 'frames.jsonl')));
b = origapp.LegacyVsaBackend(bc);
cfg = origapp.defaultConfig();
cfg.originalRepoPath = string(originalRepoPath);
stubCalls = zeros(1,0); stubDelaySeq = 7;
if mode == "vsa-stub"
    cfg.backend = struct('open', @() b.open(), 'close', @() b.close(), 'next', @(t) b.next(t), ...
        'availableChannels', @() b.availableChannels(), 'vsaSend', @stubVsaSend, 'vsaStatus', @stubStatus);
    cfg.vsa = 1;
else
    cfg.backend = b; cfg.vsa = 0;
end
cfg.directOnly = false; cfg.dataChan = 32768; cfg.ch = 5; cfg.cutterAllowed = false;
cfg.cutter = 1;   % requested by config: must be refused at start-up for window4
cfg.bf = 'Steering'; cfg.doa = 'MVDR'; cfg.fc = 3e9; cfg.fcAnt = 3e9; cfg.fsRfsoc = 125e6;
cfg.frameTimeoutSeconds = 10; cfg.staleSeconds = 2; cfg.maxConsecutiveErrors = 6;
cfg.arrayLabel = "common-feed diagnostic / array model (ULA d=lambda/2 @3 GHz)";
app = VSA_rfsoc_refactor_exported(cfg);
appGuard = onCleanup(@() delete(app));
% Cutter is refused for window4 at start-up (control greyed, visible note)
cutter = struct('disabledAtStartup', strcmp(app.CutterCheckBox.Enable, 'off') && ~app.CutterCheckBox.Value && ...
    privGet(app, 'cutter') == 0 && any(contains(app.Notes, "Cutter disabled")), 'refusedAtRuntime', false);
% a user/programmatic tick of the (greyed) box runs the real callback: refused again
app.CutterCheckBox.Value = true;
cb = app.CutterCheckBox.ValueChangedFcn; cb(app.CutterCheckBox, struct('Value', true));
cutter.refusedAtRuntime = ~app.CutterCheckBox.Value && privGet(app, 'cutter') == 0;
app.Controller.open();
assert(isequal(b.availableChannels(), true(1,4)), 'w4:Mask', 'v3 must report four measured streams');

B = "crosses a loop boundary";
if mode == "vsa-stub"
    expect = {20, 20, B, 20, B, B, 20, "expired during VSA", -35};
else
    expect = {20, 20, -35, "No wanted-signal lock", "No wanted-signal lock on stream(s) 2", ...
        "Repeated full-capture", "Window SHA256 differs", 10, B, B, B, B, B, B, B, B, B, 20, 20, 20, -35};
end
rows = struct('item', {}, 'ok', {}, 'doa', {}, 'patternPeak', {}, 'status', {}, 'title', {}, ...
    'windowStart', {}, 'hostLocks', {}, 'boundaryFree', {}, 'integrityReason', {}, 'boardCandidate', {}, ...
    'boardSummaryOk', {}, 'avgReset', {}, 'boundaryCount', {}, 'expiredCount', {}, 'consecutiveErrors', {}, ...
    'boardSelectS', {}, 'hostCheckS', {}, 'integrityS', {}, 'tickS', {});
since = [];   % valid angles since the last invalid frame (Avg history)
for k = 1:numel(expect)
    nBefore = numel(b.Delivered);
    t = tic; app.tick(); dt = toc(t);
    m = struct();
    if numel(b.Delivered) > nBefore, m = b.Delivered{end}; end
    e = expect{k};
    pm = privGet(app, 'p_manual_mean'); ym = privGet(app, 'yspec_mean');
    avgReset = (isempty(pm) || all(pm(:) == 0)) && (isempty(ym) || all(ym(:) == 0));
    if isnumeric(e)
        [~, i] = max(app.CurrentPattern);
        pk = app.scan_axis(i);
        since(end+1) = e; %#ok<AGROW>
        % the displayed pattern is the Avg-frame mean: check its peak only when
        % every averaged frame had this angle (history restarts after rejection)
        ok = ~isempty(app.CurrentDoa) && abs(app.CurrentDoa(1) - e) <= 2 && ...
            (any(since ~= e) || abs(pk - e) <= 3) && isequal(fieldOr(m, 'boundaryFree'), true) && ...
            contains(strjoin(string(app.UIAxes.Title.String)), "common-feed diagnostic") && ...
            contains(strjoin(string(app.UIAxes.Title.String)), "UNCALIBRATED");
        doa = app.CurrentDoa;
    else
        pk = NaN; doa = app.CurrentDoa; since = [];
        ok = isempty(app.CurrentDoa) && isempty(app.CurrentPattern) && contains(app.Status, e) && avgReset && ...
            contains(strjoin(string(app.UIAxes.Title.String)), "unavailable") && ...
            contains(strjoin(string(app.UIAxes2.Title.String)), "unavailable");
        if e == B   % refused by the host flag at Controller admission (before VSA and plots)
            ok = ok && isequal(fieldOr(m, 'boundaryFree'), false) && app.Controller.ConsecutiveErrors == 0;
        end
    end
    ok = ok && app.Controller.IsOpen;   % boundary/expired/no-signal frames never stop acquisition
    rows(end+1) = struct('item', string(k), 'ok', ok, 'doa', doa, 'patternPeak', pk, 'status', app.Status, ...
        'title', strjoin(string(app.UIAxes.Title.String), ' | '), 'windowStart', fieldOr(m, 'windowStart'), ...
        'hostLocks', fieldOr(m, 'hostStreamLocks'), 'boundaryFree', fieldOr(m, 'boundaryFree'), ...
        'integrityReason', fieldOr(m, 'integrityReason'), 'boardCandidate', fieldOr(m, 'boardCandidate'), ...
        'boardSummaryOk', fieldOr(m, 'boardSummaryOk'), 'avgReset', avgReset, ...
        'boundaryCount', app.Controller.BoundaryFrames, 'expiredCount', app.Controller.ExpiredFrames, ...
        'consecutiveErrors', app.Controller.ConsecutiveErrors, ...
        'boardSelectS', fieldOr(m, 'boardSelectS'), 'hostCheckS', fieldOr(m, 'hostCheckS'), ...
        'integrityS', fieldOr(m, 'integrityS'), 'tickS', dt); %#ok<AGROW>
end
results.mode = mode;
results.frames = rows;
results.cutter = cutter;
results.vsaStubCalls = stubCalls;

%% VSA input classification on the last (valid) frame; no VSA session exists
v = struct();
if mode == "vsa-off" && isfield(b.LastFrameMeta, 'sequence')
    X = b.LastMeasured4; seq = b.LastFrameMeta.sequence;
    v.rawStreamClassified = errId(@() b.vsaSend(X(:,3))) == "a2live:Vsa";            % passed classification
    v.combinedSameFrame = errId(@() b.vsaSend(sum(X,2)/2, struct('kind',"combined",'sequence',seq))) == "a2live:Vsa";
    v.combinedWrongFrame = errId(@() b.vsaSend(sum(X,2)/2, struct('kind',"combined",'sequence',seq-1))) == "a2live:Channel";
    v.unlabelledNonStream = errId(@() b.vsaSend(sum(X,2)/2)) == "a2live:Channel";
    y = sum(X,2)/2; y(100:1000) = 0;
    v.zeroPaddedRefused = errId(@() b.vsaSend(y, struct('kind',"combined",'sequence',seq))) == "a2live:Channel";
elseif mode == "vsa-off"
    v.lastFrameMissing = false;
else
    % host-refused windows never reached VSA; the expired frame did (drawn
    % while fresh, then cleared as Expired when the blocking VSA returned)
    v.stubCallsExactlyAccepted = isequal(stubCalls, [0 1 3 6 7 8]);
end
results.vsaInput = v;

%% Host continuity check (windowIntegrity) on reference-built windows: the real
% loop wrap at many positions incl. the first/last 8192-row blocks, 300-row
% losses incl. near the edges, a clean window and ~100 ppm one-row losses
r = load(referenceMat); ref = r.ref125(:); N = numel(ref); Bu = double(r.burst125);
RFc = conj(fft(ref)); act = origapp.windowActivityModel(ref);
safe = round(2000 + Bu);                         % verifiable clean start (burst phase 2000)
pre = [1 4 16 64 600 1543 3000 8191 8192 16384 24575 24576 30000 32704 32752 32760 32767];
v2 = struct('wrapTested', numel(pre), 'wrapAccepted', zeros(1,0), 'lossAccepted', zeros(1,0), ...
    'cleanRejected', "", 'slipRejected', "", 'maxS', 0);
for j = pre                                      % j pre-wrap rows, then loop index 0
    idx = mod((N - j : N - j + 32767).', N) + 1;
    A = origapp.windowIntegrity(ref(idx), ref, RFc, Bu, act); v2.maxS = max(v2.maxS, A.elapsedS);
    if A.ok, v2.wrapAccepted(end+1) = j; end
end
for pos = [16 32 500 8000 16000 24600 32700 32740]
    idx = [(safe : safe + pos - 1).'; (safe + pos + 300 : safe + 32767 + 300).'] + 1;
    A = origapp.windowIntegrity(ref(idx), ref, RFc, Bu, act); v2.maxS = max(v2.maxS, A.elapsedS);
    if A.ok, v2.lossAccepted(end+1) = pos; end
end
A = origapp.windowIntegrity(ref((safe:safe+32767).' + 1), ref, RFc, Bu, act);
if ~A.ok, v2.cleanRejected = A.reason; end
idx = (safe:safe+32767+4).'; idx([3000 13000 23000 30000]) = [];        % ~100 ppm one-row losses
A = origapp.windowIntegrity(ref(idx(1:32768) + 1), ref, RFc, Bu, act);
if ~A.ok, v2.slipRejected = A.reason; end
results.hostBoundary = v2;

%% END3 closes the stream: further ticks clear (no stale DOA kept)
app.tick();
results.endedAfterScenario = b.Ended;
delete(app); clear appGuard
b.close();

okRows = [rows.ok];
fid = fopen(fullfile(outDir, 'window4_results.json'), 'w');
fwrite(fid, jsonencode(results, 'PrettyPrint', true)); fclose(fid);
disp(jsonencode(results));
assert(all(okRows), 'w4:Frames', 'frame checks failed: %s', jsonencode(rows(~okRows)));
f = fieldnames(v);
for k = 1:numel(f), assert(v.(f{k}), 'w4:Vsa', 'VSA input check %s failed', f{k}); end
assert(results.endedAfterScenario, 'w4:End', 'END3 not seen');
assert(isempty(v2.wrapAccepted) && isempty(v2.lossAccepted) && v2.cleanRejected == "" && ...
    v2.slipRejected == "" && v2.maxS < 1, 'w4:Boundary', 'host continuity check failed: %s', jsonencode(v2));
assert(cutter.disabledAtStartup && cutter.refusedAtRuntime, 'w4:Cutter', ...
    'Cutter not refused: %s', jsonencode(cutter));
fprintf('W4_SUMMARY mode=%s frames=%d ok=%d boundary=%d expired=%d maxIntegrityS=%.3f\n', mode, ...
    numel(rows), sum(okRows), rows(end).boundaryCount, rows(end).expiredCount, max([rows.integrityS, 0]));
fprintf('WINDOW4_FIXTURE_COMPLETE %s\n', outDir);

    function stubVsaSend(buffer, varargin) %#ok<INUSL>
        % struct backends get the buffer only (Controller.sendVsa contract):
        % the frame being processed is the backend's last delivered frame
        q = b.LastFrameMeta.sequence;
        stubCalls(end+1) = q;
        if q == stubDelaySeq, pause(2.3); end   % blocking VSA: frame ages past 2 s
    end
    function s_ = stubStatus()
        s_ = struct('valid', false, 'state', "unavailable", 'reason', "offline stub (no VSA)", ...
            'shortReason', "stub", 'evmPercent', NaN, 'evmDb', NaN, 'source', "OFFLINE STUB - NOT VSA", ...
            'syncCorrelation', NaN, 'lock', NaN, 'sequence', NaN, 'timestamp', NaN);
    end
end

function v = privGet(app, name)
% Test-only read of a private app property (Avg history, cutter state).
w = warning('off', 'MATLAB:structOnObject'); c = onCleanup(@() warning(w));
s = struct(app); v = s.(name);
end

function id = errId(fn)
id = "";
try, fn(); catch e, id = string(e.identifier); end
end
function v = fieldOr(s, f)
v = []; if isstruct(s) && isfield(s, f), v = s.(f); end
end
