function weights=ofdmPilotWeights(x,template,symbolRows,burstRows)
% Receive weights in the app's row convention: sum(x .* weights,2).
% Estimate the wanted response only on the known preamble, and covariance
% in the silent intervals immediately around each synchronized OFDM burst.
t=template(:); n=size(x,1); L=numel(t); npos=n-L+1;
assert(npos>0,'origapp:NoSignal','Frame is shorter than the OFDM preamble.');
nf=2^nextpow2(n+L-1);
c=ifft(fft(x,nf).*conj(fft(t,nf))); c=c(1:npos,:);
energy=cumsum([0;sum(abs(x).^2,2)]);
ex=energy(L+1:end)-energy(1:end-L);
score=sum(abs(c).^2,2)./max(ex*sum(abs(t).^2),realmin);
score(ex<=max(ex)*1e-6)=0;
% Keep one correlation maximum per burst; timing can straddle a sample.
starts=[];
while true
    [peak,k]=max(score);
    if peak<0.8^2,break,end
    starts(end+1)=k; %#ok<AGROW>
    score(max(1,k-burstRows+1):min(npos,k+burstRows-1))=0;
end
assert(~isempty(starts),'origapp:NoSignal','OFDM pilot MVDR: no wanted preamble.');
quiet=false(n,1); guard=ceil(symbolRows/2);
for k=starts
    quiet(max(1,k-2*symbolRows):k-guard-1)=true;
    quiet(k+burstRows+guard:min(n,k+burstRows+guard+3*symbolRows-1))=true;
end
for k=starts
    quiet(max(1,k-guard):min(n,k+burstRows+guard-1))=false;
end
assert(nnz(quiet)>=64,'origapp:NoSignal','OFDM pilot MVDR: insufficient gap samples.');
a=c(starts,:);[~,anchor]=max(sum(abs(a).^2,1));
a=mean(a.*exp(-1j*angle(a(:,anchor))),1);
g=x(quiet,:);R=g'*g/size(g,1);
loadValue=max(0.01*real(trace(R))/size(R,1),eps);
v=(R+loadValue*eye(size(R)))\a';
weights=v.'; % processLegacyFrame normalizes every beamformer to the same norm
end
