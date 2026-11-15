classdef VSA_rfsoc_refactor_exported < matlab.apps.AppBase
    % Refactor of VSA_rfsoc_exported (vsa_rfsoc, original 4x2 app).
    % UI components and layout: copied from the original createComponents.
    % Behaviour: owned timer, injected backend, bounded transport, freshness,
    % explicit errors and cleanup. Construct with a session config:
    %   app = VSA_rfsoc_refactor_exported(cfg)      % cfg from origapp.defaultConfig
    %   app = VSA_rfsoc_refactor_exported('backend', b, 'visible', true, ...)
    % Startup sends no board, RF, clock, VSA or instrument command.

    % Properties that correspond to app components
    properties (Access = public)
        RFSoCBeamformerUIFigure        matlab.ui.Figure
        GridLayout                     matlab.ui.container.GridLayout
        LeftPanel                      matlab.ui.container.Panel
        PlotCheckBox                   matlab.ui.control.CheckBox
        CustomCommandTextArea          matlab.ui.control.TextArea
        CustomCommandTextAreaLabel     matlab.ui.control.Label
        VSACheckBox                    matlab.ui.control.CheckBox
        AvgSpinner                     matlab.ui.control.Spinner
        AvgSpinnerLabel                matlab.ui.control.Label
        TabGroup                       matlab.ui.container.TabGroup
        MainTab                        matlab.ui.container.Tab
        ChannelselectListBox           matlab.ui.control.ListBox
        ChannelselectListBoxLabel      matlab.ui.control.Label
        BFtypeListBox                  matlab.ui.control.ListBox
        BFtypeListBoxLabel             matlab.ui.control.Label
        DOAtypeListBox                 matlab.ui.control.ListBox
        DOAtypeListBoxLabel            matlab.ui.control.Label
        DOAresolutionEditField         matlab.ui.control.NumericEditField
        DOAresolutionEditField_3Label  matlab.ui.control.Label
        SignalpriorityButtonGroup      matlab.ui.container.ButtonGroup
        LessPowerfullButton            matlab.ui.control.RadioButton
        MostPowerfullButton            matlab.ui.control.RadioButton
        SystemTab                      matlab.ui.container.Tab
        SREditField                    matlab.ui.control.NumericEditField
        SREditFieldLabel               matlab.ui.control.Label
        FeEditField                    matlab.ui.control.NumericEditField
        FeEditFieldLabel               matlab.ui.control.Label
        FcEditField                    matlab.ui.control.NumericEditField
        FcEditFieldLabel               matlab.ui.control.Label
        DacSignalDropDown              matlab.ui.control.DropDown
        DacSignalDropDownLabel         matlab.ui.control.Label
        AntennaFcSpinner               matlab.ui.control.Spinner
        AntennaFcSpinnerLabel          matlab.ui.control.Label
        AntennaLabel                   matlab.ui.control.Label
        SyncButton                     matlab.ui.control.Button
        MirrorCheckBox                 matlab.ui.control.CheckBox
        FiltBWEditField                matlab.ui.control.NumericEditField
        FiltBWEditFieldLabel           matlab.ui.control.Label
        FilterCheckBox                 matlab.ui.control.CheckBox
        OrigFSEditField                matlab.ui.control.NumericEditField
        OrigFSEditFieldLabel           matlab.ui.control.Label
        ResampleCheckBox               matlab.ui.control.CheckBox
        PowerCheckBox_2                matlab.ui.control.CheckBox
        SYNCDropDown                   matlab.ui.control.DropDown
        SYNCDropDownLabel              matlab.ui.control.Label
        EvenNyquistZoneCheckBox_2      matlab.ui.control.CheckBox
        AngleSpinner                   matlab.ui.control.Spinner
        AngleSpinnerLabel              matlab.ui.control.Label
        dataStreamCheckBox             matlab.ui.control.CheckBox
        RFSoCFcSpinner_2               matlab.ui.control.Spinner
        RFSoCFcSpinner_2Label          matlab.ui.control.Label
        DACsLabel                      matlab.ui.control.Label
        ADCsLabel                      matlab.ui.control.Label
        EvenNyquistZoneCheckBox        matlab.ui.control.CheckBox
        RecalibrateADCsButton          matlab.ui.control.Button
        fcGenSpinner                   matlab.ui.control.Spinner
        fcGenSpinnerLabel              matlab.ui.control.Label
        gainGenSpinner                 matlab.ui.control.Spinner
        gainGenSpinnerLabel            matlab.ui.control.Label
        PowerCheckBox                  matlab.ui.control.CheckBox
        ModCheckBox                    matlab.ui.control.CheckBox
        ScanBWEditField                matlab.ui.control.NumericEditField
        ScanBWEditFieldLabel           matlab.ui.control.Label
        LoadVSAsetupButton             matlab.ui.control.Button
        SigBWSpinner                   matlab.ui.control.Spinner
        SigBWSpinnerLabel              matlab.ui.control.Label
        MaxSignalsSpinner              matlab.ui.control.Spinner
        MaxSignalsSpinnerLabel         matlab.ui.control.Label
        RFSoCFsSpinner                 matlab.ui.control.Spinner
        RFSoCFsSpinnerLabel            matlab.ui.control.Label
        RFSoCFcSpinner                 matlab.ui.control.Spinner
        RFSoCFcSpinnerLabel            matlab.ui.control.Label
        DownconverterTab               matlab.ui.container.Tab
        StepangEditField               matlab.ui.control.NumericEditField
        StepangEditFieldLabel          matlab.ui.control.Label
        StarrangEditField              matlab.ui.control.NumericEditField
        StarrangEditFieldLabel         matlab.ui.control.Label
        ArduinoprogramButton           matlab.ui.control.Button
        StartphasecalibrationsButton   matlab.ui.control.Button
        Gauge                          matlab.ui.control.SemicircularGauge
        DebugTab                       matlab.ui.container.Tab
        SaveButton                     matlab.ui.control.Button
        NumberofsavedfilesEditField    matlab.ui.control.NumericEditField
        NumberofsavedfilesLabel        matlab.ui.control.Label
        DebugCheckBox_2                matlab.ui.control.CheckBox
        CutterCheckBox                 matlab.ui.control.CheckBox
        iterEditField                  matlab.ui.control.NumericEditField
        iterEditFieldLabel             matlab.ui.control.Label
        alphaEditField                 matlab.ui.control.NumericEditField
        alphaEditFieldLabel            matlab.ui.control.Label
        gammaEditField                 matlab.ui.control.NumericEditField
        gammaEditFieldLabel            matlab.ui.control.Label
        alg_scan_resEditField          matlab.ui.control.NumericEditField
        alg_scan_resEditFieldLabel     matlab.ui.control.Label
        mis_angEditField               matlab.ui.control.NumericEditField
        mis_angEditFieldLabel          matlab.ui.control.Label
        patternCorrCheckBox            matlab.ui.control.CheckBox
        BWEditField                    matlab.ui.control.NumericEditField
        BWEditFieldLabel               matlab.ui.control.Label
        GetSpectrumButton              matlab.ui.control.StateButton
        DLFEditField                   matlab.ui.control.NumericEditField
        DLFEditFieldLabel              matlab.ui.control.Label
        UpdRateEditField               matlab.ui.control.NumericEditField
        UpdRateEditFieldLabel          matlab.ui.control.Label
        MatlabPatternCheckBox          matlab.ui.control.CheckBox
        c2CheckBox                     matlab.ui.control.CheckBox
        c1CheckBox                     matlab.ui.control.CheckBox
        dataChanEditField              matlab.ui.control.NumericEditField
        dataChanEditFieldLabel         matlab.ui.control.Label
        CutoffsetEditField             matlab.ui.control.NumericEditField
        CutoffsetEditFieldLabel        matlab.ui.control.Label
        GetPatternButton               matlab.ui.control.StateButton
        ResetButton                    matlab.ui.control.StateButton
        PlutoButton                    matlab.ui.control.Button
        IQtoolsButton                  matlab.ui.control.Button
        RightPanel                     matlab.ui.container.Panel
        GridLayout2                    matlab.ui.container.GridLayout
        UIAxes2                        matlab.ui.control.UIAxes
        UIAxes                         matlab.ui.control.UIAxes
    end

    % Properties that correspond to apps with auto-reflow
    properties (Access = private)
        onePanelWidth = 576;
    end

    % Original state (same names; values come from the session config)
    properties (Access = private)
        vsa; ch; bf; doa; cutter; off; gap; ang_num; diag; bwOff; dataChan
        scan_res; debug; plotUpd; MatlabPattern; avg_factor; updrate; c1; c2
        patternCorr; numFiles; saveFlg = 0; saveName = ''
        ula; fcAnt; c = physconst('LightSpeed'); alg_scan_res; mis_ang; alpha; gamma; iter
        fc; fsRfsoc; fsDAC; bw; num; scan_bw
        start_ang; step_ang; cur_ang = 0; phase_cal = 0; phase_cal_dir = ''; phase_cal_capture = 0
        reset_req = 1; part_reset_req = 1; estimator; estimatorKind = ""
        dataStream; nyquistZone; nyquistZone_d0; nyquistZone_d1; fc_d0; fc_d1
        dphase; dacPow; da; bwDac; fsOrig; dacFilt; resmp; adcMirror; dacAngle
        dacSignalType; dacFc; dacFe; dacSR; dacAmp
        p_manual_mean; yspec_mean; plot_handle
        lineHandles = struct('am',[],'bs',[],'cs',[],'am2',[],'bs2',[],'cs2',[])
        patternCount = 1; fileCnt = 1; saveFile = struct('raw', {})
        Busy = false
        ExternalFigures = gobjects(0)
    end

    properties (Access = public)
        scan_axis = -90:1:90;
        koef;
        num_elements = 4;
        fcInt; stateInt; powInt; modInt
        weights
        % Refactor session objects (read-only use from tests/parent)
        Config
        Controller
        AcqTimer = []
        Status = "idle"
        Notes = strings(0,1)     % advisories (held commands, backend features absent)
        CurrentDoa = []          % estimated angles of the last accepted frame, [] when invalid
        CurrentPattern = []      % averaged pattern (dB) of the last accepted frame, [] when invalid
        LastResult = []
    end

    methods (Access = public)

        function startAcquisition(app)
            % Explicit start (also the Reset button). Opens the injected
            % backend and starts the owned timer.
            if isempty(app.AcqTimer) || ~isvalid(app.AcqTimer), return; end
            if ~app.Controller.hasBackend()
                setStatus(app, "no backend injected: acquisition not started");
                return
            end
            app.Controller.open();
            if strcmp(app.AcqTimer.Running, 'off')
                start(app.AcqTimer);
            end
            setStatus(app, "running");
        end

        function stopAcquisition(app, reason)
            if nargin < 2, reason = "stopped"; end
            if ~isempty(app.AcqTimer) && isvalid(app.AcqTimer) && strcmp(app.AcqTimer.Running, 'on')
                stop(app.AcqTimer);
            end
            if ~isempty(app.Controller), app.Controller.close(); end
            clearCurrent(app, reason);
        end

        function tick(app)
            % One acquisition/processing step (timer callback; callable from tests).
            if app.Busy, return; end
            app.Busy = true;
            busyGuard = onCleanup(@() setBusy(app, false));
            try
                if app.reset_req
                    resetApp(app);
                elseif app.part_reset_req
                    partReset(app);
                end
                [frame, st] = app.Controller.acquire();
                if isempty(frame)
                    if st == "stale"
                        clearCurrent(app, "no fresh frame");
                    end
                    return
                end
                if app.Config.directOnly
                    processDirect(app, frame);
                else
                    processArray(app, frame);
                    setStatus(app, sprintf('running: frame %g', frame.sequence));
                end
                app.Controller.recordSuccess();
            catch err
                handleFailure(app, err);
            end
        end
    end

    methods (Access = private)

        function setBusy(app, value)
            if isvalid(app), app.Busy = value; end
        end

        function setStatus(app, msg)
            app.Status = string(msg);
            if app.debug, disp(app.Status); end
        end

        function applyConfig(app, cfg)
            names = {'vsa','ch','bf','doa','cutter','off','gap','ang_num','diag','bwOff', ...
                'dataChan','scan_res','debug','plotUpd','MatlabPattern','avg_factor','updrate', ...
                'c1','c2','patternCorr','numFiles','fcAnt','alg_scan_res','mis_ang','alpha', ...
                'gamma','iter','fc','fsRfsoc','fsDAC','bw','num','scan_bw','num_elements', ...
                'start_ang','step_ang','dataStream','nyquistZone','nyquistZone_d0', ...
                'nyquistZone_d1','fc_d0','fc_d1','dphase','dacPow','da','bwDac','fsOrig', ...
                'dacFilt','resmp','adcMirror','dacAngle','dacSignalType','dacFc','dacFe', ...
                'dacSR','dacAmp','fcInt','stateInt','powInt','modInt'};
            for k = 1:numel(names)
                app.(names{k}) = cfg.(names{k});
            end
        end

        function syncControlsFromState(app)
            % Original controls showed values that differed from the state the
            % loop used (e.g. Fc 1000 MHz vs fc = 5.1 GHz). Controls now show
            % the state actually used.
            app.VSACheckBox.Value = logical(app.vsa);
            app.ChannelselectListBox.Value = num2str(app.ch);
            app.BFtypeListBox.Value = char(app.bf);
            app.DOAtypeListBox.Value = char(app.doa);
            app.DOAresolutionEditField.Value = app.scan_res;
            if app.ang_num == 2
                app.SignalpriorityButtonGroup.SelectedObject = app.LessPowerfullButton;
            else
                app.SignalpriorityButtonGroup.SelectedObject = app.MostPowerfullButton;
            end
            app.RFSoCFcSpinner.Value = app.fc/1e6;
            app.RFSoCFsSpinner.Value = app.fsRfsoc/1e6;
            app.MaxSignalsSpinner.Value = app.num;
            app.SigBWSpinner.Value = app.bw/1e6;
            app.ScanBWEditField.Value = app.scan_bw;
            app.AvgSpinner.Value = app.avg_factor;
            app.AntennaFcSpinner.Value = app.fcAnt/1e6;
            app.RFSoCFcSpinner_2.Value = app.fc_d0/1e6;
            app.EvenNyquistZoneCheckBox.Value = app.nyquistZone == 2;
            app.EvenNyquistZoneCheckBox_2.Value = app.nyquistZone_d0 == 2;
            app.MirrorCheckBox.Value = app.adcMirror == -1;
            app.dataStreamCheckBox.Value = logical(app.dataStream);
            app.PowerCheckBox_2.Value = logical(app.dacPow(1));
            app.SYNCDropDown.Value = app.da;
            app.AngleSpinner.Value = app.dacAngle;
            app.dataChanEditField.Value = app.dataChan;
            app.CutoffsetEditField.Value = app.off;
            app.CutterCheckBox.Value = logical(app.cutter);
            app.DLFEditField.Value = app.diag;
            app.BWEditField.Value = app.bwOff;
            app.UpdRateEditField.Value = app.updrate;
            app.mis_angEditField.Value = app.mis_ang;
            app.alg_scan_resEditField.Value = app.alg_scan_res;
            app.gammaEditField.Value = app.gamma;
            app.alphaEditField.Value = app.alpha;
            app.iterEditField.Value = app.iter;
            app.c1CheckBox.Value = logical(app.c1);
            app.c2CheckBox.Value = logical(app.c2);
            app.MatlabPatternCheckBox.Value = logical(app.MatlabPattern);
            app.patternCorrCheckBox.Value = logical(app.patternCorr);
            app.DebugCheckBox_2.Value = logical(app.debug);
            app.PlotCheckBox.Value = logical(app.plotUpd);
            app.StarrangEditField.Value = app.start_ang;
            app.StepangEditField.Value = app.step_ang;
            app.fcGenSpinner.Value = app.fcInt/1e6;
            app.gainGenSpinner.Value = app.powInt;
            app.PowerCheckBox.Value = logical(app.stateInt);
            app.ModCheckBox.Value = logical(app.modInt);
        end

        function resetApp(app)
            partReset(app);
            app.ResetButton.Text = 'Reseting...';
            app.ResetButton.BackgroundColor = 'r';
            % Original: vsaDdc (create/attach 89600 VSA, DirectDataSource) and
            % vsaSetup (VISA hislip load of the .setx). VSA is backend-owned.
            request = struct('fs', app.fsRfsoc, 'dataChan', app.dataChan, ...
                'setupFile', string(app.Config.vsaSetupFile));
            if app.vsa && ~app.Controller.vsaReset(request)
                note(app, "VSA reset not available from backend (VSA is backend-owned)");
            end
            app.reset_req = 0;
            app.part_reset_req = 0;
            app.ResetButton.Text = 'Reset';
            app.ResetButton.BackgroundColor = 'g';
        end

        function partReset(app)
            app.ResetButton.Text = 'Reseting...';
            app.ResetButton.BackgroundColor = 'y';
            % Original prepended 'da' and 'dataStream' and reconnected; here
            % the queue goes to backend.send only when board commands are allowed.
            queueCommand(app, ['da ' num2str(app.da)]);
            queueCommand(app, ['dataStream ' num2str(app.dataStream)]);
            msg = app.Controller.flushCommands();
            if strlength(msg) > 0, note(app, msg); end
            app.Controller.setDataChan(app.dataChan);
            app.ula = buildArray(app);
            app.scan_axis = -app.scan_bw/2:app.scan_res:app.scan_bw/2;
            prepPlots(app);
            app.p_manual_mean = zeros(length(app.scan_axis), app.avg_factor);
            app.yspec_mean = zeros(length(app.scan_axis), app.avg_factor);
            [app.estimator, app.estimatorKind] = origapp.makeEstimator(app.doa, app.ula, ...
                app.scan_axis, app.num, app.fc, app.Config.calibration);
            app.koef = loadKoef(app);
            app.part_reset_req = 0;
            app.ResetButton.Text = 'Reset';
            app.ResetButton.BackgroundColor = 'g';
        end

        function ula = buildArray(app)
            if app.Config.elementModel == "patch"
                ula = antPrep(app.num_elements, app.c, app.fcAnt);   % original
            else
                ula = phased.ULA('NumElements', app.num_elements, ...
                    'ElementSpacing', app.c/app.fcAnt/2);
            end
        end

        function k = loadKoef(app)
            % Original: bare 'load koef' from the working folder.
            k = app.Config.calibration.koef;
            if isempty(k) && strlength(string(app.Config.originalRepoPath)) > 0
                f = fullfile(app.Config.originalRepoPath, 'koef.mat');
                if isfile(f)
                    s = load(f, 'koef'); k = s.koef;
                end
            end
            if isempty(k)
                k = [];
                return
            end
            k = interp1(linspace(1,length(k),length(k))', k(:), ...
                linspace(1,length(k),length(app.scan_axis))', 'linear', 'extrap');
        end

        function prepPlots(app)
            % Original plotPrep with cla instead of clf on uiaxes.
            cla(app.UIAxes); cla(app.UIAxes2);
            app.lineHandles = struct('am',[],'bs',[],'cs',[],'am2',[],'bs2',[],'cs2',[]);
            app.plot_handle = plot(app.UIAxes, app.scan_axis, nan(size(app.scan_axis)));
            app.UIAxes.XLim = [app.scan_axis(1) app.scan_axis(end)];
            app.UIAxes2.XLim = [app.scan_axis(1) app.scan_axis(end)];
            app.UIAxes.YLim = [0 1];
            app.UIAxes2.YLim = [-30 0.5];
            app.UIAxes.LineWidth = 2.5;
            app.UIAxes2.LineWidth = 2.5;
            app.UIAxes.XLabel.String = '\Theta^o';
            app.UIAxes.YLabel.String = 'DOA Normalized Spectrum';
            app.UIAxes2.XLabel.String = '\Theta^o';
            app.UIAxes2.YLabel.String = 'Gain Pattern (dB)';
            app.UIAxes.FontSize = 30;
            app.UIAxes2.FontSize = 30;
        end

        function p = frameParams(app)
            p = struct('ch', app.ch, 'bf', app.bf, 'doa', app.doa, 'off', app.off, ...
                'cutter', app.cutter, 'ang_num', app.ang_num, 'fc', app.fc, ...
                'dataChan', app.dataChan, 'diag', app.diag, 'bwOff', app.bwOff, ...
                'ula', app.ula, 'scan_axis', app.scan_axis, 'c1', app.c1, 'c2', app.c2, ...
                'fsRfsoc', app.fsRfsoc, 'bw', app.bw, 'c', app.c, ...
                'estimator', app.estimator, 'estimatorKind', app.estimatorKind, ...
                'alg_scan_res', app.alg_scan_res, 'mis_ang', app.mis_ang, ...
                'alpha', app.alpha, 'gamma', app.gamma, 'iter', app.iter, ...
                'calibration', app.Config.calibration, ...
                'bfEngine', string(app.Config.bfEngine), 'reviewed', app.Config.reviewed);
        end

        function processDirect(app, frame)
            % Direct/conducted mode: one RF path, so no physical DOA/pattern.
            clearCurrent(app, "directOnly: no physical DOA/pattern");
            if app.vsa
                chn = app.ch; if chn > 4, chn = 1; end
                buff = frame.samples(:,chn)/2^16;
                if ~app.Controller.sendVsa(buff)
                    note(app, "directOnly: VSA send not available from backend");
                end
            end
            app.LastResult = struct('directOnly', true, 'sequence', getfield(frame, 'sequence')); %#ok<GFLD>
        end

        function processArray(app, frame)
            out = origapp.processLegacyFrame(frame.samples, frameParams(app));
            if any(isnan(out.weights))
                error('origapp:NoSignal', 'No signal (NaN weights).');
            end
            app.weights = out.weights;
            if app.vsa && ~app.Controller.sendVsa(out.vsaBuffer)
                note(app, "VSA send not available from backend");
            end
            app.LastResult = out;
            estimated_angle = out.estimated_angle;
            if app.plotUpd
                renderArray(app, out, estimated_angle);
            end
            saveStep(app, out.rawData);
            phaseCalStep(app, out.rawData);
            app.CurrentDoa = estimated_angle;
        end

        function renderArray(app, out, estimated_angle)
            w = conj(app.weights);
            p_manual = beamPatternCalc(w, app.fc, app.scan_axis, length(w));
            [p_manual_mean_vec, app.p_manual_mean] = avgData(p_manual, app.p_manual_mean);
            p_manual_mean_db = 20*log10(p_manual_mean_vec) - max(20*log10(p_manual_mean_vec));
            app.CurrentPattern = p_manual_mean_db;
            spectrumNote = '';
            if out.spectrumAvailable
                [yspec_mean_vec, app.yspec_mean] = avgData(out.yspec(:), app.yspec_mean);
                if app.patternCorr
                    assert(~isempty(app.koef), 'origapp:Calibration', ...
                        'patternCorr needs koef (cfg.calibration.koef or originalRepoPath/koef.mat).');
                    yspec_mean_vec = yspec_mean_vec.*(1./app.koef);
                end
                set(app.plot_handle, 'YData', yspec_mean_vec/max(yspec_mean_vec), 'LineWidth', 1.5);
            else
                set(app.plot_handle, 'YData', nan(size(app.scan_axis)));
                spectrumNote = [newline '(angle-only estimator: no spectrum)'];
            end
            app.UIAxes.Title.String = ['Direction of Arrival (array model):' newline 'Estimated Angles = ' ...
                num2str(estimated_angle) newline 'DAC Angles = ' num2str(app.dacAngle) spectrumNote];
            cla(app.UIAxes2);
            app.lineHandles.am2 = []; app.lineHandles.bs2 = []; app.lineHandles.cs2 = [];
            plot(app.UIAxes2, app.scan_axis, p_manual_mean_db, 'LineWidth', 1.5);
            main.line = '-b'; main.txt = 'Main'; sub.line = '--c'; sub.txt = 'Sub';
            ea = [estimated_angle NaN NaN];
            L = app.lineHandles;
            L.am = guiXline(L.am, app.UIAxes, main, ea(1), 'right');
            L.am2 = guiXline(L.am2, app.UIAxes2, main, ea(1), 'right');
            if sum(~isnan(ea)) > 1
                L.bs = guiXline(L.bs, app.UIAxes, sub, ea(2), 'center');
                L.bs2 = guiXline(L.bs2, app.UIAxes2, sub, ea(2), 'center');
                null_diff = round(p_manual_mean_db(app.scan_axis == ea(1)) - p_manual_mean_db(app.scan_axis == ea(2)));
                if sum(~isnan(ea)) > 2
                    L.cs = guiXline(L.cs, app.UIAxes, sub, ea(3), 'center');
                    L.cs2 = guiXline(L.cs2, app.UIAxes2, sub, ea(3), 'center');
                end
            else
                null_diff = round(p_manual_mean_db(app.scan_axis == ea(1)) - min(p_manual_mean_db));
            end
            app.lineHandles = L;
            app.UIAxes2.Title.String = ['Beam Pattern [' char(app.Config.bfEngine) ' ' char(app.bf) ']' ...
                newline 'Gain Difference = ' num2str(abs(null_diff)) ' dB'];
            if app.MatlabPattern
                if app.patternCount >= app.updrate
                    openPatternFigure(app);
                    app.patternCount = 1;
                else
                    app.patternCount = app.patternCount + 1;
                end
            end
        end

        function openPatternFigure(app)
            if ~app.Config.allowExternalWindows
                setStatus(app, "MatlabPattern/GetPattern: external windows disabled (cfg.allowExternalWindows)");
                return
            end
            if isempty(app.weights), setStatus(app, "no current weights"); return; end
            f = figure('Name', 'VSA_rfsoc pattern');
            app.ExternalFigures(end+1) = f;
            plotResponse(app.ula, app.fc, app.c, 'AzimuthAngles', app.scan_axis, ...
                'Unit', 'db', 'Weights', app.weights.');
        end

        function saveStep(app, rawData)
            if ~app.saveFlg, return; end
            if app.fileCnt >= app.numFiles
                app.fileCnt = 1;
                app.saveFlg = 0;
                saveFile = app.saveFile;
                save(app.saveName, 'saveFile');
                app.saveFile = struct('raw', {});
            else
                app.saveFile(app.fileCnt).raw = rawData;
                app.fileCnt = app.fileCnt + 1;
            end
        end

        function phaseCalStep(app, rawData)
            % Non-blocking version of the original uiwait loop: each button
            % press captures the next processed frame for the current angle.
            if ~app.phase_cal || ~app.phase_cal_capture, return; end
            app.phase_cal_capture = 0;
            save(fullfile(app.phase_cal_dir, [num2str(app.cur_ang) '.mat']), 'rawData');
            if app.cur_ang == -(app.start_ang)
                phase_scan_axis = -abs(app.start_ang):app.step_ang:abs(app.start_ang);
                meas_mat = [];
                for k = 1:length(phase_scan_axis)
                    % Original loaded phase_scan_axis(1) for every k (bug); each angle here.
                    s = load(fullfile(app.phase_cal_dir, [num2str(phase_scan_axis(k)) '.mat']));
                    meas_mat(:,:,k) = s.rawData; %#ok<AGROW>
                end
                % Original passed (..., fc, c) too; phase_pattern_generator takes 4 inputs.
                figsBefore = findall(groot, 'Type', 'figure');
                [steering_correction, ~, ~] = phase_pattern_generator(meas_mat, phase_scan_axis, ...
                    app.scan_res, app.num_elements);
                % The helper plots; own any new figure so delete(app) removes it.
                newFigs = setdiff(findall(groot, 'Type', 'figure'), figsBefore);
                for k = 1:numel(newFigs), app.ExternalFigures(end+1) = newFigs(k); end
                save(fullfile(app.phase_cal_dir, 'steering_correction.mat'), 'steering_correction');
                app.StartphasecalibrationsButton.Text = 'Press to start calibrations';
                app.phase_cal = 0;
                app.cur_ang = 0;
            else
                app.cur_ang = app.cur_ang + app.step_ang;
                app.StartphasecalibrationsButton.Text = ['Set ' num2str(app.cur_ang) ' deg and press'];
                app.Gauge.Value = app.cur_ang;
            end
        end

        function note(app, msg)
            msg = string(msg);
            if ~any(app.Notes == msg), app.Notes(end+1,1) = msg; end
        end

        function clearCurrent(app, reason)
            % Invalidates the displayed DOA/pattern so stale results are never shown.
            app.CurrentDoa = [];
            app.CurrentPattern = [];
            app.weights = [];
            if ~isempty(app.plot_handle) && isvalid(app.plot_handle)
                set(app.plot_handle, 'YData', nan(size(app.scan_axis)));
            end
            names = fieldnames(app.lineHandles);
            for k = 1:numel(names)
                h = app.lineHandles.(names{k});
                if ~isempty(h) && isvalid(h), delete(h); end
                app.lineHandles.(names{k}) = [];
            end
            if isvalid(app.UIAxes2), cla(app.UIAxes2); end
            if isvalid(app.UIAxes)
                app.UIAxes.Title.String = ['Direction of Arrival: unavailable' newline char(reason)];
                app.UIAxes2.Title.String = ['Beam Pattern: unavailable' newline char(reason)];
            end
            setStatus(app, reason);
        end

        function handleFailure(app, err)
            mustStop = app.Controller.recordFailure(err);
            clearCurrent(app, "frame rejected: " + string(err.message));
            if mustStop
                stopAcquisition(app, sprintf('stopped after %d consecutive errors: %s', ...
                    app.Controller.ConsecutiveErrors, err.message));
            end
        end

        function queueCommand(app, command)
            app.Controller.queue(command);
        end

        function queueFc(app)
            queueCommand(app, ['fc ' num2str(app.fc/1e6*app.adcMirror) '/' num2str(app.nyquistZone) '/' ...
                num2str(app.fc_d0/1e6) '/' num2str(app.nyquistZone_d0) '/' ...
                num2str(app.fc_d1/1e6) '/' num2str(app.nyquistZone_d1)]);
        end

        function queueSource(app)
            queueCommand(app, ['source ' num2str(app.dacSignalType) '/' num2str(app.dacSR) '/' ...
                num2str(app.dacFc) '/' num2str(app.dacFe) '/' num2str(app.dacAmp)]);
        end

        function generatorUpdate(app)
            % Original: genCtrl to the signal generator on every change.
            if ~app.Config.allowInstrumentCommands || strlength(string(app.Config.generator.address)) == 0
                setStatus(app, "generator: not configured or instrument commands disabled");
                return
            end
            genCtrl(char(app.Config.generator.address), app.Config.generator.port, ...
                app.stateInt, app.powInt, app.fcInt, app.modInt);
        end

        function tf = externalAllowed(app, what)
            tf = app.Config.allowExternalWindows;
            if ~tf, setStatus(app, what + ": external windows disabled (cfg.allowExternalWindows)"); end
        end

        function onTimerError(app, ~, evt)
            if isvalid(app)
                setStatus(app, "timer error: " + string(evt.Data.message));
            end
        end
    end


    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app, varargin)
            cfg = origapp.resolveConfig(varargin{:});
            app.Config = cfg;
            if strlength(string(cfg.originalRepoPath)) > 0
                fdir = fullfile(cfg.originalRepoPath, 'Functions');
                assert(isfolder(fdir), 'origapp:Config', 'originalRepoPath has no Functions folder.');
                addpath(fdir);   % read-only helper use; no cd, no genpath of the repo
            end
            if cfg.bfEngine == "reviewed" && strlength(string(cfg.reviewedPath)) > 0
                addpath(char(cfg.reviewedPath));
            end
            applyConfig(app, cfg);
            syncControlsFromState(app);
            app.Controller = origapp.Controller(cfg);
            if cfg.sendInitialTuning
                queueFc(app);
                queueCommand(app, ['dataChan ' num2str(app.dataChan*8)]);
            end
            app.RFSoCBeamformerUIFigure.CloseRequestFcn = @(~,~) delete(app);
            app.AcqTimer = timer('ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
                'Period', cfg.periodSeconds, 'Name', 'VSA_rfsoc_refactor', ...
                'TimerFcn', @(~,~) app.tick(), 'ErrorFcn', @(t,e) app.onTimerError(t,e));
            if cfg.visible
                movegui(app.RFSoCBeamformerUIFigure, "east");
                app.RFSoCBeamformerUIFigure.Visible = 'on';
            end
            if cfg.directOnly
                app.UIAxes.Title.String = ['Direction of Arrival: unavailable' newline 'directOnly'];
            end
            setStatus(app, "idle: press Reset (or call startAcquisition) to start");
            if cfg.autoStart
                startAcquisition(app);
            end
        end

        % Value changed function: VSACheckBox
        function VSACheckBoxValueChanged(app, event)
            app.vsa = app.VSACheckBox.Value;
        end

        % Value changed function: ChannelselectListBox
        function ChannelselectListBoxValueChanged(app, event)
            app.ch = str2double(app.ChannelselectListBox.Value);
        end

        % Value changed function: dataChanEditField
        function dataChanEditFieldValueChanged(app, event)
            app.dataChan = app.dataChanEditField.Value;
            queueCommand(app, ['dataChan ' num2str(app.dataChanEditField.Value*8)]);
            app.reset_req = 1;
        end

        % Button pushed function: IQtoolsButton
        function IQtoolsButtonPushed(app, event)
            if ~externalAllowed(app, "IQtools"), return; end
            assert(isfolder(app.Config.iqtoolsPath), 'origapp:Config', 'Set cfg.iqtoolsPath.');
            addpath(genpath(char(app.Config.iqtoolsPath)));
            iqtools
        end

        % Value changed function: CutterCheckBox
        function CutterCheckBoxValueChanged(app, event)
            app.cutter = app.CutterCheckBox.Value;
        end

        % Value changed function: BFtypeListBox
        function BFtypeListBoxValueChanged(app, event)
            app.bf = app.BFtypeListBox.Value;
        end

        % Selection changed function: SignalpriorityButtonGroup
        function SignalpriorityButtonGroupSelectionChanged(app, event)
            switch app.SignalpriorityButtonGroup.SelectedObject.Text
                case 'Most Powerfull'
                    app.ang_num = 1;
                case 'Less Powerfull'
                    app.ang_num = 2;
            end
        end

        % Value changed function: CutoffsetEditField
        function CutoffsetEditFieldValueChanged(app, event)
            app.off = app.CutoffsetEditField.Value;
        end

        % Value changed function: MatlabPatternCheckBox
        function MatlabPatternCheckBoxValueChanged(app, event)
            app.MatlabPattern = app.MatlabPatternCheckBox.Value;
        end

        % Value changed function: GetPatternButton
        function GetPatternButtonValueChanged(app, event)
            openPatternFigure(app);
        end

        % Value changed function: ResetButton
        function ResetButtonValueChanged(app, event)
            % Original: StateButton requested a reset of the running loop.
            % Refactor: also the explicit start of acquisition.
            app.reset_req = 1;
            app.ResetButton.Value = false;
            startAcquisition(app);
        end

        % Button pushed function: PlutoButton
        function PlutoButtonPushed(app, event)
            if externalAllowed(app, "Pluto"), PlutoControl; end
        end

        % Value changed function: c1CheckBox
        function c1CheckBoxValueChanged(app, event)
            app.c1 = app.c1CheckBox.Value;
        end

        % Value changed function: c2CheckBox
        function c2CheckBoxValueChanged(app, event)
            app.c2 = app.c2CheckBox.Value;
        end

        % Value changed function: RFSoCFcSpinner
        function RFSoCFcSpinnerValueChanged(app, event)
            app.fc = app.RFSoCFcSpinner.Value*1e6;
            queueFc(app);
            app.fc = abs(app.fc);
            app.part_reset_req = 1;
        end

        % Value changed function: RFSoCFsSpinner
        function RFSoCFsSpinnerValueChanged(app, event)
            app.fsRfsoc = app.RFSoCFsSpinner.Value*1e6;
            app.part_reset_req = 1;
        end

        % Value changed function: MaxSignalsSpinner
        function MaxSignalsSpinnerValueChanged(app, event)
            app.num = app.MaxSignalsSpinner.Value;
            app.part_reset_req = 1;   % original did not rebuild the estimator (NumSignals stale)
        end

        % Value changed function: DOAtypeListBox
        function DOAtypeListBoxValueChanged(app, event)
            app.doa = app.DOAtypeListBox.Value;
            app.part_reset_req = 1;
        end

        % Value changed function: AvgSpinner
        function AvgSpinnerValueChanged(app, event)
            app.avg_factor = app.AvgSpinner.Value;
            app.part_reset_req = 1;
        end

        % Value changed function: UpdRateEditField
        function UpdRateEditFieldValueChanged(app, event)
            app.updrate = app.UpdRateEditField.Value;
        end

        % Value changed function: DOAresolutionEditField
        function DOAresolutionEditFieldValueChanged(app, event)
            app.scan_res = app.DOAresolutionEditField.Value;
            app.part_reset_req = 1;
        end

        % Value changed function: DLFEditField
        function DLFEditFieldValueChanged2(app, event)
            app.diag = app.DLFEditField.Value;
        end

        % Value changed function: GetSpectrumButton
        function GetSpectrumButtonValueChanged(app, event)
            if ~externalAllowed(app, "GetSpectrum"), return; end
            assert(isobject(app.estimator), 'origapp:DoaMethod', 'GetSpectrum needs a toolbox estimator.');
            f = figure('Name', 'VSA_rfsoc spectrum');
            app.ExternalFigures(end+1) = f;
            plotSpectrum(app.estimator);
        end

        % Value changed function: SigBWSpinner
        function SigBWSpinnerValueChanged(app, event)
            app.bw = app.SigBWSpinner.Value*1e6;
        end

        % Button pushed function: LoadVSAsetupButton
        function LoadVSAsetupButtonPushed(app, event)
            if ~externalAllowed(app, "Load VSA setup dialog"), return; end
            [file, path] = uigetfile(fullfile(char(app.Config.originalRepoPath), 'Settings', '*.setx'));
            if isequal(file, 0), return; end
            app.Config.vsaSetupFile = string(fullfile(path, file));
            app.reset_req = 1;
        end

        % Value changed function: ScanBWEditField
        function ScanBWEditFieldValueChanged(app, event)
            app.scan_bw = app.ScanBWEditField.Value;
            app.part_reset_req = 1;
        end

        % Value changed function: BWEditField
        function BWEditFieldValueChanged(app, event)
            app.bwOff = app.BWEditField.Value;
        end

        % Value changed function: fcGenSpinner
        function fcGenSpinnerValueChanged(app, event)
            app.fcInt = app.fcGenSpinner.Value*1e6;
            generatorUpdate(app);
        end

        % Value changed function: gainGenSpinner
        function gainGenSpinnerValueChanged(app, event)
            app.powInt = app.gainGenSpinner.Value;
            generatorUpdate(app);
        end

        % Value changed function: ModCheckBox
        function ModCheckBoxValueChanged(app, event)
            app.modInt = app.ModCheckBox.Value;
            generatorUpdate(app);
        end

        % Value changed function: PowerCheckBox
        function PowerCheckBoxValueChanged(app, event)
            app.stateInt = app.PowerCheckBox.Value;
            generatorUpdate(app);
        end

        % Value changed function: patternCorrCheckBox
        function patternCorrCheckBoxValueChanged(app, event)
            app.patternCorr = app.patternCorrCheckBox.Value;
        end

        % Value changed function: mis_angEditField
        function mis_angEditFieldValueChanged(app, event)
            app.mis_ang = app.mis_angEditField.Value;
        end

        % Value changed function: alg_scan_resEditField
        function alg_scan_resEditFieldValueChanged(app, event)
            app.alg_scan_res = app.alg_scan_resEditField.Value;
        end

        % Value changed function: gammaEditField
        function gammaEditFieldValueChanged(app, event)
            app.gamma = app.gammaEditField.Value;
        end

        % Value changed function: alphaEditField
        function alphaEditFieldValueChanged(app, event)
            app.alpha = app.alphaEditField.Value;
        end

        % Value changed function: iterEditField
        function iterEditFieldValueChanged(app, event)
            app.iter = app.iterEditField.Value;
        end

        % Value changed function: CustomCommandTextArea
        function CustomCommandTextAreaValueChanged(app, event)
            queueCommand(app, strjoin(string(app.CustomCommandTextArea.Value), ' '));
        end

        % Button pushed function: RecalibrateADCsButton
        function RecalibrateADCsButtonPushed(app, event)
            queueCommand(app, ['cal ' num2str(8)]);
            app.part_reset_req = 1;
        end

        % Value changed function: dataStreamCheckBox
        function dataStreamCheckBoxValueChanged(app, event)
            app.dataStream = app.dataStreamCheckBox.Value;
            app.part_reset_req = 1;
        end

        % Value changed function: EvenNyquistZoneCheckBox
        function EvenNyquistZoneCheckBoxValueChanged(app, event)
            app.nyquistZone = app.EvenNyquistZoneCheckBox.Value + 1;
            queueFc(app);
            app.part_reset_req = 1;
        end

        % Value changed function: DebugCheckBox_2
        function DebugCheckBox_2ValueChanged(app, event)
            app.debug = app.DebugCheckBox_2.Value;
        end

        % Value changed function: PlotCheckBox
        function PlotCheckBoxValueChanged(app, event)
            app.plotUpd = app.PlotCheckBox.Value;
        end

        % Value changed function: NumberofsavedfilesEditField
        function NumberofsavedfilesEditFieldValueChanged(app, event)
            app.numFiles = app.NumberofsavedfilesEditField.Value + 1;
        end

        % Button pushed function: SaveButton
        function SaveButtonPushed(app, event)
            % Original: uiputfile into .\Signals of the repo. Refactor: cfg.outputDir.
            assert(strlength(string(app.Config.outputDir)) > 0, 'origapp:Config', 'Set cfg.outputDir to save frames.');
            if ~isfolder(app.Config.outputDir), mkdir(app.Config.outputDir); end
            app.saveName = fullfile(char(app.Config.outputDir), ...
                [num2str(app.numFiles - 1) '_RawSavesFromRfsoc_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '.mat']);
            app.fileCnt = 1;
            app.saveFile = struct('raw', {});
            app.saveFlg = 1;
        end

        % Value changed function: SYNCDropDown
        function SYNCDropDownValueChanged(app, event)
            app.da = app.SYNCDropDown.Value;
            app.part_reset_req = 1;
        end

        % Value changed function: RFSoCFcSpinner_2
        function RFSoCFcSpinner_2ValueChanged(app, event)
            app.fc_d0 = app.RFSoCFcSpinner_2.Value*1e6;
            queueFc(app);
            app.part_reset_req = 1;
        end

        % Value changed function: AngleSpinner
        function AngleSpinnerValueChanged(app, event)
            app.dacAngle = app.AngleSpinner.Value;
            if isempty(app.ula), app.ula = buildArray(app); end
            beamforming = phased.SteeringVector('SensorArray', app.ula);
            weight = beamforming(app.fcAnt, app.dacAngle);
            app.dphase = round(rad2deg(angle(weight).'), 2)*100;
            queueCommand(app, ['dphase ' strjoin(arrayfun(@num2str, app.dphase, 'UniformOutput', false), '/')]);
            app.part_reset_req = 1;
        end

        % Value changed function: EvenNyquistZoneCheckBox_2
        function EvenNyquistZoneCheckBox_2ValueChanged(app, event)
            app.nyquistZone_d0 = app.EvenNyquistZoneCheckBox_2.Value + 1;
            queueFc(app);
            app.part_reset_req = 1;
        end

        % Value changed function: PowerCheckBox_2
        function PowerCheckBox_2ValueChanged(app, event)
            app.dacPow(1) = app.PowerCheckBox_2.Value;
            queueCommand(app, ['dacPow ' strjoin(arrayfun(@num2str, app.dacPow, 'UniformOutput', false), '/')]);
            app.part_reset_req = 1;
        end

        % Value changed function: ResampleCheckBox
        function ResampleCheckBoxValueChanged(app, event)
            % Original behaviour kept: only affects the (unwired) DAC file loader.
            app.resmp = app.ResampleCheckBox.Value;
            if ~app.resmp
                app.fsOrig = app.fsDAC;
            end
        end

        % Value changed function: FilterCheckBox
        function FilterCheckBoxValueChanged(app, event)
            app.dacFilt = app.FilterCheckBox.Value;
            if ~app.dacFilt
                app.bwDac = app.fsDAC - 1e6;
            end
        end

        % Value changed function: FiltBWEditField
        function FiltBWEditFieldValueChanged(app, event)
            app.bwDac = app.FiltBWEditField.Value*1e6;
        end

        % Value changed function: OrigFSEditField
        function OrigFSEditFieldValueChanged(app, event)
            app.fsOrig = app.OrigFSEditField.Value*1e6;
        end

        % Button pushed function: StartphasecalibrationsButton
        function StartphasecalibrationsButtonPushed(app, event)
            if app.phase_cal
                app.phase_cal_capture = 1;   % capture next frame at app.cur_ang
                return
            end
            % Original deleted .\phase_cal in the repo (rmdir 's'); refactor
            % writes a new stamped folder under cfg.outputDir instead.
            assert(strlength(string(app.Config.outputDir)) > 0, 'origapp:Config', ...
                'Set cfg.outputDir for phase calibration output.');
            app.phase_cal_dir = fullfile(char(app.Config.outputDir), ...
                ['phase_cal_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
            mkdir(app.phase_cal_dir);
            app.cur_ang = app.start_ang;
            app.phase_cal = 1;
            app.phase_cal_capture = 0;
            app.StartphasecalibrationsButton.Text = ['Set ' num2str(app.cur_ang) ' deg and press'];
            app.Gauge.Value = app.cur_ang;
        end

        % Value changed function: StepangEditField
        function StepangEditFieldValueChanged(app, event)
            app.step_ang = app.StepangEditField.Value;
        end

        % Value changed function: StarrangEditField
        function StarrangEditFieldValueChanged(app, event)
            app.start_ang = app.StarrangEditField.Value;
        end

        % Button pushed function: ArduinoprogramButton
        function ArduinoprogramButtonPushed(app, event)
            if ~app.Config.allowInstrumentCommands
                setStatus(app, "Arduino program: instrument commands disabled");
                return
            end
            arduino_prog();
        end

        % Value changed function: MirrorCheckBox
        function MirrorCheckBoxValueChanged(app, event)
            if app.MirrorCheckBox.Value
                app.adcMirror = -1;
            else
                app.adcMirror = 1;
            end
            app.fc = app.RFSoCFcSpinner.Value*1e6;
            queueFc(app);
            app.part_reset_req = 1;
        end

        % Button pushed function: SyncButton
        function SyncButtonPushed(app, event)
            queueCommand(app, ['sync ' num2str(1)]);
            app.part_reset_req = 1;
        end

        % Value changed function: AntennaFcSpinner
        function AntennaFcSpinnerValueChanged(app, event)
            app.fcAnt = app.AntennaFcSpinner.Value*1e6;
            app.part_reset_req = 1;
        end

        % Value changed function: DacSignalDropDown
        function DacSignalDropDownValueChanged(app, event)
            switch app.DacSignalDropDown.Value
                case 'OFDM'
                    app.dacSignalType = 4;
                case 'Custom'
                    app.dacSignalType = 0;
                case 'CW'
                    app.dacSignalType = 1;
                case 'SAW'
                    app.dacSignalType = 2;
                case 'Chirp'
                    app.dacSignalType = 3;
            end
            queueSource(app);
            app.part_reset_req = 1;
        end

        % Value changed function: FcEditField
        function FcEditFieldValueChanged(app, event)
            app.dacFc = app.FcEditField.Value;
            queueSource(app);
            app.part_reset_req = 1;
        end

        % Value changed function: FeEditField
        function FeEditFieldValueChanged(app, event)
            app.dacFe = app.FeEditField.Value;
            queueSource(app);
            app.part_reset_req = 1;
        end
        % Changes arrangement of the app based on UIFigure width
        function updateAppLayout(app, event)
            currentFigureWidth = app.RFSoCBeamformerUIFigure.Position(3);
            if(currentFigureWidth <= app.onePanelWidth)
                % Change to a 2x1 grid
                app.GridLayout.RowHeight = {949, 949};
                app.GridLayout.ColumnWidth = {'1x'};
                app.RightPanel.Layout.Row = 2;
                app.RightPanel.Layout.Column = 1;
            else
                % Change to a 1x2 grid
                app.GridLayout.RowHeight = {'1x'};
                app.GridLayout.ColumnWidth = {234, '1x'};
                app.RightPanel.Layout.Row = 1;
                app.RightPanel.Layout.Column = 2;
            end
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create RFSoCBeamformerUIFigure and hide until all components are created
            app.RFSoCBeamformerUIFigure = uifigure('Visible', 'off');
            app.RFSoCBeamformerUIFigure.AutoResizeChildren = 'off';
            app.RFSoCBeamformerUIFigure.Position = [100 100 835 949];
            app.RFSoCBeamformerUIFigure.Name = 'RFSoC Beamformer';
            app.RFSoCBeamformerUIFigure.SizeChangedFcn = createCallbackFcn(app, @updateAppLayout, true);
            app.RFSoCBeamformerUIFigure.Scrollable = 'on';

            % Create GridLayout
            app.GridLayout = uigridlayout(app.RFSoCBeamformerUIFigure);
            app.GridLayout.ColumnWidth = {234, '1x'};
            app.GridLayout.RowHeight = {'1x'};
            app.GridLayout.ColumnSpacing = 0;
            app.GridLayout.RowSpacing = 0;
            app.GridLayout.Padding = [0 0 0 0];
            app.GridLayout.Scrollable = 'on';

            % Create LeftPanel
            app.LeftPanel = uipanel(app.GridLayout);
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;

            % Create IQtoolsButton
            app.IQtoolsButton = uibutton(app.LeftPanel, 'push');
            app.IQtoolsButton.ButtonPushedFcn = createCallbackFcn(app, @IQtoolsButtonPushed, true);
            app.IQtoolsButton.Position = [81 153 100 22];
            app.IQtoolsButton.Text = 'IQtools';

            % Create PlutoButton
            app.PlutoButton = uibutton(app.LeftPanel, 'push');
            app.PlutoButton.ButtonPushedFcn = createCallbackFcn(app, @PlutoButtonPushed, true);
            app.PlutoButton.Position = [81 126 100 22];
            app.PlutoButton.Text = 'Pluto';

            % Create ResetButton
            app.ResetButton = uibutton(app.LeftPanel, 'state');
            app.ResetButton.ValueChangedFcn = createCallbackFcn(app, @ResetButtonValueChanged, true);
            app.ResetButton.Text = 'Reset';
            app.ResetButton.Position = [83 4 100 22];

            % Create TabGroup
            app.TabGroup = uitabgroup(app.LeftPanel);
            app.TabGroup.Position = [9 224 219 705];

            % Create MainTab
            app.MainTab = uitab(app.TabGroup);
            app.MainTab.Title = 'Main';

            % Create SignalpriorityButtonGroup
            app.SignalpriorityButtonGroup = uibuttongroup(app.MainTab);
            app.SignalpriorityButtonGroup.AutoResizeChildren = 'off';
            app.SignalpriorityButtonGroup.SelectionChangedFcn = createCallbackFcn(app, @SignalpriorityButtonGroupSelectionChanged, true);
            app.SignalpriorityButtonGroup.Title = 'Signal priority';
            app.SignalpriorityButtonGroup.Position = [60 124 113 83];

            % Create MostPowerfullButton
            app.MostPowerfullButton = uiradiobutton(app.SignalpriorityButtonGroup);
            app.MostPowerfullButton.Text = 'Most Powerfull';
            app.MostPowerfullButton.Position = [11 37 101 22];
            app.MostPowerfullButton.Value = true;

            % Create LessPowerfullButton
            app.LessPowerfullButton = uiradiobutton(app.SignalpriorityButtonGroup);
            app.LessPowerfullButton.Text = 'Less Powerfull';
            app.LessPowerfullButton.Position = [11 15 100 22];

            % Create DOAresolutionEditField_3Label
            app.DOAresolutionEditField_3Label = uilabel(app.MainTab);
            app.DOAresolutionEditField_3Label.HorizontalAlignment = 'right';
            app.DOAresolutionEditField_3Label.Position = [23 642 58 28];
            app.DOAresolutionEditField_3Label.Text = {'DOA'; 'resolution'};

            % Create DOAresolutionEditField
            app.DOAresolutionEditField = uieditfield(app.MainTab, 'numeric');
            app.DOAresolutionEditField.Limits = [0.0001 Inf];
            app.DOAresolutionEditField.ValueChangedFcn = createCallbackFcn(app, @DOAresolutionEditFieldValueChanged, true);
            app.DOAresolutionEditField.Position = [96 648 77 22];
            app.DOAresolutionEditField.Value = 1;

            % Create DOAtypeListBoxLabel
            app.DOAtypeListBoxLabel = uilabel(app.MainTab);
            app.DOAtypeListBoxLabel.HorizontalAlignment = 'right';
            app.DOAtypeListBoxLabel.Position = [-8 592 79 43];
            app.DOAtypeListBoxLabel.Text = {'DOA'; 'type'};

            % Create DOAtypeListBox
            app.DOAtypeListBox = uilistbox(app.MainTab);
            app.DOAtypeListBox.Items = {'MVDR', 'MVDRman', 'MVDRman_corr', 'MUSIC', 'Beamscan', 'MUSICR', 'ESPRITE', 'ESPRITEBS', 'WSFR'};
            app.DOAtypeListBox.ValueChangedFcn = createCallbackFcn(app, @DOAtypeListBoxValueChanged, true);
            app.DOAtypeListBox.Position = [75 463 98 174];
            app.DOAtypeListBox.Value = 'MVDR';

            % Create BFtypeListBoxLabel
            app.BFtypeListBoxLabel = uilabel(app.MainTab);
            app.BFtypeListBoxLabel.HorizontalAlignment = 'right';
            app.BFtypeListBoxLabel.Position = [-8 416 79 43];
            app.BFtypeListBoxLabel.Text = {'BF'; 'type'};

            % Create BFtypeListBox
            app.BFtypeListBox = uilistbox(app.MainTab);
            app.BFtypeListBox.Items = {'Without', 'Steering', 'MVDR', 'DMR', 'PC', 'PC_corr', 'LCMV', 'RVL', 'RAB PC', 'DL MVDR', 'DL ITER MVDR', 'QCB'};
            app.BFtypeListBox.ValueChangedFcn = createCallbackFcn(app, @BFtypeListBoxValueChanged, true);
            app.BFtypeListBox.Position = [75 228 98 233];
            app.BFtypeListBox.Value = 'Steering';

            % Create ChannelselectListBoxLabel
            app.ChannelselectListBoxLabel = uilabel(app.MainTab);
            app.ChannelselectListBoxLabel.HorizontalAlignment = 'right';
            app.ChannelselectListBoxLabel.Position = [67 55 50 43];
            app.ChannelselectListBoxLabel.Text = {'Channel'; 'select'};

            % Create ChannelselectListBox
            app.ChannelselectListBox = uilistbox(app.MainTab);
            app.ChannelselectListBox.Items = {'Ch1', 'Ch2', 'Ch3', 'Ch4', 'All'};
            app.ChannelselectListBox.ItemsData = {'1', '2', '3', '4', '5', ''};
            app.ChannelselectListBox.ValueChangedFcn = createCallbackFcn(app, @ChannelselectListBoxValueChanged, true);
            app.ChannelselectListBox.Position = [121 21 52 98];
            app.ChannelselectListBox.Value = '5';

            % Create SystemTab
            app.SystemTab = uitab(app.TabGroup);
            app.SystemTab.Title = 'System';

            % Create RFSoCFcSpinnerLabel
            app.RFSoCFcSpinnerLabel = uilabel(app.SystemTab);
            app.RFSoCFcSpinnerLabel.HorizontalAlignment = 'right';
            app.RFSoCFcSpinnerLabel.Position = [17 590 44 27];
            app.RFSoCFcSpinnerLabel.Text = {'RFSoC'; 'Fc'};

            % Create RFSoCFcSpinner
            app.RFSoCFcSpinner = uispinner(app.SystemTab);
            app.RFSoCFcSpinner.Limits = [1 10000];
            app.RFSoCFcSpinner.ValueChangedFcn = createCallbackFcn(app, @RFSoCFcSpinnerValueChanged, true);
            app.RFSoCFcSpinner.Position = [76 595 77 22];
            app.RFSoCFcSpinner.Value = 1000;

            % Create RFSoCFsSpinnerLabel
            app.RFSoCFsSpinnerLabel = uilabel(app.SystemTab);
            app.RFSoCFsSpinnerLabel.HorizontalAlignment = 'right';
            app.RFSoCFsSpinnerLabel.Position = [17 557 44 27];
            app.RFSoCFsSpinnerLabel.Text = {'RFSoC'; 'Fs'};

            % Create RFSoCFsSpinner
            app.RFSoCFsSpinner = uispinner(app.SystemTab);
            app.RFSoCFsSpinner.Limits = [1 500];
            app.RFSoCFsSpinner.ValueDisplayFormat = '%.0f';
            app.RFSoCFsSpinner.ValueChangedFcn = createCallbackFcn(app, @RFSoCFsSpinnerValueChanged, true);
            app.RFSoCFsSpinner.Position = [76 562 77 22];
            app.RFSoCFsSpinner.Value = 250;

            % Create MaxSignalsSpinnerLabel
            app.MaxSignalsSpinnerLabel = uilabel(app.SystemTab);
            app.MaxSignalsSpinnerLabel.HorizontalAlignment = 'right';
            app.MaxSignalsSpinnerLabel.Position = [50 117 71 22];
            app.MaxSignalsSpinnerLabel.Text = 'Max Signals';

            % Create MaxSignalsSpinner
            app.MaxSignalsSpinner = uispinner(app.SystemTab);
            app.MaxSignalsSpinner.Limits = [1 5];
            app.MaxSignalsSpinner.ValueDisplayFormat = '%.0f';
            app.MaxSignalsSpinner.ValueChangedFcn = createCallbackFcn(app, @MaxSignalsSpinnerValueChanged, true);
            app.MaxSignalsSpinner.Position = [136 117 45 22];
            app.MaxSignalsSpinner.Value = 2;

            % Create SigBWSpinnerLabel
            app.SigBWSpinnerLabel = uilabel(app.SystemTab);
            app.SigBWSpinnerLabel.HorizontalAlignment = 'right';
            app.SigBWSpinnerLabel.Position = [36 524 25 28];
            app.SigBWSpinnerLabel.Text = {'Sig'; 'BW'};

            % Create SigBWSpinner
            app.SigBWSpinner = uispinner(app.SystemTab);
            app.SigBWSpinner.Limits = [1 500];
            app.SigBWSpinner.ValueDisplayFormat = '%.0f';
            app.SigBWSpinner.ValueChangedFcn = createCallbackFcn(app, @SigBWSpinnerValueChanged, true);
            app.SigBWSpinner.Position = [76 530 77 22];
            app.SigBWSpinner.Value = 249;

            % Create LoadVSAsetupButton
            app.LoadVSAsetupButton = uibutton(app.SystemTab, 'push');
            app.LoadVSAsetupButton.ButtonPushedFcn = createCallbackFcn(app, @LoadVSAsetupButtonPushed, true);
            app.LoadVSAsetupButton.Position = [114 1 102 22];
            app.LoadVSAsetupButton.Text = 'Load VSA setup';

            % Create ScanBWEditFieldLabel
            app.ScanBWEditFieldLabel = uilabel(app.SystemTab);
            app.ScanBWEditFieldLabel.HorizontalAlignment = 'right';
            app.ScanBWEditFieldLabel.Position = [11 1 33 28];
            app.ScanBWEditFieldLabel.Text = {'Scan'; 'BW'};

            % Create ScanBWEditField
            app.ScanBWEditField = uieditfield(app.SystemTab, 'numeric');
            app.ScanBWEditField.Limits = [2 360];
            app.ScanBWEditField.RoundFractionalValues = 'on';
            app.ScanBWEditField.ValueChangedFcn = createCallbackFcn(app, @ScanBWEditFieldValueChanged, true);
            app.ScanBWEditField.Position = [59 7 44 22];
            app.ScanBWEditField.Value = 180;

            % Create ModCheckBox
            app.ModCheckBox = uicheckbox(app.SystemTab);
            app.ModCheckBox.ValueChangedFcn = createCallbackFcn(app, @ModCheckBoxValueChanged, true);
            app.ModCheckBox.Text = 'Mod';
            app.ModCheckBox.Position = [131 30 45 22];

            % Create PowerCheckBox
            app.PowerCheckBox = uicheckbox(app.SystemTab);
            app.PowerCheckBox.ValueChangedFcn = createCallbackFcn(app, @PowerCheckBoxValueChanged, true);
            app.PowerCheckBox.Text = 'Power';
            app.PowerCheckBox.Position = [64 30 56 22];

            % Create gainGenSpinnerLabel
            app.gainGenSpinnerLabel = uilabel(app.SystemTab);
            app.gainGenSpinnerLabel.HorizontalAlignment = 'right';
            app.gainGenSpinnerLabel.Position = [57 59 51 22];
            app.gainGenSpinnerLabel.Text = 'gainGen';

            % Create gainGenSpinner
            app.gainGenSpinner = uispinner(app.SystemTab);
            app.gainGenSpinner.Limits = [-144 18];
            app.gainGenSpinner.ValueChangedFcn = createCallbackFcn(app, @gainGenSpinnerValueChanged, true);
            app.gainGenSpinner.Position = [123 59 64 22];

            % Create fcGenSpinnerLabel
            app.fcGenSpinnerLabel = uilabel(app.SystemTab);
            app.fcGenSpinnerLabel.HorizontalAlignment = 'right';
            app.fcGenSpinnerLabel.Position = [62 84 38 22];
            app.fcGenSpinnerLabel.Text = 'fcGen';

            % Create fcGenSpinner
            app.fcGenSpinner = uispinner(app.SystemTab);
            app.fcGenSpinner.Limits = [1 6000];
            app.fcGenSpinner.ValueChangedFcn = createCallbackFcn(app, @fcGenSpinnerValueChanged, true);
            app.fcGenSpinner.Position = [108 84 69 22];
            app.fcGenSpinner.Value = 5700;

            % Create RecalibrateADCsButton
            app.RecalibrateADCsButton = uibutton(app.SystemTab, 'push');
            app.RecalibrateADCsButton.ButtonPushedFcn = createCallbackFcn(app, @RecalibrateADCsButtonPushed, true);
            app.RecalibrateADCsButton.Position = [68 453 100 35];
            app.RecalibrateADCsButton.Text = {'Recalibrate'; 'ADCs'};

            % Create EvenNyquistZoneCheckBox
            app.EvenNyquistZoneCheckBox = uicheckbox(app.SystemTab);
            app.EvenNyquistZoneCheckBox.ValueChangedFcn = createCallbackFcn(app, @EvenNyquistZoneCheckBoxValueChanged, true);
            app.EvenNyquistZoneCheckBox.Text = 'Even Nyquist Zone';
            app.EvenNyquistZoneCheckBox.Position = [64 497 123 22];

            % Create ADCsLabel
            app.ADCsLabel = uilabel(app.SystemTab);
            app.ADCsLabel.FontWeight = 'bold';
            app.ADCsLabel.Position = [93 615 38 22];
            app.ADCsLabel.Text = 'ADCs';

            % Create DACsLabel
            app.DACsLabel = uilabel(app.SystemTab);
            app.DACsLabel.FontWeight = 'bold';
            app.DACsLabel.Position = [93 416 38 22];
            app.DACsLabel.Text = {'DACs'; ''};

            % Create RFSoCFcSpinner_2Label
            app.RFSoCFcSpinner_2Label = uilabel(app.SystemTab);
            app.RFSoCFcSpinner_2Label.HorizontalAlignment = 'right';
            app.RFSoCFcSpinner_2Label.Position = [42 388 44 27];
            app.RFSoCFcSpinner_2Label.Text = {'RFSoC'; 'Fc'};

            % Create RFSoCFcSpinner_2
            app.RFSoCFcSpinner_2 = uispinner(app.SystemTab);
            app.RFSoCFcSpinner_2.Limits = [-10000 10000];
            app.RFSoCFcSpinner_2.ValueChangedFcn = createCallbackFcn(app, @RFSoCFcSpinner_2ValueChanged, true);
            app.RFSoCFcSpinner_2.Position = [101 393 77 22];
            app.RFSoCFcSpinner_2.Value = 4500;

            % Create dataStreamCheckBox
            app.dataStreamCheckBox = uicheckbox(app.SystemTab);
            app.dataStreamCheckBox.ValueChangedFcn = createCallbackFcn(app, @dataStreamCheckBoxValueChanged, true);
            app.dataStreamCheckBox.Text = 'dataStream';
            app.dataStreamCheckBox.Position = [133 615 84 22];
            app.dataStreamCheckBox.Value = true;

            % Create AngleSpinnerLabel
            app.AngleSpinnerLabel = uilabel(app.SystemTab);
            app.AngleSpinnerLabel.HorizontalAlignment = 'right';
            app.AngleSpinnerLabel.Position = [50 367 36 22];
            app.AngleSpinnerLabel.Text = 'Angle';

            % Create AngleSpinner
            app.AngleSpinner = uispinner(app.SystemTab);
            app.AngleSpinner.Limits = [-179 179];
            app.AngleSpinner.ValueChangedFcn = createCallbackFcn(app, @AngleSpinnerValueChanged, true);
            app.AngleSpinner.Position = [101 367 77 22];

            % Create EvenNyquistZoneCheckBox_2
            app.EvenNyquistZoneCheckBox_2 = uicheckbox(app.SystemTab);
            app.EvenNyquistZoneCheckBox_2.ValueChangedFcn = createCallbackFcn(app, @EvenNyquistZoneCheckBox_2ValueChanged, true);
            app.EvenNyquistZoneCheckBox_2.Text = 'Even Nyquist Zone';
            app.EvenNyquistZoneCheckBox_2.Position = [57 346 123 22];
            app.EvenNyquistZoneCheckBox_2.Value = true;

            % Create SYNCDropDownLabel
            app.SYNCDropDownLabel = uilabel(app.SystemTab);
            app.SYNCDropDownLabel.HorizontalAlignment = 'right';
            app.SYNCDropDownLabel.Position = [43 643 39 22];
            app.SYNCDropDownLabel.Text = 'SYNC';

            % Create SYNCDropDown
            app.SYNCDropDown = uidropdown(app.SystemTab);
            app.SYNCDropDown.Items = {'all', 'dac', 'none'};
            app.SYNCDropDown.ItemsData = [2 1 0];
            app.SYNCDropDown.ValueChangedFcn = createCallbackFcn(app, @SYNCDropDownValueChanged, true);
            app.SYNCDropDown.Position = [97 643 100 22];
            app.SYNCDropDown.Value = 1;

            % Create PowerCheckBox_2
            app.PowerCheckBox_2 = uicheckbox(app.SystemTab);
            app.PowerCheckBox_2.ValueChangedFcn = createCallbackFcn(app, @PowerCheckBox_2ValueChanged, true);
            app.PowerCheckBox_2.Text = 'Power';
            app.PowerCheckBox_2.Position = [137 416 56 22];
            app.PowerCheckBox_2.Value = true;

            % Create ResampleCheckBox
            app.ResampleCheckBox = uicheckbox(app.SystemTab);
            app.ResampleCheckBox.ValueChangedFcn = createCallbackFcn(app, @ResampleCheckBoxValueChanged, true);
            app.ResampleCheckBox.Text = 'Resample';
            app.ResampleCheckBox.Position = [7 169 76 22];

            % Create OrigFSEditFieldLabel
            app.OrigFSEditFieldLabel = uilabel(app.SystemTab);
            app.OrigFSEditFieldLabel.HorizontalAlignment = 'right';
            app.OrigFSEditFieldLabel.Position = [90 169 47 22];
            app.OrigFSEditFieldLabel.Text = 'Orig FS';

            % Create OrigFSEditField
            app.OrigFSEditField = uieditfield(app.SystemTab, 'numeric');
            app.OrigFSEditField.ValueChangedFcn = createCallbackFcn(app, @OrigFSEditFieldValueChanged, true);
            app.OrigFSEditField.Position = [152 169 47 22];
            app.OrigFSEditField.Value = 60;

            % Create FilterCheckBox
            app.FilterCheckBox = uicheckbox(app.SystemTab);
            app.FilterCheckBox.ValueChangedFcn = createCallbackFcn(app, @FilterCheckBoxValueChanged, true);
            app.FilterCheckBox.Text = 'Filter';
            app.FilterCheckBox.Position = [7 144 48 22];

            % Create FiltBWEditFieldLabel
            app.FiltBWEditFieldLabel = uilabel(app.SystemTab);
            app.FiltBWEditFieldLabel.HorizontalAlignment = 'right';
            app.FiltBWEditFieldLabel.Position = [92 144 44 22];
            app.FiltBWEditFieldLabel.Text = 'Filt BW';

            % Create FiltBWEditField
            app.FiltBWEditField = uieditfield(app.SystemTab, 'numeric');
            app.FiltBWEditField.ValueChangedFcn = createCallbackFcn(app, @FiltBWEditFieldValueChanged, true);
            app.FiltBWEditField.Position = [151 144 47 22];
            app.FiltBWEditField.Value = 100;

            % Create MirrorCheckBox
            app.MirrorCheckBox = uicheckbox(app.SystemTab);
            app.MirrorCheckBox.ValueChangedFcn = createCallbackFcn(app, @MirrorCheckBoxValueChanged, true);
            app.MirrorCheckBox.Text = 'Mirror';
            app.MirrorCheckBox.Position = [160 594 54 22];

            % Create SyncButton
            app.SyncButton = uibutton(app.SystemTab, 'push');
            app.SyncButton.ButtonPushedFcn = createCallbackFcn(app, @SyncButtonPushed, true);
            app.SyncButton.Position = [63 205 100 22];
            app.SyncButton.Text = 'Sync';

            % Create AntennaLabel
            app.AntennaLabel = uilabel(app.SystemTab);
            app.AntennaLabel.FontWeight = 'bold';
            app.AntennaLabel.Position = [90 259 53 22];
            app.AntennaLabel.Text = 'Antenna';

            % Create AntennaFcSpinnerLabel
            app.AntennaFcSpinnerLabel = uilabel(app.SystemTab);
            app.AntennaFcSpinnerLabel.HorizontalAlignment = 'right';
            app.AntennaFcSpinnerLabel.Position = [33 231 50 27];
            app.AntennaFcSpinnerLabel.Text = {'Antenna'; 'Fc'};

            % Create AntennaFcSpinner
            app.AntennaFcSpinner = uispinner(app.SystemTab);
            app.AntennaFcSpinner.Limits = [1 33000];
            app.AntennaFcSpinner.ValueChangedFcn = createCallbackFcn(app, @AntennaFcSpinnerValueChanged, true);
            app.AntennaFcSpinner.Position = [98 236 77 22];
            app.AntennaFcSpinner.Value = 1000;

            % Create DacSignalDropDownLabel
            app.DacSignalDropDownLabel = uilabel(app.SystemTab);
            app.DacSignalDropDownLabel.HorizontalAlignment = 'right';
            app.DacSignalDropDownLabel.Position = [43 320 60 22];
            app.DacSignalDropDownLabel.Text = 'DacSignal';

            % Create DacSignalDropDown
            app.DacSignalDropDown = uidropdown(app.SystemTab);
            app.DacSignalDropDown.Items = {'OFDM', 'CW', 'SAW', 'Chirp', 'Custom'};
            app.DacSignalDropDown.ValueChangedFcn = createCallbackFcn(app, @DacSignalDropDownValueChanged, true);
            app.DacSignalDropDown.Position = [118 320 68 22];
            app.DacSignalDropDown.Value = 'OFDM';

            % Create FcEditFieldLabel
            app.FcEditFieldLabel = uilabel(app.SystemTab);
            app.FcEditFieldLabel.HorizontalAlignment = 'right';
            app.FcEditFieldLabel.Position = [4 286 25 22];
            app.FcEditFieldLabel.Text = 'Fc';

            % Create FcEditField
            app.FcEditField = uieditfield(app.SystemTab, 'numeric');
            app.FcEditField.ValueChangedFcn = createCallbackFcn(app, @FcEditFieldValueChanged, true);
            app.FcEditField.Position = [44 286 25 22];

            % Create FeEditFieldLabel
            app.FeEditFieldLabel = uilabel(app.SystemTab);
            app.FeEditFieldLabel.HorizontalAlignment = 'right';
            app.FeEditFieldLabel.Position = [80 286 25 22];
            app.FeEditFieldLabel.Text = 'Fe';

            % Create FeEditField
            app.FeEditField = uieditfield(app.SystemTab, 'numeric');
            app.FeEditField.ValueChangedFcn = createCallbackFcn(app, @FeEditFieldValueChanged, true);
            app.FeEditField.Position = [113 286 32 22];
            app.FeEditField.Value = 50;

            % Create SREditFieldLabel
            app.SREditFieldLabel = uilabel(app.SystemTab);
            app.SREditFieldLabel.HorizontalAlignment = 'right';
            app.SREditFieldLabel.Position = [151 286 25 22];
            app.SREditFieldLabel.Text = 'SR';

            % Create SREditField
            app.SREditField = uieditfield(app.SystemTab, 'numeric');
            app.SREditField.Position = [181 286 26 22];
            app.SREditField.Value = 1;

            % Create DownconverterTab
            app.DownconverterTab = uitab(app.TabGroup);
            app.DownconverterTab.Title = 'Downconverter';

            % Create Gauge
            app.Gauge = uigauge(app.DownconverterTab, 'semicircular');
            app.Gauge.Limits = [-90 90];
            app.Gauge.Position = [14 368 189 102];

            % Create StartphasecalibrationsButton
            app.StartphasecalibrationsButton = uibutton(app.DownconverterTab, 'push');
            app.StartphasecalibrationsButton.ButtonPushedFcn = createCallbackFcn(app, @StartphasecalibrationsButtonPushed, true);
            app.StartphasecalibrationsButton.Position = [41 277 140 58];
            app.StartphasecalibrationsButton.Text = 'Start phase calibrations';

            % Create ArduinoprogramButton
            app.ArduinoprogramButton = uibutton(app.DownconverterTab, 'push');
            app.ArduinoprogramButton.ButtonPushedFcn = createCallbackFcn(app, @ArduinoprogramButtonPushed, true);
            app.ArduinoprogramButton.Position = [57 612 104 23];
            app.ArduinoprogramButton.Text = 'Arduino program';

            % Create StarrangEditFieldLabel
            app.StarrangEditFieldLabel = uilabel(app.DownconverterTab);
            app.StarrangEditFieldLabel.HorizontalAlignment = 'right';
            app.StarrangEditFieldLabel.Position = [17 341 54 22];
            app.StarrangEditFieldLabel.Text = 'Starr ang';

            % Create StarrangEditField
            app.StarrangEditField = uieditfield(app.DownconverterTab, 'numeric');
            app.StarrangEditField.Limits = [-90 90];
            app.StarrangEditField.RoundFractionalValues = 'on';
            app.StarrangEditField.ValueChangedFcn = createCallbackFcn(app, @StarrangEditFieldValueChanged, true);
            app.StarrangEditField.Position = [79 341 29 22];
            app.StarrangEditField.Value = -60;

            % Create StepangEditFieldLabel
            app.StepangEditFieldLabel = uilabel(app.DownconverterTab);
            app.StepangEditFieldLabel.HorizontalAlignment = 'right';
            app.StepangEditFieldLabel.Position = [114 341 53 22];
            app.StepangEditFieldLabel.Text = 'Step ang';

            % Create StepangEditField
            app.StepangEditField = uieditfield(app.DownconverterTab, 'numeric');
            app.StepangEditField.Limits = [0.01 50];
            app.StepangEditField.ValueChangedFcn = createCallbackFcn(app, @StepangEditFieldValueChanged, true);
            app.StepangEditField.Position = [175 341 24 22];
            app.StepangEditField.Value = 10;

            % Create DebugTab
            app.DebugTab = uitab(app.TabGroup);
            app.DebugTab.Title = 'Debug';

            % Create GetPatternButton
            app.GetPatternButton = uibutton(app.DebugTab, 'state');
            app.GetPatternButton.ValueChangedFcn = createCallbackFcn(app, @GetPatternButtonValueChanged, true);
            app.GetPatternButton.Text = 'GetPattern';
            app.GetPatternButton.Position = [69 415 100 22];

            % Create CutoffsetEditFieldLabel
            app.CutoffsetEditFieldLabel = uilabel(app.DebugTab);
            app.CutoffsetEditFieldLabel.HorizontalAlignment = 'right';
            app.CutoffsetEditFieldLabel.Position = [31 253 57 22];
            app.CutoffsetEditFieldLabel.Text = 'Cut offset';

            % Create CutoffsetEditField
            app.CutoffsetEditField = uieditfield(app.DebugTab, 'numeric');
            app.CutoffsetEditField.ValueChangedFcn = createCallbackFcn(app, @CutoffsetEditFieldValueChanged, true);
            app.CutoffsetEditField.Position = [131 253 38 22];
            app.CutoffsetEditField.Value = 500;

            % Create dataChanEditFieldLabel
            app.dataChanEditFieldLabel = uilabel(app.DebugTab);
            app.dataChanEditFieldLabel.HorizontalAlignment = 'right';
            app.dataChanEditFieldLabel.Position = [23 280 58 22];
            app.dataChanEditFieldLabel.Text = 'dataChan';

            % Create dataChanEditField
            app.dataChanEditField = uieditfield(app.DebugTab, 'numeric');
            app.dataChanEditField.Limits = [1024 131072];
            app.dataChanEditField.ValueChangedFcn = createCallbackFcn(app, @dataChanEditFieldValueChanged, true);
            app.dataChanEditField.Position = [95 280 74 22];
            app.dataChanEditField.Value = 16384;

            % Create c1CheckBox
            app.c1CheckBox = uicheckbox(app.DebugTab);
            app.c1CheckBox.ValueChangedFcn = createCallbackFcn(app, @c1CheckBoxValueChanged, true);
            app.c1CheckBox.Text = 'c1';
            app.c1CheckBox.Position = [134 334 35 22];

            % Create c2CheckBox
            app.c2CheckBox = uicheckbox(app.DebugTab);
            app.c2CheckBox.ValueChangedFcn = createCallbackFcn(app, @c2CheckBoxValueChanged, true);
            app.c2CheckBox.Text = 'c2';
            app.c2CheckBox.Position = [134 307 35 22];

            % Create MatlabPatternCheckBox
            app.MatlabPatternCheckBox = uicheckbox(app.DebugTab);
            app.MatlabPatternCheckBox.ValueChangedFcn = createCallbackFcn(app, @MatlabPatternCheckBoxValueChanged, true);
            app.MatlabPatternCheckBox.Text = 'MatlabPattern';
            app.MatlabPatternCheckBox.Position = [87 360 97 22];

            % Create UpdRateEditFieldLabel
            app.UpdRateEditFieldLabel = uilabel(app.DebugTab);
            app.UpdRateEditFieldLabel.HorizontalAlignment = 'right';
            app.UpdRateEditFieldLabel.Position = [22 388 55 22];
            app.UpdRateEditFieldLabel.Text = 'UpdRate';

            % Create UpdRateEditField
            app.UpdRateEditField = uieditfield(app.DebugTab, 'numeric');
            app.UpdRateEditField.Limits = [1 Inf];
            app.UpdRateEditField.ValueChangedFcn = createCallbackFcn(app, @UpdRateEditFieldValueChanged, true);
            app.UpdRateEditField.Position = [92 388 77 22];
            app.UpdRateEditField.Value = 10;

            % Create DLFEditFieldLabel
            app.DLFEditFieldLabel = uilabel(app.DebugTab);
            app.DLFEditFieldLabel.HorizontalAlignment = 'right';
            app.DLFEditFieldLabel.Position = [56 502 55 28];
            app.DLFEditFieldLabel.Text = 'DLF';

            % Create DLFEditField
            app.DLFEditField = uieditfield(app.DebugTab, 'numeric');
            app.DLFEditField.ValueChangedFcn = createCallbackFcn(app, @DLFEditFieldValueChanged2, true);
            app.DLFEditField.Position = [126 508 43 22];
            app.DLFEditField.Value = 1;

            % Create GetSpectrumButton
            app.GetSpectrumButton = uibutton(app.DebugTab, 'state');
            app.GetSpectrumButton.ValueChangedFcn = createCallbackFcn(app, @GetSpectrumButtonValueChanged, true);
            app.GetSpectrumButton.Text = 'GetSpectrum';
            app.GetSpectrumButton.Position = [69 442 100 22];

            % Create BWEditFieldLabel
            app.BWEditFieldLabel = uilabel(app.DebugTab);
            app.BWEditFieldLabel.HorizontalAlignment = 'right';
            app.BWEditFieldLabel.Position = [56 469 55 28];
            app.BWEditFieldLabel.Text = 'BW';

            % Create BWEditField
            app.BWEditField = uieditfield(app.DebugTab, 'numeric');
            app.BWEditField.Limits = [0 45];
            app.BWEditField.ValueChangedFcn = createCallbackFcn(app, @BWEditFieldValueChanged, true);
            app.BWEditField.Position = [126 475 43 22];
            app.BWEditField.Value = 0.1;

            % Create patternCorrCheckBox
            app.patternCorrCheckBox = uicheckbox(app.DebugTab);
            app.patternCorrCheckBox.ValueChangedFcn = createCallbackFcn(app, @patternCorrCheckBoxValueChanged, true);
            app.patternCorrCheckBox.Text = 'patternCorr';
            app.patternCorrCheckBox.Position = [86 226 83 22];

            % Create mis_angEditFieldLabel
            app.mis_angEditFieldLabel = uilabel(app.DebugTab);
            app.mis_angEditFieldLabel.HorizontalAlignment = 'right';
            app.mis_angEditFieldLabel.Position = [60 643 51 22];
            app.mis_angEditFieldLabel.Text = 'mis_ang';

            % Create mis_angEditField
            app.mis_angEditField = uieditfield(app.DebugTab, 'numeric');
            app.mis_angEditField.Limits = [0.1 20];
            app.mis_angEditField.ValueChangedFcn = createCallbackFcn(app, @mis_angEditFieldValueChanged, true);
            app.mis_angEditField.Position = [126 643 43 22];
            app.mis_angEditField.Value = 15;

            % Create alg_scan_resEditFieldLabel
            app.alg_scan_resEditFieldLabel = uilabel(app.DebugTab);
            app.alg_scan_resEditFieldLabel.HorizontalAlignment = 'right';
            app.alg_scan_resEditFieldLabel.Position = [34 616 77 22];
            app.alg_scan_resEditFieldLabel.Text = 'alg_scan_res';

            % Create alg_scan_resEditField
            app.alg_scan_resEditField = uieditfield(app.DebugTab, 'numeric');
            app.alg_scan_resEditField.Limits = [0.001 10];
            app.alg_scan_resEditField.ValueChangedFcn = createCallbackFcn(app, @alg_scan_resEditFieldValueChanged, true);
            app.alg_scan_resEditField.Position = [126 616 43 22];
            app.alg_scan_resEditField.Value = 1;

            % Create gammaEditFieldLabel
            app.gammaEditFieldLabel = uilabel(app.DebugTab);
            app.gammaEditFieldLabel.HorizontalAlignment = 'right';
            app.gammaEditFieldLabel.Position = [65 589 46 22];
            app.gammaEditFieldLabel.Text = 'gamma';

            % Create gammaEditField
            app.gammaEditField = uieditfield(app.DebugTab, 'numeric');
            app.gammaEditField.Limits = [0 Inf];
            app.gammaEditField.ValueChangedFcn = createCallbackFcn(app, @gammaEditFieldValueChanged, true);
            app.gammaEditField.Position = [126 589 43 22];
            app.gammaEditField.Value = 1;

            % Create alphaEditFieldLabel
            app.alphaEditFieldLabel = uilabel(app.DebugTab);
            app.alphaEditFieldLabel.HorizontalAlignment = 'right';
            app.alphaEditFieldLabel.Position = [76 562 35 22];
            app.alphaEditFieldLabel.Text = 'alpha';

            % Create alphaEditField
            app.alphaEditField = uieditfield(app.DebugTab, 'numeric');
            app.alphaEditField.Limits = [0 Inf];
            app.alphaEditField.ValueChangedFcn = createCallbackFcn(app, @alphaEditFieldValueChanged, true);
            app.alphaEditField.Position = [126 562 43 22];
            app.alphaEditField.Value = 1.1;

            % Create iterEditFieldLabel
            app.iterEditFieldLabel = uilabel(app.DebugTab);
            app.iterEditFieldLabel.HorizontalAlignment = 'right';
            app.iterEditFieldLabel.Position = [86 535 25 22];
            app.iterEditFieldLabel.Text = 'iter';

            % Create iterEditField
            app.iterEditField = uieditfield(app.DebugTab, 'numeric');
            app.iterEditField.Limits = [1 Inf];
            app.iterEditField.ValueChangedFcn = createCallbackFcn(app, @iterEditFieldValueChanged, true);
            app.iterEditField.Position = [126 535 43 22];
            app.iterEditField.Value = 1;

            % Create CutterCheckBox
            app.CutterCheckBox = uicheckbox(app.DebugTab);
            app.CutterCheckBox.ValueChangedFcn = createCallbackFcn(app, @CutterCheckBoxValueChanged, true);
            app.CutterCheckBox.Text = 'Cutter';
            app.CutterCheckBox.Position = [89 205 55 22];

            % Create DebugCheckBox_2
            app.DebugCheckBox_2 = uicheckbox(app.DebugTab);
            app.DebugCheckBox_2.ValueChangedFcn = createCallbackFcn(app, @DebugCheckBox_2ValueChanged, true);
            app.DebugCheckBox_2.Text = 'Debug';
            app.DebugCheckBox_2.Position = [91 180 57 22];

            % Create NumberofsavedfilesLabel
            app.NumberofsavedfilesLabel = uilabel(app.DebugTab);
            app.NumberofsavedfilesLabel.HorizontalAlignment = 'right';
            app.NumberofsavedfilesLabel.Position = [18 142 62 27];
            app.NumberofsavedfilesLabel.Text = {'Number of'; 'saved files'};

            % Create NumberofsavedfilesEditField
            app.NumberofsavedfilesEditField = uieditfield(app.DebugTab, 'numeric');
            app.NumberofsavedfilesEditField.Limits = [0 10000];
            app.NumberofsavedfilesEditField.ValueChangedFcn = createCallbackFcn(app, @NumberofsavedfilesEditFieldValueChanged, true);
            app.NumberofsavedfilesEditField.Position = [95 147 100 22];

            % Create SaveButton
            app.SaveButton = uibutton(app.DebugTab, 'push');
            app.SaveButton.ButtonPushedFcn = createCallbackFcn(app, @SaveButtonPushed, true);
            app.SaveButton.Position = [82 117 100 22];
            app.SaveButton.Text = 'Save';

            % Create AvgSpinnerLabel
            app.AvgSpinnerLabel = uilabel(app.LeftPanel);
            app.AvgSpinnerLabel.HorizontalAlignment = 'right';
            app.AvgSpinnerLabel.Position = [58 180 26 22];
            app.AvgSpinnerLabel.Text = 'Avg';

            % Create AvgSpinner
            app.AvgSpinner = uispinner(app.LeftPanel);
            app.AvgSpinner.Limits = [1 Inf];
            app.AvgSpinner.ValueChangedFcn = createCallbackFcn(app, @AvgSpinnerValueChanged, true);
            app.AvgSpinner.Position = [98 180 56 22];
            app.AvgSpinner.Value = 10;

            % Create VSACheckBox
            app.VSACheckBox = uicheckbox(app.LeftPanel);
            app.VSACheckBox.ValueChangedFcn = createCallbackFcn(app, @VSACheckBoxValueChanged, true);
            app.VSACheckBox.Text = 'VSA';
            app.VSACheckBox.Position = [184 180 46 22];
            app.VSACheckBox.Value = true;

            % Create CustomCommandTextAreaLabel
            app.CustomCommandTextAreaLabel = uilabel(app.LeftPanel);
            app.CustomCommandTextAreaLabel.HorizontalAlignment = 'right';
            app.CustomCommandTextAreaLabel.Position = [6 38 60 27];
            app.CustomCommandTextAreaLabel.Text = {'Custom'; 'Command'};

            % Create CustomCommandTextArea
            app.CustomCommandTextArea = uitextarea(app.LeftPanel);
            app.CustomCommandTextArea.ValueChangedFcn = createCallbackFcn(app, @CustomCommandTextAreaValueChanged, true);
            app.CustomCommandTextArea.Position = [81 43 146 24];

            % Create PlotCheckBox
            app.PlotCheckBox = uicheckbox(app.LeftPanel);
            app.PlotCheckBox.ValueChangedFcn = createCallbackFcn(app, @PlotCheckBoxValueChanged, true);
            app.PlotCheckBox.Text = 'Plot';
            app.PlotCheckBox.Position = [187 147 43 22];
            app.PlotCheckBox.Value = true;

            % Create RightPanel
            app.RightPanel = uipanel(app.GridLayout);
            app.RightPanel.Layout.Row = 1;
            app.RightPanel.Layout.Column = 2;

            % Create GridLayout2
            app.GridLayout2 = uigridlayout(app.RightPanel);
            app.GridLayout2.ColumnWidth = {'100x'};
            app.GridLayout2.RowHeight = {'100x', '100x'};
            app.GridLayout2.RowSpacing = 1.33333333333333;
            app.GridLayout2.Padding = [2.5 1.33333333333333 2.5 1.33333333333333];

            % Create UIAxes
            app.UIAxes = uiaxes(app.GridLayout2);
            title(app.UIAxes, 'Title')
            xlabel(app.UIAxes, 'X')
            ylabel(app.UIAxes, 'Y')
            zlabel(app.UIAxes, 'Z')
            app.UIAxes.FontWeight = 'bold';
            app.UIAxes.LineWidth = 1;
            app.UIAxes.XGrid = 'on';
            app.UIAxes.XMinorGrid = 'on';
            app.UIAxes.YGrid = 'on';
            app.UIAxes.SubtitleFontWeight = 'bold';
            app.UIAxes.Layout.Row = 1;
            app.UIAxes.Layout.Column = 1;

            % Create UIAxes2
            app.UIAxes2 = uiaxes(app.GridLayout2);
            title(app.UIAxes2, 'Beam Pattern')
            xlabel(app.UIAxes2, 'X')
            ylabel(app.UIAxes2, 'Y')
            zlabel(app.UIAxes2, 'Z')
            app.UIAxes2.FontWeight = 'bold';
            app.UIAxes2.XGrid = 'on';
            app.UIAxes2.XMinorGrid = 'on';
            app.UIAxes2.YGrid = 'on';
            app.UIAxes2.Layout.Row = 2;
            app.UIAxes2.Layout.Column = 1;

            % Show the figure after all components are created
            app.RFSoCBeamformerUIFigure.Visible = 'off'; % refactor: startupFcn applies cfg.visible
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = VSA_rfsoc_refactor_exported(varargin)

            % No singleton focus: several hidden instances may exist in tests.
            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.RFSoCBeamformerUIFigure)

            % Execute the startup function
            runStartupFcn(app, @(app)startupFcn(app, varargin{:}))

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)
            % Owned resources: timer, backend (via controller), external figures.
            if ~isempty(app.AcqTimer) && isvalid(app.AcqTimer)
                stop(app.AcqTimer);
                delete(app.AcqTimer);
            end
            if ~isempty(app.Controller) && isvalid(app.Controller)
                try
                    app.Controller.close();
                catch err
                    warning('origapp:Close', 'Backend close failed: %s', err.message);
                end
                delete(app.Controller);
            end
            for k = 1:numel(app.ExternalFigures)
                if isvalid(app.ExternalFigures(k)), delete(app.ExternalFigures(k)); end
            end
            % Delete UIFigure when app is deleted
            delete(app.RFSoCBeamformerUIFigure)
        end
    end
end
