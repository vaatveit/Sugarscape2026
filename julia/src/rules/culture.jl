# Cultural tags, transmission K, and networks of friends (pp.72-80; sugarscape/rules/culture.py). Tags are the low
# n bits of a UInt64, bit i-1 being position i.

tag_mask(n::Int) = n == 64 ? typemax(UInt64) : (UInt64(1) << n) - UInt64(1)

"""A uniformly random tag string of length n; with a tribe, resampled until its majority matches (our call)."""
function random_tags(rng::AbstractRNG, n::Int, tribe::Symbol)
    while true
        t = rand(rng, UInt64) & tag_mask(n)
        tribe === :none && return t
        (2 * count_ones(t) < n ? :blue : :red) === tribe && return t
    end
end

"""Vertical transmission (p.78, Table III-2): agreeing positions copy, the others take a fair coin."""
function cross_tags(rng::AbstractRNG, a::UInt64, b::UInt64, n::Int)
    mask = tag_mask(n)
    agree = ~(a ⊻ b) & mask
    return (a & agree) | (rand(rng, UInt64) & ~agree & mask)
end

hamming(a::UInt64, b::UInt64) = count_ones(a ⊻ b)

"""
    culture_reach_agents!(out, m, a) -> out

Replaces `out` with the agents rule K reaches from `a`, by `culture_reach` (VI-1-far, VI-1-far-speed):
- "neighbours": [`neighbors_of`](@ref)'s, in its order, with its draws (none).
- "sight": the agents on the sites of combat's look from where `a` stands, drawn afresh. With xxl round vision,
  [`look!`](@ref) without memory; otherwise the 4 lattice lines in a [`random_directions`](@ref) order, each
  [`look_line!`](@ref) with `look_stride` out to `a.vision`, as [`combat_move!`](@ref) scans them.
- "attack": the agents on `near_offsets(m, a.speed)` around `a` (xxl speed only).
`a` itself is left out. No agent is listed twice: the round look lists a site once, and with vision (and speed, which
does not exceed it) below half the grid neither the lattice lines nor the speed disc wrap onto a site twice. The looks
use rule K's own scratch (`m.culture_line`, `m.culture_looked`), never the move's.
"""
function culture_reach_agents!(out::Vector{Agent}, m::Model, a::Agent)
    empty!(out)
    reach = m.config.culture_reach
    reach == "neighbours" && return append!(out, neighbors_of(m, a))
    if reach == "attack"
        for (dx, dy) in near_offsets(m, Float64(a.speed))
            reach_push!(out, a, agent_at(m, a.x + dx, a.y + dy))
        end
    elseif xxl_on(m.config, :disc)
        for (x, y) in look!(m.culture_looked, m, a, a.x, a.y; memory=false)
            reach_push!(out, a, @inbounds m.grid[x + 1, y + 1])
        end
    else
        stride = m.config.look_stride
        for d in random_directions(m.rng)
            dx, dy = @inbounds VON_NEUMANN[d]
            for dist in look_line!(m.culture_line, m.rng, stride, a.vision)
                reach_push!(out, a, agent_at(m, a.x + dx * dist, a.y + dy * dist))
            end
        end
    end
    return out
end

@inline function reach_push!(out::Vector{Agent}, a::Agent, other)
    (other === nothing || other === a) || push!(out, other)
    return out
end

"""
    culture_transmit!(m, a)

Cultural transmission (p.73, App. B): for each agent reached ([`culture_reach_agents!`](@ref): the neighbours, or
with `culture_reach` combat's sight or attack reach), in random order, a random tag position is chosen; if that agent
disagrees there, its tag is flipped to the agent's.
"""
function culture_transmit!(m::Model, a::Agent)
    neighbors = shuffle!(m.rng, culture_reach_agents!(m.culture_reached, m, a))
    for other in neighbors
        other.ntags == 0 && continue
        bit = UInt64(1) << rand(m.rng, 0:(a.ntags - 1))
        other.tags = (other.tags & ~bit) | (a.tags & bit)
    end
    return nothing
end

"""
    update_friends!(a, neighbors; max_friends=5)

Networks of friends (pp.79-80): remember the culturally nearest agents met as neighbours. Distances are taken at the
encounter and never re-evaluated; dead friends are dropped (our call). A newcomer displaces the stored-farthest
friend only when strictly closer.
"""
function update_friends!(a::Agent, neighbors; max_friends::Int=5)
    filter!(p -> p[1].alive, a.friends)
    for other in neighbors
        (other === a || other.ntags == 0 || !other.alive) && continue
        any(p -> p[1] === other, a.friends) && continue
        d = hamming(a.tags, other.tags)
        if length(a.friends) < max_friends
            push!(a.friends, (other, d))
            continue
        end
        worst = 1  # the first friend at the largest stored distance, as Python's max() picks
        for i in 2:length(a.friends)
            a.friends[i][2] > a.friends[worst][2] && (worst = i)
        end
        d < a.friends[worst][2] && (a.friends[worst] = (other, d))
    end
    return nothing
end
