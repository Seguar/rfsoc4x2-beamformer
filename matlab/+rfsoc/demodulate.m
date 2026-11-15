function [metric,equalized] = demodulate(y,ref)
% Training-only channel estimate; distributed pilots track phase/timing.
span=ref.nfft+ref.cp; count=size(ref.symbols,1);
assert(numel(y)>=count*span,'rfsoc:Frame','Incomplete waveform.');
blocks=reshape(y(1:count*span),span,[]).';
frequency=fft(blocks(:,ref.cp+1:end),[],2);
bins=frequency(:,ref.bins);
h=mean(bins(1:ref.train,:)./ref.symbols(1:ref.train,:),1);
assert(min(abs(h))>1e-12,'rfsoc:Lock','Zero training channel estimate.');
equalized=bins(ref.train+1:end,:)./h;
target=ref.symbols(ref.train+1:end,:);
signedBins=ref.bins-1; signedBins(signedBins>ref.nfft/2)=signedBins(signedBins>ref.nfft/2)-ref.nfft;
errors=unwrap(angle(equalized(:,ref.pilots).*conj(target(:,ref.pilots))),[],2);
basis=[ones(numel(ref.pilots),1),signedBins(ref.pilots).'];
fit=basis\errors.';
equalized=equalized.*exp(-1j*(fit(1,:).'+fit(2,:).'*signedBins));
data=true(1,numel(ref.bins)); data(ref.pilots)=false;
equalized=equalized(:,data); target=target(:,data);
evm=sqrt(mean(abs(equalized-target).^2,'all')/mean(abs(target).^2,'all'));
ber=mean(cat(3,real(equalized)>0,imag(equalized)>0)~= ...
    cat(3,real(target)>0,imag(target)>0),'all');
metric=struct('evmPercent',100*evm,'evmDb',20*log10(evm),'ber',ber, ...
    'payloadPhaseDeg',rad2deg(fit(1,:)), ...
    'payloadTimingSamples',fit(2,:)*ref.nfft/(2*pi));
end
