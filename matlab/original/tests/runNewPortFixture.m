function results = runNewPortFixture(originalRepoPath, reviewedPath, outDir, appPath)
%RUNNEWPORTFIXTURE Headless SIMULATION fixture for the VSA_rfsoc_new feature
% port (New tab). Synthetic IQ only (FiniteIqBackend); no board, VSA,
% instrument or network I/O. Every check is an assertion; a failure stops
% the run. Results are labelled simulation: they show code behaviour, not RF
% performance, physical DOA or measured calibration.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 4, appPath = fullfile(root, 'app'); end
addpath(appPath); addpath(char(reviewedPath));
addpath(fullfile(char(originalRepoPath), 'Functions'));
if ~isfolder(outDir), mkdir(outDir); end
oldVis = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis));
rng(20261116, 'twister');
timersBefore = numel(timerfindall);
figsBefore = numel(findall(groot, 'Type', 'figure'));
results = struct('label', "SIMULATION: synthetic IQ, FiniteIqBackend; no hardware");

base = origapp.defaultConfig();
base.originalRepoPath = string(originalRepoPath);
base.bfEngine = "original";
base.dataChan = 4096;
base.directOnly = false;
base.num = 2;
base.frameTimeoutSeconds = 0.2;

%% 1. Pure functions against the VSA_rfsoc_new originals (HEAD Functions/)
u = struct();
N = 4096; t = (0:N-1).'/base.fsRfsoc;
ideal = 3000*exp(1j*2*pi*5e6*t);
imb = ideal + 0.08*exp(1j*0.3)*conj(ideal);                 % IQ imbalance -> image tone
X = [imb, imb*exp(1j*0.4), imb*exp(-1j*0.9), imb*exp(1j*2.0)];
mu = 1e-9; L = 4;
[Yp, Fp] = origapp.iqCompensate(X, zeros(L,4), "adaptive", mu);
Yo = zeros(size(X)); Fo = zeros(L,4);
for c = 1:4
    [y, Fo(:,c)] = adaptiveIQCompensation(X(:,c), mu*eye(L), zeros(L,1));
    Yo(:,c) = y(:);
end
u.adaptiveMaxAbsDiffVsOriginal = max(abs(Yp - Yo), [], 'all');
u.adaptiveFilterMaxAbsDiff = max(abs(Fp - Fo), [], 'all');
img = @(x) imagePowerRatioDb(x(N/2+1:end), base.fsRfsoc);
u.imageRatioBeforeDb = img(X(:,1));
u.imageRatioAfterDb = img(Yp(:,1));
Ys = origapp.iqCompensate(X, Fp, "static");
Yso = X(:,2) + conv(conj(X(:,2)), Fp(:,2), 'same');
u.staticMaxAbsDiffVsOriginal = max(abs(Ys(:,2) - Yso));
assert(u.adaptiveMaxAbsDiffVsOriginal < 1e-9 && u.adaptiveFilterMaxAbsDiff < 1e-12 && ...
    u.staticMaxAbsDiffVsOriginal < 1e-9, 'fixture:IqEquivalence', 'IQ port differs from original');
assert(u.imageRatioAfterDb < u.imageRatioBeforeDb - 10, 'fixture:IqEffect', 'IQ comp did not reduce the image');
assertError(@() origapp.iqCompensate(X(1:3,:), zeros(L,4), "static"), 'origapp:IqComp');

pm = origapp.phaseMismatch(X, 1); [~, ~, ca] = cphase(X, 1);
u.phaseMismatchDiffDeg = max(abs(pm(:) - rad2deg(ca(:))));
assert(u.phaseMismatchDiffDeg < 1e-9 && abs(pm(1)) < 1e-12, 'fixture:Cphase', 'phaseMismatch != cphase');

% angle calibration: simulated array captures at operator-labelled angles
ula = antPrep(4, physconst('LightSpeed'), base.fcAnt);
angs = -60:30:60;
mm = zeros(N, 4, numel(angs));
for k = 1:numel(angs), mm(:,:,k) = arrayFrame(N, base, angs(k), []); end
cal = origapp.angleCalibration(mm, angs, 1, ula, base.fcAnt, physconst('LightSpeed'), 3);
figsB = findall(groot, 'Type', 'figure');
[sc0, as0] = phase_pattern_generator(mm, angs, 1, 4);
[~, ps0, pi0] = power_pattern_generator(mm, angs, 1, 4);
cm0 = adaptiveCouplingMatrixCalculation(mm, ps0, as0, angs, base.fcAnt, physconst('LightSpeed'), ula, 4, 3);
delete(setdiff(findall(groot, 'Type', 'figure'), figsB));   % original helpers open figures
u.calSteeringDiff = max(abs(cal.steeringCorrection - sc0), [], 'all');
u.calPowerDiff = max(abs(cal.powCalibration - pi0), [], 'all') / max(abs(pi0), [], 'all');
u.calCouplingDiff = max(abs(cal.couplingMatrix - cm0), [], 'all') / max(abs(cm0), [], 'all');
u.calGrid = [cal.gridDeg(1) cal.gridDeg(end) numel(cal.gridDeg)];
assert(u.calSteeringDiff < 1e-9 && u.calPowerDiff < 1e-9 && u.calCouplingDiff < 1e-6, ...
    'fixture:Calibration', 'angleCalibration differs from the original helpers');
% Finding (recorded, not hidden): on IDEAL single-source captures the original
% coupling iteration does not return ~identity, because it least-squares fits
% eigenvectors whose per-angle phase is arbitrary. Recorded as an original
% algorithm defect; the port keeps the original numerics.
mi = zeros(N, 4, numel(angs)); mv = 0:3;
for k = 1:numel(angs), mi(:,:,k) = 3000*exp(1j*2*pi*5e6*t)*exp(1j*pi*mv*sind(angs(k))); end
ci = origapp.angleCalibration(mi, angs, 1, ula, base.fcAnt, physconst('LightSpeed'), 20);
Ci = ci.couplingMatrix;
x20 = 3000*exp(1j*2*pi*5e6*t)*exp(1j*pi*mv*sind(20)) + 3*(randn(N,4) + 1j*randn(N,4));
est = phased.MVDREstimator('SensorArray', ula, 'OperatingFrequency', base.fcAnt, ...
    'ScanAngles', -60:60, 'DOAOutputPort', true, 'NumSignals', 1);
[~, d0] = est(x20); release(est); [~, d1] = est((Ci*x20.').');
u.couplingIdealFinding = struct('offIdentityFro', norm(Ci/Ci(1,1) - eye(4), 'fro'), ...
    'doaWithoutCouplingDeg', d0, 'doaWithCouplingDeg', d1, ...
    'label', "simulation: ideal ULA captures; original VSA_rfsoc_new coupling calibration");
assert(all(isfinite(Ci), 'all'), 'fixture:Calibration', 'ideal coupling matrix not finite');

% command policy
caps0 = struct('commands', strings(1,0), 'txArrayElements', 0, 'uploadDac', false);
capsAll = struct('commands', ["dgain","again","phase","dacbf","stream","dphase"], 'txArrayElements', 4, 'uploadDac', true);
u.policy = struct( ...
    'dacbfRefusedEvenIfDeclared', ~origapp.commandPolicy("dacbf tracking", capsAll), ...
    'streamRefusedEvenIfDeclared', ~origapp.commandPolicy("stream 8", capsAll), ...
    'dacbfcorrRefused', ~origapp.commandPolicy("dacbfcorr 0/0/0/0", capsAll), ...
    'dgainRefusedUndeclared', ~origapp.commandPolicy("dgain 1/1/1/1", caps0), ...
    'dgainAllowedDeclared', origapp.commandPolicy("dgain 1/1/1/1", capsAll), ...
    'dphaseOriginalVerbAllowed', origapp.commandPolicy("dphase 0/0/0/0", caps0));
assert(all(cell2mat(struct2cell(u.policy))), 'fixture:Policy', 'command policy');

% DAC BF sequencer
rs = RandStream('twister', 'Seed', 1);
[a1, s1] = origapp.dacBeamSteering("Scaning", -2:2, 0, [], 120, ula, base.fcAnt, [0 0 0 0], rs);
[a2, s2] = origapp.dacBeamSteering("Scaning", s1, 0, [], 120, ula, base.fcAnt, [0 0 0 0], rs);
[a3, s3] = origapp.dacBeamSteering("Rescaning", -2:2, 0, [], 120, ula, base.fcAnt, [0 0 0 0], rs);
[a4, ~, ph4] = origapp.dacBeamSteering("GUI", [], 30, [], 120, ula, base.fcAnt, [0 0 0 200], rs);
r1 = origapp.dacBeamSteering("Random", [], 0, [], 120, ula, base.fcAnt, [0 0 0 0], RandStream('twister','Seed',7));
r2 = origapp.dacBeamSteering("Random", [], 0, [], 120, ula, base.fcAnt, [0 0 0 0], RandStream('twister','Seed',7));
sv = phased.SteeringVector('SensorArray', ula); w30 = sv(base.fcAnt, 30);
want = mod(round(rad2deg(angle(w30)).', 2) + [0 0 0 200] + 180, 360) - 180;
u.dacBf = struct('scan', [a1 a2], 'scanSeq', s2, 'rescan', a3, 'rescanSeq', s3, 'gui', a4, ...
    'phaseDeg', ph4, 'randomReproducible', r1 == r2, 'randomInRange', abs(r1) <= 60);
assert(isequal([a1 a2], [-2 -1]) && isequal(s3, [2 -2 -1 0 1]) && a3 == -2 && a4 == 30 && ...
    max(abs(ph4 - want)) < 1e-9 && all(ph4 >= -180 & ph4 < 180) && r1 == r2 && abs(r1) <= 60, ...
    'fixture:DacBf', 'DAC BF sequencer');
assertError(@() origapp.dacBeamSteering("Tracking", [], 0, [], 120, ula, base.fcAnt, [0 0 0 0], rs), 'origapp:DacBf');

% DAC file preparation vs the original sigPrepare
fs = 500e6; n = 16384; tt = (0:n-1).'/fs;
Y = 0.9*exp(1j*2*pi*(fs/n*512)*tt); XDelta = 1/fs;
f1 = fullfile(outDir, 'dac_tone_16384.mat'); save(f1, 'Y', 'XDelta');
[i16, info] = origapp.prepareDacWaveform(f1, 'fsDac', fs, 'peakCode', 1200);
% sigPrepare always resamples and filters; compare at a normalised rate
% (filtSig is rate-scale invariant; avoids resample(Y, 5e8, 5e8)).
f0 = fullfile(outDir, 'dac_tone_noXDelta.mat'); save(f0, 'Y');
iN = origapp.prepareDacWaveform(f0, 'fsOrig', 1, 'fsDac', 1, 'resample', true, 'filter', true, ...
    'bwDac', 0.998, 'peakCode', 1200);
orig = sigPrepare(f0, 1, 1, 0.998);
cc = corrcoef(double(iN), double(orig(:)));
u.dac = struct('samples', info.complexSamples, 'periodsInRam', info.periodsInRam, ...
    'peak', info.peakCode, 'corrWithSigPrepare', cc(1,2), 'firstIQ', double(i16(1:2)).', ...
    'sha256', info.sha256);
assert(info.complexSamples == n && info.periodsInRam == 32 && info.peakCode <= 1200 && ...
    cc(1,2) > 0.99999 && i16(1) > 0 && abs(double(i16(2))) < 20, 'fixture:Dac', ...
    'DAC preparation (I + jQ order, peak, RAM tiling)');
Y = Y(1:1000); save(fullfile(outDir, 'dac_bad_1000.mat'), 'Y', 'XDelta');
assertError(@() origapp.prepareDacWaveform(fullfile(outDir, 'dac_bad_1000.mat'), 'fsDac', fs), 'origapp:DacFile');
results.units = u;

%% 2. App: startup, New tab, nothing sent
s = struct();
b = origapp.FiniteIqBackend(frames(2, base, 20));
app = VSA_rfsoc_refactor_exported(with(base, 'backend', b));
s.newTabTitle = string(app.NewTab.Title);
s.componentCount = countComponents(app);
s.noBackendCallsAtStartup = isempty(b.Calls);
s.dacBfOff = strcmp(app.DACBFmodeListBox.Value, 'Off') && strcmp(app.RFSOCBFmodeListBox.Value, 'Off');
s.channelLimits = app.Ch1Spinner.Limits;
delete(app);
assert(s.componentCount == 151 && s.noBackendCallsAtStartup && s.dacBfOff && ...
    isequal(s.channelLimits, [-179 179]), 'fixture:Startup', 'startup');
results.startup = s;

%% 3. IQ compensation in the array pipeline
q = struct();
[app, ~] = start(with(with(base, 'adIQcomp', 1), 'stepMU', 1e-9), frames(4, base, 20, 0.08));
app.tick(); app.tick();
q.adaptiveRuns = ~isempty(app.CurrentDoa) && any(app.LastResult.iqFilter ~= 0, 'all');
q.doa = app.CurrentDoa;
q.corrections = app.LastResult.corrections;
app.IQCompCheckBox.Value = true; cb(app.IQCompCheckBox);
app.tick();
q.adaptiveThenStatic = isequal(app.LastResult.corrections, ["adaptiveIQ","staticIQ"]);
app.LsizeEditField.Value = 8; cb(app.LsizeEditField);
q.lMessage = contains(app.PortStatusLabel.Text, "L=8");
app.tick();
q.lResetsFilter = q.lMessage && isequal(size(app.LastResult.iqFilter), [8 4]);
delete(app);
[app, ~] = start(with(base, 'IQcomp', 1), frames(2, base, 20));
app.tick();
q.staticZeroFilterExplicit = isempty(app.CurrentDoa) && contains(app.Status, "nonzero IQ filter");
delete(app);
fprintf('SECTION %s\n', jsonencode(q));
assert(q.adaptiveRuns && abs(q.doa(1) - 20) <= 2 && q.adaptiveThenStatic && q.lResetsFilter && ...
    q.staticZeroFilterExplicit, 'fixture:IqApp', 'IQ comp in app');
results.iq = q;

%% 4. Coupling and phase/power compensation need calibration (explicit errors)
k = struct();
[app, ~] = start(with(base, 'coupComp', 1), frames(2, base, 20));
app.tick(); k.couplingMissingExplicit = isempty(app.CurrentDoa) && contains(app.Status, "disabled pending review");
delete(app);
calI = base.calibration; calI.couplingMatrix = eye(4);
[app, ~] = start(with(with(base, 'coupComp', 1), 'calibration', calI), frames(2, base, 20));
app.tick(); k.couplingIdentityRefused = isempty(app.CurrentDoa) && contains(app.Status, "disabled pending review");
delete(app);
[app, ~] = start(with(base, 'phComp', 1), frames(2, base, 20));
app.tick(); k.phaseMissingExplicit = isempty(app.CurrentDoa) && contains(app.Status, "steeringCorrection");
delete(app);
G = numel(-60:1:60);
calU = struct('powCalibration', ones(G,4), 'steeringCorrection', ones(G,4), 'koef', [], 'couplingMatrix', []);
[app, ~] = start(with(with(base, 'phComp', 1), 'calibration', calU), frames(2, base, 20));
app.tick(); k.phaseUnitDoa = app.CurrentDoa;
delete(app);
[app, ~] = start(with(with(with(with(base, 'phComp', 1), 'c1', 1), 'calibration', calU), 'doa', 'MVDRman_corr'), frames(2, base, 20));
app.tick(); k.c1AndPhaseExplicit = isempty(app.CurrentDoa) && contains(app.Status, "only one");
delete(app);
[app, ~] = start(with(with(base, 'doa', 'MVDRman'), 'calibration', calU), frames(2, base, 20));
app.tick(); k.mvdrman45e726b = app.CurrentDoa;
delete(app);
[app, ~] = start(with(with(with(base, 'doa', 'MVDRman'), 'calibration', calU), 'manualMvdrFormula', "head"), frames(2, base, 20));
app.tick(); k.mvdrmanHead = app.CurrentDoa;
delete(app);
fprintf('SECTION %s\n', jsonencode(k));
assert(k.couplingMissingExplicit && k.couplingIdentityRefused && k.phaseMissingExplicit && ...
    abs(k.phaseUnitDoa(1) - 20) <= 2 && k.c1AndPhaseExplicit && ...
    ~isempty(k.mvdrmanHead) && isequal(k.mvdrmanHead(1), k.mvdrman45e726b(1)), 'fixture:Comp', 'compensation');
results.compensation = k;

%% 5. Angle calibration (VSA_rfsoc_new chain) end-to-end, then use it
c = struct();
calAngles = -60:30:60; per = 2;
fr = {};
for a = calAngles, fr = [fr, frames(per, base, a)]; end %#ok<AGROW>
fr = [fr, frames(2, base, 20)];
cfgC = with(with(base, 'outputDir', string(fullfile(outDir, 'anglecal'))), 'calibrationFramesPerAngle', per);
cfgC.start_ang = -60; cfgC.step_ang = 30; cfgC.couplingIterations = 3;
[app, ~] = start(cfgC, fr);
press = @() app.StartphasecalibrationsButton.ButtonPushedFcn(app.StartphasecalibrationsButton, struct());
press();
for a = calAngles
    press(); for r = 1:per, app.tick(); end
end
d = dir(fullfile(outDir, 'anglecal', 'phase_cal_*'));
c.files = string({dir(fullfile(d(end).folder, d(end).name, '*.mat')).name});
c.message = app.PortMessages(end);
c.installed = ~isempty(app.SessionCalibration) && isequal(app.Config.calibration.couplingMatrix, ...
    app.SessionCalibration.couplingMatrix);
app.PhasecompCheckBox.Value = true; cb(app.PhasecompCheckBox);
app.CouplingcompCheckBox.Value = true; cb(app.CouplingcompCheckBox);
app.tick();
c.generatedCouplingRefused = isempty(app.CurrentDoa) && contains(app.Status, "disabled pending review");
app.CouplingcompCheckBox.Value = false; cb(app.CouplingcompCheckBox);
app.tick();
c.doaWithInstalledCalibration = app.CurrentDoa;
c.corrections = app.LastResult.corrections;
delete(app);
assert(all(ismember(["steering_correction.mat","pow_claibration_intrp.mat","coupling_matrix.mat"], c.files)) && ...
    c.installed && contains(c.message, "installed") && ~isempty(c.doaWithInstalledCalibration) && ...
    c.generatedCouplingRefused && isequal(c.corrections, "phasePower"), 'fixture:AngleCal', 'angle calibration');
[app, ~] = start(with(base, 'directOnly', true), frames(1, base, 20));
app.StartphasecalibrationsButton.ButtonPushedFcn(app.StartphasecalibrationsButton, struct());
c.directOnlyRefused = contains(app.PortStatusLabel.Text, "array mode");
delete(app);
fprintf('SECTION %s\n', jsonencode(c));
assert(c.directOnlyRefused, 'fixture:AngleCal', 'directOnly calibration must be refused');
results.angleCalibration = c;

%% 6. EVM title (guarded backend status only), mirror, phase mismatch
e = struct();
[app, b] = start(with(with(base, 'EVM_check', 1), 'plotMirror', 1), frames(3, base, 20));
b.VsaStatus = struct('valid', true, 'reason', "ok", 'evmPercent', 3.79);
app.tick();
ttl = strjoin(string(app.UIAxes.Title.String), ' ');
e.evmShown = contains(ttl, "3.79 %") && contains(ttl, "-28.4 dB");
e.mirrorTitle = contains(ttl, "[mirrored]") && contains(ttl, "-2");
e.doaDataUnmirrored = app.CurrentDoa;
b.VsaStatus = struct('valid', false, 'reason', "stale");
app.tick();
e.evmInvalidShownUnavailable = contains(strjoin(string(app.UIAxes.Title.String), ' '), "EVM = unavailable");
app.PrintphasemissmatchButton.ButtonPushedFcn(app.PrintphasemissmatchButton, struct());
e.phaseMismatch = string(app.PortStatusLabel.Text);
delete(app);
[app, ~] = start(with(base, 'directOnly', true), frames(1, base, 20));
app.tick();
app.PrintphasemissmatchButton.ButtonPushedFcn(app.PrintphasemissmatchButton, struct());
e.phaseMismatchDirectOnly = string(app.PortStatusLabel.Text);
delete(app);
fprintf('SECTION %s\n', jsonencode(e));
assert(e.evmShown && e.mirrorTitle && abs(e.doaDataUnmirrored(1) - 20) <= 2 && e.evmInvalidShownUnavailable && ...
    startsWith(e.phaseMismatch, "Phase mismatch vs Ch1 (deg): 0.00") && ...
    contains(e.phaseMismatchDirectOnly, "unavailable"), 'fixture:Display', 'EVM/mirror/phase mismatch');
results.display = e;

%% 7. directOnly keeps the native VSA feed raw (no IQ comp on the vendor EVM path)
r = struct();
fx = frames(1, base, 20);
[app, b] = start(with(with(with(base, 'directOnly', true), 'adIQcomp', 1), 'IQcomp', 1), fx);
app.tick();
r.vsaFeedIsRawChannel = isequal(b.LastVsaBuffer, fx{1}(:,1)/2^16);
delete(app);
fprintf('SECTION %s\n', jsonencode(r));
assert(r.vsaFeedIsRawChannel, 'fixture:RawFeed', 'direct VSA feed changed');
results.rawFeed = r;

%% 8. DAC BF, RFSoC BF, burst length: capability gated / ZCU216 refused
g = struct();
[app, ~] = start(base, frames(3, base, 20));
app.DACBFmodeListBox.Value = 'Scaning'; cb(app.DACBFmodeListBox);
g.dacBfRefusedNoCaps = strcmp(app.DACBFmodeListBox.Value, 'Off') && contains(app.PortStatusLabel.Text, "steerable TX array");
app.RFSOCBFmodeListBox.Value = 'Tracking'; cb(app.RFSOCBFmodeListBox);
g.rfsocBfRefused = strcmp(app.RFSOCBFmodeListBox.Value, 'Off') && contains(app.PortStatusLabel.Text, "ZCU216");
app.BurstLenSpinner.Value = 8; cb(app.BurstLenSpinner);
g.burstRefused = app.BurstLenSpinner.Value == 1 && contains(app.PortStatusLabel.Text, "ZCU216");
g.nothingQueued = isempty(app.Controller.Pending);
delete(app);
[app, b] = start(base, frames(4, base, 20));
b.Capabilities = capsAll;
app.RFSOCBFmodeListBox.Value = 'Retracking'; cb(app.RFSOCBFmodeListBox);
g.rfsocBfRefusedEvenIfDeclared = strcmp(app.RFSOCBFmodeListBox.Value, 'Off') && contains(app.PortStatusLabel.Text, "ZCU216");
app.DACBFmodeListBox.Value = 'Scaning'; cb(app.DACBFmodeListBox);
app.tick(); app.tick();
g.scanTitle = strjoin(string(app.UIAxes.Title.String), ' ');
g.scanAngles = str2double(regexp(g.scanTitle, 'DAC Angles = (-?[\d.]+)', 'tokens', 'once'));
g.dphaseQueued = sum(startsWith(app.Controller.Pending, "dphase "));
g.heldWithoutPermission = isempty(b.SentCommands);
app.DACBFmodeListBox.Value = 'Tracking'; cb(app.DACBFmodeListBox);
app.tick();
g.trackingTitle = strjoin(string(app.UIAxes.Title.String), ' ');
g.trackingFollowsDoa = contains(g.trackingTitle, "DAC Angles = " + num2str(app.CurrentDoa(1)));
delete(app);
[app, b] = start(with(base, 'directOnly', true), frames(1, base, 20));
b.Capabilities = capsAll;
app.DACBFmodeListBox.Value = 'Tracking'; cb(app.DACBFmodeListBox);
g.trackingRefusedDirectOnly = strcmp(app.DACBFmodeListBox.Value, 'Off') && contains(app.PortStatusLabel.Text, "directOnly");
delete(app);
fprintf('SECTION %s\n', jsonencode(g));
assert(g.dacBfRefusedNoCaps && g.rfsocBfRefused && g.burstRefused && g.nothingQueued && ...
    g.rfsocBfRefusedEvenIfDeclared && g.scanAngles == -59 && g.dphaseQueued == 2 && ...
    g.heldWithoutPermission && g.trackingFollowsDoa && g.trackingRefusedDirectOnly, 'fixture:Gating', 'gating');
results.gating = g;

%% 9. Channel control
h = struct();
[app, b] = start(with(base, 'allowBoardCommands', true), frames(3, base, 20));
app.ChannelcontrolDropDown.Value = 'DAC gain'; cb(app.ChannelcontrolDropDown);
h.gainLimits = app.Ch2Spinner.Limits;
app.Ch2Spinner.Value = 50; cb(app.Ch2Spinner);
h.dgainRefusedReverted = app.Ch2Spinner.Value == 0 && contains(app.PortStatusLabel.Text, "not declared");
b.Capabilities = struct('commands', "dgain", 'txArrayElements', 0, 'uploadDac', false);
app.Ch2Spinner.Value = 50; cb(app.Ch2Spinner);
app.ChannelcontrolDropDown.Value = 'DAC phase'; cb(app.ChannelcontrolDropDown);
app.Ch3Spinner.Value = 10; cb(app.Ch3Spinner);
app.ChannelcontrolDropDown.Value = 'ADC phase'; cb(app.ChannelcontrolDropDown);
app.Ch1Spinner.Value = 5; cb(app.Ch1Spinner);
h.adcPhaseRefused = contains(app.PortStatusLabel.Text, "not declared");
app.tick();   % part reset flushes the queue (allowBoardCommands=true)
h.sent = b.SentCommands;
delete(app);
assert(isequal(h.gainLimits, [0 199]) && h.dgainRefusedReverted && h.adcPhaseRefused && ...
    any(contains(h.sent, "dgain 0/50/0/0")) && any(contains(h.sent, "dphase 0/0/1000/0")) && ...
    ~any(contains(h.sent, "phase 500")), 'fixture:ChannelControl', 'channel control');
results.channelControl = h;

%% 10. Custom DAC file: prepared; upload only with capability + permission
f = struct();
[app, b] = start(with(base, 'dacFile', string(f1)), frames(1, base, 20));
app.DACfileButton.ButtonPushedFcn(app.DACfileButton, struct());
f.preparedNoUpload = ~isempty(app.DacPrepared) && contains(app.PortStatusLabel.Text, "not provided") && isempty(b.Uploads);
delete(app);
[app, b] = start(with(with(base, 'dacFile', string(f1)), 'allowBoardCommands', true), frames(1, base, 20));
b.Capabilities = struct('commands', strings(1,0), 'txArrayElements', 0, 'uploadDac', true);
app.DACportDropDown.Value = 'DAC_A (dac1)';
app.DACfileButton.ButtonPushedFcn(app.DACfileButton, struct());
i16b = origapp.prepareDacWaveform(f1, 'fsDac', base.fsDAC);
f.uploaded = isscalar(b.Uploads) && b.Uploads(1).port == "DAC_A (dac1)" && isequal(b.Uploads(1).samples, i16b);
delete(app);
[app, ~] = start(with(base, 'dacFile', string(fullfile(outDir, 'dac_bad_1000.mat'))), frames(1, base, 20));
app.DACfileButton.ButtonPushedFcn(app.DACfileButton, struct());
f.badRejected = isempty(app.DacPrepared) && contains(app.PortStatusLabel.Text, "rejected");
delete(app);
[app, ~] = start(base, frames(1, base, 20));
app.DACfileButton.ButtonPushedFcn(app.DACfileButton, struct());
f.noDialogWhenWindowsDisabled = contains(app.Status, "external windows disabled");
delete(app);
fprintf('SECTION %s\n', jsonencode(f));
assert(f.preparedNoUpload && f.uploaded && f.badRejected && f.noDialogWhenWindowsDisabled, 'fixture:DacFile', 'DAC file');
results.dacFile = f;

%% 11. Reviewed engine with the new corrections (convention unchanged)
if strlength(string(reviewedPath)) > 0
    rc = rfsoc.defaultConfig(); rc.spacingM = physconst('LightSpeed')/base.fcAnt/2; rc.fsHz = base.fsRfsoc;
    rv = with(with(with(with(base, 'bfEngine', "reviewed"), 'reviewed', rc), 'adIQcomp', 1), 'stepMU', 1e-9);
    [app, ~] = start(rv, frames(2, base, 20, 0.08));
    app.tick(); app.tick();
    results.reviewed = struct('doa', app.CurrentDoa, 'peakDeg', app.scan_axis(find(app.CurrentPattern == max(app.CurrentPattern), 1)));
    delete(app);
    assert(abs(results.reviewed.peakDeg - 20) <= 3, 'fixture:Reviewed', 'reviewed engine pattern peak');
end

%% 12. Cleanup
results.cleanup = struct('timersLeaked', numel(timerfindall) - timersBefore, ...
    'figuresLeaked', numel(findall(groot, 'Type', 'figure')) - figsBefore);
assert(results.cleanup.timersLeaked == 0 && results.cleanup.figuresLeaked == 0, 'fixture:Cleanup', 'leak');
fid = fopen(fullfile(outDir, 'new_port_results.json'), 'w');
fwrite(fid, jsonencode(results, 'PrettyPrint', true)); fclose(fid);
fprintf('NEW_PORT_FIXTURE_COMPLETE %s\n', outDir);
end

function [app, b] = start(cfg, fr)
b = origapp.FiniteIqBackend(fr);
cfg.backend = b;
app = VSA_rfsoc_refactor_exported(cfg);
app.Controller.open();
end

function cb(h)
% Invoke a component's bound callback as App Designer would on user input.
if isprop(h, 'ValueChangedFcn') && ~isempty(h.ValueChangedFcn)
    h.ValueChangedFcn(h, struct('Value', h.Value));
else
    h.ButtonPushedFcn(h, struct());
end
end

function fr = frames(n, cfg, angleDeg, imbalance)
if nargin < 4, imbalance = []; end
fr = cell(1, n);
for k = 1:n, fr{k} = arrayFrame(cfg.dataChan, cfg, angleDeg, imbalance); end
end

function X = arrayFrame(N, cfg, angleDeg, imbalance)
% Wanted source at angleDeg plus a weaker interferer at -30 deg on a
% half-wavelength 4-element ULA (phased.SteeringVector convention).
m = 0:3; a = @(th) exp(1j*pi*m*sind(th));
t = (0:N-1).'/cfg.fsRfsoc;
s1 = 3000*exp(1j*2*pi*5e6*t + 1j*2*pi*rand);
s2 = 1200*exp(1j*2*pi*-11e6*t + 1j*2*pi*rand);
X = s1*a(angleDeg) + s2*a(-30) + 30*(randn(N,4) + 1j*randn(N,4));
if ~isempty(imbalance), X = X + imbalance*conj(X); end
end

function r = imagePowerRatioDb(x, fs)
n = numel(x); F = fftshift(abs(fft(x)).^2); fr = (-n/2:n/2-1)*fs/n;
[~, ip] = min(abs(fr - 5e6)); [~, im] = min(abs(fr + 5e6));
r = 10*log10(F(im)/F(ip));
end

function assertError(fn, id)
try
    fn();
catch err
    assert(strcmp(err.identifier, id), 'fixture:ErrorId', 'expected %s, got %s', id, err.identifier);
    return
end
error('fixture:NoError', 'expected error %s', id);
end

function s = with(s, name, value)
s.(name) = value;
end

function n = countComponents(app)
n = 0; p = properties(app);
for k = 1:numel(p)
    v = app.(p{k});
    if isa(v, 'matlab.graphics.Graphics') && isscalar(v) && isvalid(v), n = n + 1; end
end
end
