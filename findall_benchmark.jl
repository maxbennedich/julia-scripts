using BenchmarkTools, Random, Statistics, Printf

####################
# OPTIMIZED FINDALL
####################

@inline _blsr(x)= x & (x-1)

# Generic case (>2 dimensions)
function allindices!(I, B::BitArray)
    ind = first(keys(B))
    for k = 1:length(B)
        I[k] = ind
        ind = nextind(B, ind)
    end
end

# Optimized case for vector
function allindices!(I, B::BitVector)
    I[:] .= 1:length(B)
end

# Optimized case for matrix
function allindices!(I, B::BitMatrix)
    k = 1
    for c = 1:size(B,2), r = 1:size(B,1)
        I[k] = CartesianIndex(r, c)
        k += 1
    end
end

import Base.tail

@inline overflowind(i1, irest::Tuple{}, size) = (i1, irest)
@inline function overflowind(i1, irest, size)
    i2 = irest[1]
    while i1 > size[1]
        i1 -= size[1]
        i2 += 1
    end
    i2, irest = overflowind(i2, tail(irest), tail(size))
    return (i1, (i2, irest...))
end

@inline toind(i1, irest::Tuple{}) = i1
@inline toind(i1, irest) = CartesianIndex(i1, irest...)

function findall_optimized(B::BitArray)
    nnzB = count(B)
    I = Vector{eltype(keys(B))}(undef, nnzB)
    nnzB == 0 && return I
    nnzB == length(B) && (allindices!(I, B); return I)
    Bc = B.chunks
    Bs = size(B)
    Bi = i1 = i = 1
    irest = ntuple(one, length(B.dims) - 1)
    c = Bc[1]
    @inbounds while true
        while c == 0
            Bi == length(Bc) && return I
            i1 += 64
            Bi += 1
            c = Bc[Bi]
        end

        tz = trailing_zeros(c)
        c = _blsr(c)

        i1, irest = overflowind(i1 + tz, irest, Bs)
        I[i] = toind(i1, irest)
        i += 1
        i1 -= tz
    end
end

####################
# BENCHMARKING CODE
####################

function cpu_speed_ghz()
    # if available, use reported CPU speed instead of current speed (which
    # may be inaccurate if the CPU is idling)
    cpu_info = Sys.cpu_info()[1]
    m = match(r"([\d\.]+)GHz", cpu_info.model)
    ghz = m ≡ nothing ? cpu_info.speed / 1000 : parse(Float64,  m.captures[1])
end

const CPU_SPEED_GHZ = cpu_speed_ghz()

function benchmark_findall(M, quick_benchmark = false)
    func = [findall, findall_optimized]

    for target_fill_rate in [0.001, 0.01, 0.05, 0.2, 0.5, 0.8, 0.99, 1]
        B = M .< target_fill_rate

        # verify that the results are identical
        @assert func[1](B) == func[2](B)

        actual_fill_rate = count(B) / length(M)
        sizestr = join(size(B), " x ")
        @printf("%16s |  %5.1f %%", sizestr, actual_fill_rate*100)

        times = []
        for f in func
            if quick_benchmark
                b = @timed for n = 1:100; f(B); end
                time_ns = b[2] * 1e9 / 100
            else
                b = @benchmark $f($B)
                time_ns = minimum(b.times)
            end
            push!(times, time_ns)
            ns_per_idx = time_ns / count(B)
            cycles_per_idx = ns_per_idx * CPU_SPEED_GHZ
            @printf(" | %7.2f μs | %7.2f ns | %7.2f", time_ns*1e-3, ns_per_idx, cycles_per_idx)
        end
        @printf(" | %5.2f x\n", times[1] / times[2])
    end
end

@printf("CPU speed: %.2f GHz\n\n", CPU_SPEED_GHZ)
header = "       size      | selected |  old time  |   per idx  |  cycles |  new time  |   per idx  |  cycles | speedup"
println(header * "\n" * "-"^length(header))

for dims = [(100000,), (191,211), (15,201,10), (64,9,3,18)]
    Random.seed!(0)
    benchmark_findall(rand(dims...))
end
