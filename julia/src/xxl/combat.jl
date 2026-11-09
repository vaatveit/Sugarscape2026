# xxl rule 7: combat under round vision and speed (spec, "Combat (rule C)"). Rule C with the xxl look and step; the book's
# rule C (rules/combat.jl) runs when neither is on.

"""
    disc_vulnerable(m, a, x, y, reward, victim) -> Bool

Whether site (x, y) is vulnerable to retaliation for attacker `a` taking `reward` there (spec, rule 7): a fresh
[`look!`](@ref) of `a`'s vision from that site, with no remembered sites, holds an agent of another tribe, other than `a`
and `victim`, with more wealth ([`combat_wealth`](@ref)) than `a` would then have; `reward` is in the same units (the
site's goods plus the loot). Travel cost doesn't count, as in the book's threshold. With the lattice look it is the
book's [`vulnerable`](@ref).
"""
function disc_vulnerable(
    m::Model, a::Agent, x::Int, y::Int, reward::Float64, victim::Union{Nothing,Agent}
)
    xxl_on(m.config, :disc) || return vulnerable(m, a, x, y, reward, victim)
    spice = m.config.spice
    after = combat_wealth(a, spice) + reward
    mine = tribe(a)
    for (sx, sy) in look!(m.threat_looked, m, a, x, y; memory=false)
        other = @inbounds m.grid[sx + 1, sy + 1]
        other === nothing && continue
        (other === a || other === victim) && continue
        tribe(other) !== mine && combat_wealth(other, spice) > after && return true
    end
    return false
end

# Where agent `a` would end this period if it went for the candidate at (x, y), `d` away, or `nothing` if that is
# unsafe (spec, rule 7). Within `reach` it ends on the site itself, which must not be vulnerable for `reward`. Beyond it
# the candidate is safe when the walk toward it (rule 2's step) has a landing site that is empty and not vulnerable, with
# that site's goods (its sugar, and its spice with spice on) as the reward; the far target itself isn't checked.
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
    sugar, spice = m.landscape.sugar, m.landscape.spice
    two = m.config.spice
    goods(sx, sy) =
        two ? @inbounds(sugar[sx + 1, sy + 1] + spice[sx + 1, sy + 1]) :
        @inbounds(sugar[sx + 1, sy + 1])
    land = step_site(
        m, a, x, y; ok=(sx, sy) -> !disc_vulnerable(m, a, sx, sy, goods(sx, sy), nothing)
    )
    return land == (a.x, a.y) ? nothing : land
end

"""
    xxl_combat_move!(m, a)

Rule C_alpha with the xxl look and step (spec, rule 7); [`combat_move!`](@ref) calls it when round vision or speed is on.
The candidates are the agent's own site, the sites it looks at that are empty or held by an agent of another tribe with
no more wealth ([`combat_wealth`](@ref); with speed, an occupied one only within its speed: it won't stay put farther
off), and with memory its remembered sites beyond vision, as empty sites with their remembered resources. A candidate
is worth [`net_value`](@ref) with the site's resources plus the occupant's [`loot`](@ref) if occupied: without spice
the reward (the site's sugar plus the loot) in the one-commodity form, as in the book; with spice the agent's
[`SiteWelfare`](@ref) of the site's sugar and spice, devalued by its pollution (a remembered site's by the pollution
remembered), plus the loot, which isn't devalued (VI-1 combat design, "The rule"). The best safe candidate wins:
highest value, then nearest, then at random (a reservoir over the safe ties). A strictly better candidate is checked
for retaliation only when it would replace the best so far, a candidate tied in value and distance always, so only safe
ties count in the draw; the reward checked is in wealth units, the site's goods plus the loot. With none safe the agent
stays. A defeated occupant gives up its loot and dies ([`take_loot!`](@ref)) before the attacker moves onto its site and
harvests it through [`harvest!`](@ref), so the loot isn't income. `travel_free` records whether the target is within
`free_step`, as in [`speed_move!`](@ref). With spice the move's blend and price go to `m.move_lambda` and
`m.move_inv_p`, and [`remember!`](@ref) gets the move's welfare, as in `speed_move!`.
"""
function xxl_combat_move!(m::Model, a::Agent)
    ls = m.landscape
    spice = m.config.spice
    c, free = m.config.xxl.travel_cost, m.config.xxl.free_step
    w, h = ls.width, ls.height
    mine = tribe(a)
    wealth = combat_wealth(a, spice)
    reach = a.speed > 0 ? Float64(a.speed) : Inf  # without speed every looked-at site is within reach (a jump)
    a.moved_dist = 0.0
    a.target_remembered = false
    looked = look!(m, a)  # first, so the look's draws don't depend on the retaliation checks
    sw = spice ? SiteWelfare(m, a, looked) : NO_WELFARE  # after the look, as speed_move!; it draws nothing
    spice && ((m.move_lambda, m.move_inv_p) = (sw.lambda, sw.inv_p))
    i0, j0 = a.x + 1, a.y + 1
    own = spice ? ls.sugar[i0, j0] + ls.spice[i0, j0] : ls.sugar[i0, j0]
    best_v = if spice
        site_value(a, sw, true, c, free, ls, a.x, a.y, 0.0)
    else
        net_value(a, NO_WELFARE, false, c, free, 0.0, own, 0.0)
    end
    best_d, best_land, best_victim, best_remembered = 0.0, (a.x, a.y), nothing, false
    found = !disc_vulnerable(m, a, a.x, a.y, own, nothing)
    ties = found ? 1 : 0
    for (x, y) in looked
        occupant = @inbounds m.grid[x + 1, y + 1]
        occupant === a && continue  # the own site was scored above
        d = torus_dist(w, h, a.x, a.y, x, y)
        sugar = @inbounds ls.sugar[x + 1, y + 1]
        if occupant === nothing
            g1, g2 = 0.0, 0.0
        elseif tribe(occupant) !== mine && combat_wealth(occupant, spice) <= wealth && d <= reach
            g1, g2 = loot(m, occupant)
        else
            continue
        end
        reward = sugar + g1
        if spice
            site_spice = @inbounds ls.spice[x + 1, y + 1]
            reward += site_spice + g2
            devalue = 1.0 + @inbounds ls.pollution[x + 1, y + 1]
            v = net_value(a, sw, true, c, free, d, sugar / devalue + g1, site_spice / devalue + g2)
        else
            v = net_value(a, NO_WELFARE, false, c, free, d, reward, 0.0)
        end
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
    if xxl_on(m.config, :memory)  # remembered sites beyond vision: empty, with the resources remembered
        vision = Float64(a.vision)
        for e in a.memory
            d = torus_dist(w, h, a.x, a.y, e.x, e.y)
            d > vision || continue  # within vision it was looked at afresh
            if spice
                devalue = 1.0 + e.pollution
                v = net_value(a, sw, true, c, free, d, e.sugar / devalue, e.spice / devalue)
                reward = e.sugar + e.spice
            else
                v = net_value(a, NO_WELFARE, false, c, free, d, e.sugar, 0.0)
                reward = e.sugar
            end
            v == -Inf && continue
            better = !found || v > best_v || (v == best_v && d < best_d)
            tie = found && v == best_v && d == best_d
            (better || tie) || continue
            land = combat_landing(m, a, e.x, e.y, d, reach, reward, nothing)
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
    best_victim === nothing || take_loot!(m, a, best_victim)
    x, y = best_land
    a.moved = (x, y) != (a.x, a.y)
    a.target_remembered = best_remembered
    a.travel_free = best_d <= free
    move_agent!(m, a, x, y)
    harvest!(m, a, x, y)
    xxl_on(m.config, :memory) && remember!(m, a; sw)
    return nothing
end
