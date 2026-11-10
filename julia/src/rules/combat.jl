# Agent combat rule C_alpha (pp.82-83, App. B p.183-184; sugarscape/rules/combat.py). Replaces movement M.

"""
    combat_wealth(a, spice) -> Float64

The wealth combat compares: the agent's sugar, plus its spice on the sugar-and-spice landscape (our call; the book
defines combat for sugar only, p.83). Welfare isn't comparable across agents, since it rests on each one's metabolisms.
"""
combat_wealth(a::Agent, spice::Bool) = spice ? a.sugar + a.spice : a.sugar

"""
    loot(m, victim) -> (sugar, spice)

What rule C_alpha takes from a defeated `victim`: min(alpha, its sugar), and min(alpha, its spice) with spice on (0
without). A good the victim holds less than nothing of (spice can be below 0 until its owner's own turn, after a gift to
a child in rule S) yields 0: there is nothing to take, and a negative loot would feed a negative amount to the welfare.
"""
function loot(m::Model, victim::Agent)
    alpha = m.config.combat_alpha
    return (max(0.0, min(alpha, victim.sugar)), m.config.spice ? max(0.0, min(alpha, victim.spice)) : 0.0)
end

"""
    take_loot!(m, a, victim)

`a` takes the [`loot`](@ref) from `victim`, which is then killed: recorded in `m.killed` and removed through
[`die!`](@ref), so its loans are settled as on any death. Both combat moves kill here, so the kill is also logged in
`m.kill_log` as (distance, same_label): the number of tags where killer and victim differ, and 1 if they are of one
tribe, read before the victim dies.
"""
function take_loot!(m::Model, a::Agent, victim::Agent)
    g1, g2 = loot(m, victim)
    victim.sugar -= g1
    a.sugar += g1
    if m.config.spice
        victim.spice -= g2
        a.spice += g2
    end
    push!(m.killed, victim.id)  # for the combat readings' and the scorecard's deaths by cause
    push!(m.kill_log, (count_ones(a.tags ⊻ victim.tags), tribe(a) === tribe(victim) ? 1 : 0))  # the kills file
    die!(m, victim)
    return nothing
end

"""
    fight_chance(h, a, b, k=1.0) -> Float64

The chance that `a` is hostile to `b` under combat by cultural distance: h (d / L)^k, d the number of tags where they
differ, L the tag length (`a.ntags`) and k the curve (`combat_curve`). Identical agents never fight; agents that differ
everywhere fight with probability h. With k = 1 it is h d / L, computed as it always was, so linear runs don't change;
a larger k makes agents a few tags apart fight far less than agents far apart.
"""
function fight_chance(h::Float64, a::Agent, b::Agent, k::Float64=1.0)
    d = count_ones(a.tags ⊻ b.tags)
    k == 1.0 && return h * d / a.ntags
    return h * (d / a.ntags)^k
end

"""
    hostile!(m, a, other) -> Bool

Whether `a` treats `other` as an enemy in this move, as a possible victim or a possible avenger. With
`combat_hostility` 0 it is the tribe test, `tribe(other) !== tribe(a)`, with no draw. Above 0 it is a draw from
`m.rng` with probability [`fight_chance`](@ref); the first call for `other` in a move draws and the answer is kept
in `m.hostile` for the rest of the move (one draw per pair per move), which [`combat_move!`](@ref) empties at its
start.
"""
function hostile!(m::Model, a::Agent, other::Agent)
    h = m.config.combat_hostility
    h == 0 && return tribe(other) !== tribe(a)
    k = m.config.combat_curve
    return get!(() -> rand(m.rng) < fight_chance(h, a, other, k), m.hostile, other.id)
end

"""
The one distance scanned along each lattice line with `combat_reach` "neighbours" (VI-1-near): the adjacent site,
whatever vision and `look_stride`. Read only.
"""
const ADJACENT = [1]

"""
    combat_line!(m, buf, a) -> Vector{Int}

The distances [`combat_move!`](@ref) and [`vulnerable`](@ref) scan along one lattice line: with `combat_reach`
"vision" the looks out to `a.vision` ([`look_line!`](@ref) into `buf`, with its stride draws); with "neighbours"
(VI-1-near) distance 1 only ([`ADJACENT`](@ref)), with no draw.
"""
@inline function combat_line!(m::Model, buf::Vector{Int}, a::Agent)
    m.config.combat_reach == "neighbours" && return ADJACENT
    return look_line!(buf, m.rng, m.config.look_stride, a.vision)
end

"""
    vulnerable(m, a, x, y, reward, victim)

A site is vulnerable to retaliation if an agent within the attacker's vision of that site would be bigger than the
attacker after taking it and the attacker is [`hostile!`](@ref) to it: of another tribe, or with `combat_hostility`
above 0 a draw on cultural distance, made only for a watcher that passes the size test (p.82; Kehoe on the
viewpoint). Size is [`combat_wealth`](@ref) and `reward` is in its units: the site's goods plus the loot. With
`combat_reach` "neighbours" (VI-1-near) only the 4 sites adjacent to it are watched ([`combat_line!`](@ref)).
"""
function vulnerable(
    m::Model, a::Agent, x::Int, y::Int, reward::Float64, victim::Union{Nothing,Agent}
)
    spice = m.config.spice
    after = combat_wealth(a, spice) + reward
    for (dx, dy) in VON_NEUMANN
        # Each direction draws its own looks (docs/xl.md), into a buffer of its own: combat_move! is mid-line in m.line.
        for dist in combat_line!(m, m.threat, a)
            other = agent_at(m, x + dx * dist, y + dy * dist)
            other === nothing && continue
            (other === a || other === victim) && continue
            combat_wealth(other, spice) > after && hostile!(m, a, other) && return true
        end
    end
    return false
end

"""
    combat_move!(m, a)

Rule C_alpha: take the nearest safe site of maximum value; a defeated occupant is killed. Candidates are scanned as
in M: the current site first at distance 0, then each direction in random order out to vision; with `combat_reach`
"neighbours" (VI-1-near) the direction order is drawn as before but only distance 1 is scanned
([`combat_line!`](@ref)). Sites held by anyone wealthier ([`combat_wealth`](@ref)) or by an agent the mover isn't
[`hostile!`](@ref) to (its own tribe, or with `combat_hostility` above 0 a failed draw on cultural distance, made only
after the wealth test) are thrown out, and sight continues past them.
Without spice the value is the reward, site sugar + min(alpha, occupant's sugar) if occupied. With spice it is the
book's welfare score of the site's goods plus the [`loot`](@ref), as `move!` scores sites, and the reward checked for
retaliation is the site's sugar and spice plus the loot. With no safe site the agent stays and harvests where it is
(Kehoe; harvesting is our call). The landing harvests through [`harvest!`](@ref), so the loot isn't income.

Python checks every candidate for retaliation, then picks; here only a candidate that would replace the best safe
one so far is checked, which picks the same site.

This move's hostility answers (`m.hostile`) are emptied first, so no draw answers another agent's move. With xxl
round vision or speed on, [`xxl_combat_move!`](@ref) runs instead.
"""
function combat_move!(m::Model, a::Agent)
    isempty(m.hostile) || empty!(m.hostile)
    (xxl_on(m.config, :disc) || xxl_on(m.config, :speed)) && return xxl_combat_move!(m, a)
    ls = m.landscape
    w, h = ls.width, ls.height
    spice = m.config.spice
    wealth = combat_wealth(a, spice)
    # The agent's part of the welfare score, once per move, as in move!
    sw = spice ? SiteWelfare(m, a, NO_SITES) : NO_WELFARE
    i0, j0 = a.x + 1, a.y + 1
    own = spice ? ls.sugar[i0, j0] + ls.spice[i0, j0] : ls.sugar[i0, j0]
    found = !vulnerable(m, a, a.x, a.y, own, nothing)
    best_x, best_y, best_d, best_victim = a.x, a.y, 0, nothing
    best_v = spice ? score(sw, ls, i0, j0) : own
    for d in random_directions(m.rng)
        dx, dy = @inbounds VON_NEUMANN[d]
        for dist in combat_line!(m, m.line, a)
            x, y = mod(a.x + dx * dist, w), mod(a.y + dy * dist, h)
            occupant = @inbounds m.grid[x + 1, y + 1]
            if occupant === nothing
                g1, g2 = 0.0, 0.0
                reward = ls.sugar[x + 1, y + 1]
            elseif combat_wealth(occupant, spice) <= wealth && hostile!(m, a, occupant)
                g1, g2 = loot(m, occupant)
                reward = ls.sugar[x + 1, y + 1] + g1
            else
                continue
            end
            if spice
                reward += ls.spice[x + 1, y + 1] + g2
                v = score(sw, ls, x + 1, y + 1, g1, g2)
            else
                v = reward
            end
            better = !found || v > best_v || (v == best_v && dist < best_d)
            better || continue
            vulnerable(m, a, x, y, reward, occupant) && continue
            found = true
            best_x, best_y, best_d, best_v, best_victim = x, y, dist, v, occupant
        end
    end
    if !found  # nothing is safe: stay (the current site, as Python's candidates[0])
        best_x, best_y, best_victim = a.x, a.y, nothing
    end
    best_victim === nothing || take_loot!(m, a, best_victim)
    a.moved = (best_x, best_y) != (a.x, a.y)
    move_agent!(m, a, best_x, best_y)
    harvest!(m, a, best_x, best_y)
    return nothing
end
