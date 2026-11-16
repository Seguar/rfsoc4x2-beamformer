function L = adFigureCode(fig)
%ADFIGURECODE createComponents uifigure lines from the figure's design-time
% code (same substitutions as adComponentCode).
d = fig.DesignTimeProperties;
code = strrep(d.ComponentCode(:)', 'ad_CODENAME_ad', d.CodeName);
code = regexprep(code, '(Fcn) = ''(\w+)'';$', '$1 = createCallbackFcn(app, @$2, true);');
L = strcat({'            '}, code(:));
end
