function report=validateBoardLink(address)
% Board search and session ownership against board/session_service.py running
% with the fake helper (no hardware). Start it first, then pass its address:
%   python -m tests.fake_session_service --port <port> [--bind <address>]
here=fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(here),'app'),fullfile(fileparts(fileparts(here)),'standalone'));
address=string(address);dead="127.0.0.1:1";serviceHost=extractBefore(address,":");
% addresses
[h,p]=origapp.BoardLink.parseAddress(" 192.168.2.99 ");assert(h=="192.168.2.99" && p==4013);
[h,p]=origapp.BoardLink.parseAddress("board-1.local:5000");assert(h=="board-1.local" && p==5000);
for bad=["","a b","1.2.3.4:0","1.2.3.4:x","a:1:2","-x","x;rm"]
    refused=false;try,origapp.BoardLink.parseAddress(bad);catch,refused=true;end
    assert(refused,'Address "%s" was accepted.',bad);
end
% probe and search order
info=origapp.BoardLink.probe(address);
assert(~isempty(info) && string(info.board)=="RFSoC4x2" && ~info.busy,'Service did not identify itself.');
assert(isempty(origapp.BoardLink.probe(dead)),'A closed port identified as a board.');
found=origapp.BoardLink.find({'first',dead;'second',address});
assert(found.host==address && found.via=="second" && numel(found.tried)==2);
none=origapp.BoardLink.find({'only',dead});assert(strlength(none.host)==0);
% last address
file=[tempname '.txt'];setenv('RFSOC_BEAMFORMER_SETTINGS',file);restore=onCleanup(@()setenv('RFSOC_BEAMFORMER_SETTINGS',''));
assert(strlength(origapp.BoardLink.lastAddress())==0);
origapp.BoardLink.lastAddress("10.1.2.3");assert(origapp.BoardLink.lastAddress()=="10.1.2.3");
fid=fopen(file,'w');fprintf(fid,'not an address!');fclose(fid);assert(strlength(origapp.BoardLink.lastAddress())==0);
delete(file);
% session: ready, second owner refused, orderly stop with DAC report
steps=0;
link=origapp.BoardLink(address);
ready=link.start(60,@count);
assert(link.State=="ready" && ready.stream_port==4011 && ready.control_port==4012 && string(ready.host)==serviceHost);
other=origapp.BoardLink(address);message="";
try,other.start(60);catch err,message=string(err.message);assert(strcmp(err.identifier,'origapp:BoardConnect'));end
assert(contains(message,"already in use"),'Second owner was not refused: %s',message);
busy=origapp.BoardLink.probe(address);assert(busy.busy);
result=link.finish(30);
assert(string(result.state)=="ended" && string(result.reason)=="client_stop" && result.dac_off_commanded && isempty(result.shutdown_errors));
% owner loss: deleting the link ends the board session
link=origapp.BoardLink(address);link.start(60);delete(link);
freed=false;started=tic;
while toc(started)<15 && ~freed
    pause(.3);state=origapp.BoardLink.probe(address);freed=~isempty(state) && ~state.busy;
end
assert(freed,'The board session survived its owner.');
% cancel during start
link=origapp.BoardLink(address);cancelled=false;
try,link.start(60,@(~)false);catch err,cancelled=strcmp(err.identifier,'origapp:BoardCancelled');end
assert(cancelled,'Cancel was ignored.');
% entry point: unreachable board without the dialog is an error, no window left
figures0=numel(findall(groot,'Type','figure'));id="";
try,RFSoCBeamformer('board',dead,'dialog','off');catch err,id=string(err.identifier);end
assert(id=="origapp:BoardConnect",'Unreachable board gave "%s".',id);
drawnow;assert(numel(findall(groot,'Type','figure'))==figures0,'Connection window leaked.');
% address window: typed address, a bad address keeps the window open, simulation, close
shot=[tempname '.png'];
c=withPress(@()origapp.boardDialog("No board answered (test).",""),{'Connect','10.9.8.7'},shot);
assert(c.action=="connect" && c.host=="10.9.8.7",'Address window did not return the typed address.');
c=withPress(@()origapp.boardDialog("note","192.168.2.99"),{'Connect','bad address','Run simulation',''},'');
assert(c.action=="demo",'A bad address closed the window or the simulation button failed.');
c=withPress(@()origapp.boardDialog("note",""),{'Close',''},'');assert(c.action=="cancel");
assert(numel(findall(groot,'Type','figure'))==figures0,'Address window leaked.');
report=struct('progressMessages',steps,'dialogScreenshot',shot,'label','session service with fake helper, no hardware');
disp('BOARD_LINK_COMPLETE');
    function ok=count(~)
        steps=steps+1;ok=true;
    end
end

function out=withPress(fcn,steps,shot)
% Run a modal window and press its buttons from a timer: steps = {button,fieldValue,...}.
t=timer('StartDelay',2.5,'TimerFcn',@(~,~)press(steps,shot));start(t);guard=onCleanup(@()delete(t));
out=fcn();
end

function press(steps,shot)
fig=findall(groot,'Type','figure','Name','RFSoC Beamformer');
try
    if ~isempty(shot),exportapp(fig,shot);end
    for k=1:2:numel(steps)
        field=findall(fig,'Type','uieditfield');
        if ~isempty(steps{k+1}),field.Value=steps{k+1};end
        button=findall(fig,'Type','uibutton','Text',steps{k});
        feval(button.ButtonPushedFcn,button,[]);drawnow;
    end
catch err
    disp(getReport(err));delete(fig);
end
end
