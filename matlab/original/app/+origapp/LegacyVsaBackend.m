classdef LegacyVsaBackend < handle
    %LEGACYVSABACKEND Board stream backend of the app (matlab/README.md):
    % receives the board helper's frames and checks every window on the host.
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
    % v3 (cfg.wireMode = "window4", helper --wire-mode window4): magic R4X2IQ3,
    % frames IQZ3/IQL3 + extension (window start row, SHA256 of the full capture
    % and of the selected window, board selection time, bounded JSON summary),
    % END3. The wire carries ALL FOUR measured streams as one contiguous
    % 32768-row window of the same full-RAM capture, selected on the board to
    % exclude the legacy DAC loop boundary. next() returns 32768-by-4 measured
    % samples, availableChannels [1 1 1 1]; the host re-checks every frame
    % independently (per-stream wanted-reference lock, boundary/jump-free
    % blocks, window SHA, a repeated capture SHA is stale) and reports
    % signalChannels (stream lock >= lockThreshold).
    % The stream mode must equal cfg.wireMode; there is no silent switch.
    properties (SetAccess = private)
        Config
        Control = []
        ControlPaused = false
        Display = []            % second control connection, board OLED only (showEvm)
        DisplayOff = false
        DisplayAt = -Inf
        Metadata = struct()
        Ended = false
        LastFrameMeta = struct()
        Delivered = {}
        SourceTag = "SOURCE NOT YET KNOWN"   % LIVE HW only for helper source rfsoc4x2-hardware
        PrefetchHold = false
        N = 131072                 % wire samples per stream (v2 131072, v3 32768)
        FRAME_BYTES = 4*131072
        AVAILABLE = logical([1 0 0 0])
        FORMAT = "int16le-IQ-1ch-fullram-v2"
        WireMode = "adc-d-fullram"
        LastMeasured4 = []         % v3: measured N-by-4 (I - jQ)/2^16 of the last frame
        LastCaptureSha = ""
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
        Ref = []
        RefFftConj = []
        Burst = NaN
        RefAct = []             % frame-level activity of Ref (windowActivityModel)
        Closed = false
        Stage = 0               % 0 header, 1 v3 extension, 2 v3 extension JSON, 3 body
        ExtBuf = []
        ExtBytes = []
        JsonBuf = []
        RowsAllowed = 32768     % v3 window sizes the stream declared (window_rows_allowed)
        Compressed = false      % codec of the frame being received (its magic)
    end
    properties (Constant)
        LOOP_N = 131072         % legacy loop (= full capture) length at 125 MHz
        WIN_N = 32768           % v3 window rows
        HEADER_BYTES = 52
        EXT_BYTES = 74          % <II32s32sH
        EXT_JSON_MAX = 1024
        DRIFT = 100e-6          % allowance for board/host clock rate difference
        CODEC = "byteplane-shuffle+deflate-raw-lossless"
    end
    methods
        function obj = LegacyVsaBackend(cfg)
            req = {'host','port','referenceMat','orientation'};
            for k = 1:numel(req)
                assert(isfield(cfg,req{k}), 'a2live:Config', 'Missing %s', req{k});
            end
            assert(any(cfg.orientation == ["IminusjQ","IplusjQ"]), 'a2live:Config', ...
                'orientation must be IminusjQ (as delivered) or IplusjQ (conjugated)');
            d = struct('connectTimeoutSeconds',30,'lockThreshold',0.3, ...
                'staleSeconds',2,'allowContinuous',false,'rawDir',"",'maxTimestampDelaySeconds',2, ...
                'expectSource',"rfsoc4x2-hardware",'prefetch',true, ...
                'wireMode',"adc-d-fullram",'frameLogFile',"",'controlPort',0,'controlTimeoutSeconds',8,'controlLogFile',"");
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(cfg,f{k}), cfg.(f{k}) = d.(f{k}); end
            end
            assert(cfg.lockThreshold >= 0.3 && cfg.lockThreshold < 1, 'a2live:Config', ...
                'legacy profile needs lockThreshold in [0.3, 1)');
            cfg.wireMode = string(cfg.wireMode);
            assert(any(cfg.wireMode == ["adc-d-fullram","window4"]), 'a2live:Config', ...
                'wireMode must be "adc-d-fullram" (v2) or "window4" (v3)');
            obj.Config = cfg;
            obj.setMode(cfg.wireMode);
            r = load(cfg.referenceMat);
            assert(numel(r.ref125) == obj.LOOP_N && strtrim(string(r.profile)) == "legacy-ofdm64-truncated-v1", ...
                'a2live:Reference', 'Wrong legacy reference');
            obj.Ref = r.ref125(:); obj.Burst = double(r.burst125);
            obj.RefFftConj = conj(fft(obj.Ref));
            obj.RefAct = origapp.windowActivityModel(obj.Ref);
        end

        function c = capabilities(obj)
            names=strings(1,0);
            if obj.Config.controlPort>0, names=["fc","phase","dphase","dacPow","da","dataStream"];end
            % Reduced windows: only when the connected stream declared them.
            if obj.Config.controlPort>0 && numel(obj.RowsAllowed)>1, names(end+1)="dataChan";end
            % Converter path settings (gains, I/Q phase, attenuator, current, fine
            % phases) only when the connected board helper declares them.
            if obj.Config.controlPort>0 && isfield(obj.Metadata,'path_controls')
                names=[names reshape(string(obj.Metadata.path_controls),1,[])];
            end
            display=strings(1,0);
            if obj.Config.controlPort>0 && isfield(obj.Metadata,'display_controls')
                display=reshape(string(obj.Metadata.display_controls),1,[]);
            end
            c=struct('commands',names,'display',display);
        end

        function showEvm(obj,evmPercent,angleDeg)
            % Board OLED only: the EVM and the main (wanted) DOA in the app go to the
            % board at most every 2 s over its own control connection. evm/doa change
            % no converter and no settings revision; any failure turns the display
            % updates off for the session and never touches the IQ stream or the
            % settings connection. A helper without "doa" gets the EVM only.
            if nargin<3, angleDeg=NaN; end
            if obj.DisplayOff || obj.Closed || obj.WireMode~="window4", return, end
            t=obj.now();
            if t-obj.DisplayAt<2, return, end
            obj.DisplayAt=t;
            if ~any(obj.capabilities().display=="evm"), obj.DisplayOff=true; return, end
            code=-1;
            if isscalar(evmPercent) && isfinite(evmPercent), code=round(min(max(evmPercent,0),1000)*100);end
            line=sprintf('evm %d',code);
            if any(obj.capabilities().display=="doa")
                doa=99999;
                if isscalar(angleDeg) && isfinite(angleDeg), doa=round(min(max(angleDeg,-180),180)*100);end
                line=sprintf('%s#doa %d',line,doa);
            end
            try
                if isempty(obj.Display)
                    obj.Display=origapp.BoardControl(obj.Config.host,obj.Config.controlPort,2);
                end
                obj.Display.send(line);
            catch
                obj.DisplayOff=true;
                if ~isempty(obj.Display), delete(obj.Display); obj.Display=[]; end
            end
        end

        function reply = send(obj,line)
            assert(obj.Config.controlPort>0 && obj.WireMode=="window4", ...
                'origapp:Control','Live board commands require window4 and a control port.');
            try
                if isempty(obj.Control)
                    obj.Control=origapp.BoardControl(obj.Config.host,obj.Config.controlPort,obj.Config.controlTimeoutSeconds);
                end
                reply=obj.Control.send(line);
            catch err
                if string(err.identifier)~="origapp:CommandRejected"
                    obj.close();  % no IQ may continue with an uncertain applied setting
                end
                rethrow(err)
            end
            if strlength(string(obj.Config.controlLogFile))>0
                try
                    fid=fopen(obj.Config.controlLogFile,'a');
                    assert(fid>=0,'origapp:ControlLog','Cannot open command acknowledgement log.');
                    g=onCleanup(@()fclose(fid));
                    fprintf(fid,'%s\n',jsonencode(struct('timestamp',obj.now(),'command',string(line),'reply',reply)));
                    clear g
                catch err
                    warning('origapp:ControlLog','Command applied but its log could not be saved: %s',err.message);
                end
            end
            obj.ControlPaused=~logical(reply.result.streaming);
            obj.PrefetchHold=obj.ControlPaused;
        end

        function state=controlStatus(obj)
            state=[];
            if ~isempty(obj.Control) && isfield(obj.Control.LastReply,'result')
                state=obj.Control.LastReply.result;
            end
        end

        function m = availableChannels(obj)
            m = obj.AVAILABLE;
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
            obj.ExtBuf = NET.createArray('System.Byte', obj.EXT_BYTES);
            obj.JsonBuf = NET.createArray('System.Byte', obj.EXT_JSON_MAX);
            obj.Stream.ReadTimeout = int32(10000);
            magic = obj.readBlocking(8);
            want = ifelse(obj.WireMode == "window4", 'R4X2IQ3', 'R4X2IQ2');
            assert(isequal(magic(:).', uint8([want newline])), 'a2live:Protocol', ...
                'Wrong magic (wireMode %s needs helper %s)', obj.WireMode, want);
            n = double(typecast(obj.readBlocking(4),'uint32'));
            assert(n < 65536, 'a2live:Protocol', 'Oversized header');
            md = jsondecode(native2unicode(obj.readBlocking(n).','UTF-8'));
            obj.validateMetadata(md);
            if obj.Config.controlPort>0
                assert(isfield(md,'control_port') && md.control_port==obj.Config.controlPort && ...
                    isfield(md,'control_protocol') && string(md.control_protocol)=="jsonline-v1", ...
                    'a2live:Protocol','Board control endpoint differs from configuration.');
            end
            obj.SourceTag = origapp.LegacyVsaBackend.sourceTag(string(md.source));
            obj.RowsAllowed = obj.N;
            if obj.WireMode == "window4" && isfield(md,'window_rows_allowed')
                ra = double(md.window_rows_allowed(:).');
                assert(~isempty(ra) && all(ra == fix(ra)) && all(ra >= 4096 & ra <= obj.N) && any(ra == obj.N), ...
                    'a2live:Metadata', 'Invalid window_rows_allowed');
                obj.RowsAllowed = ra;
            end
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
            if obj.Ended || obj.Closed, return; end
            if isempty(obj.Client), obj.open(); end
            t = tic;
            if obj.ControlPaused, return; end
            if ~obj.Pending, obj.sendRequest(); end
            while true
                switch obj.Stage
                    case 0, target = obj.Hdr; need = obj.HEADER_BYTES;
                    case 1, target = obj.ExtBuf; need = obj.EXT_BYTES;
                    case 2, target = obj.JsonBuf; need = obj.BodyNeedJson();
                    otherwise, target = obj.Body; need = obj.BodyNeed;
                end
                if obj.Got == need
                    if obj.Stage == 0
                        if obj.headerComplete(), return; end   % END2/END3
                        continue
                    elseif obj.Stage == 1
                        obj.extensionComplete(); continue
                    elseif obj.Stage == 2
                        obj.ExtBytes = [obj.ExtBytes; reshape(uint8(obj.JsonBuf), [], 1)];
                        obj.ExtBytes = obj.ExtBytes(1:obj.EXT_BYTES + need);
                        obj.Stage = 3; obj.Got = 0; continue
                    end
                    break
                end
                left = timeoutSeconds - toc(t);
                if left <= 0, return; end
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

        function holdPrefetch(obj, tf)
            obj.PrefetchHold = logical(tf);
        end

        function tf = requestOutstanding(obj)
            tf = obj.Pending;
        end

        function close(obj)
            if obj.Closed, return; end
            obj.Closed = true;
            try
                if ~isempty(obj.Client), obj.Client.Close(); end
            catch
            end
            obj.Client = []; obj.Stream = [];
            if ~isempty(obj.Control), delete(obj.Control); obj.Control=[]; end
            if ~isempty(obj.Display), delete(obj.Display); obj.Display=[]; end
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
            N = obj.LOOP_N; L = 8192; nb = numel(x)/L; B = obj.Burst;
            assert(nb == fix(nb) && nb >= 1, 'a2live:Window', 'Window length must be a multiple of 8192');
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
            if obj.WireMode == "window4"
                % v3: the board already excluded the capture's last block. The
                % legacy loop is burst-periodic (bursts correlate ~0.98), so the
                % block loop index - and the "matched range crosses the loop end"
                % rule - is ambiguous by whole bursts (live false rejections);
                % only the burst-phase jumps (psi), which a real wrap (6459) or
                % a loss always produces, mark a boundary.
                excl = unique([jumps, jumps + 1]);
            end
            A = struct('medianLock', median(lock), 'lock', lock, 'loopIdx', loopIdx, ...
                'psi', psi, 'dpsi', d, 'jumps', jumps, 'wraps', wraps, 'boundaryBlocks', excl, ...
                'jumpSizes', d(jumps), 'blockLen', L);
        end

        function A = hostWindowCheck(obj, X)
            % Independent host check of one v3 window (N-by-4, I - jQ counts):
            % per-stream wanted-reference block locks, and sample continuity of
            % the strongest stream by origapp.windowIntegrity (frame-timing
            % model; covers the first/last 8192-row blocks, fails closed where
            % the data cannot show a wrap). The
            % 8192-block burst-phase jumps are kept only as a logged diagnostic:
            % they are burst-label ambiguous (live seq-25 false positive) and
            % blind inside the first/last block.
            if obj.Config.orientation == "IplusjQ", X = conj(X); end
            locks = zeros(1, size(X,2)); B = []; kb = 1;
            for k = 1:size(X,2)
                Ak = obj.analyzeBlocks(X(:,k));
                locks(k) = Ak.medianLock;
                if isempty(B) || Ak.medianLock > B.medianLock, B = Ak; kb = k; end
            end
            I = struct('ok', false, 'reason', "no stream locked", 'lagSpread', NaN, 'minCorr', NaN, ...
                'anchorsTried', 0, 'elapsedS', 0, 'startPhase', NaN, 'endPhase', NaN);
            if max(locks) >= obj.Config.lockThreshold
                I = origapp.windowIntegrity(X(:,kb), obj.Ref, obj.RefFftConj, obj.Burst, obj.RefAct);
            end
            % Without any locked stream the wrap search cannot run: the window
            % is shown unverified (interference can drown every stream; the
            % user wants the plots to keep updating) instead of refused.
            verified = max(locks) >= obj.Config.lockThreshold;
            A = struct('streamLocks', locks, 'boundaryFree', logical(I.ok || ~verified), 'verified', verified, ...
                'integrityReason', string(I.reason), ...
                'integrityStream', kb - 1, 'lagSpread', I.lagSpread, 'minCorr', I.minCorr, ...
                'anchorsTried', I.anchorsTried, 'integrityS', I.elapsedS, ...
                'startPhase', I.startPhase, 'endPhase', I.endPhase, ...
                'legacyPsiJumps', B.jumps, 'wraps', B.wraps, 'loopIdx1', B.loopIdx(1), 'psi', B.psi);
        end
        function A = reducedWindowCheck(obj, X, start, info)
            % Host check of a reduced v3 window (fewer rows, made for display
            % rate): every stream's first and last 4096 rows must correlate
            % with the transmitted loop at the board-reported alignment
            % (+-8 rows). This shows the wanted signal on each stream and
            % that both ends belong to one pass; unlike windowIntegrity it
            % does not search the rows between them for a wrap or a loss.
            t0 = tic;
            if obj.Config.orientation == "IplusjQ", X = conj(X); end
            n = size(X,1); m = min(n, 4096); locks = zeros(1, size(X,2));
            kk = origapp.LegacyVsaBackend.metaField(info, 'kk');
            reason = "reduced window: board alignment missing";
            if isnumeric(kk) && isscalar(kk) && isfinite(kk) && kk == fix(kk)
                base = mod(start - kk, obj.LOOP_N);
                parts = unique([0, n - m]); best = zeros(numel(parts), size(X,2));
                for q = 1:numel(parts)
                    x = X(parts(q) + (1:m), :); nx = sqrt(sum(abs(x).^2, 1)) + realmin;
                    for lag = -8:8
                        r = obj.Ref(mod(base + parts(q) + lag + (0:m-1), obj.LOOP_N) + 1);
                        c = abs(r' * x) ./ (sqrt(sum(abs(r).^2)) * nx + realmin);
                        best(q,:) = max(best(q,:), c);
                    end
                end
                locks = min(best, [], 1);
                reason = "reduced window: reference lock at both ends, no wrap search";
            end
            [~, kb] = max(locks);
            % The reduced check is a lock test, not a wrap search: a stream
            % without lock (interference) leaves the window unverified, shown.
            % Only a missing board alignment refuses it.
            unaligned = isequal(string(origapp.LegacyVsaBackend.metaField(info, 'candidate')), "none");
            A = struct('streamLocks', locks, 'boundaryFree', unaligned || (isnumeric(kk) && isscalar(kk) && isfinite(kk)), ...
                'verified', all(locks >= obj.Config.lockThreshold), ...
                'integrityReason', reason, 'integrityStream', kb - 1, 'lagSpread', NaN, 'minCorr', min(locks), ...
                'anchorsTried', 0, 'integrityS', toc(t0), 'startPhase', NaN, 'endPhase', NaN, ...
                'legacyPsiJumps', [], 'wraps', [], 'loopIdx1', NaN, 'psi', []);
        end
    end
    methods (Static)
        function ok = validWindowSummary(info, reduced)
            % Fail closed on a selector fallback, missing or malformed JSON.
            % A reduced window must come from the reduced selector ("fast": offset
            % searched; "fixed": the offset of the last search, reused between
            % checks), a full one from the wrap-searching selector. Either way
            % the host checks the window against the reference itself.
            if nargin < 2, reduced = false; end
            ok = isstruct(info) && isscalar(info) && isfield(info,'candidate');
            if ~ok, return; end
            c = string(info.candidate);
            % "none": no stream locked (blank input or interference everywhere);
            % "held": reduced window at the session's last alignment while nothing
            % locks. Both are shown unverified (2026-11-24: keep showing everything).
            names = ["before-wrap","after-wrap","nowrap","clear","none"]; if reduced, names = ["fast","fixed","held","none"]; end
            ok = isscalar(c) && ~ismissing(c) && any(c == names);
        end
        function h = sha256(path)
            md = System.Security.Cryptography.SHA256.Create();
            fs = System.IO.File.OpenRead(char(path));
            c = onCleanup(@() fs.Dispose());
            h = lower(string(reshape(dec2hex(uint8(md.ComputeHash(fs)))',1,[])));
        end
        function v = field(s, name)
            v = NaN; if isstruct(s) && isfield(s,name), v = s.(name); end
        end
        function v = metaField(s, name)
            v = []; if isstruct(s) && isfield(s,name), v = s.(name); end
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
            v3 = obj.WireMode == "window4";
            assert(md.magic_version == 2 + v3 && string(md.format) == obj.FORMAT && ...
                string(md.capture) == "full-ram-contiguous" && md.adc_ram_words == 8*obj.LOOP_N && ...
                md.samples_per_channel == obj.N && md.fs_hz == 125e6 && ...
                string(md.profile) == "legacy-ofdm64-truncated-v1" && string(md.frame_header) == "<4sQQQq8sII", ...
                'a2live:Metadata', 'Format/profile/capture metadata mismatch');
            wc = double(md.wire_channels(:).'); ac = double(md.available_channels(:).');
            if v3
                assert(isfield(md,'window') && string(md.window) == "same-capture-contiguous" && ...
                    isfield(md,'window_rows') && md.window_rows == obj.N && isfield(md,'capture_rows') && ...
                    md.capture_rows == obj.LOOP_N && isfield(md,'frame_extension') && ...
                    string(md.frame_extension) == "<II32s32sH" && isfield(md,'extension_json_max') && ...
                    md.extension_json_max == obj.EXT_JSON_MAX, 'a2live:Metadata', 'v3 window metadata mismatch');
                assert(isequal(wc, 0:3), 'a2live:Metadata', 'v3 wire must carry streams 0..3; got %s', mat2str(wc));
            else
                assert(isequal(wc, 0), 'a2live:Metadata', 'Wire must carry exactly stream0 (ADC_D); got %s', mat2str(wc));
            end
            assert(isequal(ac, double(obj.AVAILABLE)), 'a2live:Metadata', ...
                'availableChannels must be %s; got %s', mat2str(double(obj.AVAILABLE)), mat2str(ac));
            assert(isfield(md,'compression') && any(string(md.compression) == ["none", obj.CODEC]), ...
                'a2live:Metadata', 'Unknown wire compression');
            assert(md.frame_bytes == 4*obj.N*numel(wc) && md.frame_bytes == obj.FRAME_BYTES, 'a2live:Metadata', ...
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
            v3 = obj.WireMode == "window4";
            if kind == string(ifelse(v3, "END3", "END2"))
                assert(seq == obj.ExpectedSeq, 'a2live:Sequence', 'END count %d differs from %d frames received', seq, obj.ExpectedSeq);
                obj.Ended = true; obj.Pending = false; ended = true;
                return
            end
            % The codec is per frame (its magic): a reduced v3 window is sent raw
            % also on a stream that compresses its full windows.
            z = startsWith(string(kind), "IQZ");
            assert(any(string(kind) == ["IQZ","IQL"] + string(2 + v3)) && ...
                (~z || string(obj.Metadata.compression) ~= "none") && ...
                (z || v3 || string(obj.Metadata.compression) == "none"), 'a2live:Protocol', 'Bad frame magic %s', kind);
            obj.Compressed = z;
            assert(seq == obj.ExpectedSeq, 'a2live:Sequence', 'Missing/out-of-order frame: got seq %d, expected %d', seq, obj.ExpectedSeq);
            assert(obj.Metadata.continuous || seq < obj.Metadata.frames_planned, 'a2live:Bound', ...
                'Frame %d exceeds the claimed bound of %d frames', seq, obj.Metadata.frames_planned);
            assert(mask == ifelse(v3, 15, 1), 'a2live:Metadata', 'Frame channel mask %d differs from metadata', mask);
            if z
                assert(nbytes > 36 && nbytes <= obj.FRAME_BYTES + 36 + 8192, 'a2live:Protocol', ...
                    'Compressed frame length %d out of range', nbytes);
            else
                assert(nbytes == obj.FRAME_BYTES || (v3 && any(nbytes == 16*obj.RowsAllowed)), 'a2live:Protocol', ...
                    'Frame wire length %d differs from %d', nbytes, obj.FRAME_BYTES);
            end
            obj.BodyNeed = nbytes;
            obj.HdrBytes = h; obj.InBody = true; obj.Got = 0;
            obj.Stage = ifelse(v3, 1, 3); obj.ExtBytes = [];
        end

        function extensionComplete(obj)
            e = uint8(obj.ExtBuf); e = e(:);
            n = double(typecast(e(73:74), 'uint16'));
            assert(n >= 2 && n <= obj.EXT_JSON_MAX, 'a2live:Protocol', 'Frame extension JSON length %d out of range', n);
            start = double(typecast(e(1:4), 'uint32'));
            rows = obj.N; if ~obj.Compressed, rows = obj.BodyNeed/16; end
            assert(start + rows <= obj.LOOP_N - 8192, 'a2live:Protocol', ...
                'Window start row %d outside the capture (last block excluded)', start);
            obj.ExtBytes = e; obj.Got = 0; obj.Stage = 2;
        end

        function n = BodyNeedJson(obj)
            n = double(typecast(obj.ExtBytes(73:74), 'uint16'));
        end

        function frame = finishFrame(obj)
            h = obj.HdrBytes; payload = uint8(obj.Body); payload = payload(1:obj.BodyNeed);
            if obj.Compressed
                body = origapp.LegacyVsaBackend.decodeWire(payload, obj.FRAME_BYTES);   % verified lossless
            else
                body = payload;
            end
            obj.Pending = false; obj.Got = 0; obj.InBody = false; obj.Stage = 0;
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
            v3 = obj.WireMode == "window4";
            if v3
                w = reshape(w, 8, []).';
                samples = w(:,1:2:7) - 1j*w(:,2:2:8);   % four measured streams, same capture rows
                obj.LastMeasured4 = samples/2^16;
            else
                w = reshape(w, 2, []).';
                samples = zeros(obj.N, 4);
                samples(:,1) = w(:,1) - 1j*w(:,2);      % measured ADC_D; columns 2..4 placeholders
            end
            obj.LastReceiptPosix = received;
            frame = struct('samples', samples, 'timestamp', ts, 'sequence', seq, ...
                'phase', strtrim(char(h(37:44).')), 'availableChannels', obj.AVAILABLE, ...
                'wireChannels', ifelse(v3, 0:3, 0), 'wireFormat', obj.FORMAT, 'hostRequestSent', obj.RequestPosix, ...
                'hostReceived', received, 'boardDelayS', delay, 'requestBoundTimestamp', obj.RequestPosix + delay, ...
                'anchorTimestamp', obj.Anchor.hostPosix + (capMono - obj.Anchor.boardMonoNs)/1e9, ...
                'boardRealtime', boardReal);
            if strlength(string(obj.Config.rawDir)) > 0     % every received window, also rejected ones
                fid = fopen(fullfile(obj.Config.rawDir, sprintf('wire_%05d_%s.i16', seq, frame.phase)), 'w');
                fwrite(fid, body, 'uint8'); fclose(fid);
            end
            if v3
                try
                    frame = obj.windowFrame(frame, body, samples);
                catch er
                    obj.logFrame(frame, string(er.identifier) + ": " + string(er.message));
                    rethrow(er)
                end
            end
            if obj.Config.controlPort>0
                assert(isfield(frame,'boardInfo') && isfield(frame.boardInfo,'control_revision'), ...
                    'a2live:Protocol','Control-enabled frame has no settings revision.');
                rev=frame.boardInfo.control_revision;
                assert(isscalar(rev) && isnumeric(rev) && isfinite(rev) && rev>=0 && rev==fix(rev), ...
                    'a2live:Protocol','Invalid settings revision.');
                frame.controlRevision=rev;
                if ~isempty(obj.Control) && rev<obj.Control.Revision
                    obj.logFrame(frame,"settings changed after this capture");
                    error('origapp:SettingsChanged','Discarded a capture from before the acknowledged settings change.');
                end
            end
            obj.LastFrameMeta = rmfield(frame,'samples');
            obj.logFrame(frame, "");
            obj.Delivered{end+1} = obj.LastFrameMeta;
            if numel(obj.Delivered) > 5000, obj.Delivered(1) = []; end   % bounded history
            % Prefetch: at most ONE outstanding request. The next capture starts
            % now, so its transfer overlaps this frame's processing; the board
            % still acquires only on request and the timestamp is the capture
            % time (an unread prefetched frame simply ages).
            if obj.Config.prefetch && ~obj.PrefetchHold && ...
                    (obj.Metadata.continuous || seq + 1 < obj.Metadata.frames_planned)
                obj.sendRequest();
            end
        end

        function logFrame(obj, frame, err)
            % One JSON record per received frame (accepted or not), before any
            % Controller/plot step: host verdict, reasons and provenance.
            if strlength(string(obj.Config.frameLogFile)) == 0, return; end
            e = rmfield(frame, intersect(fieldnames(frame), {'samples'}));
            e.receiveError = err;
            e.provenance = "windowStart, captureSha256, boardCandidate and boardStreamLocks are board-reported; " + ...
                "windowSha256 (equal to the decoded bytes), hostStreamLocks and integrity are host-verified";
            fid = fopen(obj.Config.frameLogFile, 'a'); fprintf(fid, '%s\n', jsonencode(e)); fclose(fid);
        end

        function sendRequest(obj)
            obj.RequestPosix = origapp.LegacyVsaBackend.now();   % before the write
            obj.Stream.Write(uint8('N'), 0, 1); obj.Pending = true;
            obj.Got = 0; obj.InBody = false; obj.Stage = 0;
        end

        function setMode(obj, mode)
            obj.WireMode = string(mode);
            if obj.WireMode == "window4"
                obj.N = obj.WIN_N; obj.AVAILABLE = true(1,4); obj.FORMAT = "int16le-IQ-4ch-window-v3";
                obj.FRAME_BYTES = 16*obj.WIN_N;
            else
                obj.N = obj.LOOP_N; obj.AVAILABLE = logical([1 0 0 0]); obj.FORMAT = "int16le-IQ-1ch-fullram-v2";
                obj.FRAME_BYTES = 4*obj.LOOP_N;
            end
        end

        function frame = windowFrame(obj, frame, body, samples)
            % v3 extension: start row, SHA256 of the full capture and of the
            % window; the window SHA must equal the decoded bytes (lossless,
            % same window); a repeated full-capture SHA is a stale frame.
            e = obj.ExtBytes;
            start = double(typecast(e(1:4), 'uint32'));
            selUs = double(typecast(e(5:8), 'uint32'));
            fullSha = lower(string(reshape(dec2hex(e(9:40))', 1, [])));
            winSha = e(41:72);
            md = System.Security.Cryptography.SHA256.Create();
            d = uint8(md.ComputeHash(body(:))); d = d(:);
            assert(isequal(d, winSha(:)), 'a2live:Protocol', 'Window SHA256 differs from the decoded window');
            assert(fullSha ~= obj.LastCaptureSha, 'a2live:Stale', 'Repeated full-capture SHA256 (stale capture)');
            obj.LastCaptureSha = fullSha;
            info = struct();
            try
                info = jsondecode(native2unicode(e(75:end).', 'UTF-8'));
            catch
            end
            t = tic;
            reduced = size(samples,1) < obj.N;
            if reduced
                A = obj.reducedWindowCheck(samples, start, info);
            else
                A = obj.hostWindowCheck(samples);
            end
            frame.windowStart = start;
            frame.captureSha256 = fullSha;
            frame.windowSha256 = lower(string(reshape(dec2hex(winSha)', 1, [])));
            frame.boardSelectS = selUs/1e6;
            frame.boardInfo = info;
            frame.boardStreamLocks = obj.metaField(info, 'stream_locks');
            frame.hostStreamLocks = A.streamLocks;
            frame.signalChannels = A.streamLocks >= obj.Config.lockThreshold;
            summaryOK = origapp.LegacyVsaBackend.validWindowSummary(info, reduced);
            frame.reducedWindow = reduced;
            frame.boundaryFree = logical(A.boundaryFree && summaryOK);
            frame.boundaryVerified = logical(A.verified);
            frame.boardSummaryOk = summaryOK;
            cand = obj.metaField(info, 'candidate');
            if ischar(cand) || (isstring(cand) && isscalar(cand)), frame.boardCandidate = string(cand); else, frame.boardCandidate = "missing"; end
            frame.integrityReason = A.integrityReason;
            frame.integrityStream = A.integrityStream;
            frame.integrityLagSpread = A.lagSpread;
            frame.integrityMinCorr = A.minCorr;
            frame.integrityS = A.integrityS;
            frame.legacyPsiJumps = A.legacyPsiJumps;
            frame.selectionProvenance = "board-reported window start, capture SHA and selector; host-verified window SHA, stream locks and sample continuity (windowIntegrity)";
            frame.hostCheckS = toc(t);
        end

        function updateTheta(obj, bound, hostT)
            if ~isfinite(obj.ThetaLB) || bound >= obj.ThetaLB - obj.DRIFT*max(0, hostT - obj.ThetaLBHost)
                obj.ThetaLB = bound; obj.ThetaLBHost = hostT;
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
