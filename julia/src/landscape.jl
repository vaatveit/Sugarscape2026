# The sugarscape lattice: resource levels, capacities, pollution, and the site rules (sugarscape/landscape.py).
# Arrays are indexed [x + 1, y + 1]; x east, y north, y = 0 the southern row.

mutable struct Landscape
    width::Int
    height::Int
    capacity::Matrix{Int}
    spice_capacity::Matrix{Int}
    sugar::Matrix{Float64}
    spice::Matrix{Float64}
    pollution::Matrix{Float64}
    scratch::Matrix{Float64}  # diffusion's second buffer
end

function Landscape(capacity::AbstractMatrix{<:Integer}, spice_capacity=nothing)
    cap = Matrix{Int}(capacity)
    scap = spice_capacity === nothing ? zeros(Int, size(cap)) : Matrix{Int}(spice_capacity)
    size(scap) == size(cap) ||
        throw(ArgumentError("spice capacity must match the sugar map"))
    w, h = size(cap)
    # p.21: "the sugar level at every site initially at its capacity value".
    return Landscape(
        w, h, cap, scap, Float64.(cap), Float64.(scap), zeros(w, h), zeros(w, h)
    )
end

"""Spice capacity and level (p.96: each site has a spice level and capacity), the level starting full."""
function set_spice!(ls::Landscape, spice_capacity::AbstractMatrix{<:Integer})
    size(spice_capacity) == size(ls.capacity) ||
        throw(ArgumentError("spice capacity must match the sugar map"))
    ls.spice_capacity = Matrix{Int}(spice_capacity)
    ls.spice = Float64.(ls.spice_capacity)
    return ls
end

wrap(ls::Landscape, x::Int, y::Int) = (mod(x, ls.width), mod(y, ls.height))

"""G_alpha (p.23 fn 3): r(t+1) = min(r(t) + alpha, c); alpha = Inf gives G_inf (p.26)."""
function growback!(ls::Landscape, rate::Float64)
    @inbounds for i in eachindex(ls.sugar)
        ls.sugar[i] = min(ls.sugar[i] + rate, ls.capacity[i])
        ls.spice[i] = min(ls.spice[i] + rate, ls.spice_capacity[i])
    end
    return ls
end

"""p.44 fn 33: the top half is in summer while (t mod 2 gamma) / gamma < 1."""
is_summer_north(t::Int, gamma::Int) = mod(t, 2 * gamma) < gamma

"""
    seasonal_growback!(ls, t, alpha, beta, gamma, winter)

S_alpha,beta,gamma (p.44): summer grows alpha per period, winter alpha per beta periods. `winter = "fractional"`
adds alpha/beta each period; `"pulse"` adds alpha on periods where t % beta == 0. Spice follows the same rule.
"""
function seasonal_growback!(
    ls::Landscape, t::Int, alpha::Float64, beta::Int, gamma::Int, winter::String
)
    winter_rate = winter == "fractional" ? alpha / beta : (mod(t, beta) == 0 ? alpha : 0.0)
    north_summer = is_summer_north(t, gamma)
    half = ls.height ÷ 2
    @inbounds for j in 1:ls.height
        north = j - 1 >= half
        rate = north == north_summer ? alpha : winter_rate
        for i in 1:ls.width
            ls.sugar[i, j] = min(ls.sugar[i, j] + rate, ls.capacity[i, j])
            ls.spice[i, j] = min(ls.spice[i, j] + rate, ls.spice_capacity[i, j])
        end
    end
    return ls
end

"""
    seasonal_growback_gradient!(ls, t, alpha, beta, gamma)

Rule 5 of the xxl set (spec, "Seasons by latitude"): the halves and their summers are those of
[`seasonal_growback!`](@ref), but a row `j` in winter grows `alpha * beta^(-winter_weight(j - 1, height))` per period,
so the rate runs from alpha at the equators (y = 0 and y = H/2) to the book's alpha/beta along the middle of each half.
Only the fractional winter is defined. Spice follows the same rule.
"""
function seasonal_growback_gradient!(
    ls::Landscape, t::Int, alpha::Float64, beta::Int, gamma::Int
)
    north_summer = is_summer_north(t, gamma)
    h = ls.height
    half = h ÷ 2
    @inbounds for j in 1:h
        north = j - 1 >= half
        rate = north == north_summer ? alpha : alpha * beta^(-winter_weight(j - 1, h))
        for i in 1:ls.width
            ls.sugar[i, j] = min(ls.sugar[i, j] + rate, ls.capacity[i, j])
            ls.spice[i, j] = min(ls.spice[i, j] + rate, ls.spice_capacity[i, j])
        end
    end
    return ls
end

"""D_alpha (p.48): each site's new pollution is the mean over its von Neumann neighbours, on the torus."""
function diffuse!(ls::Landscape)
    p, out = ls.pollution, ls.scratch
    w, h = ls.width, ls.height
    @inbounds for j in 1:h
        jn = j == h ? 1 : j + 1
        js = j == 1 ? h : j - 1
        for i in 1:w
            ie = i == w ? 1 : i + 1
            iw = i == 1 ? w : i - 1
            # Python's order: roll(p, 1, axis=0) + roll(p, -1, axis=0) + roll(p, 1, axis=1) + roll(p, -1, axis=1).
            out[i, j] = (p[iw, j] + p[ie, j] + p[i, js] + p[i, jn]) / 4.0
        end
    end
    ls.pollution, ls.scratch = out, p
    return ls
end
