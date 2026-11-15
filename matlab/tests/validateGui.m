function report = validateGui(referencePath,directory,arrayMode)
% SIMULATED localhost only. Start tools/gui_fixture.py first with a fresh folder.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
cfg=rfsoc.defaultConfig(); cfg.host="127.0.0.1";
cfg.port=str2double(fileread(fullfile(directory,'port.txt')));
cfg.referencePath=referencePath; cfg.visible=false; cfg.startTimer=false;
if nargin>=3 && arrayMode
    cfg.directOnly=false; cfg.spacingM=299792458/cfg.fcHz/2; cfg.sourceCount=1;
end
cfg.simulated=true; cfg.timeoutSeconds=1; cfg.displayStaleSeconds=5; % allow cold UI rendering
app=runBeamformingDemo(cfg); cleanup=onCleanup(@()closeTest(app.Figure));
callback=app.Timer.TimerFcn;
labels=findall(app.Figure,'Type','uilabel'); scatter=findall(app.Figure,'Type','scatter');
waitFrame(); callback([],[]);
assert(any(contains(string({labels.Text}),'LIVE seq 1')),'Clean frame did not lock.');
assert(any(isfinite(scatter.XData)),'Clean constellation empty.');
iqAxes=scatter.Parent;
inside=scatter.XData>=iqAxes.XLim(1) & scatter.XData<=iqAxes.XLim(2) & ...
    scatter.YData>=iqAxes.YLim(1) & scatter.YData<=iqAxes.YLim(2);
assert(mean(inside)>.9,'Fixed I/Q bounds hide the constellation.');
card=findobj(app.Figure,'Tag','Metric1'); assert(~strcmp(card.Text,'—'),'EVM card empty.');
callback([],[]); % no new frame: current data remains steady, not blinked away
assert(any(isfinite(scatter.XData)),'Display blinked between fresh frames.');
spatialAxes=[findobj(app.Figure,'Tag','DoaSpectrum');findobj(app.Figure,'Tag','ReceivePattern')];
assert(numel(spatialAxes)==2,'Missing DOA/pattern plots.');
if ~cfg.directOnly
    for axis=spatialAxes.'
        lines=findall(axis,'Type','line');
        assert(any(arrayfun(@(line)any(isfinite(line.YData)),lines)),'Missing spatial curve.');
    end
end
advance('advance1'); pause(.3); callback([],[]);
assert(any(contains(string({labels.Text}),'CURRENT EVM UNAVAILABLE')),'Noise not rejected.');
assert(all(isnan(scatter.XData)),'Noise retained current constellation.');
assertSpatialCleared();
assert(strcmp(card.Text,'—'),'Unavailable data retained current EVM card.');
advance('advance2'); pause(cfg.displayStaleSeconds+.1); callback([],[]);
assert(any(contains(string({labels.Text}),'UNAVAILABLE')),'Pause retained current EVM.');
assert(all(isnan(scatter.XData)),'Pause retained constellation.');
assertSpatialCleared();
assert(strcmp(card.Text,'—'),'Unavailable data retained current EVM card.');
axes=findall(app.Figure,'-isa','matlab.ui.control.UIAxes'); history=false;
for k=1:numel(axes), history=history||contains(string(axes(k).YLabel.String),'History'); end
assert(history,'History was not labelled.');
assert(contains(app.Figure.Name,'SIMULATED'),'Missing simulation label.');
close(app.Figure);
assert(~isvalid(app.Timer) && ~isvalid(app.Figure),'Close cleanup failed.');
deadline=tic;
while ~isfile(fullfile(directory,'closed')) && toc(deadline)<3, pause(.05); end
assert(strcmp(strtrim(fileread(fullfile(directory,'closed'))),'1'),'Socket did not close.');
report=struct('passed',true,'source',"SIMULATED localhost", ...
    'clean',true,'noise',true,'pause',true,'history',true,'close',true);
disp('RFSOC_SIMULATED_GUI_PASS');
    function waitFrame()
        deadline=tic;
        while ~app.Source.isFrameReady() && toc(deadline)<3, pause(.01); end
    end
    function assertSpatialCleared()
        for axis=spatialAxes.'
            lines=findall(axis,'Type','line');
            assert(all(arrayfun(@(line)all(isnan(line.YData)),lines)),'Stale spatial plot retained.');
        end
    end
    function advance(name)
        fid=fopen(fullfile(directory,name),'w'); assert(fid>=0,'Handshake write failed.'); fclose(fid);
    end
    function closeTest(figure)
        if isvalid(figure), close(figure); end
    end
end
