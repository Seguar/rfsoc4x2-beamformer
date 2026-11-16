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
    v.Figure.Position=[10 10 widths(k) 768];drawnow;
    assert(numel(v.PlotGrid.ColumnWidth)==cols(k),'Real SizeChangedFcn did not update plot columns.');
end
v.Figure.Position=[10 10 1366 500];drawnow;assert(strcmp(v.PlotGrid.Scrollable,'on'));
v.Figure.Position=[10 10 1366 768];drawnow;
assert(strcmp(v.PlotGrid.Scrollable,'off'),'Six panels should fit at 1366x768.');
s=snapshot(1);v.show(s);drawnow;
n=numel(findall(v.Figure));
for k=2:30,s=snapshot(k);v.show(s);end
assert(numel(findall(v.Figure))==n,'Per-frame rendering rebuilt graphics.');
assert(v.LastSequence==30 && numel(v.HistorySequence)==30);
assert(contains(v.EvmLabel.Text,'4.00') && contains(v.EvmLabel.Text,'-28.0'));
assert(contains(v.CoverageLabel.Text,'DEGRADED') && contains(v.CoverageLabel.Text,'clean-only'));
assert(numel(v.Lines.timeI.XData)<=2048 && numel(v.Lines.timeQ.XData)<=2048);
assert(any(isfinite(v.Lines.payload.XData)) && any(isfinite(v.Lines.spectrum.YData)));
% User zoom persists until the explicit Fit plots action.
v.Ax.spectrum.XLim=[-10 10];v.show(snapshot(31));
assert(isequal(v.Ax.spectrum.XLim,[-10 10]));
set(v.Lines.payload,'XData',[0 2.2],'YData',[0 -2.2]);v.fitPlots();
assert(v.Ax.constellation.XLim(2)>2.2 && v.Ax.constellation.YLim(1)<-2.2);
% Only OFDM can be unavailable while the same acquired frame remains valid.
s=snapshot(32);s.analysis.valid=false;s.analysis.reason='synthetic OFDM no sync';v.show(s);
assert(any(isfinite(v.Lines.doa.YData)) && any(isfinite(v.Lines.timeI.YData)));
assert(all(isnan(v.Lines.payload.XData)) && strcmp(v.EvmLabel.Text,'EVM —'));
% A stale/invalid acquisition clears every current plot and keeps labelled history.
v.show(struct('valid',false,'reason','STALE synthetic fixture'));
for name=["doa","pattern","spectrum","timeI","timeQ","payload","header","pilots","evmCurrent"]
    assert(all(isnan(v.Lines.(name).XData)) && all(isnan(v.Lines.(name).YData)));
end
assert(contains(v.Ax.evm.Parent.Parent.Title,'History only') && isnan(v.LastSequence));
% Callback changes map to supported session fields and refusals revert values.
h=v.Controls.bf;old=h.Value;h.Value='MVDR';h.ValueChangedFcn(h,struct());
assert(strcmp(calls{end}.name,'configure') && strcmp(calls{end}.value.bf,'MVDR'));
reject=true;h.Value='DMR';h.ValueChangedFcn(h,struct());
assert(strcmp(h.Value,'MVDR') && contains(v.Controls.Error.Text,'deliberate'));
reject=false;
h=v.Controls.CompareVsa;h.Value=true;h.ValueChangedFcn(h,struct());
assert(string(calls{end}.value.analyzer)=='both');
h=v.Controls.Pause;h.Value=true;h.ValueChangedFcn(h,struct());
assert(strcmp(calls{end}.name,'pause') && calls{end}.value);
v.Controls.adcMHz.Value=3050;v.Controls.dacMHz.Value=3050;
v.Controls.ApplyRF.ButtonPushedFcn(v.Controls.ApplyRF,struct());
assert(calls{end}.value.adcMHz==3050 && strcmp(calls{end}.name,'rf'));
v.Controls.phase1.Value=45;v.Controls.ApplyPhase.ButtonPushedFcn(v.Controls.ApplyPhase,struct());
assert(strcmp(calls{end}.name,'phase') && calls{end}.value.values(1)==45);
% A calibration load can enable the previously unavailable correction option.
cfg.calibration.powCalibration=ones(121,4);cfg.calibration.steeringCorrection=ones(121,4);
v.updateConfig(cfg);assert(strcmp(v.Controls.phComp.Enable,'on'));
v.show(snapshot(33));v.Figure.Name='SYNTHETIC GUI FIXTURE — NOT HARDWARE';
try,exportapp(v.Figure,fullfile(outDir,'synthetic-six-panel.png'));catch err
    warning('view:Screenshot','Synthetic screenshot unavailable: %s',err.message);
end
close(v.Figure);assert(strcmp(calls{end}.name,'close') && ~v.isOpen());delete(v);
assert(numel(findall(groot,'Type','figure'))==figures0 && numel(timerfindall)==timers0,'View leaked resources.');
% A direct-only session must not offer unmeasured streams or Combined.
cfg.directOnly=true;cfg.ch=1;v=origapp.BeamformerView(cfg,struct());
assert(numel(v.Controls.ch.Items)==1 && v.Controls.ch.Value==1);
assert(strcmp(v.Controls.Start.Enable,'off') && strcmp(v.Controls.Pause.Enable,'off'));
delete(v);
report=struct('label','SYNTHETIC GUI ONLY — no board/VSA', 'axes',6,'resizeWidths',widths, ...
    'persistentObjectCount',n,'callbacks',numel(calls),'leakedFigures',numel(findall(groot,'Type','figure'))-figures0, ...
    'leakedTimers',numel(timerfindall)-timers0);
fid=fopen(fullfile(outDir,'view-validation.json'),'w');fprintf(fid,'%s\n',jsonencode(report));fclose(fid);
disp('BEAMFORMER_VIEW_COMPLETE');
    function mark(name,value),calls{end+1}=struct('name',name,'value',value);end
    function configure(value)
        if reject,error('view:NegativeControl','deliberate unsupported setting');end
        mark('configure',value);
    end
end
function s=snapshot(seq)
scan=-60:60;t=(0:32767)'/125e6;
x=.01*exp(1j*2*pi*5e6*t);
pts=(-3:2:3)/sqrt(10);[a,b]=meshgrid(pts);
r=struct('valid',true,'degraded',true,'evmPercent',4,'evmDb',20*log10(.04), ...
    'qualifiedBursts',4,'metricBursts',5,'qualifiedPayloadEvmPercent',3.2, ...
    'constellation',struct('payload',a(:)+1j*b(:),'header',[-1;1],'pilot',[1;1j]), ...
    'cfoHz',120,'rxLevelDbfs',-30);
s=struct('valid',true,'reason','','sequence',seq,'timestamp',1,'age',.1, ...
    'scope','SYNTHETIC ULA model — NOT HARDWARE','scan',scan, ...
    'doaSpectrum',exp(-((scan-20)/8).^2),'patternDb',-min(80,abs(scan-20)), ...
    'angles',20,'samples',x,'analysis',r, ...
    'spectrum',struct('freqHz',linspace(-62.5e6,62.5e6,256),'psdDbfs',-70+30*exp(-(linspace(-1,1,256)/.3).^2)));
end
