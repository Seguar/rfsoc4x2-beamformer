classdef FakeVsaData < handle
 properties
 Status=0
 Evm=3
 Correlation=0.9
 end
 methods
 function v=Summary(obj,key)
 if strcmp(key,'Ch1EVM'), v=obj.Evm; else, v=obj.Correlation; end
 end
 function v=SummaryUnit(~,key)
 if strcmp(key,'Ch1EVM'), v='%'; else, v=''; end
 end
 function Dispose(~), end
 end
end
