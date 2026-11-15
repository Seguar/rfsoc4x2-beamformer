function ref = loadReference(path)
ref=load(path);
assert(isfield(ref,'waveformVersion') && ref.waveformVersion==2, ...
    'rfsoc:Reference','Export the exact waveform v2 using export_matlab_reference.py.');
for name=["nfft","cp","train","bins","pilots","fsHz"]
    ref.(name)=double(ref.(name));
end
ref.wave=ref.wave(:); ref.bins=ref.bins(:).'; ref.pilots=ref.pilots(:).';
assert(size(ref.symbols,2)==numel(ref.bins),'rfsoc:Reference','Reference dimensions disagree.');
end
