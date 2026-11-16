classdef OfdmViewer < handle
    %OFDMVIEWER Owned window of the Integrated Custom OFDM analyzer.
    % One uifigure with persistent graphics (created once, updated in place):
    % constellation (payload, header, pilots), spectrum of the analysed buffer
    % with the occupied band, EVM per payload symbol and per subcarrier,
    % common phase and pilot timing per symbol, a status banner and a
    % parameter/metric panel. show(R) draws one valid result; clear(reason)
    % blanks every current value (NaN data, "UNAVAILABLE"), keeping only a
    % labelled history line. The app deletes it with its other owned windows.
    properties (SetAccess = private)
        Figure = []
        Grid = []
        SideGrid = []
        Ax = struct()
        H = struct()
        Banner = []
        Text = []
        Profile
        Source = ""
        Created = 0          % graphics objects created (persistent: only in build)
        ShownSequence = NaN
    end
    methods
        function obj = OfdmViewer(profile, source, visible)
            obj.Profile = profile; obj.Source = string(source);
            obj.build(visible);
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function setVisible(obj, on)
            if obj.isOpen(), obj.Figure.Visible = matlab.lang.OnOffSwitchState(on); end
        end

        function show(obj, R, history)
            if ~obj.isOpen(), return; end
            c = R.constellation;
            set(obj.H.pay, 'XData', real(c.payload), 'YData', imag(c.payload));
            set(obj.H.hdr, 'XData', real(c.header), 'YData', imag(c.header));
            set(obj.H.pil, 'XData', real(c.pilot), 'YData', imag(c.pilot));
            set(obj.H.spec, 'XData', R.spectrum.freqHz/1e6, 'YData', R.spectrum.psdDbfs);
            set(obj.H.evs, 'XData', R.evmSymbolIndex, 'YData', R.evmPerSymbolPercent);
            set(obj.H.evc, 'XData', R.evmSubcarrier, 'YData', R.evmPerSubcarrierPercent);
            ns = size(R.commonPhaseDeg, 1); s = R.evmSymbolIndex(:);
            set(obj.H.cpe, 'XData', repmat([s; NaN], size(R.commonPhaseDeg, 2), 1), ...
                'YData', reshape([R.commonPhaseDeg; nan(1, size(R.commonPhaseDeg, 2))], [], 1));
            set(obj.H.tim, 'XData', repmat([s; NaN], size(R.timingSlopeSamples, 2), 1), ...
                'YData', reshape([R.timingSlopeSamples - R.timingSlopeSamples(1,:); nan(1, size(R.timingSlopeSamples, 2))], [], 1));
            assert(ns == numel(s), 'origapp:Ofdm', 'symbol count mismatch');
            status = "LOCKED"; if R.degraded, status = "DEGRADED"; end
            obj.Banner.Text = sprintf(['%s  seq %g  |  all-complete payload EVM %.2f %% (%.1f dB)  |  ' ...
                '%d/%d complete bursts qualified  |  input: %s'], status, R.sequence, R.evmPercent, ...
                R.evmDb, R.qualifiedBursts, R.metricBursts, R.input);
            obj.Banner.BackgroundColor = [0.80 0.93 0.80];
            if R.degraded, obj.Banner.BackgroundColor = [1.0 0.90 0.65]; end
            obj.Text.Value = obj.panelText(R, history);
            obj.Figure.Name = sprintf('%s - %s - seq %g', origapp.OfdmAnalyzer.NAME, obj.Source, R.sequence);
            obj.ShownSequence = R.sequence;
            title(obj.Ax.const, sprintf('Constellation (equalized, seq %g)', R.sequence));
            drawnow limitrate nocallbacks
        end

        function clear(obj, reason, history, R)
            % Blank all current values. R (optional) is an invalid result whose
            % spectrum/sync peak may still be shown, labelled as not demodulated.
            if ~obj.isOpen(), return; end
            for n = ["pay","hdr","pil","evs","evc","cpe","tim","spec"]
                h = obj.H.(n); set(h, 'XData', NaN, 'YData', NaN);
            end
            if nargin >= 4 && ~isempty(R) && isfield(R, 'spectrum') && isfield(R.spectrum, 'freqHz')
                set(obj.H.spec, 'XData', R.spectrum.freqHz/1e6, 'YData', R.spectrum.psdDbfs);
            end
            obj.Banner.Text = "UNAVAILABLE  |  " + string(reason);
            obj.Banner.BackgroundColor = [0.97 0.85 0.80];
            lines = "CURRENT: none (" + string(reason) + ")";
            if nargin >= 4 && ~isempty(R) && isfield(R, 'syncPeak')
                lines(end+1) = sprintf('this frame: state %s, sync peak %.3f, RX level %.1f dBFS (spectrum shown, not demodulated)', ...
                    R.state, R.syncPeak, R.rxLevelDbfs);
            end
            lines = [lines(:); obj.historyLine(history); ""; obj.profileLines()];
            obj.Text.Value = cellstr(lines(:));
            obj.Figure.Name = sprintf('%s - %s - UNAVAILABLE', origapp.OfdmAnalyzer.NAME, obj.Source);
            title(obj.Ax.const, 'Constellation: unavailable');
            obj.ShownSequence = NaN;
            drawnow limitrate nocallbacks
        end

        function delete(obj)
            if obj.isOpen(), delete(obj.Figure); end
        end
    end
    methods (Access = private)
        function reflow(obj)
            if ~obj.isOpen() || isempty(obj.Grid) || isempty(obj.SideGrid), return; end
            g=obj.Grid; side=obj.SideGrid; width=obj.Figure.Position(3);
            if width < 900
                g.ColumnWidth={'1x','1x'}; g.RowHeight={54,260,220,400};
                g.Scrollable='on'; obj.Banner.Layout.Column=[1 2];
                side.Layout.Row=4; side.Layout.Column=[1 2];
            else
                g.ColumnWidth={'1x','1x',min(380,max(260,round(width*.30)))};
                side.Layout.Row=[2 3]; side.Layout.Column=3;
                g.RowHeight={34,'1x','1x'}; g.Scrollable='off';
                obj.Banner.Layout.Column=[1 3];
            end
        end

        function build(obj, visible)
            P = obj.Profile;
            f = uifigure('Name', origapp.OfdmAnalyzer.NAME + " - " + obj.Source, 'Visible', 'off', ...
                'Position', [80 60 1250 780], 'Tag', 'IntegratedCustomOfdm', 'AutoResizeChildren', 'off');
            obj.Figure = f;
            mp=get(groot,'MonitorPositions'); m=mp(1,:);
            w=min(1250,max(400,m(3)-40)); h=min(780,max(300,m(4)-110));
            f.Position=[m(1)+round((m(3)-w)/2),m(2)+max(50,round((m(4)-h)/2)),w,h];
            g = uigridlayout(f, [3 3], 'RowHeight', {34, '1x', '1x'}, 'ColumnWidth', {'1x', '1x', 380});
            obj.Grid=g;
            obj.Banner = uilabel(g, 'Text', 'waiting for first frame', 'FontWeight', 'bold', 'FontSize', 14, ...
                'FontColor', [0 0 0], 'BackgroundColor', [0.9 0.9 0.9]);
            obj.Banner.Layout.Row = 1; obj.Banner.Layout.Column = [1 3]; obj.Banner.WordWrap='on';
            a = uiaxes(g); a.Layout.Row = 2; a.Layout.Column = 1; obj.Ax.const = a;
            hold(a, 'on'); grid(a, 'on'); axis(a, 'equal'); a.XLim = [-1.6 1.6]; a.YLim = [-1.6 1.6];
            lev = (-3:2:3)/sqrt(10); [gi, gq] = meshgrid(lev, lev);
            plot(a, gi(:), gq(:), '+', 'Color', [0.5 0.5 0.5], 'MarkerSize', 10);
            obj.H.pay = plot(a, NaN, NaN, '.', 'MarkerSize', 4, 'Color', [0 0.35 0.75]);
            obj.H.hdr = plot(a, NaN, NaN, '.', 'MarkerSize', 6, 'Color', [0.85 0.4 0]);
            obj.H.pil = plot(a, NaN, NaN, '.', 'MarkerSize', 6, 'Color', [0.1 0.6 0.1]);
            legend(a, {'ideal 16QAM', 'payload (16QAM)', 'header (BPSK)', 'pilots / value'}, 'Location', 'southoutside', 'NumColumns', 2);
            title(a, 'Constellation'); xlabel(a, 'I'); ylabel(a, 'Q');
            a = uiaxes(g); a.Layout.Row = 2; a.Layout.Column = 2; obj.Ax.spec = a;
            hold(a, 'on'); grid(a, 'on');
            obj.H.spec = plot(a, NaN, NaN, 'Color', [0 0.35 0.75]);
            bw = [min(P.bins)-0.5, max(P.bins)+0.5]*P.subcarrierSpacing/1e6;
            xline(a, bw(1), '--', 'Color', [0.4 0.4 0.4], 'Label', 'occupied band');
            xline(a, bw(2), '--', 'Color', [0.4 0.4 0.4]);
            title(a, 'Spectrum of the analysed buffer'); xlabel(a, 'MHz (baseband)'); ylabel(a, 'dBFS/bin');
            a.XLim = [-P.fsRx/2 P.fsRx/2]/1e6;
            a = uiaxes(g); a.Layout.Row = 3; a.Layout.Column = 1; obj.Ax.evs = a;
            hold(a, 'on'); grid(a, 'on');
            obj.H.evs = plot(a, NaN, NaN, 'o-', 'Color', [0 0.35 0.75], 'MarkerSize', 4);
            title(a, 'EVM per symbol (all complete bursts)'); xlabel(a, 'symbol in burst'); ylabel(a, 'EVM %');
            a = uiaxes(g); a.Layout.Row = 3; a.Layout.Column = 2; obj.Ax.evc = a;
            hold(a, 'on'); grid(a, 'on');
            obj.H.evc = stem(a, NaN, NaN, 'filled', 'MarkerSize', 3, 'Color', [0 0.35 0.75]);
            title(a, 'Payload EVM per subcarrier'); xlabel(a, 'subcarrier'); ylabel(a, 'EVM %');
            a.XLim = [min(P.bins)-1 max(P.bins)+1];
            g2 = uigridlayout(g, [2 1], 'RowHeight', {'1x', '1.2x'}, 'Padding', [0 0 0 0]);
            g2.Layout.Row = [2 3]; g2.Layout.Column = 3; obj.SideGrid=g2;
            a = uiaxes(g2); obj.Ax.trk = a; hold(a, 'on'); grid(a, 'on');
            yyaxis(a, 'left'); obj.H.cpe = plot(a, NaN, NaN, '.-'); ylabel(a, 'common phase (deg)');
            yyaxis(a, 'right'); obj.H.tim = plot(a, NaN, NaN, '.-'); ylabel(a, 'pilot timing drift (samples)');
            title(a, 'Pilot tracking per symbol'); xlabel(a, 'symbol in burst');
            obj.Text = uitextarea(g2, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
            obj.Text.Value = cellstr(obj.profileLines());
            obj.Created = 12;
            f.SizeChangedFcn=@(~,~)obj.reflow(); obj.reflow();
            if visible, f.Visible = 'on'; end
        end

        function L = panelText(obj, R, history)
            L = [ ...
                sprintf("CURRENT seq %g  (input: %s)", R.sequence, R.input)
                sprintf("payload EVM %.2f %% / %.1f dB  (max burst %.2f %%)", R.evmPercent, R.evmDb, R.evmPercentMax)
                sprintf("header  EVM %.2f %% / %.1f dB (BPSK)", R.headerEvmPercent, R.headerEvmDb)
                sprintf("pilot error %.2f %% rms", R.pilotEvmPercent)
                sprintf("SETX ResLen-interval EVM %.2f %% (1st burst; interpretation)", R.setxIntervalEvmPercent)
                sprintf("bursts: %d qualified / %d complete / %d detected", R.qualifiedBursts, R.metricBursts, numel(R.candidates))
                sprintf("primary includes rejected complete bursts (%d); no quality exclusion", R.refusedCompleteBursts)
                sprintf("qualified-only EVM %.2f %% (secondary diagnostic)", R.qualifiedPayloadEvmPercent)
                sprintf("sync peak %.3f (own threshold %.2f)  ref lock %.3f", R.syncPeak, R.syncThreshold, R.referenceLock)
                sprintf("RX level %.1f dBFS rms, peak %.1f dBFS", R.rxLevelDbfs, R.peakDbfs)
                sprintf("CFO per burst (kHz): %s", mat2str(round(R.cfoHz/1e3, 2)))
                sprintf("training SNR (dB): %s", mat2str(round(R.trainingSnrDb, 1)))
                sprintf("timing offset (samples): %s", mat2str(round(R.timingOffsetSamples, 2)))
                sprintf("sampling error est. %.1f ppm (pilot drift, median)", R.samplingErrorPpm)
                sprintf("common phase rms %.2f deg", sqrt(mean(R.commonPhaseDeg(:).^2)))
                sprintf("analysis %.0f ms, age at analysis %.2f s", 1e3*R.elapsedS, R.ageAtAnalysis)];
            refused = R.candidates(~[R.candidates.accepted]);
            for k = 1:numel(refused)
                L(end+1) = sprintf("refused burst @%d: %s", refused(k).start, refused(k).reason); %#ok<AGROW>
            end
            L = cellstr([L; obj.historyLine(history); ""; obj.profileLines()]);
        end

        function s = historyLine(~, h)
            s = "HISTORY (not current): none";
            if isstruct(h) && isfinite(h.sequence)
                s = sprintf("HISTORY (not current): last valid seq %g, EVM %.2f %%, %d burst(s), %s UTC", h.sequence, ...
                    h.evmPercent, h.bursts, string(datetime(h.timestamp, 'ConvertFrom', 'posixtime', 'Format', 'HH:mm:ss.SS')));
            end
        end

        function L = profileLines(obj)
            S = obj.Profile.summary;
            L = [ ...
                "PROFILE (from SETX " + extractBefore(obj.Profile.setxSha256, 13) + "...)"
                sprintf("FFT %d, CP %d (GI %.3g) at %.4g MS/s system rate", S.fftLength, S.cpSamples, S.guardInterval, S.systemRateHz/1e6)
                sprintf("receive %.4g MS/s: %d-pt FFT, CP %d (no resampling)", S.receiveRateHz/1e6, S.rxFftLength, S.rxCpSamples)
                sprintf("subcarrier spacing %.4g kHz, guard %d/%d, %d active", S.subcarrierSpacingHz/1e3, S.guardSubcarriers, S.activeSubcarriers)
                sprintf("payload %s, %d data + pilots %s", S.payloadModulation, S.dataSubcarriers, mat2str(S.pilotSubcarriers))
                sprintf("header %s; preamble rows %s; repeat row %d", S.headerModulation, mat2str(S.preambleRows), S.repeatRow0)
                sprintf("burst %d symbols (%s)", S.burstSymbols, S.burstSymbolsSource)
                sprintf("symbol %.3g us; SymTimeAdj %.4g %%; SETX ResLen %d", S.symbolSeconds*1e6, S.symTimeAdjPercent, S.resultLength)
                "pilots: " + S.pilotSource
                "EQ: training (preamble) rows only + pilot phase/timing/amplitude"
                "NOT implemented: data-aided EQ/tracking (vendor SETX has EqUseData/TrkData on), BER (no payload bits)"];
        end
    end
end
