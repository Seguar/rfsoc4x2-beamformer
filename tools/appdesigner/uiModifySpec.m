function spec = uiModifySpec()
%UIMODIFYSPEC Intentional property changes to EXISTING components of the
% 151-component VSA_rfsoc_refactor model (69ea229: 119 original + 32 port).
% Responsive layout for short laptop screens: a landscape design window that
% fits 1366x768, a scrollable left control panel (its absolute-positioned
% tabs keep their original layout and scroll instead of being clipped) and a
% left column wide enough for the vertical scroll bar. Nothing else changes;
% verify_mlapp_resp allows exactly these (CodeName, property) differences.
%
% Each row: CodeName, property, value in the shipped model, new value.
% The generated updateAppLayout follows App Designer's two-panel reflow rule
% (rows = design figure height, left column = GridLayout column 1).
R = {
 'RFSoCBeamformerUIFigure', 'Position',    [100 100 835 949], [100 100 1180 680]
 'GridLayout',              'ColumnWidth', {234, '1x'},       {250, '1x'}
 'LeftPanel',               'Scrollable',  matlab.lang.OnOffSwitchState('off'), matlab.lang.OnOffSwitchState('on')
};
spec = cell2struct(R, {'CodeName','Property','Old','New'}, 2);
end
