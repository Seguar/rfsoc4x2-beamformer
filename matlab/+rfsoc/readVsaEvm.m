function [pct,db,status]=readVsaEvm(measurement,fresh,threshold)
% Both traces are resolved through the SAME selected measurement.
pct=NaN; db=NaN; status='VSA unavailable';
validateattributes(threshold,{'numeric'},{'scalar','finite','>',0,'<=',1});
if ~fresh, status='VSA unavailable: stale acquisition'; return; end
try
    iq=measurement.MeasurementData('IQ Meas1');
    if isempty(iq), status='VSA unavailable: missing IQ measurement'; return; end
    iqGuard=onCleanup(@()iq.Dispose());
    summary=measurement.MeasurementData('OFDM Error Summary1');
    if isempty(summary), status='VSA unavailable: missing OFDM summary'; return; end
    summaryGuard=onCleanup(@()summary.Dispose());
    % Unknown bits (including 32) remain unavailable.
    if int32(iq.Status)~=0 || int32(summary.Status)~=0
        status='VSA unavailable: IQ or summary status nonzero'; return;
    end
    correlation=double(summary.Summary('Ch1SyncCorr'));
    correlationUnit=strtrim(char(summary.SummaryUnit('Ch1SyncCorr')));
    if ~isscalar(correlation) || ~isfinite(correlation) || ...
            correlation<threshold || correlation>1 || ...
            ~any(strcmpi(correlationUnit,{'','1','unitless','dimensionless'}))
        status='VSA unavailable: missing or insufficient normalized sync correlation'; return;
    end
    value=double(summary.Summary('Ch1EVM'));
    unit=strtrim(char(summary.SummaryUnit('Ch1EVM')));
    if ~isscalar(value) || ~isfinite(value) || value<0 || ~strcmp(unit,'%')
        status='VSA unavailable: invalid percent EVM'; return;
    end
    pct=value; db=20*log10(pct/100);
    status='completed: fresh IQ and same-measurement correlated summary';
catch exception
    pct=NaN; db=NaN; status=['VSA unavailable: ' exception.message];
end
end
