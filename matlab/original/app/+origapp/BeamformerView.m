classdef BeamformerView < handle
    %BEAMFORMERVIEW Six measured views, readout tiles and the supported RF/DSP controls.
    % This class performs no acquisition, beamforming or instrument IO. Its
    % callback contract is implemented by DemoSession/the owning frontend.
    % Everything drawn is display math on the snapshot handed to show():
    % readout tiles, markers, per-stream table and histories never feed back
    % into processing. The only file output is the user-requested snapshot.
    properties (SetAccess=private)
        Figure = []
        Ax = struct()
        Controls = struct()
        Lines = struct()
        StatusLabel = []
        StatePill = []
        EvmLabel = []
        Kpi = struct()
        KpiGrid = []
        Card = struct()
        Marks = struct()
        Empty = struct()
        Monitor = struct()
        PlotGrid = []
        RootGrid = []
        Sidebar = []
        ScopeLabel = []
        MetricLabel = []
        CoverageLabel = []
        HeaderGrid = []
        FooterGrid = []
        OuterGrid = []
        TitleLabel = []
        LastSequence = NaN
        HistorySequence = []
        HistoryEvm = []
        HistoryDegraded = []
        HistoryBreak = []
        Held = false
        ChannelSequence = []
        ChannelPhase = zeros(0,4)
        ChannelLevel = zeros(0,4)
        ChannelBreak = []
        FramesShown = 0
        FramesCleared = 0
        EventLog = {}
        TimeMode = 'iq'
        EvmMode = 'history'
        EvmUnit = 'percent'
        ThemeName = 'dark'
    end
    properties (Constant,Access=private)
        RfFields = ["adcMHz","dacMHz","dac1MHz","adcEven","adcMirror","d0Even","d1Even"]
    end
    properties (Access=private)
        Config
        Callbacks
        % Axis limits the view sets itself instead of MATLAB's automatic
        % limits (see holdLimits): per axes, x/y = managed, lx/ly = last set.
        Managed = struct()
        Panels = []
        Accepted = struct()
        % converter path settings by kind (DemoSession.PathKinds); DAC kinds use
        % elements 1 and 3 (DAC_B, DAC_A). Replaced by the board's state on start.
        PhaseValues = struct('ADC',[-90 -90 90 90],'DAC',[0 0 0 0],'adcGain',[1.99 1.99 1.99 1.99], ...
            'adcIq',[0 0 0 0],'adcAtten',[0 0 0 0],'dacGain',[1.99 0 1.99 0],'dacIq',[0 0 0 0],'dacCurrent',[40.5 0 40.5 0])
        AdcNames = {'ADC_D','ADC_C','ADC_B','ADC_A'}   % stream 0..3 by RFSoC 4x2 connector
        DacNames = {'DAC_B','DAC_A'}                   % DAC index 0, 2
        UserSidebar = []
        Closing = false
        LastData = []
        LastReason = ""
        SnapshotDir = ''
        Clock = []
        FrameTimes = []
        RecordedSequence = NaN  % last frame given to record()
        SpectrumHold = []
        Page = 1
        SeenSequence = NaN
        GapPending = false
        Health = []
        Exporting = false
        Deferred = []
        ChannelGap = false
        EvmSub = struct('x',[],'y',[])
        EvmSym = struct('x',[],'y',[])
        EvmNow = [NaN NaN]
        LastFs = 125e6
        Theme = struct()
        Probe = []
        ClientSize = []
        Scale = 1
    end
    methods
        function obj=BeamformerView(cfg,callbacks)
            if nargin<2,callbacks=struct();end
            obj.Config=cfg;obj.Callbacks=callbacks;
            name=char(lower(string(obj.field(cfg,'theme','light'))));
            if ~any(strcmp(name,{'dark','light'})),name='dark';end
            obj.ThemeName=name;obj.Theme=obj.palette(name);
            if isfield(cfg,'dphase'),obj.PhaseValues.DAC=reshape(cfg.dphase,1,[]);end
            if isfield(cfg,'adcConnectors'),obj.AdcNames=cellstr(string(cfg.adcConnectors));end
            if isfield(cfg,'dacConnectors'),obj.DacNames=cellstr(string(cfg.dacConnectors));end
            obj.SnapshotDir=char(string(obj.field(cfg,'snapshotDir','')));
            out=char(string(obj.field(cfg,'outputDir','')));
            if isempty(obj.SnapshotDir) && ~isempty(out),obj.SnapshotDir=fullfile(out,'snapshots');end
            obj.Clock=tic;
            obj.build();
        end
        function record(obj,s)
            % Per-frame data without drawing (see recordFrame).
            obj.recordFrame(s);
        end
        function show(obj,s)
            if ~obj.isOpen(),return,end
            if obj.Exporting,obj.Deferred=s;return,end
            if isfield(s,'health'),obj.Health=s.health;end
            if ~isfield(s,'valid') || ~s.valid
                obj.clear(obj.field(s,'reason','No fresh acquisition'));
                return
            end
            th=obj.Theme;
            seq=obj.field(s,'sequence',NaN);age=obj.field(s,'age',NaN);
            if ~(seq==obj.RecordedSequence),obj.recordFrame(s);end   % callers that draw every frame
            fresh=~(seq==obj.SeenSequence);obj.SeenSequence=seq;
            if fresh,obj.FramesShown=obj.FramesShown+1;end
            if obj.Held
                % View-only hold: the six plots stay on the held frame and
                % say so; acquisition and counters keep running.
                obj.put(obj.StatusLabel,sprintf('HELD frame %g  ·  NOT LIVE  ·  live acquisition is at frame %g',obj.LastSequence,seq));
                obj.StatusLabel.FontColor=th.warn;obj.pill('HELD','warn');
                obj.ChannelGap=true;obj.GapPending=true;
                obj.showRate();
                drawnow limitrate nocallbacks
                return
            end
            scope=string(obj.field(s,'scope','Array model / UNCALIBRATED'));
            obj.put(obj.ScopeLabel,char(scope));obj.setp(obj.ScopeLabel,'Tooltip',char(scope));
            obj.put(obj.StatusLabel,sprintf('frame %g  ·  age %.2f s',seq,age));
            obj.setp(obj.StatusLabel,'FontColor',th.muted);
            obj.pill('LIVE','ok');
            obj.setp(obj.Controls.Start,'Enable','off');obj.put(obj.Controls.Start,'Running');
            if strlength(obj.LastReason)>0
                obj.logEvent(sprintf('live again · frame %g',seq));obj.LastReason="";
            end
            obj.LastData=s;obj.LastFs=obj.field(s,'fsHz',obj.field(obj.Config,'fsRfsoc',125e6));
            names=fieldnames(obj.Empty);
            for k=1:numel(names),obj.setp(obj.Empty.(names{k}),'Visible','off');end
            % --- spatial model views -------------------------------------
            scan=obj.field(s,'scan',[]);
            doa=obj.field(s,'doaSpectrum',[]);pat=obj.field(s,'patternDb',[]);
            obj.setLine('doa',scan,doa);
            obj.setLine('pattern',scan,pat);
            angles=obj.field(s,'angles',[]);pw=obj.field(s,'anglePowerDb',[]);
            if numel(pw)~=numel(angles),pw=nan(size(angles));end
            keep=isfinite(angles);angles=angles(keep);pw=pw(keep);
            if logical(obj.field(obj.Config,'plotMirror',0))
                % Mirror (display only): angle -> -angle on both spatial plots
                scan=-scan;angles=-angles;
                obj.setLine('doa',scan,doa);obj.setLine('pattern',scan,pat);
            end
            sy=obj.field(s,'angleSync',[]);if numel(sy)~=numel(keep),sy=nan(size(keep));end;sy=sy(keep);
            roles=obj.directionRoles(angles,pw,string(obj.field(s,'beamformer',"")),sy,logical(obj.field(s,'tracked',false)));
            obj.mark('doa',angles,roles);obj.mark('pattern',angles,roles);
            if obj.field(obj.Config,'num',1)==0 && isfield(obj.Controls,'SourceCount')
                obj.paintSourceCount(0,obj.field(s,'sourceCount',[]));   % Auto: show this frame's count
            end
            if isempty(angles) || isempty(doa)
                obj.put(obj.Card.doa.note,'estimate unavailable');
                if isempty(doa) && (logical(obj.field(s,'directOnly',false)) || isempty(angles))
                    obj.emptyState('doa','NO DOA SPECTRUM','no array estimate in this session or frame');
                elseif isempty(doa)
                    obj.emptyState('doa','NO DOA SPECTRUM','this estimator returns angles only');
                end
            else
                obj.put(obj.Card.doa.note,strjoin(roles.text,' · '));
            end
            if isempty(pat)
                obj.put(obj.Card.pattern.note,'single stream · no weights');
                obj.emptyState('pattern','NO PATTERN','direct single-stream session');
            elseif isempty(angles)
                [~,ix]=max(pat);
                obj.put(obj.Card.pattern.note,sprintf('peak at model %.1f°',scan(ix)));
            else
                % response of the beam toward each direction: the difference is
                % how much the other signal is rejected relative to the beam
                g=arrayfun(@(a)pat(find(abs(scan-a)==min(abs(scan-a)),1)),angles);g(g==0)=0;   % no '-0 dB'
                parts=compose('%s %.1f°: %.0f dB',string(roles.name(:)),angles(:),g(:));
                obj.put(obj.Card.pattern.note,char(strjoin(parts,' · ')));
            end
            % --- time domain and per-stream histories --------------------
            samples=obj.field(s,'samples',[]);fs=obj.field(s,'fsHz',obj.field(obj.Config,'fsRfsoc',125e6));
            % Only the visible view of the time card is sent to the window:
            % every changed line costs render time even when it is hidden.
            if strcmp(obj.TimeMode,'iq'),obj.drawTime(samples,fs);end
            ch=obj.field(s,'channels',[]);
            obj.drawChannels();
            obj.pad();
            obj.showChannels(ch,obj.field(s,'weights',[]));
            obj.timeNote(numel(samples),fs);
            % --- spectrum ------------------------------------------------
            analysis=obj.field(s,'analysis',[]);
            spec=obj.field(s,'spectrum',[]);
            if isempty(spec) && isstruct(analysis),spec=obj.field(analysis,'spectrum',[]);end
            if isstruct(spec) && isfield(spec,'freqHz') && isfield(spec,'psdDbfs')
                obj.showSpectrum(spec.freqHz(:)/1e6,spec.psdDbfs(:));
            else
                obj.setLine('spectrum',[],[]);obj.setLine('spectrumHold',[],[]);
                obj.put(obj.Card.spectrum.note,'unavailable');
            end
            % --- demodulation --------------------------------------------
            if isstruct(analysis),obj.showLevel(analysis,ch);end
            if isstruct(analysis) && isfield(analysis,'valid') && analysis.valid
                obj.showAnalysis(analysis,seq);
            else
                why='OFDM unavailable';
                if isstruct(analysis),why=char(string(obj.field(analysis,'reason',why)));end
                obj.clearAnalysis(why);
                if isstruct(analysis) && isfinite(obj.field(analysis,'syncPeak',NaN))
                    sub=char(string(obj.field(analysis,'state','no demodulation')));
                    if analysis.syncPeak<obj.field(analysis,'syncThreshold',-Inf),sub='below sync threshold';end
                    obj.tile('sync',sprintf('%.2f',analysis.syncPeak),sub,'warn');
                end
            end
            obj.showVendor(obj.field(s,'vendor',[]),seq);
            obj.showRate();
            obj.LastSequence=seq;
            obj.holdLimits();
            drawnow limitrate nocallbacks
        end
        function clear(obj,reason)
            if ~obj.isOpen(),return,end
            reason=string(reason);
            if obj.Held
                obj.Held=false;obj.Controls.Hold.Value=false;obj.holdLook();
                obj.logEvent('hold released · acquisition became invalid');
            end
            obj.SeenSequence=NaN;obj.ChannelGap=true;
            set([obj.Lines.chPhase obj.Lines.chLevel],'Color',obj.Theme.dim);
            for n=["doa","pattern","spectrum","spectrumHold","timeI","timeQ"]
                obj.setLine(char(n),[],[]);
            end
            obj.SpectrumHold=[];
            obj.mark('doa',[]);obj.mark('pattern',[]);
            obj.clearAnalysis(reason);
            for n=["doa","pattern","spectrum","constellation"]
                obj.emptyState(char(n),'NO CURRENT FRAME',reason);
            end
            if strcmp(obj.TimeMode,'iq'),obj.emptyState('time','NO CURRENT FRAME',reason);end
            obj.StatusLabel.Text=char(reason);obj.StatusLabel.FontColor=obj.Theme.warn;
            low=lower(reason);
            if contains(low,"paus"),obj.pill('PAUSED','idle');
            elseif contains(low,"idle"),obj.pill('IDLE','idle');
            elseif contains(low,"stop"),obj.pill('STOPPED','fault');
            elseif contains(low,"stale") || contains(low,"expired"),obj.pill('STALE','warn');
            else,obj.pill('NO DATA','warn');
            end
            for n=["doa","pattern","spectrum"],obj.Card.(n).note.Text='unavailable';end
            obj.timeNote(0,NaN);
            obj.tile('rx','—','','idle');
            obj.showChannels([],[]);
            obj.showVendor([],NaN);
            if reason~=obj.LastReason
                obj.FramesCleared=obj.FramesCleared+1;
                obj.logEvent("display cleared · "+reason);obj.LastReason=reason;
            end
            obj.LastData=[];obj.LastSequence=NaN;obj.FrameTimes=[];
            obj.ScopeLabel.Text=char(string(obj.field(obj.Config,'arrayLabel','Array model'))+' · UNCALIBRATED');
            obj.ScopeLabel.Tooltip=obj.ScopeLabel.Text;
            obj.showRate();
            drawnow limitrate nocallbacks
        end
        function showHealth(obj,health)
            % Counter refresh only (no plot work): the controller counts a
            % frame as accepted after it was drawn.
            if ~obj.isOpen() || obj.Exporting || ~isstruct(health),return,end
            obj.Health=health;obj.showRate();
        end
        function tf=isOpen(obj)
            tf=~isempty(obj.Figure) && isvalid(obj.Figure);
        end
        function delete(obj)
            if obj.isOpen()
                obj.Figure.CloseRequestFcn=[];
                delete(obj.Figure);
            end
        end
        function updateConfig(obj,cfg)
            % Called after an explicit successful load/configuration action,
            % not each frame (never overwrite edits while a user types).
            rescan=~isequal(obj.field(obj.Config,'scan_bw',NaN),obj.field(cfg,'scan_bw',NaN));
            obj.Config=cfg;
            if rescan,obj.defaultLimits('doa');obj.defaultLimits('pattern');end
            cal=obj.field(cfg,'calibration',struct());
            ready=~isempty(obj.field(cal,'steeringCorrection',[])) && ~isempty(obj.field(cal,'powCalibration',[]));
            obj.Controls.phComp.Enable=matlab.lang.OnOffSwitchState(ready);
            obj.Controls.phComp.Value=logical(cfg.phComp);obj.Accepted.phComp=logical(cfg.phComp);
            obj.Controls.doa.Value=char(cfg.doa);obj.Accepted.doa=char(cfg.doa);
            if isfield(cfg,'pathKinds') && ~isempty(cfg.pathKinds)
                kinds=cellstr(string(cfg.pathKinds));labels=cell(size(kinds));
                for j=1:numel(kinds),sp=obj.pathSpec(kinds{j});labels{j}=sp{1};end
                old=obj.Controls.PhaseKind.Value;
                obj.Controls.PhaseKind.Items=labels;obj.Controls.PhaseKind.ItemsData=kinds;
                if any(strcmp(kinds,old)),obj.Controls.PhaseKind.Value=old;else,obj.Controls.PhaseKind.Value=kinds{1};end
            end
            if isfield(cfg,'paths') && isstruct(cfg.paths)
                for n=string(fieldnames(cfg.paths)).'
                    v=double(cfg.paths.(n));v(~isfinite(v))=0;obj.PhaseValues.(n)=v;
                end
            end
            obj.phaseKind();
            if isfield(cfg,'zeroCal'),obj.zeroLook(cfg.zeroCal);end
            if isfield(cfg,'rows') && any(cellfun(@(v)isequal(v,cfg.rows),obj.Controls.rows.ItemsData))
                obj.Controls.rows.Value=cfg.rows;obj.Accepted.rows=cfg.rows;
            end
            obj.band();
        end
        function fitPlots(obj)
            names=fieldnames(obj.Ax);
            for k=1:numel(names),obj.defaultLimits(names{k});end
            obj.SpectrumHold=[];obj.setLine('spectrumHold',[],[]);
            values=[obj.Lines.payload.XData(:);obj.Lines.payload.YData(:); ...
                obj.Lines.header.XData(:);obj.Lines.header.YData(:);obj.Lines.pilots.XData(:);obj.Lines.pilots.YData(:)];
            values=values(isfinite(values));lim=1.45;
            if ~isempty(values),lim=max(lim,1.05*max(abs(values)));end
            obj.Ax.constellation.XLim=[-lim lim];obj.Ax.constellation.YLim=[-lim lim];
        end
        function files=saveSnapshot(obj,folder)
            % User-requested record of what is on screen: a PNG of the window
            % and a MAT file with the displayed snapshot struct and settings.
            files={};
            if ~obj.isOpen(),return,end
            if nargin<2 || isempty(folder)
                folder=obj.SnapshotDir;
                if isempty(folder)
                    folder=uigetdir(pwd,'Folder for RFSoC snapshots');
                    figure(obj.Figure);
                    if isequal(folder,0),return,end
                    obj.SnapshotDir=folder;
                end
            end
            folder=char(folder);
            if ~isfolder(folder),mkdir(folder);end
            stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
            base=fullfile(folder,['rfsoc4x2_' stamp]);
            data=obj.LastData;
            settings=obj.Accepted;drop={'phase1','phase2','phase3','phase4','phaseKind','CompareVsa','bwMHz','bw','dac','analyzer'};
            settings=rmfield(settings,drop(isfield(settings,drop)));
            settings.bwHz=obj.field(obj.Config,'bw',NaN);settings.analyzer=char(string(obj.field(obj.Config,'analyzer','')));
            settings.dacEnabled=logical(obj.Controls.Dac.Value);settings.phases=obj.PhaseValues;
            settings.theme=obj.ThemeName; %#ok<STRNU>
            history=struct('sequence',obj.HistorySequence,'evmPercent',obj.HistoryEvm, ...
                'degraded',obj.HistoryDegraded,'channelSequence',obj.ChannelSequence, ...
                'channelPhaseDeg',obj.ChannelPhase,'channelLevelDbfs',obj.ChannelLevel); %#ok<NASGU>
            events=obj.EventLog; %#ok<NASGU>
            save([base '.mat'],'data','settings','history','events','-v7');
            files={[base '.mat']};
            % The capture lets the acquisition timer run. Frames arriving
            % meanwhile are deferred, so the PNG shows the frame in the MAT.
            obj.Exporting=true;obj.Deferred=[];
            try
                drawnow;exportapp(obj.Figure,[base '.png']);files{end+1}=[base '.png'];
            catch err
                obj.logEvent("screenshot unavailable · "+string(err.message));
            end
            obj.Exporting=false;later=obj.Deferred;obj.Deferred=[];
            if ~isempty(later),obj.show(later);end
            tag='current frame';if isempty(data),tag='no current frame, history only';end
            obj.logEvent(sprintf('snapshot saved (%s) · rfsoc4x2_%s',tag,stamp));
        end
        function setTheme(obj,name)
            % Live light/dark switch. Every colour in the window comes from the
            % palette, so each object is recoloured by looking its current
            % colour up in the old palette; no graphics are rebuilt.
            name=char(lower(string(name)));
            assert(any(strcmp(name,{'dark','light'})),'origapp:View','Theme must be dark or light.');
            if ~obj.isOpen() || strcmp(name,obj.ThemeName),return,end
            from=cell2mat(struct2cell(obj.Theme));next=obj.palette(name);to=cell2mat(struct2cell(next));
            try
                if isprop(obj.Figure,'Theme'),obj.Figure.Theme=name;end
            catch
            end
            props={'Color','BackgroundColor','FontColor','ForegroundColor','XColor','YColor','GridColor', ...
                'MarkerFaceColor','MarkerEdgeColor','FaceColor','EdgeColor'};
            for k=1:numel(props)
                h=findall(obj.Figure,'-property',props{k});
                for n=1:numel(h)
                    v=get(h(n),props{k});
                    if ~isnumeric(v) || numel(v)~=3,continue,end
                    [d,ix]=min(max(abs(from-v(:).'),[],2));
                    if d<2e-3,set(h(n),props{k},to(ix,:));end
                end
            end
            % Setting a ruler colour also recolours its label; restore those.
            names=fieldnames(obj.Ax);
            for k=1:numel(names)
                obj.Ax.(names{k}).XLabel.Color=next.muted;obj.Ax.(names{k}).YLabel.Color=next.muted;
            end
            obj.Theme=next;obj.ThemeName=name;obj.themeLook();obj.keys();
            obj.logEvent([name ' theme']);
        end
        function clearHistory(obj)
            obj.HistorySequence=[];obj.HistoryEvm=[];obj.HistoryDegraded=[];obj.HistoryBreak=[];
            obj.ChannelSequence=[];obj.ChannelPhase=zeros(0,4);obj.ChannelLevel=zeros(0,4);obj.ChannelBreak=[];
            obj.SpectrumHold=[];obj.FrameTimes=[];
            for n=["evmHistory","evmFlagged","spectrumHold","evmPad"],obj.setLine(char(n),[],[]);end
            for k=1:4
                set(obj.Lines.chPhase(k),'XData',NaN,'YData',NaN);
                set(obj.Lines.chLevel(k),'XData',NaN,'YData',NaN);
            end
            obj.Marks.evmMedian.Visible='off';
            if strcmp(obj.EvmMode,'history'),obj.Card.evm.note.Text='no history';end
            obj.logEvent('histories cleared');
        end
    end
    methods (Access=private)
        function build(obj)
            th=obj.Theme;
            f=uifigure('Name','RFSoC 4x2 Beamformer','Visible','off','Color',th.bg, ...
                'Position',[60 60 1480 900],'AutoResizeChildren','off','Tag','RFSoCBeamformerDashboard');
            obj.Figure=f;
            try
                % Built-in chrome (popups, scrollbars, axes toolbars) follows
                % the dark palette on releases that support figure themes.
                if isprop(f,'Theme'),f.Theme=obj.ThemeName;end
            catch
            end
            f.CloseRequestFcn=@(~,~)obj.onClose();
            outer=uigridlayout(f,[4 1],'RowHeight',{44,66,'1x',24},'Padding',[14 10 14 8], ...
                'RowSpacing',8,'BackgroundColor',th.bg);obj.OuterGrid=outer;
            % --- header ---------------------------------------------------
            header=uigridlayout(outer,[1 8],'ColumnWidth',{112,150,84,'1x',76,104,90,84},'Padding',[0 0 0 0], ...
                'ColumnSpacing',10,'BackgroundColor',th.bg);header.Layout.Row=1;obj.HeaderGrid=header;
            obj.Controls.Sidebar=uibutton(header,'Text','☰ Controls','FontWeight','bold', ...
                'BackgroundColor',th.input,'FontColor',th.text,'ButtonPushedFcn',@(~,~)obj.toggleSidebar(), ...
                'Tooltip','F6 · Show or hide the control sidebar');
            obj.TitleLabel=uilabel(header,'Text','RFSoC 4×2','FontWeight','bold','FontSize',22,'FontColor',th.text);
            pillBox=uigridlayout(header,[1 1],'Padding',[0 9 0 9],'BackgroundColor',th.bg);
            obj.StatePill=uilabel(pillBox,'Text','IDLE','HorizontalAlignment','center','FontWeight','bold', ...
                'FontSize',11,'BackgroundColor',th.input,'FontColor',th.muted);
            obj.StatusLabel=uilabel(header,'Text','ready to acquire','FontSize',12,'FontColor',th.muted);
            obj.Controls.Hold=uibutton(header,'state','Text','Hold','BackgroundColor',th.input,'FontColor',th.text, ...
                'ValueChangedFcn',@(~,~)obj.holdAction(), ...
                'Tooltip','F3 · Freeze the plots on the current frame for inspection. View only: the board keeps streaming. Released when acquisition becomes invalid.');
            obj.Controls.Snapshot=uibutton(header,'Text','Snapshot','BackgroundColor',th.input,'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.snapshotAction(), ...
                'Tooltip','F2 · Save a PNG of this window and a MAT file with the displayed frame, settings and histories');
            obj.Controls.Fit=uibutton(header,'Text','Fit plots','BackgroundColor',th.input,'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.fitPlots(),'Tooltip','F5 · Restore default limits on all six plots and reset max hold');
            obj.Controls.ThemeSwitch=uibutton(header,'Text','','BackgroundColor',th.input,'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.toggleTheme(),'Tooltip','F7 · Switch between the dark and the light theme');
            obj.themeLook();
            % --- readout tiles --------------------------------------------
            kg=uigridlayout(outer,[1 7],'ColumnWidth',repmat({'1x'},1,7),'RowHeight',{'1x'},'ColumnSpacing',8, ...
                'RowSpacing',6,'Padding',[0 0 0 0],'BackgroundColor',th.bg);kg.Layout.Row=2;obj.KpiGrid=kg;
            spec={'evm','PAYLOAD EVM','Primary metric: rms error of every complete detected payload burst'; ...
                'evmDb','EVM (dB)','Same payload EVM in dB; header and pilot EVM below'; ...
                'rx','OUTPUT LEVEL','Mean level of the analysed output buffer; highest raw ADC peak below'; ...
                'cfo','CARRIER OFFSET','Median training-based CFO; pilot timing drift along the burst in ppm (a slip indicator in shared-clock loopback)'; ...
                'sync','SYNC PEAK','Best preamble correlation in this buffer (own metric 0..1, not the vendor sync quantity) and median training-row SNR estimate'; ...
                'bursts','BURSTS','Qualified / complete bursts in this buffer; clean-only EVM is the secondary metric'; ...
                'rate','DISPLAY RATE','Fresh frames received by the display per second (also while held); acquisition counters of this session'};
            for k=1:size(spec,1),obj.buildTile(kg,spec{k,1},spec{k,2},spec{k,3});end
            obj.EvmLabel=obj.Kpi.evm.value;obj.EvmLabel.FontSize=22;
            % --- sidebar and plots ----------------------------------------
            main=uigridlayout(outer,[1 2],'ColumnWidth',{300,'1x'},'ColumnSpacing',10, ...
                'Padding',[0 0 0 0],'BackgroundColor',th.bg);main.Layout.Row=3;obj.RootGrid=main;
            % Containers are grids, not uipanels: on a monitor whose scale differs
            % from the primary one MATLAB sizes a uipanel in primary-scale pixels
            % (too small or too large for its cell); a grid always fills its cell.
            side=uigridlayout(main,[1 1],'Padding',[0 0 0 0],'BackgroundColor',th.panel);side.Layout.Column=1;obj.Sidebar=side;
            obj.buildControls(side);obj.fitLimits();
            pg=uigridlayout(main,[2 3],'ColumnWidth',{'1x','1x','1x'}, ...
                'RowHeight',{'1x','1x'},'Padding',[0 0 0 0], ...
                'RowSpacing',9,'ColumnSpacing',9,'BackgroundColor',th.bg);
            pg.Layout.Column=2;obj.PlotGrid=pg;
            keys={'doa','pattern','spectrum','time','constellation','evm'};
            titles={'DOA spectrum','Receive pattern','Baseband spectrum','Time domain','Constellation','Payload EVM'};
            tips={'Spatial spectrum of the selected estimator on the array model. Uncalibrated model angle.', ...
                'Relative response of the applied weights on the array model. Uncalibrated model angle.', ...
                'Averaged spectrum of the analysed output buffer. Shaded: configured signal bandwidth.', ...
                'Selected output as a min/max envelope with detected burst starts, or frame-to-frame phase / level of the raw receive streams (conducted path, not arrival angle).', ...
                'Equalized cells of every complete detected burst: payload, header and pilots.', ...
                'Primary payload EVM over all complete detected bursts. Ringed points were quality-flagged; the line breaks where acquisitions were rejected or skipped.'};
            badges={'MODEL','MODEL','','','',''};
            obj.Panels=gobjects(1,6);
            for k=1:6,obj.buildCard(pg,k,keys{k},titles{k},badges{k});obj.Card.(keys{k}).title.Tooltip=tips{k};end
            obj.buildPlots();
            % --- client size probe (hidden under the footer) --------------
            % Figure.Position is in primary-monitor pixels. On a monitor with
            % another scale the window is really Position*primaryScale/ownScale
            % CSS pixels; only the client knows that, so it reports its size.
            try
                obj.Probe=uihtml(outer,'HTMLSource',['<html><body style="margin:0;background:#000"><script>function setup(c){var l="";' ...
                    'function r(){try{var w=window.top,s=w.innerWidth+"x"+w.innerHeight;if(s!==l){l=s;c.Data=[w.innerWidth,w.innerHeight];}}catch(e){}}' ...
                    'try{window.top.addEventListener("resize",r);}catch(e){}r();setInterval(r,500);}</script></body></html>'], ...
                    'DataChangedFcn',@(h,~)obj.clientSize(h.Data));
                obj.Probe.Layout.Row=4;obj.Probe.Layout.Column=1;
            catch
                obj.Probe=[];
            end
            % --- footer ---------------------------------------------------
            footer=uigridlayout(outer,[1 3],'ColumnWidth',{'1x',330,330},'Padding',[0 0 0 0], ...
                'BackgroundColor',th.bg);footer.Layout.Row=4;obj.FooterGrid=footer;
            obj.ScopeLabel=uilabel(footer,'Text',char(string(obj.field(obj.Config,'arrayLabel','Array model'))+' · UNCALIBRATED'), ...
                'FontSize',11,'FontColor',th.warn);
            obj.MetricLabel=uilabel(footer,'Text','F2 snapshot · F3 hold · F5 fit · F6 controls · F7 theme · F8 pause','FontSize',11,'FontColor',th.dim,'HorizontalAlignment','right');
            obj.CoverageLabel=uilabel(footer,'Text','No demodulated frame','FontSize',11,'FontColor',th.muted,'HorizontalAlignment','right');
            set(findall(f,'-property','FontName'),'FontName','Segoe UI');
            obj.Monitor.log.FontName='Consolas';
            f.SizeChangedFcn=@(~,~)obj.reflow();
            f.WindowKeyPressFcn=@(~,e)obj.onKey(e);
            % Start on the primary monitor (row 1): the only one whose
            % MonitorPositions row is in the units of Figure.Position when
            % monitor scales differ. Never larger than that monitor.
            mp=get(groot,'MonitorPositions');m=mp(1,:);
            w=min(1540,max(420,m(3)-48));h=min(930,max(340,m(4)-110));
            f.Position=[m(1)+round((m(3)-w)/2),m(2)+max(45,round((m(4)-h)/2)),w,h];
            obj.reflow();obj.selectPage(1);obj.timeMode();obj.evmMode();obj.band();
            if logical(obj.field(obj.Config,'visible',false)),f.Visible='on';end
        end
        function buildTile(obj,parent,key,caption,tip)
            th=obj.Theme;
            g=uigridlayout(parent,[3 2],'ColumnWidth',{3,'1x'},'RowHeight',{13,'1x',13},'RowSpacing',1, ...
                'ColumnSpacing',9,'Padding',[0 5 8 5],'BackgroundColor',th.panel,'Tooltip',tip);
            t.grid=g;
            t.edge=uilabel(g,'Text','','BackgroundColor',th.hair);t.edge.Layout.Row=[1 3];t.edge.Layout.Column=1;
            t.caption=uilabel(g,'Text',caption,'FontSize',9,'FontWeight','bold','FontColor',th.dim);
            t.caption.Layout.Row=1;t.caption.Layout.Column=2;
            t.value=uilabel(g,'Text','—','FontSize',20,'FontWeight','bold','FontColor',th.dim);
            t.value.Layout.Row=2;t.value.Layout.Column=2;
            t.sub=uilabel(g,'Text','','FontSize',10,'FontColor',th.muted);
            t.sub.Layout.Row=3;t.sub.Layout.Column=2;
            obj.Kpi.(key)=t;
        end
        function buildCard(obj,parent,k,key,titleText,badge)
            th=obj.Theme;
            p=uigridlayout(parent,[1 1],'Padding',[0 0 0 0],'BackgroundColor',th.panel);obj.Panels(k)=p;
            g=uigridlayout(p,[2 1],'RowHeight',{24,'1x'},'RowSpacing',2,'Padding',[10 7 8 6],'BackgroundColor',th.panel);
            head=uigridlayout(g,[1 4],'ColumnWidth',{'fit','1x',0,0},'Padding',[0 0 0 0],'ColumnSpacing',8, ...
                'BackgroundColor',th.panel);
            c.panel=p;c.head=head;
            c.title=uilabel(head,'Text',titleText,'FontWeight','bold','FontSize',13,'FontColor',th.text);
            c.note=uilabel(head,'Text','','FontSize',11,'FontColor',th.muted);
            c.slot=uigridlayout(head,[1 1],'Padding',[0 1 0 1],'BackgroundColor',th.panel);
            c.badge=uilabel(head,'Text',badge,'FontSize',9,'FontWeight','bold','HorizontalAlignment','center', ...
                'BackgroundColor',th.warnBg,'FontColor',th.warn, ...
                'Tooltip','Array-model quantity. Angles are model angles, not calibrated physical directions.');
            if ~isempty(badge),head.ColumnWidth{4}=52;end
            ax=uiaxes(g,'Color',th.panel,'XColor',th.dim,'YColor',th.dim,'GridColor',th.hair,'GridAlpha',1, ...
                'FontSize',10,'Box','off','TickLength',[0 0],'LineWidth',.75);
            grid(ax,'on');hold(ax,'on');
            ax.XLabel.Color=th.muted;ax.YLabel.Color=th.muted;
            axtoolbar(ax,{'datacursor','zoomin','zoomout','pan'});
            obj.Ax.(key)=ax;obj.Card.(key)=c;
            obj.Empty.(key)=text(ax,.5,.5,'','Units','normalized','HorizontalAlignment','center', ...
                'VerticalAlignment','middle','Color',th.dim,'FontSize',11,'FontWeight','bold', ...
                'Visible','off','HandleVisibility','off','PickableParts','none');
        end
        function buildPlots(obj)
            th=obj.Theme;A=obj.Ax;
            % DOA spectrum and receive pattern (array model)
            obj.Lines.doa=plot(A.doa,NaN,NaN,'LineWidth',1.6,'Color',th.model);
            xlabel(A.doa,'Model angle (°)');ylabel(A.doa,'Normalized spectrum');
            obj.Lines.pattern=plot(A.pattern,NaN,NaN,'LineWidth',1.6,'Color',th.model);
            xlabel(A.pattern,'Model angle (°)');ylabel(A.pattern,'Relative response (dB)');
            for n=["doa","pattern"]
                for k=1:3
                    obj.Marks.(n)(k)=xline(A.(n),0,'--','','Color',th.muted,'LineWidth',.9,'FontSize',9, ...
                        'LabelOrientation','horizontal','LabelVerticalAlignment','middle','Visible','off','HandleVisibility','off');
                end
            end
            % Baseband spectrum with band shading and optional max hold
            try
                obj.Marks.band=xregion(A.spectrum,-1,1,'FaceColor',th.s1,'FaceAlpha',.07,'EdgeColor','none', ...
                    'HandleVisibility','off');
            catch
                obj.Marks.band=[];
            end
            obj.Lines.spectrumHold=plot(A.spectrum,NaN,NaN,'Color',th.dim,'LineWidth',1,'Visible','off');
            obj.Lines.spectrum=plot(A.spectrum,NaN,NaN,'Color',th.s1,'LineWidth',1.2);
            xlabel(A.spectrum,'Baseband frequency (MHz)');ylabel(A.spectrum,'dBFS/bin');
            obj.Controls.MaxHold=uibutton(obj.Card.spectrum.slot,'state','Text','Max hold','FontSize',10, ...
                'BackgroundColor',th.input,'FontColor',th.muted,'ValueChangedFcn',@(~,~)obj.maxHold(), ...
                'Tooltip','Keep the per-bin maximum since the last clear, Fit plots or setting change');
            obj.Card.spectrum.head.ColumnWidth{3}=72;
            obj.Controls.Mirror=uibutton(obj.Card.doa.slot,'state','Text','Mirror','FontSize',10, ...
                'Value',logical(obj.field(obj.Config,'plotMirror',0)),'BackgroundColor',th.input,'FontColor',th.muted, ...
                'ValueChangedFcn',@(h,~)obj.configure('plotMirror',logical(h.Value),h), ...
                'Tooltip','Mirror the DOA spectrum and the receive pattern (angle -> -angle); display and board OLED only');
            obj.Card.doa.head.ColumnWidth{3}=60;
            % Time domain: waveform, or per-stream phase / level histories
            obj.Lines.timeQ=plot(A.time,NaN,NaN,'Color',th.s2,'LineWidth',.8);
            obj.Lines.timeI=plot(A.time,NaN,NaN,'Color',th.s1,'LineWidth',.8);
            obj.Lines.timePad=plot(A.time,NaN,NaN,'LineStyle','none','Marker','none','HandleVisibility','off');
            obj.Lines.burstOk=plot(A.time,NaN,NaN,'v','Color',th.ok,'MarkerFaceColor',th.ok,'MarkerSize',6,'LineStyle','none');
            obj.Lines.burstBad=plot(A.time,NaN,NaN,'v','Color',th.warn,'MarkerFaceColor',th.warn,'MarkerSize',6,'LineStyle','none');
            colors={th.s1,th.s2,th.s3,th.s4};
            for k=1:4
                obj.Lines.chPhase(k)=plot(A.time,NaN,NaN,'.-','Color',colors{k},'LineWidth',1,'MarkerSize',9,'Visible','off');
                obj.Lines.chLevel(k)=plot(A.time,NaN,NaN,'.-','Color',colors{k},'LineWidth',1,'MarkerSize',9,'Visible','off');
            end
            obj.Marks.timeKey=obj.key(A.time,'left');
            obj.Controls.TimeMode=uidropdown(obj.Card.time.slot,'Items',{'I/Q waveform','Stream phase','Stream level'}, ...
                'ItemsData',{'iq','phase','level'},'Value','iq','FontSize',10,'BackgroundColor',th.input,'FontColor',th.text, ...
                'ValueChangedFcn',@(~,~)obj.timeMode(), ...
                'Tooltip','Waveform of the selected output, or frame-to-frame phase / level of each raw receive stream');
            obj.Card.time.head.ColumnWidth{3}=118;
            % Constellation
            lev=(-3:2:3)/sqrt(10);[a,b]=meshgrid(lev);
            for v=[-2 0 2]/sqrt(10)
                xline(A.constellation,v,':','Color',th.hair,'HandleVisibility','off');
                yline(A.constellation,v,':','Color',th.hair,'HandleVisibility','off');
            end
            obj.Lines.ideal=plot(A.constellation,a(:),b(:),'o','Color',th.dim,'MarkerSize',10,'LineWidth',.75);
            obj.Lines.payload=scatter(A.constellation,NaN,NaN,9,'filled','MarkerFaceColor',th.s1, ...
                'MarkerFaceAlpha',.4,'MarkerEdgeColor','none');
            obj.Lines.header=scatter(A.constellation,NaN,NaN,22,'d','filled','MarkerFaceColor',th.s3, ...
                'MarkerFaceAlpha',.9,'MarkerEdgeColor','none');
            obj.Lines.pilots=scatter(A.constellation,NaN,NaN,22,'^','filled','MarkerFaceColor',th.s4, ...
                'MarkerFaceAlpha',.9,'MarkerEdgeColor','none');
            grid(A.constellation,'off');
            A.constellation.XTick=lev;A.constellation.YTick=lev;
            A.constellation.XTickLabel={'-3','-1','1','3'};A.constellation.YTickLabel={'-3','-1','1','3'};
            xlabel(A.constellation,'I');ylabel(A.constellation,'Q');
            A.constellation.DataAspectRatio=[1 1 1];
            A.constellation.XLim=[-1.45 1.45];A.constellation.YLim=[-1.45 1.45];
            obj.Marks.constKey=obj.key(A.constellation,'center');obj.keys();
            % Payload EVM: history, or the current frame per subcarrier / symbol
            obj.Marks.evmMedian=yline(A.evm,0,':','median','Color',th.muted,'FontSize',9,'LabelHorizontalAlignment','left', ...
                'Visible','off','HandleVisibility','off');
            obj.Lines.evmPad=plot(A.evm,NaN,NaN,'LineStyle','none','Marker','none','HandleVisibility','off');
            obj.Lines.evmHistory=plot(A.evm,NaN,NaN,'.-','Color',th.s1,'LineWidth',1.3,'MarkerSize',9);
            obj.Lines.evmFlagged=plot(A.evm,NaN,NaN,'o','Color',th.warn,'MarkerSize',7,'LineWidth',1.2,'LineStyle','none');
            obj.Lines.evmCurrent=plot(A.evm,NaN,NaN,'o','Color',th.text,'MarkerFaceColor',th.s1,'MarkerSize',7);
            obj.Lines.evmSub=plot(A.evm,NaN,NaN,'.-','Color',th.s1,'LineWidth',1,'MarkerSize',8,'Visible','off');
            obj.Lines.evmSym=plot(A.evm,NaN,NaN,'.-','Color',th.s1,'LineWidth',1.2,'MarkerSize',10,'Visible','off');
            obj.Card.evm.slot.ColumnWidth={46,'1x'};obj.Card.evm.slot.ColumnSpacing=6;
            obj.Controls.EvmUnit=uibutton(obj.Card.evm.slot,'state','Text','%','FontSize',10,'FontWeight','bold', ...
                'BackgroundColor',th.input,'FontColor',th.text,'ValueChangedFcn',@(~,~)obj.evmUnit(), ...
                'Tooltip','Switch the EVM graph between percent and dB (20·log10 of the same values)');
            obj.Controls.EvmMode=uidropdown(obj.Card.evm.slot,'Items',{'History','Per subcarrier','Per symbol'}, ...
                'ItemsData',{'history','subcarrier','symbol'},'Value','history','FontSize',10, ...
                'BackgroundColor',th.input,'FontColor',th.text,'ValueChangedFcn',@(~,~)obj.evmMode(), ...
                'Tooltip','Frame history of the primary EVM, or the current frame resolved by subcarrier or payload symbol');
            obj.Card.evm.head.ColumnWidth{3}=170;
            for n=["doa","pattern","spectrum","evm"],obj.defaultLimits(char(n));end
        end
        function h=key(obj,ax,align)
            % Persistent coloured series key (cheaper than a legend), kept in
            % the axes title: one text object, so its entries cannot overlap
            % each other whatever the panel width is, and the title is placed
            % correctly on a monitor with another scale, where text in
            % normalized units inside the axes is not.
            h=ax.Title;ax.TitleHorizontalAlignment=align;
            set(h,'String','','FontSize',9,'FontWeight','bold','Color',obj.Theme.muted,'Interpreter','tex');
        end
        function keys(obj)
            th=obj.Theme;colors={th.s1,th.s2,th.s3,th.s4};
            switch obj.TimeMode
                case 'iq',labels={'I','Q','▼ burst','▼ flagged / incomplete'};colors={th.s1,th.s2,th.ok,th.warn};
                otherwise,labels=obj.AdcNames;
            end
            obj.Marks.timeKey.String=obj.keyText(labels,colors);
            if isfield(obj.Marks,'constKey')
                obj.Marks.constKey.String=obj.keyText({'● 16QAM data','◆ BPSK header','▲ pilots'},{th.s1,th.s3,th.s4});
            end
        end
        function buildControls(obj,parent)
            th=obj.Theme;
            g=uigridlayout(parent,[5 1],'RowHeight',{34,206,30,'1x',0},'Padding',[10 10 10 8],'RowSpacing',8, ...
                'BackgroundColor',th.panel);obj.Controls.SideGrid=g;
            buttons=uigridlayout(g,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0], ...
                'BackgroundColor',th.panel);
            obj.Controls.Start=uibutton(buttons,'Text','Start','FontWeight','bold', ...
                'BackgroundColor',th.accent,'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.action('start',[]),'Tooltip','Open the board session and start acquiring');
            obj.Controls.Pause=uibutton(buttons,'state','Text','Pause','BackgroundColor',th.input,'FontColor',th.text, ...
                'ValueChangedFcn',@(h,~)obj.valueAction('pause',h,logical(h.Value)), ...
                'Tooltip','F8 · Stop / resume the board data stream; current plots are cleared while paused');
            if ~obj.has('start'),obj.Controls.Start.Enable='off';end
            if ~obj.has('pause'),obj.Controls.Pause.Enable='off';end
            obj.Controls.Error=uilabel(g,'Text','','FontColor',th.warn,'BackgroundColor',th.warnBg,'WordWrap','on', ...
                'FontSize',11,'Visible','off');
            % Bottom row: a refusal must not move the selectors (scripts and
            % users click them by position); the page area shrinks instead.
            obj.Controls.Error.Layout.Row=5;
            % Always visible, whatever page is open (as in the original GUI):
            % what is shown, which source, and the two algorithm selectors.
            q=uigridlayout(g,[7 2],'ColumnWidth',{104,'1x'},'RowHeight',{26,26,26,26,26,26,26},'Padding',[0 0 0 0], ...
                'RowSpacing',4,'ColumnSpacing',6,'BackgroundColor',th.panel);q.Layout.Row=2;obj.Controls.QuickGrid=q;
            seg=uigridlayout(g,[2 4],'RowHeight',{'1x',2},'ColumnWidth',{'1x','1x','1.35x','1.15x'},'RowSpacing',0, ...
                'ColumnSpacing',2,'Padding',[0 0 0 0],'BackgroundColor',th.panel);seg.Layout.Row=3;
            names={'DSP','RF','Algorithms','Monitor'};
            for k=1:4
                obj.Controls.PageButton(k)=uibutton(seg,'state','Text',names{k},'FontSize',11, ...
                    'BackgroundColor',th.panel,'FontColor',th.muted,'ValueChangedFcn',@(~,~)obj.selectPage(k));
                obj.Controls.PageButton(k).Layout.Row=1;obj.Controls.PageButton(k).Layout.Column=k;
                obj.Controls.PageRule(k)=uilabel(seg,'Text','','BackgroundColor',th.hair);
                obj.Controls.PageRule(k).Layout.Row=2;obj.Controls.PageRule(k).Layout.Column=k;
            end
            for k=1:4
                obj.Controls.PagePanel(k)=uigridlayout(g,[1 1],'Padding',[0 0 0 0],'BackgroundColor',th.panel,'Visible','off');
                obj.Controls.PagePanel(k).Layout.Row=4;obj.Controls.PagePanel(k).Layout.Column=1;
            end
            dsp=obj.Controls.PagePanel(1);rf=obj.Controls.PagePanel(2);
            advanced=obj.Controls.PagePanel(3);mon=obj.Controls.PagePanel(4);
            % --- RF ---------------------------------------------------------
            % Rows 17..20 hold the four phase fields (see phaseKind).
            r=obj.controlGrid(rf,{20,28,22,22,20,28,22,28,22,28,22,22,28,6,20,28,28,28,28,28,28,6,28,44});
            % RF limits measured on the board (2026-11-22): the RF data converter
            % accepts mixer frequencies -6000..6000 MHz for the ADC and each DAC
            % (6001 refused); the ADC sign is the Mirror box. Phases: -180 refused.
            obj.heading(r,1,'ADC');
            obj.number(r,2,'ADC center','adcMHz',obj.field(obj.Config,'fc',3e9)/1e6,[0 6000],false,'%g MHz');
            obj.checkbox(r,3,'Even Nyquist zone','adcEven',obj.field(obj.Config,'nyquistZone',1)==2,false);
            obj.checkbox(r,4,'Mirror','adcMirror',obj.field(obj.Config,'adcMirror',1)<0,false);
            obj.Controls.adcMirror.Tooltip='Negative ADC mixer frequency: mirrors the received spectrum.';
            obj.heading(r,5,'DAC');
            obj.number(r,6,'DAC B center','dacMHz',obj.field(obj.Config,'fc_d0',3e9)/1e6,[-6000 6000],false,'%g MHz');
            obj.checkbox(r,7,'DAC B even Nyquist zone','d0Even',obj.field(obj.Config,'nyquistZone_d0',1)==2,false);
            obj.number(r,8,'DAC A center','dac1MHz',obj.field(obj.Config,'fc_d1',3e9)/1e6,[-6000 6000],false,'%g MHz');
            obj.checkbox(r,9,'DAC A even Nyquist zone','d1Even',obj.field(obj.Config,'nyquistZone_d1',1)==2,false);
            for n=["adcMHz","dacMHz","dac1MHz","adcEven","adcMirror","d0Even","d1Even"]
                obj.Controls.(n).ValueChangedFcn=@(~,~)obj.dirty();
            end
            for n=["adcMHz","dacMHz","dac1MHz"],obj.Controls.(n).RoundFractionalValues='on';end
            obj.Controls.ApplyRF=obj.button(r,10,'Apply frequency',@(~,~)obj.rfAction());
            obj.Controls.ApplyRF.Tooltip='Retune ADC and DAC mixers and Nyquist zones. Clears model calibration and averaging.';
            pow=logical(obj.field(obj.Config,'dacPow',[1 0 0 0]));pow(end+1:4)=false;
            obj.Controls.Dac=obj.checkbox(r,11,'DAC B power','dac',pow(1),false);
            obj.Controls.DacA=obj.checkbox(r,12,'DAC A power','dacA',pow(3),false);
            obj.Controls.Dac.ValueChangedFcn=@(h,~)obj.dacAction(h);
            obj.Controls.DacA.ValueChangedFcn=@(h,~)obj.dacAction(h);
            obj.Controls.DacA.Tooltip='Both DACs play the same waveform; they add in the combiner.';
            obj.Controls.Sync=obj.dropdown(r,13,'SYNC','da',{'DAC = ADC','DAC = DAC','Free running'},'DAC = ADC',false);
            obj.Controls.Sync.ItemsData={2,1,0};obj.Controls.Sync.Value=obj.field(obj.Config,'da',2);
            obj.Accepted.da=obj.Controls.Sync.Value;
            obj.Controls.Sync.ValueChangedFcn=@(h,~)obj.syncAction(h);
            obj.Controls.Sync.Tooltip=['DAC = ADC: the DACs play during each capture, started with it. ' ...
                'DAC = DAC: both DACs start together and play continuously. Free running: no common start.'];
            obj.heading(r,15,'CONVERTER PATHS (original channel control)');
            obj.Controls.PhaseKind=obj.dropdown(r,16,'Setting','phaseKind',{'ADC mixer phase','DAC mixer phase'},'DAC mixer phase',false);
            obj.Controls.PhaseKind.ItemsData={'ADC','DAC'};obj.Controls.PhaseKind.Value='DAC';
            obj.Controls.PhaseKind.ValueChangedFcn=@(~,~)obj.phaseKind();
            for k=1:4
                obj.number(r,16+k,sprintf('Channel %d',k),sprintf('phase%d',k),obj.PhaseValues.DAC(k),[-179.99 179.99],false,'%g°');
                obj.Controls.(sprintf('phase%d',k)).ValueChangedFcn=@(~,~)obj.dirty();
                obj.Controls.(sprintf('phase%d',k)).RoundFractionalValues='on';
            end
            obj.Controls.ApplyPhase=obj.button(r,21,'Apply',@(~,~)obj.phaseAction());
            obj.Controls.ApplyPhase.Tooltip=['Write the selected converter setting. Mixer phases clear the model and 0° ' ...
                'calibration; every change clears averaging.'];
            if obj.has('calibration'),obj.Controls.Calibration=obj.button(r,23,'Load calibration…',@(~,~)obj.action('calibration',[]));end
            info=uilabel(r,'Text',['Streams 0..3 = ADC_D, ADC_C, ADC_B, ADC_A (RFSoC 4x2 manual rev A5; order checked ' ...
                'by per-ADC phase steps). DAC index 0 = DAC_B, 2 = DAC_A.'], ...
                'WordWrap','on','FontColor',th.dim,'FontSize',10,'VerticalAlignment','top');info.Layout.Row=24;info.Layout.Column=[1 2];
            if ~obj.has('rf'),obj.Controls.ApplyRF.Enable='off';end
            if ~obj.has('dac'),obj.Controls.Dac.Enable='off';obj.Controls.DacA.Enable='off';end
            if ~obj.has('sync'),obj.Controls.Sync.Enable='off';end
            if ~obj.has('phase'),obj.Controls.ApplyPhase.Enable='off';end
            % --- DSP --------------------------------------------------------
            obj.Controls.ch=obj.dropdown(q,1,'Output','ch',[{'Combined beam'} obj.AdcNames],'Combined beam',false);
            mask=true(1,4);if obj.field(obj.Config,'directOnly',false),mask=[true false false false];end
            mask=logical(obj.field(obj.Config,'availableChannels',mask));
            vals=find(mask);labels=obj.AdcNames(mask);
            if all(mask) && ~obj.field(obj.Config,'directOnly',false),vals=[5 vals];labels=[{'Combined beam'} labels];end
            obj.Controls.ch.Items=labels;obj.Controls.ch.ItemsData=num2cell(vals);
            selected=obj.field(obj.Config,'ch',5);if ~ismember(selected,vals),selected=vals(1);end
            obj.Controls.ch.Value=selected;
            obj.Controls.ch.ValueChangedFcn=@(h,~)obj.configure('ch',h.Value,h);
            obj.Accepted.ch=obj.Controls.ch.Value;
            obj.Controls.ang_num=uidropdown(q,'Items',{'OFDM (tracked)','Strongest','Weaker'},'ItemsData',{3,1,2}, ...
                'Value',obj.field(obj.Config,'ang_num',1),'BackgroundColor',th.input,'FontColor',th.text,'FontSize',11, ...
                'Tooltip',['Which direction the beam points at. OFDM (tracked): the direction whose signal carries ' ...
                'the OFDM preamble, whatever its power; without a clear one the beam stays on the last ' ...
                'identified direction. Strongest / Weaker: by steered band power.']);
            obj.Controls.ang_num.Layout.Row=2;obj.Controls.ang_num.Layout.Column=2;
            obj.label(q,2,'Signal priority');
            obj.Accepted.ang_num=obj.Controls.ang_num.Value;
            obj.Controls.ang_num.ValueChangedFcn=@(h,~)obj.configure('ang_num',h.Value,h);
            bfs={'Without','Steering','OFDM pilot MVDR','MVDR','DMR','PC','PC_corr','LCMV','RVL','RAB PC','DL MVDR','DL ITER MVDR','QCB'};
            obj.dropdown(q,3,'Beamformer','bf',bfs,char(obj.field(obj.Config,'bf','Steering')),true);
            doa={'MVDR','MUSIC','Beamscan','MUSICR','ESPRITE','ESPRITEBS','WSFR','MVDRman','MVDRman_corr'};
            obj.dropdown(q,4,'DOA estimator','doa',doa,char(obj.field(obj.Config,'doa','MVDR')),true);
            rows=double(obj.field(obj.Config,'rowsAllowed',obj.field(obj.Config,'dataChan',32768)));
            rows=sort(rows(:).');labels=cell(1,numel(rows));
            for k=1:numel(rows)
                labels{k}=sprintf('%d samples',rows(k));
                if rows(k)==4096,labels{k}='4096 · one frame, fastest';end
                if k==numel(rows) && numel(rows)>1,labels{k}=sprintf('%d · full, checked',rows(k));end
            end
            obj.Controls.rows=obj.dropdown(q,5,'Data amount','rows',labels,labels{end},false);
            obj.Controls.rows.ItemsData=num2cell(rows);
            obj.Controls.rows.Value=obj.field(obj.Config,'rows',rows(end));obj.Accepted.rows=obj.Controls.rows.Value;
            obj.Controls.rows.ValueChangedFcn=@(h,~)obj.configure('rows',h.Value,h);
            obj.Controls.rows.Tooltip=['Samples per frame. Fewer samples raise the display rate: the smallest amount holds one ' ...
                'OFDM frame. Reduced frames are checked against the reference at both ends only; the full frame ' ...
                'gets the complete continuity check.'];
            if numel(rows)<2,obj.Controls.rows.Enable='off';end
            obj.Controls.Zero=uibutton(q,'Text','Set 0°','BackgroundColor',th.input,'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.action('zero',obj.Controls.ZeroSource.Value),'Interruptible','off','BusyAction','cancel', ...
                'Tooltip',['Common-feed calibration: every ADC gets the same splitter output, so the ADC mixer phases ' ...
                'and gains are set until ADC_C, ADC_B and ADC_A match ADC_D (twice, then checked). The array model then ' ...
                'reads the loopback signal at 0°. Repeat after every new session or frequency change.']);
            obj.Controls.Zero.Layout.Row=6;obj.Controls.Zero.Layout.Column=1;
            obj.Controls.ZeroState=uilabel(q,'Text','not calibrated','FontSize',10,'FontColor',th.warn,'WordWrap','on');
            obj.Controls.ZeroState.Layout.Row=6;obj.Controls.ZeroState.Layout.Column=2;
            obj.label(q,7,'Calibrate on');
            obj.Controls.ZeroSource=uidropdown(q,'Items',{'OFDM (wideband)','CW tone'},'ItemsData',{'ofdm','cw'}, ...
                'Value','ofdm','BackgroundColor',th.input,'FontColor',th.text,'FontSize',11, ...
                'Tooltip',['Signal Set 0° measures. OFDM: the whole band of the loopback OFDM. CW tone: the strongest ' ...
                'spectral line (e.g. the MXG CW) at its own frequency, where a null on that tone has to be deep; ' ...
                'the tone then reads at 0°, so feed it to every ADC the same way (common feed).']);
            obj.Controls.ZeroSource.Layout.Row=7;obj.Controls.ZeroSource.Layout.Column=2;
            if ~obj.has('zero'),obj.Controls.Zero.Enable='off';obj.Controls.ZeroSource.Enable='off';obj.Controls.ZeroState.Text='needs board control';end
            d=obj.controlGrid(dsp,{20,28,28,28,28,28,22,24,24,24,24});
            obj.heading(d,1,'RECEIVE PROCESSING');
            obj.sourceCountButtons(d,2,obj.field(obj.Config,'num',1));
            obj.number(d,3,'Scan width','scan_bw',obj.field(obj.Config,'scan_bw',120),[2 360],true,'%g°');
            obj.number(d,4,'Scan step','scan_res',obj.field(obj.Config,'scan_res',1),[1e-4 Inf],true,'%g°');
            obj.number(d,5,'Average frames','avg_factor',obj.field(obj.Config,'avg_factor',10),[1 Inf],true,'%g');
            obj.Controls.avg_factor.RoundFractionalValues='on';
            obj.number(d,6,'Signal bandwidth','bwMHz',obj.field(obj.Config,'bw',100e6)/1e6,[1 500],false,'%g MHz');
            obj.Accepted.bw=obj.Controls.bwMHz.Value;
            obj.Controls.bwMHz.ValueChangedFcn=@(h,~)obj.bandwidth(h);
            obj.heading(d,7,'IQ / PHASE CORRECTION');
            obj.checkbox(d,8,'Adaptive IQ correction','adIQcomp',logical(obj.field(obj.Config,'adIQcomp',false)),true);
            obj.checkbox(d,9,'Static IQ correction','IQcomp',logical(obj.field(obj.Config,'IQcomp',false)),true);
            obj.Controls.IQcomp.Tooltip='Uses the frozen IQ filter learned by adaptive correction.';
            obj.checkbox(d,10,'Phase / power correction','phComp',logical(obj.field(obj.Config,'phComp',false)),true);
            cal=obj.field(obj.Config,'calibration',struct());
            if isempty(obj.field(cal,'steeringCorrection',[])) || isempty(obj.field(cal,'powCalibration',[]))
                obj.Controls.phComp.Enable='off';obj.Controls.phComp.Tooltip='Load matching steering and power calibration tables first.';
            end
            obj.Controls.CompareVsa=obj.checkbox(d,11,'Compare with native VSA','CompareVsa',string(obj.field(obj.Config,'analyzer','integrated'))~="integrated",false);
            obj.Accepted.analyzer=obj.Controls.CompareVsa.Value;
            obj.Controls.CompareVsa.ValueChangedFcn=@(h,~)obj.compareVsa(h);
            % --- Algorithms -------------------------------------------------
            a=obj.controlGrid(advanced,{20,28,28,28,28,28,28,6,22,28,28,44});
            obj.heading(a,1,'BEAMFORMER PARAMETERS');
            % Limits come from origapp.processingLimits (fitLimits), the same ranges
            % DemoSession accepts: a value that would be refused cannot be entered.
            spec={'diag','Diagonal loading',[0 Inf],'%g';'alpha','Uncertainty',[0 Inf],'%g';'gamma','Robust loading γ',[0 Inf],'%g'; ...
                'iter','Iterations',[1 Inf],'%g';'mis_ang','Mismatch angle',[0.1 20],'%g°';'alg_scan_res','Algorithm step',[0.001 10],'%g°'};
            for k=1:size(spec,1),obj.number(a,k+1,spec{k,2},spec{k,1},obj.field(obj.Config,spec{k,1},1),spec{k,3},true,spec{k,4});end
            obj.Controls.iter.RoundFractionalValues='on';
            obj.heading(a,9,'IQ FILTER PARAMETERS');
            obj.number(a,10,'Filter length','sizeL',obj.field(obj.Config,'sizeL',4),[1 50],true,'%g');
            obj.number(a,11,'LMS step μ','stepMU',obj.field(obj.Config,'stepMU',1e-16),[1e-31 1],true,'%g');
            note=uilabel(a,'Text','Only supported processing options are shown. RF changes reset current measurements.', ...
                'WordWrap','on','FontSize',10,'FontColor',th.dim,'VerticalAlignment','top');note.Layout.Row=12;note.Layout.Column=[1 2];
            % --- Monitor ----------------------------------------------------
            m=obj.controlGrid(mon,{20,100,38,20,32,28,44,20,'1x',28});
            obj.heading(m,1,'RECEIVE STREAMS · RAW CAPTURE');
            tg=uigridlayout(m,[5 6],'ColumnWidth',{34,'1x','1x','1x','1x','1x'},'RowHeight',repmat({'1x'},1,5), ...
                'RowSpacing',2,'ColumnSpacing',4,'Padding',[0 0 0 0],'BackgroundColor',th.panel);
            tg.Layout.Row=2;tg.Layout.Column=[1 2];
            heads={'ADC','dBFS','Δφ °','coh','w dB','w °'};colors={th.s1,th.s2,th.s3,th.s4};
            for c=1:6
                uilabel(tg,'Text',heads{c},'FontSize',10,'FontWeight','bold','FontColor',th.dim,'HorizontalAlignment','right');
            end
            for rr=1:4
                for c=1:6
                    h=uilabel(tg,'Text','—','FontSize',11,'FontColor',th.text,'HorizontalAlignment','right');
                    h.Layout.Row=rr+1;h.Layout.Column=c;
                    if c==1,h.Text=extractAfter(obj.AdcNames{rr},'_');h.FontColor=colors{rr};h.FontWeight='bold';end
                    obj.Monitor.cell(rr,c)=h;
                end
            end
            n=uilabel(m,'Text',['Level, phase and coherence against the first measured stream; applied weight w. ' ...
                'Conducted-path readouts, not arrival angles.'],'WordWrap','on','FontSize',10,'FontColor',th.dim, ...
                'VerticalAlignment','top');n.Layout.Row=3;n.Layout.Column=[1 2];
            obj.heading(m,4,'SESSION');
            obj.Monitor.counts=uilabel(m,'Text','No frame displayed yet','WordWrap','on','FontSize',11,'FontColor',th.muted, ...
                'VerticalAlignment','top');obj.Monitor.counts.Layout.Row=5;obj.Monitor.counts.Layout.Column=[1 2];
            obj.Controls.Vendor=uilabel(m,'Text','Native VSA comparison —','WordWrap','on', ...
                'FontColor',th.muted,'FontSize',11,'VerticalAlignment','top');obj.Controls.Vendor.Layout.Row=6;obj.Controls.Vendor.Layout.Column=[1 2];
            obj.Controls.Profile=uilabel(m,'Text','OFDM profile · awaiting data','WordWrap','on', ...
                'FontColor',th.muted,'FontSize',10,'VerticalAlignment','top');obj.Controls.Profile.Layout.Row=7;obj.Controls.Profile.Layout.Column=[1 2];
            obj.heading(m,8,'EVENT LOG');
            obj.Monitor.log=uitextarea(m,'Editable','off','Value',{'(no events yet)'},'FontSize',10, ...
                'BackgroundColor',th.bg,'FontColor',th.muted,'WordWrap','on');
            obj.Monitor.log.Layout.Row=9;obj.Monitor.log.Layout.Column=[1 2];
            obj.Controls.ClearHistory=obj.button(m,10,'Clear histories',@(~,~)obj.clearHistory());
            obj.Controls.ClearHistory.Tooltip='Forget the EVM and per-stream histories, max hold and rate estimate';
            obj.phaseKind();
            if isfield(obj.Config,'ofdmProfile'),obj.Controls.Profile.Text=obj.profileText(obj.Config.ofdmProfile);end
        end
        function g=controlGrid(obj,parent,rows)
            g=uigridlayout(parent,[numel(rows) 2],'ColumnWidth',{126,'1x'},'RowHeight',rows, ...
                'Padding',[2 6 4 6],'RowSpacing',5,'ColumnSpacing',6,'BackgroundColor',obj.Theme.panel,'Scrollable','on');
        end
        function heading(obj,g,row,text)
            h=uilabel(g,'Text',text,'FontColor',obj.Theme.dim,'FontWeight','bold','FontSize',10, ...
                'VerticalAlignment','bottom');
            h.Layout.Row=row;h.Layout.Column=[1 2];
        end
        function h=label(obj,g,row,text)
            h=uilabel(g,'Text',text,'FontColor',obj.Theme.muted,'FontSize',11);
            h.Layout.Row=row;h.Layout.Column=1;
        end
        function fitLimits(obj)
            % Field limits from origapp.processingLimits for the current settings.
            % A bound is only tightened while the shown value satisfies it, so a
            % field never errors; the session refuses anything still outside.
            L=origapp.processingLimits(obj.Config);
            keys=["num","scan_bw","scan_res","avg_factor","bwMHz","diag","alpha","gamma","iter","mis_ang","alg_scan_res"];
            for k=keys
                if ~isfield(obj.Controls,k) || ~isvalid(obj.Controls.(k)),continue,end
                h=obj.Controls.(k);lim=L.(k);op=[false false];
                if isfield(L.open,k),op=L.open.(k);end
                v=h.Value;
                inside=(v>lim(1) || (~op(1) && v==lim(1))) && (v<lim(2) || (~op(2) && v==lim(2)));
                if ~inside || lim(1)>=lim(2),continue,end
                set(h,'LowerLimitInclusive',matlab.lang.OnOffSwitchState(~op(1)), ...
                    'UpperLimitInclusive',matlab.lang.OnOffSwitchState(~op(2)),'Limits',lim);
            end
        end
        function h=number(obj,g,row,text,key,value,limits,bind,fmt)
            lh=obj.label(g,row,text);obj.Controls.([key 'Label'])=lh;
            h=uieditfield(g,'numeric','Value',value,'Limits',limits,'BackgroundColor',obj.Theme.input, ...
                'FontColor',obj.Theme.text,'FontSize',11,'ValueDisplayFormat',fmt);
            h.Layout.Row=row;h.Layout.Column=2;obj.Controls.(key)=h;obj.Accepted.(key)=value;
            if bind,h.ValueChangedFcn=@(src,~)obj.configure(key,src.Value,src);end
        end
        function h=dropdown(obj,g,row,text,key,items,value,bind)
            obj.label(g,row,text);
            h=uidropdown(g,'Items',items,'Value',value,'BackgroundColor',obj.Theme.input, ...
                'FontColor',obj.Theme.text,'FontSize',11);
            h.Layout.Row=row;h.Layout.Column=2;obj.Controls.(key)=h;obj.Accepted.(key)=value;
            if bind,h.ValueChangedFcn=@(src,~)obj.configure(key,src.Value,src);end
        end
        function h=checkbox(obj,g,row,text,key,value,bind)
            h=uicheckbox(g,'Text',text,'Value',value,'FontColor',obj.Theme.text,'FontSize',11);
            h.Layout.Row=row;h.Layout.Column=[1 2];obj.Controls.(key)=h;obj.Accepted.(key)=value;
            if bind,h.ValueChangedFcn=@(src,~)obj.configure(key,logical(src.Value),src);end
        end
        function h=button(obj,g,row,text,callback)
            h=uibutton(g,'Text',text,'BackgroundColor',obj.Theme.input,'FontColor',obj.Theme.text, ...
                'ButtonPushedFcn',callback,'Interruptible','off','BusyAction','cancel');
            h.Layout.Row=row;h.Layout.Column=[1 2];
        end
        function selectPage(obj,k)
            th=obj.Theme;obj.Page=k;
            for j=1:4
                on=j==k;
                obj.Controls.PageButton(j).Value=on;
                obj.Controls.PagePanel(j).Visible=matlab.lang.OnOffSwitchState(on);
                if on
                    set(obj.Controls.PageButton(j),'FontColor',th.text,'FontWeight','bold','BackgroundColor',th.input);
                    obj.Controls.PageRule(j).BackgroundColor=th.s1;
                else
                    set(obj.Controls.PageButton(j),'FontColor',th.muted,'FontWeight','normal','BackgroundColor',th.panel);
                    obj.Controls.PageRule(j).BackgroundColor=th.hair;
                end
            end
        end
        function configure(obj,key,value,h)
            old=h.Value;
            if isfield(obj.Accepted,key),old=obj.Accepted.(key);end
            try
                assert(obj.has('configure'),'origapp:View','Processing controls are unavailable.');
                obj.Callbacks.configure(struct(key,value));
                obj.Accepted.(key)=h.Value;
                obj.Config.(key)=value;
                obj.fitLimits();
                if strcmp(key,'scan_bw'),obj.defaultLimits('doa');obj.defaultLimits('pattern');end
                if strcmp(key,'plotMirror') && isstruct(obj.LastData),obj.show(obj.LastData);end
                obj.noError();
                obj.logEvent(sprintf('%s = %s',key,obj.valueText(value)));
            catch err
                h.Value=old;obj.showError(err.message);
            end
        end
        function sourceCountButtons(obj,g,row,value)
            % Source count as one row of buttons: Auto, 1, 2, 3 (Auto = 0: the
            % session estimates the count per frame and the button shows it).
            th=obj.Theme;obj.Controls.numLabel=obj.label(g,row,'Source count');
            s=uigridlayout(g,[1 4],'ColumnWidth',{'1.7x','1x','1x','1x'},'ColumnSpacing',2,'Padding',[0 0 0 0], ...
                'BackgroundColor',th.panel);s.Layout.Row=row;s.Layout.Column=2;
            vals=[0 1 2 3];names={'Auto','1','2','3'};
            for k=1:4
                b=uibutton(s,'state','Text',names{k},'FontSize',11,'BackgroundColor',th.panel,'FontColor',th.muted, ...
                    'ValueChangedFcn',@(~,~)obj.setSourceCount(vals(k)));
                b.Layout.Row=1;b.Layout.Column=k;obj.Controls.SourceCount(k)=b;
            end
            obj.Controls.SourceCount(1).Tooltip=['Auto: counted on every frame. Each further source must raise a ' ...
                'covariance eigenvalue 3 dB above the noise ones; the button shows the count used (Auto · n).'];
            for k=2:4,obj.Controls.SourceCount(k).Tooltip=sprintf('%d source(s) for the DOA estimator',vals(k));end
            obj.Accepted.num=value;obj.paintSourceCount(value);
        end
        function setSourceCount(obj,v)
            old=obj.Accepted.num;
            try
                assert(obj.has('configure'),'origapp:View','Processing controls are unavailable.');
                obj.Callbacks.configure(struct('num',v));
                obj.Accepted.num=v;obj.Config.num=v;obj.fitLimits();obj.noError();
                obj.logEvent(sprintf('num = %s',obj.valueText(v)));
            catch err
                v=old;obj.showError(err.message);
            end
            obj.paintSourceCount(v);
        end
        function paintSourceCount(obj,v,autoCount)
            if nargin<3,autoCount=[];end
            th=obj.Theme;vals=[0 1 2 3];
            for k=1:4
                b=obj.Controls.SourceCount(k);on=vals(k)==v;b.Value=on;
                if on,set(b,'FontColor',th.text,'FontWeight','bold','BackgroundColor',th.input);
                else,set(b,'FontColor',th.muted,'FontWeight','normal','BackgroundColor',th.panel);end
            end
            t='Auto';if v==0 && isscalar(autoCount) && isfinite(autoCount),t=sprintf('Auto · %d',autoCount);end
            if ~strcmp(obj.Controls.SourceCount(1).Text,t),obj.Controls.SourceCount(1).Text=t;end
        end
        function bandwidth(obj,h)
            obj.configure('bw',h.Value*1e6,h);obj.band();
        end
        function compareVsa(obj,h)
            mode='integrated';if h.Value,mode='both';end
            obj.configure('analyzer',mode,h);
        end
        function valueAction(obj,name,h,value)
            old=~logical(h.Value);
            try
                assert(obj.has(name),'origapp:View','This control is unavailable.');
                obj.Callbacks.(name)(value);obj.noError();
                obj.logEvent(sprintf('%s %s',name,obj.valueText(logical(value))));
            catch err
                h.Value=old;obj.showError(err.message);
            end
            if isfield(obj.Controls,'Pause') && isequal(h,obj.Controls.Pause),obj.pauseLook();end
        end
        function pauseLook(obj)
            h=obj.Controls.Pause;
            if h.Value
                set(h,'Text','Resume','BackgroundColor',obj.Theme.warnBg,'FontColor',obj.Theme.warn);
            else
                set(h,'Text','Pause','BackgroundColor',obj.Theme.input,'FontColor',obj.Theme.text);
            end
        end
        function action(obj,name,arg)
            try
                assert(obj.has(name),'origapp:View','This control is unavailable.');
                if isempty(arg),obj.Callbacks.(name)();else,obj.Callbacks.(name)(arg);end
                if strcmp(name,'start')
                    obj.Controls.Start.Enable='off';obj.Controls.Start.Text='Running';
                    obj.pill('WAITING','idle');obj.StatusLabel.Text='waiting for the first frame';
                end
                obj.noError();obj.logEvent(name);
            catch err,obj.showError(err.message);end
        end
        function snapshotAction(obj)
            try
                files=obj.saveSnapshot();
                if ~isempty(files),obj.StatusLabel.Text=['snapshot saved · ' files{1}];end
            catch err,obj.showError(err.message);end
        end
        function rfAction(obj)
            try
                assert(obj.has('rf'),'origapp:View','Frequency controls are unavailable.');
                c=obj.Controls;names=obj.RfFields;rf=struct();
                for n=names,rf.(n)=double(c.(n).Value);end
                obj.Callbacks.rf(rf);
                for n=names,obj.Accepted.(n)=c.(n).Value;end
                obj.noError();
                obj.logEvent(sprintf('RF applied · ADC %g MHz · DAC B %g MHz · DAC A %g MHz',rf.adcMHz,rf.dacMHz,rf.dac1MHz));
            catch err
                for n=obj.RfFields,obj.Controls.(n).Value=obj.Accepted.(n);end
                obj.showError(err.message);
            end
            obj.dirty();
        end
        function zeroLook(obj,z)
            th=obj.Theme;h=obj.Controls.ZeroState;
            switch string(z.state)
                case "running",h.Text='calibrating…';h.FontColor=th.muted;
                case "done"
                    on='';if isfield(z,'source') && z.source=="cw",on=sprintf(' on CW %+.1f MHz',z.toneHz/1e6);end
                    h.Text=sprintf('0° set%s %s · ±%.2f° ±%.2f dB',on,char(z.time,'HH:mm'),max(abs(z.residualDeg)),max(abs(z.levelDb)));
                    h.FontColor=th.ok;
                    obj.logEvent(sprintf('0° calibration: residual %s° · %s dB · phases %s° · gains %s', ...
                        strjoin(compose('%.2f',z.residualDeg(2:4)),'/'),strjoin(compose('%.2f',z.levelDb(2:4)),'/'), ...
                        strjoin(compose('%.2f',z.phases),'/'),strjoin(compose('%.2f',z.gains),'/')));
                case "changed",h.Text='settings changed: set 0° again';h.FontColor=th.warn;
                otherwise,h.Text='not calibrated';h.FontColor=th.warn;
            end
        end
        function dacAction(obj,h)
            % Power of DAC B / DAC A (original "Power" boxes): one dacPow command.
            mask=[logical(obj.Controls.Dac.Value) logical(obj.Controls.DacA.Value)];
            try
                assert(obj.has('dac'),'origapp:View','This control is unavailable.');
                obj.Callbacks.dac(mask);obj.noError();
                obj.logEvent(sprintf('DAC power · B %d · A %d',mask(1),mask(2)));
            catch err
                h.Value=~logical(h.Value);obj.showError(err.message);
            end
        end
        function syncAction(obj,h)
            try
                assert(obj.has('sync'),'origapp:View','This control is unavailable.');
                obj.Callbacks.sync(h.Value);obj.Accepted.da=h.Value;obj.noError();
                obj.logEvent(sprintf('SYNC mode %d',h.Value));
            catch err
                h.Value=obj.Accepted.da;obj.showError(err.message);
            end
        end
        function spec=pathSpec(~,kind)
            % label, display format, limits, two-port DAC kind
            switch kind
                case 'ADC',spec={'ADC mixer phase','%.2f°',[-179.99 179.99],false};   % ±180.00 refused by the RF data converter
                case 'DAC',spec={'DAC mixer phase','%.2f°',[-179.99 179.99],true};
                case 'adcGain',spec={'ADC gain (QMC)','%.2f',[0 1.99],false};
                case 'adcIq',spec={'ADC I/Q phase (QMC)','%.2f°',[-26.49 26.49],false};
                case 'adcAtten',spec={'ADC attenuator','%g dB',[0 27],false};
                case 'dacGain',spec={'DAC gain (QMC)','%.2f',[0 1.99],true};
                case 'dacIq',spec={'DAC I/Q phase (QMC)','%.2f°',[-26.49 26.49],true};
                case 'dacCurrent',spec={'DAC output current','%.2f mA',[2.25 40.5],true};
            end
        end
        function phaseKind(obj)
            kind=obj.Controls.PhaseKind.Value;v=obj.PhaseValues.(kind);spec=obj.pathSpec(kind);
            g=obj.Controls.phase1.Parent;rh=g.RowHeight;
            for k=1:4
                h=obj.Controls.(sprintf('phase%d',k));lab=obj.Controls.(sprintf('phase%dLabel',k));
                h.Limits=spec{3};h.ValueDisplayFormat=spec{2};h.RoundFractionalValues='off';
                h.Value=min(max(v(k),spec{3}(1)),spec{3}(2));h.Layout.Row=16+k;lab.Layout.Row=16+k;
                h.Visible='on';lab.Visible='on';lab.Text=obj.AdcNames{k};
                rh{16+k}=28;
            end
            if spec{4}
                obj.Controls.phase1Label.Text=obj.DacNames{1};
                obj.Controls.phase3Label.Text=obj.DacNames{2};
                obj.Controls.phase3.Layout.Row=18;obj.Controls.phase3Label.Layout.Row=18;
                for k=[2 4]
                    obj.Controls.(sprintf('phase%d',k)).Visible='off';
                    obj.Controls.(sprintf('phase%dLabel',k)).Visible='off';
                end
                rh{19}=0;rh{20}=0;
            end
            g.RowHeight=rh;
            if isfield(obj.Controls,'ApplyPhase'),obj.dirty();end
        end
        function phaseAction(obj)
            kind=obj.Controls.PhaseKind.Value;values=zeros(1,4);spec=obj.pathSpec(kind);
            indices=1:4;if spec{4},indices=[1 3];end
            for k=indices,values(k)=obj.Controls.(sprintf('phase%d',k)).Value;end
            try
                assert(obj.has('phase'),'origapp:View','Converter settings are unavailable.');
                obj.Callbacks.phase(struct('kind',kind,'values',values));
                obj.PhaseValues.(kind)=values;obj.noError();
                obj.logEvent(sprintf('%s applied · %s',spec{1},strjoin(compose('%g',values(indices)),' / ')));
            catch err,obj.phaseKind();obj.showError(err.message);end
            obj.dirty();
        end
        function dirty(obj)
            % Tint an Apply button while its fields differ from the last
            % values the board accepted (display hint only).
            th=obj.Theme;
            if ~isfield(obj.Controls,'ApplyRF') || ~isfield(obj.Controls,'ApplyPhase'),return,end
            rf=false;for n=obj.RfFields,rf=rf || obj.Controls.(n).Value~=obj.Accepted.(n);end
            kind=obj.Controls.PhaseKind.Value;v=obj.PhaseValues.(kind);
            indices=1:4;spec=obj.pathSpec(kind);if spec{4},indices=[1 3];end
            ph=false;for k=indices,ph=ph || obj.Controls.(sprintf('phase%d',k)).Value~=v(k);end
            pairs={obj.Controls.ApplyRF,rf;obj.Controls.ApplyPhase,ph};
            for k=1:2
                if pairs{k,2},set(pairs{k,1},'BackgroundColor',th.accent,'FontWeight','bold');
                else,set(pairs{k,1},'BackgroundColor',th.input,'FontWeight','normal');end
            end
        end
        function showError(obj,text)
            text=char(string(text));
            obj.Controls.Error.Text=text;obj.Controls.Error.Visible='on';
            obj.Controls.SideGrid.RowHeight{5}=44;
            obj.StatusLabel.Text=['control refused · ' text];
            obj.StatusLabel.FontColor=obj.Theme.warn;
            obj.logEvent("REFUSED · "+string(text));
        end
        function noError(obj)
            obj.Controls.Error.Text='';obj.Controls.Error.Visible='off';
            obj.Controls.SideGrid.RowHeight{5}=0;
        end
        function showAnalysis(obj,r,seq)
            th=obj.Theme;
            c=r.constellation;
            obj.setLine('payload',real(c.payload),imag(c.payload));
            obj.setLine('header',real(c.header),imag(c.header));
            obj.setLine('pilots',real(c.pilot),imag(c.pilot));
            obj.setp(obj.Empty.constellation,'Visible','off');
            ev=r.evmPercent;db=r.evmDb;
            degraded=logical(obj.field(r,'degraded',false));
            state='ok';if degraded,state='warn';end
            obj.appendEvm(seq,r);
            hist=obj.HistoryEvm;
            obj.tile('evm',sprintf('%.2f %%',ev),sprintf('median %.2f · max %.2f · n=%d',median(hist),max(hist),numel(hist)),state);
            obj.tile('evmDb',sprintf('%.1f dB',db),sprintf('header %.2f %% · pilots %.2f %%', ...
                obj.field(r,'headerEvmPercent',NaN),obj.field(r,'pilotEvmPercent',NaN)),state);
            obj.EvmNow=[seq ev];
            sc=obj.field(r,'evmPerSubcarrierPercent',[]);sx=obj.field(r,'evmSubcarrier',[]);
            if numel(sx)~=numel(sc),sx=1:numel(sc);end
            sy=obj.field(r,'evmPerSymbolPercent',[]);yx=obj.field(r,'evmSymbolIndex',[]);
            if numel(yx)~=numel(sy),yx=1:numel(sy);end
            obj.EvmSub=struct('x',sx,'y',sc);obj.EvmSym=struct('x',yx,'y',sy);
            obj.drawEvm();
            obj.setp(obj.Empty.evm,'Visible','off');
            switch obj.EvmMode
                case 'history'
                    obj.put(obj.Card.evm.note,obj.count(numel(hist),'frame'));
                case 'subcarrier'
                    [worst,ix]=max(sc);
                    if isempty(sc),obj.put(obj.Card.evm.note,sprintf('frame %g · unavailable',seq));
                    else,obj.put(obj.Card.evm.note,sprintf('worst %.1f %% at k=%g',worst,sx(ix)));end
                case 'symbol'
                    [worst,ix]=max(sy);
                    if isempty(sy),obj.put(obj.Card.evm.note,sprintf('frame %g · unavailable',seq));
                    else,obj.put(obj.Card.evm.note,sprintf('worst %.1f %% at row %g',worst,yx(ix)));end
            end
            if isfield(r,'profile'),obj.put(obj.Controls.Profile,obj.profileText(r.profile));end
            qualified=obj.field(r,'qualifiedBursts',NaN);complete=obj.field(r,'metricBursts',NaN);
            secondary=obj.field(r,'qualifiedPayloadEvmPercent',NaN);
            tag='LOCKED';if degraded,tag='DEGRADED';end
            clean='clean-only —';if isfinite(secondary),clean=sprintf('clean-only %.2f %%',secondary);end
            obj.put(obj.CoverageLabel,sprintf('%s · %g/%g qualified · %s',tag,qualified,complete,clean));
            obj.setp(obj.CoverageLabel,'FontColor',th.(state));
            obj.setp(obj.CoverageLabel,'Tooltip',char(string(obj.field(r,'reason',''))));
            obj.tile('bursts',sprintf('%g / %g',qualified,complete),clean,state);
            cfo=median(obj.field(r,'cfoHz',NaN),'omitnan');
            ppm=obj.field(r,'samplingErrorPpm',NaN);
            obj.tile('cfo',obj.hz(cfo),sprintf('pilot timing drift %+.2f ppm',ppm),'ok');
            snr=median(obj.field(r,'trainingSnrDb',NaN),'omitnan');
            obj.tile('sync',sprintf('%.2f',obj.field(r,'syncPeak',NaN)),sprintf('training SNR %.1f dB',snr),'ok');
            obj.put(obj.Card.constellation.note,sprintf('frame %g · %d cells',seq,numel(c.payload)));
            pb=obj.field(r,'perBurst',[]);cand=obj.field(r,'candidates',[]);
            obj.showBursts(cand,pb);
            if degraded && ~(numel(obj.HistoryDegraded)>1 && obj.HistoryDegraded(end-1))
                why='';
                if isstruct(pb) && isfield(pb,'qualified') && isfield(pb,'rejectionReason')
                    bad=find(~[pb.qualified],1);
                    if ~isempty(bad),why=[' · ' char(string(pb(bad).rejectionReason))];end
                end
                obj.logEvent(sprintf('frame %g degraded · %g/%g bursts qualified%s',seq,qualified,complete,why));
            end
        end
        function showLevel(obj,analysis,ch)
            rx=obj.field(analysis,'rxLevelDbfs',NaN);
            if ~isfinite(rx),return,end
            state='ok';sub=sprintf('output peak %.1f dBFS',obj.field(analysis,'peakDbfs',NaN));
            if isstruct(ch) && isfield(ch,'peakDbfs') && any(isfinite(ch.peakDbfs))
                pk=max(ch.peakDbfs);sub=sprintf('ADC peak %.1f dBFS',pk);
                clip=sum(obj.field(ch,'clipCount',0));
                if clip>0,state='fault';sub=sprintf('%s · %d at full scale',sub,clip);
                elseif pk>-1,state='fault';sub=[sub ' · near full scale'];
                elseif pk>-6,state='warn';end
            end
            obj.tile('rx',sprintf('%.1f dBFS',rx),sub,state);
        end
        function showSpectrum(obj,f,p)
            obj.setLine('spectrum',f,p);
            if numel(obj.SpectrumHold)~=numel(p),obj.SpectrumHold=p;else,obj.SpectrumHold=max(obj.SpectrumHold,p);end
            if obj.Controls.MaxHold.Value,obj.setLine('spectrumHold',f,obj.SpectrumHold);end
            lin=10.^(p/10);tot=sum(lin);note='';
            if tot>0 && numel(p)>2
                c=cumsum(lin)/tot;lo=f(find(c>=.005,1));hi=f(find(c>=.995,1));
                note=sprintf('99 %% power in %.1f MHz',hi-lo);
            end
            obj.put(obj.Card.spectrum.note,note);
        end
        function maxHold(obj)
            on=obj.Controls.MaxHold.Value;th=obj.Theme;
            obj.Lines.spectrumHold.Visible=matlab.lang.OnOffSwitchState(on);
            if on
                set(obj.Controls.MaxHold,'FontColor',th.text,'BackgroundColor',th.accent);
                obj.SpectrumHold=obj.Lines.spectrum.YData(:);
                if all(isnan(obj.SpectrumHold)),obj.SpectrumHold=[];end
            else
                set(obj.Controls.MaxHold,'FontColor',th.muted,'BackgroundColor',th.input);
                obj.setLine('spectrumHold',[],[]);
            end
        end
        function band(obj)
            if isempty(obj.Marks.band) || ~isvalid(obj.Marks.band),return,end
            bw=obj.field(obj.Config,'bw',NaN)/1e6;
            if isfinite(bw) && bw>0
                obj.Marks.band.Value=[-bw/2 bw/2];obj.Marks.band.Visible='on';
            else
                obj.Marks.band.Visible='off';
            end
        end
        function recordFrame(obj,s)
            % Every processed frame, drawn or not (no graphics): the EVM and
            % channel histories, their gap marks and the frame rate stay per
            % frame when the window is redrawn less often than frames arrive.
            if ~obj.isOpen(),return,end
            if obj.Held || ~isfield(s,'valid') || ~s.valid
                obj.GapPending=true;obj.ChannelGap=true;return
            end
            seq=obj.field(s,'sequence',NaN);
            if seq==obj.RecordedSequence,return,end
            obj.RecordedSequence=seq;
            obj.FrameTimes(end+1)=toc(obj.Clock);
            if numel(obj.FrameTimes)>9,obj.FrameTimes(1)=[];end
            obj.appendChannels(seq,obj.field(s,'channels',[]));
            r=obj.field(s,'analysis',[]);
            if isstruct(r) && isfield(r,'valid') && r.valid,obj.appendEvm(seq,r);
            else,obj.GapPending=true;end
        end
        function appendEvm(obj,seq,r)
            if isempty(obj.HistorySequence) || seq~=obj.HistorySequence(end)
                % A rejected or skipped acquisition breaks the history line:
                % it is never drawn as if frames in between were measured.
                gap=~isempty(obj.HistorySequence) && (obj.GapPending || seq-obj.HistorySequence(end)~=1);
                obj.HistorySequence(end+1)=seq;obj.HistoryEvm(end+1)=r.evmPercent;
                obj.HistoryDegraded(end+1)=logical(obj.field(r,'degraded',false));
                obj.HistoryBreak(end+1)=gap;
                if numel(obj.HistorySequence)>300
                    obj.HistorySequence(1)=[];obj.HistoryEvm(1)=[];obj.HistoryDegraded(1)=[];obj.HistoryBreak(1)=[];
                end
            end
            obj.GapPending=false;
        end
        function appendChannels(obj,seq,ch)
            if ~isstruct(ch) || ~isfield(ch,'relPhaseDeg') || ~isfinite(seq),return,end
            if ~isempty(obj.ChannelSequence) && obj.ChannelSequence(end)==seq,return,end
            row=nan(1,4);lev=nan(1,4);n=min(4,numel(ch.relPhaseDeg));
            row(1:n)=ch.relPhaseDeg(1:n);lev(1:n)=ch.levelDbfs(1:n);
            % Same rule as the EVM history: never join across rejected,
            % skipped or held acquisitions.
            gap=~isempty(obj.ChannelSequence) && (obj.ChannelGap || seq-obj.ChannelSequence(end)~=1);
            obj.ChannelGap=false;
            obj.ChannelSequence(end+1)=seq;obj.ChannelPhase(end+1,:)=row;obj.ChannelLevel(end+1,:)=lev;
            obj.ChannelBreak(end+1)=gap;
            if numel(obj.ChannelSequence)>300
                obj.ChannelSequence(1)=[];obj.ChannelPhase(1,:)=[];obj.ChannelLevel(1,:)=[];obj.ChannelBreak(1)=[];
            end
        end
        function drawTime(obj,samples,fs)
            if ~isempty(samples)
                [t,yi,yq]=obj.envelope(samples(:),fs);
                obj.setLine('timeI',t,yi);obj.setLine('timeQ',t,yq);
            else
                obj.setLine('timeI',[],[]);obj.setLine('timeQ',[],[]);
            end
        end
        function drawChannels(obj)
            % The eight history lines are drawn only while their view is shown.
            if isempty(obj.ChannelSequence) || strcmp(obj.TimeMode,'iq'),return,end
            pos=(1:numel(obj.ChannelSequence))+cumsum(logical(obj.ChannelBreak));
            x=nan(1,pos(end));x(pos)=obj.ChannelSequence;
            colors={obj.Theme.s1,obj.Theme.s2,obj.Theme.s3,obj.Theme.s4};
            for k=1:4
                yp=nan(1,pos(end));yl=yp;yp(pos)=obj.ChannelPhase(:,k);yl(pos)=obj.ChannelLevel(:,k);
                set(obj.Lines.chPhase(k),'XData',x,'YData',yp,'Color',colors{k});
                set(obj.Lines.chLevel(k),'XData',x,'YData',yl,'Color',colors{k});
            end
        end
        function showChannels(obj,ch,w)
            th=obj.Theme;T=obj.Monitor.cell;
            have=isstruct(ch) && isfield(ch,'levelDbfs');
            w=w(:).';wdb=nan(1,4);wph=nan(1,4);
            if numel(w)==4 && all(isfinite(w)) && any(abs(w)>0)
                % One weight per stream only: a single-stream output carries
                % one weight, which is not attributed to a row here.
                n=4;[~,ref]=max(abs(w(1:n)));
                wdb(1:n)=20*log10(abs(w(1:n))/abs(w(ref))+realmin);
                wph(1:n)=angle(w(1:n)/w(ref))*180/pi;
                wph(abs(w(1:n))==0)=NaN;
            end
            for k=1:4
                vals={NaN,NaN,NaN,wdb(k),wph(k)};
                if have && k<=numel(ch.levelDbfs)
                    vals(1:3)={ch.levelDbfs(k),ch.relPhaseDeg(k),ch.coherence(k)};
                end
                fmt={'%.1f','%+.1f','%.3f','%.1f','%+.1f'};
                for c=1:5
                    if isfinite(vals{c}),text=sprintf(fmt{c},vals{c});color=th.text;
                    else,text='—';color=th.dim;end
                    if c==1 && have && k<=numel(ch.peakDbfs) && isfinite(ch.peakDbfs(k)) && ch.peakDbfs(k)>-1
                        color=th.fault;
                    end
                    obj.put(T(k,c+1),text);obj.setp(T(k,c+1),'FontColor',color);
                end
            end
        end
        function timeMode(obj)
            mode=obj.Controls.TimeMode.Value;obj.TimeMode=mode;th=obj.Theme;ax=obj.Ax.time;
            iq=strcmp(mode,'iq');
            set([obj.Lines.timeI obj.Lines.timeQ obj.Lines.burstOk obj.Lines.burstBad],'Visible',matlab.lang.OnOffSwitchState(iq));
            set(obj.Lines.chPhase,'Visible',matlab.lang.OnOffSwitchState(strcmp(mode,'phase')));
            set(obj.Lines.chLevel,'Visible',matlab.lang.OnOffSwitchState(strcmp(mode,'level')));
            switch mode
                case 'iq'
                    xlabel(ax,'Time (µs) · min/max per display bin');ylabel(ax,'Amplitude');
                case 'phase'
                    xlabel(ax,'Acquisition sequence');ylabel(ax,'Phase vs first stream (°)');
                case 'level'
                    xlabel(ax,'Acquisition sequence');ylabel(ax,'Mean level (dBFS)');
            end
            obj.keys();
            if ~iq,obj.Empty.time.Visible='off';end
            if iq && isstruct(obj.LastData)
                obj.drawTime(obj.field(obj.LastData,'samples',[]),obj.field(obj.LastData,'fsHz',obj.field(obj.Config,'fsRfsoc',125e6)));
            end
            obj.drawChannels();
            obj.pad();obj.defaultLimits('time');
            n=0;fs=NaN;
            if isstruct(obj.LastData)
                n=numel(obj.field(obj.LastData,'samples',[]));
                fs=obj.field(obj.LastData,'fsHz',obj.field(obj.Config,'fsRfsoc',125e6));
            end
            obj.timeNote(n,fs);
        end
        function timeNote(obj,n,fs)
            switch obj.TimeMode
                case 'iq'
                    if n>0,text=sprintf('%d samples · %.4g MS/s',n,fs/1e6);
                    else,text='unavailable';end
                otherwise
                    text=obj.count(numel(obj.ChannelSequence),'frame');
                    if isempty(obj.LastData) && ~isempty(obj.ChannelSequence)
                        text=sprintf('History only · last valid frame %g',obj.ChannelSequence(end));
                    end
            end
            obj.Card.time.note.Text=text;
        end
        function evmMode(obj)
            mode=obj.Controls.EvmMode.Value;obj.EvmMode=mode;ax=obj.Ax.evm;
            hist=strcmp(mode,'history');
            set([obj.Lines.evmHistory obj.Lines.evmFlagged obj.Lines.evmCurrent],'Visible',matlab.lang.OnOffSwitchState(hist));
            obj.Marks.evmMedian.Visible=matlab.lang.OnOffSwitchState(hist && numel(obj.HistoryEvm)>2);
            obj.Lines.evmSub.Visible=matlab.lang.OnOffSwitchState(strcmp(mode,'subcarrier'));
            obj.Lines.evmSym.Visible=matlab.lang.OnOffSwitchState(strcmp(mode,'symbol'));
            switch mode
                case 'history',xlabel(ax,'Acquisition sequence');ylabel(ax,['Payload EVM (' obj.unitName() ')']);
                    obj.Card.evm.note.Text=obj.count(numel(obj.HistoryEvm),'frame');
                case 'subcarrier',xlabel(ax,'Subcarrier index');ylabel(ax,['Payload EVM (' obj.unitName() ')']);
                    obj.Card.evm.note.Text='current frame';
                case 'symbol',xlabel(ax,'Burst row (0-based) · header and payload rows');ylabel(ax,['EVM (' obj.unitName() ')']);
                    obj.Card.evm.note.Text='current frame';
            end
            obj.evmPad();obj.defaultLimits('evm');
            current=any(isfinite(obj.Lines.evmCurrent.YData));
            if ~hist && ~current,obj.emptyState('evm','NO CURRENT FRAME','per-frame view needs a demodulated frame');
            else,obj.Empty.evm.Visible='off';end
        end
        function defaultLimits(obj,name)
            ax=obj.Ax.(name);ax.XLimMode='auto';ax.YLimMode='auto';
            half=obj.field(obj.Config,'scan_bw',NaN)/2;base=NaN;
            switch name
                case 'doa',ax.YLim=[0 1.05];if isfinite(half) && half>0,ax.XLim=[-half half];end
                case 'pattern',ax.YLim=[-60 0];if isfinite(half) && half>0,ax.XLim=[-half half];end
                case 'evm',if strcmp(obj.EvmUnit,'percent'),base=0;end
                case 'constellation',ax.XLim=[-1.45 1.45];ax.YLim=[-1.45 1.45];
            end
            % Dimensions left automatic are managed by holdLimits from now on
            % (again after a user zoom only through Fit plots).
            obj.Managed.(name)=struct('x',strcmp(ax.XLimMode,'auto'),'y',strcmp(ax.YLimMode,'auto'), ...
                'lx',[],'ly',[],'base',base);
            obj.holdLimits(name);
        end
        function holdLimits(obj,names)
            % MATLAB's automatic limits are recomputed and re-sent on every
            % redraw (about 20 ms of a 60 ms render). The view sets the limits
            % itself and changes them only when the data leaves them or uses
            % less than half of them. A limit that differs from the one last
            % set was zoomed or panned by the user and is left alone.
            if nargin<2,names=fieldnames(obj.Managed);else,names=cellstr(names);end
            for k=1:numel(names)
                name=names{k};if ~isfield(obj.Managed,name),continue,end
                m=obj.Managed.(name);ax=obj.Ax.(name);
                h=findobj(ax,'-property','YData','Visible','on');
                for d='xy'
                    if ~m.(d),continue,end
                    D=upper(d);cur=ax.([D 'Lim']);last=m.(['l' d]);
                    if (isempty(last) && strcmp(ax.([D 'LimMode']),'manual')) || (~isempty(last) && ~isequal(cur,last))
                        m.(d)=false;continue
                    end
                    v=get(h,[D 'Data']);if ~iscell(v),v={v};end
                    v=cellfun(@(a)double(a(:)),v,'UniformOutput',false);v=vertcat(v{:});v=v(isfinite(v));if isempty(v),continue,end
                    lo=min(v);hi=max(v);fl=NaN;if d=='y',fl=m.base;end
                    if isfinite(fl),lo=min(lo,fl);end
                    span=hi-lo;if span<=0,span=max(abs(hi),1)*.1;end
                    margin=0;slack=.15;if d=='y',margin=.04;slack=.1;end
                    want=[lo-margin*span hi+margin*span];if isfinite(fl),want(1)=fl;end
                    if isempty(last) || want(1)<cur(1) || want(2)>cur(2) || diff(want)<.5*diff(cur)
                        new=[want(1)-slack*span want(2)+slack*span];if isfinite(fl),new(1)=fl;end
                        ax.([D 'Lim'])=new;m.(['l' d])=ax.([D 'Lim']);
                    end
                end
                obj.Managed.(name)=m;
            end
        end
        function pad(obj)
            % Invisible anchor that keeps automatic limits clear of the series key.
            x=NaN;y=NaN;
            switch obj.TimeMode
                case 'iq'
                    top=max(abs([obj.Lines.timeI.YData(:);obj.Lines.timeQ.YData(:)]),[],'omitnan');
                    if ~isempty(top) && isfinite(top) && top>0,x=[0 0];y=[-1 1.32]*top;end
                otherwise
                    v=obj.ChannelLevel;if strcmp(obj.TimeMode,'phase'),v=obj.ChannelPhase;end
                    v=v(isfinite(v));
                    if ~isempty(v)
                        span=max(1,max(v)-min(v));x=obj.ChannelSequence(1)*[1 1];y=[min(v)-.15*span max(v)+.4*span];
                    end
            end
            set(obj.Lines.timePad,'XData',x,'YData',y);
        end
        function drawEvm(obj)
            % All EVM series in the selected unit, from the stored percent values.
            hist=obj.HistoryEvm;
            if isempty(hist)
                for n=["evmHistory","evmFlagged"],obj.setLine(char(n),[],[]);end
                obj.Marks.evmMedian.Visible='off';
            else
                pos=(1:numel(hist))+cumsum(logical(obj.HistoryBreak));
                hx=nan(1,pos(end));hy=hx;hx(pos)=obj.HistorySequence;hy(pos)=obj.unit(hist);
                obj.setLine('evmHistory',hx,hy);
                flag=logical(obj.HistoryDegraded);
                obj.setLine('evmFlagged',obj.HistorySequence(flag),obj.unit(hist(flag)));
                obj.Marks.evmMedian.Value=obj.unit(median(hist));
                obj.Marks.evmMedian.Visible=matlab.lang.OnOffSwitchState(strcmp(obj.EvmMode,'history') && numel(hist)>2);
            end
            if isfinite(obj.EvmNow(2)),obj.setLine('evmCurrent',obj.EvmNow(1),obj.unit(obj.EvmNow(2)));end
            obj.setLine('evmSub',obj.EvmSub.x,obj.unit(obj.EvmSub.y));
            obj.setLine('evmSym',obj.EvmSym.x,obj.unit(obj.EvmSym.y));
            obj.evmPad();
        end
        function y=unit(obj,percent)
            y=percent;
            if strcmp(obj.EvmUnit,'db'),y=20*log10(max(percent,realmin)/100);end
        end
        function evmUnit(obj)
            if obj.Controls.EvmUnit.Value,obj.EvmUnit='db';obj.Controls.EvmUnit.Text='dB';
            else,obj.EvmUnit='percent';obj.Controls.EvmUnit.Text='%';end
            obj.drawEvm();obj.evmMode();
        end
        function text=unitName(obj)
            text='%';if strcmp(obj.EvmUnit,'db'),text='dB';end
        end
        function evmPad(obj)
            % Invisible anchor: headroom above the highest plotted EVM value.
            switch obj.EvmMode
                case 'history',h=obj.Lines.evmHistory;
                case 'subcarrier',h=obj.Lines.evmSub;
                otherwise,h=obj.Lines.evmSym;
            end
            ok=isfinite(h.YData) & isfinite(h.XData);x=NaN;y=NaN;
            if any(ok)
                x=h.XData(find(ok,1));
                if strcmp(obj.EvmUnit,'db'),y=max(h.YData(ok))+2;else,y=1.18*max(h.YData(ok));end
            end
            set(obj.Lines.evmPad,'XData',x,'YData',y);
        end
        function showBursts(obj,cand,pb)
            % Burst starts found in the analysed buffer, drawn above the trace.
            if ~isstruct(cand) || isempty(cand) || ~isfield(cand,'start')
                obj.setLine('burstOk',[],[]);obj.setLine('burstBad',[],[]);return
            end
            start=[cand.start];good=true(size(start));
            if isfield(cand,'accepted'),good=logical([cand.accepted]);end
            if isstruct(pb) && isfield(pb,'start') && isfield(pb,'qualified')
                good(ismember(start,[pb(~[pb.qualified]).start]))=false;
            end
            t=(start-1)/obj.LastFs*1e6;
            top=max(abs([obj.Lines.timeI.YData(:);obj.Lines.timeQ.YData(:)]),[],'omitnan');
            if isempty(top) || ~isfinite(top) || top==0,top=1;end
            y=1.12*top*ones(size(t));
            obj.setLine('burstOk',t(good),y(good));obj.setLine('burstBad',t(~good),y(~good));
        end
        function holdAction(obj)
            want=logical(obj.Controls.Hold.Value);
            if want && isempty(obj.LastData)
                obj.Controls.Hold.Value=false;want=false;
                obj.logEvent('hold refused · no current frame on screen');
            end
            obj.Held=want;obj.holdLook();
            if want
                obj.put(obj.StatusLabel,sprintf('HELD frame %g  ·  NOT LIVE',obj.LastSequence));
                obj.StatusLabel.FontColor=obj.Theme.warn;obj.pill('HELD','warn');
                obj.logEvent(sprintf('hold · frame %g',obj.LastSequence));
            elseif ~isempty(obj.LastData)
                obj.put(obj.StatusLabel,'hold released · waiting for the next frame');
                obj.StatusLabel.FontColor=obj.Theme.muted;obj.pill('WAITING','idle');
                obj.SeenSequence=NaN;obj.logEvent('hold released');
            end
        end
        function toggleTheme(obj)
            if strcmp(obj.ThemeName,'dark'),obj.setTheme('light');else,obj.setTheme('dark');end
        end
        function themeLook(obj)
            if strcmp(obj.ThemeName,'dark'),obj.Controls.ThemeSwitch.Text='☀ Light';
            else,obj.Controls.ThemeSwitch.Text='☾ Dark';end
        end
        function holdLook(obj)
            h=obj.Controls.Hold;name='RFSoC 4x2 Beamformer';
            if obj.Held
                set(h,'Text','Release','BackgroundColor',obj.Theme.warnBg,'FontColor',obj.Theme.warn);
                name=[name ' — HELD, NOT LIVE'];
            else
                set(h,'Text','Hold','BackgroundColor',obj.Theme.input,'FontColor',obj.Theme.text);
            end
            if ~startsWith(obj.Figure.Name,'SYNTHETIC'),obj.Figure.Name=name;end
        end
        function onKey(obj,e)
            % Function keys only: plain keys would fire while a value is typed.
            if ~isempty(e.Modifier),return,end
            switch e.Key
                case 'f2',obj.snapshotAction();
                case 'f3',obj.Controls.Hold.Value=~obj.Controls.Hold.Value;obj.holdAction();
                case 'f5',obj.fitPlots();
                case 'f6',obj.toggleSidebar();
                case 'f7',obj.toggleTheme();
                case 'f8'
                    h=obj.Controls.Pause;
                    if strcmp(h.Enable,'on'),h.Value=~h.Value;obj.valueAction('pause',h,logical(h.Value));end
            end
        end
        function mark(obj,name,angles,roles)
            % Direction markers: the first is where the beam points (solid, ok
            % colour); others are dashed in the warning colour, labelled with their
            % strength relative to the strongest direction.
            if nargin<4,roles=obj.directionRoles(angles,nan(size(angles)),"");end
            m=obj.Marks.(name);th=obj.Theme;
            for k=1:numel(m)
                if k<=numel(angles)
                    obj.setp(m(k),'Value',angles(k));obj.setp(m(k),'Label',roles.text{k});
                    if k==1,c=th.ok;st='-';lw=1.6;else,c=th.warn;st='--';lw=1.2;end
                    obj.setp(m(k),'Color',c);obj.setp(m(k),'LineStyle',st);obj.setp(m(k),'LineWidth',lw);
                    % label on the side of the line with more room (a label near
                    % the left limit was clipped); alternate when both have room
                    lim=m(k).Parent.XLim;room=[angles(k)-lim(1) lim(2)-angles(k)]/max(diff(lim),eps);
                    side='right';if mod(k,2)==0,side='left';end
                    if room(1)<.35,side='right';elseif room(2)<.35,side='left';end
                    obj.setp(m(k),'LabelHorizontalAlignment',side);obj.setp(m(k),'Visible','on');
                else
                    obj.setp(m(k),'Visible','off');
                end
            end
        end
        function r=directionRoles(~,angles,powerDb,bf,sync,tracked)
            % Names and labels per direction, in the processing order (first =
            % where the beam points, chosen by Signal priority). Strength comes from
            % the steered band power of each direction, as the priority uses; with
            % priority OFDM (tracked) each also shows its OFDM preamble correlation,
            % and "(tracked)" when the beam held the last identified direction.
            if nargin<5,sync=nan(size(angles));end
            if nargin<6,tracked=false;end
            n=numel(angles);r=struct('name',{cell(1,n)},'text',{cell(1,n)});
            strong=NaN;if n>=2 && all(isfinite(powerDb)),[~,strong]=max(powerDb);end
            for k=1:n
                if k==1,nm='beam';elseif bf=="LCMV",nm='null';else,nm='other';end
                t=sprintf('%s %.1f°',nm,angles(k));
                if k<=numel(sync) && isfinite(sync(k)),t=sprintf('%s OFDM %.2f',t,sync(k));end
                if k==1 && tracked,t=[t ' (tracked)'];end
                if isfinite(strong)
                    if k==strong,t=[t ' strong'];else,t=sprintf('%s weak %+.0f dB',t,powerDb(k)-powerDb(strong));end
                end
                r.name{k}=nm;r.text{k}=t;
            end
        end
        function emptyState(obj,name,headline,reason)
            h=obj.Empty.(name);
            lines=[{char(headline)},obj.wrap(char(string(reason)),36)];
            h.String=lines;h.Visible='on';
        end
        function tile(obj,key,value,sub,state)
            th=obj.Theme;t=obj.Kpi.(key);
            obj.put(t.value,value);obj.put(t.sub,sub);
            switch state
                case 'ok',fc=th.text;bc=th.ok;
                case 'warn',fc=th.warn;bc=th.warn;
                case 'fault',fc=th.fault;bc=th.fault;
                otherwise,fc=th.dim;bc=th.hair;
            end
            obj.setp(t.value,'FontColor',fc);obj.setp(t.edge,'BackgroundColor',bc);
        end
        function pill(obj,text,state)
            th=obj.Theme;obj.put(obj.StatePill,text);
            switch state
                case 'ok',bc=th.okBg;fc=th.ok;
                case 'warn',bc=th.warnBg;fc=th.warn;
                case 'fault',bc=th.faultBg;fc=th.fault;
                otherwise,bc=th.input;fc=th.muted;
            end
            obj.setp(obj.StatePill,'BackgroundColor',bc);obj.setp(obj.StatePill,'FontColor',fc);
        end
        function showRate(obj)
            rate=NaN;
            if numel(obj.FrameTimes)>=3,rate=1/median(diff(obj.FrameTimes));end
            text='—';state='idle';
            if isfinite(rate),text=sprintf('%.2f /s',rate);state='ok';end
            if isempty(obj.LastData),state='idle';end
            h=obj.Health;
            if isstruct(h) && isfield(h,'accepted')
                rejected=h.boundary+h.noSignal+h.expired;
                sub=sprintf('%d accepted · %d rejected',h.accepted,rejected);
                counts=sprintf('accepted %d · other errors %d\nrejected: boundary %d · no signal %d · expired %d\ndiscarded after a settings change: %d', ...
                    h.accepted,max(0,h.errors-rejected),h.boundary,h.noSignal,h.expired,obj.field(h,'settings',0));
            else
                sub=sprintf('%d shown · %d cleared',obj.FramesShown,obj.FramesCleared);
                counts=sprintf('%d fresh frames displayed · %d display clears',obj.FramesShown,obj.FramesCleared);
            end
            obj.tile('rate',text,sub,state);
            obj.put(obj.Monitor.counts,counts);
        end
        function logEvent(obj,text)
            line=[char(datetime('now','Format','HH:mm:ss')) '  ' char(string(text))];
            obj.EventLog=[{line} obj.EventLog];
            if numel(obj.EventLog)>80,obj.EventLog(81:end)=[];end
            if isfield(obj.Monitor,'log') && isvalid(obj.Monitor.log)
                obj.Monitor.log.Value=obj.EventLog(:);
            end
        end
        function showVendor(obj,v,seq)
            if ~isstruct(v) || ~isfield(v,'valid') || ~v.valid
                obj.put(obj.Controls.Vendor,'Native VSA — no current measurement');
                obj.setp(obj.Controls.Vendor,'FontColor',obj.Theme.muted);
            elseif ~isfield(v,'sequence') || v.sequence~=seq
                obj.put(obj.Controls.Vendor,'Native VSA — waiting for this frame');
                obj.setp(obj.Controls.Vendor,'FontColor',obj.Theme.muted);
            else
                obj.put(obj.Controls.Vendor,sprintf('Native VSA comparison: %.2f%% / %.1f dB',v.evmPercent,20*log10(v.evmPercent/100)));
                obj.setp(obj.Controls.Vendor,'FontColor',obj.Theme.ok);
            end
        end
        function text=profileText(obj,p)
            text=sprintf('%s · FFT %g / CP %g\n%g MHz system · %g MS/s ADC\n%g data + %g pilot subcarriers', ...
                string(obj.field(p,'payloadModulation','OFDM')),obj.field(p,'fftLength',NaN),obj.field(p,'cpSamples',NaN), ...
                obj.field(p,'systemRateHz',NaN)/1e6,obj.field(p,'receiveRateHz',NaN)/1e6, ...
                obj.field(p,'dataSubcarriers',NaN),numel(obj.field(p,'pilotSubcarriers',[])));
        end
        function clearAnalysis(obj,why)
            th=obj.Theme;why=char(string(why));
            for n=["payload","header","pilots","evmCurrent","evmSub","evmSym","burstOk","burstBad"],obj.setLine(char(n),[],[]);end
            obj.EvmSub=struct('x',[],'y',[]);obj.EvmSym=obj.EvmSub;obj.EvmNow=[NaN NaN];
            obj.GapPending=true;
            for n=["evm","evmDb","cfo","sync","bursts"],obj.tile(char(n),'—','','idle');end
            obj.CoverageLabel.Text=why;obj.CoverageLabel.FontColor=th.warn;
            obj.Lines.evmHistory.Color=th.dim;
            obj.Card.constellation.note.Text='unavailable';
            obj.emptyState('constellation','NO DEMODULATED FRAME',why);
            if strcmp(obj.EvmMode,'history')
                if isempty(obj.HistorySequence)
                    obj.Card.evm.note.Text='no current value';
                    obj.emptyState('evm','NO EVM YET',why);
                else
                    obj.Card.evm.note.Text=sprintf('History only · last valid frame %g',obj.HistorySequence(end));
                    obj.Empty.evm.Visible='off';
                end
            else
                obj.Card.evm.note.Text='unavailable';
                obj.emptyState('evm','NO CURRENT FRAME',why);
            end
        end
        function setLine(obj,name,x,y)
            if isempty(x) || isempty(y),x=NaN;y=NaN;end
            set(obj.Lines.(name),'XData',x(:),'YData',y(:));
        end
        function toggleSidebar(obj)
            obj.UserSidebar=strcmp(obj.Sidebar.Visible,'off');obj.reflow();
        end
        function reflow(obj)
            if ~obj.isOpen(),return,end
            % Layout thresholds are in CSS pixels of the monitor the window is
            % on. Scale is client size / Figure.Position; it is refreshed when
            % both agree on the aspect, i.e. after whichever event came last.
            sz=obj.Figure.Position(3:4);
            if numel(obj.ClientSize)==2 && all(sz>0)
                k=obj.ClientSize./sz;
                if abs(k(1)-k(2))<.04*k(1)
                    obj.Scale=mean(k);if abs(obj.Scale-1)<.03,obj.Scale=1;end
                end
            end
            width=sz(1)*obj.Scale;height=sz(2)*obj.Scale;
            names=fieldnames(obj.Kpi);
            if width<1000
                obj.HeaderGrid.ColumnWidth={112,'1x',76,104,90,84};obj.HeaderGrid.RowHeight={34,30};
                obj.Controls.Sidebar.Layout.Row=1;obj.Controls.Sidebar.Layout.Column=1;
                obj.TitleLabel.Layout.Row=1;obj.TitleLabel.Layout.Column=2;
                obj.Controls.Hold.Layout.Row=1;obj.Controls.Hold.Layout.Column=3;
                obj.Controls.Snapshot.Layout.Row=1;obj.Controls.Snapshot.Layout.Column=4;
                obj.Controls.Fit.Layout.Row=1;obj.Controls.Fit.Layout.Column=5;
                obj.Controls.ThemeSwitch.Layout.Row=1;obj.Controls.ThemeSwitch.Layout.Column=6;
                obj.StatePill.Parent.Layout.Row=2;obj.StatePill.Parent.Layout.Column=1;
                obj.StatusLabel.Layout.Row=2;obj.StatusLabel.Layout.Column=[2 6];
                obj.FooterGrid.ColumnWidth={'1x'};obj.FooterGrid.RowHeight={18,18,18};
                obj.ScopeLabel.Layout.Row=1;obj.ScopeLabel.Layout.Column=1;
                obj.MetricLabel.Layout.Row=2;obj.MetricLabel.Layout.Column=1;
                obj.CoverageLabel.Layout.Row=3;obj.CoverageLabel.Layout.Column=1;
                obj.KpiGrid.ColumnWidth=repmat({'1x'},1,4);obj.KpiGrid.RowHeight={'1x','1x'};
                for k=1:numel(names)
                    g=obj.Kpi.(names{k}).grid;g.Layout.Row=ceil(k/4);g.Layout.Column=mod(k-1,4)+1;
                end
                obj.OuterGrid.RowHeight={72,140,'1x',62};obj.StatePill.Parent.Padding=[0 4 0 4];
            else
                obj.HeaderGrid.ColumnWidth={112,150,84,'1x',76,104,90,84};obj.HeaderGrid.RowHeight={44};
                hs={obj.Controls.Sidebar,obj.TitleLabel,obj.StatePill.Parent,obj.StatusLabel,obj.Controls.Hold,obj.Controls.Snapshot,obj.Controls.Fit,obj.Controls.ThemeSwitch};
                for j=1:8,hs{j}.Layout.Row=1;hs{j}.Layout.Column=j;end
                obj.FooterGrid.ColumnWidth={'1x',330,330};obj.FooterGrid.RowHeight={22};
                fs={obj.ScopeLabel,obj.MetricLabel,obj.CoverageLabel};
                for j=1:3,fs{j}.Layout.Row=1;fs{j}.Layout.Column=j;end
                obj.KpiGrid.ColumnWidth=repmat({'1x'},1,7);obj.KpiGrid.RowHeight={'1x'};
                for k=1:numel(names)
                    g=obj.Kpi.(names{k}).grid;g.Layout.Row=1;g.Layout.Column=k;
                end
                obj.OuterGrid.RowHeight={44,66,'1x',24};obj.StatePill.Parent.Padding=[0 9 0 9];
            end
            side=width>=900;if ~isempty(obj.UserSidebar),side=obj.UserSidebar;end
            if side
                obj.RootGrid.ColumnWidth={300,'1x'};obj.Sidebar.Visible='on';
                obj.Controls.Sidebar.Text='Hide controls';
            else
                obj.RootGrid.ColumnWidth={0,'1x'};obj.Sidebar.Visible='off';
                obj.Controls.Sidebar.Text='☰ Controls';
            end
            if width>=1280
                nc=3;obj.PlotGrid.ColumnWidth={'1x','1x','1x'};
                if height>=680,obj.PlotGrid.RowHeight={'1x','1x'};obj.PlotGrid.Scrollable='off';
                else,obj.PlotGrid.RowHeight={270,270};obj.PlotGrid.Scrollable='on';end
            elseif width>=1000
                nc=2;obj.PlotGrid.ColumnWidth={'1x','1x'};
                if height>=860,obj.PlotGrid.RowHeight={'1x','1x','1x'};obj.PlotGrid.Scrollable='off';
                else,obj.PlotGrid.RowHeight={250,250,250};obj.PlotGrid.Scrollable='on';end
            else
                nc=1;obj.PlotGrid.ColumnWidth={'1x'};obj.PlotGrid.RowHeight=repmat({290},1,6);obj.PlotGrid.Scrollable='on';
            end
            % A scrollable grid resolves '1x' columns in Figure.Position pixels,
            % which is wrong on a monitor with another scale: give it explicit
            % widths from the true width (padding 28, sidebar 310, scrollbar 32).
            if strcmp(obj.PlotGrid.Scrollable,'on')
                obj.PlotGrid.ColumnWidth=repmat({max(160,floor((width-60-310*side-9*(nc-1))/nc))},1,nc);
            end
            % Pairs stay stacked: pattern under DOA, time domain under the
            % spectrum, EVM under the constellation.
            switch nc
                case 3,rows=[1 2 1 2 1 2];cols=[1 1 2 2 3 3];
                case 2,rows=[1 2 1 2 3 3];cols=[1 1 2 2 1 2];
                otherwise,rows=1:6;cols=ones(1,6);
            end
            for k=1:6,obj.Panels(k).Layout.Row=rows(k);obj.Panels(k).Layout.Column=cols(k);end
        end
        function clientSize(obj,d)
            % Window inner size in CSS pixels, reported by the probe.
            if ~obj.isOpen() || ~isnumeric(d) || numel(d)~=2 || ~all(isfinite(d)) || any(d<=0),return,end
            obj.ClientSize=double(d(:).');obj.reflow();
        end
        function onClose(obj)
            if obj.Closing,return,end
            obj.Closing=true;
            try
                if obj.has('close'),obj.Callbacks.close();end
            catch err
                obj.Closing=false;obj.showError(err.message);return
            end
            if obj.isOpen(),obj.Figure.CloseRequestFcn=[];delete(obj.Figure);end
        end
        function tf=has(obj,name)
            tf=isfield(obj.Callbacks,name) && isa(obj.Callbacks.(name),'function_handle');
        end
    end
    methods (Static)
        function text=keyText(labels,colors)
            text='';
            for k=1:numel(labels)
                text=[text sprintf('{\\color[rgb]{%.3f,%.3f,%.3f}%s}   ',colors{k},labels{k})]; %#ok<AGROW>
            end
            text=strtrim(text);
        end
        function th=palette(name)
            % One palette per theme. Status hues (ok/warn/fault) are never used
            % for data series. Every entry is unique within a palette so a live
            % switch can map colours one to one in both directions.
            if strcmp(name,'light')
                th=struct('bg',[.935 .945 .96],'panel',[1 1 1],'input',[.915 .93 .95], ...
                    'hair',[.85 .875 .905],'text',[.09 .12 .16],'muted',[.34 .40 .47],'dim',[.52 .57 .63], ...
                    'accent',[.56 .83 .90],'ok',[.04 .52 .33],'warn',[.72 .43 0],'fault',[.78 .14 .14], ...
                    'okBg',[.84 .95 .89],'warnBg',[.99 .92 .78],'faultBg',[.99 .87 .87], ...
                    's1',[.02 .50 .70],'s2',[.46 .30 .80],'s3',[.82 .20 .45],'s4',[.64 .50 .04], ...
                    'model',[.24 .34 .76]);
            else
                th=struct('bg',[.043 .058 .078],'panel',[.082 .106 .141],'input',[.125 .16 .20], ...
                    'hair',[.165 .205 .255],'text',[.90 .93 .97],'muted',[.56 .64 .73],'dim',[.38 .45 .53], ...
                    'accent',[.06 .45 .56],'ok',[.30 .88 .64],'warn',[1 .72 .28],'fault',[1 .43 .43], ...
                    'okBg',[.07 .24 .18],'warnBg',[.27 .19 .05],'faultBg',[.30 .10 .10], ...
                    's1',[.25 .78 .96],'s2',[.78 .60 .98],'s3',[.98 .55 .72],'s4',[.93 .87 .45], ...
                    'model',[.60 .70 .98]);
            end
        end
    end
    methods (Static,Access=private)
        function put(h,text)
            % Compare-then-set: each changed label is a round trip to the web view.
            if ~isequal(h.Text,text),h.Text=text;end
        end
        function setp(h,name,value)
            % Compare-then-set for any property (colours are re-sent otherwise).
            cur=h.(name);
            if isa(cur,'matlab.lang.OnOffSwitchState'),same=cur==matlab.lang.OnOffSwitchState(value);
            else,same=isequal(cur,value);end
            if ~same,h.(name)=value;end
        end
        function value=field(s,name,fallback)
            value=fallback;if isstruct(s) && isfield(s,name),value=s.(name);end
        end
        function [t,yi,yq]=envelope(x,fs)
            % Min/max per display bin: at most 1024 drawn points per trace
            % (more than the card's pixel width) and no burst peak is lost
            % to stride decimation.
            n=numel(x);nb=512;
            if n<=2*nb
                t=(0:n-1).'/fs*1e6;yi=real(x);yq=imag(x);return
            end
            L=floor(n/nb);X=reshape(x(1:nb*L),L,nb);
            c=((0:nb-1)*L+(L-1)/2)/fs*1e6;t=[c;c];t=t(:);
            yi=[min(real(X),[],1);max(real(X),[],1)];yi=yi(:);
            yq=[min(imag(X),[],1);max(imag(X),[],1)];yq=yq(:);
        end
        function text=count(n,noun)
            text=sprintf('%d %s',n,noun);if n~=1,text=[text 's'];end
        end
        function text=hz(v)
            if ~isfinite(v),text='—';
            elseif abs(v)>=1e3,text=sprintf('%+.2f kHz',v/1e3);
            else,text=sprintf('%+.0f Hz',v);
            end
        end
        function text=valueText(v)
            if islogical(v)
                text='off';if v,text='on';end
            elseif isnumeric(v),text=mat2str(v,6);
            else,text=char(string(v));
            end
        end
        function lines=wrap(text,width)
            words=strsplit(strtrim(text),' ');lines={};line='';
            for k=1:numel(words)
                if isempty(line),line=words{k};
                elseif numel(line)+1+numel(words{k})<=width,line=[line ' ' words{k}]; %#ok<AGROW>
                else,lines{end+1}=line;line=words{k}; %#ok<AGROW>
                end
            end
            if ~isempty(line),lines{end+1}=line;end
            if numel(lines)>3,lines=lines(1:3);lines{3}=[lines{3} ' …'];end
        end
    end
end
