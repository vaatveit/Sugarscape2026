# xxl rule 7: combat under round vision and speed (spec, "Combat (rule C)"). Rule C with the xxl look and step; the book's
# rule C (rules/combat.jl) runs when neither is on.

"""
    disc_vulnerable(m, a, x, y, reward, victim) -> Bool

Whether site (x, y) is vulnerable to retaliation for attacker `a` taking `reward` there (spec, rule 7): a fresh
[`look!`](@ref) of `a`'s vision from that site, with no remembered sites, holds an agent of another tribe, other than `a`
and `victim`, with more sugar than `a` would then have. Travel cost doesn't count, as in the book's threshold. With the
lattice look it is the book's [`vulnerable`](@ref).
"""
function disc_vulnerable(
    m::Model, a::Agent, x::Int, y::Int, reward::Float64, victim::Union{Nothing,Agent}
)
    xxl_on(m.config, :disc) || return vulnerable(m, a, x, y, reward, victim)
    after = a.sugar + reward
    mine = tribe(a)
    for (sx, sy) in look!(m.threat_looked, m, a, x, y; memory=false)
        other = @inbounds m.grid[sx + 1, sy + 1]
        other === nothing && continue
        (other === a || other === victim) && continue
        tribe(other) !== mine && other.sugar > after && return true
    end
    return false
end

# Where agent `a` would end this period if it went for the candidate at (x, y), `d` away, or `nothing` if that is
# unsafe (spec, rule 7). Within `reach` it ends on the site itself, which must not be vulnerable for `reward`. Beyond it
# the candidate is safe when the walk toward it (rule 2's step) has a landing site that is empty and not vulnerable, with
# that site's sugar as the reward; the far target itself isn't checked.
function combat_landing(
    m::Model,
    a::Agent,
    x::Int,
    y::Int,
    d::Float64,
    reach::Float64,
    reward::Float64,
    victim::Union{Nothing,Agent},
)
    if d <= reach
        return disc_vulnerable(m, a, x, y, reward, victim) ? nothing : (x, y)
    end
    sugar = m.landscape.sugar
    land = step_site(
        m,
        a,
        x,
        y;
        ok=(sx, sy) ->
            !disc_vulnerable(m, a, sx, sy, @inbounds(sugar[sx + 1, sy + 1]), nothing),
    )
    return land == (a.x, a.y) ? nothing : land
end

"""
    xxl_combat_move!(m, a)

Rule C_alpha with the xxl look and step (spec, rule 7); [`combat_move!`](@ref) calls it when round vision or speed is on.
The candidates are the agent's own site, the sites it looks at that are empty or held by an agent of another tribe with
no more sugar (with speed, an occupied one only within its speed: it won't stay put farther off), and with memory its
remembered sites beyond vision, as empty sites with their remembered sugar. A candidate is worth [`net_value`](@ref)
with the reward (the site's sugar, plus min(alpha, the occupant's sugar) if occupied) in place of the site's sugar, in
the one-commodity form. The best safe candidate wins: highest value, then nearest, then at random (a reservoir over the
safe ties). A strictly better candidate is checked for retaliation only when it would replace the best so far, a
candidate tied in value and distance always, so only safe ties count in the draw. With none safe the agent stays. A
defeated occupant loses min(alpha, its sugar) to the attacker and dies before the attacker moves onto its site and
harvests the site's sugar, with no production pollution and no income recorded, as in the book. `travel_free` records
whether the target is within `free_step`, as in [`speed_move!`](@ref).
"""
function xxl_combat_move!(m::Model, a::Agent)
    ls, alpha = m.landscape, m.config.combat_alpha
    c, free = m.config.xxl.travel_cost, m.config.xxl.free_step
    w, h = ls.width, ls.height
    mine = tribe(a)
    reach = a.speed > 0 ? Float64(a.speed) : Inf  # without speed every looked-at site is within reach (a jump)
    a.moved_dist = 0.0
    a.target_remembered = false
    looked = look!(m, a)  # first, so the look's draws don't depend on the retaliation checks
    own = ls.sugar[a.x + 1, a.y + 1]
    best_v = net_value(a, NO_WELFARE, false, c, free, 0.0, own, 0.0)
    best_d, best_land, best_victim, best_remembered = 0.0, (a.x, a.y), nothing, false
    found = !disc_vulnerable(m, a, a.x, a.y, own, nothing)
    ties = found ? 1 : 0
    for (x, y) in looked
        occupant = @inbounds m.grid[x + 1, y + 1]
        occupant === a && continue  # the own site was scored above
        d = torus_dist(w, h, a.x, a.y, x, y)
        sugar = @inbounds ls.sugar[x + 1, y + 1]
        if occupant === nothing
            reward = sugar
        elseif tribe(occupant) !== mine && occupant.sugar <= a.sugar && d <= reach
            reward = sugar + min(alpha, occupant.sugar)
        else
            continue
        end
        v = net_value(a, NO_WELFARE, false, c, free, d, reward, 0.0)
        v == -Inf && continue  # it would starve on the way
        better = !found || v > best_v || (v == best_v && d < best_d)
        tie = found && v == best_v && d == best_d
        (better || tie) || continue
        land = combat_landing(m, a, x, y, d, reach, reward, occupant)
        land === nothing && continue
        if better
            ties = 1
        else
            ties += 1
            rand(m.rng) < 1 / ties || continue
        end
        found = true
        best_v, best_d, best_land, best_victim, best_remembered = v,
        d, land, occupant,
        false
    end
    if xxl_on(m.config, :memory)  # remembered sites beyond vision: empty, with the sugar remembered
        vision = Float64(a.vision)
        for e in a.memory
            d = torus_dist(w, h, a.x, a.y, e.x, e.y)
            d > vision || continue  # within vision it was looked at afresh
            v = net_value(a, NO_WELFARE, false, c, free, d, e.sugar, 0.0)
            v == -Inf && continue
            better = !found || v > best_v || (v == best_v && d < best_d)
            tie = found && v == best_v && d == best_d
            (better || tie) || continue
            land = combat_landing(m, a, e.x, e.y, d, reach, e.sugar, nothing)
            land === nothing && continue
            if better
                ties = 1
            else
                ties += 1
                rand(m.rng) < 1 / ties || continue
            end
            found = true
            best_v, best_d, best_land, best_victim, best_remembered = v,
            d, land, nothing,
            true
        end
    end
    found || ((best_land, best_victim, best_remembered) = ((a.x, a.y), nothing, false))
    if best_victim !== nothing
        take = min(alpha, best_victim.sugar)
        best_victim.sugar -= take
        a.sugar += take
        die!(m, best_victim)
    end
    x, y = best_land
    a.moved = (x, y) != (a.x, a.y)
    a.target_remembered = best_remembered
    a.travel_free = best_d <= free
    move_agent!(m, a, x, y)
    a.sugar += ls.sugar[x + 1, y + 1]
    ls.sugar[x + 1, y + 1] = 0.0
    xxl_on(m.config, :memory) && remember!(m, a)
    return nothing
end
