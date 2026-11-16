classdef BeamformerView < handle
    %BEAMFORMERVIEW Six measured views and the supported RF/DSP controls.
    % This class performs no acquisition, beamforming or instrument IO. Its
    % callback contract is implemented by DemoSession/the owning frontend.
    properties (SetAccess=private)
        Figure = []
        Ax = struct()
        Controls = struct()
        Lines = struct()
        StatusLabel = []
        EvmLabel = []
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
    end
    properties (Access=private)
        Config
        Callbacks
        Panels = []
        Accepted = struct()
        PhaseValues = struct('ADC',[0 0 0 0],'DAC',[0 0 0 0])
        UserSidebar = []
        Closing = false
        Theme = struct('bg',[.055 .075 .10],'panel',[.09 .12 .155], ...
            'input',[.135 .17 .21],'text',[.88 .93 .98],'muted',[.54 .65 .75], ...
            'grid',[.23 .29 .35],'cyan',[.15 .78 .95],'green',[.3 .88 .64], ...
            'amber',[1 .72 .28],'red',[1 .43 .43])
    end
    methods
        function obj=BeamformerView(cfg,callbacks)
            if nargin<2,callbacks=struct();end
            obj.Config=cfg;obj.Callbacks=callbacks;
            if isfield(cfg,'dphase'),obj.PhaseValues.DAC=reshape(cfg.dphase,1,[]);end
            obj.build();
        end
        function show(obj,s)
            if ~obj.isOpen(),return,end
            if ~isfield(s,'valid') || ~s.valid
                obj.clear(obj.field(s,'reason','No fresh acquisition'));
                return
            end
            seq=obj.field(s,'sequence',NaN);age=obj.field(s,'age',NaN);
            scope=string(obj.field(s,'scope','Array model / UNCALIBRATED'));
            obj.ScopeLabel.Text=char(scope);obj.ScopeLabel.Tooltip=char(scope);
            obj.StatusLabel.Text=sprintf('LIVE  ·  frame %g  ·  age %.2f s',seq,age);
            obj.StatusLabel.FontColor=obj.Theme.green;
            obj.Controls.Start.Enable='off';
            scan=obj.field(s,'scan',[]);
            obj.setLine('doa',scan,obj.field(s,'doaSpectrum',[]));
            obj.setLine('pattern',scan,obj.field(s,'patternDb',[]));
            angles=obj.field(s,'angles',[]);
            if isempty(angles)
                obj.Panels(1).Title='DOA spectrum · unavailable';
            else
                obj.Panels(1).Title=sprintf('DOA spectrum  ·  %s°',strjoin(compose('%.1f',angles(:).'),', '));
            end
            samples=obj.field(s,'samples',[]);
            if ~isempty(samples)
                samples=samples(:);idx=unique(round(linspace(1,numel(samples),min(2048,numel(samples)))));
                fs=obj.field(obj.Config,'fsRfsoc',125e6);
                t=(idx-1)/fs*1e6;
                obj.setLine('timeI',t,real(samples(idx)));
                obj.setLine('timeQ',t,imag(samples(idx)));
            else
                obj.setLine('timeI',[],[]);obj.setLine('timeQ',[],[]);
            end
            analysis=obj.field(s,'analysis',[]);
            spec=obj.field(s,'spectrum',[]);
            if isempty(spec) && isstruct(analysis),spec=obj.field(analysis,'spectrum',[]);end
            if isstruct(spec) && isfield(spec,'freqHz') && isfield(spec,'psdDbfs')
                obj.setLine('spectrum',spec.freqHz/1e6,spec.psdDbfs);
            else
                obj.setLine('spectrum',[],[]);
            end
            if isstruct(analysis) && isfield(analysis,'valid') && analysis.valid
                obj.showAnalysis(analysis,seq);
            else
                why='OFDM unavailable';
                if isstruct(analysis),why=char(string(obj.field(analysis,'reason',why)));end
                obj.clearAnalysis(why);
            end
            obj.showVendor(obj.field(s,'vendor',[]),seq);
            obj.LastSequence=seq;
            drawnow limitrate nocallbacks
        end
        function clear(obj,reason)
            if ~obj.isOpen(),return,end
            for n=["doa","pattern","spectrum","timeI","timeQ"]
                obj.setLine(char(n),[],[]);
            end
            obj.clearAnalysis(reason);
            obj.StatusLabel.Text=char("UNAVAILABLE  ·  "+string(reason));
            obj.StatusLabel.FontColor=obj.Theme.amber;
            obj.Panels(1).Title='DOA spectrum · unavailable';
            obj.Panels(2).Title='Receive pattern · unavailable';
            obj.showVendor([],NaN);
            obj.LastSequence=NaN;
            drawnow limitrate nocallbacks
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
            obj.Config=cfg;
            cal=obj.field(cfg,'calibration',struct());
            ready=~isempty(obj.field(cal,'steeringCorrection',[])) && ~isempty(obj.field(cal,'powCalibration',[]));
            obj.Controls.phComp.Enable=matlab.lang.OnOffSwitchState(ready);
            obj.Controls.phComp.Value=logical(cfg.phComp);obj.Accepted.phComp=logical(cfg.phComp);
            obj.Controls.doa.Value=char(cfg.doa);obj.Accepted.doa=char(cfg.doa);
        end
        function fitPlots(obj)
            names=fieldnames(obj.Ax);
            for k=1:numel(names)
                ax=obj.Ax.(names{k});ax.XLimMode='auto';ax.YLimMode='auto';
            end
            axis(obj.Ax.constellation,'equal');
            values=[obj.Lines.payload.XData(:);obj.Lines.payload.YData(:); ...
                obj.Lines.header.XData(:);obj.Lines.header.YData(:);obj.Lines.pilots.XData(:);obj.Lines.pilots.YData(:)];
            values=values(isfinite(values));lim=1.6;
            if ~isempty(values),lim=max(lim,1.05*max(abs(values)));end
            obj.Ax.constellation.XLim=[-lim lim];obj.Ax.constellation.YLim=[-lim lim];
        end
    end
    methods (Access=private)
        function build(obj)
            th=obj.Theme;
            f=uifigure('Name','RFSoC Beamformer','Visible','off','Color',th.bg, ...
                'Position',[60 60 1480 900],'AutoResizeChildren','off','Tag','RFSoCBeamformerDashboard');
            obj.Figure=f;
            f.CloseRequestFcn=@(~,~)obj.onClose();
            outer=uigridlayout(f,[3 1],'RowHeight',{56,'1x',29},'Padding',[14 10 14 8], ...
                'RowSpacing',8,'BackgroundColor',th.bg);obj.OuterGrid=outer;
            header=uigridlayout(outer,[1 5],'ColumnWidth',{106,190,'1x',170,110},'Padding',[0 0 0 0], ...
                'BackgroundColor',th.bg);header.Layout.Row=1;obj.HeaderGrid=header;
            obj.Controls.Sidebar=uibutton(header,'Text','☰ Controls','FontWeight','bold', ...
                'BackgroundColor',th.input,'FontColor',th.text,'ButtonPushedFcn',@(~,~)obj.toggleSidebar());
            obj.TitleLabel=uilabel(header,'Text','RFSoC 4×2','FontWeight','bold','FontSize',25,'FontColor',th.text);
            obj.StatusLabel=uilabel(header,'Text','IDLE  ·  ready to acquire','FontSize',13,'FontColor',th.muted);
            obj.EvmLabel=uilabel(header,'Text','EVM —','FontSize',22,'FontWeight','bold','FontColor',th.cyan, ...
                'HorizontalAlignment','right');
            obj.Controls.Fit=uibutton(header,'Text','Fit plots','BackgroundColor',th.input,'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.fitPlots());
            main=uigridlayout(outer,[1 2],'ColumnWidth',{278,'1x'},'ColumnSpacing',10, ...
                'Padding',[0 0 0 0],'BackgroundColor',th.bg);main.Layout.Row=2;obj.RootGrid=main;
            side=uipanel(main,'BorderType','none','BackgroundColor',th.panel);side.Layout.Column=1;obj.Sidebar=side;
            obj.buildControls(side);
            pg=uigridlayout(main,[2 3],'ColumnWidth',{'1x','1x','1x'}, ...
                'RowHeight',{'1x','1x'},'Padding',[0 0 0 0], ...
                'RowSpacing',9,'ColumnSpacing',9,'BackgroundColor',th.bg);
            pg.Layout.Column=2;obj.PlotGrid=pg;
            keys={'doa','pattern','spectrum','time','constellation','evm'};
            titles={'DOA spectrum','Receive pattern','Baseband spectrum','Time domain · I/Q', ...
                'Constellation','Payload EVM · all complete bursts'};
            obj.Panels=gobjects(1,6);
            for k=1:6
                p=uipanel(pg,'Title',titles{k},'FontWeight','bold','FontSize',13, ...
                    'ForegroundColor',th.text,'BackgroundColor',th.panel,'BorderType','line', ...
                    'HighlightColor',th.grid);obj.Panels(k)=p;
                g=uigridlayout(p,[1 1],'Padding',[5 4 7 4],'BackgroundColor',th.panel);
                ax=uiaxes(g,'Color',th.panel,'XColor',th.muted,'YColor',th.muted, ...
                    'GridColor',th.grid,'GridAlpha',.55,'FontSize',11,'Box','off');
                grid(ax,'on');hold(ax,'on');obj.Ax.(keys{k})=ax;
                axtoolbar(ax,{'zoomin','zoomout','pan','datacursor','restoreview'});
            end
            obj.Lines.doa=plot(obj.Ax.doa,NaN,NaN,'LineWidth',1.6,'Color',th.cyan);
            xlabel(obj.Ax.doa,'Model angle (°)');ylabel(obj.Ax.doa,'Normalized spectrum');
            obj.Lines.pattern=plot(obj.Ax.pattern,NaN,NaN,'LineWidth',1.6,'Color',th.green);
            xlabel(obj.Ax.pattern,'Model angle (°)');ylabel(obj.Ax.pattern,'Relative response (dB)');
            obj.Lines.spectrum=plot(obj.Ax.spectrum,NaN,NaN,'Color',th.cyan,'LineWidth',1.1);
            xlabel(obj.Ax.spectrum,'Baseband frequency (MHz)');ylabel(obj.Ax.spectrum,'dBFS/bin');
            obj.Lines.timeI=plot(obj.Ax.time,NaN,NaN,'Color',th.cyan,'LineWidth',1);
            obj.Lines.timeQ=plot(obj.Ax.time,NaN,NaN,'Color',th.amber,'LineWidth',1);
            xlabel(obj.Ax.time,'Time (µs) · display decimated');ylabel(obj.Ax.time,'Amplitude');
            legend(obj.Ax.time,{'I','Q'},'TextColor',th.muted,'Color',th.panel,'EdgeColor','none','Location','northeast');
            lev=(-3:2:3)/sqrt(10);[a,b]=meshgrid(lev);
            obj.Lines.ideal=plot(obj.Ax.constellation,a(:),b(:),'+','Color',th.grid,'MarkerSize',9);
            obj.Lines.payload=plot(obj.Ax.constellation,NaN,NaN,'.','Color',th.cyan,'MarkerSize',5);
            obj.Lines.header=plot(obj.Ax.constellation,NaN,NaN,'.','Color',th.amber,'MarkerSize',5);
            obj.Lines.pilots=plot(obj.Ax.constellation,NaN,NaN,'.','Color',th.green,'MarkerSize',5);
            legend(obj.Ax.constellation,[obj.Lines.payload,obj.Lines.header,obj.Lines.pilots], ...
                {'16QAM data','BPSK header','Pilots'},'Location','southoutside','NumColumns',3, ...
                'TextColor',th.muted,'Color',th.panel,'EdgeColor','none','FontSize',9);
            xlabel(obj.Ax.constellation,'I');ylabel(obj.Ax.constellation,'Q');axis(obj.Ax.constellation,'equal');
            obj.Ax.constellation.XLim=[-1.6 1.6];obj.Ax.constellation.YLim=[-1.6 1.6];
            obj.Lines.evmHistory=plot(obj.Ax.evm,NaN,NaN,'Color',th.cyan,'LineWidth',1.4);
            obj.Lines.evmCurrent=plot(obj.Ax.evm,NaN,NaN,'o','Color',th.cyan,'MarkerFaceColor',th.cyan,'MarkerSize',5);
            xlabel(obj.Ax.evm,'Acquisition sequence');ylabel(obj.Ax.evm,'Payload EVM (%)');
            footer=uigridlayout(outer,[1 3],'ColumnWidth',{'1x',260,340},'Padding',[0 0 0 0], ...
                'BackgroundColor',th.bg);footer.Layout.Row=3;obj.FooterGrid=footer;
            obj.ScopeLabel=uilabel(footer,'Text',char(string(obj.field(obj.Config,'arrayLabel','Array model'))+' · UNCALIBRATED'), ...
                'FontSize',11,'FontColor',th.muted);
            obj.MetricLabel=uilabel(footer,'Text','CFO —  ·  RX —','FontColor',th.muted,'HorizontalAlignment','right');
            obj.CoverageLabel=uilabel(footer,'Text','No demodulated frame','FontColor',th.muted,'HorizontalAlignment','right');
            f.SizeChangedFcn=@(~,~)obj.reflow();
            mp=get(groot,'MonitorPositions');m=mp(1,:);
            w=min(1540,max(420,m(3)-48));h=min(930,max(340,m(4)-110));
            f.Position=[m(1)+round((m(3)-w)/2),m(2)+max(45,round((m(4)-h)/2)),w,h];
            obj.reflow();
            if logical(obj.field(obj.Config,'visible',false)),f.Visible='on';end
        end
        function buildControls(obj,parent)
            th=obj.Theme;
            g=uigridlayout(parent,[3 1],'RowHeight',{36,25,'1x'},'Padding',[10 9 10 9], ...
                'BackgroundColor',th.panel);
            buttons=uigridlayout(g,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0], ...
                'BackgroundColor',th.panel);
            obj.Controls.Start=uibutton(buttons,'Text','Start','FontWeight','bold', ...
                'BackgroundColor',[.05 .42 .51],'FontColor',th.text, ...
                'ButtonPushedFcn',@(~,~)obj.action('start',[]));
            obj.Controls.Pause=uibutton(buttons,'state','Text','Pause','BackgroundColor',th.input,'FontColor',th.text, ...
                'ValueChangedFcn',@(h,~)obj.valueAction('pause',h,logical(h.Value)));
            if ~obj.has('start'),obj.Controls.Start.Enable='off';end
            if ~obj.has('pause'),obj.Controls.Pause.Enable='off';end
            obj.Controls.Error=uilabel(g,'Text','','FontColor',th.amber,'WordWrap','on','FontSize',11);
            tabs=uitabgroup(g);tabs.Layout.Row=3;
            rf=uitab(tabs,'Title','RF','BackgroundColor',th.panel);
            dsp=uitab(tabs,'Title','DSP','BackgroundColor',th.panel);
            advanced=uitab(tabs,'Title','Algorithms','BackgroundColor',th.panel);
            r=obj.controlGrid(rf,17);
            obj.heading(r,1,'RF tuning');
            obj.number(r,2,'ADC center (MHz)','adcMHz',obj.field(obj.Config,'fc',3e9)/1e6,[-6000 6000],false);
            obj.number(r,3,'DAC center (MHz)','dacMHz',obj.field(obj.Config,'fc_d0',3e9)/1e6,[-6000 6000],false);
            obj.Controls.ApplyRF=obj.button(r,4,'Apply frequency',@(~,~)obj.rfAction());
            obj.Controls.Dac=obj.checkbox(r,5,'Selected DAC enabled','dac',logical(any(obj.field(obj.Config,'dacPow',[1 0 0 0]))),false);
            obj.Controls.Dac.ValueChangedFcn=@(h,~)obj.valueAction('dac',h,logical(h.Value));
            obj.heading(r,7,'Requested mixer phases (°)');
            obj.Controls.PhaseKind=obj.dropdown(r,8,'Converters','phaseKind',{'ADC','DAC'},'DAC',false);
            obj.Controls.PhaseKind.ValueChangedFcn=@(~,~)obj.phaseKind();
            for k=1:4,obj.number(r,8+k,sprintf('Channel %d',k),sprintf('phase%d',k),obj.PhaseValues.DAC(k),[-180 180],false);end
            obj.Controls.ApplyPhase=obj.button(r,13,'Apply phases',@(~,~)obj.phaseAction());
            if obj.has('calibration'),obj.Controls.Calibration=obj.button(r,15,'Load calibration',@(~,~)obj.action('calibration',[]));end
            info=uilabel(r,'Text','ADC_D = stream 0. Other connector mappings remain unverified.', ...
                'WordWrap','on','FontColor',th.muted,'FontSize',11);info.Layout.Row=17;info.Layout.Column=[1 2];
            if ~obj.has('rf'),obj.Controls.ApplyRF.Enable='off';end
            if ~obj.has('dac'),obj.Controls.Dac.Enable='off';end
            if ~obj.has('phase'),obj.Controls.ApplyPhase.Enable='off';end
            d=obj.controlGrid(dsp,17);
            obj.heading(d,1,'Receive processing');
            obj.Controls.ch=obj.dropdown(d,2,'Output','ch',{'Combined','ADC_D · stream 0','RX stream 1','RX stream 2','RX stream 3'},'Combined',false);
            mask=true(1,4);if obj.field(obj.Config,'directOnly',false),mask=[true false false false];end
            mask=logical(obj.field(obj.Config,'availableChannels',mask));
            vals=find(mask);labels={'ADC_D · stream 0','RX stream 1','RX stream 2','RX stream 3'};labels=labels(mask);
            if all(mask) && ~obj.field(obj.Config,'directOnly',false),vals=[5 vals];labels=[{'Combined'} labels];end
            obj.Controls.ch.Items=labels;obj.Controls.ch.ItemsData=num2cell(vals);
            selected=obj.field(obj.Config,'ch',5);if ~ismember(selected,vals),selected=vals(1);end
            obj.Controls.ch.Value=selected;
            obj.Controls.ch.ValueChangedFcn=@(h,~)obj.configure('ch',h.Value,h);
            obj.Accepted.ch=obj.Controls.ch.Value;
            bfs={'Without','Steering','MVDR','DMR','PC','PC_corr','LCMV','RVL','RAB PC','DL MVDR','DL ITER MVDR','QCB'};
            obj.dropdown(d,3,'Beamformer','bf',bfs,char(obj.field(obj.Config,'bf','Steering')),true);
            doa={'MVDR','MUSIC','Beamscan','MUSICR','ESPRITE','ESPRITEBS','WSFR','MVDRman','MVDRman_corr'};
            obj.dropdown(d,4,'DOA estimator','doa',doa,char(obj.field(obj.Config,'doa','MVDR')),true);
            obj.number(d,5,'Source count','num',obj.field(obj.Config,'num',1),[1 3],true);
            obj.number(d,6,'Scan width (°)','scan_bw',obj.field(obj.Config,'scan_bw',120),[1 180],true);
            obj.number(d,7,'Scan step (°)','scan_res',obj.field(obj.Config,'scan_res',1),[.1 10],true);
            obj.number(d,8,'Average frames','avg_factor',obj.field(obj.Config,'avg_factor',10),[1 100],true);
            obj.number(d,9,'Signal BW (MHz)','bwMHz',obj.field(obj.Config,'bw',100e6)/1e6,[1 125],false);
            obj.Accepted.bw=obj.Controls.bwMHz.Value;
            obj.Controls.bwMHz.ValueChangedFcn=@(h,~)obj.configure('bw',h.Value*1e6,h);
            obj.Controls.CompareVsa=obj.checkbox(d,10,'Compare with native VSA','CompareVsa',string(obj.field(obj.Config,'analyzer','integrated'))~="integrated",false);
            obj.Accepted.analyzer=obj.Controls.CompareVsa.Value;
            obj.Controls.CompareVsa.ValueChangedFcn=@(h,~)obj.compareVsa(h);
            obj.Controls.ang_num=uidropdown(d,'Items',{'Strongest','Weaker'},'ItemsData',{1,2}, ...
                'Value',obj.field(obj.Config,'ang_num',1),'BackgroundColor',th.input,'FontColor',th.text);
            obj.Controls.ang_num.Layout.Row=11;obj.Controls.ang_num.Layout.Column=2;
            h=uilabel(d,'Text','Signal priority','FontColor',th.muted);h.Layout.Row=11;h.Layout.Column=1;
            obj.Accepted.ang_num=obj.Controls.ang_num.Value;
            obj.Controls.ang_num.ValueChangedFcn=@(h,~)obj.configure('ang_num',h.Value,h);
            obj.heading(d,12,'IQ / phase correction');
            obj.checkbox(d,13,'Adaptive IQ correction','adIQcomp',logical(obj.field(obj.Config,'adIQcomp',false)),true);
            obj.checkbox(d,14,'Static IQ correction','IQcomp',logical(obj.field(obj.Config,'IQcomp',false)),true);
            obj.Controls.IQcomp.Tooltip='Uses the frozen IQ filter learned by adaptive correction.';
            obj.checkbox(d,15,'Phase / power correction','phComp',logical(obj.field(obj.Config,'phComp',false)),true);
            cal=obj.field(obj.Config,'calibration',struct());
            if isempty(obj.field(cal,'steeringCorrection',[])) || isempty(obj.field(cal,'powCalibration',[]))
                obj.Controls.phComp.Enable='off';obj.Controls.phComp.Tooltip='Load matching steering and power calibration tables first.';
            end
            obj.Controls.Vendor=uilabel(d,'Text','Native VSA comparison —','WordWrap','on', ...
                'FontColor',th.muted,'FontSize',11);obj.Controls.Vendor.Layout.Row=16;obj.Controls.Vendor.Layout.Column=[1 2];
            obj.Controls.Profile=uilabel(d,'Text','OFDM profile · awaiting data','WordWrap','on', ...
                'FontColor',th.muted,'FontSize',11);obj.Controls.Profile.Layout.Row=17;obj.Controls.Profile.Layout.Column=[1 2];
            a=obj.controlGrid(advanced,15);
            obj.heading(a,1,'Beamformer parameters');
            spec={'diag','Diagonal loading',[0 1e6];'alpha','Uncertainty',[0 100];'gamma','Robust loading γ',[0 100]; ...
                'iter','Iterations',[1 1000];'mis_ang','Mismatch angle (°)',[0 90];'alg_scan_res','Algorithm step (°)',[.1 10]};
            for k=1:size(spec,1),obj.number(a,k+1,spec{k,2},spec{k,1},obj.field(obj.Config,spec{k,1},1),spec{k,3},true);end
            obj.heading(a,9,'IQ filter parameters');
            obj.number(a,10,'Filter length','sizeL',obj.field(obj.Config,'sizeL',4),[1 50],true);
            obj.number(a,11,'LMS step μ','stepMU',obj.field(obj.Config,'stepMU',1e-16),[1e-31 1],true);
            note=uilabel(a,'Text','Only supported processing options are shown. RF changes reset current measurements.', ...
                'WordWrap','on','FontSize',11,'FontColor',th.muted);note.Layout.Row=14;note.Layout.Column=[1 2];
            obj.phaseKind();
            if isfield(obj.Config,'ofdmProfile'),obj.Controls.Profile.Text=obj.profileText(obj.Config.ofdmProfile);end
        end
        function g=controlGrid(obj,parent,n)
            rh=repmat({30},1,n);rh{n}=65;
            g=uigridlayout(parent,[n 2],'ColumnWidth',{132,'1x'},'RowHeight',rh, ...
                'Padding',[7 9 7 9],'RowSpacing',5,'ColumnSpacing',6,'BackgroundColor',obj.Theme.panel,'Scrollable','on');
        end
        function heading(obj,g,row,text)
            h=uilabel(g,'Text',text,'FontColor',obj.Theme.text,'FontWeight','bold','FontSize',12);
            h.Layout.Row=row;h.Layout.Column=[1 2];
        end
        function h=label(obj,g,row,text)
            h=uilabel(g,'Text',text,'FontColor',obj.Theme.muted,'FontSize',11);
            h.Layout.Row=row;h.Layout.Column=1;
        end
        function h=number(obj,g,row,text,key,value,limits,bind)
            lh=obj.label(g,row,text);obj.Controls.([key 'Label'])=lh;
            h=uieditfield(g,'numeric','Value',value,'Limits',limits,'BackgroundColor',obj.Theme.input, ...
                'FontColor',obj.Theme.text,'FontSize',11);
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
                'ButtonPushedFcn',callback);h.Layout.Row=row;h.Layout.Column=[1 2];
        end
        function configure(obj,key,value,h)
            old=h.Value;
            if isfield(obj.Accepted,key),old=obj.Accepted.(key);end
            try
                assert(obj.has('configure'),'origapp:View','Processing controls are unavailable.');
                obj.Callbacks.configure(struct(key,value));
                obj.Accepted.(key)=h.Value;
                obj.Config.(key)=value;
                obj.Controls.Error.Text='';
            catch err
                h.Value=old;obj.showError(err.message);
            end
        end
        function compareVsa(obj,h)
            mode='integrated';if h.Value,mode='both';end
            obj.configure('analyzer',mode,h);
        end
        function valueAction(obj,name,h,value)
            old=~logical(h.Value);
            try
                assert(obj.has(name),'origapp:View','This control is unavailable.');
                obj.Callbacks.(name)(value);obj.Controls.Error.Text='';
            catch err
                h.Value=old;obj.showError(err.message);
            end
        end
        function action(obj,name,arg)
            try
                assert(obj.has(name),'origapp:View','This control is unavailable.');
                if isempty(arg),obj.Callbacks.(name)();else,obj.Callbacks.(name)(arg);end
                if strcmp(name,'start'),obj.Controls.Start.Enable='off';end
                obj.Controls.Error.Text='';
            catch err,obj.showError(err.message);end
        end
        function rfAction(obj)
            try
                assert(obj.has('rf'),'origapp:View','Frequency controls are unavailable.');
                obj.Callbacks.rf(struct('adcMHz',obj.Controls.adcMHz.Value,'dacMHz',obj.Controls.dacMHz.Value));
                obj.Accepted.adcMHz=obj.Controls.adcMHz.Value;obj.Accepted.dacMHz=obj.Controls.dacMHz.Value;
                obj.Controls.Error.Text='';
            catch err
                obj.Controls.adcMHz.Value=obj.Accepted.adcMHz;obj.Controls.dacMHz.Value=obj.Accepted.dacMHz;
                obj.showError(err.message);
            end
        end
        function phaseKind(obj)
            kind=obj.Controls.PhaseKind.Value;v=obj.PhaseValues.(kind);
            g=obj.Controls.phase1.Parent;rh=g.RowHeight;
            for k=1:4
                h=obj.Controls.(sprintf('phase%d',k));lab=obj.Controls.(sprintf('phase%dLabel',k));
                h.Value=v(k);h.Layout.Row=8+k;lab.Layout.Row=8+k;
                h.Visible='on';lab.Visible='on';
                if k==1,lab.Text='RX0 · ADC_D';else,lab.Text=sprintf('RX%d · unverified',k-1);end
                rh{8+k}=30;
            end
            if strcmp(kind,'DAC')
                obj.Controls.phase1Label.Text='DAC_B (index 0)';
                obj.Controls.phase3Label.Text='DAC_A (index 2)';
                obj.Controls.phase3.Layout.Row=10;obj.Controls.phase3Label.Layout.Row=10;
                for k=[2 4]
                    obj.Controls.(sprintf('phase%d',k)).Visible='off';
                    obj.Controls.(sprintf('phase%dLabel',k)).Visible='off';
                end
                rh{11}=0;rh{12}=0;
            end
            g.RowHeight=rh;
        end
        function phaseAction(obj)
            kind=obj.Controls.PhaseKind.Value;values=zeros(1,4);
            indices=1:4;if strcmp(kind,'DAC'),indices=[1 3];end
            for k=indices,values(k)=obj.Controls.(sprintf('phase%d',k)).Value;end
            try
                assert(obj.has('phase'),'origapp:View','Phase controls are unavailable.');
                obj.Callbacks.phase(struct('kind',kind,'values',values));
                obj.PhaseValues.(kind)=values;obj.Controls.Error.Text='';
            catch err,obj.phaseKind();obj.showError(err.message);end
        end
        function showError(obj,text)
            obj.Controls.Error.Text=char(string(text));
            obj.StatusLabel.Text=char("CONTROL REFUSED  ·  "+string(text));
            obj.StatusLabel.FontColor=obj.Theme.amber;
        end
        function showAnalysis(obj,r,seq)
            c=r.constellation;
            obj.setLine('payload',real(c.payload),imag(c.payload));
            obj.setLine('header',real(c.header),imag(c.header));
            obj.setLine('pilots',real(c.pilot),imag(c.pilot));
            ev=r.evmPercent;db=r.evmDb;
            obj.EvmLabel.Text=sprintf('%.2f%% / %.1f dB',ev,db);
            degraded=logical(obj.field(r,'degraded',false));
            obj.EvmLabel.FontColor=obj.Theme.cyan;
            if degraded,obj.EvmLabel.FontColor=obj.Theme.amber;end
            if isempty(obj.HistorySequence) || seq~=obj.HistorySequence(end)
                obj.HistorySequence(end+1)=seq;obj.HistoryEvm(end+1)=ev;
                if numel(obj.HistorySequence)>300,obj.HistorySequence(1)=[];obj.HistoryEvm(1)=[];end
            end
            obj.setLine('evmHistory',obj.HistorySequence,obj.HistoryEvm);
            obj.setLine('evmCurrent',seq,ev);
            obj.Lines.evmHistory.Color=obj.Theme.cyan;
            if isfield(r,'profile'),obj.Controls.Profile.Text=obj.profileText(r.profile);end
            obj.Panels(6).Title='Payload EVM · all complete bursts';
            qualified=obj.field(r,'qualifiedBursts',NaN);complete=obj.field(r,'metricBursts',NaN);
            secondary=obj.field(r,'qualifiedPayloadEvmPercent',NaN);
            tag='LOCKED';if degraded,tag='DEGRADED';end
            obj.CoverageLabel.Text=sprintf('%s · %g/%g qualified · clean-only %.2f%%',tag,qualified,complete,secondary);
            obj.CoverageLabel.FontColor=obj.EvmLabel.FontColor;
            cfo=obj.field(r,'cfoHz',NaN);rx=obj.field(r,'rxLevelDbfs',NaN);
            obj.MetricLabel.Text=sprintf('CFO %.1f Hz  ·  RX %.1f dBFS',median(cfo,'omitnan'),rx);
            obj.Panels(2).Title='Receive pattern';
            obj.Panels(5).Title=sprintf('Constellation · frame %g',seq);
        end
        function showVendor(obj,v,seq)
            if ~isstruct(v) || ~isfield(v,'valid') || ~v.valid
                obj.Controls.Vendor.Text='Native VSA — no current measurement';
                obj.Controls.Vendor.FontColor=obj.Theme.muted;
            elseif ~isfield(v,'sequence') || v.sequence~=seq
                obj.Controls.Vendor.Text='Native VSA — waiting for this frame';
                obj.Controls.Vendor.FontColor=obj.Theme.muted;
            else
                obj.Controls.Vendor.Text=sprintf('Native VSA comparison: %.2f%% / %.1f dB',v.evmPercent,20*log10(v.evmPercent/100));
                obj.Controls.Vendor.FontColor=obj.Theme.green;
            end
        end
        function text=profileText(obj,p)
            text=sprintf('%s · FFT %g / CP %g\n%g MHz system · %g MS/s ADC\n%g data + %g pilot subcarriers', ...
                string(obj.field(p,'payloadModulation','OFDM')),obj.field(p,'fftLength',NaN),obj.field(p,'cpSamples',NaN), ...
                obj.field(p,'systemRateHz',NaN)/1e6,obj.field(p,'receiveRateHz',NaN)/1e6, ...
                obj.field(p,'dataSubcarriers',NaN),numel(obj.field(p,'pilotSubcarriers',[])));
        end
        function clearAnalysis(obj,why)
            for n=["payload","header","pilots","evmCurrent"],obj.setLine(char(n),[],[]);end
            obj.EvmLabel.Text='EVM —';obj.EvmLabel.FontColor=obj.Theme.muted;
            obj.MetricLabel.Text='CFO —  ·  RX —';
            obj.CoverageLabel.Text=char(string(why));obj.CoverageLabel.FontColor=obj.Theme.amber;
            obj.Lines.evmHistory.Color=obj.Theme.muted;
            obj.Panels(5).Title='Constellation · unavailable';
            if isempty(obj.HistorySequence)
                obj.Panels(6).Title='EVM · no current value';
            else
                obj.Panels(6).Title=sprintf('History only · last valid frame %g',obj.HistorySequence(end));
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
            width=obj.Figure.Position(3);height=obj.Figure.Position(4);
            if width<1000
                obj.EvmLabel.FontSize=16;
                obj.HeaderGrid.ColumnWidth={105,'1x',170};obj.HeaderGrid.RowHeight={34,32};
                obj.Controls.Sidebar.Layout.Row=1;obj.Controls.Sidebar.Layout.Column=1;
                obj.TitleLabel.Layout.Row=1;obj.TitleLabel.Layout.Column=2;
                obj.Controls.Fit.Layout.Row=1;obj.Controls.Fit.Layout.Column=3;
                obj.StatusLabel.Layout.Row=2;obj.StatusLabel.Layout.Column=[1 2];
                obj.EvmLabel.Layout.Row=2;obj.EvmLabel.Layout.Column=3;
                obj.FooterGrid.ColumnWidth={'1x'};obj.FooterGrid.RowHeight={20,20,20};
                obj.ScopeLabel.Layout.Row=1;obj.ScopeLabel.Layout.Column=1;
                obj.MetricLabel.Layout.Row=2;obj.MetricLabel.Layout.Column=1;
                obj.CoverageLabel.Layout.Row=3;obj.CoverageLabel.Layout.Column=1;
                obj.OuterGrid.RowHeight={76,'1x',68};
            else
                obj.EvmLabel.FontSize=22;
                obj.HeaderGrid.ColumnWidth={106,190,'1x',220,90};obj.HeaderGrid.RowHeight={46};
                hs={obj.Controls.Sidebar,obj.TitleLabel,obj.StatusLabel,obj.EvmLabel,obj.Controls.Fit};
                for j=1:5,hs{j}.Layout.Row=1;hs{j}.Layout.Column=j;end
                obj.FooterGrid.ColumnWidth={'1x',230,330};obj.FooterGrid.RowHeight={25};
                fs={obj.ScopeLabel,obj.MetricLabel,obj.CoverageLabel};
                for j=1:3,fs{j}.Layout.Row=1;fs{j}.Layout.Column=j;end
                obj.OuterGrid.RowHeight={56,'1x',29};
            end
            side=width>=900;if ~isempty(obj.UserSidebar),side=obj.UserSidebar;end
            if side
                obj.RootGrid.ColumnWidth={278,'1x'};obj.Sidebar.Visible='on';
                obj.Controls.Sidebar.Text='Hide controls';
            else
                obj.RootGrid.ColumnWidth={0,'1x'};obj.Sidebar.Visible='off';
                obj.Controls.Sidebar.Text='☰ Controls';
            end
            if width>=1280
                nc=3;obj.PlotGrid.ColumnWidth={'1x','1x','1x'};
                if height>=680,obj.PlotGrid.RowHeight={'1x','1x'};obj.PlotGrid.Scrollable='off';
                else,obj.PlotGrid.RowHeight={260,260};obj.PlotGrid.Scrollable='on';end
            elseif width>=1000
                nc=2;obj.PlotGrid.ColumnWidth={'1x','1x'};
                if height>=680,obj.PlotGrid.RowHeight={'1x','1x','1x'};obj.PlotGrid.Scrollable='off';
                else,obj.PlotGrid.RowHeight={240,240,240};obj.PlotGrid.Scrollable='on';end
            else
                nc=1;obj.PlotGrid.ColumnWidth={'1x'};obj.PlotGrid.RowHeight=repmat({280},1,6);obj.PlotGrid.Scrollable='on';
            end
            for k=1:6,obj.Panels(k).Layout.Row=ceil(k/nc);obj.Panels(k).Layout.Column=mod(k-1,nc)+1;end
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
    methods (Static,Access=private)
        function value=field(s,name,fallback)
            value=fallback;if isstruct(s) && isfield(s,name),value=s.(name);end
        end
    end
end
