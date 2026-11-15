function report = validateVsaReader()
% SIMULATED reader contract. No VSA application, DLL, instrument or RF data.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,fileparts(mfilename('fullpath')));
measurement=FakeVsaMeasurement();
[pct,db,~]=rfsoc.readVsaEvm(measurement,true,0.5);
assert(pct==3 && abs(db-20*log10(0.03))<1e-10);
measurement.Iq.Status=128;
[pct,db,~]=rfsoc.readVsaEvm(measurement,true,0.5);
assert(isnan(pct) && isnan(db),'NoSync IQ retained summary EVM.');
measurement.Iq.Status=32;
assertRejected(true,'Unknown status bit accepted.');
measurement.Iq.Status=0; measurement.Summary.Status=128;
assertRejected(true,'Bad summary status accepted.');
measurement.Summary.Status=0; measurement.Summary.Correlation=0.014;
assertRejected(true,'Noise-like sync correlation accepted.');
measurement.Summary.Correlation=NaN;
assertRejected(true,'Nonfinite sync correlation accepted.');
measurement.Summary.Correlation=0.9;
assertRejected(false,'Stale acquisition accepted.');
report=struct('passed',true,'cases',7,'source',"SIMULATED API objects; no actual VSA positive control");
disp('RFSOC_SIMULATED_VSA_READER_PASS');
    function assertRejected(fresh,message)
        [p,d,~]=rfsoc.readVsaEvm(measurement,fresh,0.5);
        assert(isnan(p) && isnan(d),message);
    end
end
