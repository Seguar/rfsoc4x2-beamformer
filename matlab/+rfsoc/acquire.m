function [aligned,tracking,a] = acquire(x,ref,fsHz)
% Reacquire each BRAM frame using only the four training symbols.
period=numel(ref.wave); span=ref.nfft+ref.cp; count=ref.train*span;
assert(size(x,1)>=2*period && size(x,2)==4 && ...
    all(isfinite(x),'all') && norm(x,'fro')>0, ...
    'rfsoc:Lock','Need at least two finite, nonzero waveform periods.');
pre=ref.wave(:); pre(count+1:end)=0; template=fft(pre);
time=(0:size(x,1)-1).'/fsHz;
grid=linspace(-150e3,150e3,max(3,ceil(4*150e3*period/fsHz)+1));
best=-Inf; delay=0; coarse=0; conjugated=false;
for flip=[false true]
    z=x; if flip, z=conj(z); end
    r=z(1:period,:).'*conj(z(1:period,:))/period;
    r=r+eye(4)*max(real(trace(r))*1e-6,1e-12);
    for frequency=grid
        block=z(1:period,:).*exp(-2j*pi*frequency*time(1:period));
        correlation=ifft(fft(block).*conj(template));
        score=real(sum(conj(correlation).*(r\correlation.').',2));
        [value,at]=max(score);
        if value>best
            best=value; delay=at; coarse=frequency; conjugated=flip;
        end
    end
end
z=x; if conjugated, z=conj(z); end
z=z.*exp(-2j*pi*coarse*time); aligned=z(delay:delay+period-1,:);
pilot=ref.wave(1:count);
[w,~]=rfsoc.pilotWeights(aligned(1:count,:),pilot);
combined=aligned*conj(w);
residual=angle(sum(conj(combined(1:(ref.train-1)*span)).* ...
    combined(span+1:count)))*fsHz/(2*pi*span);
aligned=aligned.*exp(-2j*pi*residual*(0:period-1).'/fsHz);
[w,a]=rfsoc.pilotWeights(aligned(1:count,:),pilot);
combined=aligned(1:count,:)*conj(w);
coherence=abs(pilot'*combined)^2/max(real(pilot'*pilot)*real(combined'*combined),realmin);
assert(coherence>=0.1,'rfsoc:Lock','No reliable DAC pilot lock.');
tracking=struct('delaySamples',delay-1,'cfoHz',coarse+residual, ...
    'conjugated',conjugated,'pilotCoherence',coherence);
end
