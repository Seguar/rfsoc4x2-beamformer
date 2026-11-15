function [w,a] = pilotWeights(x,pilot)
pilot=pilot(:); a=(pilot'*x).'/real(pilot'*pilot);
residual=x-pilot*a.';
r=residual.'*conj(residual)/size(x,1);
r=r+eye(4)*max(real(trace(r))/4*0.01,1e-12);
w=r\a; w=w/(a'*w);
end
