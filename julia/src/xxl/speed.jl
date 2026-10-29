# xxl rule 2: speed and travel cost (spec, "Speed and travel cost"). The agent values each site it sees as if it had
# travelled there, picks a target, steps toward it as far as its speed allows, and pays for the distance it moved.

"""
    travel_periods(d, S) -> Int

How many periods a trip of distance `d` takes at speed `S`: T = max(1, ⌈d / S⌉). Without a speed (`S == 0`) every site
is reached in one period.
"""
travel_periods(d::Real, S::Integer) = S == 0 ? 1 : max(1, ceil(Int, d / S))

"""
    net_value(a, sw, two, c, d, sugar, spice) -> Float64

The core of [`net_value`](@ref)`(m, a, x, y, d, sugar, spice)`, with the agent's part of welfare (`sw`), whether spice is
on (`two`) and the travel cost per site (`c`) already in hand, so a move builds them once.
"""
function net_value(
    a::Agent,
    sw::SiteWelfare,
    two::Bool,
    c::Float64,
    d::Float64,
    sugar::Float64,
    spice::Float64,
)
    wait = travel_periods(d, a.speed) - 1  # periods spent on the way beyond the first
    m1 = sugar_burn(a)
    if !two
        h1 = a.sugar - c * d - m1 * wait  # without spice the book has no foresight: b is the holding itself
        d > 0 && h1 <= 0 && return -Inf
        return h1 + sugar
    end
    m2 = a.spice_metabolism
    if d > 0 && (a.sugar - c * d - m1 * wait <= 0 || a.spice - m2 * wait <= 0)
        return -Inf  # starves on the way, judged on what the agent really holds
    end
    h1 = sw.base1 - c * d - m1 * wait  # travel comes off after the foresight clamp
    h2 = sw.base2 - m2 * wait
    left = sw.use1 ? max(h1 + sugar, 0.0)^sw.e1 : 1.0
    right = sw.use2 ? max(h2 + spice, 0.0)^sw.e2 : 1.0
    return left * right
end

"""
    net_value(m, a, x, y, d, sugar, spice) -> Float64

What it is worth to agent `a` to arrive at site (x, y), `d` away, finding `sugar` and `spice` there (already devalued
by pollution; `spice` is ignored without spice): h₁ + sugar with one commodity, W(h₁ + sugar, h₂ + spice) with two,
where h₁ = b₁ − c·d − m₁(T − 1), h₂ = b₂ − m₂(T − 1) and b is what the holding counts for now (spec, rule 2: the clamp
of eq. 6 with spice, the holding itself without). `-Inf` if the agent would starve on the way (d > 0 only; the own site
is never dropped). With c = 0 and T = 1 this ranks sites as rule M does.
"""
function net_value(m::Model, a::Agent, x::Int, y::Int, d::Real, sugar::Real, spice::Real)
    two = m.config.spice
    sw = two ? SiteWelfare(m, a) : NO_WELFARE
    c = m.config.xxl.travel_cost
    return net_value(a, sw, two, c, Float64(d), Float64(sugar), Float64(spice))
end

"""
    step_site(m, a, tx, ty; ok=(x, y) -> true) -> (x, y)

Where agent `a` ends up when it heads for the site (tx, ty) (spec, rule 2, step). The target itself if it is within the
agent's speed, empty and `ok`. Otherwise the straight-line walk: for k = S, S − 1, …, 1 (S capped at the distance) the
site nearest to the agent's position plus k sites along the line to the target, the first that is empty, `ok` and not
its own; if there is none, its own site. It moves nothing, and never returns an occupied site.
"""
function step_site(m::Model, a::Agent, tx::Int, ty::Int; ok=(x, y) -> true)
    (tx, ty) == (a.x, a.y) && return (a.x, a.y)
    w, h = m.landscape.width, m.landscape.height
    dx, dy = torus_delta(w, a.x, tx), torus_delta(h, a.y, ty)
    d = sqrt(Float64(dx * dx + dy * dy))
    if d <= a.speed && m.grid[tx + 1, ty + 1] === nothing && ok(tx, ty)
        return (tx, ty)
    end
    for k in min(a.speed, floor(Int, d)):-1:1
        x, y = wrap(m, round(Int, a.x + k * dx / d), round(Int, a.y + k * dy / d))
        (x, y) == (a.x, a.y) && continue
        m.grid[x + 1, y + 1] === nothing && ok(x, y) && return (x, y)
    end
    return (a.x, a.y)
end

"""
    speed_move!(m, a)

[`xxl_move!`](@ref) with speed (spec, rule 2). The candidates are the agent's own site and the empty sites it looks at;
it targets the one of highest [`net_value`](@ref), ties going to the nearest by torus distance, then at random (a
reservoir: the c-th tie replaces the choice with probability 1/c, one draw each). It steps toward the target with
[`step_site`](@ref) and harvests where it lands. [`metabolize!`](@ref) charges the distance moved.
"""
function speed_move!(m::Model, a::Agent)
    ls = m.landscape
    spice = m.config.spice
    c = m.config.xxl.travel_cost
    w, h = ls.width, ls.height
    a.moved_dist = 0.0
    a.target_remembered = false
    sw = spice ? SiteWelfare(m, a) : NO_WELFARE
    best_x, best_y, best_d = a.x, a.y, 0.0
    best = site_value(a, sw, spice, c, ls, a.x, a.y, 0.0)
    ties = 1
    for (x, y) in look!(m, a)
        @inbounds m.grid[x + 1, y + 1] === nothing || continue  # the agent's own site is occupied by itself
        d = torus_dist(w, h, a.x, a.y, x, y)
        v = site_value(a, sw, spice, c, ls, x, y, d)
        if v > best || (v == best && d < best_d)
            best, best_x, best_y, best_d, ties = v, x, y, d, 1
        elseif v == best && d == best_d
            ties += 1
            rand(m.rng) < 1 / ties && ((best_x, best_y) = (x, y))
        end
    end
    x, y = step_site(m, a, best_x, best_y)
    a.moved = (x, y) != (a.x, a.y)
    move_agent!(m, a, x, y)
    harvest!(m, a, x, y)
    return nothing
end

# The net value of site (x, y), `d` away, with its resources devalued by the pollution there.
@inline function site_value(
    a::Agent,
    sw::SiteWelfare,
    two::Bool,
    c::Float64,
    ls::Landscape,
    x::Int,
    y::Int,
    d::Float64,
)
    devalue = 1.0 + @inbounds ls.pollution[x + 1, y + 1]
    sugar = @inbounds ls.sugar[x + 1, y + 1] / devalue
    spice = two ? @inbounds(ls.spice[x + 1, y + 1]) / devalue : 0.0
    return net_value(a, sw, two, c, d, sugar, spice)
end
