function report=validateBeamformerView(outDir)
% Synthetic GUI-only fixture: no board, sockets, VSA or DSP estimator.
% Run on a MATLAB host, optionally with -noFigureWindows. All screenshots
% written here are labelled synthetic; never present them as live hardware.
if nargin<1,outDir=tempname;end
if ~isfolder(outDir),mkdir(outDir);end
figures0=numel(findall(groot,'Type','figure'));timers0=numel(timerfindall);
cfg=origapp.defaultConfig();cfg.visible=false;cfg.directOnly=false;cfg.analyzer='integrated';
cfg.fc=3e9;cfg.fc_d0=3e9;cfg.fc_d1=3e9;cfg.fcAnt=3e9;cfg.dacPow=[1 0 0 0];
calls={};reject=false;
cb=struct('start',@()mark('start',[]),'pause',@(v)mark('pause',v), ...
    'rf',@(v)mark('rf',v),'dac',@(v)mark('dac',v), ...
    'phase',@(v)mark('phase',v),'configure',@configure,'close',@()mark('close',[]));
v=origapp.BeamformerView(cfg,cb);cleanup=onCleanup(@()delete(v)); %#ok<NASGU>
assert(isempty(calls) && strcmp(v.Figure.Visible,'off'),'View startup performed an action.');
assert(numel(fieldnames(v.Ax))==6 && all(isfield(v.Ax, ...
    {'doa','pattern','spectrum','time','constellation','evm'})));
assert(~any(isfield(v.Controls,{'CustomCommand','Debug','Cutter','Burst','Upload','Pluto','Arduino'})));
assert(strcmp(v.Controls.phComp.Enable,'off'),'Missing calibration must disable correction.');
v.Figure.Visible='on';drawnow;
widths=[1600,1366,1100,850,640];cols=[3,3,2,1,1];
for k=1:numel(widths)
    v.Figure.Position=[10 10 widths(k) 768];
    assert(settle(@()numel(v.PlotGrid.ColumnWidth)==cols(k)),'Real SizeChangedFcn did not update plot columns.');
    % Stacked pairs: pattern under DOA, time under spectrum, EVM under constellation.
    L=@(n)v.Ax.(n).Parent.Parent.Layout;
    if cols(k)>1
        assert(L('pattern').Column==L('doa').Column && L('pattern').Row==L('doa').Row+1 && ...
            L('time').Column==L('spectrum').Column && L('time').Row==L('spectrum').Row+1);
    end
    if cols(k)==3,assert(L('evm').Column==L('constellation').Column && L('evm').Row==L('constellation').Row+1);end
end
v.Figure.Position=[10 10 1366 500];assert(settle(@()strcmp(v.PlotGrid.Scrollable,'on')));
v.Figure.Position=[10 10 1366 768];
assert(settle(@()strcmp(v.PlotGrid.Scrollable,'off')),'Six panels should fit at 1366x768.');
s=snapshot(1);v.show(s);drawnow;
n=numel(findall(v.Figure));
for k=2:30,s=snapshot(k);v.show(s);end
assert(numel(findall(v.Figure))==n,'Per-frame rendering rebuilt graphics.');
assert(v.LastSequence==30 && numel(v.HistorySequence)==30);
assert(contains(v.EvmLabel.Text,'4.00') && contains(v.Kpi.evmDb.value.Text,'-28.0'));
% Readout tiles carry metrics the analyzer already computed, nothing invented.
assert(contains(v.Kpi.bursts.value.Text,'4 / 5') && contains(v.Kpi.sync.value.Text,'0.93'));
assert(contains(v.Kpi.cfo.sub.Text,'drift') && contains(v.Kpi.rx.sub.Text,'ADC peak'));
assert(contains(v.Kpi.rate.sub.Text,'30 accepted') && contains(v.Monitor.counts.Text,'expired 1') && ...
    contains(v.Monitor.counts.Text,'other errors 0'));
h31=snapshot(31).health;h31.accepted=77;v.showHealth(h31);assert(contains(v.Kpi.rate.sub.Text,'77 accepted'));
% Per-stream monitor: level, phase against the first stream and applied weight.
assert(strcmp(v.Monitor.cell(2,3).Text,'+90.0') && strcmp(v.Monitor.cell(1,5).Text,'0.0'));
assert(size(v.ChannelPhase,1)==30 && v.ChannelPhase(end,3)==-45);
assert(strcmp(v.Marks.doa(1).Visible,'on') && v.Marks.doa(1).Value==20 && contains(v.Marks.doa(1).Label,'model'));
assert(any(isfinite(v.Lines.burstOk.XData)) && any(isfinite(v.Lines.burstBad.XData)));
assert(contains(v.CoverageLabel.Text,'DEGRADED') && contains(v.CoverageLabel.Text,'clean-only'));
assert(numel(v.Lines.timeI.XData)<=2048 && numel(v.Lines.timeQ.XData)<=2048);
assert(any(isfinite(v.Lines.payload.XData)) && any(isfinite(v.Lines.spectrum.YData)));
% User zoom persists until the explicit Fit plots action.
v.Ax.spectrum.XLim=[-10 10];v.show(snapshot(31));
assert(isequal(v.Ax.spectrum.XLim,[-10 10]));
set(v.Lines.payload,'XData',[0 2.2],'YData',[0 -2.2]);v.fitPlots();
assert(v.Ax.constellation.XLim(2)>2.2 && v.Ax.constellation.YLim(1)<-2.2);
% Plot modes reuse the same six axes with persistent objects only.
n2=numel(findall(v.Figure));
h=v.Controls.EvmMode;h.Value='subcarrier';h.ValueChangedFcn(h,struct());
assert(strcmp(v.Lines.evmSub.Visible,'on') && strcmp(v.Lines.evmHistory.Visible,'off') && ...
    strcmp(v.Empty.evm.Visible,'off'));
v.show(snapshot(31));assert(contains(v.Card.evm.note.Text,'worst 9.0 % at k=7'));
h.Value='symbol';h.ValueChangedFcn(h,struct());v.show(snapshot(31));
assert(strcmp(v.Lines.evmSym.Visible,'on') && numel(v.Lines.evmSym.XData)==10);
h.Value='history';h.ValueChangedFcn(h,struct());assert(strcmp(v.Lines.evmHistory.Visible,'on'));
% The EVM graph switches between percent and dB of the same stored values.
h=v.Controls.EvmUnit;h.Value=true;h.ValueChangedFcn(h,struct());
y=v.Lines.evmHistory.YData;assert(abs(y(find(isfinite(y),1))-20*log10(.04))<1e-9 && contains(v.Ax.evm.YLabel.String,'dB') && ...
    abs(v.Lines.evmCurrent.YData-20*log10(.04))<1e-9 && abs(v.Marks.evmMedian.Value-20*log10(.04))<1e-9);
v.show(snapshot(31));assert(v.Ax.evm.YLim(1)<20*log10(.04) && all(v.HistoryEvm==4));
h.Value=false;h.ValueChangedFcn(h,struct());
y=v.Lines.evmHistory.YData;assert(y(find(isfinite(y),1))==4 && contains(v.Ax.evm.YLabel.String,'%') && v.Ax.evm.YLim(1)==0);
h=v.Controls.TimeMode;h.Value='phase';h.ValueChangedFcn(h,struct());
assert(strcmp(v.Lines.chPhase(2).Visible,'on') && strcmp(v.Lines.timeI.Visible,'off') && ...
    contains(v.Ax.time.YLabel.String,'Phase'));
h.Value='iq';h.ValueChangedFcn(h,struct());assert(strcmp(v.Lines.timeI.Visible,'on'));
h=v.Controls.MaxHold;h.Value=true;h.ValueChangedFcn(h,struct());v.show(snapshot(31));
assert(strcmp(v.Lines.spectrumHold.Visible,'on') && any(isfinite(v.Lines.spectrumHold.YData)));
h.Value=false;h.ValueChangedFcn(h,struct());
assert(numel(findall(v.Figure))==n2,'Plot modes created or deleted graphics.');
% View-only hold keeps the held frame, says so, and never survives an invalid acquisition.
h=v.Controls.Hold;h.Value=true;h.ValueChangedFcn(h,struct());v.show(snapshot(40));
assert(v.Held && v.LastSequence==31 && strcmp(v.StatePill.Text,'HELD') && ...
    contains(v.StatusLabel.Text,'NOT LIVE') && contains(v.StatusLabel.Text,'40') && numel(v.HistorySequence)==31);
v.show(struct('valid',false,'reason','synthetic reject during hold'));
assert(~v.Held && ~h.Value && all(isnan(v.Lines.doa.YData)),'Hold kept an invalid acquisition on screen.');
h.Value=true;h.ValueChangedFcn(h,struct());assert(~v.Held && ~h.Value,'Hold without a frame must refuse.');
v.show(snapshot(31));
% Live light/dark switch recolours every object in place and is reversible.
for name=["dark","light"]
    c=cell2mat(struct2cell(origapp.BeamformerView.palette(char(name))));
    assert(size(unique(round(c,3),'rows'),1)==size(c,1),'Palette entries must be unique for a reversible switch.');
end
dark=origapp.BeamformerView.palette('dark');light=origapp.BeamformerView.palette('light');
n3=numel(findall(v.Figure));before=themeColours(v);
v.Controls.ThemeSwitch.ButtonPushedFcn(v.Controls.ThemeSwitch,struct());
assert(strcmp(v.ThemeName,'light') && isequal(v.Figure.Color,light.bg) && isequal(v.Ax.doa.Color,light.panel) && ...
    isequal(v.Lines.spectrum.Color,light.s1) && isequal(v.Lines.payload.MarkerFaceColor,light.s1) && ...
    isequal(v.TitleLabel.FontColor,light.text) && isequal(v.Kpi.evm.value.FontColor,light.warn) && ...
    isequal(v.Ax.evm.XColor,light.dim) && isequal(v.Controls.bf.BackgroundColor,light.input));
v.show(snapshot(31));assert(isequal(v.StatePill.FontColor,light.ok) && isequal(v.Kpi.sync.edge.BackgroundColor,light.ok));
drawnow;try,exportapp(v.Figure,fullfile(outDir,'synthetic-light.png'));catch,end
v.Figure.WindowKeyPressFcn(v.Figure,struct('Key','f7','Modifier',{{}}));
assert(strcmp(v.ThemeName,'dark') && isequal(themeColours(v),before) && isequal(v.Figure.Color,dark.bg));
assert(numel(findall(v.Figure))==n3,'Theme switch created or deleted graphics.');
% Function keys use the same paths as the buttons.
v.Figure.WindowKeyPressFcn(v.Figure,struct('Key','f3','Modifier',{{}}));assert(v.Held);
v.Figure.WindowKeyPressFcn(v.Figure,struct('Key','f3','Modifier',{{}}));assert(~v.Held);
v.Figure.WindowKeyPressFcn(v.Figure,struct('Key','f','Modifier',{{}}));
v.show(snapshot(31));
% Only OFDM can be unavailable while the same acquired frame remains valid.
s=snapshot(32);s.analysis.valid=false;s.analysis.reason='synthetic OFDM no sync';v.show(s);
assert(any(isfinite(v.Lines.doa.YData)) && any(isfinite(v.Lines.timeI.YData)));
assert(all(isnan(v.Lines.payload.XData)) && strcmp(v.EvmLabel.Text,'—'));
% A refused / unlocked analysis with a high sync peak is not called a sync failure.
s.analysis.syncThreshold=.8;s.analysis.state="REFUSED";v.show(s);
assert(strcmp(v.Kpi.sync.sub.Text,'REFUSED') && contains(v.Kpi.sync.value.Text,'0.93'));
s.sequence=32.5;s.analysis.syncPeak=.4;v.show(s);assert(contains(v.Kpi.sync.sub.Text,'below sync threshold'));
% One weight (single-stream output) is not attributed to a table row.
s.sequence=32.6;s.weights=.5+.5j;v.show(s);assert(strcmp(v.Monitor.cell(1,5).Text,'—'));
assert(strcmp(v.Empty.constellation.Visible,'on') && strcmp(v.Empty.doa.Visible,'off'));
% A stale/invalid acquisition clears every current plot and keeps labelled history.
v.show(struct('valid',false,'reason','STALE synthetic fixture'));
for name=["doa","pattern","spectrum","timeI","timeQ","payload","header","pilots","evmCurrent"]
    assert(all(isnan(v.Lines.(name).XData)) && all(isnan(v.Lines.(name).YData)));
end
assert(contains(v.Card.evm.note.Text,'History only') && isnan(v.LastSequence));
assert(strcmp(v.StatePill.Text,'STALE') && strcmp(v.Empty.spectrum.Visible,'on'));
assert(strcmp(v.Kpi.rate.value.Text,'—') && contains(v.ScopeLabel.Text,'UNCALIBRATED'));
assert(any(contains(v.EventLog,'STALE synthetic fixture')));
% Callback changes map to supported session fields and refusals revert values.
h=v.Controls.bf;old=h.Value;h.Value='MVDR';h.ValueChangedFcn(h,struct());
assert(strcmp(calls{end}.name,'configure') && strcmp(calls{end}.value.bf,'MVDR'));
drawnow;where=getpixelposition(v.Controls.doa,true);
reject=true;h.Value='DMR';h.ValueChangedFcn(h,struct());
assert(strcmp(h.Value,'MVDR') && contains(v.Controls.Error.Text,'deliberate'));
drawnow;assert(isequal(getpixelposition(v.Controls.doa,true),where), ...
    'A refusal moved the selectors (scripts and users click them by position).');
reject=false;
% Field limits are the accepted ranges (origapp.processingLimits, measured RF limits).
C=v.Controls;
lims=struct('num',C.num.Limits,'adc',C.adcMHz.Limits,'dac',C.dacMHz.Limits,'phase',C.phase1.Limits, ...
    'bw',C.bwMHz.Limits,'res',C.scan_res.Limits,'scanbw',C.scan_bw.Value);
assert(isequal(lims.num,[1 3]) && isequal(lims.adc,[0 6000]) && isequal(lims.dac,[-6000 6000]) ...
    && isequal(lims.phase,[-179.99 179.99]) && lims.bw(2)==125 && lims.res(2)==lims.scanbw, ...
    'Field limits do not match the accepted ranges: %s',jsonencode(lims));
h=v.Controls.bf;h.Value='DL ITER MVDR';h.ValueChangedFcn(h,struct());
assert(isequal(C.alpha.Limits,[0 2]) && string(C.alpha.LowerLimitInclusive)=="off" && string(C.alpha.UpperLimitInclusive)=="off", ...
    'Iterative MVDR uncertainty limits not applied.');
h.Value='MVDR';h.ValueChangedFcn(h,struct());
assert(isinf(C.alpha.Limits(2)),'Uncertainty limits not released for MVDR.');
h=C.scan_bw;h.Value=60;h.ValueChangedFcn(h,struct());
assert(C.scan_res.Limits(2)==60,'Scan step limit does not follow the scan width.');
h=C.avg_factor;h.Value=1000;h.ValueChangedFcn(h,struct());
assert(C.scan_res.Limits(1)>1e-4,'Scan step lower limit does not follow averaging.');
avg0=C.avg_factor.Value;
h=C.avg_factor;h.Value=10;h.ValueChangedFcn(h,struct());h=C.scan_bw;h.Value=120;h.ValueChangedFcn(h,struct());
assert(avg0==1000 && C.scan_res.Limits(2)==120);
h=v.Controls.CompareVsa;h.Value=true;h.ValueChangedFcn(h,struct());
assert(string(calls{end}.value.analyzer)=='both');
h=v.Controls.Pause;h.Value=true;h.ValueChangedFcn(h,struct());
assert(strcmp(calls{end}.name,'pause') && calls{end}.value && strcmp(h.Text,'Resume'));
v.Controls.adcMHz.Value=3050;v.Controls.dacMHz.Value=3050;
v.Controls.ApplyRF.ButtonPushedFcn(v.Controls.ApplyRF,struct());
assert(calls{end}.value.adcMHz==3050 && strcmp(calls{end}.name,'rf'));
v.Controls.phase1.Value=45;v.Controls.ApplyPhase.ButtonPushedFcn(v.Controls.ApplyPhase,struct());
assert(strcmp(calls{end}.name,'phase') && calls{end}.value.values(1)==45);
% A calibration load can enable the previously unavailable correction option.
cfg.calibration.powCalibration=ones(121,4);cfg.calibration.steeringCorrection=ones(121,4);
v.updateConfig(cfg);assert(strcmp(v.Controls.phComp.Enable,'on'));
h=v.Controls.Pause;h.Value=false;h.ValueChangedFcn(h,struct());assert(strcmp(h.Text,'Pause'));
v.show(snapshot(33));v.Figure.Name='SYNTHETIC GUI FIXTURE — NOT HARDWARE';
% The history line is broken across rejected acquisitions, never joined.
assert(v.HistorySequence(end)==33 && v.HistoryBreak(end) && any(isnan(v.Lines.evmHistory.YData)));
assert(v.ChannelBreak(end) && any(isnan(v.Lines.chPhase(2).YData)),'Stream history joined across a rejection.');
assert(any(contains(v.EventLog,'bf = MVDR')) && any(contains(v.EventLog,'REFUSED')) && ...
    any(contains(v.EventLog,'RF applied')));
% Requested snapshot: MAT with the displayed frame, PNG when the host can render.
files=v.saveSnapshot(fullfile(outDir,'snapshots'));
assert(~isempty(files) && isfile(files{1}));
saved=load(files{1});assert(saved.data.sequence==33 && isfield(saved,'history') && isfield(saved,'settings'));
assert(saved.settings.bwHz==cfg.bw && isequal(saved.settings.phases.DAC,[45 0 0 0]) && ...
    ~isfield(saved.settings,'phase1') && saved.settings.dacEnabled && strcmp(saved.settings.bf,'MVDR'));
for mode=["subcarrier","phase"]
    if mode=="phase",h=v.Controls.TimeMode;else,h=v.Controls.EvmMode;end
    h.Value=char(mode);h.ValueChangedFcn(h,struct());
end
v.show(snapshot(34));v.Controls.PageButton(4).Value=true;v.Controls.PageButton(4).ValueChangedFcn(v.Controls.PageButton(4),struct());
assert(strcmp(v.Controls.PagePanel(4).Visible,'on') && strcmp(v.Controls.PagePanel(1).Visible,'off'));
drawnow;
try,exportapp(v.Figure,fullfile(outDir,'synthetic-diagnostics.png'));catch err
    warning('view:Screenshot','Synthetic screenshot unavailable: %s',err.message);
end
v.Controls.TimeMode.Value='iq';v.Controls.TimeMode.ValueChangedFcn(v.Controls.TimeMode,struct());
v.Controls.EvmMode.Value='history';v.Controls.EvmMode.ValueChangedFcn(v.Controls.EvmMode,struct());
v.Controls.PageButton(1).Value=true;v.Controls.PageButton(1).ValueChangedFcn(v.Controls.PageButton(1),struct());
drawnow;
try,exportapp(v.Figure,fullfile(outDir,'synthetic-six-panel.png'));catch err
    warning('view:Screenshot','Synthetic screenshot unavailable: %s',err.message);
end
nlog=numel(v.EventLog);
frames={snapshot(34),snapshot(35),snapshot(36)};save(fullfile(outDir,'fixture.mat'),'frames'); %#ok<NASGU>
close(v.Figure);assert(strcmp(calls{end}.name,'close') && ~v.isOpen());delete(v);
assert(numel(findall(groot,'Type','figure'))==figures0 && numel(timerfindall)==timers0,'View leaked resources.');
% A session can also start in the light theme.
cfg.theme="light";v=origapp.BeamformerView(cfg,struct());
assert(strcmp(v.ThemeName,'light') && isequal(v.Figure.Color,origapp.BeamformerView.palette('light').bg));
delete(v);cfg.theme="dark";
% A direct-only session must not offer unmeasured streams or Combined.
cfg.directOnly=true;cfg.ch=1;v=origapp.BeamformerView(cfg,struct());
assert(numel(v.Controls.ch.Items)==1 && v.Controls.ch.Value==1);
assert(strcmp(v.Controls.Start.Enable,'off') && strcmp(v.Controls.Pause.Enable,'off'));
delete(v);
report=struct('label','SYNTHETIC GUI ONLY — no board/VSA', 'axes',6,'resizeWidths',widths, ...
    'persistentObjectCount',n,'callbacks',numel(calls),'plotModes',true,'viewOnlyHold',true,'themeSwitch',true, ...
    'snapshotFiles',numel(files),'eventLogLines',nlog,'leakedFigures',numel(findall(groot,'Type','figure'))-figures0, ...
    'leakedTimers',numel(timerfindall)-timers0);
fid=fopen(fullfile(outDir,'view-validation.json'),'w');fprintf(fid,'%s\n',jsonencode(report));fclose(fid);
disp('BEAMFORMER_VIEW_COMPLETE');
    function mark(name,value),calls{end+1}=struct('name',name,'value',value);end
    function configure(value)
        if reject,error('view:NegativeControl','deliberate unsupported setting');end
        mark('configure',value);
    end
end
function c=themeColours(v)
% Every colour-valued property in the window, for an exact round-trip check.
c={};
for p=["Color","BackgroundColor","FontColor","XColor","YColor","GridColor","MarkerFaceColor","FaceColor"]
    h=findall(v.Figure,'-property',char(p));c=[c;get(h,char(p))]; %#ok<AGROW>
end
end
function ok=settle(cond)
% Resize events are delivered asynchronously by the figure's web view; wait
% for the real SizeChangedFcn instead of calling the layout code directly.
t=tic;ok=false;
while toc(t)<10
    drawnow;ok=cond();if ok,return,end
    pause(.05);
end
end
function s=snapshot(seq)
scan=-60:60;t=(0:32767)'/125e6;
% Burst-gated noise-like waveform and noisy cells: a plausible picture only.
st=RandStream('mt19937ar','Seed',seq);gate=mod(t*125e6,5501)<3300 & t*125e6>80;
x=.01*gate.*(randn(st,size(t))+1j*randn(st,size(t)))/sqrt(2)+2e-4*(randn(st,size(t))+1j*randn(st,size(t)));
pts=(-3:2:3)/sqrt(10);[a,b]=meshgrid(pts);
r=struct('valid',true,'degraded',true,'evmPercent',4,'evmDb',20*log10(.04), ...
    'qualifiedBursts',4,'metricBursts',5,'qualifiedPayloadEvmPercent',3.2, ...
    'constellation',struct('payload',repmat(a(:)+1j*b(:),60,1)+.04*(randn(st,960,1)+1j*randn(st,960,1))/sqrt(2), ...
        'header',[-1;1]+.03*randn(st,2,1),'pilot',[1;1j]+.03*randn(st,2,1)), ...
    'cfoHz',120,'rxLevelDbfs',-30,'peakDbfs',-21,'syncPeak',.93,'trainingSnrDb',[31 33], ...
    'samplingErrorPpm',-.4,'headerEvmPercent',3.1,'pilotEvmPercent',2.2, ...
    'evmPerSubcarrierPercent',[repmat(4,1,32) 9 repmat(4,1,19)],'evmSubcarrier',[-26:-1 1:26], ...
    'evmPerSymbolPercent',linspace(3.5,4.5,10),'evmSymbolIndex',1:10, ...
    'candidates',struct('start',{100,5601,11102},'sync',{.93,.92,.9},'accepted',{true,true,false}, ...
        'reason',{"ok","ok","incomplete burst"}), ...
    'perBurst',struct('start',{100,5601},'qualified',{true,false},'rejectionReason',{"","synthetic timing step"}));
ch=struct('available',true(1,4),'levelDbfs',[-41 -41.5 -40.2 -42],'peakDbfs',[-28 -28.4 -27.9 -29], ...
    'clipCount',zeros(1,4),'relPhaseDeg',[0 90 -45 170],'coherence',[1 .998 .997 .995],'reference',1);
health=struct('accepted',seq,'boundary',0,'noSignal',2,'expired',1,'errors',3,'lastError',"");
s=struct('valid',true,'reason','','sequence',seq,'timestamp',1,'age',.1, ...
    'scope','SYNTHETIC ULA model — NOT HARDWARE','scan',scan, ...
    'doaSpectrum',exp(-((scan-20)/8).^2),'patternDb',-min(80,abs(scan-20)), ...
    'angles',20,'samples',x,'analysis',r,'fsHz',125e6,'channels',ch,'health',health, ...
    'weights',[1 1j -1 .5*exp(1j*pi/4)].'/2, ...
    'spectrum',struct('freqHz',linspace(-62.5e6,62.5e6,256),'psdDbfs',-70+30*exp(-(linspace(-1,1,256)/.3).^2)));
end
