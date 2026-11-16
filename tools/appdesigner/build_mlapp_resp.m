function build_mlapp_resp(root, sourceExport, baseExport)
%BUILD_MLAPP_RESP Rebuild VSA_rfsoc_refactor.mlapp + export with explicit
% property changes (uiModifySpec) to existing components of the shipped
% 151-component model. Companion of build_mlapp_ext (component additions).
%
%   root         new private workspace; root/work/VSA_rfsoc_base_copy.mlapp
%                must be a COPY of the shipped VSA_rfsoc_refactor.mlapp
%   sourceExport edited VSA_rfsoc_refactor_exported.m (code changes); its
%                component blocks, figure block and updateAppLayout body are
%                REGENERATED from the modified model, never hand-written
%   baseExport   shipped export matching the .mlapp copy (calibration input)
%
% Steps: (1) calibrate adComponentCode, the figure block and reflowCode
% byte-exactly on the shipped pair, and App Designer's ComponentCodeGenerator
% on every component to be modified; (2) apply uiModifySpec (old value
% asserted) and regenerate those components' code; (3) splice regenerated
% blocks into the source; (4) code data from the same text; (5)
% MLAPPSerializer; (6) MLAPPExporter. R2026a internal APIs.
out = fullfile(root, 'evidence', 'build'); if ~isfolder(out), mkdir(out); end
diary(fullfile(out, 'build.log')); cleanD = onCleanup(@() diary('off'));
try
    baseF = fullfile(root, 'work', 'VSA_rfsoc_base_copy.mlapp');
    appDir = fullfile(root, 'app'); if ~isfolder(appDir), mkdir(appDir); end
    newF = fullfile(appDir, 'VSA_rfsoc_refactor.mlapp');
    expF = fullfile(appDir, 'VSA_rfsoc_refactor_exported.m');
    assert(~isfile(newF) && ~isfile(expF), 'build:Exists', 'refusing to overwrite %s', appDir);

    %% 1. Load the shipped model and calibrate every generator on it
    fr = appdesigner.internal.serialization.FileReader(baseF);
    baseText = normLF(fr.readMATLABCodeText());
    des = appdesigner.internal.serialization.SerializationFactory.createDeserializer(baseF);
    md = des.getAppMetadata();
    appData = des.getAppData();
    code0 = appData.code;
    fig = appData.components.UIFigure;
    s0 = adSections(splitlines(baseText));
    assert(isequal(s0.editable, code0.EditableSectionCode(:)), 'build:Calibration', 'editable splitter');
    B = splitlines(normLF(fileread(baseExport)));
    [pl0, cl0, order0] = adComponentCode(fig);
    [bp, bc, bf] = adBlocks(B);
    lay0 = s0.callbacks(strcmp({s0.callbacks.Name}, 'updateAppLayout')).Code;
    cal = struct('components', numel(order0), 'propBlockEqual', isequal(B(bp(1):bp(2)), pl0(:)), ...
        'createBlockEqual', isequal(B(bc(1):bc(2)), cl0(:)), ...
        'figureBlockEqual', isequal(B(bf(1):bf(2)), adFigureCode(fig)), ...
        'reflowEqual', isequal(lay0(:), reflowCode(fig)));
    disp(cal);
    assert(cal.components == 151 && cal.propBlockEqual && cal.createBlockEqual && cal.figureBlockEqual && ...
        cal.reflowEqual, 'build:Calibration', 'generators do not reproduce the shipped 151-component export');

    %% 2. Apply the explicit property changes
    spec = uiModifySpec();
    amap = appdesigner.internal.appmetadata.getProductionComponentAdapterMap();
    gen = appdesigner.internal.codegeneration.ComponentCodeGenerator();
    byName = containers.Map(cellfun(@(h) char(h.DesignTimeProperties.CodeName), order0, 'UniformOutput', false), order0);
    regenCal = struct('CodeName', {}, 'regenEqualBefore', {});
    for k = 1:numel(spec)
        r = spec(k);
        assert(isKey(byName, r.CodeName), 'build:Spec', 'unknown component %s', r.CodeName);
        h = byName(r.CodeName);
        assert(isequal(h.(r.Property), r.Old), 'build:Spec', '%s.%s is not the expected shipped value', r.CodeName, r.Property);
        c = gen.getComponentGenerationCode(h, feval(amap(class(h))), 'Standard');
        regenCal(end+1) = struct('CodeName', r.CodeName, 'regenEqualBefore', ...
            isequal(c(:), h.DesignTimeProperties.ComponentCode(:))); %#ok<AGROW>
        assert(regenCal(end).regenEqualBefore, 'build:Calibration', 'generator differs on unmodified %s', r.CodeName);
        h.(r.Property) = r.New;
        assert(isequal(h.(r.Property), r.New), 'build:Spec', '%s.%s not accepted', r.CodeName, r.Property);
    end
    for name = reshape(unique({spec.CodeName}), 1, [])   % none for a code-only rebuild
        h = byName(name{1}); d = h.DesignTimeProperties;
        d.ComponentCode = gen.getComponentGenerationCode(h, feval(amap(class(h))), 'Standard');
        h.DesignTimeProperties = d;
    end
    [pl, cl, order] = adComponentCode(fig);
    assert(numel(order) == 151, 'build:Count', 'component count %d', numel(order));

    %% 3. Splice regenerated blocks into the source export (bottom-up)
    P = splitlines(normLF(fileread(sourceExport)));
    while isempty(P{end}), P(end) = []; end
    [sp, sc, sf] = adBlocks(P);
    assert(sp(2) < sf(1) && sf(2) < sc(1), 'build:Blocks', 'unexpected block order');
    P = [P(1:sf(1)-1); adFigureCode(fig); P(sf(2)+1:sc(1)-1); cl(:); P(sc(2)+1:end)];
    P = [P(1:sp(1)-1); pl(:); P(sp(2)+1:end)];
    s1 = adSections(P);
    lay = s1.callbacks(strcmp({s1.callbacks.Name}, 'updateAppLayout'));
    i0 = find(strcmp(P, '        function updateAppLayout(app, event)'));
    assert(isscalar(i0) && isequal(P(i0+1:i0+numel(lay.Code)), lay.Code(:)), 'build:Reflow', 'updateAppLayout not found');
    P = [P(1:i0); reflowCode(fig); P(i0+numel(lay.Code)+1:end)];
    regenerated = fullfile(out, 'source_regenerated_exported.m');
    writelines(string(strjoin(P, newline)), regenerated);
    P = replaceOne(P, 'classdef VSA_rfsoc_refactor_exported < matlab.apps.AppBase', ...
        {'classdef VSA_rfsoc_refactor < matlab.apps.AppBase'});
    P = replaceOne(P, '        function app = VSA_rfsoc_refactor_exported(varargin)', ...
        {'        function app = VSA_rfsoc_refactor(varargin)'});
    T = strjoin(P, newline);

    %% 4. Code data from the same text (no callback added or removed)
    s = adSections(P);
    tn = {s.callbacks.Name};
    st = s.callbacks(strcmp(tn, 'startupFcn'));
    assert(strcmp(st.Args, 'varargin'), 'build:Args', 'startup args');
    cbs = s.callbacks(~strcmp(tn, 'startupFcn'));
    assert(isempty(setxor({cbs.Name}, {code0.Callbacks.Name})), 'build:Callbacks', ...
        'callback set differs from the shipped model');
    newCb = code0.Callbacks;
    for k = 1:numel(newCb)
        if strcmp(newCb(k).Name, 'updateAppLayout'), continue, end   % generated: stored empty
        j = find(strcmp({cbs.Name}, newCb(k).Name));
        newCb(k).Code = shapeLike(cbs(j).Code, code0.Callbacks(k).Code);
    end
    if isfield(newCb, 'ComponentData'), newCb = rmfield(newCb, 'ComponentData'); end
    startup = code0.StartupCallback;
    startup.Code = shapeLike(st.Code, code0.StartupCallback.Code);
    if isfield(startup, 'ComponentData'), startup = rmfield(startup, 'ComponentData'); end

    %% 5. Serialize with the modified component model
    shot = fullfile(root, 'work', 'appScreenshot.png');
    if ~isfile(shot), unzip(baseF, fullfile(root, 'work', 'unz')); copyfile(fullfile(root, 'work', 'unz', 'metadata', 'appScreenshot.png'), shot); end
    ser = appdesigner.internal.serialization.MLAPPSerializer(newF, fig);
    if isfield(appData.components, 'Groups'), ser.Groups = appData.components.Groups; end
    mm = appdesigner.internal.model.MetadataModel;
    f = setdiff(fieldnames(md), {'Uuid'}, 'stable');
    for k = 1:numel(f), try, mm.(f{k}) = md.(f{k}); catch, end, end
    mm.Uuid = md.Uuid;
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

    info = struct('calibration', cal, 'regenCalibration', regenCal, 'components', numel(order), ...
        'modified', {strcat({spec.CodeName}, '.', {spec.Property})}, 'callbacks', numel(newCb), ...
        'editableLines', numel(s.editable), 'startupLines', numel(st.Code), 'mlapp', newF, 'export', expF);
    writelines(jsonencode(info, PrettyPrint=true), fullfile(out, 'build.json'));
    writelines(string(T), fullfile(out, 'document_code.m.txt'));
    fprintf('BUILD_MLAPP_RESP_COMPLETE %s\n', newF);
catch err
    disp(getReport(err, 'extended')); rethrow(err);
end
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
