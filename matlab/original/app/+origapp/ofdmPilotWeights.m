function weights=ofdmPilotWeights(x,template,symbolRows,burstRows)
% Receive weights in the app's row convention: sum(x .* weights,2).
% Estimate the wanted response only on the known preamble, and covariance
% in the silent intervals immediately around each synchronized OFDM burst.
% Preamble detection is spatially adaptive (origapp.ofdmSignature), so a
% jammer stronger than the wanted signal does not hide the preamble.
n=size(x,1);
assert(n>=numel(template),'origapp:NoSignal','Frame is shorter than the OFDM preamble.');
s=origapp.ofdmSignature(x,template,burstRows);
starts=s.starts;
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
a=s.a;
g=x(quiet,:);R=g'*g/size(g,1);
loadValue=max(0.01*real(trace(R))/size(R,1),eps);
v=(R+loadValue*eye(size(R)))\a';
weights=v.'; % processLegacyFrame normalizes every beamformer to the same norm
end
