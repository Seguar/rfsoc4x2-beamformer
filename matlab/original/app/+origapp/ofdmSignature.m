function s=ofdmSignature(x,template,burstRows,threshold)
%OFDMSIGNATURE Find the OFDM preambles in an N-by-4 frame and estimate the
% wanted signal's array signature from them (training samples only).
%
% Detection is the spatially adaptive preamble correlation (best receive beam
% at each position): score(k) = c_k*S_k^-1*c_k' / |t|^2 in [0,1], where c_k is
% the per-channel correlation with the template and S_k the 4-by-4 sample
% covariance of the same window. A strong interferer from another direction
% (a CW jammer) is nulled by that beam, so it cannot hide the preamble the way
% it does in a total-power normalised correlation.
%
% s.starts   first row of each detected preamble (one per burst)
% s.a        1-by-4 wanted signature in rawData's convention (x ~ s(t)*a),
%            phase-aligned average over the detected bursts, unit norm
% s.score    detection score of each start
% Empty s.starts: no preamble at or above threshold (default 0.8^2).
if nargin<4 || isempty(threshold), threshold=0.8^2; end
t=template(:); n=size(x,1); m=size(x,2); L=numel(t); npos=n-L+1;
s=struct('starts',zeros(1,0),'a',zeros(1,m),'score',zeros(1,0));
if npos<1, return, end
nf=2^nextpow2(n+L-1);
c=ifft(fft(x,nf).*conj(fft(t,nf))); c=c(1:npos,:);          % npos-by-m
% Sliding window covariance S_k = sum x_i'*x_i over the template length.
o=reshape(conj(x),n,m,1).*reshape(x,n,1,m);                  % n-by-m-by-m
o=cumsum([zeros(1,m,m);o],1); S=o(L+1:end,:,:)-o(1:end-L,:,:); % npos-by-m-by-m
S=permute(S,[2 3 1]);
tr=zeros(1,1,npos); for i=1:m, tr=tr+real(S(i,i,:)); end       % trace per window
S=S+(1e-9*tr+realmin).*eye(m);
cc=reshape(c.',m,1,npos);
z=pagemldivide(S,conj(cc));                                    % S\c'
score=real(sum(cc.*z,1));                                      % c*S^-1*c'
score=reshape(score,[],1)/max(real(t'*t),realmin);
score(reshape(tr,[],1)<=max(tr)*1e-6)=0;
work=score;
while true
    [peak,k]=max(work);
    if isempty(peak) || peak<threshold, break, end
    s.starts(end+1)=k; s.score(end+1)=peak;
    work(max(1,k-burstRows+1):min(npos,k+burstRows-1))=0;
end
if isempty(s.starts), return, end
a=c(s.starts,:);[~,anchor]=max(sum(abs(a).^2,1));
a=mean(a.*exp(-1j*angle(a(:,anchor))),1);
s.a=a/max(norm(a),realmin);
end
