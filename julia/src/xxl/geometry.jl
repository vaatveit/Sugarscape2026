# xxl: torus distances, disc offsets, ring draws and the season weight (spec, "The rules"). Pure functions; none takes a Model.

"""
    torus_delta(w, x1, x2) -> Int

The signed shortest offset from `x1` to `x2` on a ring of width `w`, in (-w/2, w/2]: a half-width apart goes positive.
"""
function torus_delta(w::Integer, x1::Integer, x2::Integer)
    d = mod(x2 - x1, w)
    return 2d > w ? d - w : d
end

"""
    torus_dist(w, h, x1, y1, x2, y2) -> Float64

The Euclidean distance between two sites on the w-by-h torus: √(dx² + dy²), each offset the shorter way round.
"""
function torus_dist(
    w::Integer, h::Integer, x1::Integer, y1::Integer, x2::Integer, y2::Integer
)
    dx = torus_delta(w, x1, x2)
    dy = torus_delta(h, y1, y2)
    return sqrt(Float64(dx * dx + dy * dy))
end

"""
    disc_offsets(r) -> Vector{Tuple{Int,Int}}

Every (dx, dy) other than (0, 0) with √(dx² + dy²) ≤ `r`, sorted by distance, then dx, then dy (all ascending). The
sort key is the integer squared distance, so ties are exact.
"""
function disc_offsets(r::Real)
    R = floor(Int, r)
    r2 = r * r
    offs = Tuple{Int,Int}[]
    for dx in (-R):R, dy in (-R):R
        (dx == 0 && dy == 0) && continue
        dx * dx + dy * dy <= r2 && push!(offs, (dx, dy))
    end
    sort!(offs; by=o -> (o[1] * o[1] + o[2] * o[2], o[1], o[2]))
    return offs
end

"""
    ring_point(rng, n, v) -> (Float64, Float64)

An offset drawn uniformly by area from the ring n < d ≤ v: two `rand(rng)` draws, u₁ then u₂, giving
ρ = √(n² + u₁(v² − n²)) and θ = 2π u₂.
"""
function ring_point(rng::AbstractRNG, n::Float64, v::Float64)
    u1 = rand(rng)
    u2 = rand(rng)
    ρ = sqrt(n * n + u1 * (v * v - n * n))
    θ = 2π * u2
    return (ρ * cos(θ), ρ * sin(θ))
end

"""
    ring_draws(v) -> Int

How many ring points a vision-`v` agent samples beyond its disc: `cld(4v, 10)`, 40% of the vision.
"""
ring_draws(v::Integer) = cld(4v, 10)

"""
    winter_weight(y, h) -> Float64

The season gradient's weight at row `y` of `h`: `abs(sinpi(2y / h))`, 0 on the equator and the poles, 1 a quarter of
the way up each hemisphere.
"""
winter_weight(y::Integer, h::Integer) = abs(sinpi(2y / h))
