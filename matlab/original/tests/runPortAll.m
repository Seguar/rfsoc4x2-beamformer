function runPortAll(originalRepoPath, reviewedPath, outDir)
%RUNPORTALL Lint gate + the existing hidden-UI fixture + the VSA_rfsoc_new
% port fixture, on one hidden test copy of the app. SIMULATION only.
% Prints ORIGINAL_APP_REFACTOR_COMPLETE (runAll) and NEW_PORT_ALL_COMPLETE.
runAll(originalRepoPath, reviewedPath, outDir);
root = fileparts(fileparts(mfilename('fullpath')));
diary(fullfile(outDir, 'run_port.log')); cleaner = onCleanup(@() diary('off'));
[appPath, shadowGuard] = hiddenAppCopy(fullfile(root, 'app')); %#ok<ASGLU>
results = runNewPortFixture(originalRepoPath, reviewedPath, fullfile(outDir, 'new_port'), appPath);
disp(jsonencode(rmfield(results, 'units')));
fprintf('NEW_PORT_ALL_COMPLETE %s\n', outDir);
end
