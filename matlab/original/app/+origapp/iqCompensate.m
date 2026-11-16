function [x, filt] = iqCompensate(x, filt, mode, mu)
%IQCOMPENSATE Per-channel receive IQ-imbalance compensation ported from
% VSA_rfsoc_new (vsa_rfsoc HEAD 2d8610a, rfsocBf.m + Functions/adaptiveIQCompensation.m).
%
%   [x, filt] = origapp.iqCompensate(x, filt, mode, mu)
%   x    : N-by-C complex samples (columns = channels), original I - jQ wire form
%   filt : L-by-C complex image-cancelling filter state (one column per channel)
%   mode : "adaptive" - update filt by the original LMS recursion, output y
%          "static"   - apply y = x + conv(conj(x), filt, 'same') (frozen filter)
%   mu   : LMS step (original 'MU step'; the original uses M = mu*eye(L))
%
% The adaptive recursion is the original one, sample by sample:
%   y(n) = x(n) + w.' * conj(x(n:-1:n-L+1)),  w <- w - mu * y(n:-1:n-L+1).' * y(n)
% The first L-1 output samples of each adaptive block are zero, as in the
% original. HEAD applies adaptive then static when both flags are set; the
% caller (processLegacyFrame) keeps that order. This is a receiver-side model
% correction; it is never applied to the direct native-VSA feed.
arguments
    x {mustBeNumeric}
    filt {mustBeNumeric}
    mode (1,1) string {mustBeMember(mode, ["adaptive","static"])}
    mu (1,1) double {mustBeNonnegative} = 0
end
C = size(x, 2);
assert(size(filt, 2) == C && size(filt, 1) >= 1, 'origapp:IqComp', ...
    'IQ filter must be L-by-%d; got %d-by-%d.', C, size(filt,1), size(filt,2));
assert(all(isfinite(x), 'all') && all(isfinite(filt), 'all'), 'origapp:IqComp', ...
    'IQ compensation needs finite samples and filter state.');
L = size(filt, 1);
assert(size(x, 1) > L, 'origapp:IqComp', 'Frame shorter than the IQ filter length %d.', L);
switch mode
    case "static"
        for c = 1:C
            x(:, c) = x(:, c) + conv(conj(x(:, c)), filt(:, c), 'same');
        end
    case "adaptive"
        for c = 1:C
            [x(:, c), filt(:, c)] = adaptiveColumn(x(:, c), filt(:, c), mu);
        end
        assert(all(isfinite(filt), 'all'), 'origapp:IqComp', ...
            'Adaptive IQ filter diverged (reduce MU step).');
end
end

function [y, w] = adaptiveColumn(x, w, mu)
N = numel(w);
y = zeros(size(x));
for n = N:numel(x)
    xv = x(n:-1:n-N+1);
    y(n) = x(n) + w.' * conj(xv);
    w = w - mu * (y(n:-1:n-N+1) * y(n));
end
end
