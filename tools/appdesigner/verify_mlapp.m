function verify_mlapp(root,referenceExport)
%VERIFY_MLAPP Fresh-process readback of the private VSA_rfsoc_refactor.mlapp.
%   Checks: metadata, full component model vs the original copy, code data vs
%   document code, an independent MathWorks parser (PlainTextCodeParser) on the
%   same code, the export vs MLAPPExporter, class metadata of .mlapp vs export,
%   checkcode. Writes evidence/verify/verify.json; prints VERIFY_MLAPP_COMPLETE.
out = fullfile(root, 'evidence', 'verify'); if ~isfolder(out), mkdir(out); end
diary(fullfile(out, 'verify.log')); cleanD = onCleanup(@() diary('off'));
try
    newF = fullfile(root, 'app', 'VSA_rfsoc_refactor.mlapp');
    origF = fullfile(root, 'work', 'VSA_rfsoc_orig_copy.mlapp');
    expF = fullfile(root, 'app', 'VSA_rfsoc_refactor_exported.m');
    R = struct();

    %% Metadata + model readback
    dn = appdesigner.internal.serialization.SerializationFactory.createDeserializer(newF);
    mdN = dn.getAppMetadata(); aN = dn.getAppData();
    do = appdesigner.internal.serialization.SerializationFactory.createDeserializer(origF);
    aO = do.getAppData();
    R.metadata = struct('Name', mdN.Name, 'AppType', mdN.AppType, 'MATLABRelease', mdN.MATLABRelease, ...
        'MinimumSupportedMATLABRelease', mdN.MinimumSupportedMATLABRelease, 'Uuid', mdN.Uuid, ...
        'warnings', numel(dn.Warnings));

    [cN, fN] = componentTable(aN.components.UIFigure);
    [cO, fO] = componentTable(aO.components.UIFigure);
    R.components = struct('countNew', numel(cN), 'countOrig', numel(cO), ...
        'codeNamesEqual', isequal(cN, cO), 'fingerprintsEqual', isequaln(fN, fO), ...
        'groupsEqual', isequaln(fieldOr(aN.components, 'Groups'), fieldOr(aO.components, 'Groups')));
    if ~R.components.fingerprintsEqual
        d = {}; for k = 1:min(numel(fN), numel(fO)), if ~isequaln(fN{k}, fO{k}), d{end+1} = cN{k}; end, end %#ok<AGROW>
        R.components.differing = d;
    end

    %% Raw appModel.mat code fields: new vs original (no ComponentData in v2 files)
    R.raw = struct('new', rawCode(newF, fullfile(out, 'rawN')), 'orig', rawCode(origF, fullfile(out, 'rawO')));
    R.raw.callbackFieldsEqual = isequal(R.raw.new.callbackFields, R.raw.orig.callbackFields);
    R.raw.startupFieldsEqual = isequal(R.raw.new.startupFields, R.raw.orig.startupFields);

    %% Code data vs document code (stored in the same file)
    fr = appdesigner.internal.serialization.FileReader(newF);
    T = normLF(fr.readMATLABCodeText());
    built = normLF(fileread(fullfile(root, 'evidence', 'build', 'document_code.m.txt')));
    R.code.documentEqualsBuild = strcmp(T, strip(built, 'right', newline)) || strcmp(T, built);
    L = splitlines(T); s = adSections(L);
    c = aN.code; tn = {s.callbacks.Name};
    R.code.className = c.ClassName;
    R.code.classdefLine = L{1};
    R.code.inputParameters = fieldOr(c, 'InputParameters');
    R.code.singletonMode = fieldOr(c, 'SingletonMode');
    R.code.editableEqual = isequal(s.editable, c.EditableSectionCode(:));
    R.code.startupEqual = isequal(s.callbacks(strcmp(tn, 'startupFcn')).Code, c.StartupCallback.Code(:));
    R.code.startupArgs = s.callbacks(strcmp(tn, 'startupFcn')).Args;
    mism = {};
    for k = 1:numel(c.Callbacks)
        j = find(strcmp(tn, c.Callbacks(k).Name));
        if strcmp(c.Callbacks(k).Name, 'updateAppLayout')
            ok = numel(j) == 1 && isempty(c.Callbacks(k).Code);
        else
            ok = numel(j) == 1 && isequal(s.callbacks(j).Code, c.Callbacks(k).Code(:));
        end
        if ~ok, mism{end+1} = c.Callbacks(k).Name; end %#ok<AGROW>
    end
    R.code.callbackCount = numel(c.Callbacks);
    R.code.callbackMismatches = mism;
    R.code.textOnlyMethods = setdiff(setdiff(tn, {'startupFcn'}), {c.Callbacks.Name});
    % bindings: every createCallbackFcn in createComponents names a stored callback with that component
    b = regexp(T, 'app\.(\w+)\.(\w+Fcn) = createCallbackFcn\(app, @(\w+), true\);', 'tokens');
    bm = {};
    for k = 1:numel(b)
        j = find(strcmp({c.Callbacks.Name}, b{k}{3}));
        ok = numel(j) == 1 && any(strcmp({c.Callbacks(j).ComponentData.CodeName}, b{k}{1}) & ...
            strcmp({c.Callbacks(j).ComponentData.CallbackPropertyName}, b{k}{2}));
        if ~ok, bm{end+1} = strjoin(b{k}, ':'); end %#ok<AGROW>
    end
    R.code.bindings = numel(b); R.code.bindingMismatches = bm;
    % ComponentData unchanged vs original for every kept callback
    cdm = {};
    for k = 1:numel(c.Callbacks)
        j = find(strcmp({aO.code.Callbacks.Name}, c.Callbacks(k).Name));
        if numel(j) ~= 1 || ~isequal(cdKey(c.Callbacks(k).ComponentData), cdKey(aO.code.Callbacks(j).ComponentData)), cdm{end+1} = c.Callbacks(k).Name; end %#ok<AGROW>
        if k == 1, R.code.componentDataFieldsNew = fieldnames(c.Callbacks(k).ComponentData); R.code.componentDataFieldsOrig = fieldnames(aO.code.Callbacks(j).ComponentData); end
    end
    R.code.componentDataChanged = cdm;

    %% Independent parser: MathWorks PlainTextCodeParser on the same code text
    try
        kids = struct('AssignedCallbacks', {}, 'Children', {});
        for k = 1:numel(c.Callbacks)
            if ~isempty(c.Callbacks(k).ComponentData)
                kids(end+1) = struct('AssignedCallbacks', struct('Name', c.Callbacks(k).Name), 'Children', []); %#ok<AGROW>
            end
        end
        tree = struct('AssignedCallbacks', [], 'Children', kids);
        p = appdesigner.internal.serialization.PlainTextCodeParser(string(T));
        pc = p.parseCodeData(tree, "startupFcn", false, "Responsive");
        pe = normWs(pc.EditableSectionCode); me = normWs(c.EditableSectionCode);
        pcb = pc.Callbacks; pnames = {pcb.Name};
        cbBody = {};
        for k = 1:numel(c.Callbacks)
            if strcmp(c.Callbacks(k).Name, 'updateAppLayout'), continue, end
            j = find(strcmp(pnames, c.Callbacks(k).Name));
            if numel(j) ~= 1 || ~strcmp(normWs(pcb(j).Code), normWs(c.Callbacks(k).Code)), cbBody{end+1} = c.Callbacks(k).Name; end %#ok<AGROW>
        end
        R.parser = struct('ok', true, 'className', char(pc.ClassName), 'inputParams', char(string(pc.InputParameters)), ...
            'editableEqualWs', strcmp(pe, me), 'startupEqualWs', strcmp(normWs(pc.StartupFcn.Code), normWs(c.StartupCallback.Code)), ...
            'callbackNamesEqual', isequal(sort(pnames), sort({c.Callbacks.Name})), 'callbackBodyMismatches', {cbBody});
    catch perr
        R.parser = struct('ok', false, 'error', perr.message);
    end

    %% Export
    ex = appdesigner.internal.serialization.converter.MLAPPExporter(expF, struct('originalName', 'VSA_rfsoc_refactor'));
    want = ex.getGeneratedCodeForExport(T);
    got = fileread(expF);
    R.export.equalsExporter = strcmp(normLF(got), normLF(want));
    R.export.classdef = regexp(got, '^classdef \w+', 'match', 'once');
    lintE = checkcode(expF, '-id'); R.export.checkcode = arrayfun(@(x) sprintf('%d %s', x.line, x.id), lintE, 'UniformOutput', false);
    if nargin<2, referenceExport=expF; end
    pub=referenceExport;
    lintP = checkcode(pub, '-id'); R.export.checkcodePublic = arrayfun(@(x) sprintf('%d %s', x.line, x.id), lintP, 'UniformOutput', false);

    %% Class metadata: .mlapp class vs exported class (no construction)
    addpath(fullfile(root, 'app')); cp = onCleanup(@() rmpath(fullfile(root, 'app')));
    mA = meta.class.fromName('VSA_rfsoc_refactor');
    mE = meta.class.fromName('VSA_rfsoc_refactor_exported');
    R.classmeta.mlappResolved = ~isempty(mA);
    R.classmeta.mlappSource = which('VSA_rfsoc_refactor');
    if ~isempty(mA) && ~isempty(mE)
        [ma, mae] = methodTable(mA, 'VSA_rfsoc_refactor'); [me2, mee] = methodTable(mE, 'VSA_rfsoc_refactor_exported');
        R.classmeta.methodsEqual = isequal(ma, me2); R.classmeta.methodAccessEqual = isequal(mae, mee);
        R.classmeta.methodCount = numel(ma);
        pa = ownProps(mA, 'VSA_rfsoc_refactor'); pe2 = ownProps(mE, 'VSA_rfsoc_refactor_exported');
        R.classmeta.propertiesEqual = isequal(pa, pe2); R.classmeta.propertyCount = numel(pa);
        R.classmeta.superclass = mA.SuperclassList(1).Name;
    end
    delete(aN.components.UIFigure); delete(aO.components.UIFigure);

    writelines(jsonencode(R, PrettyPrint=true), fullfile(out, 'verify.json'));
    assert(R.metadata.warnings==0 && R.components.countNew==119 && ...
        R.components.codeNamesEqual && R.components.fingerprintsEqual && R.components.groupsEqual && ...
        R.code.documentEqualsBuild && R.code.editableEqual && R.code.startupEqual && ...
        isempty(R.code.callbackMismatches) && isempty(R.code.bindingMismatches) && ...
        R.parser.ok && R.parser.editableEqualWs && R.parser.startupEqualWs && ...
        R.parser.callbackNamesEqual && isempty(R.parser.callbackBodyMismatches) && ...
        R.export.equalsExporter && R.classmeta.mlappResolved && R.classmeta.methodsEqual && ...
        R.classmeta.methodAccessEqual && R.classmeta.propertiesEqual, ...
        'verify:Mismatch','App Designer artifact consistency check failed.');
    disp(jsonencode(R, PrettyPrint=true));
    fprintf('VERIFY_MLAPP_COMPLETE %s\n', out);
catch err
    disp(getReport(err, 'extended')); rethrow(err);
end
end

function [names, fp] = componentTable(fig)
h = findall(fig);
h = h(arrayfun(@(x) isprop(x, 'DesignTimeProperties'), h));
names = arrayfun(@(x) char(x.DesignTimeProperties.CodeName), h, 'UniformOutput', false);
[names, ix] = sort(names); h = h(ix);
fp = cell(size(h));
for k = 1:numel(h)
    x = h(k); p = properties(x); s = struct('class', class(x));
    if ~isempty(x.Parent) && isprop(x.Parent, 'DesignTimeProperties'), s.parent = char(x.Parent.DesignTimeProperties.CodeName); end
    for j = 1:numel(p)
        if any(strcmp(p{j}, {'Children', 'Parent', 'DesignTimeProperties', 'CurrentPoint', 'BeingDeleted'})), continue, end
        try, v = x.(p{j}); catch, continue, end
        if (isnumeric(v) || islogical(v) || ischar(v) || isstring(v) || iscellstr(v)) && numel(v) < 5000
            s.(p{j}) = v;
        elseif isstruct(v) || isa(v, 'matlab.ui.layout.GridLayoutOptions')
            try, s.(p{j}) = jsonencode(v); catch, end
        elseif isa(v, 'function_handle')
            s.(p{j}) = func2str(v);
        end
    end
    fp{k} = s;
end
end

function [m, acc] = methodTable(mc, cls)
L = mc.MethodList(strcmp(arrayfun(@(x) x.DefiningClass.Name, mc.MethodList, 'UniformOutput', false), cls));
m = {L.Name}; m(strcmp(m, cls)) = {'<ctor>'};
acc = cellfun(@(a) char(string(a)), {L.Access}, 'UniformOutput', false);
[m, ix] = sort(m); acc = acc(ix);
end

function p = ownProps(mc, cls)
L = mc.PropertyList(strcmp(arrayfun(@(x) x.DefiningClass.Name, mc.PropertyList, 'UniformOutput', false), cls));
p = sort({L.Name});
end

function r = rawCode(f, tmp)
unzip(f, tmp); S = load(fullfile(tmp, 'appdesigner', 'appModel.mat'));
r.topFields = fieldnames(S);
c = S.code;
r.codeFields = fieldnames(c);
r.callbackFields = fieldnames(c.Callbacks);
r.startupFields = fieldnames(c.StartupCallback);
r.callbackCount = numel(c.Callbacks);
if isfield(S, 'components') && isfield(S.components, 'UIFigure'), delete(S.components.UIFigure); end
rmdir(tmp, 's');
end

function k = cdKey(cd)
k = arrayfun(@(x) sprintf('%s|%s|%s', x.CodeName, x.CallbackPropertyName, x.ComponentType), cd, 'UniformOutput', false);
end

function v = fieldOr(s, f)
if isfield(s, f), v = s.(f); else, v = '<absent>'; end
end
function t = normLF(t)
t = char(t); t = strrep(t, sprintf('\r\n'), newline);
end
function t = normWs(c)
if iscell(c), c = strjoin(cellfun(@char, c(:)', 'UniformOutput', false), newline); end
t = regexprep(char(c), '\s+', ' '); t = strtrim(t);
end
