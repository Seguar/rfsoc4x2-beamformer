classdef FakeVsaMeasurement < handle
 properties
 Iq
 Summary
 end
 methods
 function obj=FakeVsaMeasurement()
 obj.Iq=FakeVsaData(); obj.Summary=FakeVsaData();
 end
 function d=MeasurementData(obj,name)
 if strcmp(name,'IQ Meas1'), d=obj.Iq; else, d=obj.Summary; end
 end
 end
end
