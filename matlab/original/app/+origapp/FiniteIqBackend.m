classdef FiniteIqBackend < handle
    %FINITEIQBACKEND Fixture backend: serves a finite list of N-by-4 frames.
    % Implements the BACKEND_CONTRACT.md operations and records every call so
    % tests can prove which commands/VSA sends happened. No I/O.
    %   b = origapp.FiniteIqBackend(frames)            % cell of N-by-4
    %   b = origapp.FiniteIqBackend(frames,'FailAt',3) % next() throws on call 3
    properties (SetAccess = private)
        Frames
        Index = 0
        Calls = strings(0,1)
        SentCommands = strings(0,1)
        VsaFrames = 0
        IsOpen = false
        CloseCount = 0
        FailAt = []
        StaleAt = []
        RepeatAt = []
        Sequence = 0
    end
    methods
        function obj = FiniteIqBackend(frames, varargin)
            obj.Frames = frames;
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k+1};
            end
        end
        function open(obj)
            obj.Calls(end+1) = "open"; obj.IsOpen = true;
        end
        function frame = next(obj, timeoutSeconds)
            assert(timeoutSeconds > 0, 'fixture:Timeout', 'Unbounded next().');
            obj.Calls(end+1) = "next";
            assert(obj.IsOpen, 'fixture:Closed', 'next() on closed backend.');
            obj.Index = obj.Index + 1;
            if any(obj.Index == obj.FailAt)
                error('fixture:Transport', 'Injected transport failure at call %d.', obj.Index);
            end
            if obj.Index > numel(obj.Frames)
                frame = [];      % finite source exhausted: behaves like a timeout
                return
            end
            if ~any(obj.Index == obj.RepeatAt)
                obj.Sequence = obj.Sequence + 1;
            end
            ts = posixtime(datetime('now','TimeZone','UTC'));
            if any(obj.Index == obj.StaleAt), ts = ts - 3600; end
            frame = struct('samples', obj.Frames{obj.Index}, 'timestamp', ts, ...
                'sequence', obj.Sequence);
        end
        function send(obj, line)
            obj.Calls(end+1) = "send"; obj.SentCommands(end+1) = string(line);
        end
        function vsaSend(obj, buffer)
            assert(all(isfinite(buffer)), 'fixture:Vsa', 'Non-finite VSA buffer.');
            obj.Calls(end+1) = "vsaSend"; obj.VsaFrames = obj.VsaFrames + 1;
        end
        function close(obj)
            obj.Calls(end+1) = "close"; obj.IsOpen = false; obj.CloseCount = obj.CloseCount + 1;
        end
    end
end
