function [propLines, createLines, order] = adComponentCode(fig)
%ADCOMPONENTCODE Reassemble App Designer component declarations and the
% createComponents body (after the uifigure block) from the design-time
% model (DesignTimeProperties.ComponentCode / CodeName).
% Ordering rule calibrated byte-exactly on the shipped 119-component
% VSA_rfsoc_refactor pair:
%   createComponents: creation order (Children are reverse-creation except
%     for GridLayout and TabGroup, whose Children are in creation order);
%   property block: reverse creation order per parent, except TabGroup and
%     the auto-reflow root GridLayout, which keep creation order.
order = dfs(fig, true);
porder = dfs(fig, false);
propLines = cell(1, numel(porder));
for k = 1:numel(porder)
    h = porder{k};
    propLines{k} = sprintf('        %-30s %s', h.DesignTimeProperties.CodeName, class(h));
end
createLines = {};
for k = 2:numel(order)
    h = order{k}; d = h.DesignTimeProperties;
    par = h.Parent.DesignTimeProperties.CodeName;
    code = d.ComponentCode(:)';
    code = strrep(code, 'ad_CODENAME_ad', d.CodeName);
    code = strrep(code, 'ad_PARENTCODENAME_ad', par);
    code = regexprep(code, '(Fcn) = ''(\w+)'';$', '$1 = createCallbackFcn(app, @$2, true);');
    createLines = [createLines, {''}, {['            % Create ' d.CodeName]}, strcat({'            '}, code)]; %#ok<AGROW>
end
end

function out = dfs(h, creation)
out = {h};
if ~isprop(h, 'Children'), return; end
ch = allchild(h); ch = ch(:);
keep = false(size(ch));
for k = 1:numel(ch)
    try, ch(k).DesignTimeProperties.CodeName; keep(k) = true; catch, end
end
ch = ch(keep);
creationOrdered = isa(h, 'matlab.ui.container.GridLayout') || isa(h, 'matlab.ui.container.TabGroup');
if ~creationOrdered, ch = flipud(ch); end            % now creation order
if ~creation
    isRoot = isa(h, 'matlab.ui.container.GridLayout') && strcmp(h.DesignTimeProperties.CodeName, 'GridLayout');
    if ~(isRoot || isa(h, 'matlab.ui.container.TabGroup')), ch = flipud(ch); end
end
for k = 1:numel(ch)
    out = [out, dfs(ch(k), creation)]; %#ok<AGROW>
end
end
