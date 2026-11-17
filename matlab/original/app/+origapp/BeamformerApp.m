classdef BeamformerApp < handle
    % Focused frontend: one visible six-plot window, one headless DSP session.
    properties (SetAccess=private)
        Session = []
        View = []
        Controller = []
        AcqTimer = []
    end
    properties (Access=private)
        Busy = false
        Closed = false
        RenderKey = ""
    end
    methods
        function obj=BeamformerApp(cfg)
            try
                obj.Session=origapp.DemoSession(cfg);obj.Controller=obj.Session.Controller;
                cb=struct('start',@()obj.startAcquisition(),'pause',@(on)obj.pause(on), ...
                    'rf',@(rf)obj.rf(rf),'phase',@(r)obj.phase(r), ...
                    'dac',@(on)obj.dac(on),'sync',@(m)obj.sync(m),'configure',@(delta)obj.configure(delta), ...
                    'calibration',@()obj.calibration(),'zero',@()obj.zero(),'close',@()obj.close());
                if ~cfg.allowBoardCommands,cb=rmfield(cb,{'pause','rf','phase','dac','sync','zero'});end
                vc=obj.Session.Config;vc.ofdmProfile=obj.Session.Analyzer.Profile.summary;
                vc.availableChannels=obj.Controller.availableChannels();
                vc.rows=obj.Session.Rows;vc.rowsAllowed=obj.Session.rowsAllowed();
                vc.adcConnectors=obj.Session.AdcConnectors;vc.dacConnectors=obj.Session.DacConnectors;
                obj.View=origapp.BeamformerView(vc,cb);
                % Finish building the window now: its first draw takes seconds and
                % would otherwise age the first frame past the stale limit.
                drawnow
                obj.AcqTimer=timer('ExecutionMode','fixedSpacing','BusyMode','drop', ...
                    'Period',cfg.periodSeconds,'Name','RFSoC focused frontend', ...
                    'TimerFcn',@(~,~)obj.tick(),'ErrorFcn',@(~,e)obj.timerError(e));
                obj.Controller.setVsaIdle(@()obj.watchdog());
            catch err
                obj.close();rethrow(err)
            end
        end
        function startAcquisition(obj)
            obj.Session.start();
            % board path state and the settings it supports are known only now
            if ~isempty(obj.View) && isvalid(obj.View),obj.refreshControls();end
            if strcmp(obj.AcqTimer.Running,'off'),start(obj.AcqTimer);end
        end
        function tick(obj)
            if obj.Busy || obj.Closed,return,end
            obj.Busy=true;g=onCleanup(@()obj.unbusy()); %#ok<NASGU>
            zs=obj.Session.ZeroCal.state;
            obj.Session.step(@(s)obj.render(s));
            if obj.Session.ZeroCal.state~=zs,obj.refreshControls();end
            obj.render(obj.Session.snapshot());
            if ~obj.Controller.IsOpen && strcmp(obj.AcqTimer.Running,'on'),stop(obj.AcqTimer);end
        end
        function calibrateZero(obj)
            % "Set 0 deg" from a launcher option (same path as the button).
            obj.zero();
        end
        function setRows(obj,n)
            % Data amount (samples per frame) from a launcher option.
            obj.configure(struct('rows',n));
        end
        function watchdog(obj)
            if obj.Closed || isempty(obj.View),return,end
            s=obj.Session.snapshot();
            if ~s.valid,obj.View.show(s);end
        end
        function close(obj)
            if obj.Closed,return,end
            obj.Closed=true;
            if ~isempty(obj.AcqTimer) && isvalid(obj.AcqTimer),stop(obj.AcqTimer);delete(obj.AcqTimer);end
            if ~isempty(obj.Session) && isvalid(obj.Session),obj.Session.close();end
        end
        function delete(obj)
            obj.close();
            if ~isempty(obj.View) && isvalid(obj.View),delete(obj.View);end
            if ~isempty(obj.Session) && isvalid(obj.Session),delete(obj.Session);end
        end
    end
    methods (Access=private)
        function render(obj,s)
            if obj.Closed || isempty(obj.View) || ~isvalid(obj.View),return,end
            if s.valid
                key=string(s.sequence)+"|"+string(~isempty(s.vendor));
            else
                key="invalid|"+string(s.reason);
                if isfield(s,'health'),key=key+"|"+string(s.health.errors)+"|"+string(s.health.noSignal);end
            end
            if key~=obj.RenderKey
                obj.View.show(s);obj.RenderKey=key;
            elseif isfield(s,'health')
                obj.View.showHealth(s.health);
            end
        end
        function unbusy(obj)
            if isvalid(obj),obj.Busy=false;end
        end
        function calibration(obj)
            [f,d]=uigetfile('*.mat','Load steering, power or IQ calibration');
            if isequal(f,0),return,end
            obj.Session.loadCalibration(fullfile(d,f));obj.refreshControls();obj.render(obj.Session.snapshot());
        end
        function pause(obj,on)
            obj.Session.pause(on);obj.render(obj.Session.snapshot());
        end
        function dac(obj,on)
            obj.Session.setDac(on);obj.render(obj.Session.snapshot());
        end
        function sync(obj,mode)
            obj.Session.setSync(mode);obj.render(obj.Session.snapshot());
        end
        function zero(obj)
            obj.Session.calibrateZero();obj.refreshControls();obj.render(obj.Session.snapshot());
        end
        function rf(obj,value)
            obj.Session.applyRf(value);obj.refreshControls();obj.render(obj.Session.snapshot());
        end
        function phase(obj,value)
            obj.Session.applyPhase(value);obj.refreshControls();obj.render(obj.Session.snapshot());
        end
        function configure(obj,value)
            obj.Session.configure(value);obj.refreshControls();obj.render(obj.Session.snapshot());
        end
        function refreshControls(obj)
            c=obj.Session.Config;c.ofdmProfile=obj.Session.Analyzer.Profile.summary;
            c.availableChannels=obj.Controller.availableChannels();
            c.rows=obj.Session.Rows;c.rowsAllowed=obj.Session.rowsAllowed();
            c.paths=obj.Session.Paths;c.pathKinds=obj.Session.pathKinds();c.zeroCal=obj.Session.ZeroCal;
            obj.View.updateConfig(c);
        end
        function timerError(obj,event)
            reason="acquisition timer failed";
            if isprop(event,'Data') || isfield(event,'Data'),reason=string(event.Data.message);end
            obj.close();
            if ~isempty(obj.View) && isvalid(obj.View),obj.View.show(struct('valid',false,'reason',reason));end
        end
    end
end
