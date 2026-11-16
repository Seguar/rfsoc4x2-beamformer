function build_mlapp_ext(root, sourceExport, baseExport)
%BUILD_MLAPP_EXT Build VSA_rfsoc_refactor.mlapp + export with an explicitly
% extended component model (uiExtensionSpec) on top of the 119-component
% VSA_rfsoc_refactor model. Companion of build_mlapp (code-only rebuilds).
%
%   root         new private workspace; root/work/VSA_rfsoc_orig_copy.mlapp must
%                be a COPY of the shipped 119-component VSA_rfsoc_refactor.mlapp
%   sourceExport edited VSA_rfsoc_refactor_exported.m (code + new callbacks);
%                its component-declaration and createComponents blocks are
%                REGENERATED from the extended model, never hand-written
%   baseExport   shipped export matching the .mlapp copy (calibration input)
%
% Steps: (1) calibrate adComponentCode byte-exactly on the shipped pair;
% (2) create spec components as design-time components, code from App
% Designer's ComponentCodeGenerator and the production adapter map, callbacks
% bound by name; (3) splice the regenerated blocks into the source; (4) code
% data from the same text; (5) MLAPPSerializer; (6) MLAPPExporter.
% R2026a internal APIs; never touches the original repository or the shipped pair.
out = fullfile(root, 'evidence', 'build'); if ~isfolder(out), mkdir(out); end
diary(fullfile(out, 'build.log')); cleanD = onCleanup(@() diary('off'));
try
    origF = fullfile(root, 'work', 'VSA_rfsoc_orig_copy.mlapp');
    appDir = fullfile(root, 'app'); if ~isfolder(appDir), mkdir(appDir); end
    newF = fullfile(appDir, 'VSA_rfsoc_refactor.mlapp');
    expF = fullfile(appDir, 'VSA_rfsoc_refactor_exported.m');
    assert(~isfile(newF) && ~isfile(expF), 'build:Exists', 'refusing to overwrite %s', appDir);

    %% 1. Load the 119-component model and calibrate both generators on it
    fr = appdesigner.internal.serialization.FileReader(origF);
    origText = normLF(fr.readMATLABCodeText());
    des = appdesigner.internal.serialization.SerializationFactory.createDeserializer(origF);
    md = des.getAppMetadata();
    appData = des.getAppData();
    code0 = appData.code;
    fig = appData.components.UIFigure;
    s0 = adSections(splitlines(origText));
    assert(isequal(s0.editable, code0.EditableSectionCode(:)), 'build:Calibration', 'editable splitter');
    B = splitlines(normLF(fileread(baseExport)));
    [pl0, cl0, order0] = adComponentCode(fig);
    [bp, bc] = blocks(B);
    cal = struct('components', numel(order0), 'propBlockEqual', isequal(B(bp(1):bp(2)), pl0(:)), ...
        'createBlockEqual', isequal(B(bc(1):bc(2)), cl0(:)));
    disp(cal);
    assert(cal.components == 119 && cal.propBlockEqual && cal.createBlockEqual, 'build:Calibration', ...
        'adComponentCode does not reproduce the shipped 119-component export');

    %% 2. Extend the model explicitly
    spec = uiExtensionSpec();
    existing = cellfun(@(h) char(h.DesignTimeProperties.CodeName), order0, 'UniformOutput', false);
    assert(isempty(intersect(existing, {spec.CodeName})) && numel(unique({spec.CodeName})) == numel(spec), ...
        'build:Spec', 'spec CodeNames must be new and unique');
    amap = appdesigner.internal.appmetadata.getProductionComponentAdapterMap();
    gen = appdesigner.internal.codegeneration.ComponentCodeGenerator();
    byName = containers.Map(existing, order0);
    for k = 1:numel(spec)
        r = spec(k);
        assert(isKey(byName, r.Parent), 'build:Spec', 'unknown parent %s', r.Parent);
        h = r.ctor(byName(r.Parent));
        for j = 1:2:numel(r.Props), h.(r.Props{j}) = r.Props{j+1}; end
        if ~isempty(r.CallbackProperty), h.(r.CallbackProperty) = r.Callback; end
        adapter = feval(amap(class(h)));
        code = gen.getComponentGenerationCode(h, adapter, 'Standard');
        if ~isprop(h, 'DesignTimeProperties'), addprop(h, 'DesignTimeProperties'); end
        h.DesignTimeProperties = struct('CodeName', r.CodeName, 'GroupId', '', 'ComponentCode', {code(:)});
        byName(r.CodeName) = h;
    end
    [pl, cl, order] = adComponentCode(fig);
    assert(numel(order) == 119 + numel(spec), 'build:Count', 'component count %d', numel(order));

    %% 3. Splice regenerated component blocks into the source export
    P = splitlines(normLF(fileread(sourceExport)));
    while isempty(P{end}), P(end) = []; end
    [sp, sc] = blocks(P);
    P = [P(1:sp(1)-1); pl(:); P(sp(2)+1:sc(1)-1); cl(:); P(sc(2)+1:end)];
    regenerated = fullfile(out, 'source_regenerated_exported.m');
    writelines(string(strjoin(P, newline)), regenerated);
    P = replaceOne(P, 'classdef VSA_rfsoc_refactor_exported < matlab.apps.AppBase', ...
        {'classdef VSA_rfsoc_refactor < matlab.apps.AppBase'});
    P = replaceOne(P, '        function app = VSA_rfsoc_refactor_exported(varargin)', ...
        {'        function app = VSA_rfsoc_refactor(varargin)'});
    T = strjoin(P, newline);

    %% 4. Code data from the same text
    s = adSections(P);
    tn = {s.callbacks.Name};
    st = s.callbacks(strcmp(tn, 'startupFcn'));
    assert(strcmp(st.Args, 'varargin'), 'build:Args', 'startup args');
    cbs = s.callbacks(~strcmp(tn, 'startupFcn'));
    template = rmfield(code0.Callbacks(1), intersect(fieldnames(code0.Callbacks), {'ComponentData'}));
    newCb = repmat(template, 0, 1);
    for k = 1:numel(code0.Callbacks)
        assert(any(strcmp({cbs.Name}, code0.Callbacks(k).Name)), 'build:Bound', ...
            'existing callback %s removed', code0.Callbacks(k).Name);
    end
    added = {};
    for j = 1:numel(cbs)
        k = find(strcmp({code0.Callbacks.Name}, cbs(j).Name));
        c = template; c.Name = cbs(j).Name;
        if strcmp(cbs(j).Name, 'updateAppLayout')
            assert(isequal(cbs(j).Code, s0.callbacks(strcmp({s0.callbacks.Name}, 'updateAppLayout')).Code), ...
                'build:Reflow', 'generated updateAppLayout body changed');
            c.Code = code0.Callbacks(k).Code;
        elseif isempty(k)
            c.Code = shapeLike(cbs(j).Code, code0.Callbacks(1).Code);
            added{end+1} = cbs(j).Name; %#ok<AGROW>
        else
            c.Code = shapeLike(cbs(j).Code, code0.Callbacks(k).Code);
        end
        newCb(end+1) = c; %#ok<AGROW>
    end
    bound = {spec(~cellfun(@isempty, {spec.Callback})).Callback};
    assert(isempty(setxor(added, bound)), 'build:Callbacks', ...
        'new callbacks in text (%s) differ from spec bindings (%s)', strjoin(added, ','), strjoin(bound, ','));
    startup = code0.StartupCallback;
    startup.Code = shapeLike(st.Code, code0.StartupCallback.Code);
    if isfield(startup, 'ComponentData'), startup = rmfield(startup, 'ComponentData'); end

    %% 5. Serialize with the extended component model
    shot = fullfile(root, 'work', 'appScreenshot.png');
    if ~isfile(shot), unzip(origF, fullfile(root, 'work', 'unz')); copyfile(fullfile(root, 'work', 'unz', 'metadata', 'appScreenshot.png'), shot); end
    ser = appdesigner.internal.serialization.MLAPPSerializer(newF, fig);
    if isfield(appData.components, 'Groups'), ser.Groups = appData.components.Groups; end
    mm = appdesigner.internal.model.MetadataModel;
    f = setdiff(fieldnames(md), {'Uuid'}, 'stable');
    for k = 1:numel(f), try, mm.(f{k}) = md.(f{k}); catch, end, end
    mm.Uuid = md.Uuid;   % same app identity as the shipped refactor (updated in place)
    ser.Metadata = mm;
    ser.MatlabCodeText = T;
    ser.EditableSectionCode = shapeLike(s.editable, code0.EditableSectionCode);
    ser.Callbacks = newCb;
    ser.StartupCallback = startup;
    ser.InputParameters = 'varargin';
    ser.SingletonMode = '';
    ser.AppTypeData = code0.AppTypeData;
    ser.ClassName = 'VSA_rfsoc_refactor';
    ser.ScreenshotPath = shot;
    ser.OverwriteTargetFile = true;
    ser.save();
    delete(fig);

    %% 6. Export exactly as App Designer's MLAPPExporter would
    ex = appdesigner.internal.serialization.converter.MLAPPExporter(expF, struct('originalName', 'VSA_rfsoc_refactor'));
    txt = ex.getGeneratedCodeForExport(T);
    fid = fopen(expF, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', txt); fclose(fid);

    info = struct('calibration', cal, 'components', numel(order), 'added', numel(spec), ...
        'callbacks', numel(newCb), 'addedCallbacks', {added}, 'editableLines', numel(s.editable), ...
        'startupLines', numel(st.Code), 'mlapp', newF, 'export', expF);
    writelines(jsonencode(info, PrettyPrint=true), fullfile(out, 'build.json'));
    writelines(string(T), fullfile(out, 'document_code.m.txt'));
    fprintf('BUILD_MLAPP_EXT_COMPLETE %s\n', newF);
catch err
    disp(getReport(err, 'extended')); rethrow(err);
end
end

function [p, c] = blocks(L)
% p: first/last line of the component property declarations
% c: first/last line of createComponents after the uifigure block
i0 = find(strcmp(L, '    properties (Access = public)'), 1);
i1 = i0 + find(strcmp(L(i0+1:end), '    end'), 1);
p = [i0+1, i1-1];
c0 = find(strcmp(L, '            % Create RFSoCBeamformerUIFigure and hide until all components are created'));
c1 = find(strcmp(L, '            % Show the figure after all components are created'));
assert(isscalar(c0) && isscalar(c1) && isempty(L{c0+7}) && isempty(L{c1-1}), 'build:Blocks', ...
    'createComponents layout not recognised');
c = [c0+7, c1-2];
end
function t = normLF(t)
t = char(t); t = strrep(t, sprintf('\r\n'), newline); t = strrep(t, sprintf('\r'), newline);
end
function i = findOne(P, line)
i = find(strcmp(P, line)); assert(isscalar(i), 'build:Find', 'expected one line: %s (found %d)', line, numel(i));
end
function P = replaceOne(P, line, repl)
i = findOne(P, line); P = [P(1:i-1); repl(:); P(i+1:end)];
end
function c = shapeLike(c, ref)
c = c(:); if isrow(ref) && numel(ref) > 1, c = c.'; end
end
