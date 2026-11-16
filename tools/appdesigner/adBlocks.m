function [p, c, f] = adBlocks(L)
%ADBLOCKS Line ranges of the generated component code in an export (cellstr):
% p = component property declarations, c = createComponents body after the
% uifigure block (starting with its blank line), f = the uifigure code lines.
i0 = find(strcmp(L, '    properties (Access = public)'), 1);
i1 = i0 + find(strcmp(L(i0+1:end), '    end'), 1);
p = [i0+1, i1-1];
c0 = find(strcmp(L, '            % Create RFSoCBeamformerUIFigure and hide until all components are created'));
c1 = find(strcmp(L, '            % Show the figure after all components are created'));
assert(isscalar(c0) && isscalar(c1) && isempty(L{c0+7}) && isempty(L{c1-1}), 'adBlocks:Layout', ...
    'createComponents layout not recognised');
c = [c0+7, c1-2];
f = [c0+1, c0+6];
end
