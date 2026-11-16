function R = ofdmAnalyze(x, P, opt)
%OFDMANALYZE Integrated Custom OFDM demodulation of one buffer (no vendor code).
%   R = origapp.ofdmAnalyze(x, P, opt)
%   x   complex column at P.fsRx (the same buffer the app would feed native VSA)
%   P   origapp.ofdmProfile (parameters read from the matched SETX)
%   opt.syncThreshold   own preamble correlation threshold (required, explicit;
%                       this is NOT the vendor 0.9 sync quantity)
%   opt.fullScale       amplitude that is 0 dBFS for the RX level (default 32767/2^16)
%   opt.maxBursts       bursts analysed per buffer (default Inf)
%
% Algorithm (training- and pilot-aided only; the evaluation payload never
% sets gain, phase, timing or channel):
%  1 sync: normalised correlation with the SETX preamble (energy masked);
%    candidates are local maxima >= syncThreshold, one per burst length;
%    every candidate and its decision is returned (R.candidates).
%  2 per burst: CFO from the two full training rows (each divided by its OWN
%    SETX row values), de-rotation, channel H = mean of the training rows.
%  3 per payload symbol: E = Y/H; pilots (SETX values, verified on the
%    reference) give common phase, timing slope across subcarriers and
%    amplitude; a step of the timing slope between symbols >= half a sample
%    is a sample slip/jump: that burst is unqualified, but remains in primary EVM.
%  4 Primary EVM includes EVERY complete detected burst, including unqualified
%    timing-slip/training bursts. Qualified-only EVM is a labelled secondary metric.
%    EVM: decisions on the unit-RMS ideal constellation of each row's QAM
%    order (SETX), rms error over data cells / rms ideal (= 1). Header (BPSK)
%    and payload (16QAM) separate. Per symbol and per subcarrier too.
% Nothing is zero-filled, repeated or tiled; a burst not entirely inside the
% buffer is refused, never padded.
if nargin < 3, opt = struct(); end
assert(isfield(opt, 'syncThreshold') && isscalar(opt.syncThreshold) && opt.syncThreshold > 0 && ...
    opt.syncThreshold < 1, 'origapp:Ofdm', 'opt.syncThreshold (own sync metric, 0..1) must be explicit.');
d = struct('fullScale', 32767/65536, 'maxBursts', Inf, 'spectrumFft', 256);
f = fieldnames(d);
for k = 1:numel(f), if ~isfield(opt, f{k}), opt.(f{k}) = d.(f{k}); end, end
t0 = tic;
x = x(:);
assert(isnumeric(x) && ~isempty(x) && all(isfinite(x)), 'origapp:Ofdm', 'Buffer must be finite and nonempty.');
R = emptyResult(P, opt);
R.samples = numel(x);
R.rxLevelDbfs = 10*log10(mean(abs(x).^2)/opt.fullScale^2 + realmin);
R.peakDbfs = 20*log10(max(abs(x))/opt.fullScale + realmin);
R.spectrum = spectrumOf(x, P.fsRx, opt.spectrumFft, opt.fullScale);
burstLen = P.burstSymbols*P.symLen;
if numel(x) < numel(P.preambleTemplate)
    R.state = "NO SYNC"; R.reason = "buffer shorter than the preamble"; R.elapsedS = toc(t0); return
end
rho = origapp.ofdmSyncMetric(x, P.preambleTemplate);
R.syncPeak = max(rho);
% candidate peaks: greedy maxima separated by one burst length
cand = zeros(0, 2); r2 = rho;
while true
    [pk, n] = max(r2);
    if pk < opt.syncThreshold, break; end
    cand(end+1, :) = [n pk]; %#ok<AGROW>
    r2(max(1, n-burstLen+1):min(numel(r2), n+burstLen-1)) = 0;
end
cand = sortrows(cand, 1);
C = struct('start', {}, 'sync', {}, 'accepted', {}, 'reason', {});
B = {}; allB = {};
for i = 1:size(cand, 1)
    n0 = cand(i, 1); c = struct('start', n0, 'sync', cand(i, 2), 'accepted', false, 'reason', "");
    if numel(allB) >= opt.maxBursts
        c.reason = "not analysed (maxBursts)";
    elseif n0 + burstLen - 1 > numel(x)
        c.reason = sprintf('incomplete burst: needs %d rows, %d left in buffer', burstLen, numel(x) - n0 + 1);
    else
        [b, why] = demodBurst(x(n0:n0+burstLen-1), P);
        b.start = n0; b.sync = cand(i, 2);
        allB{end+1} = b;  % every complete detected burst contributes to primary EVM
        if strlength(why) == 0
            B{end+1} = b; c.accepted = true; c.reason = "ok"; %#ok<AGROW>
        else
            c.reason = why;
        end
    end
    C(end+1) = c; %#ok<AGROW>
end
R.candidates = C;
if ~isempty(allB), R = aggregate(R,allB,P); end
R.metricBursts = numel(allB); R.qualifiedBursts = numel(B); R.bursts = numel(B);
R.refusedCompleteBursts = numel(allB)-numel(B); R.degraded = R.refusedCompleteBursts>0;
if isempty(cand)
    R.state = "NO SYNC";
    R.reason = sprintf('no preamble correlation >= %.2f (peak %.3f)', opt.syncThreshold, R.syncPeak);
elseif isempty(B)
    R.state = "REFUSED";
    R.reason = "all " + numel(C) + " synced bursts refused: " + strjoin(unique([C.reason]), "; ");
else
    q = aggregate(emptyResult(P,opt), B, P);
    R.qualifiedPayloadEvmPercent = q.evmPercent;
    R.degraded = R.refusedCompleteBursts > 0;
    R.state = "LOCKED";
    R.reason = sprintf('%d/%d complete bursts qualified; primary EVM includes all %d complete bursts', ...
        numel(B), numel(allB), numel(allB));
    if ~isfinite(R.evmPercent)
        R.state = "REFUSED"; R.reason = "some complete bursts cannot yield finite error; no partial primary EVM";
    end
end
R.valid = R.state == "LOCKED";
R.elapsedS = toc(t0);
end

function R = emptyResult(P, opt)
R = struct('analyzer', "Integrated Custom OFDM (MATLAB, training+pilot aided)", ...
    'profile', P.summary, 'syncThreshold', opt.syncThreshold, 'state', "", 'reason', "", 'valid', false, ...
    'metricBursts', 0, 'qualifiedBursts', 0, 'refusedCompleteBursts', 0, 'degraded', false, ...
    'evmScope', "all complete detected payload bursts; timing-slip and inconsistent-training bursts included", ...
    'qualifiedPayloadEvmPercent', NaN, 'samples', 0, 'rxLevelDbfs', NaN, 'peakDbfs', NaN, 'syncPeak', NaN, 'candidates', struct([]), ...
    'bursts', 0, 'evmPercent', NaN, 'evmDb', NaN, 'headerEvmPercent', NaN, 'headerEvmDb', NaN, ...
    'evmPercentMax', NaN, 'evmPerSymbolPercent', [], 'evmPerSubcarrierPercent', [], ...
    'cfoHz', [], 'commonPhaseDeg', [], 'timingSlopeSamples', [], 'samplingErrorPpm', NaN, ...
    'timingOffsetSamples', [], 'trainingSnrDb', [], 'pilotEvmPercent', NaN, ...
    'setxIntervalEvmPercent', NaN, 'constellation', struct('payload', [], 'header', [], 'pilot', []), ...
    'spectrum', struct(), 'elapsedS', NaN, 'perBurst', struct([]));
end

function [b, why] = demodBurst(xb, P)
why = "";
b = struct();
tr = P.fullPreambleRows; nr = P.nr; fs = P.fsRx;
% CFO from consecutive full training rows, each divided by its own values
Z = cell(1, numel(tr));
for q = 1:numel(tr)
    Y = symFft(P, xb, tr(q)); c = P.ruMap(tr(q),:) == 3;
    z = nan(numel(P.bins), 1); z(c) = Y(c)./P.cellValue(tr(q), c).'; Z{q} = z;
end
cfo = 0;
if numel(tr) >= 2
    acc = 0;
    for q = 2:numel(tr)
        ok = ~isnan(Z{q}) & ~isnan(Z{q-1});
        acc = acc + sum(Z{q}(ok).*conj(Z{q-1}(ok)))/((tr(q)-tr(q-1)));
    end
    cfo = angle(acc)/(2*pi*P.symLen/fs);
end
n = (0:numel(xb)-1).';
xb = xb.*exp(-1j*2*pi*cfo*n/fs);
H = zeros(numel(P.bins), 1); cnt = zeros(numel(P.bins), 1); Zc = cell(1, numel(tr));
for q = 1:numel(tr)
    Y = symFft(P, xb, tr(q)); c = (P.ruMap(tr(q),:) == 3).';
    z = nan(numel(P.bins), 1); z(c) = Y(c)./P.cellValue(tr(q), c).'; Zc{q} = z;
    H(c) = H(c) + z(c); cnt(c) = cnt(c) + 1;
end
H = H./max(cnt, 1); H(cnt == 0) = NaN;
% training consistency and SNR (difference of the training rows)
snr = NaN; cons = 1;
if numel(tr) >= 2
    ok = ~isnan(Zc{1}) & ~isnan(Zc{2});
    dz = Zc{2}(ok) - Zc{1}(ok);
    sp = mean(abs(H(ok)).^2); np = mean(abs(dz).^2)/2;
    snr = 10*log10(sp/np);
    cons = abs(sum(Zc{2}(ok).*conj(Zc{1}(ok))))/sqrt(sum(abs(Zc{2}(ok)).^2)*sum(abs(Zc{1}(ok)).^2));
end
% A one-sample slip between or inside the training rows gives a
% consistency of ~0.4-0.9 (phase ramp of 2*pi*k/Nr across the occupied
% band); noise alone keeps it above 0.95 down to ~10 dB SNR.
if cons < 0.95
    why = sprintf('training rows inconsistent (corr %.3f < 0.95: sample slip in the preamble or interference)', cons);
end
% fractional timing from the channel phase slope (relative to FFT start)
okh = ~isnan(H);
ph = unwrap(angle(H(okh))); k = P.bins(okh).';
pf = [k ones(size(k))] \ ph;
timingOffset = -pf(1)*nr/(2*pi) + (P.fftStart - P.ncpr);   % 0 = burst starts at the sync sample
% payload symbols
pr = P.repeatIndex + 1;
nsym = P.burstSymbols;
first = P.payloadRows(1);
syms = first:nsym;
ns = numel(syms);
cpe = nan(ns,1); slope = nan(ns,1); amp = nan(ns,1);
evSym = nan(ns,1);
errC = cell(ns,1); idealC = cell(ns,1); eqC = cell(ns,1); binC = cell(ns,1); rowB = nan(ns,1);
pilC = cell(ns,1);
for q = 1:ns
    s = syms(q); r = min(s, pr);
    Y = symFft(P, xb, s); E = Y./H;
    pc = (P.ruMap(r,:) == 1).'; dc = (P.ruMap(r,:) == 0).';
    zp = E(pc)./P.cellValue(r, pc).'; kp = P.bins(pc).';
    phi = angle(sum(zp));
    th = angle(zp*exp(-1j*phi));
    A = [kp ones(size(kp))]; fp = A \ th;
    corr = exp(-1j*(phi + fp(2) + fp(1)*P.bins.'));
    a = mean(abs(zp));
    if ~P.vendor.trackAmplitude, a = 1; end
    D = E.*corr/a;
    cpe(q) = phi + fp(2); slope(q) = fp(1); amp(q) = a;
    bits = P.rowBits(r);
    [ideal, ~] = qamDecide(D(dc), bits);
    e = D(dc) - ideal;
    errC{q} = e; idealC{q} = ideal; eqC{q} = D(dc); binC{q} = P.bins(dc).'; rowB(q) = bits;
    pilC{q} = D(pc)./P.cellValue(r, pc).';
    evSym(q) = 100*sqrt(mean(abs(e).^2));
end
% sample slip / jump: step of the pilot timing slope between symbols, and
% between the training (H, timing 0 by construction) and the first payload symbol
dts = diff([0; slope])*nr/(2*pi);
jmp = find(abs(dts) >= 0.5, 1);
if ~isempty(jmp)
    previousReason = why;
    if jmp == 1
        why = sprintf('pilot timing step %.2f samples between training and symbol %d (sample slip/jump)', dts(1), syms(1)-1);
    else
        why = sprintf('pilot timing step %.2f samples between payload symbols %d and %d (sample slip/jump)', ...
            dts(jmp), syms(jmp-1)-1, syms(jmp)-1);
    end
    if strlength(previousReason)>0, why = previousReason + "; " + why; end
end
tau = slope*nr/(2*pi);   % samples
pfit = polyfit((0:ns-1).', tau, 1);
b.cfoHz = cfo; b.H = H; b.trainingSnrDb = snr; b.trainingConsistency = cons;
b.timingOffsetSamples = timingOffset;
b.symbols = syms - 1; b.cpeDeg = rad2deg(cpe); b.timingSlopeSamples = tau; b.amplitude = amp;
b.samplingErrorPpm = -pfit(1)/P.symLen*1e6;
b.qualified = strlength(why)==0; b.rejectionReason=why;
b.evmSym = evSym; b.err = errC; b.ideal = idealC; b.eq = eqC; b.bin = binC; b.bits = rowB; b.pilot = pilC;
end

function Y = symFft(P, x, s)
a = (s-1)*P.symLen + P.fftStart + 1;
F = fft(x(a:a+P.nr-1))*sqrt(P.nfft)/P.nr;
Y = F(P.binIdx);
end

function [ideal, idx] = qamDecide(z, bits)
if bits == 1
    ideal = sign(real(z)); ideal(ideal == 0) = 1; idx = (ideal > 0); return
end
m = sqrt(2^bits); assert(m == fix(m), 'origapp:Ofdm', 'Only square QAM is implemented.');
lev = (-(m-1):2:(m-1)); sc = sqrt(2*(2^bits - 1)/3);
q = @(v) lev(min(max(round((v*sc + (m-1))/2) + 1, 1), m));
ri = q(real(z)); ii = q(imag(z));
ideal = (ri(:) + 1j*ii(:))/sc; idx = [];
end

function R = aggregate(R, B, P)
pr = P.repeatIndex + 1;
pay = []; hdr = []; pil = []; payBin = []; evS = []; pb = struct([]);
for i = 1:numel(B)
    b = B{i};
    for q = 1:numel(b.err)
        s = b.symbols(q) + 1;
        if min(s, pr) == pr
            pay = [pay; b.err{q}]; payBin = [payBin; b.bin{q}]; %#ok<AGROW>
            R.constellation.payload = [R.constellation.payload; b.eq{q}];
        else
            hdr = [hdr; b.err{q}]; %#ok<AGROW>
            R.constellation.header = [R.constellation.header; b.eq{q}];
        end
        pil = [pil; b.pilot{q}]; %#ok<AGROW>
    end
    evS = [evS, b.evmSym(:)]; %#ok<AGROW>
    e = struct('start', b.start, 'sync', b.sync, 'cfoHz', b.cfoHz, 'trainingSnrDb', b.trainingSnrDb, ...
        'trainingConsistency', b.trainingConsistency, 'timingOffsetSamples', b.timingOffsetSamples, ...
        'samplingErrorPpm', b.samplingErrorPpm, 'qualified', b.qualified, 'rejectionReason', b.rejectionReason, 'evmPercent', 100*sqrt(mean(abs(vertcat(b.err{min(b.symbols+1,pr)==pr})).^2)), ...
        'headerEvmPercent', 100*sqrt(mean(abs(vertcat(b.err{min(b.symbols+1,pr)~=pr})).^2)), ...
        'cpeDegRms', sqrt(mean(b.cpeDeg.^2)), 'timingDriftSamples', b.timingSlopeSamples(end) - b.timingSlopeSamples(1));
    if isempty(pb), pb = e; else, pb(end+1) = e; end %#ok<AGROW>
end
R.perBurst = pb; R.bursts = numel(B);
R.constellation.pilot = pil;
R.evmPercent = 100*sqrt(mean(abs(pay).^2)); R.evmDb = 20*log10(R.evmPercent/100);
R.headerEvmPercent = 100*sqrt(mean(abs(hdr).^2)); R.headerEvmDb = 20*log10(R.headerEvmPercent/100);
R.evmPercentMax = max([pb.evmPercent]);
R.pilotEvmPercent = 100*sqrt(mean(abs(pil - 1).^2));
R.evmPerSymbolPercent = sqrt(mean(evS.^2, 2)).';      % rms over bursts, per payload symbol
R.evmSymbolIndex = B{1}.symbols;
ub = unique(payBin).';
R.evmSubcarrier = ub;
R.evmPerSubcarrierPercent = arrayfun(@(k) 100*sqrt(mean(abs(pay(payBin == k)).^2)), ub);
R.cfoHz = [pb.cfoHz]; R.trainingSnrDb = [pb.trainingSnrDb];
R.timingOffsetSamples = [pb.timingOffsetSamples];
R.samplingErrorPpm = median([pb.samplingErrorPpm]);
R.commonPhaseDeg = cell2mat(cellfun(@(b) b.cpeDeg(:), B, 'UniformOutput', false));
R.timingSlopeSamples = cell2mat(cellfun(@(b) b.timingSlopeSamples(:), B, 'UniformOutput', false));
% SETX result-length interval of the FIRST burst (interpretation: ResLen
% counts map rows incl. preamble, as VSA demodulates from the burst start)
b = B{1}; sel = (b.symbols + 1) <= P.resultLength & min(b.symbols + 1, pr) == pr;
if any(sel), R.setxIntervalEvmPercent = 100*sqrt(mean(abs(vertcat(b.err{sel})).^2)); end
end

function S = spectrumOf(x, fs, nfft, fullScale)
nseg = floor(numel(x)/nfft);
w = 0.5 - 0.5*cos(2*pi*(0:nfft-1).'/nfft);
X = reshape(x(1:nseg*nfft), nfft, nseg).*w;
p = mean(abs(fft(X)).^2, 2)/sum(w.^2);
p = fftshift(p);
S = struct('freqHz', ((-nfft/2:nfft/2-1)*fs/nfft).', 'psdDbfs', 10*log10(p/(fullScale^2) + realmin), ...
    'note', sprintf('Hann %d-pt, %d segments, dB rel. full scale per bin', nfft, nseg));
end
