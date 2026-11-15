function [pct,db,status,quality]=readVsaEvm(measurement,fresh,threshold,allowSetxStatus32)
% Both traces are resolved through the SAME selected measurement.
pct=NaN; db=NaN; status='VSA unavailable';
if nargin<4, allowSetxStatus32=false; end
quality=struct('iqStatus',NaN,'summaryStatus',NaN,'unclassifiedBits',0,'syncCorrelation',NaN);
validateattributes(threshold,{'numeric'},{'scalar','finite','>',0,'<=',1});
if ~fresh, status='VSA unavailable: stale acquisition'; return; end
try
    iq=measurement.MeasurementData('IQ Meas1');
    if isempty(iq), status='VSA unavailable: missing IQ measurement'; return; end
    iqGuard=onCleanup(@()iq.Dispose());
    summary=measurement.MeasurementData('OFDM Error Summary1');
    if isempty(summary), status='VSA unavailable: missing OFDM summary'; return; end
    summaryGuard=onCleanup(@()summary.Dispose());
    quality.iqStatus=double(iq.Status); quality.summaryStatus=double(summary.Status);
    statuses=[quality.iqStatus quality.summaryStatus];
    % Strict by default. Opt-in SETX policy allows only unnamed bit 32,
    % retaining it as a warning. All other nonzero bits remain rejected.
    if any(~ismember(statuses,[0 32])) || (~allowSetxStatus32 && any(statuses~=0))
        status='VSA unavailable: IQ or summary status nonzero'; return;
    end
    if allowSetxStatus32
        if ~isempty(strtrim(char(measurement.Status.MeasurementError))) || ...
                ~isempty(strtrim(char(iq.Indicator))) || ~isempty(strtrim(char(iq.IndicatorReason))) || ...
                ~isempty(strtrim(char(summary.Indicator))) || ~isempty(strtrim(char(summary.IndicatorReason)))
            status='VSA unavailable: vendor measurement or trace indicator'; return;
        end
        if any(statuses==32), quality.unclassifiedBits=32; end
    end
    correlation=double(summary.Summary('Ch1SyncCorr'));
    quality.syncCorrelation=correlation;
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
    if quality.unclassifiedBits~=0
        status=[status '; WARNING: unclassified vendor trace bit 32'];
    end
catch exception
    pct=NaN; db=NaN; status=['VSA unavailable: ' exception.message];
end
end
