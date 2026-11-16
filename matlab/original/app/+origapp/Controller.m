classdef Controller < handle
    %CONTROLLER Owns the injected backend, the board-command queue, frame
    % freshness and the bounded error policy for VSA_rfsoc_refactor_exported.
    % It never opens a socket, VSA or instrument by itself: all I/O goes
    % through the injected backend (BACKEND_CONTRACT.md).

    properties (SetAccess = private)
        Config
        Backend = []
        Pending = strings(0,1)      % queued board commands (original commandsHandler)
        Sent = strings(0,1)         % commands actually handed to backend.send
        IsOpen = false
        ConsecutiveErrors = 0
        BoundaryFrames = 0         % intact frames with invalid sample continuity
        ExpiredFrames = 0          % frames too old after processing
        NoSignalFrames = 0          % intact frames rejected for missing wanted signal (not errors)
        TotalErrors = 0
        FramesAccepted = 0
        LastFrameTime = NaN         % posix seconds of the last accepted frame
        LastSequence = NaN
        LastError = ""
    end

    methods
        function obj = Controller(cfg)
            obj.Config = cfg;
            obj.Backend = cfg.backend;
            if ~isempty(obj.Backend)
                for op = ["next","close"]
                    assert(origapp.Controller.hasOp(obj.Backend, op), 'origapp:Backend', ...
                        'Backend must provide %s().', op);
                end
            end
        end

        function tf = hasBackend(obj)
            tf = ~isempty(obj.Backend);
        end

        function queue(obj, command)
            % Original commandsHandler: commands are joined with '#'.
            obj.Pending(end+1,1) = string(command);
        end

        function open(obj)
            assert(obj.hasBackend(), 'origapp:Backend', 'No backend injected (cfg.backend is empty).');
            if obj.IsOpen, return; end
            try
                if origapp.Controller.hasOp(obj.Backend,"open"), obj.Backend.open(); end
                m=obj.availableChannels();
                assert(obj.Config.directOnly || all(m),'origapp:Channels', ...
                    'Array mode needs four measured channels.');
                obj.IsOpen=true;
            catch err
                try, obj.Backend.close(); catch, end
                rethrow(err);
            end
            obj.ConsecutiveErrors = 0;
        end

        function msg = flushCommands(obj)
            % Original partReset sent queued commands on reconnect. Here they
            % are only sent with cfg.allowBoardCommands and a backend send().
            msg = "";
            if isempty(obj.Pending), return; end
            if ~obj.Config.allowBoardCommands
                msg = sprintf('%d board command(s) held: cfg.allowBoardCommands=false', numel(obj.Pending));
                return
            end
            if ~origapp.Controller.hasOp(obj.Backend, "send")
                msg = sprintf('%d board command(s) held: backend has no send()', numel(obj.Pending));
                return
            end
            line = strjoin(obj.Pending, '#');
            obj.Backend.send(char(line));
            obj.Sent(end+1,1) = line;
            obj.Pending = strings(0,1);
        end

        function [frame, status] = acquire(obj)
            % Bounded read of one frame plus freshness checks. Returns [] and
            % a status when no fresh frame is available (not an error).
            frame = []; status = "";
            raw = obj.Backend.next(obj.Config.frameTimeoutSeconds);
            nowS = origapp.Controller.nowSeconds();
            if isempty(raw)
                if isnan(obj.LastFrameTime) || nowS - obj.LastFrameTime > obj.Config.staleSeconds
                    status = "stale";
                else
                    status = "no-frame";
                end
                return
            end
            assert(isstruct(raw) && isfield(raw,'samples'), 'origapp:Backend', ...
                'next() must return a struct with .samples.');
            x = raw.samples;
            assert(isnumeric(x) && size(x,2)==4 && size(x,1)>=16 && all(isfinite(x),'all'), ...
                'origapp:Frame', 'Frame must be finite N-by-4 samples.');
            assert(size(x,1)==obj.expectedSamples(), 'origapp:Frame', ...
                'Frame has %d samples, dataChan expects %d.', size(x,1), obj.expectedSamples());
            assert(isfield(raw,'sequence') && isnumeric(raw.sequence) && ...
                isscalar(raw.sequence) && isreal(raw.sequence) && isfinite(raw.sequence) && ...
                raw.sequence>=0 && raw.sequence==fix(raw.sequence), ...
                'origapp:Sequence','Frame needs a finite nonnegative integer sequence.');
            assert(isnan(obj.LastSequence) || raw.sequence > obj.LastSequence, ...
                'origapp:Sequence','Repeated or out-of-order frame.');
            obj.LastSequence = raw.sequence;
            assert(isfield(raw,'timestamp') && isnumeric(raw.timestamp) && ...
                isscalar(raw.timestamp) && isreal(raw.timestamp) && isfinite(raw.timestamp), ...
                'origapp:Timestamp','Frame needs a finite acquisition timestamp.');
            t=raw.timestamp;
            assert(nowS-t<=obj.Config.staleSeconds && t-nowS<=0.5, ...
                'origapp:Stale','Frame is old or its acquisition timestamp is in the future.');
            if isfield(raw,'availableChannels')
                m = raw.availableChannels;
                assert(islogical(m) && isequal(size(m),[1 4]) && any(m), ...
                    'origapp:Channels','availableChannels must be a 1-by-4 logical mask.');
                assert(obj.Config.directOnly || all(m), 'origapp:Channels', ...
                    'Array mode needs 4 measured channels; backend reports %s.', mat2str(m));
            end
            if ~obj.Config.directOnly && isfield(raw,'signalChannels')
                % Backend's independent per-stream wanted-reference lock: a
                % blank, dead or missing stream must not enter DOA/beamforming.
                sc = raw.signalChannels;
                assert(islogical(sc) && isequal(size(sc),[1 4]), 'origapp:Channels', ...
                    'signalChannels must be a 1-by-4 logical mask.');
                assert(all(sc), 'origapp:NoSignal', ...
                    'No wanted-signal lock on stream(s) %s: array DOA/pattern unavailable.', mat2str(find(~sc)-1));
            end
            if isfield(raw,'boundaryFree')
                assert(islogical(raw.boundaryFree) && isscalar(raw.boundaryFree), ...
                    'origapp:Channels','boundaryFree must be a logical scalar.');
                assert(raw.boundaryFree, 'origapp:Boundary', ...
                    'Capture window crosses a loop boundary or sample jump: DOA/pattern unavailable.');
            end
            obj.LastFrameTime = t;
            frame = raw;
        end

        function m = availableChannels(obj)
            % Optional backend op. Unavailable columns in samples are interface
            % placeholders, not measured data. Default: all four measured.
            m = true(1,4);
            if obj.hasBackend() && origapp.Controller.hasOp(obj.Backend, "availableChannels")
                m = obj.Backend.availableChannels();
                assert(islogical(m) && isequal(size(m),[1 4]) && any(m), 'origapp:Channels', ...
                    'availableChannels must be a 1-by-4 logical mask.');
            end
        end

        function s = vsaStatus(obj)
            % Optional backend op: latest guarded native-VSA result
            % (valid, reason, evmPercent...). [] when the backend has none.
            % sendVsa returning true only means the hook exists.
            s = [];
            if obj.hasBackend() && origapp.Controller.hasOp(obj.Backend, "vsaStatus")
                s = obj.Backend.vsaStatus();
            end
        end

        function c = capabilities(obj)
            % Optional backend op (VSA_rfsoc_new port). Declares which new
            % commands/operations the backend really supports; nothing is
            % assumed from the board name or a network address.
            %   commands        string array of command verbs it accepts
            %   txArrayElements DAC channels usable as one steerable TX array
            %   uploadDac       true when uploadDacWaveform(port, int16) exists
            c = struct('commands', strings(1,0), 'txArrayElements', 0, 'uploadDac', false);
            if obj.hasBackend() && origapp.Controller.hasOp(obj.Backend, "capabilities")
                d = obj.Backend.capabilities();
                assert(isstruct(d), 'origapp:Capabilities', 'capabilities() must return a struct.');
                f = fieldnames(c);
                for k = 1:numel(f)
                    if isfield(d, f{k}), c.(f{k}) = d.(f{k}); end
                end
                c.commands = reshape(string(c.commands), 1, []);
                assert(isscalar(c.txArrayElements) && c.txArrayElements >= 0 && ...
                    islogical(c.uploadDac) && isscalar(c.uploadDac), 'origapp:Capabilities', ...
                    'capabilities(): txArrayElements >= 0 and logical uploadDac expected.');
            end
        end

        function [ok, reason] = queueChecked(obj, command)
            % Queue a VSA_rfsoc_new command only if the policy allows it.
            [ok, reason] = origapp.commandPolicy(string(command), obj.capabilities());
            if ok, obj.queue(command); end
        end

        function uploadDac(obj, port, interleaved)
            c = obj.capabilities();
            assert(c.uploadDac && origapp.Controller.hasOp(obj.Backend, "uploadDacWaveform"), ...
                'origapp:Unsupported', ['DAC waveform upload is not provided by this backend ' ...
                '(capabilities().uploadDac=false); the file was prepared only.']);
            assert(obj.Config.allowBoardCommands, 'origapp:Unsupported', ...
                'DAC waveform upload held: cfg.allowBoardCommands=false.');
            obj.Backend.uploadDacWaveform(string(port), interleaved);
        end

        function n = expectedSamples(obj)
            n = obj.Config.dataChan;
        end

        function setDataChan(obj, n)
            obj.Config.dataChan = n;
        end

        function sent = sendVsa(obj, buffer, info)
            % Native VSA feed is backend-owned (a2). Returns false when absent.
            % info (optional): what the buffer is (kind "combined" / "weighted-
            % channel", frame sequence, weights) so the backend labels the VSA
            % input truthfully; raw measured columns need no info.
            sent = origapp.Controller.hasOp(obj.Backend, "vsaSend");
            if ~sent, return, end
            if nargin < 3 || isempty(info) || ~isobject(obj.Backend)
                obj.Backend.vsaSend(buffer);
            else
                obj.Backend.vsaSend(buffer, info);
            end
        end

        function setVsaIdle(obj, fn)
            % Optional: a backend whose native VSA call blocks may run fn while
            % it waits (display age watchdog). Backends without it ignore it.
            if origapp.Controller.hasOp(obj.Backend, "setVsaIdle"), obj.Backend.setVsaIdle(fn); end
        end

        function done = vsaReset(obj, request)
            done = origapp.Controller.hasOp(obj.Backend, "vsaReset");
            if done, obj.Backend.vsaReset(request); end
        end

        function recordSuccess(obj)
            obj.ConsecutiveErrors = 0;
            obj.FramesAccepted = obj.FramesAccepted + 1;
        end

        function mustStop = recordFailure(obj, err)
            obj.TotalErrors = obj.TotalErrors + 1;
            obj.LastError = string(err.identifier) + ": " + string(err.message);
            % Append each failure before later successes/rejections replace LastError.
            % Sequence is the last frame received by Controller, not an assertion
            % that a transport failure produced a new frame.
            if strlength(string(obj.Config.outputDir)) > 0
                try
                    if ~isfolder(obj.Config.outputDir), mkdir(obj.Config.outputDir); end
                    entry=struct('timestamp',obj.nowSeconds(), 'lastReceivedSequence',obj.LastSequence, ...
                        'lastFrameTimestamp',obj.LastFrameTime, 'identifier',string(err.identifier), ...
                        'message',string(err.message), 'stack',err.stack, 'totalErrors',obj.TotalErrors);
                    fid=fopen(fullfile(obj.Config.outputDir,'errors.jsonl'),'a');
                    assert(fid>=0,'origapp:ErrorLog','Cannot open errors.jsonl.');
                    logGuard=onCleanup(@()fclose(fid));
                    fprintf(fid,'%s\n',jsonencode(entry));
                    clear logGuard
                catch logError
                    warning('origapp:ErrorLog','Could not persist frame error: %s',logError.message);
                end
            end
            if string(err.identifier) == "origapp:Boundary"
                obj.BoundaryFrames = obj.BoundaryFrames + 1;
                mustStop = false;
                return
            elseif string(err.identifier) == "origapp:Expired"
                obj.ExpiredFrames = obj.ExpiredFrames + 1;
                mustStop = false;
                return
            end
            if string(err.identifier) == "origapp:NoSignal"
                % A frame that arrived intact but has no wanted signal on some
                % stream (blank DAC phase, lost cable) is not a transport
                % failure: the display is cleared and acquisition continues.
                obj.NoSignalFrames = obj.NoSignalFrames + 1;
                mustStop = false;
                return
            end
            obj.ConsecutiveErrors = obj.ConsecutiveErrors + 1;
            mustStop = obj.ConsecutiveErrors >= obj.Config.maxConsecutiveErrors;
        end

        function close(obj)
            if obj.IsOpen && ~isempty(obj.Backend)
                obj.IsOpen = false;
                obj.Backend.close();
            end
        end

        function delete(obj)
            try
                obj.close();
            catch
                % delete must not throw; LastError is not updated during teardown
            end
        end
    end

    methods (Static)
        function tf = hasOp(b, name)
            name = char(name);
            if isstruct(b)
                tf = isfield(b, name) && isa(b.(name), 'function_handle');
            else
                tf = ~isempty(b) && ismethod(b, name);
            end
        end

        function s = nowSeconds()
            s = posixtime(datetime('now','TimeZone','UTC'));
        end
    end
end
