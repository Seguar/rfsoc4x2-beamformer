function out=buildStandalone(referenceRepo,referenceMat,outDir)
%BUILDSTANDALONE Compile RFSoCBeamformer into a Windows application.
%   referenceRepo  vsa_rfsoc checkout (Functions/ and Settings/ are packaged)
%   referenceMat   legacy_ref125.mat written by tools/legacy_reference.py
%   outDir         build folder (keep it outside the repository)
% Needs MATLAB Compiler. The result runs with the matching MATLAB Runtime.
root=fileparts(fileparts(mfilename('fullpath')));
here=fullfile(root,'standalone');
setx=fullfile(referenceRepo,'Settings','ofdm_iq_100_16_4x2.setx');
assert(isfolder(fullfile(referenceRepo,'Functions')) && isfile(setx) && isfile(referenceMat), ...
    'origapp:Build','Reference repository or reference loop not found.');
stage=fullfile(outDir,'resources');if ~isfolder(stage),mkdir(stage);end
copyfile(setx,fullfile(stage,'ofdm_iq_100_16_4x2.setx'));
copyfile(referenceMat,fullfile(stage,'legacy_ref125.mat'));
addpath(here,fullfile(root,'original'),fullfile(root,'original','app'),root,fullfile(referenceRepo,'Functions'));
mcc('-m',fullfile(here,'RFSoCBeamformer.m'),'-e','-o','RFSoCBeamformer','-d',outDir, ...
    '-a',fullfile(stage,'ofdm_iq_100_16_4x2.setx'),'-a',fullfile(stage,'legacy_ref125.mat'), ...
    '-a',fullfile(referenceRepo,'Functions'));
out=fullfile(outDir,'RFSoCBeamformer.exe');
assert(isfile(out),'origapp:Build','Compiler produced no executable.');
fprintf('BUILT %s (MATLAB %s)\n',out,version('-release'));
end
