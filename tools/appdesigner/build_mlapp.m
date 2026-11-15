function build_mlapp(root, pubExport)
%BUILD_MLAPP Build a private, App Designer-consistent VSA_rfsoc_refactor.mlapp.
%   Component model: loaded from a COPY of the original VSA_rfsoc.mlapp (119 components).
%   Code: the supplied VSA_rfsoc_refactor_exported.m, reshaped to App Designer's
%   generated-code form; code data (editable section, callbacks, startup, input args)
%   is split from that same text, so document.xml code and appModel code data agree.
%   Uses R2026a internal APIs: SerializationFactory, FileReader, MLAPPSerializer,
%   MLAPPExporter.getGeneratedCodeForExport. Never touches the original repository.
out = fullfile(root, 'evidence', 'build'); if ~isfolder(out), mkdir(out); end
diary(fullfile(out, 'build.log')); cleanD = onCleanup(@() diary('off'));
try
    origF = fullfile(root, 'work', 'VSA_rfsoc_orig_copy.mlapp');
    appDir = fullfile(root, 'app'); if ~isfolder(appDir), mkdir(appDir); end
    newF = fullfile(appDir, 'VSA_rfsoc_refactor.mlapp');
    expF = fullfile(appDir, 'VSA_rfsoc_refactor_exported.m');
    assert(~isfile(newF), 'build:Exists', 'refusing to overwrite %s', newF);

    %% 1. Load the original copy (component model + code data + code text)
    fr = appdesigner.internal.serialization.FileReader(origF);
    origText = normLF(fr.readMATLABCodeText());
    des = appdesigner.internal.serialization.SerializationFactory.createDeserializer(origF);
    md = des.getAppMetadata();
    appData = des.getAppData();
    code0 = appData.code;
    fprintf('components fields: %s\n', strjoin(fieldnames(appData.components), ','));
    fprintf('Code orientation: Callbacks(1).Code %s %s; Editable %s %s\n', ...
        class(code0.Callbacks(1).Code), mat2str(size(code0.Callbacks(1).Code)), ...
        class(code0.EditableSectionCode), mat2str(size(code0.EditableSectionCode)));

    %% 2. Calibrate the splitter on the original: must reproduce its stored code data
    s0 = adSections(splitlines(origText));
    cal = struct();
    cal.editableEqual = isequal(s0.editable, code0.EditableSectionCode(:));
    names0 = {code0.Callbacks.Name};
    textNames = {s0.callbacks.Name};
    cal.startupEqual = isequal(s0.callbacks(strcmp(textNames, 'startupFcn')).Code, code0.StartupCallback.Code(:));
    mism = {};
    for k = 1:numel(names0)
        j = find(strcmp(textNames, names0{k}));
        if strcmp(names0{k}, 'updateAppLayout')   % generated auto-reflow callback: stored Code is ''
            if numel(j) ~= 1 || ~isempty(code0.Callbacks(k).Code), mism{end+1} = names0{k}; end %#ok<AGROW>
            continue
        end
        if numel(j) ~= 1 || ~isequal(s0.callbacks(j).Code, code0.Callbacks(k).Code(:)), mism{end+1} = names0{k}; end %#ok<AGROW>
    end
    cal.callbackMismatches = mism;
    cal.callbackOrderEqual = isequal(setdiff(textNames, {'startupFcn'}, 'stable'), names0);
    disp(cal);
    assert(cal.editableEqual && cal.startupEqual && isempty(mism) && cal.callbackOrderEqual, ...
        'build:Calibration', 'splitter does not reproduce the original code data');

    %% 3. Reshape the public export to App Designer generated form
    P = splitlines(normLF(fileread(pubExport)));
    while isempty(P{end}), P(end) = []; end
    P = replaceOne(P, 'classdef VSA_rfsoc_refactor_exported < matlab.apps.AppBase', ...
        {'classdef VSA_rfsoc_refactor < matlab.apps.AppBase'});
    if any(strcmp(P,'        function releaseResources(app)'))
        % Current generated export already contains the App Designer cleanup
        % listener. Keep its editable code intact; only restore its class name.
        P=replaceOne(P,'        function app = VSA_rfsoc_refactor_exported(varargin)', ...
            {'        function app = VSA_rfsoc_refactor(varargin)'});
        header={};
    else
    header = P(2:8);
    assert(all(startsWith(header, '    %')) && isempty(P{9}), 'build:Header', 'unexpected header');
    P(2:8) = [];
    usage = {
        '    % VSA_rfsoc_refactor: refactor of the original 4x2 VSA_rfsoc app'
        '    % (exported class: VSA_rfsoc_refactor_exported).'
        '    % UI components and layout: the original App Designer component model.'
        '    % Behaviour: owned timer, injected backend, bounded transport, freshness,'
        '    % explicit errors and cleanup. Construct with a session config:'
        '    %   app = VSA_rfsoc_refactor(cfg)      % cfg from origapp.defaultConfig'
        '    %   app = VSA_rfsoc_refactor(''backend'', b, ''visible'', true, ...)'
        '    % Startup sends no board, RF, clock, VSA or instrument command.'
        '    % Owned-resource cleanup: releaseResources, run by a UIFigure'
        '    % ObjectBeingDestroyed listener (App Designer owns delete(app)).'
        ''};
    i = findOne(P, '    % Original state (same names; values come from the session config)');
    P = [P(1:i-1); usage; P(i:end)];

    % delete(app) body -> releaseResources (App Designer generates delete(app))
    iDel = findOne(P, '        % Code that executes before app deletion');
    assert(strcmp(P{iDel+1}, '        function delete(app)'), 'build:Delete', 'delete not found');
    iDelEnd = iDel + 1 + find(strcmp(P(iDel+2:end), '        end'), 1);
    delBody = P(iDel+2:iDelEnd-1);
    keepTail = {'            % Delete UIFigure when app is deleted'; '            delete(app.RFSoCBeamformerUIFigure)'};
    assert(isequal(delBody(end-1:end), keepTail), 'build:DeleteTail', 'unexpected delete tail');
    owned = delBody(1:end-2);
    assert(startsWith(owned{1}, '            % Owned resources'), 'build:DeleteHead', 'unexpected delete head');
    P = [P(1:iDel+1); {''}; keepTail; P(iDelEnd:end)];

    iTe = findOne(P, '        function onTimerError(app, ~, evt)');
    iTeEnd = iTe + find(strcmp(P(iTe+1:end), '        end'), 1);
    assert(strcmp(P{iTeEnd+1}, '    end'), 'build:Methods', 'onTimerError is not last in its block');
    rel = [{''; '        function releaseResources(app)'}; owned; ...
        {'            % Called from the UIFigure ObjectBeingDestroyed listener (startupFcn).'; '        end'}];
    P = [P(1:iTeEnd); rel; P(iTeEnd+1:end)];

    % startupFcn: register cleanup first; hide when cfg.visible is false
    iS = findOne(P, '        function startupFcn(app, varargin)');
    P = [P(1:iS); {'            addlistener(app.RFSoCBeamformerUIFigure, ''ObjectBeingDestroyed'', @(~,~) releaseResources(app));'}; P(iS+1:end)];
    iV = findOne(P, '                app.RFSoCBeamformerUIFigure.Visible = ''on'';');
    assert(strcmp(P{iV+1}, '            end'), 'build:Visible', 'visible block');
    P = [P(1:iV); {'            else'; '                % App Designer shows the figure at the end of createComponents.'; ...
        '                app.RFSoCBeamformerUIFigure.Visible = ''off'';'}; P(iV+1:end)];

    % createComponents: App Designer always generates Visible = 'on'
    P = replaceOne(P, '            app.RFSoCBeamformerUIFigure.Visible = ''off''; % refactor: startupFcn applies cfg.visible', ...
        {'            app.RFSoCBeamformerUIFigure.Visible = ''on'';'});

    % Constructor in App Designer form (input arguments, no singleton)
    P = replaceOne(P, '        function app = VSA_rfsoc_refactor_exported(varargin)', {'        function app = VSA_rfsoc_refactor(varargin)'});
    P = replaceOne(P, '            % No singleton focus: several hidden instances may exist in tests.', {});
    iC = findOne(P, '        % Construct app');
    ctor = {'        % Construct app'; '        function app = VSA_rfsoc_refactor(varargin)'; ''
        '            % Create UIFigure and components'; '            createComponents(app)'; ''
        '            % Register the app with App Designer'; '            registerApp(app, app.RFSoCBeamformerUIFigure)'; ''
        '            % Execute the startup function'; '            runStartupFcn(app, @(app)startupFcn(app, varargin{:}))'; ''
        '            if nargout == 0'; '                clear app'; '            end'; '        end'};
    assert(isequal(P(iC:iC+numel(ctor)-1), ctor), 'build:Ctor', 'constructor is not in App Designer form');
    end
    T = strjoin(P, newline);   % original document code has no final newline

    %% 4. Code data split from the same text
    s = adSections(P);
    tn = {s.callbacks.Name};
    st = s.callbacks(strcmp(tn, 'startupFcn'));
    assert(strcmp(st.Args, 'varargin'), 'build:Args', 'startup args');
    cbs = s.callbacks(~strcmp(tn, 'startupFcn'));
    newCb = code0.Callbacks([]);
    dropped = {};
    for k = 1:numel(code0.Callbacks)
        j = find(strcmp({cbs.Name}, code0.Callbacks(k).Name));
        if isempty(j)
            assert(isempty(code0.Callbacks(k).ComponentData), 'build:Bound', 'bound callback %s removed', code0.Callbacks(k).Name);
            dropped{end+1} = code0.Callbacks(k).Name; %#ok<AGROW>
            continue
        end
        c = code0.Callbacks(k);
        if strcmp(c.Name, 'updateAppLayout')
            assert(isequal(cbs(j).Code, s0.callbacks(strcmp(textNames, 'updateAppLayout')).Code), ...
                'build:Reflow', 'generated updateAppLayout body changed');
        else
            c.Code = shapeLike(cbs(j).Code, code0.Callbacks(k).Code);
        end
        newCb(end+1) = c; %#ok<AGROW>
    end
    assert(isequal({newCb.Name}, {cbs.Name}), 'build:Callbacks', 'callback set/order differs from code text');
    startup = code0.StartupCallback;
    startup.Code = shapeLike(st.Code, code0.StartupCallback.Code);

    %% 5. Serialize with the original (unchanged) component model
    shot = fullfile(root, 'work', 'appScreenshot.png');
    if ~isfile(shot), unzip(origF, fullfile(root, 'work', 'unz')); copyfile(fullfile(root, 'work', 'unz', 'metadata', 'appScreenshot.png'), shot); end
    ser = appdesigner.internal.serialization.MLAPPSerializer(newF, appData.components.UIFigure);
    if isfield(appData.components, 'Groups'), ser.Groups = appData.components.Groups; end
    mm = appdesigner.internal.model.MetadataModel;
    f = fieldnames(md);
    f = setdiff(f, {'Uuid'}, 'stable');   % Uuid is set-once: new identity for the new app
    for k = 1:numel(f), try, mm.(f{k}) = md.(f{k}); catch, end, end
    mm.Uuid = '5651d1a8-fc61-4d3f-b539-b79f6e9754a0';   % python uuid4, fixed for reproducibility
    ser.Metadata = mm;
    ser.MatlabCodeText = T;
    ser.EditableSectionCode = shapeLike(s.editable, code0.EditableSectionCode);
    % MLAPP v2 does not store ComponentData: bindings live on the design-time
    % components and restoreCallbackComponentData rebuilds them at load.
    ser.Callbacks = rmfield(newCb, intersect(fieldnames(newCb), {'ComponentData'}));
    if isfield(startup, 'ComponentData'), startup = rmfield(startup, 'ComponentData'); end
    ser.StartupCallback = startup;
    ser.InputParameters = 'varargin';
    ser.SingletonMode = '';
    ser.AppTypeData = code0.AppTypeData;
    ser.ClassName = 'VSA_rfsoc_refactor';
    ser.ScreenshotPath = shot;
    ser.OverwriteTargetFile = true;
    ser.save();
    delete(appData.components.UIFigure);

    %% 6. Export exactly as App Designer's MLAPPExporter would (no editor call)
    ex = appdesigner.internal.serialization.converter.MLAPPExporter(expF, struct('originalName', 'VSA_rfsoc_refactor'));
    txt = ex.getGeneratedCodeForExport(T);
    fid = fopen(expF, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', txt); fclose(fid);

    info = struct('calibration', cal, 'droppedOrphanCallbacks', {dropped}, ...
        'callbacks', numel(newCb), 'editableLines', numel(s.editable), 'startupLines', numel(st.Code), ...
        'removedHeader', {header}, 'mlapp', newF, 'export', expF);
    writelines(jsonencode(info, PrettyPrint=true), fullfile(out, 'build.json'));
    writelines(string(T), fullfile(out, 'document_code.m.txt'));
    fprintf('BUILD_MLAPP_COMPLETE %s\n', newF);
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
