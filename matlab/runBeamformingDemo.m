function app = runBeamformingDemo(cfg)
% Readable MATLAB frontend; original App Designer binaries remain references.
% The board capture owner must already be running. This app never programs RF.
if nargin==0, cfg=rfsoc.defaultConfig(); end
if ~isfield(cfg,'displayStaleSeconds'), cfg.displayStaleSeconds=1; end
validateattributes(cfg.displayStaleSeconds,{'numeric'},{'scalar','finite','positive'});
ref=rfsoc.loadReference(cfg.referencePath);
assert(ref.fsHz==cfg.fsHz,'rfsoc:Rate','Reference sample rate mismatch.');
cfg.latestOnly=true; % display skips queued frames; transport validation stays strict
source=[]; vsa=[]; fixedWeights=[]; tick=[]; frameCount=0;
iqTrail={};
history=zeros(0,3); started=tic; lastFrame=tic; lastResult=[];
visibility='on'; if isfield(cfg,'visible') && ~cfg.visible, visibility='off'; end
fig=uifigure('Visible',visibility,'Name','RFSoC4x2 MATLAB + VSA','Position',[70 45 1280 960],'Color',[0.035 0.05 0.085]);
grid=uigridlayout(fig,[10 4]); grid.RowHeight={26,68,26,34,28,'1x','1x','1x','1x',36};
grid.BackgroundColor=fig.Color; grid.Padding=[18 12 18 12]; grid.RowSpacing=9; grid.ColumnSpacing=14;
brand=uilabel(grid,'Text','RFSoC  /  VECTOR SIGNAL ANALYZER','FontSize',16,'FontWeight','bold');
brand.Layout.Row=1; brand.Layout.Column=[1 4]; brand.FontColor=[.8 .9 1];
evmDbValue=metricCard(1,'PAYLOAD EVM  /  dB',[.2 .85 1]);
evmPctValue=metricCard(2,'PAYLOAD EVM  /  %',[.2 .85 1]);
rxValue=metricCard(3,'RECEIVED LEVEL  /  dBFS',[.4 .95 .72]);
berValue=metricCard(4,'BIT ERROR RATE',[1 .74 .35]);
status=uilabel(grid,'Text','Connecting; no current EVM'); status.Layout.Row=3; status.Layout.Column=[1 4]; status.FontColor=[.65 .75 .85]; status.FontName='Consolas';
algorithm=uidropdown(grid,'Items',cellstr(rfsoc.algorithmNames()),'Value',char(cfg.algorithm));
algorithm.Layout.Row=4; algorithm.Layout.Column=1;
track=uicheckbox(grid,'Text','Track wanted DAC','Value',cfg.tracking);
track.Layout.Row=4; track.Layout.Column=2;
calibrate=uibutton(grid,'Text','Freeze broadside baseline','ButtonPushedFcn',@freezeBaseline);
calibrate.Layout.Row=4; calibrate.Layout.Column=3;
stopButton=uibutton(grid,'Text','Stop acquisition','ButtonPushedFcn',@closeApp);
stopButton.Layout.Row=4; stopButton.Layout.Column=4;
doaMethod=uidropdown(grid,'Items',{'Beamscan','MVDR','MUSIC'},'Value',char(cfg.doaMethod));
doaMethod.Layout.Row=5; doaMethod.Layout.Column=1;
doaLabel=uilabel(grid,'Text','DOA spectrum: peaks may include interferers; pilot marks wanted DAC.');
doaLabel.Layout.Row=5; doaLabel.Layout.Column=[2 4];
evmAxes=uiaxes(grid); evmAxes.Layout.Row=[6 7]; evmAxes.Layout.Column=[1 2];
hold(evmAxes,'on');
evmGlow=plot(evmAxes,NaN,NaN,'Color',[.04 .25 .32],'LineWidth',6,'HandleVisibility','off');
evmLine=plot(evmAxes,NaN,NaN,'DisplayName','Selected','Color',[.2 .85 1],'LineWidth',2);
baselineLine=plot(evmAxes,NaN,NaN,'--','DisplayName','Frozen broadside','Color',[1 .72 .32],'LineWidth',1.4);
ylabel(evmAxes,'History: held-out payload EVM (dB)'); xlabel(evmAxes,'Time (s)'); legend(evmAxes);
iqAxes=uiaxes(grid); iqAxes.Layout.Row=6; iqAxes.Layout.Column=[3 4];
hold(iqAxes,'on');
trailLine=plot(iqAxes,NaN,NaN,'.','Color',[.12 .29 .4],'MarkerSize',4,'DisplayName','Previous 2 frames');
ideal=unique(ref.symbols(:));
plot(iqAxes,real(ideal),imag(ideal),'+','Color',[.5 .6 .7],'MarkerSize',10,'LineWidth',1.2,'DisplayName','Reference');
iqLine=scatter(iqAxes,NaN,NaN,12,[.2 .85 1],'.','DisplayName','Current frame');
iqLimit=1.6*max([abs(real(ideal));abs(imag(ideal));eps]);
xlim(iqAxes,[-iqLimit iqLimit]); ylim(iqAxes,[-iqLimit iqLimit]); iqAxes.DataAspectRatio=[1 1 1];
xlabel(iqAxes,'In phase'); ylabel(iqAxes,'Quadrature'); title(iqAxes,'CONSTELLATION · 2-frame persistence');
phaseAxes=uiaxes(grid); phaseAxes.Layout.Row=7; phaseAxes.Layout.Column=[3 4];
phaseBars=bar(phaseAxes,zeros(1,4),'FaceColor',[.27 .7 .95],'EdgeColor','none'); ylim(phaseAxes,[-180 180]);
ylabel(phaseAxes,'Pilot phase (degrees)'); xlabel(phaseAxes,'Receive stream');
doaAxes=uiaxes(grid,'Tag','DoaSpectrum'); doaAxes.Layout.Row=[8 9]; doaAxes.Layout.Column=[1 2];
doaLine=plot(doaAxes,NaN,NaN,'DisplayName','DOA spectrum'); hold(doaAxes,'on');
wantedLine=plot(doaAxes,NaN,NaN,'--','DisplayName','Wanted pilot match');
peakLine=plot(doaAxes,NaN,NaN,'o','DisplayName','Spectrum peaks');
xlabel(doaAxes,'Model angle from broadside (degrees)'); ylabel(doaAxes,'Normalized DOA spectrum (dB)');
xlim(doaAxes,[-90 90]); ylim(doaAxes,[-60 3]); legend(doaAxes);
patternAxes=uiaxes(grid,'Tag','ReceivePattern'); patternAxes.Layout.Row=[8 9]; patternAxes.Layout.Column=[3 4];
patternLine=plot(patternAxes,NaN,NaN,'DisplayName','Selected weights'); hold(patternAxes,'on');
fixedPatternLine=plot(patternAxes,NaN,NaN,'--','DisplayName','Frozen baseline');
xlabel(patternAxes,'Model angle from broadside (degrees)'); ylabel(patternAxes,'Normalized receive pattern (dB)');
xlim(patternAxes,[-90 90]); ylim(patternAxes,[-60 3]); legend(patternAxes);
for axesHandle=[evmAxes iqAxes phaseAxes doaAxes patternAxes]
    axesHandle.Color=[.055 .08 .125]; axesHandle.XColor=[.58 .68 .78]; axesHandle.YColor=[.58 .68 .78];
    axesHandle.GridColor=[.35 .5 .65]; axesHandle.GridAlpha=.16; axesHandle.XGrid='on'; axesHandle.YGrid='on';
    axesHandle.FontName='Segoe UI'; axesHandle.FontSize=10; axesHandle.Box='off';
    axesHandle.Title.Color=[.85 .92 1]; axesHandle.Title.FontSize=12;
    if ~isempty(axesHandle.Legend)
        axesHandle.Legend.Color=axesHandle.Color; axesHandle.Legend.TextColor=[.7 .8 .9]; axesHandle.Legend.EdgeColor='none';
    end
end
title(evmAxes,'ERROR VECTOR MAGNITUDE'); title(phaseAxes,'CHANNEL PHASE');
title(doaAxes,'DIRECTION OF ARRIVAL'); title(patternAxes,'RECEIVE BEAM PATTERN');
set([doaLine patternLine],'Color',[.25 .87 1],'LineWidth',2);
set([wantedLine fixedPatternLine],'Color',[1 .72 .32],'LineWidth',1.3);
peakLine.Color=[.4 1 .74]; peakLine.MarkerFaceColor=[.4 1 .74];
for control=[algorithm doaMethod]
    control.BackgroundColor=[.09 .13 .2]; control.FontColor=[.85 .92 1];
end
track.FontColor=[.75 .85 .95];
for control=[calibrate stopButton]
    control.BackgroundColor=[.1 .17 .24]; control.FontColor=[.8 .9 1];
end
doaLabel.FontColor=[.6 .73 .85];
note=uilabel(grid,'Text','Array results require measured spacing and calibration.');
note.FontColor=[.55 .66 .78]; note.FontSize=11;
note.Layout.Row=10; note.Layout.Column=[1 4];
if cfg.directOnly
    algorithm.Enable='off'; track.Enable='off'; calibrate.Enable='off'; doaMethod.Enable='off';
    doaLabel.Text='DOA and pattern unavailable: single-channel direct cable.';
    note.Text='Direct DAC_B → 20 dB → ADC_D (stream 0). Single channel; beamforming gain unmeasured.';
end
if ~cfg.useVsa, note.Text=[note.Text,' VSA unavailable (disabled).']; end
if isfield(cfg,'simulated') && cfg.simulated
    fig.Name=['SIMULATED localhost | ',fig.Name]; note.Text=['SIMULATED localhost. ',note.Text];
end
fig.CloseRequestFcn=@closeApp;
try
    if cfg.useVsa, vsa=rfsoc.VsaSession(cfg.vsa); end
    source=rfsoc.FrameSource(cfg);
    tick=timer('ExecutionMode','fixedSpacing','Period',0.05, ...
        'BusyMode','drop','TimerFcn',@update,'ErrorFcn',@timerError);
    if ~isfield(cfg,'startTimer') || cfg.startTimer, start(tick); end
catch exception
    closeApp(); rethrow(exception);
end
app=struct('Figure',fig,'Timer',tick,'Source',source);
    function update(~,~)
        if ~isvalid(fig), return; end
        try
            % Keep a genuine frame visible between arrivals; never synthesize IQ.
            % Polling avoids blanking every plot before each blocking read.
            if ~source.isFrameReady()
                if toc(lastFrame)>cfg.displayStaleSeconds
                    clearCurrent();
                    status.Text=sprintf('STALE %.1fs | CURRENT EVM UNAVAILABLE',toc(lastFrame));
                    status.FontColor=[1 .65 .3];
                end
                return;
            end
            frame=source.next(); lastFrame=tic;
            cfg.algorithm=string(algorithm.Value); cfg.tracking=track.Value; cfg.doaMethod=string(doaMethod.Value);
            result=rfsoc.processFrame(frame.samples,cfg,ref,fixedWeights);
            lastResult=result; frameCount=frameCount+1;
            baseline=NaN;
            if ~isempty(result.baselineMetric), baseline=result.baselineMetric.evmDb; end
            history(end+1,:)=[toc(started),result.metric.evmDb,baseline]; %#ok<AGROW>
            history=history(max(1,end-299):end,:);
            evmLine.XData=history(:,1); evmLine.YData=history(:,2);
            baselineLine.XData=history(:,1); baselineLine.YData=history(:,3);
            evmGlow.XData=history(:,1); evmGlow.YData=history(:,2);
            if history(end,1)>30, xlim(evmAxes,[history(end,1)-30 history(end,1)]); end
            if ~isempty(iqTrail)
                previous=vertcat(iqTrail{:});
                trailLine.XData=real(previous); trailLine.YData=imag(previous);
            end
            iqLine.XData=real(result.constellation(:)); iqLine.YData=imag(result.constellation(:));
            iqTrail{end+1}=result.constellation(:); iqTrail=iqTrail(max(1,end-1):end);
            evmDbValue.Text=sprintf('%.2f',result.metric.evmDb);
            evmPctValue.Text=sprintf('%.2f',result.metric.evmPercent);
            rxValue.Text=sprintf('%.1f',result.inputRmsDbfs(cfg.activeChannel));
            berValue.Text=sprintf('%.3g',result.metric.ber);
            status.FontColor=[.4 .95 .72];
            phaseBars.YData=rad2deg(angle(result.pilotManifold./result.pilotManifold(cfg.activeChannel)));
            if result.spatial.available
                sp=result.spatial;
                doaLine.XData=sp.anglesDeg; doaLine.YData=sp.spectrumDb;
                wantedLine.XData=sp.anglesDeg; wantedLine.YData=sp.wantedScoreDb;
                peakLine.XData=sp.peakAnglesDeg;
                peakLine.YData=interp1(sp.anglesDeg,sp.spectrumDb,sp.peakAnglesDeg);
                patternLine.XData=sp.anglesDeg; patternLine.YData=sp.patternDb;
                if ~isempty(sp.baselinePatternDb)
                    fixedPatternLine.XData=sp.anglesDeg; fixedPatternLine.YData=sp.baselinePatternDb;
                end
                doaLabel.Text=sprintf('%s DOA peaks %s deg | wanted pilot %.1f deg (model)', ...
                    sp.method,mat2str(sp.peakAnglesDeg,3),sp.wantedAngleDeg);
            end
            angleText='';
            if ~cfg.directOnly, angleText=sprintf(' | wanted DOA %.1f° (model)',result.spatial.wantedAngleDeg); end
            status.Text=sprintf('LIVE seq %s | EVM %.2f dB (%.2f%%) | BER %.4g | RX %.1f dBFS%s', ...
                string(frame.sequence),result.metric.evmDb,result.metric.evmPercent, ...
                result.metric.ber,result.inputRmsDbfs(cfg.activeChannel),angleText);
            if ~isempty(vsa)
                vs=vsa.sendFrame(result.vsaSignal);
                if vs.fresh && isfinite(vs.evmPercent)
                    status.Text=[status.Text,sprintf(' | VSA %.2f dB (%.2f%%)',vs.evmDb,vs.evmPercent)];
                    if isfield(vs,'quality') && isfield(vs.quality,'unclassifiedBits') && vs.quality.unclassifiedBits~=0
                        status.Text=[status.Text,' [vendor trace bit 32 unclassified]'];
                    end
                else
                    status.Text=[status.Text,' | VSA unavailable: ',char(vs.status)];
                end
            end
            drawnow limitrate;
            if strlength(cfg.logPath)>0
                record=rmfield(result,{'constellation','weights','pilotManifold','vsaSignal'});
                if isfield(record.beamformer,'desiredResponse')
                    response=record.beamformer.desiredResponse;
                    record.beamformer.desiredResponse=struct('real',real(response),'imag',imag(response));
                end
                record.sequence=char(string(frame.sequence)); record.hostAgeSeconds=toc(lastFrame);
                record.skippedDisplayFrames=frame.skippedDisplayFrames;
                fid=fopen(cfg.logPath,'a'); assert(fid>=0,'Cannot open metrics log.');
                cleanup=onCleanup(@() fclose(fid)); fprintf(fid,'%s\n',jsonencode(record)); clear cleanup;
            end
        catch exception
            clearCurrent();
            status.FontColor=[1 .55 .35];
            status.Text=['CURRENT EVM UNAVAILABLE: ',exception.message];
            history(end+1,:)=[toc(started),NaN,NaN]; %#ok<AGROW>
            evmLine.XData=history(:,1); evmLine.YData=history(:,2);
            baselineLine.XData=history(:,1); baselineLine.YData=history(:,3);
            evmGlow.XData=history(:,1); evmGlow.YData=history(:,2);
            if history(end,1)>30, xlim(evmAxes,[history(end,1)-30 history(end,1)]); end
            if ~startsWith(exception.identifier,'rfsoc:Lock')
                stopTimer(); % framing and socket errors require explicit reconnection
            end
        end
        if frameCount>=cfg.maxFrames, closeApp(); end
    end
    function value=metricCard(column,caption,color)
        panel=uipanel(grid,'BackgroundColor',[.065 .095 .145],'BorderType','none');
        panel.Layout.Row=2; panel.Layout.Column=column;
        layout=uigridlayout(panel,[2 1]); layout.RowHeight={18,'1x'};
        layout.Padding=[12 4 12 4]; layout.RowSpacing=0; layout.BackgroundColor=panel.BackgroundColor;
        label=uilabel(layout,'Text',caption,'FontSize',10,'FontColor',[.56 .69 .8]); %#ok<NASGU>
        value=uilabel(layout,'Text','—','FontSize',29,'FontWeight','bold','FontName','Consolas','FontColor',color);
        value.Tag=['Metric' num2str(column)];
    end
    function clearCurrent()
        lastResult=[]; iqTrail={};
        iqLine.XData=NaN; iqLine.YData=NaN; trailLine.XData=NaN; trailLine.YData=NaN;
        phaseBars.YData=nan(1,4); clearSpatial();
        for value=[evmDbValue evmPctValue rxValue berValue], value.Text='—'; end
    end
    function clearSpatial()
        for line=[doaLine wantedLine peakLine patternLine fixedPatternLine]
            line.XData=NaN; line.YData=NaN;
        end
        if ~cfg.directOnly, doaLabel.Text='Current DOA and pattern unavailable; waiting for a locked frame.'; end
    end
    function freezeBaseline(~,~)
        if isempty(lastResult), return; end
        a=lastResult.pilotManifold; fixedWeights=a/(a'*a);
        calibrate.Text='Baseline frozen; click to recalibrate';
    end
    function timerError(~,event)
        if isvalid(fig), clearCurrent(); status.Text=['ACQUISITION STOPPED: ',event.Data.Message]; end
        stopTimer();
    end
    function stopTimer()
        if ~isempty(tick) && isvalid(tick), stop(tick); end
    end
    function closeApp(varargin)
        stopTimer();
        if ~isempty(tick) && isvalid(tick), delete(tick); end
        if ~isempty(source), delete(source); source=[]; end
        if ~isempty(vsa), delete(vsa); vsa=[]; end
        if isvalid(fig), delete(fig); end
        % Board owner handles DAC RAM clears/off and its private evidence.
    end
end
