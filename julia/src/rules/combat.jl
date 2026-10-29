# Agent combat rule C_alpha (pp.82-83, App. B p.183-184; sugarscape/rules/combat.py). Replaces movement M.

"""
    vulnerable(m, a, x, y, reward, victim)

A site is vulnerable to retaliation if an agent of another tribe within the attacker's vision of that site would be
bigger than the attacker after taking it (p.82; Kehoe on the viewpoint).
"""
function vulnerable(
    m::Model, a::Agent, x::Int, y::Int, reward::Float64, victim::Union{Nothing,Agent}
)
    after = a.sugar + reward
    mine = tribe(a)
    stride = m.config.look_stride
    for (dx, dy) in VON_NEUMANN
        # Each direction draws its own looks (docs/xl.md), into a buffer of its own: combat_move! is mid-line in m.line.
        for dist in look_line!(m.threat, m.rng, stride, a.vision)
            other = agent_at(m, x + dx * dist, y + dy * dist)
            other === nothing && continue
            (other === a || other === victim) && continue
            tribe(other) !== mine && other.sugar > after && return true
        end
    end
    return false
end

"""
    combat_move!(m, a)

Rule C_alpha: take the nearest safe site of maximum reward; a defeated occupant is killed. Candidates are scanned as
in M: the current site first at distance 0, then each direction in random order out to vision. Sites held by the
agent's own tribe or by anyone wealthier are thrown out, and sight continues past them. Reward = site sugar +
min(alpha, occupant's wealth) if occupied. With no safe site the agent stays and harvests where it is (Kehoe;
harvesting is our call).

Python checks every candidate for retaliation, then picks; here only a candidate that would replace the best safe
one so far is checked, which picks the same site.

With xxl round vision or speed on, [`xxl_combat_move!`](@ref) runs instead.
"""
function combat_move!(m::Model, a::Agent)
    (xxl_on(m.config, :disc) || xxl_on(m.config, :speed)) && return xxl_combat_move!(m, a)
    ls, alpha = m.landscape, m.config.combat_alpha
    w, h = ls.width, ls.height
    mine = tribe(a)
    own = ls.sugar[a.x + 1, a.y + 1]
    found = !vulnerable(m, a, a.x, a.y, own, nothing)
    best_x, best_y, best_d, best_r, best_v = a.x, a.y, 0, own, nothing
    stride = m.config.look_stride
    for d in random_directions(m.rng)
        dx, dy = @inbounds VON_NEUMANN[d]
        for dist in look_line!(m.line, m.rng, stride, a.vision)
            x, y = mod(a.x + dx * dist, w), mod(a.y + dy * dist, h)
            occupant = @inbounds m.grid[x + 1, y + 1]
            if occupant === nothing
                reward = ls.sugar[x + 1, y + 1]
            elseif tribe(occupant) !== mine && occupant.sugar <= a.sugar
                reward = ls.sugar[x + 1, y + 1] + min(alpha, occupant.sugar)
            else
                continue
            end
            better = !found || reward > best_r || (reward == best_r && dist < best_d)
            better || continue
            vulnerable(m, a, x, y, reward, occupant) && continue
            found = true
            best_x, best_y, best_d, best_r, best_v = x, y, dist, reward, occupant
        end
    end
    if !found  # nothing is safe: stay (the current site, as Python's candidates[0])
        best_x, best_y, best_v = a.x, a.y, nothing
    end
    if best_v !== nothing
        take = min(alpha, best_v.sugar)
        best_v.sugar -= take
        a.sugar += take
        die!(m, best_v)
    end
    a.moved = (best_x, best_y) != (a.x, a.y)
    move_agent!(m, a, best_x, best_y)
    a.sugar += ls.sugar[best_x + 1, best_y + 1]
    ls.sugar[best_x + 1, best_y + 1] = 0.0
    return nothing
end
