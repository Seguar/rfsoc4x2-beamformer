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
measurement.Iq.Status=32; measurement.Summary.Status=32;
[pct,~,status,quality]=rfsoc.readVsaEvm(measurement,true,0.5,true);
assert(pct==3 && quality.unclassifiedBits==32 && contains(status,'WARNING'));
for bad=[1 2 4 16 64 128 1024 2048 4096 8192 16384 32768 256]
    measurement.Iq.Status=32+bad;
    [p,d,~]=rfsoc.readVsaEvm(measurement,true,0.5,true);
    assert(isnan(p) && isnan(d),'SETX policy accepted another status bit.');
end
measurement.Iq.Status=32; measurement.Summary.Indicator='SYNC NOT FOUND';
[p,~,~]=rfsoc.readVsaEvm(measurement,true,0.5,true); assert(isnan(p));
measurement.Summary.Indicator=''; measurement.Status.MeasurementError='failure';
[p,~,~]=rfsoc.readVsaEvm(measurement,true,0.5,true); assert(isnan(p));
measurement.Status.MeasurementError='';
[p,~,~]=rfsoc.readVsaEvm(measurement,false,0.5,true); assert(isnan(p));
report=struct('passed',true,'cases',24,'source',"SIMULATED API objects; no actual VSA positive control");
disp('RFSOC_SIMULATED_VSA_READER_PASS');
    function assertRejected(fresh,message)
        [p,d,~]=rfsoc.readVsaEvm(measurement,fresh,0.5);
        assert(isnan(p) && isnan(d),message);
    end
end
