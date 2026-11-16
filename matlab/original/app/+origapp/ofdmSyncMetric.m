function [rho, frac] = ofdmSyncMetric(x, t, nFrac)
%OFDMSYNCMETRIC Normalised cross-correlation of x with the known preamble t.
%   rho(n) = max over fractional delays d of
%            |sum_m x(n+m-1) conj(t_d(m))| / sqrt(Ex(n) * Et), n = 1..numel(x)-numel(t)+1
% t_d is t delayed by d = 0, 1/nFrac, ... samples (exact band-limited shift in
% the frequency domain; default nFrac = 4). Without it a burst whose start
% falls half-way between samples (the legacy 5501.25-row burst period) reads
% only ~0.82 on an ideal signal. frac(n) is the best d. rho is in [0, 1] by
% Cauchy-Schwarz. Windows whose energy is below 1e-6 of the strongest window
% (silence, zeros) are masked to 0: there the FFT round-off residual of the
% numerator would otherwise give rho > 1 and false peaks.
if nargin < 3, nFrac = 4; end
x = x(:); t = t(:); N = numel(x); L = numel(t);
assert(N >= L, 'origapp:Ofdm', 'Buffer shorter than the preamble template.');
nf = 2^nextpow2(N + L - 1);
X = fft(x, nf);
e = cumsum([0; abs(x).^2]);
Ex = e(L+1:end) - e(1:end-L);
Et = sum(abs(t).^2);
floorE = max(1e-6*max(Ex), realmin);
ok = Ex > floorE;
rho = zeros(N-L+1, 1); frac = zeros(N-L+1, 1);
T = fft(t);
w = [0:ceil(L/2)-1, -floor(L/2):-1].'/L;
for q = 0:nFrac-1
    d = q/nFrac;
    td = ifft(T.*exp(-1j*2*pi*w*d));
    c = ifft(X .* conj(fft(td, nf)));
    r = zeros(N-L+1, 1);
    r(ok) = min(abs(c(ok))./sqrt(Ex(ok)*Et), 1);
    better = r > rho; rho(better) = r(better); frac(better) = d;
end
end
