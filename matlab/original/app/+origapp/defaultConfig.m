function cfg = defaultConfig()
%DEFAULTCONFIG Session configuration for VSA_rfsoc_refactor_exported.
% Algorithm/UI fields keep the property names and defaults of the original
% VSA_rfsoc_exported (SI units). Session fields are new and default to the
% safe state: no backend, no board/instrument commands, no external windows.
% Network endpoints, instrument names and calibration data are NOT stored
% here; pass them in a private cfg (see BACKEND_CONTRACT.md).

cfg = struct();
%% Session / safety (refactor)
cfg.backend = [];                 % injected backend (struct of handles or object); [] = idle
cfg.originalRepoPath = "";        % read-only vsa_rfsoc checkout: Functions/, koef.mat, Settings/
cfg.iqtoolsPath = "";             % only used by the IQtools button
cfg.outputDir = "";               % raw saves and phase-calibration output (never the repo)
cfg.visible = false;              % hidden construction by default (headless fixtures)
cfg.autoStart = false;            % true: start the acquisition timer after construction
cfg.periodSeconds = 0.1;          % acquisition timer period
cfg.frameTimeoutSeconds = 1;      % bound for one backend.next call
cfg.staleSeconds = 2;             % older frames / longer gaps clear DOA and pattern
cfg.maxConsecutiveErrors = 5;     % then the timer stops and the backend is closed
cfg.directOnly = true;            % conducted/direct mode: no physical DOA or pattern
cfg.allowBoardCommands = false;   % queued board commands are only sent when true
cfg.sendInitialTuning = false;    % original startup 'fc .../dataChan' command; off by default
cfg.allowInstrumentCommands = false; % signal generator (genCtrl), Arduino programming
cfg.allowExternalWindows = false; % plotResponse/plotSpectrum figures, Pluto, IQtools, dialogs
cfg.bfEngine = "reviewed";        % "original" (vsa_rfsoc Functions) or "reviewed" (+rfsoc.beamform)
cfg.reviewed = struct();          % rfsoc.defaultConfig-style struct for bfEngine="reviewed"
cfg.reviewedPath = "";            % folder containing +rfsoc (reviewed demo matlab/)
cfg.elementModel = "patch";       % "patch" = original antPrep; "isotropic" = explicit alternative
cfg.generator = struct('address',"",'port',5025);
cfg.calibration = struct('powCalibration',[],'steeringCorrection',[],'koef',[]);
cfg.vsaSetupFile = "";            % .setx handed to backend.vsaReset (VSA is backend-owned)

%% Original algorithm / UI state (VSA_rfsoc_exported property names)
cfg.vsa = 1; cfg.ch = 5; cfg.bf = 'Steering'; cfg.doa = 'MVDR';
cfg.cutter = 0; cfg.off = 500; cfg.gap = 0; cfg.ang_num = 1;
cfg.diag = 1; cfg.bwOff = 0.1; cfg.dataChan = 2^14; cfg.scan_res = 1;
cfg.debug = 0; cfg.plotUpd = 1; cfg.MatlabPattern = 0; cfg.avg_factor = 10;
cfg.updrate = 10; cfg.c1 = 0; cfg.c2 = 0; cfg.patternCorr = 0; cfg.numFiles = 1;
cfg.fcAnt = 5.1e9; cfg.alg_scan_res = 1; cfg.mis_ang = 15; cfg.alpha = 1.1;
cfg.gamma = 1; cfg.iter = 1;
cfg.fc = 5.1e9; cfg.fsRfsoc = 125e6; cfg.fsDAC = 500e6; cfg.bw = 100e6;
cfg.num = 1; cfg.scan_bw = 120; cfg.num_elements = 4;
cfg.start_ang = -60; cfg.step_ang = 10;
cfg.dataStream = 1; cfg.nyquistZone = 1; cfg.nyquistZone_d0 = 1; cfg.nyquistZone_d1 = 1;
cfg.fc_d0 = 5.1e9; cfg.fc_d1 = 5.1e9; cfg.dphase = [0 0 0 0]; cfg.dacPow = [1 0 1 0];
cfg.da = 1; cfg.bwDac = 499e6; cfg.fsOrig = 60e6; cfg.dacFilt = 0; cfg.resmp = 0;
cfg.adcMirror = -1; cfg.dacAngle = 0; cfg.dacSignalType = 4; cfg.dacFc = 0;
cfg.dacFe = 50; cfg.dacSR = 1; cfg.dacAmp = 2^14-1;
cfg.fcInt = 5.7e9; cfg.stateInt = 0; cfg.powInt = 0; cfg.modInt = 0;
end
