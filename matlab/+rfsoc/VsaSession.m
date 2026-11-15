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
            required = {'dllPath','setupPath','fsHz','fcHz','bandwidthHz','captureSamples','visible'};
            for k=1:numel(required)
                assert(isfield(cfg,required{k}), 'rfsoc:Config','Missing %s',required{k});
            end
            validateattributes(cfg.fsHz,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(cfg.fcHz,{'numeric'},{'scalar','real','finite'});
            validateattributes(cfg.bandwidthHz,{'numeric'},{'scalar','real','finite','positive','<=',cfg.fsHz});
            validateattributes(cfg.captureSamples,{'numeric'},{'scalar','integer','>',300});
            assert(isfile(cfg.dllPath) && isfile(cfg.setupPath),'rfsoc:Path','DLL/setup file missing');
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
                obj.App.RecallSetup(char(cfg.setupPath));
                obj.Meas=obj.App.Measurements.SelectedItem;
                obj.Meas.Pause();
                hw=obj.App.Hardware.Configurations.Create(obj.ConfigurationName);
                hw.Groups.Create('USR::Stream');
                hw.Groups.ApplyChanges();
                obj.Meas.SelectedAnalyzer=hw;
                obj.Input=obj.Meas.SelectedAnalyzer.Groups.Item(0).UserInput;
                assert(~isempty(obj.Input) && obj.Input.Enabled,'rfsoc:DDC','USR::Stream unavailable (license/configuration)');
                obj.Input.ChannelCount=int32(1);
                s=obj.Input.Setup;
                s.IsImmediateChangesEnabled=false;
                s.SetFrequencyParameters(true,double(cfg.fcHz),double(cfg.fsHz),double(cfg.bandwidthHz));
                s.CaptureSizeMaximum=double(cfg.captureSamples);
                s.IsContinuousCapable=true;
                s.ApplyChanges();
                obj.Meas.Frequency.Center=double(cfg.fcHz);
                obj.Meas.Frequency.Span=double(cfg.bandwidthHz);
                obj.Meas.IsContinuous=false;
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
            pct=NaN; db=NaN; status='EVM unavailable: no valid scalar RMS EVM summary with percent/dB units';
            traces=obj.App.Display.Traces;
            for k=0:double(traces.Count)-1

                try
                    d=obj.Meas.MeasurementData(char(traces.Item(k).DataName));
                    if isempty(d), continue; end
                    guard=onCleanup(@()d.Dispose());
                    if int32(d.Status)~=0
                        status=['EVM unavailable: trace status ' char(d.Status.ToString())];
                        clear guard; continue
                    end
                    names=d.SummaryNames;
                    for j=1:names.Length
                        key=char(names(j));
                        if isempty(regexpi(key,'^(rms\s*evm|evm\s*rms|evm|Ch1EVM)$','once')), continue; end
                        v=d.Summary(key); u=strtrim(char(d.SummaryUnit(key)));
                        if isempty(v) || v.Length~=1, continue; end
                        value=System.Convert.ToDouble(v.GetValue(int32(0)));
                        if ~isfinite(value), continue; end
                        if strcmp(u,'%') && value>=0, pct=double(value); end
                        if strcmpi(u,'dB'), db=double(value); end
                    end
                    clear guard
                catch er
                    status=['EVM unavailable: ' er.message];
                end
            end
            if isfinite(pct) && isnan(db), db=20*log10(pct/100); end
            if isfinite(db) && isnan(pct), pct=100*10^(db/20); end
            if isfinite(pct) || isfinite(db), status='completed; RMS EVM read from VSA summary'; end
        end
    end
end
