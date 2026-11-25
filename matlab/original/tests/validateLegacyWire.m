function validateLegacyWire(fixtureDir)
% Synthetic wire fixtures (tests/make_wire_fixtures.py); no board. Exact
% reconstruction and bounded inflate.
read=@(name)readBytes(fullfile(fixtureDir,name));
raw=read('wire-raw.bin'); encoded=read('wire-valid.bin');
actual=origapp.LegacyVsaBackend.decodeWire(encoded,numel(raw));
assert(isequal(actual(:),raw(:)),'Wire decoding changed IQ bytes.');
failed=false;
try, origapp.LegacyVsaBackend.decodeWire(read('wire-oversize.bin'),numel(raw));
catch e, failed=strcmp(e.identifier,'a2live:Protocol'); end
assert(failed,'Oversized decompression accepted.');
encoded(5)=bitxor(encoded(5),uint8(1));failed=false;
try, origapp.LegacyVsaBackend.decodeWire(encoded,numel(raw));
catch e, failed=strcmp(e.identifier,'a2live:Protocol'); end
assert(failed,'Corrupt wire digest accepted.');
cfg=origapp.defaultConfig(); cfg.dataChan=16; closed=0;
cfg.directOnly=false;
cfg.backend=struct('open',@()[],'next',@(~)[],'close',@markClosed, ...
    'availableChannels',@()logical([1 0 0 0]));
c=origapp.Controller(cfg);failed=false;
try, c.open(); catch e, failed=strcmp(e.identifier,'origapp:Channels'); end
assert(failed && closed==1 && ~c.IsOpen,'Partial array was accepted or open leaked.');delete(c);
cfg.directOnly=true;cfg.backend.availableChannels=@()[1 0 0 0];closed=0;
c=origapp.Controller(cfg);failed=false;
try, c.open(); catch e, failed=strcmp(e.identifier,'origapp:Channels'); end
assert(failed && closed==1,'Nonlogical channel mask accepted or open leaked.');delete(c);
disp('ORIGINAL_LEGACY_WIRE_PASS');
    function markClosed(), closed=closed+1; end
end
function bytes=readBytes(path)
fid=fopen(path,'rb'); assert(fid>=0); guard=onCleanup(@()fclose(fid)); bytes=fread(fid,Inf,'*uint8');
end
