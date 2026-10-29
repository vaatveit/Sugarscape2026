# xxl rule 4: interaction radius (spec, "Interaction radius"). An agent's neighbours are the living agents within
# distance R; a child is born on an empty site within R of either parent. At R = 1.0 none of this runs: `neighbors_of`,
# `set_neighbors!` and `add_empty_sites!` keep the book's four von Neumann sites.

"""
    radius_neighbors!(out, m, a) -> out

Replaces `out` with the living agents within the interaction radius of `a` (spec, rule 4): those at
[`near_offsets`](@ref)`(m, R)`, wrapped round the torus, nearest first and, at equal distance, by dx then dy.
"""
function radius_neighbors!(out::Vector{Agent}, m::Model, a::Agent)
    empty!(out)
    for (dx, dy) in near_offsets(m, m.config.xxl.interaction_radius)
        other = agent_at(m, a.x + dx, a.y + dy)
        other === nothing || push!(out, other)
    end
    return out
end

"""
    radius_empty_sites!(sites, m, a) -> sites

Adds the empty sites within the interaction radius of `a` that `sites` doesn't already list (spec, rule 4), in
[`near_offsets`](@ref) order: [`add_empty_sites!`](@ref) for a radius other than 1.
"""
function radius_empty_sites!(sites::Vector{Tuple{Int,Int}}, m::Model, a::Agent)
    for (dx, dy) in near_offsets(m, m.config.xxl.interaction_radius)
        s = wrap(m, a.x + dx, a.y + dy)
        m.grid[s[1] + 1, s[2] + 1] === nothing && !(s in sites) && push!(sites, s)
    end
    return sites
end
