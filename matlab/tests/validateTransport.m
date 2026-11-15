function rows = validateTransport(port,outputPath)
% Start tests/fake_server.py with an explicit --port-file before calling.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
cfg=rfsoc.defaultConfig(); cfg.host="127.0.0.1"; cfg.port=port;
cfg.frameSamples=32; cfg.fsHz=61440000; cfg.timeoutSeconds=3;
expected=["rfsoc:Freshness","rfsoc:Protocol","rfsoc:Protocol","rfsoc:Disconnected"];
rows=struct('rejection',{});
for k=1:4
    source=rfsoc.FrameSource(cfg); guard=onCleanup(@()delete(source));
    if k==1
        first=source.next(); second=source.next();
        assert(first.sequence==1 && second.sequence==2,'Sequence mismatch.');
        lanes=reshape(0:255,8,[]).';
        assert(isequal(first.samples,lanes(:,1:2:8)-1j*lanes(:,2:2:8)),'IQ decoding mismatch.');
    end
    identifier="";
    try
        source.next();
    catch exception
        identifier=string(exception.identifier);
    end
    assert(identifier==expected(k),'Unexpected rejection %s',identifier);
    rows(k).rejection=identifier; clear guard;
end
if nargin>1
    fid=fopen(outputPath,'w'); guard=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(rows));
end
disp('RFSOC_MATLAB_TRANSPORT_PASS');
end
