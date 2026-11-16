function lines = reflowCode(fig)
%REFLOWCODE updateAppLayout body that App Designer generates for its
% two-panel auto-reflow template (R2026a bundle: rows = left/right panel
% design heights, left column = left panel design width). In the design-time
% model the panels are layout-managed, so their sizes are taken from the
% figure design height (single row, zero padding) and GridLayout column 1.
h = findall(fig); h = h(arrayfun(@(x) isprop(x, 'DesignTimeProperties'), h));
nm = arrayfun(@(x) char(x.DesignTimeProperties.CodeName), h, 'UniformOutput', false);
G = h(strcmp(nm, 'GridLayout'));
assert(isscalar(G) && isequal(G.RowHeight, {'1x'}) && isequal(G.Padding, [0 0 0 0]) && ...
    G.RowSpacing == 0 && G.ColumnSpacing == 0 && isnumeric(G.ColumnWidth{1}) && isequal(G.ColumnWidth{2}, '1x'), ...
    'reflowCode:Layout', 'two-panel reflow layout not recognised');
H = fig.Position(4); W = G.ColumnWidth{1};
lines = {
 '            currentFigureWidth = app.RFSoCBeamformerUIFigure.Position(3);'
 '            if(currentFigureWidth <= app.onePanelWidth)'
 '                % Change to a 2x1 grid'
 sprintf('                app.GridLayout.RowHeight = {%d, %d};', H, H)
 '                app.GridLayout.ColumnWidth = {''1x''};'
 '                app.RightPanel.Layout.Row = 2;'
 '                app.RightPanel.Layout.Column = 1;'
 '            else'
 '                % Change to a 1x2 grid'
 '                app.GridLayout.RowHeight = {''1x''};'
 sprintf('                app.GridLayout.ColumnWidth = {%d, ''1x''};', W)
 '                app.RightPanel.Layout.Row = 1;'
 '                app.RightPanel.Layout.Column = 2;'
 '            end'};
end
