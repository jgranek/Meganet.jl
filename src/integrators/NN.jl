export NN,getNN,initTheta

"""
NN Neural Network block

 Y_k+1 = layer{k}(theta{k},Y_k)
"""
mutable struct NN{T} <: AbstractMeganetElement{T}
    layers  # layers of Neural Network, cell array
    outTimes
    Q
end

function getNN(layers::Array{AbstractMeganetElement{T}},outTimes=eye(Int,length(layers))[:,end],Q=I) where {T}
	nt   = length(layers)
    nout = nFeatOut(layers[1])

    for k=2:nt
        if nFeatIn(layers[k]) != nout
            error("Dim. of input features of block $k does not match dim. of output features of block $(k-1)");
        end
        nout = nFeatOut(layers[k])
    end
	return NN{T}(layers,outTimes,Q);
end


import Base.display
function display(this::NN)
    println("-- Neural Network --")
    println("nLayers: \t $(length(this.layers))")
    println("nFeatIn: \t $(nFeatIn(this))")
    println("nFeatOut: \t $(nFeatOut(this))")
    println("nTheta: \t $(nTheta(this))")
end

# ---------- counting thetas, input and output features -----
function nTheta(this::NN{T}) where {T}
    n = 0;
    for k=1:length(this.layers)
        n = n + nTheta(this.layers[k]);
    end
    return n
end
nFeatIn(this::NN{T}) where {T}  = nFeatIn(this.layers[1])
nFeatOut(this::NN{T}) where {T} = nFeatOut(this.layers[end])

function nDataOut(this::NN{T}) where {T}
    n=0;
    for k=1:length(this.layers)
        n = n+this.outTimes[k]* nFeatOut(this.layers[k]);
    end
end

function initTheta(this::NN{T}) where {T}
    theta = zeros(T,0)
    for k=1:length(this.layers)
        theta = [theta; vec(initTheta(this.layers[k]))]
    end
    return convert(Array{T},theta)
end


# --------- forward problem ----------
function apply(this::NN{T},theta::Array{T},Y0::Array{T},doDerivative=true) where {T}

    Y  = copy(Y0)
    nex = div(length(Y),nFeatIn(this))
    nt = length(this.layers)

    tmp = Array{Any}(nt+1,2)
    if doDerivative
        tmp[1,1] = Y0
    end

    Ydata = zeros(T,0,nex)
    cnt = 0
    for i=1:nt
        ni = nTheta(this.layers[i])
        Yd,Y,tmp[i,2] = apply(this.layers[i],theta[cnt+(1:ni)],Y,doDerivative)
        if this.outTimes[i]==1
            Ydata = [Ydata; this.Q*Yd]
        end
        if doDerivative
            tmp[i+1,1] = copy(Y)
        end
        cnt = cnt + ni
    end
    return Ydata,Y,tmp
end

# -------- Jacobian matvecs --------
function JYmv(this::NN{T},dY::Array{T},theta::Array{T},Y::Array{T},tmp) where {T}
    nex = div(length(Y),nFeatIn(this))
    nt = length(this.layers)
    cnt = 0
    dYdata = zeros(T,0,nex)
    for i=1:nt
        ni = nTheta(this.layers[i])
        dY = JYmv(this.layers[i],dY,theta[cnt+(1:ni)],tmp[i,1],tmp[i,2])[2]
        if this.outTimes[i]==1
            dYdata = [dYdata; this.Q*dY]
        end
        cnt = cnt+ni
    end
    return dYdata, dY
end

function  Jmv(this::NN,dtheta::Array{T},dY::Array{T},theta::Array{T},Y::Array{T},tmp) where {T}
    nex = div(length(Y),nFeatIn(this))
    nt = length(this.layers);
    if isempty(dY)
        dY = 0*Y
    end

    dYdata = zeros(T,0,nex)
    cnt = 0
    for i=1:nt
        ni = nTheta(this.layers[i])
        dY = Jmv(this.layers[i],dtheta[cnt+(1:ni)],dY,theta[cnt+(1:ni)],
                tmp[i,1],tmp[i,2])[2]
        if this.outTimes[i]==1
            dYdata = [dYdata; this.Q*dY]
        end
        cnt = cnt+ni
    end
    return dYdata,dY
end

# -------- Jacobian' matvecs --------
function JYTmv(this,Wdata::Array{T},W::Array{T},theta::Array{T},Y::Array{T},tmp) where {T}

    nex = div(length(Y),nFeatIn(this));
    if !isempty(Wdata)
        Wdata = reshape(Wdata,:,nex);
    end
    if isempty(W)
        W = 0.0
    elseif length(W)>1
        W     = reshape(W,:,nex)
    end
    nt = length(this.layers)

    cnt = 0; cnt2 = 0;
    for i=nt:-1:1
        ni = nTheta(this.layers[i])
        if this.outTimes[i]==1
            nn = nFeatOut(this.layers[i])
            W = W + this.Q'*Wdata[end-cnt2-nn+1:end-cnt2,:]
            cnt2 = cnt2 + nn
        end
        W  = JYTmv(this.layers[i], W,[],theta[end-cnt-ni+1:end-cnt],
                    tmp[i,1],tmp[i,2])
        cnt = cnt+ni
    end
    return W
end


function JthetaTmv(this::NN{T},Wdata::Array{T},W::Array{T},theta::Array{T},Y::Array{T},tmp) where {T}
	return JTmv(this,Wdata,W,theta,Y,tmp)[1];
end



function JTmv(this::NN,Wdata::Array{T},W::Array{T},theta::Array{T},Y::Array{T},tmp) where {T}
    nex = div(length(Y),nFeatIn(this))

    if size(Wdata,1)>0
        Wdata = reshape(Wdata,:,nex)
    end
    if length(W)==0
        W = zeros(T,nFeatOut(this),nex)
    elseif length(W)>1
        W     = reshape(W,:,nex)
    end

    dtheta = 0*theta
    nt = length(this.layers)

    cnt = 0; cnt2 = 0
    for i=nt:-1:1
        if this.outTimes[i]==1
            nn = nFeatOut(this.layers[i])
            W += this.Q'*Wdata[end-cnt2-nn+1:end-cnt2,:]
            cnt2 = cnt2 + nn
        end
        ni     = nTheta(this.layers[i])

        dmbi,W = JTmv(this.layers[i],W,zeros(T,0),theta[end-cnt-ni+1:end-cnt],tmp[i,1],tmp[i,2])
        dtheta[end-cnt-ni+1:end-cnt]  = dmbi
        cnt = cnt+ni
    end
    return  vec(dtheta), vec(W)

end
