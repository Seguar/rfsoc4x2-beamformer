function [angleDeg, sequence, phaseDeg] = dacBeamSteering(mode, sequence, guiAngle, estimatedAngle, scanBw, ula, fc, phaseCorrDeg, rs)
%DACBEAMSTEERING MATLAB-side DAC (TX) steering of VSA_rfsoc_new ("DAC BF mode").
%
%   [ang, seq, ph] = origapp.dacBeamSteering(mode, seq, gui, est, scanBw, ula, fc, corr, rs)
%   mode : GUI | Random | Scaning | Rescaning | Tracking | Retracking
%   seq  : scan list (original dacTestArray), rotated for Scaning/Rescaning
%   ph   : per-element DAC phase in degrees, wrapped to [-180,180)
%
% Ported from the VSA_rfsoc_new frame loop ("%% DAC BF"). Differences:
% * Random uses the caller's RandStream (original: unseeded randi).
% * Tracking/Retracking need a current estimated angle; without one this is
%   an explicit error, never a silent reuse of an old angle.
% * Phase wrapping uses mod(...+180,360)-180. The original "indices" fold
%   mapped e.g. 200 deg to -21 deg (not 200-360); that is not reproduced.
% * The sign convention is the original's: ph = angle(steering vector) +
%   correction. It is a model command; TX steering direction has not been
%   measured on any RFSoC4x2 hardware.
arguments
    mode (1,1) string
    sequence (1,:) double
    guiAngle (1,1) double
    estimatedAngle double
    scanBw (1,1) double {mustBePositive}
    ula
    fc (1,1) double {mustBePositive}
    phaseCorrDeg (1,:) double
    rs = RandStream('twister', 'Seed', 0)
end
switch mode
    case "GUI"
        angleDeg = guiAngle;
    case "Random"
        angleDeg = randi(rs, [-scanBw/2, scanBw/2], 1);
    case "Scaning"
        angleDeg = sequence(1); sequence = [sequence(2:end) sequence(1)];
    case "Rescaning"
        angleDeg = sequence(1); sequence = [sequence(end) sequence(1:end-1)];
    case {"Tracking", "Retracking"}
        assert(~isempty(estimatedAngle) && isfinite(estimatedAngle(1)), 'origapp:DacBf', ...
            '%s DAC BF needs a current estimated DOA (array mode with measured channels).', mode);
        angleDeg = estimatedAngle(1);
        if mode == "Retracking", angleDeg = -angleDeg; end
    otherwise
        error('origapp:DacBf', 'Unknown DAC BF mode "%s".', mode);
end
sv = phased.SteeringVector('SensorArray', ula);
w = sv(fc, angleDeg);
n = numel(w);
assert(numel(phaseCorrDeg) == n, 'origapp:DacBf', ...
    'DAC phase correction has %d entries; array has %d elements.', numel(phaseCorrDeg), n);
phaseDeg = round(rad2deg(angle(w)).', 2) + phaseCorrDeg;
phaseDeg = mod(phaseDeg + 180, 360) - 180;
end
