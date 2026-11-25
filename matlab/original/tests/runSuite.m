function ok=runSuite(referenceMat,referenceRepo,outDir,opt)
%RUNSUITE All MATLAB checks of the app, no hardware. Prints one PASS/FAIL line
% per check and SUITE_COMPLETE. Arguments:
%   referenceMat   legacy_ref125.mat (tools/legacy_reference.py)
%   referenceRepo  vsa_rfsoc checkout (Functions/, Settings/)
%   outDir         scratch folder for reports and snapshots
%   opt.window4Port   port of tests/fake_window4_server.py with the scenario in
%                     runWindow4Fixture (0 = skip)
%   opt.serviceAddress address of tests/fake_session_service.py ("" = skip)
%   opt.wireFixtures  folder written by tests/make_wire_fixtures.py ("" = skip)
%   opt.view          true: also the GUI fixture (needs an interactive desktop)
if nargin<4,opt=struct();end
d=struct('window4Port',0,'serviceAddress',"",'wireFixtures',"",'view',false);
for f=string(fieldnames(d)).',if ~isfield(opt,f),opt.(f)=d.(f);end,end
here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(here));
addpath(here,fullfile(root,'original'),fullfile(root,'original','app'),root,fullfile(root,'standalone'), ...
    fullfile(char(referenceRepo),'Functions'));
setenv('RFSOC_DEMO_SETX',fullfile(char(referenceRepo),'Settings','ofdm_iq_100_16_4x2.setx'));
setenv('RFSOC_DEMO_REFERENCE',char(referenceMat));
if ~isfolder(outDir),mkdir(outDir);end
checks={ ...
    'lint',@()lint(fullfile(root,'original','app','+origapp'),fullfile(root,'standalone'),fullfile(root,'original'),here); ...
    'metadata',@()validateMetadata(); ...
    'streamGate',@()validateStreamGate(); ...
    'windowAdmission',@()validateWindowAdmission(); ...
    'commandQueue',@()validateBoardCommandQueue(); ...
    'pilotFallback',@()validatePilotFallback(referenceMat,referenceRepo); ...
    'demoSession',@()validateDemoSession(referenceMat,referenceRepo,fullfile(outDir,'session')); ...
    'zeroCal',@()validateZeroCal(referenceMat,referenceRepo,fullfile(outDir,'zero')); ...
    'standaloneDemo',@()validateStandaloneDemo(fullfile(outDir,'demo'))};
if strlength(string(opt.wireFixtures))>0,checks(end+1,:)={'legacyWire',@()validateLegacyWire(opt.wireFixtures)};end
if opt.window4Port>0
    checks(end+1,:)={'window4',@()runWindow4Fixture(opt.window4Port,referenceMat,referenceRepo,fullfile(outDir,'window4'))};
end
if strlength(string(opt.serviceAddress))>0,checks(end+1,:)={'boardLink',@()validateBoardLink(opt.serviceAddress)};end
if opt.view,checks(end+1,:)={'view',@()validateBeamformerView(fullfile(outDir,'view'))};end
ok=true;
for k=1:size(checks,1)
    t=tic;
    try
        checks{k,2}();
        fprintf('SUITE PASS %s (%.0f s)\n',checks{k,1},toc(t));
    catch e
        ok=false;
        fprintf('SUITE FAIL %s: %s\n',checks{k,1},getReport(e,'extended','hyperlinks','off'));
    end
    close all force
end
fprintf('SUITE_COMPLETE ok=%d\n',ok);
end

function lint(varargin)
% Parse errors only (style messages are not failures).
bad={};
for k=1:numel(varargin)
    files=dir(fullfile(varargin{k},'*.m'));
    for j=1:numel(files)
        f=fullfile(files(j).folder,files(j).name);
        r=checkcode(f,'-id');
        for q=1:numel(r)
            if any(strcmp(r(q).id,{'NOPAR','PARSE','EOFER','ENDCT','NOPRV','MCNPR'}))
                bad{end+1}=sprintf('%s:%d %s',files(j).name,r(q).line,r(q).message); %#ok<AGROW>
            end
        end
    end
end
assert(isempty(bad),'suite:Lint','%s',strjoin(bad,newline));
end
