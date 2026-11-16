function cal = angleCalibration(meas_mat, cal_angles, interp_res, ula, fc, c, couplingIterations)
%ANGLECALIBRATION Figure-free port of the VSA_rfsoc_new angle-calibration
% chain (vsa_rfsoc HEAD 2d8610a): Functions/phase_pattern_generator.m,
% power_pattern_generator.m and adaptiveCouplingMatrixCalculation.m.
%
%   cal = origapp.angleCalibration(meas_mat, cal_angles, interp_res, ula, fc, c, iter)
%   meas_mat   : N-by-4-by-K captures, one per calibration angle (array mode only)
%   cal_angles : 1-by-K angles in degrees (as labelled by the operator/rotator)
%   interp_res : interpolation step in degrees (original: app scan_res)
%   Returns cal.steeringCorrection (G-by-4), cal.powCalibration (G-by-4),
%   cal.couplingMatrix (4-by-4), cal.gridDeg (1-by-G), plus source tables.
%
% Numerically identical to the originals (fixture compares them); the
% original helpers additionally opened figures. The angles are operator
% labels: a common splitter/cable feed carries no angle information, so a
% calibration made from such captures is a model table, not physical DOA
% calibration.
arguments
    meas_mat (:,:,:) {mustBeNumeric}
    cal_angles (1,:) double {mustBeFinite}
    interp_res (1,1) double {mustBePositive}
    ula
    fc (1,1) double {mustBePositive}
    c (1,1) double {mustBePositive}
    couplingIterations (1,1) double {mustBeInteger, mustBeNonnegative} = 20
end
K = numel(cal_angles);
M = size(meas_mat, 2);
assert(M == 4 && size(meas_mat, 3) == K && K >= 2, 'origapp:Calibration', ...
    'Angle calibration needs N-by-4-by-%d captures (got %s).', K, mat2str(size(meas_mat)));
assert(all(diff(cal_angles) > 0), 'origapp:Calibration', 'Calibration angles must increase.');
assert(all(isfinite(meas_mat), 'all'), 'origapp:Calibration', 'Calibration captures must be finite.');
grid = cal_angles(1):interp_res:cal_angles(end);

%% Phase pattern (phase_pattern_generator)
calibration_w = zeros(M, K);
mm = meas_mat;
for k = 1:K
    direction_w = exp(1j*pi*(0:M-1)'*sind(cal_angles(k)));
    mm(:,:,k) = mm(:,:,k).*direction_w';
    calibration_w(:,k) = origapp.phaseMismatch(mm(:,:,k), 1, "weights");
end
angle_src = rad2deg(angle(calibration_w));
angle_intrp = zeros(numel(grid), M);
for m = 1:M
    angle_intrp(:, m) = spline(cal_angles, angle_src(m,:), grid);
end
steering = exp(-1j*deg2rad(angle_intrp));

%% Power pattern (power_pattern_generator)
norm_sig = zeros(M, K);
for k = 1:K
    norm_sig(:,k) = 20*log10(std(meas_mat(:,:,k)));
end
pow_src = 10.^(norm_sig/10);
pow_intrp = zeros(numel(grid), M);
for m = 1:M
    pow_intrp(:, m) = spline(cal_angles, pow_src(m,:), grid);
end

%% Coupling matrix (adaptiveCouplingMatrixCalculation, same iteration)
lambda = c/fc; d = lambda/2;
ca = cal_angles.';
estimator = phased.MUSICEstimator('SensorArray', ula, 'ScanAngles', ca(1):ca(end), ...
    'OperatingFrequency', fc, 'DOAOutputPort', true, 'NumSignalsSource', 'Property', ...
    'NumSignals', 1);
str_mat_err = exp(1j*2*pi*d/lambda*sind(angle_src')).*pow_src';
str_mat_gen = exp(1j*2*pi*d/lambda*(0:M-1).*sind(ca));
C = pinv(str_mat_gen.*str_mat_err)*str_mat_gen;
cal_tmp = ca;
str_with_err = zeros(K, M);
for q = 1:couplingIterations
    for i = 1:K
        sig_rx = meas_mat(:,:,i);
        [~, doa] = estimator(sig_rx);
        cal_tmp(i) = doa;
        R = sig_rx'*sig_rx;
        [V, ~] = eig(R, 'matrix');
        str_with_err(i,:) = C\V(:,end);
    end
    str_mat_gen = exp(1j*2*pi*d/lambda*(0:M-1).*sind(cal_tmp));
    C = pinv(str_with_err)*str_mat_gen;
end
release(estimator);

cal = struct('gridDeg', grid, 'steeringCorrection', steering, 'powCalibration', pow_intrp, ...
    'couplingMatrix', C, 'angleSourceDeg', angle_src, 'powSource', pow_src, ...
    'calAnglesDeg', cal_angles, 'couplingIterations', couplingIterations, ...
    'label', "model calibration from operator-labelled captures; not physical DOA evidence");
end
