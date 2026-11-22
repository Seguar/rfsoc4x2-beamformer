function out = processLegacyFrame(rawData, p)
%PROCESSLEGACYFRAME DOA + beamforming of one N-by-4 frame, ported from the
% rfsocBf.m revision the original app was written against (vsa_rfsoc commit
% 45e726b, 2025-01-14: 29-argument call, no 'num'). TCP receive and VSA send
% are removed: frames come from the injected backend, VSA output is returned
% as out.vsaBuffer for the backend's vsaSend.
%
% Original silent failures are explicit errors here (identifier origapp:*),
% so the caller clears the current DOA/pattern instead of looping silently.
% Ported unchanged: filtSig band filter, covariance passed to the estimator
% (original quirk: the 4x4 covariance is given to the phased estimators as
% four snapshots), signal-priority selection, the beamformer calls, weight
% normalisation (norm 2), channel selection, c2 conjugation and the cutter.
%
% p fields: ch bf off cutter ang_num fc dataChan diag bwOff ula scan_axis c1
% c2 fsRfsoc bw c estimator estimatorKind alg_scan_res mis_ang alpha gamma
% iter calibration bfEngine reviewed

%
% VSA_rfsoc_new additions (vsa_rfsoc HEAD 2d8610a rfsocBf.m), all optional
% fields with the HEAD order IQ -> coupling -> band filter -> DOA -> phase comp:
%   p.iqAdaptive / p.iqStatic / p.iqFilter (L-by-4) / p.iqMu : receive IQ compensation
%   p.coupComp + p.calibration.couplingMatrix (4-by-4)       : coupling compensation
%   p.phComp + steeringCorrection/powCalibration            : phase/power compensation
%   p.manualMvdrFormula "45e726b" (default) | "head" (m_mvdr power-weighted manifold)
% out.iqFilter returns the updated adaptive filter state.

out = struct('yspec',[],'estimated_angle',[],'bfSig',[],'weights',[], ...
    'rawData',[],'vsaBuffer',[],'spectrumAvailable',false,'engine',string(p.bfEngine), ...
    'iqFilter',[],'corrections',strings(1,0));
assert(size(rawData,2)==4, 'origapp:Frame', 'Need N-by-4 data.');
p = withDefaults(p);

%% Receive IQ compensation (VSA_rfsoc_new: adaptive first, then static)
if p.iqAdaptive
    [rawData, p.iqFilter] = origapp.iqCompensate(rawData, p.iqFilter, "adaptive", p.iqMu);
    out.corrections(end+1) = "adaptiveIQ";
end
if p.iqStatic
    assert(any(p.iqFilter ~= 0, 'all'), 'origapp:IqComp', ['Static IQ comp needs a ' ...
        'nonzero IQ filter (run Adaptive IQ comp first); an all-zero filter is a no-op.']);
    rawData = origapp.iqCompensate(rawData, p.iqFilter, "static");
    out.corrections(end+1) = "staticIQ";
end
out.iqFilter = p.iqFilter;

%% Coupling compensation (VSA_rfsoc_new: rawData = (C*rawData.').')
if p.coupComp
    error('origapp:CouplingUnreviewed', ['Coupling compensation is disabled pending review: ' ...
        'the legacy calibration moved a known 20-degree source to -41 degrees in simulation. ' ...
        'Stored couplingMatrix tables are diagnostic only.']);
end

%% Band filter (original filtSig)
rawData = filtSig(rawData, p.fsRfsoc, p.bw);

%% DOA
Rx = rawData'*rawData;
estimator = p.estimator;
switch p.estimatorKind
    case "manual"
        pow = p.calibration.powCalibration;
        assert(~isempty(pow), 'origapp:Calibration', ...
            ['%s needs cfg.calibration.powCalibration (scan-by-4); the original app ' ...
            'never passed it to rfsocBf, so this mode failed silently there.'], p.doa);
        assert(size(pow,1)==numel(p.scan_axis) && size(pow,2)==4, 'origapp:Calibration', ...
            'powCalibration must be %d-by-4.', numel(p.scan_axis));
        yspec = zeros(1, numel(p.scan_axis));
        if p.manualMvdrFormula == "head"
            % VSA_rfsoc_new Functions/m_mvdr.m: manifold weighted by the power
            % table, unnormalised data, linear output.
            Rinv = (rawData'*rawData)^(-1);
            for t = 1:numel(p.scan_axis)
                A_fixed = exp(-1j*pi*(0:3)'*sind(p.scan_axis(t))).*estimator(t,:)'.*pow(t,:).';
                yspec(t) = abs(1/(A_fixed'*Rinv*A_fixed));
            end
        end
        for t = 1:numel(p.scan_axis)*(p.manualMvdrFormula ~= "head")
            A = exp(-1j*pi*(0:3)'*sind(p.scan_axis(t)));
            A_fixed = A.*estimator(t,:)';
            sig_final_fixed = rawData./(pow(t,:).^0.5);
            Rx_fixed = sig_final_fixed'*sig_final_fixed;
            B_fixed = A_fixed'*Rx_fixed^(-1)*A_fixed; % literal original form
            yspec(t) = 10*log10(abs(1/B_fixed));
        end
        [~, ind] = findpeaks(yspec, "SortStr", "descend");
        estimated_angle = p.scan_axis(ind);
        out.spectrumAvailable = true;
    case "spectrum"
        [yspec, estimated_angle] = estimator(Rx);
        out.spectrumAvailable = true;
    case "angles"
        estimated_angle = estimator(Rx);
        yspec = zeros(size(p.scan_axis));
    otherwise
        error('origapp:DoaMethod', 'Unknown estimator kind.');
end

%% Channels
ch = p.ch;
if ch > 4, ch = 1:4; end

%% Signal choice (original order and tie behaviour kept)
estimated_angle = estimated_angle(:).';
estimated_angle = estimated_angle(~isnan(estimated_angle));
npc = numel(estimated_angle);
assert(npc >= 1, 'origapp:NoDoa', 'DOA estimator returned no direction.');
if npc > 2
    estimated_angle = estimated_angle(1:2);
    npc = 2;
end
assert(p.ang_num <= npc, 'origapp:Priority', ...
    'Signal priority %d requested but only %d direction(s) found.', p.ang_num, npc);
powbp = zeros(1, npc);
for i = 1:npc
    % as steerBf (conj(sv).' per column), with the steering object kept between frames
    rawSumM = sum(rawData .* origapp.steeringVector(p.ula, p.fc, estimated_angle(i))', 2);
    powbp(i,:) = bandpower(rawSumM, p.fsRfsoc, [-p.bw/2 p.bw/2]);
end
[~, idx] = sort(powbp, 'ascend');
if idx(p.ang_num) == 1
    estimated_angle = flip(estimated_angle);
end

%% c1: calibrated phase/power correction (original 45e726b semantics)
if p.c1
    assert(p.estimatorKind=="manual" && size(estimator,2)==4, 'origapp:Calibration', ...
        'c1 correction needs DOA type MVDRman_corr (original indexed the estimator as a table).');
    pow = p.calibration.powCalibration;
    ang_idx = find(p.scan_axis == estimated_angle(1), 1);
    assert(~isempty(ang_idx), 'origapp:Calibration', 'Estimated angle is not on the scan grid.');
    rawData = conj(estimator(ang_idx,:)).*rawData./(pow(ang_idx,:).^0.5);
end

%% Phase/power comp (VSA_rfsoc_new phComp/powComp; replaces c1 there)
if p.phComp
    assert(~p.c1, 'origapp:Calibration', ['c1 and Phase/power comp apply the same ' ...
        'correction; enable only one.']);
    if p.estimatorKind == "manual" && size(estimator,2) == 4
        sc = estimator;                       % HEAD: estimator(ang_idx,:) first
    else
        sc = p.calibration.steeringCorrection;
    end
    pow = p.calibration.powCalibration;
    G = numel(p.scan_axis);
    assert(isequal(size(sc), [G 4]) && isequal(size(pow), [G 4]), 'origapp:Calibration', ...
        ['Phase/power comp needs steeringCorrection and powCalibration of %d-by-4 ' ...
        '(the current scan grid); got %s and %s.'], G, mat2str(size(sc)), mat2str(size(pow)));
    ang_idx = find(p.scan_axis == estimated_angle(1), 1);
    assert(~isempty(ang_idx), 'origapp:Calibration', 'Estimated angle is not on the scan grid.');
    rawData = conj(sc(ang_idx,:)).*rawData./(pow(ang_idx,:).^0.5);
    out.corrections(end+1) = "phasePower";
end

%% Beamforming
if p.bfEngine == "reviewed"
    weights = reviewedWeights(rawData, estimated_angle, p);
else
    weights = originalWeights(rawData, estimated_angle, npc, p);
end

weights = weights/norm(weights)*2;
rawDataAdj = zeros(size(rawData));
for k = 1:4
    rawDataAdj(:,k) = rawData(:,k)*weights(k);
end
rawSum = sum(rawDataAdj(:,ch), 2);
if p.c2
    weights = conj(weights);
end
weights = weights(ch);

%% Cutter (original sigFinder logic; only cutInds = fb(1):fe(end) is used)
nRows = size(rawSum,1);
cutInds = 1:min(p.dataChan, nRows);
if p.cutter
    [~, fb_lines, fe_lines, ~, ~] = sigFinder(rawSum, 1, 100);
    if ~isempty(fb_lines)
        cutInds = fb_lines(1):fe_lines(end);
    end
end
bfSig = rawSum(cutInds);

buff = zeros(size(rawSum));
buff(cutInds) = bfSig/2^16;   % original VSA normalisation

out.yspec = yspec;
out.estimated_angle = estimated_angle;
out.bfSig = bfSig;
out.weights = weights;
out.rawData = rawData;
out.vsaBuffer = buff;
end

function weights = originalWeights(rawData, estimated_angle, npc, p)
ula = p.ula;
switch char(p.bf)
    case 'Steering'
        weights = origapp.steeringVector(ula, p.fc, estimated_angle(1))';   % as steerBf
    case 'MVDR'
        [~, weights] = mvdrBf(rawData, estimated_angle(1), p.diag, ula, p.fc, p.c);
        weights = conj(weights);
    case 'DMR'
        [~, weights] = dmr_beamformer(rawData, npc, ula, estimated_angle(1));
    case 'PC'
        [~, weights] = pc_beamformer(rawData, npc, ula, estimated_angle(1));
        weights = conj(weights);
    case 'PC_corr'
        error('origapp:Pending', ['PC_corr: original rfsocBf calls pc_beamformer with a 5th ' ...
            'argument it does not accept (failed silently). Use bfEngine="reviewed" explicitly.']);
    case 'LCMV'
        assert(numel(estimated_angle) >= 2, 'origapp:Constraints', ...
            'LCMV needs a second (interferer) direction; only one found.');
        [~, weights] = lcmv_beamformer(rawData, estimated_angle(1), estimated_angle(2), ula, p.bwOff, p.fc);
        weights = conj(weights);
    case 'RVL'
        [~, weights] = rvl_beamformer(rawData, p.gamma, ula, estimated_angle(1));
        weights = conj(weights);
    case 'RAB PC'
        [~, weights] = rab_pc_beamformer(rawData, npc, ula, estimated_angle(1), p.diag);
    case 'DL MVDR'
        loading = mean(var(rawData))*p.diag;
        [~, weights] = mvdrBf(rawData, estimated_angle(1), loading, ula, p.fc, p.c);
    case 'DL ITER MVDR'
        [~, weights] = dl_mvdr_beamformer(rawData, ula, estimated_angle(1));
    case 'QCB'
        [~, weights] = qcb_beamformer_algo_2(rawData, ula, estimated_angle(1), p.mis_ang, ...
            p.gamma, p.alpha, p.iter, p.alg_scan_res, p.fc);
    case 'Without'
        weights = ones(1,4);
    otherwise
        error('origapp:Algorithm', 'Unknown beamformer "%s".', p.bf);
end
weights = reshape(weights, 1, []);
assert(numel(weights)==4, 'origapp:Weights', 'Beamformer returned %d weights.', numel(weights));
end

function weights = reviewedWeights(rawData, estimated_angle, p)
% Reviewed +rfsoc core. Convention: y = X*conj(w); the original applies
% y = X*w.', so the original-convention weights are conj(w).'.
rc = p.reviewed;
if isstruct(rc) && isempty(fieldnames(rc)), rc=rfsoc.defaultConfig(); end
assert(isstruct(rc) && isfield(rc,'algorithm'), 'origapp:Config', ...
    'bfEngine="reviewed" needs cfg.reviewed (rfsoc.defaultConfig-style struct).');
rc.algorithm = string(p.bf);
rc.angleDeg = estimated_angle(1);
rc.fcHz = p.fc;
% Use the app's own phased.ULA geometry as the manifold, so the reviewed core
% steers in the same angle convention as the original DOA estimators.
grid = -90:0.25:90;
rc.manifold = origapp.steeringVector(p.ula, p.fc, grid);
rc.manifoldAnglesDeg = grid;
if rc.algorithm == "LCMV"
    assert(numel(estimated_angle) >= 2, 'origapp:Constraints', 'LCMV needs a second direction.');
    rc.nullAnglesDeg = estimated_angle(2);
end
[~, w] = rfsoc.beamform(rawData, rc);
weights = conj(w(:)).';
end

function p = withDefaults(p)
% VSA_rfsoc_new fields are optional so existing callers keep 45e726b behaviour.
d = struct('iqAdaptive', false, 'iqStatic', false, 'iqFilter', zeros(4,4), 'iqMu', 1e-16, ...
    'coupComp', false, 'phComp', false, 'manualMvdrFormula', "45e726b");
f = fieldnames(d);
for k = 1:numel(f)
    if ~isfield(p, f{k}), p.(f{k}) = d.(f{k}); end
end
p.manualMvdrFormula = string(p.manualMvdrFormula);
assert(any(p.manualMvdrFormula == ["45e726b","head"]), 'origapp:Config', ...
    'manualMvdrFormula must be "45e726b" or "head".');
if ~isfield(p.calibration, 'couplingMatrix'), p.calibration.couplingMatrix = []; end
end
