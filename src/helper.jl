
function ql(A::Matrix)
    Q,R=qr(A[end:-1:1,end:-1:1])
    Q[end:-1:1,end:-1:1],R[end:-1:1,end:-1:1]
end

joukowsky(z) = 0.5*(z+1/z)

function jacobimatrix(a,b,t0,t1,N)
    J = BandedMatrix(Float64,N,N,1,1)

    for i = 1:min(length(a),N)
        J[i,i] = a[i]
    end
    for i=length(a)+1:N
        J[i,i] = t0
    end

    for i = 1:min(length(b),N-1)
        J[i,i+1] = J[i+1,i] = b[i]
    end

    for i=length(b)+1:N-1
        J[i,i+1] = J[i+1,i] = t1
    end

    J
end

jacobimatrix(a,b,N) = jacobimatrix(a,b,0,.5,N)

function jacobioperator(a,b,t0,t1)
    n = max(length(a),length(b)+1)
    a = [a;zeros(n-length(a))]; b = [b;.5+zeros(n-length(b))]
    SymTriPertToeplitz(ToeplitzOperator([t1],[t0,t1]),SymTriOperator(a-t0,b-t1))
end

jacobioperator(a,b) = jacobioperator(a,b,0,.5)


freejacobioperator() = SymTriPertToeplitz([0.],[.5],0.,.5)


## tridiagonal ql

function tridql!(L::Matrix)
    n=size(L,1)

  # Now we do QL for the compact part in the top left
    cc=Array{eltype(L)}(n)
    ss=Array{eltype(L)}(n-1)

    for i = n:-1:2
        nrm=sqrt(L[i-1,i]^2+L[i,i]^2)
        c,s = L[i,i]/nrm, -L[i-1,i]/nrm
        if i > 2
            L[i-1:i,i-2:i] = [c s; -s c]*L[i-1:i,i-2:i]
            L[i-1,i]=0
        else
            L[i-1:i,i-1:i] = [c s; -s c]*L[i-1:i,i-1:i]
            L[i-1,i]=0
        end
        cc[i]=c
        ss[i-1]=s
    end
    cc[1]=sign(L[1,1])
    L[1,1]=abs(L[1,1])
    cc,ss,L
end


function tridql!(J::BandedMatrix)
    n=size(J,1)
    L=BandedMatrix(copy(J.data),J.m,2,0)

  # Now we do QL for the compact part in the top left
    cc=Array{eltype(J)}(n)
    ss=Array{eltype(J)}(n-1)

    for i = n:-1:2
        nrm=sqrt(J[i-1,i]^2+J[i,i]^2)
        c,s = J[i,i]/nrm, -J[i-1,i]/nrm

        for j=max(i-2,1):i
            L[i,j]=-s*J[i-1,j]+c*J[i,j]
            J[i-1,j]=c*J[i-1,j]+s*J[i,j]
        end
        cc[i]=c
        ss[i-1]=s
    end
    cc[1]=sign(J[1,1])
    L[1,1]=abs(J[1,1])
    cc,ss,L
end

#Finds NxN truncation of C such that C'(Q_k(s)) =  (P_k(s)),
# where P_k has Jacobi coeffs a,b and Q_k has Jacobi coeffs c,d
function connectioncoeffsmatrix(a::AbstractVector, b::AbstractVector, c::AbstractVector, d::AbstractVector, N)
  if N>max(length(a),length(b)+1,length(c),length(d)+1)
    a = [a;zeros(N-length(a))]; b = [b;.5+zeros(N-length(b))]
    c = [c;zeros(N-length(c))]; d = [d;.5+zeros(N-length(d))]
  end

  C = zeros(eltype(a),N,N)
  C[1,1] = 1
  C[1,2] = (c[1]-a[1])/b[1]
  C[2,2] = d[1]/b[1]
  for j = 3:N
    C[1,j] = ((c[1]-a[j-1])*C[1,j-1] + d[1]*C[2,j-1] - b[j-2]*C[1,j-2])/b[j-1]
    for i = 2:j-1
      C[i,j] = (d[i-1]*C[i-1,j-1] + (c[i]-a[j-1])*C[i,j-1] + d[i]*C[i+1,j-1] - b[j-2]*C[i,j-2])/b[j-1]
    end
    C[j,j] = d[j-1]*C[j-1,j-1]/b[j-1]
  end
  C
end


#Makes the matrix C which transforms the coefficients of an expansion in "right" matrix orthonormal polynomial with recurrence coeffs a,b (J) to those of an expansion in the "right" MOPs with recurrence coeffs c,d (D). So C is block-upper-triangular and CJ = DC (modulo the final column). The types of a,b,c,d must be BlockArrays which are like column vectors of length N whose entries are kxk blocks. The blocks of a and c should be symmetric.
function connectioncoeffsmatrix(a::AbstractBlockArray, b::AbstractBlockArray, c::AbstractBlockArray, d::AbstractBlockArray)
  k = blocksize(a,1,1)[1]
  N = nblocks(a,1)
  C = BlockArray(zeros(k*N,k*N),k*ones(Int64,N),k*ones(Int64,N))
  C[Block(1,1)] = eye(k,k)
  C[Block(1,2)] = (c[Block(1,1)]-a[Block(1,1)])*pinv(b[Block(1,1)]')
  C[Block(2,2)] = d[Block(1,1)]'/b[Block(1,1)]'
  for j = 3:N
    C[Block(1,j)] = (c[Block(1,1)]*C[Block(1,j-1)]-C[Block(1,j-1)]*a[Block(j-1,1)] + d[Block(1,1)]*C[Block(2,j-1)]-C[Block(1,j-2)]*b[Block(j-2,1)])/b[Block(j-1,1)]'
    for i = 2:j-1
        C[Block(i,j)] = (d[Block(i-1,1)]'*C[Block(i-1,j-1)] + c[Block(i,1)]*C[Block(i,j-1)]-C[Block(i,j-1)]*a[Block(j-1,1)] +d[Block(i,1)]*C[Block(i+1,j-1)] - C[Block(i,j-2)]*b[Block(j-2,1)])/b[Block(j-1,1)]'
    end
    C[Block(j,j)] = (d[Block(j-1,1)]'*C[Block(j-1,j-1)])/b[Block(j-1,1)]'
  end
  C
end

# This is for Chebyshev U
connectioncoeffsmatrix(a,b,N) = connectioncoeffsmatrix(a,b,[],[],N)

# Converts coefficients a^J to coefficients a^D using Clenshaw
function applyconversion(J::SymTriPertToeplitz,D::SymTriPertToeplitz,v::Vector)
  N = length(v)
  T = eltype(b)
  b = zeros(T,N); b1 = zeros(T,N); b2 = zeros(T,N)
  for k = N:-1:1
    # before: b = b_k+1, b1 = b_k+2, (and b2 = b_k+3 is to be forgotten)
    b2 = pad((D-J[k,k]*I)*b,N)/J[k,k+1]-b1*(J[k,k+1]/J[k+1,k+2])
    b2[1] += v[k]
    b2, b1, b = b1, b, b2
    # after: b = b_k, b1 = b_k+1, b2 = b_k+2
  end
  b
end
