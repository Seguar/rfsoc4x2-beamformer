function [setx,ref]=demoResources()
%DEMORESOURCES Locate the OFDM setup and reference loop used by the simulation.
% Deployed: the files are packaged into the application archive by
% buildStandalone. From source: set RFSOC_DEMO_SETX and RFSOC_DEMO_REFERENCE.
names={'ofdm_iq_100_16_4x2.setx','legacy_ref125.mat'};found=cell(1,2);
keys={'RFSOC_DEMO_SETX','RFSOC_DEMO_REFERENCE'};
for k=1:2
    p=getenv(keys{k});
    if isempty(p) || ~isfile(p)
        p=which(names{k});
        if isempty(p) && isdeployed
            hit=dir(fullfile(ctfroot,'**',names{k}));
            if ~isempty(hit),p=fullfile(hit(1).folder,hit(1).name);end
        end
    end
    assert(~isempty(p) && isfile(p),'origapp:Standalone','Demo resource %s not found (set %s).',names{k},keys{k});
    found{k}=p;
end
setx=found{1};ref=found{2};
end
