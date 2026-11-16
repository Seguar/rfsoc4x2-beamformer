function out = phaseMismatch(rawData, referenceAnt, what)
%PHASEMISMATCH Port of vsa_rfsoc Functions/cphase.m (used by VSA_rfsoc_new's
% "Print phase missmatch" button, PAcheck, and the phase-pattern calibration).
%
%   deg = origapp.phaseMismatch(rawData, ref)            % 1-by-C degrees
%   w   = origapp.phaseMismatch(rawData, ref, "weights") % C-by-1 exp(1j*cal)
%
% Per channel, the FFT bin of largest real-ordered value (the original uses
% max() of the complex spectrum, which orders by magnitude) gives the phase;
% the result is phase(ref) - phase(ch). Only meaningful when every column is
% a measured channel carrying the same tone; zero placeholder columns are
% rejected by the caller (availableChannels guard).
arguments
    rawData (:,:) {mustBeNumeric}
    referenceAnt (1,1) double {mustBeInteger, mustBePositive} = 1
    what (1,1) string {mustBeMember(what, ["degrees","weights"])} = "degrees"
end
C = size(rawData, 2);
assert(referenceAnt <= C, 'origapp:PhaseMismatch', 'Reference channel %d > %d.', referenceAnt, C);
assert(all(isfinite(rawData), 'all') && size(rawData,1) >= 2, 'origapp:PhaseMismatch', ...
    'Phase mismatch needs finite samples.');
maxVal = zeros(C, 1);
for i = 1:C
    rawFt = fftshift(fft(rawData(:, i)));
    maxVal(i) = max(rawFt);
end
angs = angle(maxVal);
cal = angs(referenceAnt) - angs;
if what == "weights"
    out = exp(1j*cal);
else
    out = rad2deg(cal).';
end
end
