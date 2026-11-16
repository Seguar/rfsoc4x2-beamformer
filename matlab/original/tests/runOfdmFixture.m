function results = runOfdmFixture(referenceMat, originalRepoPath, outDir, appPath)
%RUNOFDMFIXTURE Software gates of the Integrated Custom OFDM analyzer and its
% integration in the original app. SIMULATION from the transmitted reference
% loop (legacy_ref125.mat) - not hardware, no VSA, no board.
%  Core: ideal, CFO, noise (EVM tracks the injected level), payload-only
%  corruption keeps a nonzero EVM (no payload fitting), one-sample loss in
%  the payload and in the preamble (burst refused), truncated burst, noise
%  only, zeros, wrong preamble profile, unsupported rate ratio, SHA pin, SETX
%  without FFT length (no default).
%  App: integrated only (no VSA call), both (VSA gets the identical buffer),
%  vsa only (no analyzer/viewer), blank/no-lock and stale/expiry clear the
%  current values (history labelled), VSA checkbox, constant graphics over
%  frames, MVDRman/MVDRman_corr refused without calibration (acquisition
%  continues), accepted with tables, invalid start-up config errors, close
%  deletes the owned viewer and leaves no timers.
% Prints OFDM_FIXTURE_COMPLETE.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 4 || isempty(appPath), appPath = fullfile(root, 'app'); end
addpath(appPath, fileparts(root));
if ~isfolder(outDir), mkdir(outDir); end
oldVis = get(groot, 'DefaultFigureVisible'); set(groot, 'DefaultFigureVisible', 'off');
rv = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis)); %#ok<NASGU>
setx = fullfile(originalRepoPath, 'Settings', 'ofdm_iq_100_16_4x2.setx');
SHA = origapp.LegacyVsaBackend.sha256(setx);
assert(any(SHA == ["62d4c02859b90d4fa8b9efe56425b63143dfc7e6bbd9de64491da47d8b14c8d8", ...
    "81acc6b652bc2303701888f8ea3af598c0c3be5fa3e05acb48473930a7c6602e"]), 'fixture:Profile','Unknown reference SETX.');
r = load(referenceMat); ref = r.ref125(:);
P = origapp.ofdmProfile(setx, 125e6, 'sha256', SHA, 'reference', ref);
opt = struct('syncThreshold', 0.8);
rng(20261116);
T = struct('name', {}, 'ok', {}, 'detail', {});
    function check(name, ok, detail)
        T(end+1) = struct('name', string(name), 'ok', logical(ok), 'detail', string(detail));
        fprintf('%-46s %s  %s\n', name, string(ifelse(ok, 'PASS', 'FAIL')), detail);
    end
x = ref(1:32768);
sc = sqrt(mean(abs(x).^2));
% ---- core ----
R = origapp.ofdmAnalyze(x, P, opt);
check('ideal reference', R.valid && R.evmPercent < 0.5 && R.bursts >= 5 && R.bursts == numel(R.candidates) && R.headerEvmPercent < 0.5, ...
    sprintf('EVM %.3f %%, header %.3f %%, %d bursts, setx FFT %d (not 256)', R.evmPercent, R.headerEvmPercent, R.bursts, P.nfft));
check('parameters from SETX', P.nfft == 64 && P.ncp == 16 && P.nr == 80 && numel(P.bins) == 53 && ...
    P.summary.dataSubcarriers == 48 && isequal(P.summary.pilotSubcarriers, [-21 -7 7 21]) && ...
    string(P.summary.payloadModulation) == "16QAM" && string(P.summary.headerModulation) == "BPSK" && P.burstSymbols == 30, ...
    sprintf('FFT %d CP %d, rx FFT %d, %d data, pilots %s', P.nfft, P.ncp, P.nr, P.summary.dataSubcarriers, mat2str(P.summary.pilotSubcarriers)));
n = (0:numel(x)-1).';
R = origapp.ofdmAnalyze(x.*exp(1j*2*pi*50e3*n/125e6), P, opt);
check('CFO 50 kHz', R.valid && all(abs(R.cfoHz - 50e3) < 1e3) && R.evmPercent < 1, ...
    sprintf('CFO est %s kHz, EVM %.3f %%', mat2str(round(R.cfoHz/1e3, 2)), R.evmPercent));
ev = zeros(1, 3); lv = [0.01 0.03 0.1];
for k = 1:3
    xn = x + lv(k)*sc*(randn(size(x)) + 1j*randn(size(x)))/sqrt(2);
    R = origapp.ofdmAnalyze(xn, P, opt); ev(k) = R.evmPercent;
end
check('noise: EVM tracks injected level', all(diff(ev) > 0) && ev(1) > 0.5 && ev(3) < 40, ...
    sprintf('noise %s of rms -> EVM %s %%', mat2str(lv), mat2str(round(ev, 2))));
% payload-only corruption: preamble/training untouched
xc = x; Rr = origapp.ofdmAnalyze(x, P, opt);
for b = [Rr.candidates.start]
    a = b + 4*P.symLen; e = min(b + P.burstSymbols*P.symLen - 1, numel(x));
    if a <= numel(x), xc(a:e) = xc(a:e) + 0.05*sc*(randn(e-a+1,1) + 1j*randn(e-a+1,1))/sqrt(2); end
end
R = origapp.ofdmAnalyze(xc, P, opt);
check('payload corruption keeps nonzero EVM', R.valid && R.evmPercent > 3 && mean(R.trainingSnrDb) > 50, ...
    sprintf('EVM %.2f %% with clean training (SNR %.0f dB): no payload fitting', R.evmPercent, mean(R.trainingSnrDb)));
s0 = Rr.candidates(2).start;
xl = x; xl(s0 + 15*P.symLen + 37) = [];
R = origapp.ofdmAnalyze(xl, P, opt);
c = R.candidates([R.candidates.start] == s0);
check('one-sample loss in payload refuses burst', ~isempty(c) && ~c.accepted && contains(c.reason, "slip") && R.valid, ...
    sprintf('burst@%d: %s; others valid %d', s0, c.reason, R.bursts));
check('primary includes rejected complete bursts', R.degraded && R.refusedCompleteBursts >= 1 && ...
    R.metricBursts == numel(R.perBurst) && R.metricBursts > R.qualifiedBursts && ...
    R.evmPercent > 1.5*R.qualifiedPayloadEvmPercent && any(~[R.perBurst.qualified]), ...
    sprintf('primary %.2f%% vs qualified-only %.2f%%, %d/%d qualified', ...
        R.evmPercent, R.qualifiedPayloadEvmPercent, R.qualifiedBursts, R.metricBursts));
xl = x; xl(s0 + 2*P.symLen + 50) = [];
R = origapp.ofdmAnalyze(xl, P, opt);
c = R.candidates(abs([R.candidates.start] - s0) <= 2);
check('one-sample loss in preamble refuses burst', isempty(c) || all(~[c.accepted]), ...
    sprintf('candidates near %d: %s', s0, strjoin(string({c.reason}), '; ')));
check('preamble quality failures remain in primary', ~isempty(c) && R.metricBursts > R.qualifiedBursts && ...
    R.refusedCompleteBursts >= 1 && numel(R.perBurst)==R.metricBursts, ...
    sprintf('primary %.2f%%, complete %d, qualified %d',R.evmPercent,R.metricBursts,R.qualifiedBursts));
R = origapp.ofdmAnalyze(x(1:Rr.candidates(end).start + 1000), P, opt);
check('truncated burst refused, never padded', any(contains([R.candidates.reason], "incomplete")) && R.bursts == numel(Rr.candidates) - 1, ...
    sprintf('%d of %d bursts', R.bursts, numel(R.candidates)));
R = origapp.ofdmAnalyze(sc*(randn(size(x)) + 1j*randn(size(x)))/sqrt(2), P, opt);
check('noise only: NO SYNC', ~R.valid && R.state == "NO SYNC" && isnan(R.evmPercent), sprintf('peak %.3f', R.syncPeak));
R = origapp.ofdmAnalyze(zeros(size(x)), P, opt);
check('all-zero buffer: NO SYNC', R.state == "NO SYNC" && ~R.valid, sprintf('peak %g', R.syncPeak));
R = origapp.ofdmAnalyze([zeros(4000,1); x(1:28000)], P, opt);
check('silence + signal: no false sync in silence', R.valid && all([R.candidates.start] > 3000), ...
    sprintf('first candidate at %d', R.candidates(1).start));
P2 = P; pm = P2.preambleTemplate; P2.preambleTemplate = pm(randperm(numel(pm)));
R = origapp.ofdmAnalyze(x, P2, opt);
check('wrong preamble profile: NO SYNC', R.state == "NO SYNC", sprintf('peak %.3f', R.syncPeak));
check('unsupported rate ratio refused', throws(@() origapp.ofdmProfile(fullfile(originalRepoPath, 'Settings', 'ofdm_iq_60_64.setx'), 125e6), 'origapp:OfdmProfile'), ...
    'ofdm_iq_60_64 (60 MS/s) at 125 MS/s: explicit error');
check('SETX SHA pin', throws(@() origapp.ofdmProfile(setx, 125e6, 'sha256', repmat('0', 1, 64)), 'origapp:OfdmProfile'), 'wrong pin: explicit error');
bad = fullfile(outDir, 'nofft.setx');
t = fileread(setx); t = regexprep(t, 'key="DemodFlexOfdmFFTLen"', 'key="RemovedFFTLen"');
fid = fopen(bad, 'w'); fwrite(fid, t); fclose(fid);
check('SETX without FFT length: no default', throws(@() origapp.ofdmProfile(bad, 125e6), 'origapp:OfdmProfile'), 'no FFT256/64 fallback');

% ---- app ----
q = {}; sent = {}; nowS = @() origapp.Controller.nowSeconds();
    function f = nextFrame(~)
        f = [];
        if isempty(q), return; end
        f = q{1}; q(1) = [];
        f.timestamp = nowS() - f.timestamp;   % stored as age: acquisition time is set when delivered
    end
    function sendStub(buf, varargin)
        sent{end+1} = buf(:);
    end
    function enqueue(kind, seq, age)
        if kind == "wave"
            X = repmat(conj(x)*2^15*0.03/max(abs(x)), 1, 4) + 2*(randn(numel(x),4) + 1j*randn(numel(x),4));
        else
            X = 2*(randn(numel(x),4) + 1j*randn(numel(x),4));
        end
        q{end+1} = struct('samples', X, 'sequence', seq, 'timestamp', age, 'availableChannels', true(1,4), ...
            'boundaryFree', true);
    end
be = struct('open', @() [], 'close', @() [], 'next', @nextFrame, 'availableChannels', @() true(1,4), ...
    'vsaSend', @sendStub, 'vsaStatus', @() struct('valid', false, 'reason', "stub", 'sequence', NaN));
base = origapp.defaultConfig();
base.backend = be; base.originalRepoPath = string(originalRepoPath); base.visible = false; base.directOnly = false;
base.ch = 5; base.dataChan = 32768; base.fc = 3e9; base.fcAnt = 3e9; base.fsRfsoc = 125e6; base.staleSeconds = 2;
base.cutterAllowed = false; base.vsa = 1; base.EVM_check = 1; base.frameTimeoutSeconds = 0.1;
base.arrayLabel = "common-feed diagnostic / array model (ULA d=lambda/2 @3 GHz)"; base.vsaSetupFile = setx;
base.ofdm = struct('setupSha256', SHA, 'referenceMat', referenceMat, 'orientation', "IplusjQ", 'syncThreshold', 0.8);
timers0 = numel(timerfindall); figures0 = numel(findall(groot,'Type','figure'));
cfg = base; cfg.analyzer = "integrated";
app = VSA_rfsoc_refactor_exported(cfg); app.Controller.open();
enqueue("wave", 0, 0); app.tick();   % first tick also runs the start-up partReset (may expire, as live seq 0)
enqueue("wave", 1, 0); app.tick();
c = app.Ofdm.Current;
if isempty(c), error('ofdm:Fixture', 'first integrated frame invalid: %s | %s', app.Status, app.Ofdm.LastReason); end
check('integrated: valid, no VSA call', ~isempty(c) && c.valid && isempty(sent) && app.OfdmView.isOpen() && ...
    contains(strjoin(string(app.UIAxes.Title.String)), "Integrated Custom OFDM") && c.input == "combined", ...
    sprintf('EVM %.2f %%, %d bursts, title "%s"', c.evmPercent, c.bursts, strjoin(string(app.UIAxes.Title.String), ' | ')));
v=app.OfdmView; v.Figure.Visible='on'; drawnow;
v.Figure.Position=[50 50 640 600]; drawnow;
check('viewer narrow layout scrolls', numel(v.Grid.ColumnWidth)==2 && ...
    string(v.Grid.Scrollable)=="on" && isequal(v.SideGrid.Layout.Row,4), 'real resize callback: 640x600, two-column scrollable');
v.Figure.Position=[50 50 1250 780]; drawnow;
check('viewer wide layout restores', numel(v.Grid.ColumnWidth)==3 && ...
    string(v.Grid.Scrollable)=="off" && isequal(v.SideGrid.Layout.Row,[2 3]), '1250x780, responsive');
nObj = numel(findall(app.OfdmView.Figure));
for k = 2:21, enqueue("wave", k, 0); app.tick(); end
check('graphics objects constant over 20 frames', numel(findall(app.OfdmView.Figure)) == nObj && app.Ofdm.ValidFrames >= 21, ...
    sprintf('%d objects before and after, %d valid frames', nObj, app.Ofdm.ValidFrames));
enqueue("blank", 22, 0); app.tick();
v = app.OfdmView;
check('blank: current cleared, history labelled', isempty(app.Ofdm.Current) && contains(v.Banner.Text, "UNAVAILABLE") && ...
    all(isnan(v.H.pay.XData)) && any(contains(string(v.Text.Value), "HISTORY (not current): last valid seq 21")) && ...
    contains(strjoin(string(app.UIAxes.Title.String)), "unavailable"), string(v.Banner.Text));
enqueue("wave", 23, 0); app.tick();
okRecover = ~isempty(app.Ofdm.Current) && app.Ofdm.Current.sequence == 23;
enqueue("wave", 24, 3); app.tick();
check('recovery, then stale frame clears', okRecover && isempty(app.Ofdm.Current) && contains(v.Banner.Text, "UNAVAILABLE"), ...
    string(v.Banner.Text));
enqueue("wave", 25, 1.8); app.tick();
shown = ~isempty(app.Ofdm.Current);
pause(0.3); app.displayWatchdog();   % the shown result is now older than 2 s
check('watchdog clears an aged result', shown && isempty(app.Ofdm.Current) && contains(v.Banner.Text, "expired"), string(v.Banner.Text));
app.VSACheckBox.Value = false; cb = app.VSACheckBox.ValueChangedFcn; cb(app.VSACheckBox, struct());
enqueue("wave", 26, 0); app.tick();
offOk = isempty(app.Ofdm.Current) && strcmp(v.Figure.Visible, 'off');
app.VSACheckBox.Value = true; cb(app.VSACheckBox, struct());
enqueue("wave", 27, 0); app.tick();
check('VSA checkbox switches the analyzer', offOk && ~isempty(app.Ofdm.Current) && app.Ofdm.Current.sequence == 27, 'off: no analysis; on: frame 27 analysed');
% MVDRman refusal (the 10:55 UTC stop): rejected before app.doa changes
doa0 = privGet(app, 'doa'); err0 = app.Controller.TotalErrors;
for mode = ["MVDRman", "MVDRman_corr"]
    app.DOAtypeListBox.Value = char(mode); cbd = app.DOAtypeListBox.ValueChangedFcn; cbd(app.DOAtypeListBox, struct());
end
for k = 28:34, enqueue("wave", k, 0); app.tick(); end
check('MVDRman without tables refused, run continues', isequal(privGet(app, 'doa'), doa0) && isequal(app.DOAtypeListBox.Value, doa0) && ...
    app.Controller.IsOpen && app.Controller.ConsecutiveErrors == 0 && app.Controller.TotalErrors == err0 && any(contains(app.Notes, "MVDRman needs")), ...
    sprintf('doa stays %s; errors %d; %s', doa0, app.Controller.TotalErrors, app.Notes(contains(app.Notes, "MVDRman"))));
G = numel(app.scan_axis);
app.Config.calibration.powCalibration = ones(G, 4);
app.DOAtypeListBox.Value = 'MVDRman'; cbd(app.DOAtypeListBox, struct());
check('MVDRman accepted with powCalibration', isequal(privGet(app, 'doa'), 'MVDRman'), sprintf('%d-by-4 table', G));
viewerFig = app.OfdmView.Figure;
delete(app);
check('close deletes owned viewer, no timers left', ~isvalid(viewerFig) && numel(timerfindall) == timers0 && ...
    isempty(findall(groot, 'Tag', 'IntegratedCustomOfdm')), sprintf('timers %d', numel(timerfindall)));
% both: VSA gets the identical buffer
cfg = base; cfg.analyzer = "both"; sent = {};
app = VSA_rfsoc_refactor_exported(cfg); app.Controller.open();
enqueue("wave", 1, 0); app.tick();
check('both: VSA comparison gets the same buffer', numel(sent) == 1 && ~isempty(app.Ofdm.Current) && ...
    contains(strjoin(string(app.UIAxes.Title.String)), "Integrated Custom OFDM") && contains(strjoin(string(app.UIAxes.Title.String)), "VSA:"), ...
    strjoin(string(app.UIAxes.Title.String), ' | '));
delete(app);
cfg = base; cfg.analyzer = "vsa"; sent = {};
app = VSA_rfsoc_refactor_exported(cfg); app.Controller.open();
enqueue("wave", 1, 0); app.tick();
check('vsa only: no analyzer, no viewer', isempty(app.Ofdm) && isempty(app.OfdmView) && numel(sent) == 1, 'native path unchanged');
delete(app);
cfg = base; cfg.analyzer = "integrated"; cfg.ofdm.setupSha256 = "";
check('start-up: integrated without pinned SHA errors', throws(@() VSA_rfsoc_refactor_exported(cfg), 'origapp:Ofdm'), 'explicit error, no fallback');
cfg = base; cfg.analyzer = "integrated"; cfg.ofdm.orientation = "";
check('start-up: orientation must be explicit', throws(@() VSA_rfsoc_refactor_exported(cfg), 'origapp:Ofdm'), 'explicit error');
cfg = base; cfg.analyzer = "fast";
check('start-up: unknown analyzer errors', throws(@() VSA_rfsoc_refactor_exported(cfg), 'origapp:Config'), 'explicit error');
check('no stray figures/timers at end', isempty(findall(groot, 'Tag', 'IntegratedCustomOfdm')) && numel(timerfindall) == timers0 && ...
    numel(findall(groot,'Type','figure'))==figures0, ...
    sprintf('timers %d, figures %d (baseline %d)', numel(timerfindall),numel(findall(groot,'Type','figure')),figures0));
results = T;
fid = fopen(fullfile(outDir, 'ofdm_fixture.json'), 'w'); fwrite(fid, jsonencode(T, 'PrettyPrint', true)); fclose(fid);
assert(all([T.ok]), 'ofdm:Fixture', '%d check(s) failed', nnz(~[T.ok]));
fprintf('%d/%d checks passed\nOFDM_FIXTURE_COMPLETE\n', nnz([T.ok]), numel(T));
end

function tf = throws(f, id)
tf = false;
try
    f();
catch e
    tf = startsWith(string(e.identifier), string(id));
end
end

function v = privGet(obj, name)
w = warning('off', 'all'); s = struct(obj); warning(w);
v = s.(name);
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
