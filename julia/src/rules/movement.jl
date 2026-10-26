# Agent movement rule M, harvesting, metabolism, and pollution formation P (sugarscape/rules/movement.py).
#
# M (p.25, App. B p.182): look out as far as vision permits in the four lattice directions; considering only
# unoccupied positions, find the nearest position of maximum welfare; move there and collect all the resources. The
# direction search order is random (fn 8); ties at equal distance go to the first site encountered (fn 9).

function pollution_active(m::Model)
    cfg = m.config
    (cfg.pollution === nothing || m.t < cfg.pollution_start) && return false
    return cfg.pollution_stop === nothing || m.t < cfg.pollution_stop
end

"""
    look_distance(rng, stride, k)

The distance of an agent's k-th look (k = 1, 2, ...) along one lattice line: k with a stride of 1, which draws
nothing, or with a stride s > 1 (xl), s k + a - b with a and b uniform on 0 … s - 1: where a random site of the
regular cell k away lies from a random site of one's own cell (docs/xl.md, "Looking"). A line of vision v has
v ÷ stride looks.
"""
@inline function look_distance(rng::AbstractRNG, stride::Int, k::Int)
    stride == 1 && return k
    return stride * k + rand(rng, 0:(stride - 1)) - rand(rng, 0:(stride - 1))
end

"""Inserts `x` into the sorted `v[1:len]` unless it is there already; returns the new length. `v` has room."""
@inline function insert_sorted!(v::Vector{Int}, len::Int, x::Int)
    i = len
    @inbounds while i > 0 && v[i] > x
        i -= 1
    end
    @inbounds i > 0 && v[i] == x && return len
    @inbounds for j in len:-1:(i + 1)
        v[j + 1] = v[j]
    end
    @inbounds v[i + 1] = x
    return len + 1
end

"""
    look_line!(v, rng, stride, vision) -> v

The distances of one lattice line's looks, into `v`, nearest first (Python's `look_distances`). Looks overlap with
a stride above 1, so a distance drawn twice is looked at once.
"""
function look_line!(v::Vector{Int}, rng::AbstractRNG, stride::Int, vision::Int)
    n = vision ÷ stride
    resize!(v, n)
    len = 0
    for k in 1:n
        len = insert_sorted!(v, len, look_distance(rng, stride, k))
    end
    return resize!(v, len)
end

"""The distances of every look along one lattice line, nearest first (Python's `look_distances`)."""
function look_distances(m::Model, vision::Int)
    return look_line!(Int[], m.rng, m.config.look_stride, vision)
end

"""Sugar-to-pollution ratio s/(1+p) (p.47 fn 37); equals plain sugar while p = 0."""
@inline site_score(ls::Landscape, i::Int, j::Int) =
    @inbounds ls.sugar[i, j] / (1.0 + ls.pollution[i, j])

"""
    move!(m, a)

Rule M: go to the nearest best site in view and harvest it (p.25). The agent's own site is scanned first at distance
0 (a move to it means staying; Kehoe's reading), then each direction in a random order, out to vision. Strict
comparisons keep the first site encountered on ties. On the sugar-and-spice landscape the score is the welfare
the site's resources would bring (`welfare_score`, Chapter IV).
"""
function move!(m::Model, a::Agent)
    ls = m.landscape
    spice = m.config.spice
    w, h = ls.width, ls.height
    best_x, best_y, best_d = a.x, a.y, 0
    sw = spice ? SiteWelfare(m, a) : NO_WELFARE  # the agent's part of welfare_score, once per move
    best = spice ? score(sw, ls, a.x + 1, a.y + 1) : site_score(ls, a.x + 1, a.y + 1)
    stride = m.config.look_stride
    for d in random_directions(m.rng)
        dx, dy = @inbounds VON_NEUMANN[d]
        for dist in look_line!(m.line, m.rng, stride, a.vision)
            x = mod(a.x + dx * dist, w)
            y = mod(a.y + dy * dist, h)
            @inbounds m.grid[x + 1, y + 1] === nothing || continue
            s = spice ? score(sw, ls, x + 1, y + 1) : site_score(ls, x + 1, y + 1)
            if s > best || (s == best && dist < best_d)
                best, best_x, best_y, best_d = s, x, y, dist
            end
        end
    end
    a.moved = (best_x, best_y) != (a.x, a.y)
    move_agent!(m, a, best_x, best_y)

    i, j = best_x + 1, best_y + 1
    harvest = ls.sugar[i, j]
    a.sugar += harvest
    ls.sugar[i, j] = 0.0
    a.last_income = harvest  # metabolize! subtracts metabolism
    if spice
        a.spice += ls.spice[i, j]
        ls.spice[i, j] = 0.0
    end
    if pollution_active(m)
        ls.pollution[i, j] += m.config.pollution[1] * harvest  # production pollution (p.47)
    end
    return nothing
end

"""
    metabolize!(m, a)

Burn sugar (and spice) at the metabolic rates; die when either reaches zero (p.25, p.97). Pollution comes from sugar
only: spice is a clean good (p.127).
"""
function metabolize!(m::Model, a::Agent)
    burn = sugar_burn(a)  # metabolism plus the fee for each active disease (p.143)
    a.sugar -= burn
    a.last_income -= burn
    spice = m.config.spice
    spice && (a.spice -= a.spice_metabolism)
    if pollution_active(m)
        m.landscape.pollution[a.x + 1, a.y + 1] += m.config.pollution[2] * burn  # consumption (p.47)
    end
    (a.sugar <= 0 || (spice && a.spice <= 0)) && die!(m, a)
    return nothing
end
