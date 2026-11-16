function A = windowIntegrity(z, ref, refFftConj, burst, act)
%WINDOWINTEGRITY Host check that one received window is a single contiguous
% pass of the legacy loop (no loop wrap, no sample loss beyond ~100 ppm
% one-row advances). Independent of the board selector and of VSA; never
% uses EVM.  z: window rows of one stream in the reference sense (I + jQ).
%
% Measured reference structure (ref125): 4 full bursts + a truncated 5th; a
% burst is 5 OFDM frames (5501.25 rows: ~3000 active, ~2500 silent). Frames
% inside a burst differ (correlation ~0.1); whole bursts repeat (~0.95 at the
% best integer lag). At the loop wrap the truncated burst's frame 4 is
% followed, after a shortened 1543-row gap, by burst 1 frame 1: the burst
% phase jumps. A sample loss also shifts it.
%
% Model: ONE continuous burst phase phi(r) = phi0 + r + lag(r) for the whole
% window. Every predicted-active run is checked in <=256-row chunks (plus
% 32/16-row edge chunks) by normalised correlation with the reference at
% the tracked lag (+-2 rows per chunk, +-4 across a silent gap; best of the
% 4 burst labels, i.e.
% quarter-row offsets); every predicted-silent row (16-row guard at
% transitions) must be silent; the lag spread must stay <= 8 rows (slips).
% Edge rules (fail closed where the data cannot show a wrap): a window that
% starts within the truncated-gap length before a burst start, or ends
% within 16 rows after the truncation phase, is refused; an active run
% shorter than 64 rows at an edge cannot be verified and is refused.
% Three anchors (centre, first, last 8192 rows) are tried; the window passes
% only if one continuous-phase hypothesis explains every active and silent
% row. Resolution limit: a jump within the outermost ~8 active rows, or a
% jump wholly inside a silent prefix/suffix (no active sample affected),
% cannot be seen.
t0 = tic;
z = z(:); ref = ref(:); n = numel(z);
assert(n >= 16384 && numel(ref) == numel(act), 'origapp:Integrity', 'window/reference size');
anchors = [n/2 - 4096, 0, n - 8192];
first = [];
for a0 = anchors
    A = check1(z, ref, refFftConj, burst, act, a0);
    if isempty(first), first = A; end
    if A.ok, break; end
end
if ~A.ok, A = first; end
A.anchorsTried = find(anchors == a0, 1);
A.elapsedS = toc(t0);
end

function A = check1(z, ref, RFc, B, act, mid)
CH = 256; STEP = 2; STEP_GAP = 4; SPREAD = 8; MINRUN = 64; GUARD = 16; TRUNC_GAP = 1543;
CORR_MIN = 0.60; SIL_MAX = 0.05; EN = 16; EDGE = 32;
N = numel(ref); n = numel(z); tail = N - 4*B;
labels = floor((0:3)*B + 0.5);
% coarse alignment on rows mid..mid+8191 (row r <-> loop index r - k)
x = zeros(N,1); r8 = (mid:mid+8191).'; x(r8+1) = z(r8+1);
c = abs(ifft(fft(x) .* RFc));
[pk, k] = max(c); k = k - 1;
rr = ref(mod(r8 - k, N) + 1);
lk = pk / (norm(x)*norm(rr) + 1e-30);
A = struct('ok', false, 'reason', "", 'fails', strings(0,1), 'lock', lk, 'lagSpread', NaN, ...
    'minCorr', NaN, 'nChunks', 0, 'startPhase', NaN, 'endPhase', NaN, 'anchorsTried', 0, 'elapsedS', 0);
if lk < 0.3
    A.fails = "no reference lock " + sprintf('%.2f', lk); A.reason = A.fails; return
end
rc = mid + 4096;
phi0 = mod(mod(rc - k, N), B) - rc;          % burst phase of row r = phi0 + r + lag (mod B)
rows = (0:n-1).';
pm = act(floor(mod(phi0 + rows, B)) + 1);    % predicted activity (anchor lag)
ed = find(diff(pm)) ;                        % last row (1-based) of each run but the final
st = [0; ed]; en = [ed; n];                  % runs [st, en) 0-based
pwr = abs(z).^2;
pa = median(pwr(pm)); if isempty(pa) || isnan(pa), pa = 0; end
fails = strings(0,1);
chunks = zeros(0,2);
for q = 1:numel(st)
    a = st(q); b = en(q);
    if pm(a+1)
        if b - a < MINRUN
            if a == 0 || b == n, w = "short-edge-active-run"; else, w = "short-active-run"; end
            fails(end+1) = sprintf('%s at %d (%d rows)', w, a, b - a); %#ok<AGROW>
            continue
        end
        s = a;
        while s < b
            e = min(b, s + CH);
            if b - e < CH/2, e = b; end
            chunks(end+1,:) = [s e]; %#ok<AGROW>
            s = e;
        end
        for E = [EDGE, EDGE/2]                   % edge micro-chunks
            if a == 0, chunks(end+1,:) = [0 E]; end %#ok<AGROW>
            if b == n, chunks(end+1,:) = [n-E n]; end %#ok<AGROW>
        end
    else
        a0 = a + GUARD; if a == 0, a0 = 0; end
        a1 = b - GUARD; if b == n, a1 = n; end
        cs = a0:EN:(a1 - EN);
        if a1 - a0 >= 4, cs(end+1) = max(a0, a1 - EN); end %#ok<AGROW>
        for s = cs
            e = min(a1, s + EN);
            v = mean(pwr(s+1:e));
            if v > SIL_MAX*pa
                fails(end+1) = sprintf('energy in predicted silence at %d (%.3f of active)', s, v/pa); %#ok<AGROW>
                break
            end
        end
        if b == n && a1 - a0 >= 4 && mean(pwr(n-3:n)) > SIL_MAX*pa
            fails(end+1) = sprintf('energy in predicted silence at %d (tail)', n - 4); %#ok<AGROW>
        end
    end
end
nc = size(chunks,1);
cv = nan(nc,1); cl = zeros(nc,1); done = false(nc,1);
main = find(chunks(:,2) - chunks(:,1) > EDGE);
if ~isempty(main)
    [~, o] = sort(chunks(main,1)); order = main(o);
    [~, c0] = min(abs(chunks(order,1) - (mid + 4096)));
    % track outward from the anchor chunk; +-STEP_GAP only across a silent gap
    lag = 0; prev = 0;
    for i = order(c0:end).'
        st = STEP;
        if prev && chunks(i,1) ~= chunks(prev,2) && chunks(i,2) ~= chunks(prev,1), st = STEP_GAP; end
        [cv(i), cl(i)] = corrChunk(z, ref, phi0, B, labels, st, chunks(i,1), chunks(i,2), lag); done(i) = true;
        if cv(i) >= CORR_MIN, lag = cl(i); end
        prev = i;
    end
    lag = cl(order(c0)); prev = order(c0);
    for i = flip(order(1:c0-1)).'
        st = STEP;
        if chunks(i,1) ~= chunks(prev,2) && chunks(i,2) ~= chunks(prev,1), st = STEP_GAP; end
        [cv(i), cl(i)] = corrChunk(z, ref, phi0, B, labels, st, chunks(i,1), chunks(i,2), lag); done(i) = true;
        if cv(i) >= CORR_MIN, lag = cl(i); end
        prev = i;
    end
    lagFirst = cl(order(1)); lagLast = cl(order(end));
else
    lagFirst = 0; lagLast = 0;
end
for i = find(~done).'
    if chunks(i,1) == 0, l0 = lagFirst; else, l0 = lagLast; end
    [cv(i), cl(i)] = corrChunk(z, ref, phi0, B, labels, STEP, chunks(i,1), chunks(i,2), l0);
end
good = cl(cv >= CORR_MIN);
[~, o] = sort(chunks(:,1));
for i = o(cv(o) < CORR_MIN).'
    fails(end+1) = sprintf('active mismatch at %d (%d rows, corr %.3f)', chunks(i,1), ...
        chunks(i,2) - chunks(i,1), cv(i)); %#ok<AGROW>
end
spread = 0; if ~isempty(good), spread = max(good) - min(good); end
if spread > SPREAD, fails(end+1) = sprintf('lag spread %d rows', spread); end
if isempty(main), fails(end+1) = "no active rows"; end
ps = mod(phi0 + lagFirst, B);
pe = mod(phi0 + n - 1 + lagLast, B);
if ps > B - (TRUNC_GAP + GUARD) || ps < GUARD
    fails(end+1) = sprintf('leading silent gap may hide a wrap (start phase %.1f)', ps);
end
if pe >= tail - GUARD && pe < tail + GUARD
    fails(end+1) = sprintf('window ends at the truncation phase (%.1f)', pe);
end
A.ok = isempty(fails); A.fails = fails(:);
if A.ok, A.reason = "ok"; else, A.reason = strjoin(fails(1:min(3,end)), '; '); end
A.lagSpread = spread; A.nChunks = nc; A.startPhase = ps; A.endPhase = pe;
if nc, A.minCorr = min(cv); end

end

function [best, bl] = corrChunk(z, ref, phi0, B, labels, step, s, e, lag0)
% Best normalised correlation of rows s..e-1 with the reference over lags
% lag0-step..lag0+step and the 4 burst labels (first max: lag-major).
N = numel(ref);
seg = z(s+1:e); ns = norm(seg) + 1e-30;
ds = lag0-step:lag0+step;
V = zeros(numel(labels), numel(ds));
for j = 1:numel(ds)
    ph = floor(mod(phi0 + (s:e-1).' + ds(j), B));
    R = ref(mod(ph + labels, N) + 1);              % rows x 4 burst labels
    V(:,j) = abs(R' * seg) ./ (vecnorm(R).' * ns + 1e-30);
end
[best, k] = max(V(:));
bl = ds(ceil(k/numel(labels)));
end
