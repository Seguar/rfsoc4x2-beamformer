function report=runBoardControlLive(settingsFile)
% Explicit bounded LIVE test. Caller must own the already-staged board helper.
% Never run as part of the host-only regression suites.
s=jsondecode(fileread(settingsFile));
assert(isfield(s,'enableLive') && s.enableLive,'origapp:Live','Explicit live authorization required.');
b=origapp.LegacyVsaBackend(s.backend); guard=onCleanup(@()delete(b)); %#ok<NASGU>
c=origapp.defaultConfig(); c.backend=b; c.dataChan=32768; c.directOnly=false;
c.allowBoardCommands=true; c.frameTimeoutSeconds=.25;
controller=origapp.Controller(c); controller.open();
report=struct('commands',{{}},'frames',{{}},'obsoleteRejected',0);
r=command('status'); assert(r.result.revision==0 && r.result.streaming);
f=rawFrame(); assert(any(f.signalChannels));
% The first frame prefetch can overlap this change. Its old revision may never
% be delivered after the acknowledged new setting.
r=command('dphase 45/0/0/0'); assert(abs(r.result.dac_mixers(1).PhaseOffset-45)<.01);
f=rawFrame(); assert(f.controlRevision>=r.result.revision);
r=command('dphase 0/0/0/0'); assert(abs(r.result.dac_mixers(1).PhaseOffset)<.01);
command('phase -90/-90/90/90');
r=command('fc 3000/2/3000/1/3000/1');
assert(all(abs([r.result.adc_mixers.Freq]-3000)<.01) && ...
    all(abs([r.result.dac_mixers.Freq]-3000)<.01));
command('dataChan 262144');
for bad=["dataChan 131072","dacPow 0/0/1/0","cal 8","stream 1"]
    rejected=false;
    try, command(bad); catch err, rejected=string(err.identifier)=="origapp:CommandRejected";end
    assert(rejected,'origapp:Live','Unsupported command was not explicitly rejected.');
end
% Pause control must remain responsive while the consumer does not read IQ.
command('dataStream 0'); t=tic; assert(isempty(b.next(.25)) && toc(t)<.2);
r=command('status'); assert(~r.result.streaming);
command('dataStream 1'); f=rawFrame(); assert(f.controlRevision>=b.Control.Revision);
% The trigger also enables DAC players in this bitstream. The adapter must
% zero selected RAM on OFF, not merely lower a software enable.
command('dacPow 0/0/0/0'); f=rawFrame(); assert(~any(f.signalChannels));
command('dacPow 1/0/0/0');
ok=false;
for k=1:5, f=rawFrame();if all(f.signalChannels),ok=true;break,end,end
assert(ok,'origapp:Live','Signal did not recover after DAC RAM restore.');
% Exercise the same queue/ACK path used by original-app callbacks.
controller.queue('da 1#dataStream 1'); controller.flushCommands();
assert(isempty(controller.Pending) && numel(controller.Sent)==1);
ok=false;t=tic;
while toc(t)<20
    try
        [f,~]=controller.acquire();
        if ~isempty(f), controller.recordSuccess(); ok=true; break,end
    catch err
        assert(any(string(err.identifier)==["origapp:NoSignal","origapp:Stale","origapp:Boundary"]), ...
            'origapp:Live','Unexpected Controller error: %s',err.message);
        controller.recordFailure(err);
    end
end
assert(ok && controller.FramesAccepted==1,'origapp:Live','Controller did not recover on new settings.');
report.lastSequence=f.sequence; report.revision=b.Control.Revision;
controller.close();
fid=fopen(s.reportFile,'w'); assert(fid>=0); clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report));
disp('BOARD_CONTROL_LIVE_COMPLETE');
    function r=command(line)
        t=tic; r=b.send(char(line));
        report.commands{end+1}=struct('command',string(line),'seconds',toc(t),'reply',r);
    end
    function f=rawFrame()
        t=tic; f=[];
        while isempty(f) && toc(t)<20
            try
                f=b.next(.25);
            catch err
                assert(any(string(err.identifier)==["origapp:SettingsChanged","a2live:Timestamp"]), ...
                    'origapp:Live','Unexpected stream error: %s',err.message);
                report.obsoleteRejected=report.obsoleteRejected+1;
            end
        end
        assert(~isempty(f),'origapp:Live','Timed out waiting for fresh IQ.');
        assert(f.controlRevision>=b.Control.Revision,'origapp:Live','Old settings admitted after ACK.');
        report.frames{end+1}=rmfield(f,'samples');
    end
end
