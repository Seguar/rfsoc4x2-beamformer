function act = windowActivityModel(ref, gap)
%WINDOWACTIVITYMODEL Frame-level activity of the legacy loop reference.
% A row is silent only inside a reference silent run of at least GAP rows
% (32-row smoothed power below 1 % of the active power); every other row is
% active. The legacy loop (ref125, 131072 rows) holds 4 full bursts and a
% truncated 5th; a burst is 5 OFDM frames of 5501.25 rows, each ~3000 rows
% active then ~2500 silent. The truncation falls in a silent gap (1543 rows).
if nargin < 2, gap = 256; end
ref = ref(:); N = numel(ref);
p = abs(ref).^2;
sm = conv([p(end-15:end); p; p(1:15)], ones(32,1)/32, 'valid');
sm = sm(1:N);
quiet = sm < 0.01*mean(p(p > 0.1*max(p)));
act = true(N,1);
d = diff([false; quiet; false]);
s = find(d == 1); e = find(d == -1) - 1;
for k = 1:numel(s)
    if e(k) - s(k) + 1 >= gap, act(s(k):e(k)) = false; end
end
end
