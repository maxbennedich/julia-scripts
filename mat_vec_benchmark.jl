# Matrix-vector multiplication benchmarks (Julia 0.7 version)

using LinearAlgebra
using Statistics
using Printf

f(a, b) = a * b # Matrix-vector multiplication
#f(a, b) = log(1 + a^b) # Slow operation

function mul_broadcast!(M, v)
    # For f = a*b, use M .*= v' (same performance)
    M .= f.(M, v')
end

function mul_diagonal!(M, v)
    rmul!(M, Diagonal(v))
end

function mul_loop!(M, v)
    n,m = size(M)
    for c = 1:m
        x = v[c]
        for r = 1:n
            # For f = a*b, use M[r,c] *= x (same performance)
            M[r,c] = f(M[r,c], x)
        end
    end
end

function mul_loop_inbounds!(M, v)
    n,m = size(M)
    @inbounds for c = 1:m
        x = v[c]
        for r = 1:n
            M[r,c] = f(M[r,c], x)
        end
    end
end

function mul_parallel_loop!(M, v)
    n,m = size(M)
    @inbounds Threads.@threads for c = 1:m
        x = v[c]
        for r = 1:n
            M[r,c] = f(M[r,c], x)
        end
    end
end

# Run expression 'ex' 'iterations' times and report median time and memory usage
macro timem(name, iterations, ex)
    quote
        t = [collect((@timed $(esc(ex)))[2:3]) for x=1:$iterations][2:end]
        m = median(reduce(hcat, t), dims=2)
        @printf("%s%5.0f ms (%d bytes)\n", $(esc(name)), m[1]*1e3, m[2])
    end
end

m = 1000
n = 100000

@printf("Matrix size: %d x %d\n", m, n)

types = [Int16, Int64, Float16, Float32, Float64]
tests = [
    (name = "Parallel for loop", fun = mul_parallel_loop!)
    (name = "For loop", fun = mul_loop!)
    (name = "For loop @inbounds", fun = mul_loop_inbounds!)
    (name = "Broadcast", fun = mul_broadcast!)
    (name = "Diagonal", fun = mul_diagonal!)]

width = maximum(map(t -> length(t.name), tests))

for dt in types
    println("\n$dt:")
    M = rand(dt, n, m)
    v = rand(dt, m)
    norms = map(t -> (A = copy(M); @timem rpad(t.name, width) 10 t.fun(A, v); norm(A)), tests)
    if !all(diff(norms) .== 0) println("==> Norms differ: $norms") end
end
