# xxl rule 6: the generated landscape (spec, "Generated landscape"). A sum of Gaussian bumps on the torus, cut into
# capacities 0-4 by rank so that every capacity covers exactly as many sites as the xl map's. Standard library only,
# and a generator of its own (SplitMix64) so the maps regenerate identically on any Julia version or in another language.

const XXL_SPICE_MAP = "spice-map-xxl.txt"

"""
    SplitMix64(seed)

Vigna's SplitMix64, written out here rather than drawn from `Random`, whose streams Julia doesn't promise to keep
between versions. `state` starts at `seed`.
"""
mutable struct SplitMix64
    state::UInt64
end

SplitMix64(seed::Integer) = SplitMix64(UInt64(seed))

"""
    next!(g::SplitMix64) -> UInt64

The next 64-bit output: add 0x9e3779b97f4a7c15 to the state, then mix with two xor-shift-multiply rounds (constants
0xbf58476d1ce4e5b9 and 0x94d049bb133111eb) and a final xor-shift. Arithmetic wraps modulo 2^64.
"""
function next!(g::SplitMix64)
    g.state += 0x9e3779b97f4a7c15
    z = g.state
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

"""
    unit!(g::SplitMix64) -> Float64

A uniform draw on [0, 1) from the top 53 bits of `next!(g)`: `(next!(g) >> 11) * 2^-53`.
"""
unit!(g::SplitMix64) = (next!(g) >> 11) * 2.0^-53

"""
    draw_bumps(seed; w=500, h=500, n=400) -> Vector{NamedTuple}

The field's `n` bumps from one SplitMix64 stream, each drawn in the order centre x (`w·unit!`), centre y (`h·unit!`),
radius (`exp(log 5 + unit!·(log 80 − log 5))`, log-uniform on 5-80 sites), height (`1 − unit!`, uniform on (0, 1]).
"""
function draw_bumps(seed::Integer; w::Int=500, h::Int=500, n::Int=400)
    g = SplitMix64(seed)
    bumps = NamedTuple{(:x, :y, :r, :h),NTuple{4,Float64}}[]
    for _ in 1:n
        x = w * unit!(g)
        y = h * unit!(g)
        r = exp(log(5) + unit!(g) * (log(80) - log(5)))
        height = 1 - unit!(g)
        push!(bumps, (x=x, y=y, r=r, h=height))
    end
    return bumps
end

# The wrapped distance along one axis of a ring of width `w`, for real coordinates: dx = |a − b| mod w, then the
# shorter way round. (geometry.jl's integer helpers load after this file.)
function wrapped_gap(w::Int, a::Float64, b::Float64)
    d = mod(abs(a - b), w)
    return min(d, w - d)
end

# One bump's contribution at squared wrapped distance `d2`: h·exp(−d²/(2r²)).
bump_height(b, d2::Float64) = b.h * exp(-d2 / (2 * b.r * b.r))

"""
    field_value(bumps, x::Float64, y::Float64; w=500, h=500) -> Float64

The field at any point of the torus: the bumps' contributions summed in draw order, each `h·exp(−d²/(2r²))` at the
wrapped distance d to its centre, with d² = dx² + dy².
"""
function field_value(bumps, x::Float64, y::Float64; w::Int=500, h::Int=500)
    total = 0.0
    for b in bumps
        dx = wrapped_gap(w, x, b.x)
        dy = wrapped_gap(h, y, b.y)
        total += bump_height(b, dx * dx + dy * dy)
    end
    return total
end

"""
    bump_field(seed; w=500, h=500, n=400) -> Matrix{Float64}

The field at every site's 0-based integer coordinates, indexed `[x + 1, y + 1]`: the `n` bumps of
[`draw_bumps`](@ref) summed in draw order with no truncation, so each entry equals `field_value` there exactly.
"""
function bump_field(seed::Integer; w::Int=500, h::Int=500, n::Int=400)
    field = zeros(Float64, w, h)
    dx2 = Vector{Float64}(undef, w)
    dy2 = Vector{Float64}(undef, h)
    for b in draw_bumps(seed; w, h, n)
        for x in 1:w
            dx2[x] = wrapped_gap(w, Float64(x - 1), b.x)^2
        end
        for y in 1:h
            dy2[y] = wrapped_gap(h, Float64(y - 1), b.y)^2
        end
        for y in 1:h, x in 1:w
            field[x, y] += bump_height(b, dx2[x] + dy2[y])
        end
    end
    return field
end

"""
    cut_by_rank(field, counts::NTuple{5,Int}) -> (Matrix{Int}, Float64)

Capacities 0-4 by rank: the lowest `counts[1]` sites of `field` get 0, the next `counts[2]` get 1, and so on up, so
capacity c covers exactly `counts[c + 1]` sites. Also returns the smallest gap between neighbouring values at the four
cuts (the first value of one class less the last of the one below); a tie is a gap of 0.
"""
function cut_by_rank(field::AbstractMatrix{<:Real}, counts::NTuple{5,Int})
    sum(counts) == length(field) ||
        throw(ArgumentError("counts $counts must sum to the $(length(field)) sites"))
    order = sortperm(vec(field); alg=MergeSort)  # stable
    cap = zeros(Int, size(field))
    gap = Inf
    first_site = 1
    for (c, n) in enumerate(counts)
        for k in first_site:(first_site + n - 1)
            cap[order[k]] = c - 1
        end
        if c > 1 && n > 0 && first_site > 1
            gap = min(gap, field[order[first_site]] - field[order[first_site - 1]])
        end
        first_site += n
    end
    return cap, gap
end

"""
    generate_map(first_seed, counts; w=500, h=500, n=400) -> (Matrix{Int}, Int)

The capacity map from the first seed, `first_seed`, `first_seed + 1`, …, whose cuts all have gaps of at least 1e-9 (far
above the rounding a different machine or language could introduce), and that seed.
"""
function generate_map(first_seed::Integer, counts::NTuple{5,Int}; kw...)
    seed = Int(first_seed)
    while true
        cap, gap = cut_by_rank(bump_field(seed; kw...), counts)
        gap >= 1e-9 && return cap, seed
        seed += 1
    end
end

"""
    map_text(cap) -> String

A capacity matrix in the map file format (docs/xl.md, "The map"): one line per row, the northernmost first, numbers
separated by single spaces, LF line endings, a newline after the last line.
"""
function map_text(cap::AbstractMatrix{<:Integer})
    w, h = size(cap)
    io = IOBuffer()
    for y in (h - 1):-1:0
        println(io, join((cap[x + 1, y + 1] for x in 0:(w - 1)), ' '))
    end
    return String(take!(io))
end

"""The seeds the committed xxl maps were generated from (printed by `julia/make_xxl_maps.jl`)."""
const XXL_TERRAIN_SEEDS = (sugar=1, spice=1001)
