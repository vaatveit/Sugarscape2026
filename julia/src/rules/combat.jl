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
[`die!`](@ref), so its loans are settled as on any death.
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
    die!(m, victim)
    return nothing
end

"""
    vulnerable(m, a, x, y, reward, victim)

A site is vulnerable to retaliation if an agent of another tribe within the attacker's vision of that site would be
bigger than the attacker after taking it (p.82; Kehoe on the viewpoint). Size is [`combat_wealth`](@ref) and `reward`
is in its units: the site's goods plus the loot.
"""
function vulnerable(
    m::Model, a::Agent, x::Int, y::Int, reward::Float64, victim::Union{Nothing,Agent}
)
    spice = m.config.spice
    after = combat_wealth(a, spice) + reward
    mine = tribe(a)
    stride = m.config.look_stride
    for (dx, dy) in VON_NEUMANN
        # Each direction draws its own looks (docs/xl.md), into a buffer of its own: combat_move! is mid-line in m.line.
        for dist in look_line!(m.threat, m.rng, stride, a.vision)
            other = agent_at(m, x + dx * dist, y + dy * dist)
            other === nothing && continue
            (other === a || other === victim) && continue
            tribe(other) !== mine && combat_wealth(other, spice) > after && return true
        end
    end
    return false
end

"""
    combat_move!(m, a)

Rule C_alpha: take the nearest safe site of maximum value; a defeated occupant is killed. Candidates are scanned as
in M: the current site first at distance 0, then each direction in random order out to vision. Sites held by the
agent's own tribe or by anyone wealthier ([`combat_wealth`](@ref)) are thrown out, and sight continues past them.
Without spice the value is the reward, site sugar + min(alpha, occupant's sugar) if occupied. With spice it is the
book's welfare score of the site's goods plus the [`loot`](@ref), as `move!` scores sites, and the reward checked for
retaliation is the site's sugar and spice plus the loot. With no safe site the agent stays and harvests where it is
(Kehoe; harvesting is our call). The landing harvests through [`harvest!`](@ref), so the loot isn't income.

Python checks every candidate for retaliation, then picks; here only a candidate that would replace the best safe
one so far is checked, which picks the same site.

With xxl round vision or speed on, [`xxl_combat_move!`](@ref) runs instead.
"""
function combat_move!(m::Model, a::Agent)
    (xxl_on(m.config, :disc) || xxl_on(m.config, :speed)) && return xxl_combat_move!(m, a)
    ls = m.landscape
    w, h = ls.width, ls.height
    spice = m.config.spice
    mine = tribe(a)
    wealth = combat_wealth(a, spice)
    # The agent's part of the welfare score, once per move, as in move!
    sw = spice ? SiteWelfare(m, a, NO_SITES) : NO_WELFARE
    i0, j0 = a.x + 1, a.y + 1
    own = spice ? ls.sugar[i0, j0] + ls.spice[i0, j0] : ls.sugar[i0, j0]
    found = !vulnerable(m, a, a.x, a.y, own, nothing)
    best_x, best_y, best_d, best_victim = a.x, a.y, 0, nothing
    best_v = spice ? score(sw, ls, i0, j0) : own
    stride = m.config.look_stride
    for d in random_directions(m.rng)
        dx, dy = @inbounds VON_NEUMANN[d]
        for dist in look_line!(m.line, m.rng, stride, a.vision)
            x, y = mod(a.x + dx * dist, w), mod(a.y + dy * dist, h)
            occupant = @inbounds m.grid[x + 1, y + 1]
            if occupant === nothing
                g1, g2 = 0.0, 0.0
                reward = ls.sugar[x + 1, y + 1]
            elseif tribe(occupant) !== mine && combat_wealth(occupant, spice) <= wealth
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
