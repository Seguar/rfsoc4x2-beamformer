function [interleaved, info] = prepareDacWaveform(source, opts)
%PREPAREDACWAVEFORM Custom DAC-file preparation for the RFSoC4x2 original app.
% Port of vsa_rfsoc Functions/sigPrepare.m (the original custom DAC-file
% loader; its LoadSignal buttons were never wired in VSA_rfsoc or
% VSA_rfsoc_new) with explicit RFSoC4x2 constraints.
%
%   [i16, info] = origapp.prepareDacWaveform(source, opts)
%   source : .mat file with complex Y (and optional XDelta, as saved by VSA)
%            or a complex column vector
%   opts.fsOrig   : source sample rate (Hz); XDelta in the file overrides it
%   opts.fsDac    : DAC input sample rate (Hz)
%   opts.resample : true -> resample fsOrig -> fsDac (original Resample box)
%   opts.filter   : true -> band-limit to opts.bwDac with the original filtSig
%   opts.bwDac    : filter bandwidth (Hz)
%   opts.peakCode : integer peak per I/Q rail after scaling (AGENTS: start low, 1200)
%   opts.ramComplex : DAC RAM capacity in complex samples (backend/config value)
%
% Output: int16 column [I1;Q1;I2;Q2;...] with the TX convention I + jQ
% (sigPrepare order). info carries lengths, period count, peak and SHA-256
% of the little-endian bytes. Preparation performs no I/O to any board; the
% upload is a separate backend capability.
arguments
    source
    opts.fsOrig (1,1) double {mustBePositive} = 60e6
    opts.fsDac (1,1) double {mustBePositive} = 500e6
    opts.resample (1,1) logical = false
    opts.filter (1,1) logical = false
    opts.bwDac (1,1) double {mustBePositive} = 499e6
    opts.peakCode (1,1) double {mustBeInteger, mustBePositive, mustBeLessThanOrEqual(opts.peakCode, 1200)} = 1200
    opts.ramComplex (1,1) double {mustBeInteger, mustBePositive} = 524288
end
fsOrig = opts.fsOrig; origin = "vector";
if ischar(source) || isstring(source)
    S = load(char(source));
    assert(isfield(S, 'Y'), 'origapp:DacFile', 'DAC file must contain Y (complex samples).');
    Y = S.Y;
    if isfield(S, 'XDelta'), fsOrig = 1/S.XDelta; end
    origin = string(source);
else
    Y = source;
end
assert(isnumeric(Y) && isvector(Y) && numel(Y) >= 16 && all(isfinite(Y)), 'origapp:DacFile', ...
    'DAC samples must be a finite vector with at least 16 samples.');
Y = double(Y(:));
if opts.resample
    [p, q] = rat(opts.fsDac/fsOrig, 1e-9);
    Y = resample(Y, p, q);
    fsOut = opts.fsDac;
else
    assert(abs(fsOrig - opts.fsDac) <= 1e-6*opts.fsDac, 'origapp:DacFile', ...
        ['Source rate %.6g Hz differs from DAC rate %.6g Hz; enable Resample ' ...
        '(original sigPrepare always resampled).'], fsOrig, opts.fsDac);
    fsOut = fsOrig;
end
if opts.filter
    assert(opts.bwDac < opts.fsDac, 'origapp:DacFile', 'Filter bandwidth must be below fsDac.');
    Y = filtSig(Y, opts.fsDac, opts.bwDac);
end
n = numel(Y);
assert(n <= opts.ramComplex && mod(opts.ramComplex, n) == 0, 'origapp:DacFile', ...
    ['%d complex samples do not tile the %d-sample DAC RAM exactly; a partial ' ...
    'period would create a discontinuity at the RAM loop boundary.'], n, opts.ramComplex);
pk = max(abs([real(Y); imag(Y)]));
assert(pk > 0, 'origapp:DacFile', 'DAC waveform is all zeros.');
Y = Y/pk*opts.peakCode;
interleaved = zeros(2*n, 1);
interleaved(1:2:end) = real(Y);
interleaved(2:2:end) = imag(Y);
interleaved = int16(round(interleaved));
bytes = typecast(interleaved, 'uint8');   % little-endian on supported hosts
md = java.security.MessageDigest.getInstance('SHA-256');
h = typecast(md.digest(bytes), 'uint8');
info = struct('origin', origin, 'complexSamples', n, 'periodsInRam', opts.ramComplex/n, ...
    'fsHz', fsOut, 'sourceFsHz', fsOrig, 'resampled', opts.resample, 'filtered', opts.filter, ...
    'peakCode', double(max(abs(interleaved))), 'convention', "I + jQ interleaved int16", ...
    'sha256', string(lower(reshape(dec2hex(h, 2).', 1, []))));
end
