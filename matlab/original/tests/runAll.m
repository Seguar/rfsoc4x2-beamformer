function runAll(originalRepoPath, reviewedPath, outDir)
%RUNALL Lint gate + hidden UI fixture. Prints ORIGINAL_APP_REFACTOR_COMPLETE.
root = fileparts(fileparts(mfilename('fullpath')));
if ~isfolder(outDir), mkdir(outDir); end
diary(fullfile(outDir, 'run.log'));
cleaner = onCleanup(@() diary('off'));
try
    files = [dir(fullfile(root, 'app', '*.m')); dir(fullfile(root, 'app', '+origapp', '*.m')); ...
        dir(fullfile(root, 'tests', '*.m'))];
    lint = struct('file', {}, 'line', {}, 'id', {}, 'message', {});
    for k = 1:numel(files)
        f = fullfile(files(k).folder, files(k).name);
        info = checkcode(f, '-id');
        for j = 1:numel(info)
            lint(end+1) = struct('file', files(k).name, 'line', info(j).line, ... %#ok<AGROW>
                'id', info(j).id, 'message', info(j).message);
        end
    end
    fprintf('LINT %d messages\n', numel(lint));
    for j = 1:numel(lint)
        fprintf('LINT %s:%d %s %s\n', lint(j).file, lint(j).line, lint(j).id, lint(j).message);
    end
    fid = fopen(fullfile(outDir, 'checkcode.json'), 'w');
    fwrite(fid, jsonencode(lint, 'PrettyPrint', true)); fclose(fid);
    addpath(fullfile(root,'app'),char(reviewedPath));
    validateMetadata();
    [appPath,shadowGuard]=hiddenAppCopy(fullfile(root,'app')); %#ok<NASGU>
    results = runOriginalUiFixture(originalRepoPath, reviewedPath, outDir,appPath);
    disp(jsonencode(results));
    fprintf('ORIGINAL_APP_REFACTOR_COMPLETE %s\n', outDir);
catch err
    disp(getReport(err, 'extended'));
    rethrow(err);
end
end
