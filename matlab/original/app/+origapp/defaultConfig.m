function cfg = defaultConfig()
%DEFAULTCONFIG Session configuration of the beamformer app (SI units).
% Algorithm fields keep the property names of the original vsa_rfsoc app.
% Session fields default to the safe state: no backend and no board
% commands. RFSoCBeamformer sets the hardware and demo profiles on top of
% these. Network endpoints and calibration data are never stored here.

cfg = struct();
%% Session
cfg.backend = [];                 % injected backend (struct of handles or object); [] = idle
cfg.originalRepoPath = "";        % vsa_rfsoc checkout (Functions/, Settings/) when run from source
cfg.outputDir = "";               % snapshots and command logs (never the repository)
cfg.theme = "light";              % "light" or "dark" (switchable live)
cfg.visible = false;              % hidden construction (tests); the app shows the window
cfg.periodSeconds = 0.1;          % acquisition timer period
cfg.displayPeriodSeconds = 0.1;   % the window is redrawn at most this often; every frame is processed
cfg.frameTimeoutSeconds = 1;      % bound for one backend.next call
cfg.staleSeconds = 2;             % older frames / longer gaps clear the current plots
cfg.maxConsecutiveErrors = 5;     % then the timer stops and the backend is closed
cfg.directOnly = true;            % one measured stream only: no DOA or pattern
cfg.arrayLabel = "array model";   % DOA/pattern scope shown in the footer
cfg.allowBoardCommands = false;   % board commands (RF, phases, DACs, pause) only when true
cfg.bfEngine = "reviewed";        % "original" (vsa_rfsoc Functions) or "reviewed" (+rfsoc.beamform)
cfg.reviewed = struct();          % rfsoc.defaultConfig-style struct for bfEngine="reviewed"
cfg.reviewedPath = "";            % folder containing +rfsoc when run from source
cfg.elementModel = "patch";       % "patch" (Antenna Toolbox, not deployable) or "isotropic"
cfg.calibration = struct('powCalibration',[],'steeringCorrection',[],'koef',[],'couplingMatrix',[]);
cfg.ofdmSetupFile = "";           % pinned .setx of the OFDM profile (ofdm_iq_100_16_4x2.setx)
cfg.ofdm = struct('setupSha256', "", 'referenceMat', "", 'orientation', "", ...
    'syncThreshold', 0.8, 'lockThreshold', 0.3, 'staleSeconds', 2, 'logFile', "", 'maxBursts', Inf);
                                  % OFDM analyzer: pinned SETX sha, transmitted loop (.mat ref125),
                                  % buffer orientation, own preamble-correlation threshold

%% Processing (original vsa_rfsoc property names)
cfg.ch = 5; cfg.bf = 'Steering'; cfg.doa = 'MVDR';
cfg.cutter = 0; cfg.off = 500; cfg.ang_num = 1;
cfg.diag = 1; cfg.bwOff = 0.1; cfg.dataChan = 2^14; cfg.scan_res = 1;
cfg.avg_factor = 10; cfg.c1 = 0; cfg.c2 = 0;
cfg.fcAnt = 5.1e9; cfg.alg_scan_res = 1; cfg.mis_ang = 15; cfg.alpha = 1.1;
cfg.gamma = 1; cfg.iter = 1;
cfg.fc = 5.1e9; cfg.fsRfsoc = 125e6; cfg.bw = 100e6;
cfg.num = 1; cfg.scan_bw = 120; cfg.num_elements = 4;
cfg.dataStream = 1; cfg.nyquistZone = 1; cfg.nyquistZone_d0 = 1; cfg.nyquistZone_d1 = 1;
cfg.fc_d0 = 5.1e9; cfg.fc_d1 = 5.1e9; cfg.dphase = [0 0 0 0]; cfg.dacPow = [1 0 1 0];
cfg.da = 1; cfg.adcMirror = -1;

%% Receive corrections (vsa_rfsoc HEAD 2d8610a); all off by default
cfg.IQcomp = 0;                   % static receive IQ compensation (frozen filter)
cfg.adIQcomp = 0;                 % adaptive receive IQ compensation (LMS)
cfg.sizeL = 4;                    % IQ filter length L
cfg.stepMU = 1e-16;               % LMS step (original default)
cfg.phComp = 0;                   % phase/power comp from steeringCorrection/powCalibration
cfg.coupComp = 0;                 % coupling comp from calibration.couplingMatrix
cfg.manualMvdrFormula = "45e726b";% MVDRman formula: "45e726b" (default) or "head" (m_mvdr)
cfg.plotMirror = 0;               % mirror DOA/pattern display (display and board OLED only)
end
