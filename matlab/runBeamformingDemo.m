function app = runBeamformingDemo(cfg)
% Readable MATLAB frontend; original App Designer binaries remain references.
% The board capture owner must already be running. This app never programs RF.
if nargin==0, cfg=rfsoc.defaultConfig(); end
ref=rfsoc.loadReference(cfg.referencePath);
assert(ref.fsHz==cfg.fsHz,'rfsoc:Rate','Reference sample rate mismatch.');
cfg.latestOnly=true; % display skips queued frames; transport validation stays strict
source=[]; vsa=[]; fixedWeights=[]; tick=[]; frameCount=0;
history=zeros(0,3); started=tic; lastFrame=tic; lastResult=[];
visibility='on'; if isfield(cfg,'visible') && ~cfg.visible, visibility='off'; end
fig=uifigure('Visible',visibility,'Name','RFSoC4x2 MATLAB + VSA','Position',[100 100 1150 740]);
grid=uigridlayout(fig,[5 4]); grid.RowHeight={35,35,'1x','1x',45};
status=uilabel(grid,'Text','Connecting; no current EVM'); status.Layout.Column=[1 4];
algorithm=uidropdown(grid,'Items',cellstr(rfsoc.algorithmNames()),'Value',char(cfg.algorithm));
track=uicheckbox(grid,'Text','Track wanted DAC','Value',cfg.tracking);
calibrate=uibutton(grid,'Text','Freeze broadside baseline','ButtonPushedFcn',@freezeBaseline);
uibutton(grid,'Text','Stop acquisition','ButtonPushedFcn',@closeApp);
evmAxes=uiaxes(grid); evmAxes.Layout.Row=[3 4]; evmAxes.Layout.Column=[1 2];
evmLine=plot(evmAxes,NaN,NaN,'DisplayName','Selected'); hold(evmAxes,'on');
baselineLine=plot(evmAxes,NaN,NaN,'DisplayName','Frozen broadside');
ylabel(evmAxes,'History: held-out payload EVM (dB)'); xlabel(evmAxes,'Time (s)'); legend(evmAxes);
iqAxes=uiaxes(grid); iqAxes.Layout.Row=3; iqAxes.Layout.Column=[3 4];
iqLine=scatter(iqAxes,NaN,NaN,7,'.'); xlabel(iqAxes,'I'); ylabel(iqAxes,'Q');
phaseAxes=uiaxes(grid); phaseAxes.Layout.Row=4; phaseAxes.Layout.Column=[3 4];
phaseBars=bar(phaseAxes,zeros(1,4)); ylim(phaseAxes,[-180 180]);
ylabel(phaseAxes,'Pilot phase (degrees)'); xlabel(phaseAxes,'Receive stream');
note=uilabel(grid,'Text','Array results require measured spacing and calibration.');
note.Layout.Row=5; note.Layout.Column=[1 4];
if cfg.directOnly
    algorithm.Enable='off'; track.Enable='off'; calibrate.Enable='off';
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
        % Clear current values before a potentially blocking network operation.
        status.Text=sprintf('Waiting for next frame (%.1f s); current EVM unavailable',toc(lastFrame));
        iqLine.XData=NaN; iqLine.YData=NaN; phaseBars.YData=nan(1,4);
        drawnow limitrate;
        try
            frame=source.next(); lastFrame=tic;
            cfg.algorithm=string(algorithm.Value); cfg.tracking=track.Value;
            result=rfsoc.processFrame(frame.samples,cfg,ref,fixedWeights);
            lastResult=result; frameCount=frameCount+1;
            baseline=NaN;
            if ~isempty(result.baselineMetric), baseline=result.baselineMetric.evmDb; end
            history(end+1,:)=[toc(started),result.metric.evmDb,baseline]; %#ok<AGROW>
            history=history(max(1,end-299):end,:);
            evmLine.XData=history(:,1); evmLine.YData=history(:,2);
            baselineLine.XData=history(:,1); baselineLine.YData=history(:,3);
            iqLine.XData=real(result.constellation(:)); iqLine.YData=imag(result.constellation(:));
            phaseBars.YData=rad2deg(angle(result.pilotManifold./result.pilotManifold(cfg.activeChannel)));
            angleText='';
            if ~cfg.directOnly, angleText=sprintf(' | wanted %.1f°',result.angleDeg); end
            status.Text=sprintf('LIVE seq %s | EVM %.2f dB (%.2f%%) | BER %.4g | RX %.1f dBFS%s', ...
                string(frame.sequence),result.metric.evmDb,result.metric.evmPercent, ...
                result.metric.ber,result.inputRmsDbfs(cfg.activeChannel),angleText);
            if ~isempty(vsa)
                vs=vsa.sendFrame(result.vsaSignal);
                if vs.fresh && isfinite(vs.evmPercent)
                    status.Text=[status.Text,sprintf(' | VSA %.2f dB (%.2f%%)',vs.evmDb,vs.evmPercent)];
                else
                    status.Text=[status.Text,' | VSA unavailable: ',char(vs.status)];
                end
            end
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
            lastResult=[]; iqLine.XData=NaN; iqLine.YData=NaN; phaseBars.YData=nan(1,4);
            status.Text=['CURRENT EVM UNAVAILABLE: ',exception.message];
            history(end+1,:)=[toc(started),NaN,NaN]; %#ok<AGROW>
            evmLine.XData=history(:,1); evmLine.YData=history(:,2);
            baselineLine.XData=history(:,1); baselineLine.YData=history(:,3);
            if ~startsWith(exception.identifier,'rfsoc:Lock')
                stopTimer(); % framing and socket errors require explicit reconnection
            end
        end
        if frameCount>=cfg.maxFrames, closeApp(); end
    end
    function freezeBaseline(~,~)
        if isempty(lastResult), return; end
        a=lastResult.pilotManifold; fixedWeights=a/(a'*a);
        calibrate.Text='Baseline frozen; click to recalibrate';
    end
    function timerError(~,event)
        if isvalid(fig), status.Text=['ACQUISITION STOPPED: ',event.Data.Message]; end
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
