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

# One agent's ranking in progress: `a.memory` being rebuilt, best first, with each kept entry's value and what its two
# powers are of. Building one empties `a.memory`. `price`'s rule 13 blend and price, if any, carry over (a move's
# `SiteWelfare`); the holdings are the agent's now.
struct Ranking
    a::Agent
    sw::SiteWelfare
    two::Bool  # spice is on
    two_powers::Bool  # both commodities count: an entry can lose without a power being taken (surely_less)
    m1::Float64
    c::Float64
    free::Float64
    cap::Int
    mem::Vector{Remembered}
    vals::Vector{Float64}
    ka::Vector{Float64}
    kb::Vector{Float64}
end

function Ranking(m::Model, a::Agent, price::SiteWelfare=NO_WELFARE)
    cfg = m.config
    two = cfg.spice
    sw = two ? priced(SiteWelfare(m, a), price.lambda, price.inv_p) : NO_WELFARE
    cap = cfg.xxl.memory
    return Ranking(
        a,
        sw,
        two,
        two && sw.use1 && sw.use2 && sw.lambda == 0,  # surely_less holds for the book's welfare only
        sugar_burn(a),
        cfg.xxl.travel_cost,
        cfg.xxl.free_step,
        cap,
        empty!(a.memory),
        empty!(m.pool_values),
        resize!(m.kept_a, cap),
        resize!(m.kept_b, cap),
    )
end

# Entry `e`, valued `v`, goes in its place in the kept list if it ranks there.
@inline function keep_ranked!(r::Ranking, v::Float64, e::Remembered, A::Float64, B::Float64)
    mem, vals, ka, kb = r.mem, r.vals, r.ka, r.kb
    n = length(mem)
    n == r.cap && !ranks_above(v, e, @inbounds(vals[n]), @inbounds(mem[n])) && return nothing
    if n < r.cap  # room: a new last slot; otherwise the new entry replaces the last
        push!(mem, e)
        push!(vals, v)
        n += 1
    else
        @inbounds mem[n], vals[n] = e, v
    end
    @inbounds ka[n], kb[n] = A, B
    while n > 1 && ranks_above(v, e, @inbounds(vals[n - 1]), @inbounds(mem[n - 1]))
        @inbounds mem[n], mem[n - 1] = mem[n - 1], mem[n]
        @inbounds vals[n], vals[n - 1] = vals[n - 1], vals[n]
        @inbounds ka[n], ka[n - 1] = ka[n - 1], ka[n]
        @inbounds kb[n], kb[n - 1] = kb[n - 1], kb[n]
        n -= 1
    end
    return nothing
end

# Ranks entry `e`, `d` from the agent. (c1, c2) are the weights against the last kept entry once the list is full, for an
# entry that can't reach it to lose without its powers being taken; returns them as they now stand.
@inline function rank_entry!(r::Ranking, d::Float64, e::Remembered, c1::Float64, c2::Float64)
    a, sw = r.a, r.sw
    devalue = 1.0 + e.pollution
    sugar, spice = e.sugar / devalue, r.two ? e.spice / devalue : 0.0
    if !r.two_powers
        keep_ranked!(r, net_value(a, sw, r.two, r.c, r.free, d, sugar, spice), e, 0.0, 0.0)
        return c1, c2
    end
    A, B = net_parts(a, sw, r.m1, r.c, r.free, d, sugar, spice)
    if A < 0  # worth -Inf, and it counts as worth nothing against what comes after it
        keep_ranked!(r, -Inf, e, 0.0, 0.0)
    elseif surely_less(c1, c2, A, B)
        return c1, c2
    else
        keep_ranked!(r, A^sw.e1 * B^sw.e2, e, A, B)
    end
    length(r.mem) == r.cap || return c1, c2
    return prune_weights(sw.e1, sw.e2, @inbounds(r.ka[r.cap]), @inbounds(r.kb[r.cap]))
end

"""
    rank_pool!(m, a)

Replaces `a.memory` with the best `memory` entries of the pool `m.pool`, best first, by [`net_value`](@ref) from the
agent's position with its holdings now (spec, rule 3). An entry's resources are devalued by the pollution it was seen
with. An entry the agent could not reach alive (valued `-Inf`) ranks last, so it is kept only if fewer than `memory`
entries are reachable. The pool is not changed; `m.pool_values` holds the kept entries' values.
"""
function rank_pool!(m::Model, a::Agent)
    w, h = m.landscape.width, m.landscape.height
    r = Ranking(m, a)
    c1, c2 = Inf, Inf
    for e in m.pool
        c1, c2 = rank_entry!(r, torus_dist(w, h, a.x, a.y, e.x, e.y), e, c1, c2)
    end
    return a.memory
end

"""
    remember!(m, a; sw=NO_WELFARE)

Updates agent `a`'s memory after its move (spec, rule 3). It ranks, as [`rank_pool!`](@ref) does, the site it stands on
and the sites it looked at this move (`m.looked`), which count as seen now at their current resources and pollution (the
site it harvested is as it is after harvest), then the rest of its memory. One entry per site: the newest sighting, and a
fresh look wins over a remembered entry of the same period. Entries older than `memory_span` periods are dropped first.
The sites are ranked without being pooled, as most lose at once; `m.pool` holds only the memory's entries. `sw` is the
move's [`SiteWelfare`](@ref): under rule 13 the entries are valued at the move's blend and price (our call), with the
holdings as they are after the harvest.
"""
function remember!(m::Model, a::Agent; sw::SiteWelfare=NO_WELFARE)
    ls = m.landscape
    span = m.config.xxl.memory_span
    spice = m.config.spice
    w, h = ls.width, ls.height
    ax, ay = a.x, a.y
    looked = m.looked
    rest = empty!(m.pool)  # first: the ranking empties the memory
    for e in a.memory
        m.t - e.t > span && continue
        dup = (e.x == ax) & (e.y == ay)
        for i in eachindex(looked)
            s = @inbounds looked[i]
            dup |= (s[1] == e.x) & (s[2] == e.y)
        end
        dup || push!(rest, e)
    end
    r = Ranking(m, a, sw)
    c1, c2 = rank_entry!(r, 0.0, seen(ls, spice, ax, ay, m.t), Inf, Inf)
    for (x, y) in looked
        ((x == ax) & (y == ay)) && continue
        c1, c2 = rank_entry!(r, torus_dist(w, h, ax, ay, x, y), seen(ls, spice, x, y, m.t), c1, c2)
    end
    for e in rest
        c1, c2 = rank_entry!(r, torus_dist(w, h, ax, ay, e.x, e.y), e, c1, c2)
    end
    return a.memory
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
