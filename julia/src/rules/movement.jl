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

The distance of an agent's k-th look (k = 0, 1, ...) along one lattice line: k + 1 with a stride of 1, which draws
nothing, or one site drawn uniformly from the stretch stride k + 1 .. stride (k + 1) (docs/xl.md, "Looking"). A
line of vision v has v ÷ stride looks.
"""
@inline function look_distance(rng::AbstractRNG, stride::Int, k::Int)
    return stride == 1 ? k + 1 : stride * k + rand(rng, 1:stride)
end

"""The distances of every look along one lattice line, nearest first (Python's `look_distances`)."""
function look_distances(m::Model, vision::Int)
    s = m.config.look_stride
    return [look_distance(m.rng, s, k) for k in 0:(vision ÷ s - 1)]
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
        for k in 0:(a.vision ÷ stride - 1)
            dist = look_distance(m.rng, stride, k)
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
