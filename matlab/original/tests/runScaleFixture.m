function results = runScaleFixture(originalRepoPath, outDir, appPath)
%RUNSCALEFIXTURE Responsive layout + axes interaction fixture (hidden UI,
% synthetic finite IQ, no board/VSA). Window sizes include a 1366x768
% laptop. Checks per size: reflow mode (1x2 / 2x1), grid rows/columns with no
% high fixed rows in 1x2 mode, the scrollable left panel, both axes inside
% the right panel with a usable plot area, and start-up fitting to monitors.
% Axes: Autoscale follows the data (pattern nulls deeper than the original
% fixed -30 dB are not clipped), a user zoom/pan is kept across frames,
% Autoscale/Tight restore. Prints SCALE_FIXTURE_COMPLETE.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 3, appPath = fullfile(root, 'app'); end
addpath(appPath);
if ~isfolder(outDir), mkdir(outDir); end
oldVis = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis)); %#ok<NASGU>
rng(20261116, 'twister');
base = origapp.defaultConfig();
base.originalRepoPath = string(originalRepoPath);
base.bfEngine = "original"; base.directOnly = false; base.dataChan = 4096;
base.frameTimeoutSeconds = 0.2; base.num = 2;
results = struct();

%% 1. Window sizes (wide and narrow reflow), incl. a 1366x768 laptop work area
b = origapp.FiniteIqBackend(makeFrames(1, base));
app = VSA_rfsoc_refactor_exported(withField(base, 'backend', b));
f = app.RFSoCBeamformerUIFigure;
sizes = [1366 768-40-31; 1280 680; 1600 860; 1920 1000; 2560 1400; 1180 680; 800 600; 560 700; 420 500];
rows = struct('w', {}, 'h', {}, 'outer', {}, 'panel', {}, 'mode', {}, 'rowHeight', {}, 'colWidth', {}, 'leftScrollable', {}, ...
    'axesInside', {}, 'axesInnerHeights', {}, 'ok', {});
for k = 1:size(sizes, 1)
    f.Position = [20 40 sizes(k,:)];
    drawnow;
    feval(f.SizeChangedFcn, f, []);    % the generated updateAppLayout (SizeChangedFcn)
    G = app.GridLayout; R = app.RightPanel;
    narrow = sizes(k,1) <= 576;
    % the (hidden) web layout is asynchronous: wait until the right panel
    % has the width the grid gives it, then until the axes follow it
    % (the OS may cap a window larger than the screen: use the actual width)
    settled = false;
    for t = 1:200
        drawnow; pause(0.05);
        wantW = f.Position(3) - 250*(~narrow);   % narrow: minus the grid scroll bar (tolerance)
        o = [app.UIAxes.OuterPosition; app.UIAxes2.OuterPosition]; q = R.InnerPosition;
        if abs(q(3) - wantW) < 8 + 14*narrow && all(o(:,1) >= -1 & o(:,2) >= -1 & o(:,1)+o(:,3) <= q(3)+2 & o(:,2)+o(:,4) <= q(4)+2), settled = true; break, end
    end
    rh = G.RowHeight; cw = G.ColumnWidth;
    if narrow
        modeOk = numel(rh) == 2 && all(cellfun(@(x) isnumeric(x) && x <= 700, rh)) && R.Layout.Row == 2;
    else
        modeOk = isequal(rh, {'1x'}) && isequal(cw, {250, '1x'}) && R.Layout.Column == 2;
    end
    inner = [app.UIAxes.InnerPosition; app.UIAxes2.InnerPosition];
    outer = [app.UIAxes.OuterPosition; app.UIAxes2.OuterPosition];
    rp = R.InnerPosition;
    inside = all(outer(:,1) >= -1 & outer(:,2) >= -1 & outer(:,1)+outer(:,3) <= rp(3)+2 & outer(:,2)+outer(:,4) <= rp(4)+2);
    usable = all(inner(:,3) > 60 & inner(:,4) > 40);
    rows(end+1) = struct('w', f.Position(3), 'h', f.Position(4), 'outer', outer, 'panel', rp, 'mode', string(ifelse(narrow, "2x1", "1x2")), ...
        'rowHeight', {rh}, 'colWidth', {cw}, 'leftScrollable', string(app.LeftPanel.Scrollable), ...
        'axesInside', inside, 'axesInnerHeights', inner(:,4).', ...
        'ok', settled && modeOk && strcmp(app.LeftPanel.Scrollable, 'on') && inside && (usable || narrow)); %#ok<AGROW>
end
results.sizes = rows;
assert(all([rows.ok]), 'scale:Layout', 'layout check failed: %s', jsonencode(rows(~[rows.ok])));

%% 2. Start-up fit to monitors (incl. 1366x768 and the user's 1646x1029 scaled screen)
mons = [0 0 1366 768; 0 0 1646 1029; 0 0 1280 720; 0 0 1920 1080; 0 0 2560 1440; -416 -1080 1920 1080];
fit = struct('monitor', {}, 'position', {}, 'fits', {});
for k = 1:size(mons, 1)
    app.fitFigureToScreen(mons(k,:));
    p = f.Position; m = mons(k,:);
    fits = p(1) >= m(1) && p(1)+p(3) <= m(1)+m(3) && p(2) >= m(2)+40 && p(2)+p(4)+32 <= m(2)+m(4) && p(3) > p(4);
    fit(end+1) = struct('monitor', m, 'position', p, 'fits', fits); %#ok<AGROW>
end
results.fit = fit;
assert(all([fit.fits]), 'scale:Fit', 'start-up window does not fit: %s', jsonencode(fit(~[fit.fits])));
results.resizable = string(f.Resize);
assert(strcmp(f.Resize, 'on'), 'scale:Resize', 'figure must stay resizable');
delete(app);

%% 3. Axes: autoscale, user zoom kept across frames, Autoscale/Tight restore
cfg = base; cfg.bf = 'MVDR';
frames = makeFrames(4, cfg);
b = origapp.FiniteIqBackend(frames);
app = VSA_rfsoc_refactor_exported(withField(cfg, 'backend', b));
app.Controller.open();
app.tick();
ax = app.UIAxes2; a = struct();
tb = ax.Toolbar;
a.toolbarButtons = string(arrayfun(@(x) string(x.Tooltip), tb.Children(:)', 'UniformOutput', false));
a.toolbarHasZoomPan = numel(tb.Children) >= 8;
a.interactions = string(arrayfun(@class, ax.Interactions, 'UniformOutput', false));
y = app.CurrentPattern;
a.patternMinDb = min(y);
a.yLimFollow = ax.YLim;
a.dataInsideLimits = min(y(isfinite(y))) >= ax.YLim(1) && max(y) <= ax.YLim(2);
a.xFull = isequal(ax.XLim, [app.scan_axis(1) app.scan_axis(end)]);
% user zoom (any non-app limit change): autoscale stops, view is kept
ax.XLim = [-10 25]; ax.YLim = [-12 1]; drawnow;
a.followAfterZoom = app.AxesFollow(2);
a.buttonAfterZoom = string(app.AxesButtons{2}.Value);
app.tick(); drawnow;
a.zoomKeptAfterFrame = isequal(ax.XLim, [-10 25]) && isequal(ax.YLim, [-12 1]);
a.doaAxesStillFollows = app.AxesFollow(1) && isequal(app.UIAxes.XLim, [app.scan_axis(1) app.scan_axis(end)]);
% Autoscale button (state) back on
app.AxesButtons{2}.Value = 'on';
app.setAxesFollow(2, true); drawnow;
a.autoscaleRestored = app.AxesFollow(2) && isequal(ax.XLim, [app.scan_axis(1) app.scan_axis(end)]);
app.tick(); drawnow;
y = app.CurrentPattern;
a.followNextFrame = min(y(isfinite(y))) >= ax.YLim(1) && max(y) <= ax.YLim(2);
% Tight one-shot while zoomed
ax.XLim = [0 10]; drawnow;
app.applyAxesLimits(2, true); drawnow;
a.tightRestoresFull = isequal(ax.XLim, [app.scan_axis(1) app.scan_axis(end)]);
a.tightDoesNotReenableFollow = ~app.AxesFollow(2);
% deep null: a pattern below -30 dB is fully inside the limits (original fixed [-30 0.5] clipped it)
yd = -55 + 55*cosd(1.5*app.scan_axis).^2; cla(ax); plot(ax, app.scan_axis, yd); app.applyAxesLimits(2, true); drawnow;
a.deepNullVisible = min(yd) < -30 && ax.YLim(1) <= min(yd) && ax.YLim(2) >= max(yd);
% stale/cleared frame: limits stay finite and the app shows "unavailable"
app.tick(); app.tick(); drawnow;
a.limitsFinite = all(isfinite([ax.XLim ax.YLim app.UIAxes.XLim app.UIAxes.YLim]));
results.axes = a;
delete(app);
need = {'toolbarHasZoomPan','dataInsideLimits','xFull','zoomKeptAfterFrame','doaAxesStillFollows', ...
    'autoscaleRestored','followNextFrame','tightRestoresFull','tightDoesNotReenableFollow','deepNullVisible','limitsFinite'};
for k = 1:numel(need)
    assert(isequal(a.(need{k}), true), 'scale:Axes', 'axes check %s failed: %s', need{k}, jsonencode(a));
end
assert(~a.followAfterZoom && a.buttonAfterZoom == "off", 'scale:Axes', 'zoom must stop autoscale');

fid = fopen(fullfile(outDir, 'scale_results.json'), 'w');
fwrite(fid, jsonencode(results, 'PrettyPrint', true)); fclose(fid);
disp(jsonencode(results));
fprintf('SCALE_FIXTURE_COMPLETE %s\n', outDir);
end

function frames = makeFrames(n, cfg)
N = cfg.dataChan; m = (0:3);
a = @(th) exp(1j*pi*m*sind(th));
frames = cell(1, n);
for k = 1:n
    t = (0:N-1).'/cfg.fsRfsoc;
    s1 = 3000*exp(1j*2*pi*5e6*t + 1j*2*pi*rand);
    s2 = 1200*exp(1j*2*pi*-11e6*t + 1j*2*pi*rand);
    frames{k} = s1*a(20) + s2*a(-30) + 30*(randn(N,4) + 1j*randn(N,4));
end
end
function s = withField(s, name, value)
s.(name) = value;
end
function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
