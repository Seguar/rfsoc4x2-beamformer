function s = adSections(lines)
%ADSECTIONS Split App Designer generated class code into its user-editable parts.
%   lines: cellstr column, one line each, no line terminators.
%   s.editable  : editable section lines (between the auto-reflow block and callbacks)
%   s.callbacks : struct array Name / Code (body lines) / Args, in file order
%   The rule is calibrated against the original VSA_rfsoc.mlapp (see build_mlapp).
lines = lines(:);
iReflow = find(strcmp(lines, '    % Properties that correspond to apps with auto-reflow'), 1);
assert(~isempty(iReflow), 'adSections:NoReflow', 'auto-reflow properties block not found');
iEnd = iReflow + find(strcmp(lines(iReflow+1:end), '    end'), 1);
iCb = find(strcmp(lines, '    % Callbacks that handle component events'), 1);
iInit = find(strcmp(lines, '    % Component initialization'), 1);
assert(~isempty(iCb) && ~isempty(iInit) && iCb < iInit, 'adSections:Blocks', 'callback block not found');
assert(isempty(strtrim(lines{iEnd+1})) && isempty(strtrim(lines{iCb-1})), 'adSections:Spacing', 'unexpected spacing');
s.editable = lines(iEnd+2 : iCb-2);
cb = struct('Name', {}, 'Code', {}, 'Args', {});
k = iCb;
while k < iInit
    tok = regexp(lines{k}, '^        function (\w+)\(app(, .*)?\)$', 'tokens', 'once');
    if ~isempty(tok)
        if numel(tok) < 2, tok{2} = ''; end
        tok{2} = regexprep(tok{2}, '^, ', '');
        e = k + find(strcmp(lines(k+1:iInit), '        end'), 1);
        cb(end+1) = struct('Name', tok{1}, 'Code', {lines(k+1:e-1)}, 'Args', tok{2}); %#ok<AGROW>
        k = e;
    end
    k = k + 1;
end
s.callbacks = cb;
end
