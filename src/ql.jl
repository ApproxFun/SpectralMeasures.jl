
# returns the parameters for the limiting Toeplitz
function givenstail(t₀::Real,t₁::Real)
    @assert t₀^2-4t₁^2≥0
    s = (-t₀ + sqrt(t₀^2-4t₁^2))/(2t₁)
    l⁰ = (t₀ + sqrt(t₀^2-4t₁^2))/2
    # if s∞^2 > 1
    #     s∞ = (t₀ + sqrt(t₀^2-4t₁^2))/(2t₁)
    #     l0 = (t₀ - sqrt(t₀^2-4t₁^2))/2
    # end
    c = -sqrt(1-s^2)
    γ¹ = t₁*c
    γ⁰ = c*t₀ + s*γ¹
    l¹ = 2t₁  # = c*γ¹ - st₁
    l² = -t₁*s
    c,s,l⁰,l¹,l²,γ¹,γ⁰
end


function ql(a,b,t₀,t₁)
    if t₀^2 < 4t₁^2
        error("A QL decomposition only exists outside the essential spectrum")
    end
    # The Givens rotations coming from infinity (with parameters c∞ and s∞) leave us with the almost triangular
    # a[n-1]  b[n-1]   0    0    0
    # b[n-1]   a[n]   t₁    0    0
    #   0       γ¹      γ⁰    0    0
    #   0      l2     l1   l0    0
    #   0       0     l2   l1   l0


    if t₀ < 0
        # we want positive on the diagonal
        Q,L=ql(-a,-b,-t₀,-t₁)
        return -Q,L
    end




    n = max(length(a), length(b)+1)
    a = pad(a,n); b = pad(b,n-1);

    c∞,s∞,l⁰,l¹,l²,γ¹∞,γ⁰∞ = givenstail(t₀,t₁)
    # use recurrence for c. If we have a_0,…,a_N,t0,t0…, then
    # we only need c_-1,c_0,c_1,…,c_{N-1}.
    c=Array{eltype(c∞)}(n)
    s=Array{eltype(c∞)}(n-1)

    # ranges from 1 to N
    γ¹ = Array{eltype(c∞)}(n-1)
    γ¹[n-1] = c∞*b[n-1]  # k = N

    # ranges from 0 to N
    γ⁰ = Array{eltype(c∞)}(n)
    γ⁰[n] = c∞*a[n] + s∞*γ¹∞  # k = N


    k=n-1
    nrm = 1/sqrt(γ⁰[k+1]^2+b[k]^2)
    c[k+1] = γ⁰[k+1]*nrm  # K = N-1
    s[k] = -b[k]*nrm # K = N-1

    @inbounds for k=n-2:-1:1
        γ¹[k] = c[k+2]*b[k]  # k = N-1
        γ⁰[k+1] = c[k+2]*a[k+1] + s[k+1]*γ¹[k+1]  # k = N
        nrm = 1/sqrt(γ⁰[k+1]^2+b[k]^2)
        c[k+1] = γ⁰[k+1]*nrm  # K = N-1
        s[k] = -b[k]*nrm # K = N-1
    end

    γ⁰[1] = c[2]*a[1] + s[1]*γ¹[1]  # k = 0


    c[1] = sign(γ⁰[1])  # k = -1

    Q = HessenbergUnitary(Val{'L'},true,c,s,c∞,s∞)

    L = BandedMatrix(eltype(c∞),n+1,n,2,0)

    L[1,1] = abs(γ⁰[1]) - l⁰
    @views L[band(0)][2:end] .=  (-).(b./s) .- l⁰
    @views L[band(-1)][1:end-1] .=  c[2:end].*γ¹ .- s.*a[1:end-1] .- l¹
    view(L,band(-1))[end] .= c∞*γ¹∞ - s∞*a[end] - l¹
    @views L[band(-2)][1:end-1] .= (-).(s[2:end].*b[1:end-1]) .- l²
    view(L,band(-2))[end] .= -s∞*b[end] - l²

    Q,ToeplitzOperator([l¹,l²],[l⁰])+FiniteOperator(L,ℓ⁰,ℓ⁰)
end



discreteeigs(J::SymTriToeplitz) =
    2*J.b*discreteeigs(0.5*(J.dv-J.a)/J.b,0.5*J.ev/J.b) + J.a

connection_coeffs_operator(J::SymTriToeplitz) =
    connection_coeffs_operator(0.5*(J.dv-J.a)/J.b,0.5*J.ev/J.b)



struct SpectralMap{CC,QQ,RS,T} <: Operator{T}
    C::CC
    Q::QQ
    rangespace::RS
end

SpectralMap(C::Operator{T},Q::Operator{T},rs) where {T} =
    SpectralMap{typeof(C),typeof(Q),typeof(rs),T}(C,Q,rs)


domainspace(::SpectralMap) = SequenceSpace()
rangespace(S::SpectralMap) = S.rangespace


A_ldiv_B_coefficients(S::SpectralMap,v::AbstractVector;opts...) =
    A_ldiv_B_coefficients(S.Q,A_ldiv_B_coefficients(S.C,v);opts...)

A_mul_B_coefficients(S::SpectralMap,v::AbstractVector;opts...) =
    A_mul_B_coefficients(S.C,A_mul_B_coefficients(S.Q,v;opts...))

function getindex(S::SpectralMap,k::Integer,j::Integer)
    v = A_mul_B_coefficients(S,[zeros(j-1);1])
    k ≤ length(v) && return v[k]
    zero(eltype(S))
end


isbanded(S::SpectralMap) = true
function bandinds(S::SpectralMap)
    bi = bandinds(S.Q)
    bi[1],bi[2]+bandinds(S.C,2)
end

function Base.eig(Jin::SymTriToeplitz)
    Qret=Array(HessenbergUnitary{'U',Float64},0)
    λapprox=sort(discreteeigs(Jin))

    ctsspec = ApproxFun.Interval(Jin.a-2*abs(Jin.b),Jin.a+2*abs(Jin.b))

    J=Jin

    if length(λapprox) == 0
        C=connection_coeffs_operator(J)

        x=Fun(identity,Ultraspherical(1,ctsspec))

        U=SpaceOperator(C,ℓ⁰,space(x))
        return x,U
    end

    λ=Array(Float64,0)

    tol=1E-14
    for k=1:length(λapprox)
        μ=λapprox[k]

        Q,L=ql(J-μ*I)
        push!(Qret,deflate(Q',k-1))
        J=L*Q+μ*I

         while abs(J[1,2]) > tol
             # μ=J[1,1] DO NOT DO THIS. IF MU IS NOT ACCURATE, J[1,1] CAN BE AN INVALID SHIFT (MW)
             Q,L=ql(J-μ*I)
             J=L*Q+μ*I
             push!(Qret,deflate(Q',k-1))
         end

        push!(λ,J[1,1])
        J=J[2:end,2:end]
    end

    if length(λ) == 1
         Q=Qret[1]

         x=Fun(identity,PointSpace(λ[1])⊕Ultraspherical(1,ctsspec))
         C=SpaceOperator(InterlaceOperator(Diagonal([eye(length(λ)),connection_coeffs_operator(J)])),SequenceSpace(),space(x))

         U=SpectralMap(C,Q,space(x))
         return x,U
    else
        Q=BandedUnitary(reverse!(Qret))
        x=Fun(identity,mapreduce(PointSpace,⊕,λ)⊕Ultraspherical(1,ctsspec))
        C=SpaceOperator(InterlaceOperator(Diagonal([eye(length(λ)),connection_coeffs_operator(J)])),SequenceSpace(),space(x))

        U=SpectralMap(C,Q,space(x))
        return x,U
    end
end
