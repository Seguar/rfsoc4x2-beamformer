function results = runWindow4Fixture(port, referenceMat, originalRepoPath, outDir)
%RUNWINDOW4FIXTURE Four-stream (window4) transport + session fixture against
% the OFFLINE fake stream tests/fake_window4_server.py (source "offline-fake",
% NOT hardware), started by the caller with the scenario
%   wave:20,wave:20,wave:-35,blank,dead:2,stale,badsha,wave:10,
%   wrapfirst:16,wrapfirst:3000,wraplast:8,wraplast:3000,loss:32740:300,loss:16000:300,
%   fallback,nocand,badjson,clean,slips,loss:16000:1,wave:-35
% Checks, through the real LegacyVsaBackend decode (bounded inflate, window
% SHA) and the headless DemoSession: known steered angles; blank and
% dead-stream frames are shown (lock is reported, never a reason to drop a
% frame); stale (repeated capture SHA) and corrupted windows are refused.
% Board-misjudgement items (wrapfirst/wraplast/loss and the selector-summary
% faults fallback/nocand/badjson) claim a good candidate, so only the host
% check can refuse them: refused at Controller admission (Boundary), never
% stopping acquisition; clean windows, ~100 ppm one-row advances and a single
% one-row loss are accepted. Then the host continuity check (windowIntegrity)
% on reference-built windows. No board or instrument.
% Prints WINDOW4_FIXTURE_COMPLETE.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'app'));
addpath(fullfile(char(originalRepoPath), 'Functions'));
if ~isfolder(outDir), mkdir(outDir); end

bc = struct('host', "127.0.0.1", 'port', port, 'referenceMat', referenceMat, 'orientation', "IplusjQ", ...
    'expectSource', "offline-fake", 'wireMode', "window4", 'prefetch', false, ...
    'connectTimeoutSeconds', 60, 'frameLogFile', string(fullfile(outDir, 'frames.jsonl')));
b = origapp.LegacyVsaBackend(bc);
setx = fullfile(char(originalRepoPath), 'Settings', 'ofdm_iq_100_16_4x2.setx');
cfg = origapp.defaultConfig();
cfg.originalRepoPath = string(originalRepoPath); cfg.backend = b;
cfg.directOnly = false; cfg.dataChan = 32768; cfg.ch = 5; cfg.elementModel = "isotropic";
cfg.bf = 'Steering'; cfg.doa = 'MVDR'; cfg.fc = 3e9; cfg.fcAnt = 3e9; cfg.fsRfsoc = 125e6;
cfg.frameTimeoutSeconds = 10; cfg.staleSeconds = 2; cfg.maxConsecutiveErrors = 6;
cfg.arrayLabel = "common-feed diagnostic / array model (ULA d=lambda/2 @3 GHz)";
cfg.ofdmSetupFile = setx;
cfg.ofdm = struct('setupSha256', origapp.LegacyVsaBackend.sha256(setx), 'referenceMat', referenceMat, ...
    'orientation', "IplusjQ", 'syncThreshold', .8);
s = origapp.DemoSession(cfg); sGuard = onCleanup(@() delete(s));
s.start();
assert(isequal(b.availableChannels(), true(1,4)), 'w4:Mask', 'v3 must report four measured streams');

B = "crosses a loop boundary"; S = "shown";
expect = {20, 20, -35, S, S, "Repeated full-capture", "Window SHA256 differs", 10, B, B, B, B, B, B, B, B, B, 20, 20, 20, -35};
rows = struct('item', {}, 'ok', {}, 'doa', {}, 'patternPeak', {}, 'reason', {}, 'windowStart', {}, ...
    'hostLocks', {}, 'boundaryFree', {}, 'integrityReason', {}, 'boardCandidate', {}, 'boardSummaryOk', {}, ...
    'boundaryCount', {}, 'consecutiveErrors', {}, 'integrityS', {}, 'stepS', {});
c = s.Controller;
for k = 1:numel(expect)
    nBefore = numel(b.Delivered);
    t = tic; s.step(); dt = toc(t);
    a = s.snapshot();
    m = struct(); if numel(b.Delivered) > nBefore, m = b.Delivered{end}; end
    e = expect{k}; pk = NaN; doa = [];
    if isfield(a, 'angles'), doa = a.angles; end
    if isstring(e) && e == S
        ok = a.valid && isequal(fieldOr(m, 'boundaryFree'), true) && isfield(m, 'signalChannels') && ~all(m.signalChannels);
    elseif isnumeric(e)
        [~, i] = max(a.patternDb); pk = a.scan(i);
        ok = a.valid && ~isempty(doa) && abs(doa(1) - e) <= 2 && isequal(fieldOr(m, 'boundaryFree'), true) && ...
            contains(a.scope, "common-feed diagnostic") && contains(a.scope, "UNCALIBRATED");
    else
        ok = ~a.valid && contains(string(a.reason), e);
        if e == B   % refused by the host flag at Controller admission
            ok = ok && isequal(fieldOr(m, 'boundaryFree'), false) && c.ConsecutiveErrors == 0;
        end
    end
    ok = ok && c.IsOpen;   % refused frames never stop acquisition
    rows(end+1) = struct('item', string(k), 'ok', ok, 'doa', doa, 'patternPeak', pk, 'reason', string(a.reason), ...
        'windowStart', fieldOr(m, 'windowStart'), 'hostLocks', fieldOr(m, 'hostStreamLocks'), ...
        'boundaryFree', fieldOr(m, 'boundaryFree'), 'integrityReason', fieldOr(m, 'integrityReason'), ...
        'boardCandidate', fieldOr(m, 'boardCandidate'), 'boardSummaryOk', fieldOr(m, 'boardSummaryOk'), ...
        'boundaryCount', c.BoundaryFrames, 'consecutiveErrors', c.ConsecutiveErrors, ...
        'integrityS', fieldOr(m, 'integrityS'), 'stepS', dt); %#ok<AGROW>
end
results.frames = rows;

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

%% END3 closes the stream
s.step();
results.endedAfterScenario = b.Ended;
s.close(); b.close();

okRows = [rows.ok];
fid = fopen(fullfile(outDir, 'window4_results.json'), 'w');
fwrite(fid, jsonencode(results, 'PrettyPrint', true)); fclose(fid);
assert(all(okRows), 'w4:Frames', 'frame checks failed: %s', jsonencode(rows(~okRows)));
assert(results.endedAfterScenario, 'w4:End', 'END3 not seen');
assert(isempty(v2.wrapAccepted) && isempty(v2.lossAccepted) && v2.cleanRejected == "" && ...
    v2.slipRejected == "" && v2.maxS < 1, 'w4:Boundary', 'host continuity check failed: %s', jsonencode(v2));
fprintf('W4_SUMMARY frames=%d ok=%d boundary=%d maxIntegrityS=%.3f\n', numel(rows), sum(okRows), ...
    rows(end).boundaryCount, max([rows.integrityS, 0]));
fprintf('WINDOW4_FIXTURE_COMPLETE %s\n', outDir);
end

function v = fieldOr(s, f)
v = []; if isstruct(s) && isfield(s, f), v = s.(f); end
end
