function P = ofdmProfile(setxPath, fsRx, varargin)
%OFDMPROFILE Custom OFDM parameters read from a Keysight 89600 .setx file
% (Agilent.SA.Vsa.CustomOfdm measurement) for the integrated analyzer.
%
%   P = origapp.ofdmProfile(setxPath, fsRx, 'sha256', pinnedSha, 'reference', ref)
%
% Every parameter comes from the file (FFT length, guard interval, system
% sample rate, guard subcarriers, resource map, preamble and pilot values,
% modulation per cell, repeat index, result length, symbol time adjust,
% tracking/equalizer flags). Nothing is assumed (no FFT256 fallback).
% fsRx is the rate of the analysed buffer. The receiver uses an
% Nr = Nfft*fsRx/fsys point FFT per symbol at fsRx (80 at 125 MS/s for
% 64 at 100 MS/s): for a band-limited signal whose occupied subcarriers lie
% inside +-fsRx/2 this is the exact 125->100 conversion of the subcarrier
% values (no resampling filter). A non-integer Nr or Ncp is refused.
%
% Optional 'reference' (column vector at fsRx, the transmitted loop) gives the
% burst length in symbols and the transmitted pilot values per symbol, both
% checked against the SETX (reference-aided profile constants). The
% reference payload is never used for gain/phase/channel fitting.
%
% Cell codes in the SETX RUMap: 0 data, 1 pilot, 3 preamble, 4 unused
% (checked: counts per row must match the preamble/pilot value lists).
o = struct('sha256', "", 'reference', [], 'maxDataSymbols', 64);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
setxPath = string(setxPath);
assert(isfile(setxPath), 'origapp:OfdmProfile', 'SETX file not found: %s', setxPath);
raw = fileread(setxPath);
sha = lower(string(origapp.LegacyVsaBackend.sha256(char(setxPath))));
if strlength(string(o.sha256)) > 0
    assert(sha == lower(string(o.sha256)), 'origapp:OfdmProfile', ...
        'SETX SHA256 %s differs from the pinned profile %s.', sha, o.sha256);
end
i0 = strfind(raw, 'CustomOfdm.MeasurementExtension');
assert(~isempty(i0), 'origapp:OfdmProfile', 'SETX has no CustomOfdm measurement.');
i1 = strfind(raw(i0(1):end), '</State>');
assert(~isempty(i1), 'origapp:OfdmProfile', 'SETX CustomOfdm state is not terminated.');
seg = raw(i0(1):i0(1)+i1(1));
tok = regexp(seg, '<(\w+) key="(DemodFlexOfdm[^"]+)" value="([^"]*)"', 'tokens');
K = containers.Map();
for k = 1:numel(tok), K(tok{k}{2}) = tok{k}{3}; end
num = @(name) str2double(strsplit(strtrim(getk(K, name))));
flag = @(name) strcmpi(strtrim(getk(K, name)), 'true');

P = struct();
P.setxPath = setxPath; P.setxSha256 = sha;
P.nfft = num('DemodFlexOfdmFFTLen');
P.guardInterval = num('DemodFlexOfdmGuardInt');
P.fsys = num('DemodFlexOfdmSysSmpFreq');
P.guardLower = num('DemodFlexOfdmGuardSubcarsLower');
P.guardUpper = num('DemodFlexOfdmGuardSubcarsUpper');
P.resultLength = num('DemodFlexOfdmResLen');
P.repeatIndex = num('DemodFlexOfdmRURepeatIdx');          % 0-based row
P.measInterval = num('DemodFlexOfdmMeasInt');
P.measOffset = num('DemodFlexOfdmMeasOffset');
P.symTimeAdjPercent = num('DemodFlexOfdmSymTimeAdj');
P.searchLengthS = num('DemodFlexOfdmSrchLen');
P.mirrorFreq = flag('DemodFlexOfdmMirrorFreq');
P.vendor = struct('eqUsePreamble', flag('DemodFlexOfdmEqUsePmbl'), 'eqUsePilot', flag('DemodFlexOfdmEqUsePilot'), ...
    'eqUseData', flag('DemodFlexOfdmEqUseData'), 'trackPhase', flag('DemodFlexOfdmTrkPhase'), ...
    'trackTiming', flag('DemodFlexOfdmTrkTiming'), 'trackAmplitude', flag('DemodFlexOfdmTrkAmp'), ...
    'trackData', flag('DemodFlexOfdmTrkData'), 'normalize', flag('DemodFlexOfdmNormalize'), ...
    'evmNormRef', flag('DemodFlexOfdmEVMNormRef'), 'syncMode', num('DemodFlexOfdmSyncMode'));
assert(isscalar(P.nfft) && P.nfft >= 8 && P.nfft == fix(P.nfft), 'origapp:OfdmProfile', 'Bad FFT length.');
assert(~P.mirrorFreq, 'origapp:OfdmProfile', 'MirrorFreq=true is not implemented.');
ncp = P.nfft*P.guardInterval;
assert(abs(ncp - round(ncp)) < 1e-9, 'origapp:OfdmProfile', 'Guard interval is not an integer sample count.');
P.ncp = round(ncp);
nActive = P.nfft - P.guardLower - P.guardUpper;
P.bins = (-P.nfft/2 + P.guardLower) : (P.nfft/2 - 1 - P.guardUpper);   % subcarrier index per map column
assert(numel(P.bins) == nActive, 'origapp:OfdmProfile', 'Guard subcarriers inconsistent.');

ru = num('DemodFlexOfdmRUMap'); md = num('DemodFlexOfdmRUMod');
assert(mod(numel(ru), nActive) == 0 && numel(md) == numel(ru), 'origapp:OfdmProfile', ...
    'RUMap/RUMod length %d is not rows x %d active subcarriers.', numel(ru), nActive);
P.ruMap = reshape(ru, nActive, []).';     % rows = symbols, columns = P.bins (row-major in file)
P.ruMod = reshape(md, nActive, []).';
nRows = size(P.ruMap, 1);
assert(P.repeatIndex >= 0 && P.repeatIndex < nRows, 'origapp:OfdmProfile', 'RURepeatIdx outside the map.');
assert(all(ismember(P.ruMap(:), [0 1 3 4])), 'origapp:OfdmProfile', 'Unsupported RUMap cell code.');
pm = num('DemodFlexOfdmPmblVals'); pv = num('DemodFlexOfdmPilotVals');
pm = pm(1:2:end) + 1j*pm(2:2:end); pv = pv(1:2:end) + 1j*pv(2:2:end);
mt = P.ruMap.'; isPm = mt == 3; isPl = mt == 1;
assert(nnz(isPm) == numel(pm), 'origapp:OfdmProfile', '%d preamble cells but %d PmblVals.', nnz(isPm), numel(pm));
assert(nnz(isPl) == numel(pv), 'origapp:OfdmProfile', '%d pilot cells but %d PilotVals.', nnz(isPl), numel(pv));
V = zeros(size(mt)); V(isPm) = pm; V(isPl) = pv;     % raster order (row by row)
P.cellValue = V.';                                    % known preamble/pilot value per map cell
qid = num('DemodFlexOfdmQAMModID'); qlev = num('DemodFlexOfdmQAMLevel');
P.qamModId = qid; P.qamBits = qlev(end-numel(qid)+1:end);
P.preambleRows = find(all(P.ruMap ~= 0 & P.ruMap ~= 1, 2) & any(P.ruMap == 3, 2)).';
P.fullPreambleRows = P.preambleRows(sum(P.ruMap(P.preambleRows,:) == 3, 2) >= nActive - 1);
assert(numel(P.fullPreambleRows) >= 1, 'origapp:OfdmProfile', 'No full preamble (training) row: no channel estimate.');
P.payloadRows = setdiff(1:nRows, P.preambleRows);
% modulation (bits/cell) of data cells per row
P.rowBits = nan(1, nRows);
for r = P.payloadRows
    m = unique(P.ruMod(r, P.ruMap(r,:) == 0));
    assert(isscalar(m) && any(qid == m), 'origapp:OfdmProfile', 'Row %d mixes modulations.', r);
    P.rowBits(r) = P.qamBits(qid == m);
end
assert(all(ismember(P.rowBits(P.payloadRows), [1 2 4 6 8])), 'origapp:OfdmProfile', 'Unsupported QAM order.');

% ---- receive rate ----
P.fsRx = fsRx;
Nr = P.nfft*fsRx/P.fsys; Ncr = P.ncp*fsRx/P.fsys;
assert(abs(Nr-round(Nr)) < 1e-9 && abs(Ncr-round(Ncr)) < 1e-9, 'origapp:OfdmProfile', ...
    'fsRx %.6g / fsys %.6g gives a non-integer FFT/CP length (%.3f/%.3f): unsupported rate ratio.', fsRx, P.fsys, Nr, Ncr);
P.nr = round(Nr); P.ncpr = round(Ncr); P.symLen = P.nr + P.ncpr;
assert(max(abs(P.bins)) < P.nr/2, 'origapp:OfdmProfile', 'Occupied subcarriers exceed the receive Nyquist band.');
P.binIdx = mod(P.bins, P.nr) + 1;                     % FFT index at fsRx
P.fftStart = P.ncpr + round(P.symTimeAdjPercent/100*P.nr);   % FFT window start inside a symbol
assert(P.fftStart >= 0 && P.fftStart <= P.ncpr, 'origapp:OfdmProfile', 'SymTimeAdj outside the guard interval.');
P.subcarrierSpacing = P.fsys/P.nfft;
% time-domain preamble at fsRx (sync template)
tmpl = zeros(numel(P.preambleRows)*P.symLen, 1);
for q = 1:numel(P.preambleRows)
    r = P.preambleRows(q); X = zeros(P.nr, 1);
    c = P.ruMap(r,:) == 3; X(P.binIdx(c)) = P.cellValue(r, c);
    s = ifft(X)*P.nr/sqrt(P.nfft);
    tmpl((q-1)*P.symLen + (1:P.symLen)) = [s(end-P.ncpr+1:end); s];
end
P.preambleTemplate = tmpl;
% Burst length (symbols): from the reference if given, else the map rows only.
P.burstSymbols = nRows; P.burstSymbolsSource = "SETX resource map rows (no reference)";
P.pilotPolarity = []; P.pilotSource = "SETX PilotVals (repeat row reused)";
if ~isempty(o.reference)
    P = deriveFromReference(P, o.reference(:), o.maxDataSymbols);
end
P.summary = profileSummary(P);
end

function v = getk(K, name)
assert(isKey(K, name), 'origapp:OfdmProfile', 'SETX lacks %s.', name);
v = K(name);
end

function P = deriveFromReference(P, ref, maxData)
% Locate the first complete burst in the transmitted loop by the preamble
% template (exact integer timing at fsRx is not guaranteed: the DAC 500->125
% decimation of a 5501.25-row burst period leaves quarter-sample phases), then
% count active symbols and read the transmitted pilot cells per symbol.
rho = origapp.ofdmSyncMetric(ref, P.preambleTemplate);
[pk, n0] = max(rho);
assert(pk > 0.95, 'origapp:OfdmProfile', 'Reference does not contain the SETX preamble (rho %.3f).', pk);
nRows = size(P.ruMap, 1); maxSym = nRows + maxData;
e = zeros(1, maxSym);
for s = 1:maxSym
    a = n0 + (s-1)*P.symLen; b = a + P.symLen - 1;
    if b > numel(ref), break; end
    e(s) = mean(abs(ref(a:b)).^2);
end
act = e > 0.05*median(e(1:numel(P.preambleRows)));
nb = find(~act, 1) - 1; if isempty(nb), nb = numel(e); end
assert(nb >= nRows, 'origapp:OfdmProfile', 'Reference burst shorter than the SETX map.');
P.burstSymbols = nb; P.burstSymbolsSource = sprintf('reference loop (first burst at row %d, %d active symbols)', n0, nb);
% transmitted pilot sign per payload symbol, relative to the SETX row values
pr = P.repeatIndex + 1; pc = P.ruMap(pr,:) == 1;
Hs = channelFromTraining(P, ref, n0);
pol = nan(nb, nnz(pc));
for s = P.payloadRows(1):nb
    Y = symFft(P, ref, n0, s);
    r = min(s, pr); c = P.ruMap(r,:) == 1;
    z = Y(c)./Hs(c)./P.cellValue(r, c).';
    pol(s, 1:nnz(c)) = real(z).';
end
P.pilotPolarity = sign(pol);   % +1: as SETX row, -1: inverted (per reference symbol)
P.pilotSource = "reference-verified";
P.referencePilotAgreement = mean(abs(pol(P.payloadRows(1):end,:) - sign(pol(P.payloadRows(1):end,:))), 'all');
assert(all(P.pilotPolarity(P.payloadRows(1):end,:) == 1, 'all'), 'origapp:OfdmProfile', ...
    'Reference pilots differ from the SETX PilotVals in some symbols: per-symbol pilot sequences are not implemented.');
P.pilotSource = "SETX PilotVals; verified on every reference payload symbol";
end

function H = channelFromTraining(P, x, n0)
H = zeros(numel(P.bins), 1); n = zeros(numel(P.bins), 1);
for r = P.fullPreambleRows
    Y = symFft(P, x, n0, r); c = P.ruMap(r,:) == 3;
    H(c) = H(c) + Y(c)./P.cellValue(r, c).'; n(c) = n(c) + 1;
end
H = H./max(n, 1); H(n == 0) = NaN;
end

function Y = symFft(P, x, n0, s)
a = n0 + (s-1)*P.symLen + P.fftStart;
F = fft(x(a:a+P.nr-1))*sqrt(P.nfft)/P.nr;
Y = F(P.binIdx);
end

function S = profileSummary(P)
S = struct('fftLength', P.nfft, 'cpSamples', P.ncp, 'guardInterval', P.guardInterval, ...
    'systemRateHz', P.fsys, 'receiveRateHz', P.fsRx, 'rxFftLength', P.nr, 'rxCpSamples', P.ncpr, ...
    'subcarrierSpacingHz', P.subcarrierSpacing, 'guardSubcarriers', [P.guardLower P.guardUpper], ...
    'activeSubcarriers', numel(P.bins), 'mapRows', size(P.ruMap,1), 'repeatRow0', P.repeatIndex, ...
    'resultLength', P.resultLength, 'symTimeAdjPercent', P.symTimeAdjPercent, ...
    'burstSymbols', P.burstSymbols, 'burstSymbolsSource', P.burstSymbolsSource, 'pilotSource', P.pilotSource);
r = P.repeatIndex + 1;
S.dataSubcarriers = nnz(P.ruMap(r,:) == 0); S.pilotSubcarriers = P.bins(P.ruMap(r,:) == 1);
S.payloadModulation = qamName(P.rowBits(r));
hr = setdiff(P.payloadRows, r);
S.headerModulation = strjoin(arrayfun(@(b) qamName(b), P.rowBits(hr), 'UniformOutput', false), ',');
S.preambleRows = P.preambleRows - 1; S.symbolSeconds = (P.nfft + P.ncp)/P.fsys;
end

function s = qamName(b)
names = containers.Map({1,2,4,6,8}, {'BPSK','QPSK','16QAM','64QAM','256QAM'});
s = names(b);
end
