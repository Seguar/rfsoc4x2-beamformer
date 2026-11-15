classdef FrameSource < handle
    % Owns one .NET TCP connection. No Instrument Control Toolbox required.
    properties (SetAccess=private)
        Metadata
        LastSequence=[]
    end
    properties (Access=private)
        Client
        Stream
        Config
        Counter=uint64(0)
    end
    methods
        function self=FrameSource(cfg)
            assert(strlength(cfg.host)>0,'rfsoc:Host','Supply an explicit private endpoint.');
            assert(any(cfg.profile==["demo-framed","legacy4x2"]), ...
                'rfsoc:Protocol','ZCU216 burst control is not a 4x2 protocol.');
            self.Config=cfg;
            self.Client=System.Net.Sockets.TcpClient();
            % GUI readiness checks need room for one complete framed capture.
            self.Client.ReceiveBufferSize=int32(max(1048576,cfg.frameSamples*16+24));
            try
                task=self.Client.ConnectAsync(char(cfg.host),int32(cfg.port));
                assert(task.Wait(int32(cfg.timeoutSeconds*1000)), ...
                    'rfsoc:Timeout','Connection deadline expired.');
                self.Stream=self.Client.GetStream();
                self.Stream.ReadTimeout=int32(cfg.timeoutSeconds*1000);
                self.Stream.WriteTimeout=int32(cfg.timeoutSeconds*1000);
                if cfg.profile=="demo-framed"
                    magic=self.readExact(8);
                    assert(isequal(magic,uint8([82 52 88 50 73 81 49 10])), ...
                        'rfsoc:Protocol','Wrong framed stream magic.');
                    sizeBytes=double(self.number(self.readExact(4),'uint32'));
                    assert(sizeBytes<=65536,'rfsoc:Protocol','Oversized metadata.');
                    self.Metadata=jsondecode(native2unicode(self.readExact(sizeBytes),'UTF-8'));
                    assert(string(self.Metadata.format)=="int16le-I-minus-jQ-4ch" && ...
                        self.Metadata.frame_bytes==cfg.frameSamples*16 && ...
                        self.Metadata.fs_hz==cfg.fsHz && self.Metadata.waveform_version==2, ...
                        'rfsoc:Protocol','Format, rate, size or reference version mismatch.');
                else
                    self.Metadata=struct('fs_hz',cfg.fsHz,'format',"legacy-unframed");
                    self.write(sprintf('dataChan %d#dataStream 1\n',cfg.frameSamples*8));
                end
            catch exception
                delete(self); rethrow(exception);
            end
        end
        function ready=isFrameReady(self)
            count=self.Config.frameSamples*16;
            if self.Config.profile=="demo-framed", count=count+24; end
            available=double(self.Client.Available);
            assert(~(available==0 && self.Client.Client.Poll(int32(0), ...
                System.Net.Sockets.SelectMode.SelectRead)), ...
                'rfsoc:Disconnected','Stream disconnected.');
            ready=available>=count;
        end
        function frame=next(self)
            frame=self.readFrame(); skipped=0; deadline=tic;
            if self.Config.latestOnly && self.Config.profile=="demo-framed"
                while double(self.Client.Available)>=24+self.Config.frameSamples*16
                    assert(skipped<128 && toc(deadline)<self.Config.timeoutSeconds, ...
                        'rfsoc:Freshness','Cannot drain queued display frames within deadline.');
                    frame=self.readFrame(); skipped=skipped+1;
                end
            end
            frame.skippedDisplayFrames=skipped;
        end
        function delete(self)
            if ~isempty(self.Stream), self.Stream.Close(); self.Stream=[]; end
            if ~isempty(self.Client), self.Client.Close(); self.Client=[]; end
            % This closes acquisition only. RF shutdown belongs to board owner.
            % Legacy firmware cannot acknowledge an in-stream stop command.
        end
    end
    methods (Access=private)
        function frame=readFrame(self)
            cfg=self.Config;
            sequence=self.Counter; timestamp=uint64(0);
            if cfg.profile=="demo-framed"
                header=self.readExact(24);
                assert(isequal(header(1:4),uint8('IQF1')), ...
                    'rfsoc:Protocol','Invalid frame marker.');
                sequence=self.number(header(5:12),'uint64');
                timestamp=self.number(header(13:20),'uint64');
                count=double(self.number(header(21:24),'uint32'));
                assert(count==cfg.frameSamples*16,'rfsoc:Protocol','Invalid frame size.');
                assert(isempty(self.LastSequence) || sequence>self.LastSequence, ...
                    'rfsoc:Freshness','Non-increasing sequence.');
            else
                count=cfg.frameSamples*16;
            end
            bytes=self.readExact(count);
            lanes=reshape(double(self.number(bytes,'int16')),8,[]).';
            frame=struct('samples',lanes(:,1:2:8)-1j*lanes(:,2:2:8), ...
                'sequence',sequence,'timestampNs',timestamp,'receivedUtc',datetime('now','TimeZone','UTC'));
            self.LastSequence=sequence; self.Counter=self.Counter+1;
        end
        function bytes=readExact(self,count)
            buffer=NET.createArray('System.Byte',count);
            offset=0; deadline=tic;
            while offset<count
                assert(toc(deadline)<self.Config.timeoutSeconds, ...
                    'rfsoc:Timeout','Incomplete frame before deadline.');
                self.Stream.ReadTimeout=int32(max(1,1000*(self.Config.timeoutSeconds-toc(deadline))));
                got=self.Stream.Read(buffer,int32(offset),int32(count-offset));
                assert(got>0,'rfsoc:Disconnected','Stream disconnected.');
                offset=offset+double(got);
            end
            bytes=uint8(buffer); bytes=bytes(:).';
        end
        function write(self,text)
            bytes=uint8(text); self.Stream.Write(bytes,int32(0),int32(numel(bytes)));
        end
    end
    methods (Static,Access=private)
        function value=number(bytes,type)
            value=typecast(uint8(bytes),type);
            [~,~,endian]=computer;
            if endian=='B', value=swapbytes(value); end
        end
    end
end
