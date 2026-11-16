classdef VsaSession < handle
    % Owned DirectDataSource/USR::Stream session; no Instrument Control Toolbox.
    properties (SetAccess=private)
        Config
        ConfigurationName
        IdleErrors = 0
    end
    properties
        IdleFcn = []   % optional: run by sendFrame while it waits (owner's display watchdog)
    end
    properties (Access=private)
        App = []
        Meas = []
        Input = []
        Closed = false
    end
    methods
        function obj = VsaSession(cfg)
            required={'dllPath','fsHz','fcHz','bandwidthHz','captureSamples','visible'};
            setx=isfield(cfg,'setupPath') && strlength(cfg.setupPath)>0;
            if setx
                required=[required,{'setupPath'}];
            else
                required=[required,{'customOfdmDllPath','typedHelperPath','referencePath'}];
            end
            for k=1:numel(required)
                assert(isfield(cfg,required{k}),'rfsoc:Config','Missing %s',required{k});
            end
            validateattributes(cfg.fsHz,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(cfg.fcHz,{'numeric'},{'scalar','real','finite'});
            validateattributes(cfg.bandwidthHz,{'numeric'},{'scalar','real','finite','positive','<=',cfg.fsHz});
            validateattributes(cfg.captureSamples,{'numeric'},{'scalar','integer','>',300});
            files={'dllPath'};
            if setx, files=[files,{'setupPath'}];
            else, files=[files,{'customOfdmDllPath','typedHelperPath','referencePath'}]; end
            for name=files
                assert(isfile(cfg.(name{1})),'rfsoc:Path','Missing %s',name{1});
            end
            if ~setx
                ref=rfsoc.loadReference(cfg.referencePath);
                assert(cfg.fsHz==125e6 && ref.fsHz==cfg.fsHz && ref.nfft==256 && ...
                    ref.cp==64 && ref.train==4 && isequal(size(ref.symbols),[12 48]), ...
                    'rfsoc:Reference','Typed VSA configuration requires the exact 125MHz v2 reference.');
            end
            if ~isfield(cfg,'startupTimeoutSeconds'), cfg.startupTimeoutSeconds=45; end
            if ~isfield(cfg,'measurementTimeoutSeconds'), cfg.measurementTimeoutSeconds=15; end
            if ~isfield(cfg,'maxInputSamples'), cfg.maxInputSamples=cfg.captureSamples; end
            validateattributes(cfg.maxInputSamples,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(cfg.startupTimeoutSeconds,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(cfg.measurementTimeoutSeconds,{'numeric'},{'scalar','positive','finite'});
            cfg.configurationMode="typed-v2"; if setx, cfg.configurationMode="setx"; end
            obj.Config=cfg; obj.ConfigurationName='DirectDataSource';
            applicationTitle=['MATLAB_' char(System.Guid.NewGuid().ToString('N'))];
            NET.addAssembly(cfg.dllPath);
            try
                if ~isfield(cfg,'startupPort'), cfg.startupPort=-1; end
                obj.App=Agilent.SA.Vsa.ApplicationFactory.Create(true,'','localhost', ...
                    int32(cfg.startupPort),int32(cfg.startupTimeoutSeconds),Agilent.SA.Vsa.CreateOptions.Use64Bit);
                assert(~isempty(obj.App),'rfsoc:StartupTimeout','New VSA instance did not start before timeout');
                obj.App.IsVisible=logical(cfg.visible); obj.App.Title=applicationTitle;
                obj.Meas=obj.App.Measurements.SelectedItem; obj.Meas.Pause();
                hw=obj.App.Hardware.Configurations.Item(obj.ConfigurationName);
                if isempty(hw)
                    hw=obj.App.Hardware.Configurations.Create(obj.ConfigurationName);
                    hw.Groups.Create('USR::Stream'); hw.Groups.ApplyChanges();
                end
                obj.Meas.SelectedAnalyzer=hw;
                obj.configureInput();
                if setx
                    % Repository order: DirectDataSource first, then SETX recall.
                    obj.App.RecallSetup(char(cfg.setupPath));
                    % Recall embeds an analyzer; never feed the pre-recall handle.
                    obj.Meas=obj.App.Measurements.SelectedItem; obj.Meas.Pause();
                    obj.configureInput();
                    assert(contains(lower(char(obj.Meas.MeasurementExtensionType.FullName)),'customofdm'), ...
                        'rfsoc:Setup','Selected SETX did not establish Custom OFDM.');
                else
                    NET.addAssembly(cfg.customOfdmDllPath); NET.addAssembly(cfg.typedHelperPath);
                    FinalValidation.FinalVsa.Restore(obj.Meas);
                    obj.Meas.Frequency.Center=double(cfg.fcHz); obj.Meas.Frequency.Span=double(cfg.bandwidthHz);
                    pre=ref.symbols(1:4,:).'; pilots=ref.symbols(5:12,ref.pilots).';
                    pack=@(x)single(reshape([real(x(:)).';imag(x(:)).'],[],1));
                    disp(char(FinalValidation.FinalVsa.Apply(obj.Meas,pack(pre),pack(pilots))));
                end
                obj.Meas.IsContinuous=false;
            catch exception
                delete(obj); rethrow(exception);
            end
        end
        function r=sendFrame(obj,x)
            t=tic;
            r=struct('evmPercent',NaN,'evmDb',NaN,'fresh',false,'status','unavailable','elapsedSeconds',0,'sentFloats',0,'requiredFloats',0,'quality',struct());
            assert(~obj.Closed,'rfsoc:Closed','Session is closed');
            iq=rfsoc.VsaSession.packFrame(x,obj.Config.maxInputSamples);
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
                    if ~isempty(obj.IdleFcn)
                        try obj.IdleFcn(); catch, obj.IdleErrors=obj.IdleErrors+1; end
                    end
                end
                if r.fresh
                    [r.evmPercent,r.evmDb,r.status,r.quality]=obj.readEvm();
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
        function setDisplayStatus(obj,text)
            % Owned-instance window annotation only (Application.Title of the
            % VSA this session created). Never attaches to another instance and
            % never writes measurement values into vendor traces.
            if obj.Closed || isempty(obj.App), return; end
            text=char(string(text));
            assert(numel(text)<=200,'rfsoc:DisplayStatus','Status text too long');
            obj.App.Title=text;
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
        function iq=packFrame(x,maxInputSamples)
            validateattributes(x,{'single','double'},{'vector','nonempty','finite'});
            assert(numel(x)<=maxInputSamples,'rfsoc:FrameSize','Frame exceeds maxInputSamples');
            iq=single(reshape([real(x(:)).';imag(x(:)).'],[],1));
            assert(all(isfinite(iq)),'rfsoc:FloatOverflow','Input overflows single precision');
        end
    end
    methods (Access=private)
        function configureInput(obj)
            cfg=obj.Config;
            obj.Meas.Input.DataFrom=Agilent.SA.Vsa.DataSource.Hardware;
            obj.Input=obj.Meas.SelectedAnalyzer.Groups.Item(0).UserInput;
            assert(~isempty(obj.Input) && obj.Input.Enabled,'rfsoc:DDC','DirectDataSource user input unavailable');
            obj.Input.ChannelCount=int32(1); setup=obj.Input.Setup;
            setup.IsImmediateChangesEnabled=false;
            setup.SetFrequencyParameters(true,double(cfg.fcHz),double(cfg.fsHz),double(cfg.bandwidthHz));
            capacity=cfg.captureSamples;
            if cfg.configurationMode=="typed-v2", capacity=max(8192,capacity); end
            setup.CaptureSizeMaximum=double(capacity); setup.IsContinuousCapable=true; setup.ApplyChanges();
            assert(double(setup.SampleRate)==cfg.fsHz && double(setup.CenterFrequency)==cfg.fcHz, ...
                'rfsoc:Source','DirectDataSource frequency readback differs from configured input.');
        end
        function [pct,db,status,quality]=readEvm(obj)
            threshold=0.5;
            if isfield(obj.Config,'syncCorrThreshold'), threshold=obj.Config.syncCorrThreshold; end
            allow32=obj.Config.configurationMode=="setx" && ...
                isfield(obj.Config,'allowSetxStatus32') && logical(obj.Config.allowSetxStatus32);
            [pct,db,status,quality]=rfsoc.readVsaEvm(obj.Meas,true,threshold,allow32);
        end
    end
end
