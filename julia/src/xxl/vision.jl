# xxl rule 1: round vision (spec, "Round vision"). The look is a set of sites; movement and mate search both read it.

"""The squared torus distance between two sites, an integer: the exact key for ordering by distance."""
@inline function torus_dist2(w::Int, h::Int, x1::Int, y1::Int, x2::Int, y2::Int)
    dx = torus_delta(w, x1, x2)
    dy = torus_delta(h, y1, y2)
    return dx * dx + dy * dy
end

"""
    look!(out, m, a, x, y; memory=true) -> out

The sites agent `a` looks at from (x, y), into `out`, wrapped and 0-based. With the disc shape (spec, rule 1): the
centre's own site first, then every site within the near radius n (`near_offsets`, nearest first), where n is the
agent's speed, or 1.0 without one (the four adjacent sites), then `ring_draws(a.vision)` points drawn uniformly by area
from the ring n < d ≤ V, each rounded to a site: one whose rounded distance is not in (n, V] is dropped, and a site
already looked at is looked at once. With the lattice shape, the sites [`move!`](@ref) scans: the own site, then each
direction in a random order out along its looks. With memory on (and `memory=true`), the agent's remembered sites within
vision (torus distance at most V) of (x, y) that are not looked at yet come last: they are looked at afresh, so they
count at their current values (rule 3). `memory=false` leaves them out.
"""
function look!(
    out::Vector{Tuple{Int,Int}}, m::Model, a::Agent, x::Int, y::Int; memory::Bool=true
)
    empty!(out)
    push!(out, (x, y))
    if !xxl_on(m.config, :disc)
        stride = m.config.look_stride
        for d in random_directions(m.rng)
            dx, dy = @inbounds VON_NEUMANN[d]
            for dist in look_line!(m.line, m.rng, stride, a.vision)
                push!(out, wrap(m, x + dx * dist, y + dy * dist))
            end
        end
        memory && xxl_on(m.config, :memory) && look_remembered!(out, m, a, x, y)
        return out
    end
    n = a.speed > 0 ? Float64(a.speed) : 1.0
    v = Float64(a.vision)
    for (dx, dy) in near_offsets(m, n)
        push!(out, wrap(m, x + dx, y + dy))
    end
    if v > n  # a vision no longer than the near radius leaves no ring (and draws nothing)
        ring_start = length(out) + 1  # near sites never repeat a ring site: their distances differ
        for _ in 1:ring_draws(a.vision)
            rx, ry = ring_point(m.rng, n, v)
            dx, dy = round(Int, rx), round(Int, ry)
            r2 = dx * dx + dy * dy
            (r2 > n * n && r2 <= v * v) || continue
            site = wrap(m, x + dx, y + dy)
            seen = false
            for i in ring_start:length(out)
                @inbounds seen |= out[i] == site
            end
            seen || push!(out, site)
        end
    end
    memory && xxl_on(m.config, :memory) && look_remembered!(out, m, a, x, y)
    return out
end

# Appends the sites `a` remembers within its vision of (x, y) that `out` doesn't hold yet. They can coincide with a near
# or ring site, so the whole of `out` is checked; there are few of them.
function look_remembered!(out::Vector{Tuple{Int,Int}}, m::Model, a::Agent, x::Int, y::Int)
    w, h = m.landscape.width, m.landscape.height
    v = Float64(a.vision)
    for e in a.memory
        torus_dist(w, h, x, y, e.x, e.y) <= v || continue
        site = (e.x, e.y)
        site in out || push!(out, site)
    end
    return out
end

"""`look!(m, a)`: agent `a`'s look from where it stands, into the model's scratch `m.looked`."""
look!(m::Model, a::Agent) = look!(m.looked, m, a, a.x, a.y)

"""
    xxl_move!(m, a)

Rule M with round vision (spec, rule 1): the agent scores its own site and every empty site it looks at with the same
score as [`move!`](@ref), and jumps to the best. Ties go to the nearest site by torus distance, then to the first
looked at; staying wins a tie with the own site. It harvests as `move!` does. With speed on it is
[`speed_move!`](@ref) instead (rule 2).
"""
function xxl_move!(m::Model, a::Agent)
    xxl_on(m.config, :speed) && return speed_move!(m, a)
    ls = m.landscape
    spice = m.config.spice
    w, h = ls.width, ls.height
    a.moved_dist = 0.0
    a.target_remembered = false
    best_x, best_y, best_d2 = a.x, a.y, 0
    sw = spice ? SiteWelfare(m, a) : NO_WELFARE  # the agent's part of welfare_score, once per move
    best = spice ? score(sw, ls, a.x + 1, a.y + 1) : site_score(ls, a.x + 1, a.y + 1)
    for (x, y) in look!(m, a)
        @inbounds m.grid[x + 1, y + 1] === nothing || continue  # the agent's own site is occupied by itself
        s = spice ? score(sw, ls, x + 1, y + 1) : site_score(ls, x + 1, y + 1)
        s < best && continue
        d2 = torus_dist2(w, h, a.x, a.y, x, y)
        if s > best || d2 < best_d2
            best, best_x, best_y, best_d2 = s, x, y, d2
        end
    end
    a.moved = (best_x, best_y) != (a.x, a.y)
    move_agent!(m, a, best_x, best_y)
    harvest!(m, a, best_x, best_y)
    return nothing
end

"""
    disc_in_sight(m, a) -> Vector{Agent}

The other agents on a fresh [`look!`](@ref) from where `a` stands, nearest first by torus distance and, at equal
distance, in the order looked at (spec, rule 1: mate search with `mate_contact = "vision"`). Returns `m.sight`, which the
next call reuses.
"""
function disc_in_sight(m::Model, a::Agent)
    w, h = m.landscape.width, m.landscape.height
    found = empty!(m.sight)
    for (x, y) in look!(m.looked, m, a, a.x, a.y; memory=false)
        other = @inbounds m.grid[x + 1, y + 1]
        (other === nothing || other === a) && continue
        d2 = torus_dist2(w, h, a.x, a.y, x, y)
        push!(found, other)
        i = length(found)  # a stable insertion: past every agent at least as near
        while i > 1
            p = @inbounds found[i - 1]
            torus_dist2(w, h, a.x, a.y, p.x, p.y) <= d2 && break
            @inbounds found[i] = p
            i -= 1
        end
        @inbounds found[i] = other
    end
    return found
end
