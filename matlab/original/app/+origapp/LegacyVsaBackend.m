classdef LegacyVsaBackend < handle
    %LEGACYVSABACKEND Board + native VSA backend for VSA_rfsoc_refactor_exported
    % (BACKEND_CONTRACT.md, demo 0d628ae). native VSA profile, v2.
    %
    % Transport (helper legacy_capture.py v2): magic R4X2IQ2 + JSON metadata,
    % frames IQL2, end END2. One request byte per wanted frame; the board
    % captures only after the request. The wire carries ONE measured stream
    % (stream0 = ADC_D) of a full-RAM contiguous capture: 131072 complex,
    % int16 lanes I,Q (524288 bytes). Metadata must state exactly that
    % (wire_channels [0], available_channels [1 0 0 0], frame_bytes 4*N);
    % anything else is rejected. next() returns N-by-4 for the UI contract:
    % column 1 = measured ADC_D (I - 1j*Q), columns 2..4 = zero PLACEHOLDERS
    % (not measured data), flagged by frame.availableChannels = [1 0 0 0].
    %
    % timestamp (conservative acquisition time on the host clock):
    %   ts = capture board-monotonic time + thetaLB, where thetaLB is a LOWER
    %   bound of the host-minus-board clock offset. Every host->board message
    %   gives one: host time just before sending minus board-monotonic time at
    %   which the board read it (the board cannot read it earlier). Sources:
    %   the connect (host time before connect vs header stamp) and every frame
    %   request. The tightest bound is kept and aged by a 100 ppm drift
    %   allowance, so ts is never later than the true acquisition time (it
    %   reads older by the shortest one-way latency seen plus the allowance).
    %   A request read late by the board (e.g. after a pause) cannot make a
    %   frame look older than the best bound. Never receive time.
    %
    % Native VSA: one new owned 89600 instance via rfsoc.VsaSession (SETX sha
    % pinned, allowSetxStatus32). The session reads vendor EVM/sync with a
    % near-zero threshold so the RAW vendor values are always recorded; the
    % backend then applies the profile guard: a metric is valid ONLY if the
    % independent wanted-reference block lock >= lockThreshold (0.3) AND the
    % vendor sync correlation >= syncCorrThreshold (0.9, profile default).
    % Rejected frames (blanks, noise, false vendor locks) are NOT errors: they
    % are logged, vsaStatus() reports valid=false with the reason, and the
    % owned VSA window title says UNAVAILABLE. No padding, tiling, joining,
    % payload fit or sample modification (except the configured orientation
    % conjugate). The window fed to VSA is one contiguous boundary-free run.
    properties (SetAccess = private)
        Config
        Metadata = struct()
        Log = struct([])
        Ended = false
        LastFrameMeta = struct()
        Delivered = {}
        Session = []
        VsaState = struct('valid',false,'state',"idle",'reason',"no frame yet",'evmPercent',NaN, ...
            'evmDb',NaN,'syncCorrelation',NaN,'lock',NaN,'sequence',NaN,'timestamp',NaN, ...
            'vendorEvmPercent',NaN,'vendorSync',NaN,'vendorStatus',"",'updatedPosix',NaN,'shortReason',"no frame yet",'source',"SOURCE NOT YET KNOWN")
        DisplaySupported = false
        SourceTag = "SOURCE NOT YET KNOWN"   % LIVE HW only for helper source rfsoc4x2-hardware
        DisplayLog = strings(0,1)
        PrefetchHold = false
        WarmupSeconds = zeros(1,0)
    end
    properties (Access = private)
        Client = []
        Stream = []
        Anchor = struct('hostPosix',NaN,'boardMonoNs',NaN,'headerReceivedPosix',NaN)
        Pending = false
        RequestPosix = NaN
        ThetaLB = -Inf          % host posix - board monotonic s, lower bound
        ThetaLBHost = NaN       % host time the bound was established
        Hdr = []
        Body = []
        HdrBytes = []
        Got = 0
        InBody = false
        ExpectedSeq = 0
        BodyNeed = 0
        LastReceiptPosix = NaN
        LastMeasured = []
        Ref = []
        RefFftConj = []
        Burst = NaN
        Closed = false
    end
    properties (Constant)
        N = 131072
        HEADER_BYTES = 52
        FRAME_BYTES = 4*131072
        AVAILABLE = logical([1 0 0 0])
        FORMAT = "int16le-IQ-1ch-fullram-v2"
        DRIFT = 100e-6          % allowance for board/host clock rate difference
        CODEC = "byteplane-shuffle+deflate-raw-lossless"
    end
    methods
        function obj = LegacyVsaBackend(cfg)
            req = {'host','port','referenceMat','orientation','dllPath','setupPath', ...
                'setupSha256','vsaPort','visible'};
            for k = 1:numel(req)
                assert(isfield(cfg,req{k}), 'a2live:Config', 'Missing %s', req{k});
            end
            assert(any(cfg.orientation == ["IminusjQ","IplusjQ"]), 'a2live:Config', ...
                'orientation must be IminusjQ (as delivered) or IplusjQ (conjugated)');
            d = struct('connectTimeoutSeconds',30,'lockThreshold',0.3,'minWindow',32768, ...
                'logFile',"",'syncCorrThreshold',0.9,'vendorReadThreshold',1e-6, ...
                'staleSeconds',2,'allowContinuous',false,'rawDir',"",'maxTimestampDelaySeconds',2, ...
                'expectSource',"rfsoc4x2-hardware",'prefetch',true,'warmup',true);
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(cfg,f{k}), cfg.(f{k}) = d.(f{k}); end
            end
            % Profile guard: 0.9 is the frozen legacy-profile default (0.5 admitted
            % a live noise frame at sync 0.542). It never weakens below 0.9 here.
            assert(cfg.syncCorrThreshold >= 0.9 && cfg.syncCorrThreshold <= 1, 'a2live:Config', ...
                'legacy profile needs syncCorrThreshold in [0.9, 1]');
            assert(cfg.lockThreshold >= 0.3 && cfg.lockThreshold < 1, 'a2live:Config', ...
                'legacy profile needs lockThreshold in [0.3, 1)');
            obj.Config = cfg;
            r = load(cfg.referenceMat);
            assert(numel(r.ref125) == obj.N && strtrim(string(r.profile)) == "legacy-ofdm64-truncated-v1", ...
                'a2live:Reference', 'Wrong legacy reference');
            obj.Ref = r.ref125(:); obj.Burst = double(r.burst125);
            obj.RefFftConj = conj(fft(obj.Ref));
        end

        function m = availableChannels(obj) %#ok<MANU>
            m = origapp.LegacyVsaBackend.AVAILABLE;
        end

        function open(obj)
            assert(~obj.Closed, 'a2live:Closed', 'Backend closed');
            if ~isempty(obj.Client), return; end
            preConnect = origapp.LegacyVsaBackend.now();
            c = System.Net.Sockets.TcpClient();
            c.ReceiveBufferSize = int32(4*1048576);
            c.NoDelay = true;
            task = c.ConnectAsync(char(obj.Config.host), int32(obj.Config.port));
            if ~task.Wait(int32(obj.Config.connectTimeoutSeconds*1000))
                c.Close(); error('a2live:Timeout','Board connect timeout');
            end
            obj.Client = c; obj.Stream = c.GetStream();
            obj.Hdr = NET.createArray('System.Byte', obj.HEADER_BYTES);
            obj.Body = NET.createArray('System.Byte', obj.FRAME_BYTES + 36 + 8192);
            obj.Stream.ReadTimeout = int32(10000);
            magic = obj.readBlocking(8);
            assert(isequal(magic(:).', uint8(['R4X2IQ2' newline])), 'a2live:Protocol', 'Wrong magic (need helper v2)');
            n = double(typecast(obj.readBlocking(4),'uint32'));
            assert(n < 65536, 'a2live:Protocol', 'Oversized header');
            md = jsondecode(native2unicode(obj.readBlocking(n).','UTF-8'));
            obj.validateMetadata(md);
            obj.SourceTag = origapp.LegacyVsaBackend.sourceTag(string(md.source));
            obj.Metadata = md;
            obj.Anchor.boardMonoNs = double(md.board_monotonic_ns);
            obj.Anchor.hostPosix = preConnect;
            obj.Anchor.headerReceivedPosix = origapp.LegacyVsaBackend.now();
            obj.Metadata.anchor = obj.Anchor;
            obj.updateTheta(preConnect - obj.Anchor.boardMonoNs/1e9, preConnect);
        end

        function frame = next(obj, timeoutSeconds)
            % Bounded: the deadline is checked on EVERY loop pass (also while
            % bytes keep arriving). Returns [] if the requested frame is not
            % complete in time; partial bytes are kept, so framing is never lost.
            frame = [];
            obj.updateStale();
            if obj.Ended || obj.Closed, return; end
            if isempty(obj.Client), obj.open(); end
            t = tic;
            if ~obj.Pending, obj.sendRequest(); end
            while true
                obj.updateStale();
                if ~obj.InBody, target = obj.Hdr; need = obj.HEADER_BYTES;
                else, target = obj.Body; need = obj.BodyNeed; end
                if obj.Got == need
                    if ~obj.InBody
                        if obj.headerComplete(), return; end   % END2
                        continue
                    end
                    break
                end
                left = timeoutSeconds - toc(t);
                if left <= 0
                    obj.updateStale(); return
                end
                avail = double(obj.Client.Available);
                if avail == 0
                    % Wait inside .NET (Poll), not pause() (pause yields to the UI
                    % and delayed frames by ~3 s). Poll is also true on EOF.
                    if obj.Client.Client.Poll(int32(min(left, 0.05)*1e6), System.Net.Sockets.SelectMode.SelectRead) ...
                            && double(obj.Client.Available) == 0
                        error('a2live:Disconnected','Board stream disconnected');
                    end
                    continue
                end
                got = obj.Stream.Read(target, int32(obj.Got), int32(min([avail, need - obj.Got, 262144])));
                obj.Got = obj.Got + double(got);
            end
            frame = obj.finishFrame();
        end

        function vsaReset(obj, request)
            assert(request.fs == 125e6, 'a2live:Vsa', 'Legacy profile needs fs 125 MHz');
            assert(request.dataChan == obj.N, 'a2live:Vsa', 'dataChan must be %d (full-RAM contiguous capture)', obj.N);
            setx = string(request.setupFile);
            if strlength(setx) == 0, setx = string(obj.Config.setupPath); end
            assert(isfile(setx) && origapp.LegacyVsaBackend.sha256(setx) == string(obj.Config.setupSha256), ...
                'a2live:Vsa', 'SETX is not the matched FFT64 setup');
            if ~isempty(obj.Session) && isvalid(obj.Session), return; end   % owned session kept
            vc = struct('dllPath', obj.Config.dllPath, 'fsHz', 125e6, 'fcHz', 0, ...
                'bandwidthHz', 125e6, 'captureSamples', 16384, 'visible', logical(obj.Config.visible), ...
                'setupPath', char(setx), 'startupPort', obj.Config.vsaPort, ...
                'maxInputSamples', obj.N, 'allowSetxStatus32', true, ...
                'syncCorrThreshold', obj.Config.vendorReadThreshold);   % raw read; guard below
            obj.Session = rfsoc.VsaSession(vc);
            obj.DisplaySupported = ismethod(obj.Session, 'setDisplayStatus');
            obj.showStatus("RFSoC native VSA [" + obj.SourceTag + "] | waiting for first frame (legacy FFT64, guard lock>=" + ...
                obj.Config.lockThreshold + " sync>=" + obj.Config.syncCorrThreshold + ")");
            obj.warmLink();
        end

        function warmLink(obj)
            % One PAD2 link warm-up filler (zeros, NOT ADC data, never delivered)
            % right before the first frame request: the first transfer after the
            % ~40 s VSA start-up idle was ~3 s slower than the rest.
            if ~obj.Config.warmup || isempty(obj.Client) || obj.Pending || obj.ExpectedSeq > 0, return; end
            t = tic;
            obj.Stream.Write(uint8('W'), 0, 1);
            h = obj.readBlocking(obj.HEADER_BYTES);
            assert(isequal(char(h(1:4).'), 'PAD2'), 'a2live:Protocol', 'Expected PAD2 warm-up');
            n = double(typecast(h(49:52),'uint32'));
            assert(n == double(obj.Metadata.pad_bytes), 'a2live:Protocol', 'PAD2 size differs');
            obj.readBlocking(n);
            obj.WarmupSeconds(end+1) = toc(t);
        end

        function vsaSend(obj, buffer)
            x = buffer(:);
            % Only the measured stream may be analysed: a placeholder column (or
            % any other buffer) is refused, never sent to VSA as data.
            assert(~isempty(obj.LastMeasured) && isequal(x, obj.LastMeasured), 'a2live:Channel', ...
                'vsaSend input is not the measured ADC_D stream (available channels [1 0 0 0])');
            if isempty(obj.Session) || ~isvalid(obj.Session)
                error('a2live:Vsa','vsaSend before vsaReset (no owned VSA session)');
            end
            assert(numel(x) == obj.N && all(isfinite(x)), 'a2live:Vsa', 'Need one full contiguous capture');
            if obj.Config.orientation == "IplusjQ", x = conj(x); end
            A = obj.analyzeBlocks(x);
            Aother = obj.analyzeBlocks(conj(x));
            lock = A.medianLock; lockOther = Aother.medianLock;
            m = obj.LastFrameMeta;
            winErr = "";
            try
                [win, note] = obj.chooseWindow(A);
            catch er
                win = []; note = er.message; winErr = string(er.message);
            end
            r = struct('evmPercent',NaN,'evmDb',NaN,'fresh',false,'status','not sent: no boundary-free window', ...
                'elapsedSeconds',0,'sentFloats',0,'quality',struct());
            if ~isempty(win)
                pending=obj.VsaState; pending.valid=false; pending.state="acquiring";
                pending.evmPercent=NaN; pending.evmDb=NaN;
                pending.reason="VSA measurement in progress; previous display is history";
                pending.shortReason="VSA acquiring"; pending.sequence=m.sequence;
                pending.timestamp=m.timestamp; obj.VsaState=pending;
                obj.showStatus("RFSoC native VSA ["+obj.SourceTag+"] | ACQUIRING seq "+ ...
                    m.sequence+" | previous display is history");
                r = obj.Session.sendFrame(x(win));   % blanks too: real IQ as negative control
            end
            sync = obj.field(r.quality,'syncCorrelation');
            % ---- guard (independent of vendor EVM magnitude) ----
            short = "";
            captureAge=origapp.LegacyVsaBackend.now()-m.timestamp;
            if captureAge>obj.Config.staleSeconds || captureAge< -0.5
                short="stale acquisition";
                reason=sprintf('acquisition age %.2f s exceeds freshness bound',captureAge);
            elseif lock < obj.Config.lockThreshold
                short = "no wanted-signal lock";
                reason = sprintf('no wanted-reference lock (block lock %.3f < %.2f)', lock, obj.Config.lockThreshold);
            elseif strlength(winErr) > 0
                short = "no boundary-free window";
                reason = "no boundary-free contiguous window: " + winErr;
            elseif ~r.fresh
                short = "VSA not fresh";
                reason = "VSA measurement not fresh: " + string(r.status);
            elseif ~isfinite(r.evmPercent)
                short = "VSA rejected frame";
                reason = "VSA rejected frame: " + string(r.status);
            elseif ~(isfinite(sync) && sync >= obj.Config.syncCorrThreshold && sync <= 1)
                short = sprintf('VSA sync %.2f < %.2f', sync, obj.Config.syncCorrThreshold);
                reason = sprintf('insufficient VSA sync correlation %.3f < %.2f', sync, obj.Config.syncCorrThreshold);
            else
                reason = "";
            end
            valid = strlength(string(reason)) == 0;
            nowS = origapp.LegacyVsaBackend.now();
            s = obj.VsaState;
            s.valid = valid; s.state = string(ifelse(valid, "valid", "unavailable")); s.source = obj.SourceTag;
            s.reason = string(ifelse(valid, "ok", reason)); s.shortReason = string(ifelse(valid, "ok", short));
            s.evmPercent = ifelse(valid, r.evmPercent, NaN); s.evmDb = ifelse(valid, r.evmDb, NaN);
            s.syncCorrelation = sync; s.lock = lock; s.sequence = m.sequence; s.timestamp = m.timestamp;
            s.vendorEvmPercent = r.evmPercent; s.vendorSync = sync; s.vendorStatus = string(r.status);
            s.updatedPosix = nowS;
            obj.VsaState = s;
            if valid
                obj.showStatus(sprintf('RFSoC native VSA [%s] | VALID seq %d | guarded EVM %.2f %% | sync %.3f | lock %.2f', ...
                    obj.SourceTag, m.sequence, r.evmPercent, sync, lock));
            else
                obj.showStatus(sprintf('RFSoC native VSA [%s] | UNAVAILABLE seq %d: %s | vendor display is not a valid measurement', ...
                    obj.SourceTag, m.sequence, s.reason));
            end
            if isempty(win), w = [NaN NaN]; else, w = [win(1) win(end)]; end
            e = struct('sequence', m.sequence, 'timestamp', m.timestamp, 'phase', m.phase, ...
                'hostRequestSent', m.hostRequestSent, 'hostReceived', m.hostReceived, ...
                'ageAtReceipt', m.hostReceived - m.timestamp, 'ageAtVsaDone', nowS - m.timestamp, ...
                'boardDelayS', m.boardDelayS, 'anchorTimestamp', m.anchorTimestamp, ...
                'requestBoundTimestamp', m.requestBoundTimestamp, ...
                'lockI', lock, 'lockConj', lockOther, 'boundary', {A.boundaryBlocks}, 'window', w, ...
                'windowNote', note, 'guardValid', valid, 'guardReason', s.reason, ...
                'guardedEvmPercent', s.evmPercent, 'vendorEvmPercent', r.evmPercent, 'vendorEvmDb', r.evmDb, ...
                'vendorSync', sync, 'vendorFresh', r.fresh, 'vendorStatus', string(r.status), ...
                'sentFloats', r.sentFloats, 'elapsedSeconds', r.elapsedSeconds, ...
                'iqStatus', obj.field(r.quality,'iqStatus'), 'summaryStatus', obj.field(r.quality,'summaryStatus'), ...
                'lockThreshold', obj.Config.lockThreshold, 'syncCorrThreshold', obj.Config.syncCorrThreshold);
            if isempty(obj.Log), obj.Log = e; else, obj.Log(end+1) = e; end
            fprintf('A2VSA seq=%d phase=%s age=%.2fs lock=%.3f/%.3f win=%d..%d vendorEVM=%.4f%% sync=%.4f guard=%d %s :: %s\n', ...
                e.sequence, e.phase, e.ageAtReceipt, lock, lockOther, w(1), w(end), r.evmPercent, sync, valid, ...
                s.reason, r.status);
            if strlength(string(obj.Config.logFile)) > 0
                fid = fopen(obj.Config.logFile,'a'); fprintf(fid,'%s\n',jsonencode(e)); fclose(fid);
            end
        end

        function holdPrefetch(obj, tf)
            obj.PrefetchHold = logical(tf);
        end

        function tf = requestOutstanding(obj)
            tf = obj.Pending;
        end

        function s = vsaStatus(obj)
            % Latest guarded native-VSA result for the UI: valid, state
            % (idle/valid/unavailable/stale), source (LIVE HW / OFFLINE ...), reason, guarded evmPercent/evmDb,
            % raw vendor values kept separately (vendorEvmPercent, vendorSync).
            obj.updateStale();
            s = obj.VsaState;
        end

        function close(obj)
            if obj.Closed, return; end
            obj.Closed = true;
            try
                if ~isempty(obj.Client), obj.Client.Close(); end
            catch
            end
            obj.Client = []; obj.Stream = [];
            try
                if ~isempty(obj.Session) && isvalid(obj.Session), delete(obj.Session); end
            catch
            end
            obj.Session = [];
        end

        function delete(obj)
            obj.close();
        end

        function A = analyzeBlocks(obj, x)
            % Per-block (8192) circular correlation with the known transmitted loop.
            % The 4 bursts are ~80% alike, so the block loop index i is ambiguous
            % by whole bursts, but its burst phase (i mod B) is not. Inside one
            % contiguous pass psi = (n - i mod B) mod B is constant (+-1 per dropped
            % sample); at the truncation boundary it jumps by B - 21047 = 6459.25.
            N = obj.N; L = 8192; nb = N/L; B = obj.Burst;
            lock = zeros(1,nb); psi = zeros(1,nb); loopIdx = zeros(1,nb);
            for j = 1:nb
                xb = zeros(N,1); r = (j-1)*L + (1:L);
                xb(r) = x(r);
                c = ifft(fft(xb) .* obj.RefFftConj);
                [pk, kk] = max(abs(c)); kk = kk - 1;
                idx = mod((r-1) - kk, N) + 1;
                lock(j) = pk / sqrt(sum(abs(xb).^2) * sum(abs(obj.Ref(idx)).^2) + realmin);
                loopIdx(j) = mod((j-1)*L - kk, N);
                psi(j) = mod((j-1)*L - mod(loopIdx(j), B), B);
            end
            d = mod(diff(psi) + B/2, B) - B/2;
            jumps = find(abs(d) > 200);          % jump between block j and j+1
            % A wrap INSIDE a block is hidden from psi, so also flag blocks whose
            % matched loop range crosses the loop end; always drop the last block.
            wraps = find(loopIdx + L > N);
            excl = unique([jumps, jumps + 1, wraps, nb]);
            A = struct('medianLock', median(lock), 'lock', lock, 'loopIdx', loopIdx, ...
                'psi', psi, 'dpsi', d, 'jumps', jumps, 'wraps', wraps, 'boundaryBlocks', excl, ...
                'jumpSizes', d(jumps), 'blockLen', L);
        end

        function [win, note] = chooseWindow(obj, A)
            N = obj.N; L = A.blockLen; nb = N/L;
            if A.medianLock < obj.Config.lockThreshold
                win = (1:N).'; note = 'unlocked: whole capture from start (negative control), boundary unknown'; return
            end
            keep = true(1,nb); keep(A.boundaryBlocks) = false;
            best = [0 0]; s0 = 0;
            for j = 1:nb+1
                if j <= nb && keep(j)
                    if s0 == 0, s0 = j; end
                elseif s0 > 0
                    if j - s0 > best(2) - best(1), best = [s0 j]; end
                    s0 = 0;
                end
            end
            W = (best(2) - best(1)) * L;
            if W < obj.Config.minWindow
                error('a2live:Window','No boundary-free contiguous window >= %d (jumps %s)', ...
                    obj.Config.minWindow, mat2str(A.jumps));
            end
            win = ((best(1)-1)*L + 1 : (best(2)-1)*L).';
            unexpected = A.jumpSizes(abs(abs(A.jumpSizes) - (5*obj.Burst - N)) > 300);
            note = sprintf('blocks %d..%d, jumps %s (sizes %s), wraps %s, excluded %s%s', best(1), best(2)-1, ...
                mat2str(A.jumps), mat2str(round(A.jumpSizes)), mat2str(A.wraps), mat2str(A.boundaryBlocks), ...
                repmat(' UNEXPECTED-JUMP', 1, ~isempty(unexpected) || numel(A.jumps) > 1));
        end

        function frame = replayFrame(obj, x, sequence, phase)
            % Offline replay of a genuine stored capture (measured column only)
            % through the same guard; no board. x = ADC counts, I - 1j*Q.
            obj.SourceTag = "OFFLINE REPLAY - NOT LIVE";
            obj.LastMeasured = x(:)/2^16;
            t = origapp.LegacyVsaBackend.now();
            obj.LastFrameMeta = struct('timestamp', t, 'sequence', sequence, 'phase', phase, ...
                'hostRequestSent', t, 'hostReceived', t, 'boardDelayS', 0, 'anchorTimestamp', NaN, ...
                'requestBoundTimestamp', t);
            frame = obj.LastFrameMeta;
            obj.vsaSend(obj.LastMeasured);
        end
    end
    methods (Static)
        function h = sha256(path)
            md = System.Security.Cryptography.SHA256.Create();
            fs = System.IO.File.OpenRead(char(path));
            c = onCleanup(@() fs.Dispose());
            h = lower(string(reshape(dec2hex(uint8(md.ComputeHash(fs)))',1,[])));
        end
        function v = field(s, name)
            v = NaN; if isstruct(s) && isfield(s,name), v = s.(name); end
        end
        function tag = sourceTag(src)
            if src == "rfsoc4x2-hardware", tag = "LIVE HW";
            else, tag = "OFFLINE SYNTHETIC - NOT HARDWARE"; end
        end
        function body = decodeWire(payload, rawBytes)
            % IQZ2: <uint32 raw_len><32-byte sha256 of raw wire> + raw deflate of
            % [low-byte plane, high-byte plane]. Exact inverse; sha256 checked.
            payload = payload(:);
            validateattributes(rawBytes,{'numeric'},{'scalar','integer','positive','<=',4*131072});
            assert(numel(payload)>36,'a2live:Protocol','Truncated compressed frame');
            n = double(typecast(payload(1:4), 'uint32'));
            assert(n == rawBytes, 'a2live:Protocol', 'Decoded length %d differs from %d', n, rawBytes);
            ms = System.IO.MemoryStream(payload(37:end));
            ds = System.IO.Compression.DeflateStream(ms, System.IO.Compression.CompressionMode.Decompress);
            cleanup=onCleanup(@()ds.Dispose());
            % A declared frame is fixed-size. Refuse expansion before allocating
            % more than that size plus one detection byte.
            buffer=NET.createArray('System.Byte',n+1); got=0;
            while got<=n
                take=ds.Read(buffer,int32(got),int32(n+1-got));
                if take==0, break; end
                got=got+double(take);
            end
            assert(got==n,'a2live:Protocol','Inflated size differs from declared frame');
            planes=uint8(buffer); planes=planes(1:n); planes=planes(:);
            b = reshape(planes, n/2, 2).';
            body = b(:);
            md = System.Security.Cryptography.SHA256.Create();
            d = uint8(md.ComputeHash(body)); d = d(:);
            assert(isequal(d, payload(5:36)), 'a2live:Protocol', 'Decoded wire sha256 mismatch (not lossless)');
        end
        function t = now()
            t = posixtime(datetime('now','TimeZone','UTC'));
        end
    end
    methods (Access = private)
        function validateMetadata(obj, md)
            need = {'magic_version','source','format','adc_ram_words','capture','wire_channels','available_channels', ...
                'frame_bytes','frame_header','samples_per_channel','fs_hz','profile','frames_planned', ...
                'continuous','board_monotonic_ns'};
            for k = 1:numel(need)
                assert(isfield(md, need{k}), 'a2live:Metadata', 'Metadata lacks %s', need{k});
            end
            assert(any(string(md.source) == ["rfsoc4x2-hardware","offline-fake"]) && ...
                string(md.source) == string(obj.Config.expectSource), 'a2live:Metadata', ...
                'Stream source "%s" differs from expected "%s"', string(md.source), string(obj.Config.expectSource));
            assert(md.magic_version == 2 && string(md.format) == obj.FORMAT && ...
                string(md.capture) == "full-ram-contiguous" && md.adc_ram_words == 8*obj.N && ...
                md.samples_per_channel == obj.N && md.fs_hz == 125e6 && ...
                string(md.profile) == "legacy-ofdm64-truncated-v1" && string(md.frame_header) == "<4sQQQq8sII", ...
                'a2live:Metadata', 'Format/profile/capture metadata mismatch');
            wc = double(md.wire_channels(:).'); ac = double(md.available_channels(:).');
            assert(isequal(wc, 0), 'a2live:Metadata', 'Wire must carry exactly stream0 (ADC_D); got %s', mat2str(wc));
            assert(isequal(ac, double(obj.AVAILABLE)), 'a2live:Metadata', ...
                'availableChannels must be [1 0 0 0]; got %s', mat2str(ac));
            assert(isfield(md,'compression') && any(string(md.compression) == ["none", obj.CODEC]), ...
                'a2live:Metadata', 'Unknown wire compression');
            assert(md.frame_bytes == 4*obj.N*numel(wc), 'a2live:Metadata', ...
                'frame_bytes %d differs from 4*N*channels = %d', md.frame_bytes, 4*obj.N*numel(wc));
            fp = double(md.frames_planned);
            assert(isscalar(fp) && fp >= 1 && fp == fix(fp), 'a2live:Bound', 'frames_planned invalid');
            if md.continuous
                assert(logical(obj.Config.allowContinuous), 'a2live:Bound', ...
                    'continuous helper refused: cfg.allowContinuous=false (launcher-owned runs only)');
                assert(isfield(md,'max_seconds') && isnumeric(md.max_seconds) && isfinite(md.max_seconds) && ...
                    md.max_seconds > 0 && md.max_seconds <= 14400, 'a2live:Bound', 'continuous run needs max_seconds <= 14400');
            else
                assert(fp <= 30, 'a2live:Bound', 'bounded schedule claims %d > 30 frames', fp);
            end
        end

        function ended = headerComplete(obj)
            % Parse a complete 52-byte frame header. Returns true on END2.
            ended = false;
            h = uint8(obj.Hdr); h = h(:);
            kind = char(h(1:4).');
            seq = double(typecast(h(5:12),'uint64'));
            mask = double(typecast(h(45:48),'uint32'));
            nbytes = double(typecast(h(49:52),'uint32'));
            if kind == "END2"
                assert(seq == obj.ExpectedSeq, 'a2live:Sequence', 'END2 count %d differs from %d frames received', seq, obj.ExpectedSeq);
                obj.Ended = true; obj.Pending = false; ended = true;
                obj.updateStale(true);
                return
            end
            z = string(obj.Metadata.compression) ~= "none";
            assert(kind == string(ifelse(z, "IQZ2", "IQL2")), 'a2live:Protocol', 'Bad frame magic %s', kind);
            assert(seq == obj.ExpectedSeq, 'a2live:Sequence', 'Missing/out-of-order frame: got seq %d, expected %d', seq, obj.ExpectedSeq);
            assert(obj.Metadata.continuous || seq < obj.Metadata.frames_planned, 'a2live:Bound', ...
                'Frame %d exceeds the claimed bound of %d frames', seq, obj.Metadata.frames_planned);
            assert(mask == 1, 'a2live:Metadata', 'Frame channel mask %d differs from metadata (1 = ADC_D)', mask);
            if z
                assert(nbytes > 36 && nbytes <= obj.FRAME_BYTES + 36 + 8192, 'a2live:Protocol', ...
                    'Compressed frame length %d out of range', nbytes);
            else
                assert(nbytes == obj.FRAME_BYTES, 'a2live:Protocol', 'Frame wire length %d differs from %d', nbytes, obj.FRAME_BYTES);
            end
            obj.BodyNeed = nbytes;
            obj.HdrBytes = h; obj.InBody = true; obj.Got = 0;
        end

        function frame = finishFrame(obj)
            h = obj.HdrBytes; payload = uint8(obj.Body); payload = payload(1:obj.BodyNeed);
            if string(obj.Metadata.compression) ~= "none"
                body = origapp.LegacyVsaBackend.decodeWire(payload, obj.FRAME_BYTES);   % verified lossless
            else
                body = payload;
            end
            obj.Pending = false; obj.Got = 0; obj.InBody = false;
            received = origapp.LegacyVsaBackend.now();
            seq = double(typecast(h(5:12),'uint64'));
            capMono = double(typecast(h(13:20),'uint64'));
            reqMono = double(typecast(h(21:28),'uint64'));
            boardReal = double(typecast(h(29:36),'int64'))/1e9;
            delay = (capMono - reqMono)/1e9;
            assert(delay >= 0 && delay <= obj.Config.maxTimestampDelaySeconds, 'a2live:Timestamp', ...
                'Board request->capture delay %.3f s outside [0, %g]', delay, obj.Config.maxTimestampDelaySeconds);
            obj.updateTheta(obj.RequestPosix - reqMono/1e9, obj.RequestPosix);
            theta = obj.ThetaLB - obj.DRIFT*max(0, received - obj.ThetaLBHost);
            ts = max(capMono/1e9 + theta, obj.RequestPosix + delay);   % max of two lower bounds
            assert(ts <= received, 'a2live:Timestamp', 'Acquisition timestamp after host receipt');
            obj.ExpectedSeq = seq + 1;
            w = double(typecast(body(:),'int16'));
            w = reshape(w, 2, []).';
            samples = zeros(obj.N, 4);
            samples(:,1) = w(:,1) - 1j*w(:,2);      % measured ADC_D; columns 2..4 placeholders
            obj.LastMeasured = samples(:,1)/2^16;   % what the UI hands to vsaSend for ch 1
            obj.LastReceiptPosix = received;
            frame = struct('samples', samples, 'timestamp', ts, 'sequence', seq, ...
                'phase', strtrim(char(h(37:44).')), 'availableChannels', obj.AVAILABLE, ...
                'wireChannels', 0, 'wireFormat', obj.FORMAT, 'hostRequestSent', obj.RequestPosix, ...
                'hostReceived', received, 'boardDelayS', delay, 'requestBoundTimestamp', obj.RequestPosix + delay, ...
                'anchorTimestamp', obj.Anchor.hostPosix + (capMono - obj.Anchor.boardMonoNs)/1e9, ...
                'boardRealtime', boardReal);
            obj.LastFrameMeta = rmfield(frame,'samples');
            obj.Delivered{end+1} = obj.LastFrameMeta;
            % Prefetch: at most ONE outstanding request. The next capture starts
            % now, so its transfer overlaps this frame's VSA processing; the
            % board still acquires only on request and the timestamp is the
            % capture time (an unread prefetched frame simply ages).
            % Only once VSA has shown it answers fast (last measurement < 1 s),
            % so a prefetched frame does not age during VSA warm-up.
            if obj.Config.prefetch && ~obj.PrefetchHold && ~isempty(obj.Log) && ...
                    obj.Log(end).elapsedSeconds < 1 && ...
                    (obj.Metadata.continuous || seq + 1 < obj.Metadata.frames_planned)
                obj.sendRequest();
            end
            if strlength(string(obj.Config.rawDir)) > 0
                fid = fopen(fullfile(obj.Config.rawDir, sprintf('wire_%05d_%s.i16', seq, frame.phase)), 'w');
                fwrite(fid, body, 'uint8'); fclose(fid);
            end
        end

        function sendRequest(obj)
            obj.RequestPosix = origapp.LegacyVsaBackend.now();   % before the write
            obj.Stream.Write(uint8('N'), 0, 1); obj.Pending = true;
            obj.Got = 0; obj.InBody = false;
        end

        function updateTheta(obj, bound, hostT)
            if ~isfinite(obj.ThetaLB) || bound >= obj.ThetaLB - obj.DRIFT*max(0, hostT - obj.ThetaLBHost)
                obj.ThetaLB = bound; obj.ThetaLBHost = hostT;
            end
        end

        function updateStale(obj, ended)
            if nargin < 2, ended = false; end
            if ~isfinite(obj.VsaState.timestamp) || obj.VsaState.state == "stale", return; end
            age = origapp.LegacyVsaBackend.now() - obj.VsaState.timestamp;
            if ended || age > obj.Config.staleSeconds
                s = obj.VsaState;
                s.valid = false; s.state = "stale"; s.evmPercent = NaN; s.evmDb = NaN;
                if ended, s.reason = "stream ended: no fresh frame";
                else, s.reason = sprintf('no fresh frame for %.1f s (> %g s)', age, obj.Config.staleSeconds); end
                s.shortReason = "stale: no fresh frame";
                s.updatedPosix = origapp.LegacyVsaBackend.now();
                obj.VsaState = s;
                obj.showStatus("RFSoC native VSA [" + obj.SourceTag + "] | STALE: " + s.reason + " | last display is NOT current");
            end
        end

        function showStatus(obj, text)
            text = string(text);
            if strlength(text) > 200, text = extractBefore(text, 198) + ".."; end
            obj.DisplayLog(end+1,1) = string(datetime('now','TimeZone','UTC','Format','HH:mm:ss.SSS')) + " " + text;
            if ~obj.DisplaySupported || isempty(obj.Session) || ~isvalid(obj.Session), return; end
            try
                obj.Session.setDisplayStatus(text);
            catch er
                obj.DisplayLog(end+1,1) = "display error: " + string(er.message);
            end
        end

        function b = readBlocking(obj, n)
            b = zeros(n,1,'uint8'); got = 0; t = tic;
            while got < n
                a = NET.createArray('System.Byte', n-got);
                m = obj.Stream.Read(a, 0, n-got);
                if m <= 0, error('a2live:Disconnected','Stream closed'); end
                aa = uint8(a); b(got+(1:m)) = aa(1:m); got = got + m;
                assert(toc(t) < 30, 'a2live:Timeout', 'Header timeout');
            end
        end
    end
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
