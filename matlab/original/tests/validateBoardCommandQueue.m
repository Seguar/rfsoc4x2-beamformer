function validateBoardCommandQueue()
% Software checks of UI command queue/ACK and setting-revision admission.
cfg=origapp.defaultConfig(); cfg.allowBoardCommands=true; cfg.dataChan=16;
reject=false; seq=0; sent={};
cfg.backend=struct('open',@()[], 'close',@()[], 'send',@send, 'next',@next, ...
    'controlStatus',@()struct('revision',2));
c=origapp.Controller(cfg); g=onCleanup(@()delete(c)); c.open(); %#ok<NASGU>
c.queue('phase 0/0/0/0'); msg=c.flushCommands();
assert(isempty(c.Pending) && numel(c.Sent)==1 && contains(msg,'revision 2'));
reject=true; c.queue('invalid 1'); rejected=false;
try, c.flushCommands();catch e,rejected=string(e.identifier)=="origapp:CommandRejected";end
assert(rejected && isempty(c.Pending),'Rejected commands must not retry every tick.');
assert(numel(sent)==2 && numel(c.Sent)==1);
rejected=false;
try,c.acquire();catch e,rejected=string(e.identifier)=="origapp:NoSignal";end
assert(rejected && c.ControlRevision==2,'First changed-revision frame must reset plot averaging.');
[f,~]=c.acquire(); assert(f.sequence==2 && f.controlRevision==2,'Fresh settings did not recover.');
disp('BOARD_COMMAND_QUEUE_PASS');
    function send(line)
        sent{end+1}=line;
        if reject,error('origapp:CommandRejected','Deliberate negative control.');end
    end
    function f=next(~)
        seq=seq+1;
        f=struct('samples',ones(16,4),'timestamp',origapp.Controller.nowSeconds(), ...
            'sequence',seq,'controlRevision',2);
    end
end
