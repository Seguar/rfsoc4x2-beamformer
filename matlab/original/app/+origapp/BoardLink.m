classdef BoardLink < handle
    %BOARDLINK Find the board's session service and own one hardware session.
    % The service (board/session_service.py, installed once on the RFSoC4x2)
    % starts the capture helper when asked and stops it, with both DAC RAMs
    % zeroed and both outputs commanded off, when this connection closes.
    % Search order of find(): USB network address, last address that worked,
    % static Ethernet address, then a broadcast on every local network.
    properties (Constant)
        PORT = 4013
        USB = "192.168.3.1"          % PYNQ USB network address of the board
        ETHERNET = "192.168.2.99"    % PYNQ static Ethernet address
        SERVICE = "rfsoc4x2-beamformer"
        MAX_SECONDS = 14400
    end
    properties (SetAccess = private)
        Host = ""
        Port = 4013
        State = "idle"               % idle | ready | ended
        Ready = struct()             % the board's ready message
        Result = struct()            % the board's ended message
    end
    properties (Access = private)
        Client = []
        Stream = []
        Pending = zeros(1,0,'uint8')
    end
    methods
        function obj = BoardLink(address)
            [obj.Host,obj.Port] = origapp.BoardLink.parseAddress(address);
        end

        function ready = start(obj,maxSeconds,progressFcn)
            %START Ask the board to start a session and wait until it is ready.
            % progressFcn(message) is called about once a second with the
            % board's progress message; returning false cancels the start.
            if nargin<3 || isempty(progressFcn), progressFcn=@(~)true; end
            assert(obj.State=="idle" && isempty(obj.Client),'origapp:BoardConnect','This board link was already used.');
            assert(isnumeric(maxSeconds) && isscalar(maxSeconds) && maxSeconds>=1 && maxSeconds<=obj.MAX_SECONDS, ...
                'origapp:BoardConnect','Session length must be between 1 and %d seconds.',obj.MAX_SECONDS);
            obj.Client = origapp.BoardLink.connect(obj.Host,obj.Port,3);
            if isempty(obj.Client)
                error('origapp:BoardConnect','No answer from %s (port %d).',obj.Host,obj.Port);
            end
            obj.Stream = obj.Client.GetStream();
            obj.write(struct('op','start','max_seconds',round(maxSeconds)));
            started = tic;
            while true
                [line,closed] = obj.readLine(1);
                if closed
                    obj.close(); error('origapp:BoardConnect','The board closed the connection while starting.');
                end
                if strlength(line)==0
                    if toc(started)>240
                        obj.close(); error('origapp:BoardConnect','The board did not become ready within 240 s.');
                    end
                    message = struct('state','starting','step','waiting for the board','elapsed',round(toc(started)));
                else
                    message = jsondecode(char(line));
                end
                switch string(message.state)
                    case "ready"
                        obj.Ready = message; obj.State = "ready"; ready = message; return
                    case "error"
                        obj.close(); error('origapp:BoardConnect','%s',char(string(message.message)));
                    case "ended"
                        obj.close(); error('origapp:BoardConnect','The board ended the session before it was ready (%s).', ...
                            char(string(message.reason)));
                end
                if ~progressFcn(message)
                    obj.close(); error('origapp:BoardCancelled','Start cancelled.');
                end
            end
        end

        function result = finish(obj,timeoutSeconds)
            %FINISH Stop the session and wait for the board's shutdown report.
            if nargin<2, timeoutSeconds=150; end
            result = struct('state','unknown','reason','no shutdown report','dac_off_commanded',false);
            if isempty(obj.Client), return, end
            try
                obj.write(struct('op','stop'));
                started = tic;
                while toc(started)<timeoutSeconds
                    [line,closed] = obj.readLine(.5);
                    if strlength(line)>0
                        message = jsondecode(char(line));
                        if any(string(message.state)==["ended","error"])
                            if ~isfield(message,'dac_off_commanded'), message.dac_off_commanded=false; end
                            result = message; break
                        end
                    elseif closed
                        break
                    end
                end
            catch err
                result.reason = err.message;
            end
            obj.Result = result; obj.State = "ended";
            obj.close();
        end

        function close(obj)
            if ~isempty(obj.Client)
                try, obj.Client.Close(); catch, end
            end
            obj.Client = []; obj.Stream = [];
        end

        function delete(obj)
            obj.close();   % a closed session connection makes the board stop and switch the DACs off
        end
    end
    methods (Access = private)
        function write(obj,message)
            data = uint8(unicode2native([jsonencode(message) newline],'UTF-8'));
            obj.Stream.Write(data,0,numel(data));
        end

        function [line,closed] = readLine(obj,timeoutSeconds)
            [line,closed,obj.Pending] = origapp.BoardLink.readLineFrom(obj.Client,obj.Stream,obj.Pending,timeoutSeconds);
        end
    end
    methods (Static)
        function [host,port] = parseAddress(text)
            %PARSEADDRESS "address" or "address:port" (IPv4 address or host name).
            text = strtrim(string(text));
            assert(isscalar(text),'origapp:BoardAddress','One board address expected.');
            port = origapp.BoardLink.PORT;
            parts = split(text,":");
            if numel(parts)==2
                port = str2double(parts(2)); text = parts(1);
                assert(isfinite(port) && port==fix(port) && port>=1 && port<=65535,'origapp:BoardAddress','Invalid port.');
            end
            ok = numel(parts)<=2 && strlength(text)>0 && strlength(text)<=253 && ...
                ~isempty(regexp(char(text),'^[A-Za-z0-9]([A-Za-z0-9.\-]*[A-Za-z0-9])?$','once'));
            assert(ok,'origapp:BoardAddress','"%s" is not a board address. Use an IP address such as 192.168.2.99.',char(text));
            host = text;
        end

        function info = probe(address,timeoutSeconds)
            %PROBE Identity of the session service at an address, [] if none.
            if nargin<2, timeoutSeconds=.6; end
            info = [];
            try
                [host,port] = origapp.BoardLink.parseAddress(address);
                client = origapp.BoardLink.connect(host,port,timeoutSeconds);
                if isempty(client), return, end
                guard = onCleanup(@()client.Close());
                stream = client.GetStream();
                data = uint8(unicode2native(['{"op":"identify"}' newline],'UTF-8'));
                stream.Write(data,0,numel(data));
                line = origapp.BoardLink.readLineFrom(client,stream,zeros(1,0,'uint8'),max(1,timeoutSeconds));
                if strlength(line)==0, return, end
                reply = jsondecode(char(line));
                if isfield(reply,'service') && string(reply.service)==origapp.BoardLink.SERVICE && ...
                        isfield(reply,'board') && string(reply.board)=="RFSoC4x2"
                    info = reply;
                end
            catch
                info = [];
            end
        end

        function found = find(candidates)
            %FIND First address with a session service. candidates overrides the
            % default list (tests); each row is {label, address}.
            last = origapp.BoardLink.lastAddress();
            if nargin<1
                candidates = {'USB',origapp.BoardLink.USB};
                if strlength(last)>0, candidates(end+1,:) = {'last address',last}; end
                candidates(end+1,:) = {'Ethernet',origapp.BoardLink.ETHERNET};
                search = true;
            else
                search = false;
            end
            found = struct('host',"",'via',"",'info',[],'tried',strings(1,0),'hint',"");
            for k = 1:size(candidates,1)
                address = string(candidates{k,2});
                found.tried(end+1) = string(candidates{k,1})+" "+address;
                info = origapp.BoardLink.probe(address);
                if ~isempty(info)
                    found.host = address; found.via = string(candidates{k,1}); found.info = info; return
                end
            end
            if search
                found.tried(end+1) = "local network search";
                hosts = origapp.BoardLink.discover(.8);
                for address = hosts
                    info = origapp.BoardLink.probe(address);
                    if ~isempty(info)
                        found.host = address; found.via = "Ethernet"; found.info = info; return
                    end
                end
                % A board that answers on its USB address without the service
                % is the common first-time case: say what is missing.
                client = origapp.BoardLink.connect(origapp.BoardLink.USB,22,.4);
                if ~isempty(client)
                    client.Close();
                    found.hint = "A board answers on USB, but the beamformer service is not installed on it " + ...
                        "(one-time step: tools/install_board_service.py, see docs/BOARD_SERVICE.md).";
                end
            end
        end

        function hosts = discover(timeoutSeconds,port)
            %DISCOVER Broadcast on every local IPv4 network; addresses that answer.
            if nargin<2, port = origapp.BoardLink.PORT; end
            hosts = strings(1,0); sockets = {};
            question = uint8('rfsoc4x2-beamformer?');
            try
                interfaces = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                for i = 1:interfaces.Length
                    ni = interfaces(i);
                    if ni.OperationalStatus~=System.Net.NetworkInformation.OperationalStatus.Up, continue, end
                    ipSettings = ni.GetIPProperties();
                    addresses = ipSettings.UnicastAddresses;
                    for j = 0:addresses.Count-1
                        try
                            entry = addresses.Item(j);
                            if entry.Address.AddressFamily~=System.Net.Sockets.AddressFamily.InterNetwork, continue, end
                            a = uint8(entry.Address.GetAddressBytes()); m = uint8(entry.IPv4Mask.GetAddressBytes());
                            if a(1)==127 || all(m==255) || all(m==0), continue, end
                            b = bitor(a,bitcmp(m));
                            udp = System.Net.Sockets.UdpClient(System.Net.IPEndPoint(entry.Address,0));
                            udp.EnableBroadcast = true;
                            udp.Send(question,int32(numel(question)),sprintf('%d.%d.%d.%d',b),int32(port));
                            sockets{end+1} = udp; %#ok<AGROW>
                        catch
                        end
                    end
                end
                started = tic;
                while toc(started)<timeoutSeconds && ~isempty(sockets)
                    for k = 1:numel(sockets)
                        while sockets{k}.Available>0
                            task = sockets{k}.ReceiveAsync();
                            if ~task.Wait(int32(200)), break, end
                            r = task.Result;
                            reply = jsondecode(char(uint8(r.Buffer)));
                            if isfield(reply,'service') && string(reply.service)==origapp.BoardLink.SERVICE
                                hosts(end+1) = string(char(r.RemoteEndPoint.Address.ToString())); %#ok<AGROW>
                            end
                        end
                    end
                    pause(.05);
                end
            catch
            end
            for k = 1:numel(sockets)
                try, sockets{k}.Close(); catch, end
            end
            hosts = unique(hosts,'stable');
        end

        function address = lastAddress(new)
            %LASTADDRESS Read (or store) the last board address that worked.
            file = origapp.BoardLink.settingsFile();
            if nargin==1
                try
                    folder = fileparts(file);
                    if ~isfolder(folder), mkdir(folder); end
                    fid = fopen(file,'w');
                    if fid>=0, fprintf(fid,'%s\n',char(string(new))); fclose(fid); end
                catch
                end
                address = string(new); return
            end
            address = "";
            try
                if isfile(file)
                    text = strtrim(string(fileread(file)));
                    origapp.BoardLink.parseAddress(text);
                    address = text;
                end
            catch
                address = "";
            end
        end

        function file = settingsFile()
            file = getenv('RFSOC_BEAMFORMER_SETTINGS');
            if isempty(file)
                base = getenv('APPDATA');
                if isempty(base), base = tempdir; end
                file = fullfile(base,'RFSoCBeamformer','board.txt');
            end
        end
    end
    methods (Static, Access = private)
        function client = connect(host,port,timeoutSeconds)
            client = System.Net.Sockets.TcpClient();
            client.NoDelay = true;
            try
                task = client.ConnectAsync(char(host),int32(port));
                ok = task.Wait(int32(timeoutSeconds*1000)) && client.Connected;
            catch
                ok = false;
            end
            if ~ok
                try, client.Close(); catch, end
                client = [];
            end
        end

        function [line,closed,pending] = readLineFrom(client,stream,pending,timeoutSeconds)
            % One newline-terminated line, "" after the timeout. closed is true
            % when the peer closed the connection and nothing is left to read.
            line = ""; closed = false; started = tic;
            while true
                at = find(pending==10,1);
                if ~isempty(at)
                    line = string(native2unicode(pending(1:at-1),'UTF-8'));
                    pending = pending(at+1:end);
                    if strlength(strtrim(line))==0, line = ""; continue, end
                    return
                end
                try
                    if stream.DataAvailable
                        while stream.DataAvailable
                            v = stream.ReadByte();
                            if v<0, closed = true; return, end
                            pending(end+1) = uint8(v); %#ok<AGROW>
                            if v==10, break, end
                        end
                        continue
                    end
                    if client.Client.Poll(int32(0),System.Net.Sockets.SelectMode.SelectRead) && client.Client.Available==0
                        closed = true; return
                    end
                catch
                    closed = true; return
                end
                if toc(started)>=timeoutSeconds, return, end
                pause(.02);
            end
        end
    end
end
