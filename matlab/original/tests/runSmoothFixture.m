function results = runSmoothFixture(originalRepoPath, outDir, appPath)
%RUNSMOOTHFIXTURE Smoother live display fixture (hidden UI, synthetic finite
% IQ, struct backend with an OFFLINE VSA stub; no board, no native VSA).
% Checks: (1) accepted frames reuse the persistent pattern/spectrum lines and
% xlines (no per-frame cla/plot/xline creation); (2) a user zoom on the
% pattern axes is kept across frames; (3) a rejected (no-signal) frame
% blanks the display at once (NaN data, xlines hidden, "unavailable"
% titles) and resets the Avg history, and the next good frame recovers on
% the same objects; (4) the frame is drawn before the (blocking) VSA call
% with "EVM pending" for that frame, then the guarded EVM of the SAME frame;
% (5) a VSA call that blocks past the 2 s bound clears the drawn frame from
% inside the call (backend idle hook) right after the bound, and the frame
% is then rejected as Expired without stopping acquisition; (6) with no new
% frame the tick watchdog clears the display once it is older than 2 s;
% (7) the owned probe timer and timing log work and every timer is deleted
% with the app. Prints SMOOTH_FIXTURE_COMPLETE.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 3, appPath = fullfile(root, 'app'); end
addpath(appPath);
if ~isfolder(outDir), mkdir(outDir); end
oldVis = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis));
rng(20261116, 'twister');
timersBefore = numel(timerfindall);

seq = 0; mode = "good"; tsOffset = 0; vsaBlock = 0; idleFn = []; inVsa = struct('t', [], 'title', "", 'cleared', []);
evmSeq = NaN; evmValid = false;
be = struct('open', @() 1, 'close', @() 1, 'next', @nextFrame, 'availableChannels', @() true(1,4), ...
    'vsaSend', @stubVsa, 'vsaStatus', @stubStatus, 'setVsaIdle', @setIdle);
cfg = origapp.defaultConfig();
cfg.originalRepoPath = string(originalRepoPath);
cfg.bfEngine = "original"; cfg.directOnly = false; cfg.dataChan = 4096; cfg.num = 1;
cfg.frameTimeoutSeconds = 0.2; cfg.staleSeconds = 2; cfg.vsa = 1; cfg.EVM_check = 1; cfg.avg_factor = 4;
cfg.uiTimingFile = string(fullfile(outDir, 'ui_timing.jsonl'));
if isfile(cfg.uiTimingFile), delete(cfg.uiTimingFile); end
cfg.backend = be;
app = VSA_rfsoc_refactor_exported(cfg);
app.Controller.open();
R = struct();

%% 1. persistent handles over accepted frames
app.tick();
h0 = handlesOf(app); n0 = app.PlotObjectsCreated;
doa = zeros(1, 0);
for k = 1:5
    app.tick(); doa(end+1) = app.CurrentDoa(1); %#ok<AGROW>
end
h1 = handlesOf(app);
R.handlesReused = isequal(h0, h1) && all(isvalid([h1.pattern h1.spectrum h1.am h1.am2])) && app.PlotObjectsCreated == n0;
R.plotObjectsCreated = app.PlotObjectsCreated;
R.patternLines = numel(findobj(app.UIAxes2, 'Type', 'line'));
R.singlePatternLine = R.patternLines == 1;
R.doaNear20 = all(abs(doa - 20) <= 2);
R.doa = doa;

%% 2. user zoom kept across frames
ax = app.UIAxes2;
ax.XLim = [-10 25]; ax.YLim = [-12 1]; drawnow;
app.tick(); drawnow;
R.zoomKept = isequal(ax.XLim, [-10 25]) && isequal(ax.YLim, [-12 1]) && ~app.AxesFollow(2);
app.setAxesFollow(2, true); drawnow;
R.autoscaleRestored = app.AxesFollow(2) && isequal(ax.XLim, [app.scan_axis(1) app.scan_axis(end)]);

%% 3. no-signal frame: immediate blank + Avg reset, then recovery on the same objects
mode = "blank"; app.tick(); mode = "good";
R.blank = blankState(app);
R.blankStatus = string(app.Status);
R.blankKeepsRunning = app.Controller.IsOpen && app.Controller.NoSignalFrames == 1;
app.tick();
pm = privGet(app, 'p_manual_mean');
R.recovered = ~isempty(app.CurrentDoa) && abs(app.CurrentDoa(1) - 20) <= 2 && isequal(handlesOf(app), h1) && ...
    nnz(any(pm ~= 0, 1)) == 1 && all(isfinite(lineY(app)));

%% 4. drawn before VSA, EVM of the same frame afterwards
vsaBlock = 0.2; inVsa = struct('t', [], 'title', "", 'cleared', []);
app.tick();
R.drawnBeforeVsa = contains(inVsa.title, "pending (VSA measuring frame " + seq + ")") && ~isempty(inVsa.cleared) && ~inVsa.cleared(1);
R.evmAfterVsa = contains(strjoin(string(app.UIAxes.Title.String)), "EVM = 2.20 %");
R.titleAfterVsa = strjoin(string(app.UIAxes.Title.String), ' | ');

%% 5. VSA blocks past the bound: cleared from inside the call, then Expired
tsOffset = 0.6; vsaBlock = 2.0; inVsa = struct('t', [], 'title', "", 'cleared', []);
exp0 = app.Controller.ExpiredFrames;
app.tick();
first = find(inVsa.cleared, 1);
R.clearAgeInVsa = NaN;
if ~isempty(first), R.clearAgeInVsa = inVsa.t(first); end
R.drawnThenClearedInVsa = ~inVsa.cleared(1) && ~isempty(first) && R.clearAgeInVsa > 2 && R.clearAgeInVsa < 2.1;
R.expired = app.Controller.ExpiredFrames == exp0 + 1 && contains(app.Status, "expired during VSA") && ...
    app.DisplayExpiredDuringVsa == 1 && app.Controller.IsOpen;
R.expiredBlank = blankState(app);
tsOffset = 0; vsaBlock = 0;
app.tick();
R.recoveredAfterExpiry = ~isempty(app.CurrentDoa) && isequal(handlesOf(app), h1);

%% 6. no new frame: the tick watchdog clears an aging display
mode = "none"; t0 = tic; cleared = NaN;
while toc(t0) < 3.5
    app.tick();
    if isempty(app.CurrentPattern) && isnan(cleared), cleared = toc(t0); end
    pause(0.05);
end
mode = "good";
R.noFrameClearedAfterS = cleared;
R.noFrameCleared = cleared > 1.9 && cleared < 2.45 && blankState(app).ok;
R.noFrameStatus = string(app.Status);
app.tick();
R.recoveredAfterGap = ~isempty(app.CurrentDoa);
delete(app);

%% 7. owned probe timer + timing log, all timers deleted with the app
cfg.uiProbePeriodSeconds = 0.02; cfg.periodSeconds = 0.1; cfg.vsa = 0;
app = VSA_rfsoc_refactor_exported(cfg);
R.probeTimerNamed = ~isempty(timerfindall('Name', 'VSA_rfsoc_refactor_probe'));
app.startAcquisition();
t0 = tic; while toc(t0) < 2, pause(0.05); end
app.stopAcquisition("fixture stop");
delete(app);
R.timersLeft = numel(timerfindall) - timersBefore;
R.noTimerLeft = R.timersLeft == 0 && isempty(timerfindall('Name', 'VSA_rfsoc_refactor_probe')) && ...
    isempty(timerfindall('Name', 'VSA_rfsoc_refactor'));
L = splitlines(strtrim(fileread(cfg.uiTimingFile)));
T = cellfun(@jsondecode, L, 'UniformOutput', false);   % rows differ (vsaDone only with VSA)
R.timingRows = numel(T);
acc = T(cellfun(@(t) string(t.outcome) == "accepted", T));
R.timingHasPlotAge = ~isempty(acc) && all(cellfun(@(t) isfield(t, 'ageAtPlot') && t.ageAtPlot >= 0, acc));
R.probeCounted = any(cellfun(@(t) t.probeCount > 0, T));

fid = fopen(fullfile(outDir, 'smooth_results.json'), 'w'); fwrite(fid, jsonencode(R, 'PrettyPrint', true)); fclose(fid);
disp(jsonencode(R));
need = {'handlesReused', 'singlePatternLine', 'doaNear20', 'zoomKept', 'autoscaleRestored', 'blankKeepsRunning', ...
    'recovered', 'drawnBeforeVsa', 'evmAfterVsa', 'drawnThenClearedInVsa', 'expired', 'recoveredAfterExpiry', ...
    'noFrameCleared', 'recoveredAfterGap', 'probeTimerNamed', 'noTimerLeft', 'timingHasPlotAge', 'probeCounted'};
for k = 1:numel(need)
    assert(isequal(R.(need{k}), true), 'smooth:Check', 'check %s failed: %s', need{k}, jsonencode(R));
end
assert(R.blank.ok && R.expiredBlank.ok, 'smooth:Blank', 'display not blank: %s', jsonencode(R));
results = R;
clear restoreVis
fprintf('SMOOTH_FIXTURE_COMPLETE %s\n', outDir);

    function fr = nextFrame(~)
        if mode == "none", fr = []; return, end
        seq = seq + 1;
        N = cfg.dataChan; m = (0:3); t = (0:N-1).'/cfg.fsRfsoc;
        s1 = 3000*exp(1j*2*pi*5e6*t + 1j*2*pi*rand);
        X = s1*exp(1j*pi*m*sind(20)) + 30*(randn(N,4) + 1j*randn(N,4));
        sc = true(1,4); if mode == "blank", sc(3) = false; end
        fr = struct('samples', X, 'timestamp', origapp.Controller.nowSeconds() - tsOffset, 'sequence', seq, ...
            'availableChannels', true(1,4), 'signalChannels', sc, 'boundaryFree', true);
    end
    function stubVsa(~, varargin)
        evmValid = false;
        tv = tic;
        inVsa.title = strjoin(string(app.UIAxes.Title.String));
        inVsa.t(end+1) = origapp.Controller.nowSeconds() - (inVsa_ts()); inVsa.cleared(end+1) = isempty(app.CurrentPattern);
        while toc(tv) < vsaBlock
            pause(0.01);                       % as rfsoc.VsaSession.sendFrame
            if ~isempty(idleFn), idleFn(); end
            inVsa.t(end+1) = origapp.Controller.nowSeconds() - inVsa_ts();
            inVsa.cleared(end+1) = isempty(app.CurrentPattern);
        end
        evmSeq = seq; evmValid = true;
    end
    function t = inVsa_ts()
        t = privGet(app, 'TickMarks'); t = t.timestamp;
    end
    function s = stubStatus()
        s = struct('valid', evmValid, 'state', "valid", 'reason', "ok", 'shortReason', "ok", 'evmPercent', 2.2, ...
            'evmDb', 20*log10(0.022), 'source', "OFFLINE STUB - NOT VSA", 'sequence', evmSeq);
    end
    function setIdle(fn)
        idleFn = fn;
    end
end

function h = handlesOf(app)
L = privGet(app, 'lineHandles');
h = struct('pattern', privGet(app, 'patternLine'), 'spectrum', privGet(app, 'plot_handle'), 'am', L.am, 'am2', L.am2);
end

function y = lineY(app)
p = privGet(app, 'patternLine'); y = p.YData;
end

function s = blankState(app)
p = privGet(app, 'patternLine'); q = privGet(app, 'plot_handle'); L = privGet(app, 'lineHandles');
x = struct2cell(L); x = [x{:}];
vis = arrayfun(@(h) isvalid(h) && strcmp(h.Visible, 'on'), x);
pm = privGet(app, 'p_manual_mean'); ym = privGet(app, 'yspec_mean');
s = struct('patternNaN', all(isnan(p.YData)), 'spectrumNaN', all(isnan(q.YData)), 'xlinesHidden', ~any(vis), ...
    'titles', contains(strjoin(string(app.UIAxes.Title.String)), "unavailable") && ...
    contains(strjoin(string(app.UIAxes2.Title.String)), "unavailable"), ...
    'avgReset', all(pm(:) == 0) && all(ym(:) == 0), 'noCurrent', isempty(app.CurrentDoa) && isempty(app.CurrentPattern));
s.ok = s.patternNaN && s.spectrumNaN && s.xlinesHidden && s.titles && s.avgReset && s.noCurrent;
end

function v = privGet(app, name)
% test-only read of a private app property (no side effects)
w = warning('off', 'MATLAB:structOnObject'); c = onCleanup(@() warning(w));
s = struct(app); v = s.(name);
end
