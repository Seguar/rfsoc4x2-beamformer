classdef DemoSession < handle
    % Headless session shared by the focused six-plot GUI. No hidden legacy UI.
    % Acquisition, integrity checks, beamformers and OFDM math are existing core.
    properties (SetAccess=private)
        Config
        Controller
        Analyzer = []
        Last = struct('valid',false,'reason',"idle")
        Status = "idle"
        Paused = false
        IqFilter = []
        Rows = NaN              % samples per frame handed to the DSP (data amount)
        FullRows = NaN          % frame size of the stream at its full amount
        BoardRows = false       % true: the board sends Rows; false: cropped here
    end
    properties (Access=private)
        Params
        PatternAverage = []
        SpectrumAverage = []
        Closed = false
    end
    methods
        function obj=DemoSession(cfg)
            obj.Config=origapp.resolveConfig(cfg);
            obj.Config.cutter=0;obj.Config.c1=0;obj.Config.c2=0;obj.Config.coupComp=false;
            % A compiled application already contains every dependency.
            if ~isdeployed && strlength(string(obj.Config.reviewedPath))>0,addpath(obj.Config.reviewedPath);end
            if string(obj.Config.bfEngine)=="reviewed"
                rc=obj.Config.reviewed;if isempty(fieldnames(rc)),rc=rfsoc.defaultConfig();end
                obj.Config.reviewed=rc;
                obj.Config.diag=rc.loading;obj.Config.gamma=rc.gamma;obj.Config.alpha=rc.uncertainty;
                obj.Config.iter=rc.maxIterations;obj.Config.mis_ang=rc.mismatchDeg;obj.Config.alg_scan_res=rc.scanStepDeg;
            end
            cfg=obj.Config;
            if ~isdeployed && strlength(string(cfg.originalRepoPath))>0
                addpath(fullfile(cfg.originalRepoPath,'Functions'));
            end
            if ~isdeployed && strlength(string(cfg.reviewedPath))>0,addpath(cfg.reviewedPath);end
            % Integrated metrics define the plotted constellation/EVM. Vendor
            % measurements are an optional separately labelled comparison.
            if string(obj.Config.analyzer)=="vsa",obj.Config.analyzer="both";end
            obj.Controller=origapp.Controller(obj.Config);
            obj.Analyzer=origapp.OfdmAnalyzer(obj.Config.ofdm,obj.Config.vsaSetupFile,obj.Config.fsRfsoc);
            obj.IqFilter=zeros(cfg.sizeL,4);
            obj.Params=obj.parameters(obj.Config);obj.resetAverage();
            obj.FullRows=obj.Config.dataChan;obj.Rows=obj.FullRows;
        end
        function r=rowsAllowed(obj)
            % Data amounts offered: the 32768-row window may be reduced to
            % 16384, 8192 or 4096 rows (4096 hold one complete OFDM frame).
            r=obj.FullRows;
            if r==32768 && ~obj.Config.directOnly,r=[4096 8192 16384 32768];end
        end
        function start(obj)
            assert(~obj.Closed,'origapp:Closed','Session is closed.');
            obj.Controller.open();
            if obj.Paused,obj.pause(false);end
            if obj.Rows~=obj.FullRows,obj.applyRows(obj.Rows);end
            obj.Status="acquiring";
        end
        function pause(obj,on)
            obj.command(sprintf('dataStream %d',~on));
            obj.Paused=logical(on);
            if on,obj.invalidate("paused");else,obj.invalidate("resuming");end
        end
        function applyRf(obj,rf)
            % rf: adcMHz, dacMHz (DAC B, index 0) and optionally dac1MHz (DAC A,
            % index 2), adcEven / d0Even / d1Even (even Nyquist zone) and
            % adcMirror (negative ADC mixer frequency), as the original System tab.
            c=obj.Config;
            d=struct('dac1MHz',rf.dacMHz,'adcEven',c.nyquistZone==2,'adcMirror',c.adcMirror<0, ...
                'd0Even',c.nyquistZone_d0==2,'d1Even',c.nyquistZone_d1==2);
            for n=string(fieldnames(d)).',if ~isfield(rf,n),rf.(n)=d.(n);end,end
            f=[rf.adcMHz rf.dacMHz rf.dac1MHz];
            assert(all(isfinite(f)) && all(f>=0) && all(f<=6000) && all(f==fix(f)), ...
                'origapp:Control','Use integer MHz in [0,6000].');
            next=obj.uncalibrated(obj.Config);
            next.fc=rf.adcMHz*1e6;next.fc_d0=rf.dacMHz*1e6;next.fc_d1=rf.dac1MHz*1e6;
            next.nyquistZone=1+logical(rf.adcEven);next.nyquistZone_d0=1+logical(rf.d0Even);
            next.nyquistZone_d1=1+logical(rf.d1Even);next.adcMirror=1-2*logical(rf.adcMirror);
            p=obj.parameters(next);  % validate DSP before touching RF hardware
            obj.command(sprintf('fc %d/%d/%d/%d/%d/%d', ...
                rf.adcMHz*next.adcMirror,next.nyquistZone,rf.dacMHz,next.nyquistZone_d0,rf.dac1MHz,next.nyquistZone_d1));
            obj.Config=next;obj.Params=p;obj.IqFilter=zeros(next.sizeL,4);
            obj.invalidate("RF settings applied; calibration cleared");
        end
        function applyPhase(obj,request)
            v=request.values;
            assert(isnumeric(v) && numel(v)==4 && all(isfinite(v)) && all(v==fix(v)) && ...
                all(abs(v)<=360000),'origapp:Control','Four integer phases required.');
            kind=string(request.kind);assert(any(kind==["ADC","DAC"]),'origapp:Control','Unknown phase bank.');
            name='phase';if kind=="DAC",name='dphase';end
            next=obj.uncalibrated(obj.Config);p=obj.parameters(next);
            obj.command([name ' ' char(strjoin(string(v),'/'))]);
            obj.Config=next;obj.Params=p;obj.IqFilter=zeros(next.sizeL,4);
            obj.invalidate("phase applied; calibration cleared");
        end
        function setDac(obj,on)
            % on: logical scalar (the session's selected DAC, DAC_B by default)
            % or [DAC_B DAC_A] (original "Power" boxes; both play the same
            % waveform and add in the combiner).
            mask=zeros(1,4);
            if isscalar(on)
                selected=find(obj.Config.dacPow,1);if isempty(selected),selected=1;end
                if on,mask(selected)=1;end
            else
                assert(numel(on)==2,'origapp:Control','DAC power needs [DAC_B DAC_A].');
                mask([1 3])=double(logical(on));
            end
            obj.command(['dacPow ' char(strjoin(string(mask),'/'))]);
            % A scalar OFF keeps the selection so a later ON restores the same port.
            if ~isscalar(on),obj.Config.dacPow=mask;end
            obj.invalidate("DAC waveform command applied");
        end
        function setSync(obj,mode)
            % Original SYNC list: 2 DACs start with each ADC capture, 1 DACs
            % start together and play continuously, 0 no common start.
            assert(isscalar(mode) && any(mode==[0 1 2]),'origapp:Control','SYNC mode must be 0, 1 or 2.');
            obj.command(sprintf('da %d',mode));
            obj.Config.da=mode;
            obj.invalidate("SYNC mode applied");
        end
        function configure(obj,delta)
            allowed=["ch","bf","doa","num","ang_num","scan_bw","scan_res","avg_factor","diag", ...
                "alpha","gamma","iter","mis_ang","alg_scan_res","bw","adIQcomp","IQcomp","sizeL", ...
                "stepMU","phComp","analyzer"];
            if isfield(delta,'rows')
                n=delta.rows;delta=rmfield(delta,'rows');
                assert(isnumeric(n) && isscalar(n) && any(n==obj.rowsAllowed()),'origapp:Config', ...
                    'Data amount must be one of %s samples.',mat2str(obj.rowsAllowed()));
                assert(n==obj.FullRows || string(obj.Config.analyzer)=="integrated",'origapp:Config', ...
                    'The native VSA comparison needs the full frame; switch it off first.');
                if obj.Controller.IsOpen,obj.applyRows(n);end
                obj.Rows=n;
                if isempty(fieldnames(delta))
                    obj.invalidate("data amount changed; awaiting a fresh frame");return
                end
            end
            names=string(fieldnames(delta));assert(all(ismember(names,allowed)),'origapp:Config','Unsupported DSP option.');
            next=obj.Config;
            for n=names.',next.(n)=delta.(n);end
            next=origapp.resolveConfig(next);
            assert(any(string(next.bf)==["Without","Steering","MVDR","DMR","PC","PC_corr","LCMV", ...
                "RVL","RAB PC","DL MVDR","DL ITER MVDR","QCB"]),'origapp:Config','Unknown beamformer.');
            assert(~next.IQcomp || next.sizeL==obj.Config.sizeL,'origapp:Calibration', ...
                'Disable static IQ before changing filter length; learn the new filter first.');
            assert(any(next.ang_num==[1 2]) && next.ang_num<=next.num,'origapp:Config', ...
                'Weaker-source priority requires at least two detected sources.');
            assert(next.diag>=0 && next.gamma>=0 && next.alpha>=0 && next.alg_scan_res>0 && ...
                next.iter>=1 && next.iter==fix(next.iter),'origapp:Config','Invalid algorithm parameters.');
            if string(next.bf)=="QCB"
                assert(next.gamma>0 && next.mis_ang>0,'origapp:Config','QCB needs positive loading and mismatch width.');
            elseif string(next.bf)=="DL ITER MVDR"
                assert(next.alpha>0 && next.alpha<2,'origapp:Config','Iterative MVDR needs uncertainty in (0,2).');
            end
            assert(next.avg_factor>=1 && next.avg_factor<=300 && next.avg_factor==fix(next.avg_factor), ...
                'origapp:Config','Average count must be 1..300.');
            assert(next.scan_bw>0 && next.scan_bw<=180 && next.scan_res>0 && next.scan_res<=next.scan_bw, ...
                'origapp:Config','Invalid scan span/resolution.');
            assert(next.bw>0 && next.bw<=next.fsRfsoc,'origapp:Config','Bandwidth must fit the receive sample rate.');
            assert(string(next.analyzer)=="integrated" || obj.Rows==obj.FullRows,'origapp:Config', ...
                'The native VSA comparison needs the full frame; set the data amount to full first.');
            m=obj.Controller.availableChannels();
            assert(isscalar(next.ch) && next.ch==fix(next.ch) && next.ch>=1 && next.ch<=5 && ...
                ((next.ch<=4 && m(next.ch)) || (next.ch==5 && ~next.directOnly && all(m))), ...
                'origapp:Channels','Output is not measured by this session.');
            if next.IQcomp && ~any(obj.IqFilter,'all')
                error('origapp:Calibration','Static IQ compensation needs a learned filter; enable adaptive IQ first.');
            end
            if next.phComp
                assert(~isempty(next.calibration.steeringCorrection) && ~isempty(next.calibration.powCalibration), ...
                    'origapp:Calibration','Phase/power compensation needs loaded calibration tables.');
            end
            p=obj.parameters(next);
            if next.sizeL~=obj.Config.sizeL,obj.IqFilter=zeros(next.sizeL,4);end
            obj.Config=next;obj.Params=p;obj.resetAverage();
            obj.invalidate("DSP settings applied; awaiting a fresh frame");
        end
        function loadCalibration(obj,file)
            s=load(file);next=obj.Config; found=false;
            if isfield(s,'steering_correction'),next.calibration.steeringCorrection=s.steering_correction;found=true;end
            if isfield(s,'pow_claibration_intrp'),next.calibration.powCalibration=s.pow_claibration_intrp;found=true;end
            if isfield(s,'iqFilter')
                assert(isnumeric(s.iqFilter) && isequal(size(s.iqFilter),size(obj.IqFilter)) && ...
                    all(isfinite(s.iqFilter),'all'),'origapp:Calibration','Invalid IQ filter shape.');
            end
            assert(found || isfield(s,'iqFilter'),'origapp:Calibration','No supported calibration table in this file.');
            g=numel(obj.Params.scan_axis);
            for name=["powCalibration","steeringCorrection"]
                v=next.calibration.(name);
                assert(isempty(v) || (isnumeric(v) && isequal(size(v),[g 4]) && all(isfinite(v),'all')), ...
                    'origapp:Calibration','Calibration must match the current scan grid, %d-by-4.',g);
            end
            assert(isempty(next.calibration.powCalibration) || all(next.calibration.powCalibration>0,'all'), ...
                'origapp:Calibration','Power calibration must be positive.');
            p=obj.parameters(next);obj.Config=next;obj.Params=p;
            if isfield(s,'iqFilter'),obj.IqFilter=s.iqFilter;end
            obj.invalidate("model calibration loaded; awaiting fresh data");
        end
        function step(obj,render)
            if nargin<2,render=[];end
            if obj.Closed || ~obj.Controller.IsOpen || obj.Paused,return,end
            try
                [frame,state]=obj.Controller.acquire();
                if isempty(frame)
                    if state=="stale",obj.invalidate("no fresh frame");end
                    return
                end
                if size(frame.samples,1)>obj.Rows
                    frame.samples=origapp.DemoSession.cropFrame(frame.samples,obj.Rows);
                end
                if obj.Config.directOnly
                    buffer=frame.samples(:,obj.Config.ch)/2^16;
                    out=[]; angles=[];ds=[];pat=[];weights=[];
                else
                    p=obj.Params;p.iqFilter=obj.IqFilter;
                    out=origapp.processLegacyFrame(frame.samples,p);
                    assert(all(isfinite(out.weights)),'origapp:NoSignal','No finite beamforming weights.');
                    obj.IqFilter=out.iqFilter;buffer=out.vsaBuffer;angles=out.estimated_angle;weights=out.weights;
                    if out.spectrumAvailable
                        [ds,obj.SpectrumAverage]=avgData(out.yspec(:),obj.SpectrumAverage);
                        ds=ds/max(ds);
                    else,ds=[];end
                    power=beamPatternCalc(conj(out.weights),obj.Config.fc,p.scan_axis,4);
                    [power,obj.PatternAverage]=avgData(power,obj.PatternAverage);
                    pat=20*log10(max(power,realmin));pat=pat-max(pat);
                end
                kind="combined";if obj.Config.ch<=4,kind="weighted-channel";end
                if obj.Config.directOnly,kind="raw-column";end
                r=obj.Analyzer.analyze(buffer,struct('sequence',frame.sequence,'timestamp',frame.timestamp,'kind',kind));
                displaySamples=buffer;if string(obj.Config.ofdm.orientation)=="IplusjQ",displaySamples=conj(buffer);end
                obj.Last=struct('valid',true,'reason',"",'sequence',frame.sequence,'timestamp',frame.timestamp, ...
                    'age',origapp.Controller.nowSeconds()-frame.timestamp,'scope',string(obj.Config.arrayLabel)+", UNCALIBRATED", ...
                    'scan',obj.Params.scan_axis,'doaSpectrum',ds,'patternDb',pat,'angles',angles, ...
                    'samples',displaySamples,'weights',weights,'analysis',r,'spectrum',r.spectrum,'vendor',[], ...
                    'fsHz',obj.Config.fsRfsoc,'directOnly',obj.Config.directOnly, ...
                    'channels',origapp.DemoSession.channelDiagnostics(frame));
                if obj.Config.phComp,obj.Last.scope=string(obj.Config.arrayLabel)+", MODEL CALIBRATION";end
                obj.Status="acquiring";
                if ~isempty(render),render(obj.snapshot());end
                if any(string(obj.Config.analyzer)==["vsa","both"])
                    weights=[];if ~isempty(out),weights=out.weights;end
                    info=struct('kind',kind,'sequence',frame.sequence,'channel',obj.Config.ch,'weights',weights);
                    obj.Controller.sendVsa(buffer,info);obj.Last.vendor=obj.Controller.vsaStatus();
                end
                assert(origapp.Controller.nowSeconds()-frame.timestamp<=obj.Config.staleSeconds, ...
                    'origapp:Expired','Frame expired during processing.');
                obj.Controller.recordSuccess();
            catch err
                obj.invalidate(string(err.message));
                if obj.Controller.recordFailure(err),obj.close();obj.invalidate("stopped: "+string(err.message));end
            end
        end
        function s=snapshot(obj)
            s=obj.Last;
            if s.valid
                s.age=origapp.Controller.nowSeconds()-s.timestamp;
                if s.age>obj.Config.staleSeconds
                    obj.invalidate("stale acquisition");s=obj.Last;
                end
            end
            % Acquisition counters already held by the controller (no IO).
            c=obj.Controller;
            s.health=struct('accepted',c.FramesAccepted,'boundary',c.BoundaryFrames, ...
                'noSignal',c.NoSignalFrames,'expired',c.ExpiredFrames,'errors',c.TotalErrors, ...
                'lastError',string(c.LastError));
        end
        function close(obj)
            if obj.Closed,return,end
            obj.Closed=true;
            if ~isempty(obj.Controller),obj.Controller.close();end
            obj.invalidate("stopped");
        end
        function delete(obj),obj.close();end
    end
    methods (Static)
        function y=cropFrame(x,n)
            % Host-side data amount (simulation, or a board service that sends
            % only full frames): n contiguous rows of the frame, starting 256
            % rows before the first burst that follows a quiet gap, so the
            % rows hold a complete OFDM frame. No sample is changed.
            p=sum(abs(x).^2,2);N=numel(p);
            s=movmean(p,[63 0]);on=s>0.1*max(s);
            quiet=movmax(double(on),[255 0])==0;
            e=find(on(2:end) & quiet(1:end-1))+1;
            e=e(e>256 & e-256+n-1<=N);
            start=1;if ~isempty(e),start=e(1)-256;end
            y=x(start:start+n-1,:);
        end
        function d=channelDiagnostics(frame)
            % Display-only per-stream readouts of the admitted raw capture:
            % mean/peak level against the int16 converter word and the phase /
            % coherence of each stream against the first measured one. These
            % describe the conducted cabling, not arrival angles.
            x=double(frame.samples);n=size(x,2);
            mask=true(1,n);
            if isfield(frame,'availableChannels'),mask=reshape(logical(frame.availableChannels),1,[]);end
            mask=mask(1:min(n,numel(mask)));mask(end+1:n)=false;
            d=struct('available',mask,'levelDbfs',nan(1,n),'peakDbfs',nan(1,n), ...
                'clipCount',zeros(1,n), ...
                'relPhaseDeg',nan(1,n),'coherence',nan(1,n),'reference',NaN);
            r=find(mask,1);if isempty(r) || isempty(x),return,end
            d.reference=r;fs=32767;pr=sum(abs(x(:,r)).^2);
            for k=find(mask)
                pk=sum(abs(x(:,k)).^2);
                d.levelDbfs(k)=10*log10(pk/size(x,1)/fs^2+realmin);
                d.peakDbfs(k)=20*log10(max(max(abs(real(x(:,k)))),max(abs(imag(x(:,k)))))/fs+realmin);
                d.clipCount(k)=sum(abs(real(x(:,k)))>=32760 | abs(imag(x(:,k)))>=32760);
                c=x(:,r)'*x(:,k);
                if pr>0 && pk>0
                    d.relPhaseDeg(k)=angle(c)*180/pi;d.coherence(k)=abs(c)/sqrt(pr*pk);
                end
            end
        end
    end
    methods (Access=private)
        function applyRows(obj,n)
            % The board sends the reduced window when its stream declares the
            % dataChan command; otherwise full frames are cropped in step().
            caps=obj.Controller.capabilities();
            if obj.Config.allowBoardCommands && any(caps.commands=="dataChan")
                obj.command(sprintf('dataChan %d',8*n));
                obj.Controller.setDataChan(n);obj.BoardRows=true;
            else
                obj.BoardRows=false;
            end
        end
        function command(obj,line)
            assert(obj.Controller.IsOpen,'origapp:Control','Start acquisition before changing RF settings.');
            assert(obj.Config.allowBoardCommands,'origapp:Control','Live board controls are unavailable in this session.');
            obj.Controller.queue(line);obj.Controller.flushCommands();
        end
        function resetAverage(obj)
            n=numel(obj.Params.scan_axis);a=obj.Config.avg_factor;
            obj.PatternAverage=zeros(n,a);obj.SpectrumAverage=zeros(n,a);
        end
        function invalidate(obj,reason)
            obj.Status=string(reason);obj.Last=struct('valid',false,'reason',string(reason));
            if ~isempty(obj.Analyzer),obj.Analyzer.invalidate(reason);end
            if ~isempty(obj.Params),obj.resetAverage();end
        end
        function p=parameters(obj,cfg)
            p=cfg;p.c=physconst('LightSpeed');
            if ~isempty(obj.Params) && cfg.fcAnt==obj.Params.fcAnt && cfg.num_elements==obj.Params.num_elements
                p.ula=obj.Params.ula;
            elseif string(cfg.elementModel)=="patch"
                p.ula=antPrep(cfg.num_elements,p.c,cfg.fcAnt);
            else
                p.ula=phased.ULA('NumElements',cfg.num_elements,'ElementSpacing',p.c/cfg.fcAnt/2);
            end
            p.scan_axis=-cfg.scan_bw/2:cfg.scan_res:cfg.scan_bw/2;
            [p.estimator,p.estimatorKind]=origapp.makeEstimator(cfg.doa,p.ula,p.scan_axis,cfg.num,cfg.fc,cfg.calibration);
            if string(cfg.doa)=="MVDRman"
                assert(~isempty(cfg.calibration.powCalibration),'origapp:Calibration','Manual MVDR needs power calibration.');
            elseif string(cfg.doa)=="MVDRman_corr"
                assert(~isempty(cfg.calibration.powCalibration) && ~isempty(cfg.calibration.steeringCorrection), ...
                    'origapp:Calibration','Corrected manual MVDR needs power and steering calibration.');
            end
            if cfg.phComp
                g=numel(p.scan_axis);
                assert(isequal(size(cfg.calibration.powCalibration),[g 4]) && ...
                    isequal(size(cfg.calibration.steeringCorrection),[g 4]),'origapp:Calibration', ...
                    'Phase/power calibration does not match this scan grid.');
            end
            if string(cfg.bfEngine)=="reviewed"
                p.reviewed.loading=cfg.diag;p.reviewed.gamma=cfg.gamma;p.reviewed.uncertainty=cfg.alpha;
                p.reviewed.maxIterations=cfg.iter;p.reviewed.mismatchDeg=cfg.mis_ang;
                p.reviewed.scanStepDeg=cfg.alg_scan_res;p.reviewed.sourceCount=cfg.num;
            end
            p.iqAdaptive=logical(cfg.adIQcomp);p.iqStatic=logical(cfg.IQcomp);p.iqMu=cfg.stepMU;
            p.coupComp=false;p.phComp=logical(cfg.phComp);p.iqFilter=obj.IqFilter;
        end
        function cfg=uncalibrated(~,cfg)
            cfg.calibration.powCalibration=[];cfg.calibration.steeringCorrection=[];
            cfg.phComp=false;
            if startsWith(string(cfg.doa),"MVDRman"),cfg.doa='MVDR';end
        end
    end
end
