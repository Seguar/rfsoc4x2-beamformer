function validateMetadata()
% Synthetic transport-contract controls; no sockets or hardware.
cfg=origapp.defaultConfig(); cfg.dataChan=16;
good=struct('samples',zeros(16,4),'sequence',1,'timestamp',origapp.Controller.nowSeconds());
for k=1:5
    raw=good;
    switch k
        case 1, raw=rmfield(raw,'sequence');
        case 2, raw=rmfield(raw,'timestamp');
        case 3, raw.timestamp=NaN;
        case 4, raw.timestamp=origapp.Controller.nowSeconds()+3600;
        case 5, raw.sequence=[1 2];
    end
    cfg.backend=struct('next',@(~)raw,'close',@()[]);
    controller=origapp.Controller(cfg); guard=onCleanup(@()delete(controller));
    controller.open(); rejected=false;
    try, controller.acquire(); catch e, rejected=startsWith(e.identifier,'origapp:'); end
    assert(rejected,'Invalid frame metadata accepted.');
    clear guard;
end
cfg.backend=struct('next',@(~)good,'close',@()[]);
controller=origapp.Controller(cfg); guard=onCleanup(@()delete(controller));
controller.open(); frame=controller.acquire(); assert(frame.sequence==1);
rejected=false; try, controller.acquire(); catch e, rejected=strcmp(e.identifier,'origapp:Sequence'); end
assert(rejected,'Repeated frame accepted.');
disp('ORIGINAL_METADATA_PASS');
end
