# Code-only App Designer rebuild (MATLAB R2026a)

These utilities save model and code together; they never edit the user's original
app. They use undocumented R2026a APIs. Work in a new disposable directory, and
validate the saved artifact before replacing the shipped pair.

```matlab
workspace = '<new empty private working directory>';
mkdir(fullfile(workspace,'work'));
copyfile('<demo>/matlab/original/app/VSA_rfsoc_refactor.mlapp', ...
    fullfile(workspace,'work','VSA_rfsoc_orig_copy.mlapp'));
addpath('<demo>/tools/appdesigner');
source = '<demo>/matlab/original/app/VSA_rfsoc_refactor_exported.m';
build_mlapp(workspace, source);
% Run in a fresh MATLAB process:
verify_mlapp(workspace, source);
```

Output: `workspace/app/VSA_rfsoc_refactor.mlapp` and its matching export. Existing
output is refused. Build/verify JSON and logs are kept under `workspace/evidence`.
The verification fails on component/code/callback/export mismatches. Export
comparison normalizes LF/CRLF only. Keep both resulting files together.

This supports code-body/property changes with the existing119-component model and
65 callback bindings. Changes to component layout or callback signatures require
App Designer authoring and renewed validation. An editor open/save/export round trip
has not been performed. The thumbnail comes from the original component model and
is not live measurement evidence.
