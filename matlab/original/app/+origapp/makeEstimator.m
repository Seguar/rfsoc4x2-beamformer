function [estimator, kind] = makeEstimator(doa, ula, scan_axis, num, fc, calibration)
%MAKEESTIMATOR Port of the original Functions/doaEst.m with explicit modes.
% kind: "spectrum" -> [yspec, angles] = estimator(Rx)
%       "angles"   -> angles = estimator(Rx); no spatial spectrum
%       "manual"   -> numeric matrix used by the original manual MVDR loop
% Differences from doaEst.m (documented in CONTROL_MAP.md):
%  * 'WSFR' is listed in the original UI but commented out in doaEst, which
%    then silently built an MVDR estimator. Here it builds the toolbox
%    phased.RootWSFEstimator it names.
%  * 'MVDRman_corr' takes the steering correction from cfg.calibration
%    instead of importdata("steering_correction.mat") in the current folder.
%  * Unknown names are an error instead of falling back to MVDR.
switch char(doa)
    case 'MVDR'
        estimator = phased.MVDREstimator('SensorArray',ula, ...
            'OperatingFrequency',fc,'ScanAngles',scan_axis, ...
            'DOAOutputPort',true,'NumSignals',num);
        kind = "spectrum";
    case 'MVDRman'
        estimator = ones(size(scan_axis))';
        kind = "manual";
    case 'MVDRman_corr'
        sc = calibration.steeringCorrection;
        assert(~isempty(sc), 'origapp:Calibration', ...
            'MVDRman_corr needs cfg.calibration.steeringCorrection (scan-by-4).');
        assert(size(sc,1)==numel(scan_axis) && size(sc,2)==4, 'origapp:Calibration', ...
            'steeringCorrection is %dx%d, scan axis has %d angles.', size(sc,1), size(sc,2), numel(scan_axis));
        estimator = sc;
        kind = "manual";
    case 'MUSIC'
        estimator = phased.MUSICEstimator('SensorArray',ula, ...
            'OperatingFrequency',fc,'ScanAngles',scan_axis, ...
            'DOAOutputPort',true);
        kind = "spectrum";
    case 'MUSICR'
        estimator = phased.RootMUSICEstimator('SensorArray',ula,'OperatingFrequency',fc);
        kind = "angles";
    case 'Beamscan'
        estimator = phased.BeamscanEstimator('SensorArray',ula, ...
            'OperatingFrequency',fc,'ScanAngles',scan_axis, ...
            'DOAOutputPort',true,'NumSignals',num);
        kind = "spectrum";
    case 'ESPRITE'
        estimator = phased.ESPRITEstimator('SensorArray',ula,'OperatingFrequency',fc);
        kind = "angles";
    case 'ESPRITEBS'
        estimator = phased.BeamspaceESPRITEstimator('SensorArray',ula,'OperatingFrequency',fc);
        kind = "angles";
    case 'WSFR'
        estimator = phased.RootWSFEstimator('SensorArray',ula,'OperatingFrequency',fc);
        kind = "angles";
    otherwise
        error('origapp:DoaMethod', 'Unknown DOA method "%s".', doa);
end
end
