function report = validateGui(referencePath,directory)
% SIMULATED localhost only. Start tools/gui_fixture.py first with a fresh folder.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
cfg=rfsoc.defaultConfig(); cfg.host="127.0.0.1";
cfg.port=str2double(fileread(fullfile(directory,'port.txt')));
cfg.referencePath=referencePath; cfg.visible=false; cfg.startTimer=false;
cfg.simulated=true; cfg.timeoutSeconds=1;
app=runBeamformingDemo(cfg); cleanup=onCleanup(@()closeTest(app.Figure));
callback=app.Timer.TimerFcn;
labels=findall(app.Figure,'Type','uilabel'); scatter=findall(app.Figure,'Type','scatter');
callback([],[]);
assert(any(contains(string({labels.Text}),'LIVE seq 1')),'Clean frame did not lock.');
assert(any(isfinite(scatter.XData)),'Clean constellation empty.');
advance('advance1'); pause(.3); callback([],[]);
assert(any(contains(string({labels.Text}),'CURRENT EVM UNAVAILABLE')),'Noise not rejected.');
assert(all(isnan(scatter.XData)),'Noise retained current constellation.');
advance('advance2'); callback([],[]);
assert(any(contains(string({labels.Text}),'UNAVAILABLE')),'Pause retained current EVM.');
assert(all(isnan(scatter.XData)),'Pause retained constellation.');
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
    function advance(name)
        fid=fopen(fullfile(directory,name),'w'); assert(fid>=0,'Handshake write failed.'); fclose(fid);
    end
    function closeTest(figure)
        if isvalid(figure), close(figure); end
    end
end
