# xxl rule 3: memory and word of mouth (spec, "Memory and word of mouth"). An agent remembers the best sites it has
# seen, values them again from wherever it stands, and hears of its neighbours' best.

"""
    ranks_above(v1, e1, v2, e2) -> Bool

Whether remembered entry `e1`, valued `v1`, ranks above `e2`, valued `v2` (spec, rule 3): the higher net value, then the
more recent sighting, then the smaller (x, y).
"""
@inline function ranks_above(v1::Float64, e1::Remembered, v2::Float64, e2::Remembered)
    v1 != v2 && return v1 > v2
    e1.t != e2.t && return e1.t > e2.t
    return (e1.x, e1.y) < (e2.x, e2.y)
end

"""
    rank_pool!(m, a)

Replaces `a.memory` with the best `memory` entries of the pool `m.pool`, best first, by [`net_value`](@ref) from the
agent's position with its holdings now (spec, rule 3). An entry's resources are devalued by the pollution it was seen
with. An entry the agent could not reach alive (valued `-Inf`) ranks last, so it is kept only if fewer than `memory`
entries are reachable. The pool is not changed; `m.pool_values` holds the kept entries' values.
"""
function rank_pool!(m::Model, a::Agent)
    cfg = m.config
    two = cfg.spice
    c = cfg.xxl.travel_cost
    cap = cfg.xxl.memory
    w, h = m.landscape.width, m.landscape.height
    sw = two ? SiteWelfare(m, a) : NO_WELFARE
    mem, vals = empty!(a.memory), empty!(m.pool_values)
    for e in m.pool
        d = torus_dist(w, h, a.x, a.y, e.x, e.y)
        devalue = 1.0 + e.pollution
        v = net_value(a, sw, two, c, d, e.sugar / devalue, two ? e.spice / devalue : 0.0)
        n = length(mem)
        n == cap && !ranks_above(v, e, @inbounds(vals[n]), @inbounds(mem[n])) && continue
        if n < cap  # room: a new last slot; otherwise the new entry replaces the last
            push!(mem, e)
            push!(vals, v)
            n += 1
        else
            @inbounds mem[n], vals[n] = e, v
        end
        while n > 1 && ranks_above(v, e, @inbounds(vals[n - 1]), @inbounds(mem[n - 1]))
            @inbounds mem[n], mem[n - 1] = mem[n - 1], mem[n]
            @inbounds vals[n], vals[n - 1] = vals[n - 1], vals[n]
            n -= 1
        end
    end
    return a.memory
end

"""
    remember!(m, a)

Updates agent `a`'s memory after its move (spec, rule 3). It pools its memory with the sites it looked at this move
(`m.looked`) and the site it stands on, which count as seen now at their current resources and pollution (the site it
harvested is as it is after harvest). One entry per site: the newest sighting, and a fresh look wins over a remembered
entry of the same period. Entries older than `memory_span` periods are dropped first. Then [`rank_pool!`](@ref) keeps
the `memory` best.
"""
function remember!(m::Model, a::Agent)
    ls = m.landscape
    span = m.config.xxl.memory_span
    spice = m.config.spice
    pool = empty!(m.pool)
    push!(pool, seen(ls, spice, a.x, a.y, m.t))
    for (x, y) in m.looked
        (x, y) == (a.x, a.y) && continue
        push!(pool, seen(ls, spice, x, y, m.t))
    end
    fresh = length(pool)
    for e in a.memory
        m.t - e.t > span && continue
        dup = false
        for i in 1:fresh
            p = @inbounds pool[i]
            dup |= (p.x == e.x) & (p.y == e.y)
        end
        dup || push!(pool, e)
    end
    return rank_pool!(m, a)
end

# What the agent sees at site (x, y) in period t: its current resources and pollution.
@inline function seen(ls::Landscape, spice::Bool, x::Int, y::Int, t::Int)
    i, j = x + 1, y + 1
    return Remembered(
        x,
        y,
        @inbounds(ls.sugar[i, j]),
        spice ? @inbounds(ls.spice[i, j]) : 0.0,
        @inbounds(ls.pollution[i, j]),
        t,
    )
end

"""
    word_of_mouth!(m, a)

Agent `a` hears of its neighbours' best (spec, rule 3): it copies the first entry of each neighbour's memory in
`a.neighbors` (with the period it was seen) into its own, then keeps the `memory` best as [`remember!`](@ref) ranks
them, one entry per site (the newest sighting) and none older than `memory_span`.
"""
function word_of_mouth!(m::Model, a::Agent)
    span = m.config.xxl.memory_span
    pool = empty!(m.pool)
    for e in a.memory
        m.t - e.t > span || push!(pool, e)
    end
    for b in a.neighbors
        isempty(b.memory) && continue
        e = @inbounds b.memory[1]
        m.t - e.t > span && continue
        k = 0
        for i in eachindex(pool)
            p = @inbounds pool[i]
            (p.x == e.x) & (p.y == e.y) && (k=i; break)
        end
        if k == 0
            push!(pool, e)
        elseif pool[k].t < e.t
            pool[k] = e
        end
    end
    return rank_pool!(m, a)
end
