classdef BoardControl < handle
    % Separate JSON-line command connection; ACK means applied, not queued.
    properties (SetAccess=private)
        Revision = 0
        LastReply = struct()
    end
    properties (Access=private)
        Client = []
        Stream = []
        Id = 0
    end
    methods
        function obj=BoardControl(host,port,timeoutSeconds)
            assert(isnumeric(timeoutSeconds) && isscalar(timeoutSeconds) && isfinite(timeoutSeconds) && ...
                timeoutSeconds>0 && timeoutSeconds<=30,'origapp:Control','Control timeout must be in (0,30] seconds.');
            assert(isnumeric(port) && isscalar(port) && isfinite(port) && port==fix(port) && ...
                port>=1024 && port<=65535,'origapp:Control','Invalid control port.');
            obj.Client=System.Net.Sockets.TcpClient();
            obj.Client.SendTimeout=int32(timeoutSeconds*1000);
            obj.Client.ReceiveTimeout=int32(timeoutSeconds*1000);
            t=obj.Client.ConnectAsync(char(host),int32(port));
            if ~t.Wait(int32(timeoutSeconds*1000))
                obj.close(); error('origapp:ControlTimeout','Board control connection timed out.');
            end
            obj.Stream=obj.Client.GetStream();
        end
        function reply=send(obj,line)
            assert(~isempty(obj.Stream),'origapp:Control','Control connection is closed.');
            obj.Id=obj.Id+1;
            data=unicode2native([jsonencode(struct('id',obj.Id,'command',char(line))) newline],'UTF-8');
            obj.Stream.Write(uint8(data),0,numel(data));
            bytes=zeros(16384,1,'uint8'); n=0;
            try
                while true
                    v=obj.Stream.ReadByte();
                    assert(v>=0,'origapp:Control','Board control disconnected.');
                    if v==10, break,end
                    n=n+1; assert(n<=numel(bytes),'origapp:Control','Oversized board acknowledgement.');
                    bytes(n)=uint8(v);
                end
                reply=jsondecode(native2unicode(bytes(1:n).','UTF-8'));
                assert(isfield(reply,'id') && reply.id==obj.Id && isfield(reply,'ok'), ...
                    'origapp:Control','Wrong command acknowledgement.');
            catch err
                obj.close();
                error('origapp:ControlUncertain','No reliable acknowledgement; stop and reconnect: %s',err.message);
            end
            if ~reply.ok
                error('origapp:CommandRejected','Board rejected command: %s',string(reply.error.message));
            end
            assert(isfield(reply,'result') && isfield(reply.result,'revision') && ...
                isscalar(reply.result.revision) && isfinite(reply.result.revision) && ...
                reply.result.revision>=obj.Revision && reply.result.revision==fix(reply.result.revision), ...
                'origapp:Control','Invalid applied revision.');
            obj.Revision=reply.result.revision; obj.LastReply=reply;
        end
        function close(obj)
            if ~isempty(obj.Client), obj.Client.Close();end
            obj.Stream=[]; obj.Client=[];
        end
        function delete(obj), obj.close();end
    end
end
