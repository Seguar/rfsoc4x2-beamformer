function [y,w,info] = beamform(x,cfg,a)
% X: samples x channels, covariance E[x*x^H], output X*conj(w).
% a may be a pilot-derived wanted manifold; it never comes from payload fitting.
assert(size(x,2)==4 && all(isfinite(x),'all'),'rfsoc:Input','Need finite N-by-4 data.');
assert(any(cfg.algorithm==rfsoc.algorithmNames()),'rfsoc:Algorithm','Unknown algorithm.');
if nargin<3 || isempty(a), a=rfsoc.steering(cfg,cfg.angleDeg); end
a=a(:); m=4;
assert(numel(a)==m && norm(a)>0 && all(isfinite(a)), ...
    'rfsoc:Manifold','Invalid wanted manifold.');
r=x.'*conj(x)/size(x,1); r=(r+r')/2;
scale=max(real(trace(r))/m,eps);
r=r/scale; % scalar normalization preserves covariance geometry
[u,d]=eig(r,'vector'); [d,ix]=sort(real(d),'descend'); u=u(:,ix);
floorValue=max(max(d)*1e-10,1e-12); d=max(d,floorValue);
k=cfg.sourceCount;
assert(k>=1 && k<m && k==fix(k),'rfsoc:Rank','sourceCount must be 1..3.');
info=struct('algorithm',cfg.algorithm,'iterations',0,'converged',true, ...
    'covarianceCondition',max(d)/min(d),'loading',0);
switch cfg.algorithm
    case "Without"
        w=ones(m,1)/m;
    case "Steering"
        w=a/(a'*a);
    case "MVDR"
        w=(r+eye(m)*max(cfg.absoluteLoading/scale,floorValue))\a;
    case "DMR"
        d(k+1:end)=mean(d(k+1:end));
        w=u*((u'*a)./d);
    case {"PC","PC_corr"}
        w=u(:,1:k)*((u(:,1:k)'*a)./d(1:k));
        if cfg.algorithm=="PC_corr"
            assert(numel(cfg.pcCorrection)==m && all(isfinite(cfg.pcCorrection)), ...
                'rfsoc:Calibration','pcCorrection must contain four finite coefficients.');
            w=w.*cfg.pcCorrection(:);
        end
    case "LCMV"
        assert(~isempty(cfg.nullAnglesDeg),'rfsoc:Constraints','LCMV needs explicit jammer angles.');
        c=[a,rfsoc.steering(cfg,cfg.nullAnglesDeg)];
        assert(size(c,2)<=m && rank(c)==size(c,2), ...
            'rfsoc:Constraints','LCMV constraints must be independent and at most four.');
        v=(r+floorValue*eye(m))\c;
        w=v*((c'*v)\[1;zeros(size(c,2)-1,1)]);
    case "RVL"
        assert(cfg.gamma>=0,'rfsoc:Loading','gamma must be nonnegative.');
        w=u*((u'*a)./(d+cfg.gamma./d));
    case "RAB PC"
        % Worst-case norm-bounded steering mismatch. Real optimization variables.
        pc=u(:,1:k)*((u(:,1:k)'*a)./d(1:k));
        pc=normalize(pc,a);
        radius=cfg.uncertainty*norm(2*pc/norm(pc)*exp(-1j*angle(pc(1)))-a);
        assert(radius<norm(a),'rfsoc:Feasibility','RAB uncertainty is infeasible.');
        w0=a/(norm(a)*(norm(a)-radius));
        options=optimoptions('fmincon','Display','off','Algorithm','sqp', ...
            'MaxIterations',cfg.maxIterations,'ConstraintTolerance',1e-8);
        [z,~,flag,output]=fmincon(@objective,[real(w0);imag(w0)], ...
            [],[],[],[],[],[],@robustConstraint,options);
        assert(flag>0,'rfsoc:Solver','RAB PC solver failed: %s',output.message);
        w=z(1:m)+1j*z(m+1:end); info.iterations=output.iterations;
    case "DL MVDR"
        info.loading=cfg.loading;
        w=(r+max(cfg.loading,floorValue)*eye(m))\a;
    case "DL ITER MVDR"
        % Nondegenerate ellipsoid loading equations retained from the newer app.
        % epsilon is now an explicit user-selected uncertainty parameter.
        e=cfg.uncertainty^2;
        assert(e>0 && e<norm(a)^2,'rfsoc:Feasibility','Invalid ellipsoid radius.');
        z=u'*a; lo=(norm(a)-sqrt(e))/(max(d)*sqrt(e));
        hi=min((norm(a)-sqrt(e))/(min(d)*sqrt(e)), ...
            sqrt(sum(abs(z).^2./d.^2)/e));
        assert(hi>=lo,'rfsoc:Feasibility','Empty iterative-loading interval.');
        equation=@(lambda) sum(abs(z).^2./(1+lambda*d.^2))-e;
        if equation(lo)*equation(hi)>0
            error('rfsoc:Solver','Iterative-loading equation has no bracketed solution.');
        end
        lambda=fzero(equation,[lo hi]); info.loading=lambda;
        w=(r+lambda*eye(m))\a;
    case "QCB"
        assert(cfg.mismatchDeg>0 && cfg.loadingGrowth>1 && cfg.gamma>0, ...
            'rfsoc:Qcb','QCB requires positive width/loading and growth >1.');
        edges=rfsoc.steering(cfg,cfg.angleDeg+[-cfg.mismatchDeg cfg.mismatchDeg]);
        scan=rfsoc.steering(cfg,cfg.angleDeg+ ...
            linspace(-cfg.mismatchDeg,cfg.mismatchDeg,max(3,ceil(2*cfg.mismatchDeg/cfg.scanStepDeg)+1)));
        loadValue=cfg.gamma; totalLoad=0; info.converged=false;
        for iteration=1:cfg.maxIterations
            totalLoad=totalLoad+loadValue;
            v=(r+totalLoad*eye(m))\edges;
            g=(edges'*v)\eye(2);
            rho=[max(1,abs(g(1,2))/abs(g(1,1))); ...
                max(1,abs(g(1,2))/abs(g(2,2)))];
            rho(2)=rho(2)*exp(1j*(-angle(g(1,2))+pi));
            w=v*g*rho;
            if all(abs(scan'*w)>=1-1e-7), info.converged=true; break; end
            loadValue=loadValue*cfg.loadingGrowth;
        end
        info.iterations=iteration; info.loading=totalLoad;
        assert(info.converged,'rfsoc:Solver','QCB failed its sector response constraint.');
end
% QCB/RAB retain their robust gain constraints; other modes have unit desired gain.
if ~any(cfg.algorithm==["Without","QCB","RAB PC"]), w=normalize(w,a); end
assert(all(isfinite(w)),'rfsoc:Weights','Nonfinite beamforming weights.');
y=x*conj(w); info.desiredResponse=w'*a;
    function value=objective(z)
        v=z(1:m)+1j*z(m+1:end); value=real(v'*r*v);
    end
    function [c,ceq]=robustConstraint(z)
        v=z(1:m)+1j*z(m+1:end);
        c=radius*norm(v)-real(v'*a)+1; ceq=imag(v'*a);
    end
end

function w=normalize(w,a)
response=a'*w;
assert(abs(response)>1e-12*norm(a)*norm(w),'rfsoc:Weights','Zero wanted response.');
w=w/response;
end
