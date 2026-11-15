function results = runOriginalUiFixture(originalRepoPath, reviewedPath, outDir,appPath)
%RUNORIGINALUIFIXTURE Hidden-UI fixture for VSA_rfsoc_refactor_exported.
% Synthetic finite IQ only (FiniteIqBackend). No board, VSA or instrument.
%   results = runOriginalUiFixture(<vsa_rfsoc checkout>, <demo matlab folder>, <out dir>)
root = fileparts(fileparts(mfilename('fullpath')));
if nargin<4, appPath=fullfile(root,'app'); end
addpath(appPath);
addpath(char(reviewedPath));
if ~isfolder(outDir), mkdir(outDir); end
rng(20261115, 'twister');
% Helpers such as phase_pattern_generator call figure(); keep them off-screen.
oldVis = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis)); %#ok<NASGU>
results = struct();
timersBefore = numel(timerfindall);
figsBefore = numel(findall(groot, 'Type', 'figure'));

base = origapp.defaultConfig();
base.originalRepoPath = string(originalRepoPath);
base.bfEngine="original"; % explicit legacy comparison; production default is reviewed
base.dataChan = 4096;
base.directOnly = false;
base.num = 2;
base.frameTimeoutSeconds = 0.2;

%% 1. Hidden construction, idle, nothing sent
b = origapp.FiniteIqBackend(makeFrames(3, base));
app = VSA_rfsoc_refactor_exported(withField(base, 'backend', b));
t = struct();
t.figureHidden = strcmp(app.RFSoCBeamformerUIFigure.Visible, 'off');
t.timerOwnedNotRunning = isvalid(app.AcqTimer) && strcmp(app.AcqTimer.Running, 'off');
t.noBackendCallsAtStartup = isempty(b.Calls);
t.noCommandsQueuedAtStartup = isempty(app.Controller.Pending);
t.controlsShowState = app.RFSoCFcSpinner.Value == base.fc/1e6 && app.RFSoCFsSpinner.Value == base.fsRfsoc/1e6;
t.componentCount = countComponents(app);
delete(app);
t.closeAfterNoStartIsNoop = b.CloseCount == 0;
results.startup = t;

%% 2. All original beamformer modes (original engine), MVDR DOA
bfNames = {'Without','Steering','MVDR','DMR','PC','PC_corr','LCMV','RVL','RAB PC','DL MVDR','DL ITER MVDR','QCB'};
results.beamformers = runModes(base, 'bf', bfNames, {}, true);

%% 3. All original DOA modes (Steering BF); manual modes without and with calibration
doaNames = {'MVDR','MVDRman','MVDRman_corr','MUSIC','Beamscan','MUSICR','ESPRITE','ESPRITEBS','WSFR'};
results.doaNoCalibration = runModes(base, 'doa', doaNames, {}, false);
scanN = numel(-base.scan_bw/2:base.scan_res:base.scan_bw/2);
cal = struct('powCalibration', ones(scanN,4), 'steeringCorrection', ones(scanN,4), 'koef', []);
results.doaWithUnitCalibration = runModes(withField(base, 'calibration', cal), 'doa', ...
    {'MVDRman','MVDRman_corr'}, {}, false);

%% 4. Reviewed engine (explicit), all 12 names
if strlength(string(reviewedPath)) > 0
    addpath(char(reviewedPath));
    rc = rfsoc.defaultConfig();
    rc.spacingM = physconst('LightSpeed')/base.fcAnt/2;
    rc.fsHz = base.fsRfsoc;
    rev = withField(withField(withField(base, 'bfEngine', "reviewed"), 'reviewed', rc), ...
        'reviewedPath', string(reviewedPath));
    results.reviewedBeamformers = runModes(rev, 'bf', bfNames, {}, false);
end

%% 5. Bounded failure clears current DOA/pattern; stale/repeat rejected; stop after N
f = struct();
b = origapp.FiniteIqBackend(makeFrames(6, base), 'FailAt', 2, 'StaleAt', 3, 'RepeatAt', 4);
app = VSA_rfsoc_refactor_exported(withField(base, 'backend', b));
app.Controller.open();
app.tick(); f.firstOk = ~isempty(app.CurrentDoa) && all(isfinite(app.CurrentPattern));
app.tick(); f.transportFailureClears = isempty(app.CurrentDoa) && isempty(app.CurrentPattern) ...
    && contains(app.Status, "Injected transport failure");
app.tick(); f.staleFrameClears = isempty(app.CurrentDoa) && contains(app.Status, "old");
app.tick(); f.repeatedFrameClears = isempty(app.CurrentDoa) && contains(app.Status, "Repeated");
app.tick(); f.recoversOnFreshFrame = ~isempty(app.CurrentDoa);
f.statusAfterRecovery = app.Status;
delete(app);
f.closedOnDelete = b.CloseCount == 1;
c3 = withField(base, 'maxConsecutiveErrors', 3);
b = origapp.FiniteIqBackend(makeFrames(1, base), 'FailAt', 1:10);
c3.backend = b;
app = VSA_rfsoc_refactor_exported(c3);
app.Controller.open();
for k = 1:3, app.tick(); end
f.stopsAfterMaxErrors = b.CloseCount == 1 && ~app.Controller.IsOpen && isempty(app.CurrentDoa);
f.stopStatus = app.Status;
delete(app);
results.failure = f;

%% 6. directOnly=true shows no physical DOA, still feeds VSA through backend
d = struct();
b = origapp.FiniteIqBackend(makeFrames(2, base));
app = VSA_rfsoc_refactor_exported(withField(withField(base, 'directOnly', true), 'backend', b));
app.Controller.open(); app.tick(); app.tick();
d.noDoa = isempty(app.CurrentDoa) && isempty(app.CurrentPattern);
d.titleSaysUnavailable = contains(string(app.UIAxes.Title.String{1}), "unavailable");
d.vsaFrames = b.VsaFrames;
delete(app);
results.directOnly = d;

%% 7. Board-command gating and callback-to-command mapping
g = struct();
b = origapp.FiniteIqBackend(makeFrames(3, base));
app = VSA_rfsoc_refactor_exported(withField(base, 'backend', b));
app.Controller.open(); app.tick();
g.heldWhenDisabled = isempty(b.SentCommands) && numel(app.Controller.Pending) == 2;
delete(app);
b = origapp.FiniteIqBackend(makeFrames(3, base));
app = VSA_rfsoc_refactor_exported(withField(withField(base, 'backend', b), 'allowBoardCommands', true));
app.Controller.open(); app.tick();
app.RFSoCFcSpinner.Value = 4900;
app.RFSoCFcSpinner.ValueChangedFcn(app.RFSoCFcSpinner, struct('Value', 4900));
app.tick();
g.sent = b.SentCommands;
g.fcCommandMirrored = any(contains(b.SentCommands, "fc -4900/1/"));
g.stateUpdated = app.LastResult.estimated_angle(1) == app.CurrentDoa(1);
delete(app);
results.commands = g;

%% 7b. Phase calibration flow (non-blocking, writes only under outputDir)
pc = struct();
b = origapp.FiniteIqBackend(makeFrames(6, base));
cfgP = withField(withField(base, 'backend', b), 'outputDir', string(fullfile(outDir, 'phasecal')));
cfgP.start_ang = -10; cfgP.step_ang = 10;
app = VSA_rfsoc_refactor_exported(cfgP);
app.Controller.open(); app.tick();
press = @() app.StartphasecalibrationsButton.ButtonPushedFcn(app.StartphasecalibrationsButton, struct());
press();                              % start: -10 deg
for k = 1:3, press(); app.tick(); end % capture -10, 0, +10
d2 = dir(fullfile(outDir, 'phasecal', 'phase_cal_*'));
pc.folders = numel(d2);
if pc.folders == 1
    pc.files = string({dir(fullfile(d2(1).folder, d2(1).name, '*.mat')).name});
else
    pc.files = strings(0);
end
pc.steeringCorrectionWritten = any(pc.files == "steering_correction.mat");
pc.status = app.Status;
pc.buttonText = app.StartphasecalibrationsButton.Text;
delete(app);
results.phaseCal = pc;

%% 8. Owned timer: autoStart, runs, exhausts, cleanup leaves no timer/figure
m = struct();
b = origapp.FiniteIqBackend(makeFrames(4, base));
cfgT = withField(withField(withField(base, 'backend', b), 'autoStart', true), 'periodSeconds', 0.05);
cfgT.staleSeconds = 0.5;
app = VSA_rfsoc_refactor_exported(cfgT);
t0 = tic;
while toc(t0) < 20 && app.Controller.FramesAccepted < 4
    pause(0.1);
end
m.framesAcceptedByTimer = app.Controller.FramesAccepted;
pause(1.5);
m.clearedAfterSourceExhausted = isempty(app.CurrentDoa);
m.statusAfterExhausted = app.Status;
delete(app);
m.backendClosed = b.CloseCount == 1;
m.timersLeaked = numel(timerfindall) - timersBefore;
m.figuresLeaked = numel(findall(groot, 'Type', 'figure')) - figsBefore;
results.timer = m;

save(fullfile(outDir, 'fixture_results.mat'), 'results');
fid = fopen(fullfile(outDir, 'fixture_results.json'), 'w');
fwrite(fid, jsonencode(results, 'PrettyPrint', true)); fclose(fid);
end

function rows = runModes(base, field, names, ~, assertOk)
rows = struct('name', {}, 'ok', {}, 'doa', {}, 'patternPeakDeg', {}, 'gainAtWantedDb', {}, ...
    'gainAtInterfererDb', {}, 'status', {}, 'seconds', {});
for k = 1:numel(names)
    b = origapp.FiniteIqBackend(makeFrames(2, base));
    cfg = base; cfg.(field) = names{k}; cfg.backend = b;
    app = VSA_rfsoc_refactor_exported(cfg);
    app.Controller.open();
    t0 = tic; app.tick(); app.tick(); dt = toc(t0);
    ok = ~isempty(app.CurrentDoa) && ~isempty(app.CurrentPattern) && all(isfinite(app.CurrentPattern));
    pk = NaN; gw = NaN; gi = NaN;
    if ok
        [~, i] = max(app.CurrentPattern); pk = app.scan_axis(i);
        gw = interp1(app.scan_axis, app.CurrentPattern, 20);    % wanted source (fixture truth)
        gi = interp1(app.scan_axis, app.CurrentPattern, -30);   % interferer (fixture truth)
    end
    rows(end+1) = struct('name', names{k}, 'ok', ok, 'doa', app.CurrentDoa, ...
        'patternPeakDeg', pk, 'gainAtWantedDb', gw, 'gainAtInterfererDb', gi, ...
        'status', app.Status, 'seconds', dt); %#ok<AGROW>
    delete(app);
    if assertOk && ~ok
        % Failures must be explicit origapp:* errors, never silent.
        assert(contains(rows(end).status, "frame rejected"), 'fixture:Silent', ...
            'Mode %s failed without an explicit status.', names{k});
    end
end
end

function frames = makeFrames(n, cfg)
% Two narrowband sources (wanted +20 deg strong, interferer -30 deg weaker)
% on a half-wavelength 4-element array at fcAnt, in ADC-count scale.
% Generated with the phased.SteeringVector convention of a half-wavelength
% ULA (X = s*sv.'), i.e. the convention of the app's DOA estimators.
N = cfg.dataChan; m = (0:3);
a = @(th) exp(1j*pi*m*sind(th));
frames = cell(1, n);
for k = 1:n
    t = (0:N-1).'/cfg.fsRfsoc;
    s1 = 3000*exp(1j*2*pi*5e6*t + 1j*2*pi*rand);
    s2 = 1200*exp(1j*2*pi*-11e6*t + 1j*2*pi*rand);
    noise = 30*(randn(N,4) + 1j*randn(N,4));
    frames{k} = s1*a(20) + s2*a(-30) + noise;
end
end

function s = withField(s, name, value)
s.(name) = value;
end

function n = countComponents(app)
n = 0;
p = properties(app);
for k = 1:numel(p)
    v = app.(p{k});
    if isa(v, 'matlab.graphics.Graphics') && isscalar(v) && isvalid(v), n = n + 1; end
end
end
