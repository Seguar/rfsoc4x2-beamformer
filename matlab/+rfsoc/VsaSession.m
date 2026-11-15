classdef VsaSession < handle
    % Owned single-channel VSA DDC session; no Instrument Control Toolbox.
    properties (SetAccess=private)
        Config
        ConfigurationName
    end
    properties (Access=private)
        App = []
        Meas = []
        Input = []
        Closed = false
    end
    methods
        function obj = VsaSession(cfg)
            required = {'dllPath','customOfdmDllPath','typedHelperPath','referencePath', ...
                'fsHz','fcHz','bandwidthHz','captureSamples','visible'};
            for k=1:numel(required)
                assert(isfield(cfg,required{k}), 'rfsoc:Config','Missing %s',required{k});
            end
            validateattributes(cfg.fsHz,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(cfg.fcHz,{'numeric'},{'scalar','real','finite'});
            validateattributes(cfg.bandwidthHz,{'numeric'},{'scalar','real','finite','positive','<=',cfg.fsHz});
            validateattributes(cfg.captureSamples,{'numeric'},{'scalar','integer','>',300});
            for name={'dllPath','customOfdmDllPath','typedHelperPath','referencePath'}
                assert(isfile(cfg.(name{1})),'rfsoc:Path','Missing %s',name{1});
            end
            ref=rfsoc.loadReference(cfg.referencePath);
            assert(cfg.fsHz==125e6 && ref.fsHz==cfg.fsHz && ref.nfft==256 && ...
                ref.cp==64 && ref.train==4 && isequal(size(ref.symbols),[12 48]), ...
                'rfsoc:Reference','Typed VSA configuration requires the exact 125MHz v2 reference.');
            if ~isfield(cfg,'startupTimeoutSeconds'), cfg.startupTimeoutSeconds=45; end
            if ~isfield(cfg,'measurementTimeoutSeconds'), cfg.measurementTimeoutSeconds=15; end
            validateattributes(cfg.startupTimeoutSeconds,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(cfg.measurementTimeoutSeconds,{'numeric'},{'scalar','positive','finite'});
            obj.Config=cfg;
            obj.ConfigurationName=['MATLAB_' char(System.Guid.NewGuid().ToString('N'))];
            NET.addAssembly(cfg.dllPath);
            try
                % true ALWAYS starts a new instance; never call attach-only Create().
                if ~isfield(cfg,'startupPort'), cfg.startupPort=-1; end
                obj.App=Agilent.SA.Vsa.ApplicationFactory.Create(true,'','localhost', ...
                    int32(cfg.startupPort),int32(cfg.startupTimeoutSeconds), ...
                    Agilent.SA.Vsa.CreateOptions.Use64Bit);
                assert(~isempty(obj.App),'rfsoc:StartupTimeout','New VSA instance did not start before timeout');
                obj.App.IsVisible=logical(cfg.visible);
                obj.App.Title=obj.ConfigurationName;
                obj.Meas=obj.App.Measurements.SelectedItem;
                obj.Meas.Pause();
                hw=obj.App.Hardware.Configurations.Create(obj.ConfigurationName);
                hw.Groups.Create('USR::Stream');
                hw.Groups.ApplyChanges();
                obj.Meas.SelectedAnalyzer=hw;
                NET.addAssembly(cfg.customOfdmDllPath);
                NET.addAssembly(cfg.typedHelperPath);
                FinalValidation.FinalVsa.Restore(obj.Meas);
                obj.Meas.Input.DataFrom=Agilent.SA.Vsa.DataSource.Hardware;
                assert(obj.Meas.Input.DataFrom==Agilent.SA.Vsa.DataSource.Hardware, ...
                    'rfsoc:Source','Hardware source readback failed');
                obj.Input=obj.Meas.SelectedAnalyzer.Groups.Item(0).UserInput;
                assert(~isempty(obj.Input) && obj.Input.Enabled,'rfsoc:DDC','USR::Stream unavailable (license/configuration)');
                obj.Input.ChannelCount=int32(1);
                s=obj.Input.Setup;
                s.IsImmediateChangesEnabled=false;
                s.SetFrequencyParameters(true,double(cfg.fcHz),double(cfg.fsHz),double(cfg.bandwidthHz));
                % Capacity is not a promise to supply this many input samples.
                s.CaptureSizeMaximum=max(8192,double(cfg.captureSamples));
                s.IsContinuousCapable=true;
                s.ApplyChanges();
                obj.Meas.Frequency.Center=double(cfg.fcHz);
                obj.Meas.Frequency.Span=double(cfg.bandwidthHz);
                obj.Meas.IsContinuous=false;
                pre=ref.symbols(1:4,:).'; pilots=ref.symbols(5:12,ref.pilots).';
                pack=@(x)single(reshape([real(x(:)).';imag(x(:)).'],[],1));
                % Analyzer/rate/span changes precede the final typed OFDM setup.
                disp(char(FinalValidation.FinalVsa.Apply(obj.Meas,pack(pre),pack(pilots))));
            catch er
                delete(obj); rethrow(er);
            end
        end
        function r=sendFrame(obj,x)
            t=tic;
            r=struct('evmPercent',NaN,'evmDb',NaN,'fresh',false,'status','unavailable','elapsedSeconds',0,'sentFloats',0,'requiredFloats',0);
            assert(~obj.Closed,'rfsoc:Closed','Session is closed');
            iq=rfsoc.VsaSession.packFrame(x,obj.Config.captureSamples);
            try
                obj.Meas.Pause();
                obj.Input.Data.ClearData();
                obj.Meas.Restart();
                offset=0; observedPending=false;
                while toc(t)<obj.Config.measurementTimeoutSeconds
                    done=logical(obj.Meas.IsMeasurementDone);
                    observedPending=observedPending || ~done;
                    if done && observedPending && offset>0
                        r.fresh=true; break
                    end
                    n=double(obj.Input.Data.RequiredSamples);
                    r.requiredFloats=n;
                    if n>0
                        take=min(2*ceil(n/2),numel(iq)-offset);
                        if take<=0
                            r.status='insufficient frame: measurement requests more floats; no repetition or padding'; break
                        end
                        obj.Input.Data.Channels.Item(0).SendData(iq(offset+(1:take)));
                        offset=offset+take; r.sentFloats=offset;
                    end
                    pause(0.01);
                end
                if r.fresh
                    [r.evmPercent,r.evmDb,r.status]=obj.readEvm();
                elseif strcmp(r.status,'unavailable')
                    r.status='measurement timeout or no observed pending-to-done transition';
                end
                obj.Meas.Pause();
            catch er
                r.fresh=false; r.status=['VSA error: ' er.message];
                try obj.Meas.Pause(); catch, end
            end
            r.elapsedSeconds=toc(t);
        end
        function delete(obj)
            if obj.Closed, return; end
            obj.Closed=true;
            if ~isempty(obj.App)
                try obj.Meas.Pause(); catch, end
                try obj.App.Quit(); catch, end
                try obj.App.Dispose(); catch, end
            end
            obj.Input=[]; obj.Meas=[]; obj.App=[];
        end
    end
    methods (Static)
        function iq=packFrame(x,captureSamples)
            validateattributes(x,{'single','double'},{'vector','nonempty','finite'});
            assert(numel(x)<=captureSamples,'rfsoc:FrameSize','Frame exceeds captureSamples');
            iq=single(reshape([real(x(:)).';imag(x(:)).'],[],1));
            assert(all(isfinite(iq)),'rfsoc:FloatOverflow','Input overflows single precision');
        end
    end
    methods (Access=private)
        function [pct,db,status]=readEvm(obj)
            threshold=0.5;
            if isfield(obj.Config,'syncCorrThreshold'), threshold=obj.Config.syncCorrThreshold; end
            [pct,db,status]=rfsoc.readVsaEvm(obj.Meas,true,threshold);
        end
    end
end
