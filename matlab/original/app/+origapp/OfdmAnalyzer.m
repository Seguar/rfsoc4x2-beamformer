classdef OfdmAnalyzer < handle
    %OFDMANALYZER Integrated Custom OFDM analyzer session for the original app.
    % Owns the profile (read from the matched SETX, SHA pinned), the buffer
    % orientation, the guards and the per-frame JSON log. It analyses the
    % SAME buffer the app hands to native VSA (combined/weighted output or a
    % raw measured column) with origapp.ofdmAnalyze. No vendor software.
    %
    % Guards (a result is "valid" only if all hold):
    %  * own preamble sync metric >= cfg.syncThreshold (explicit; NOT the
    %    vendor 0.9 sync correlation, which is a different quantity)
    %  * independent wanted-reference lock of the analysed buffer (8192-row
    %    blocks, median of max normalised circular correlation with the
    %    transmitted loop) >= cfg.lockThreshold (0.3, as the native path)
    %  * >= 1 complete burst qualifies; primary EVM includes ALL complete bursts
    %    including timing/training failures (qualified-only EVM is secondary)
    %  * acquisition age <= staleSeconds when the analysis finishes
    % Invalid frames clear Current (numbers and constellation); History keeps
    % the last valid summary, always labelled with its sequence and time.
    properties (SetAccess = private)
        Profile
        Config
        Current = []        % result of the frame on screen ([] = nothing current)
        History = struct('sequence', NaN, 'timestamp', NaN, 'evmPercent', NaN, 'evmDb', NaN, 'bursts', 0)
        LastReason = "no frame yet"
        Frames = 0
        ValidFrames = 0
        RefFftConj = []
        Ref = []
        SelfTest = struct()
    end
    properties (Constant)
        NAME = "Integrated Custom OFDM"
    end
    methods
        function obj = OfdmAnalyzer(cfg, setxPath, fsRx)
            d = struct('setupSha256', "", 'referenceMat', "", 'orientation', "", 'syncThreshold', 0.8, ...
                'lockThreshold', 0.3, 'staleSeconds', 2, 'logFile', "", 'maxBursts', Inf);
            f = fieldnames(d);
            for k = 1:numel(f), if ~isfield(cfg, f{k}) || isempty(cfg.(f{k})), cfg.(f{k}) = d.(f{k}); end, end
            cfg.orientation = string(cfg.orientation);
            assert(any(cfg.orientation == ["IplusjQ","IminusjQ"]), 'origapp:Ofdm', ...
                'cfg.ofdm.orientation must be "IplusjQ" or "IminusjQ" (same as the native VSA feed).');
            assert(strlength(string(cfg.setupSha256)) == 64, 'origapp:Ofdm', 'cfg.ofdm.setupSha256 (pinned SETX) is required.');
            assert(isfile(cfg.referenceMat), 'origapp:Ofdm', 'cfg.ofdm.referenceMat (transmitted loop) not found.');
            assert(cfg.syncThreshold >= 0.5 && cfg.syncThreshold < 1, 'origapp:Ofdm', 'syncThreshold must be in [0.5, 1).');
            assert(cfg.lockThreshold >= 0.3 && cfg.lockThreshold < 1, 'origapp:Ofdm', 'lockThreshold must be in [0.3, 1).');
            r = load(cfg.referenceMat);
            assert(isfield(r, 'ref125') && isfield(r, 'profile') && ...
                strtrim(string(r.profile)) == "legacy-ofdm64-truncated-v1", 'origapp:Ofdm', 'Wrong reference profile.');
            obj.Profile = origapp.ofdmProfile(setxPath, fsRx, 'sha256', cfg.setupSha256, 'reference', r.ref125(:));
            obj.Ref = r.ref125(:); obj.RefFftConj = conj(fft(obj.Ref));
            obj.Config = cfg;
            % Start-up self-test (also warms the code path before the first
            % live frame): the transmitted loop itself must demodulate cleanly.
            n = min(numel(obj.Ref), 32768);
            st = origapp.ofdmAnalyze(obj.Ref(1:n), obj.Profile, struct('syncThreshold', cfg.syncThreshold));
            assert(st.valid && st.evmPercent < 0.5, 'origapp:Ofdm', ...
                'Start-up self-test on the transmitted reference failed (%s, EVM %.3f %%).', st.state, st.evmPercent);
            obj.SelfTest = struct('evmPercent', st.evmPercent, 'bursts', st.bursts, 'elapsedS', st.elapsedS);
            obj.referenceLock(obj.Ref(1:n));
        end

        function R = analyze(obj, buffer, meta)
            % meta: sequence, timestamp (acquisition, host clock), kind (combined / weighted-channel / raw)
            t0 = origapp.Controller.nowSeconds();
            x = buffer(:);
            if obj.Config.orientation == "IplusjQ", x = conj(x); end
            assert(all(isfinite(x)) && any(x ~= 0), 'origapp:Ofdm', 'Analyzer input must be finite and nonzero.');
            lock = obj.referenceLock(x);
            if lock < obj.Config.lockThreshold
                % sync is still measured and logged; nothing is demodulated
                R = origapp.ofdmAnalyze(x, obj.Profile, struct('syncThreshold', obj.Config.syncThreshold, 'maxBursts', 0));
                R.state = "NO LOCK";
                R.reason = sprintf('no wanted-reference lock (%.3f < %.2f)', lock, obj.Config.lockThreshold);
                R.valid = false;
            else
                R = origapp.ofdmAnalyze(x, obj.Profile, struct('syncThreshold', obj.Config.syncThreshold, ...
                    'maxBursts', obj.Config.maxBursts));
            end
            R.referenceLock = lock;
            R.sequence = meta.sequence; R.timestamp = meta.timestamp; R.input = string(meta.kind);
            R.source = obj.NAME;
            done = origapp.Controller.nowSeconds();
            R.ageAtAnalysis = done - meta.timestamp;
            if R.valid && R.ageAtAnalysis > obj.Config.staleSeconds
                R.valid = false; R.state = "EXPIRED";
                R.reason = sprintf('acquisition age %.2f s > %g s at analysis end', R.ageAtAnalysis, obj.Config.staleSeconds);
            end
            R.wallS = done - t0;
            obj.Frames = obj.Frames + 1;
            obj.LastReason = string(R.reason);
            if R.valid
                obj.Current = R; obj.ValidFrames = obj.ValidFrames + 1;
                obj.History = struct('sequence', R.sequence, 'timestamp', R.timestamp, 'evmPercent', R.evmPercent, ...
                    'evmDb', R.evmDb, 'bursts', R.bursts);
            else
                obj.Current = [];
            end
            obj.log(R);
        end

        function invalidate(obj, reason)
            obj.Current = []; obj.LastReason = string(reason);
        end

        function lock = referenceLock(obj, x)
            % Same quantity as LegacyVsaBackend.analyzeBlocks medianLock.
            N = numel(obj.RefFftConj); L = 8192; nb = floor(numel(x)/L);
            if nb < 1, lock = 0; return, end
            ref = obj.Ref;
            v = zeros(1, nb);
            for j = 1:nb
                xb = zeros(N, 1); r = (j-1)*L + (1:L); xb(r) = x(r);
                c = ifft(fft(xb).*obj.RefFftConj);
                [pk, kk] = max(abs(c)); kk = kk - 1;
                idx = mod((r-1) - kk, N) + 1;
                v(j) = pk/sqrt(sum(abs(xb).^2)*sum(abs(ref(idx)).^2) + realmin);
            end
            lock = median(v);
        end

        function log(obj, R)
            if strlength(string(obj.Config.logFile)) == 0, return; end
            e = rmfield(R, {'constellation', 'spectrum'});
            e.profileSetxSha256 = obj.Profile.setxSha256;
            fid = fopen(obj.Config.logFile, 'a');
            if fid < 0, return; end
            fprintf(fid, '%s\n', jsonencode(e));
            fclose(fid);
        end
    end
end
