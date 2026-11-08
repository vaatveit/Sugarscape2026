# xxl (stage 7): the culture readings (docs/superpowers/specs/2026-11-07-xxl-culture-design.md, "Part 1: the readings").
# An observer that reads, period by period, how culturally alike rule K's neighbours are against chance, how many
# neighbours an agent has and how long neighbour pairs last, how far agents move, how many tag bits flip, and the share
# of 0s at each tag position; and, every CULTURE_PATCH_EVERY periods, the tribe mix in each CULTURE_PATCH-site patch.
# `timed_seed` calls `culture_period!` once before the first step (period 0) and after each step. It draws no random
# numbers and changes nothing in the model.
#
# The neighbours are found from the grid as rule K finds them (`neighbors_of`: the four von Neumann sites, or under
# xxl rule 4 the sites at `near_offsets` for the interaction radius), into the observer's own vector, never `m.sight`.
# What persists across calls is each living agent's tags and position by id and the set of neighbour pairs, kept as
# sorted keys `lo_id << 32 | hi_id`. Flips, persistence and distance moved count only agents (and pairs of agents) alive
# at both the previous call and this one; agents born this period enter closeness and population only.

"""The side of a patch, in sites."""
const CULTURE_PATCH = 50

"""The patch rows are taken at every t that is a multiple of this."""
const CULTURE_PATCH_EVERY = 10

"""The fewest agents a patch needs to count in [`patch_polarization`](@ref)."""
const CULTURE_PATCH_MIN = 20

"""The tag positions that get a `zero_share_i` column."""
const CULTURE_ZERO_POSITIONS = 11

"""The columns of a per-period row, [`culture_rows`](@ref)."""
const CULTURE_COLUMNS = [
    "t",
    "population",
    "blue_share",
    "tag_flips_per_agent",
    "neighbour_pairs",
    "neighbour_closeness",
    "chance_closeness",
    "neighbours_per_agent",
    "share_no_neighbours",
    "persist_base",
    "persistence",
    "mean_moved",
    "mean_speed",
    ["zero_share_$i" for i in 1:CULTURE_ZERO_POSITIONS]...,
]

"""The columns of a patch row, [`culture_patch_rows`](@ref)."""
const CULTURE_PATCH_COLUMNS = ["t", "px", "py", "agents", "blue_share"]

"""
    CultureReadings()

The culture observer of a run. [`culture_rows`](@ref) has a row for every period read, t = 0 included;
[`culture_patch_rows`](@ref) has the patches at every `CULTURE_PATCH_EVERY`th. Feed it with [`culture_period!`](@ref).
"""
mutable struct CultureReadings
    seen::Bool  # a previous call exists
    prev::Dict{Int,Tuple{UInt64,Int,Int}}  # the living agents then: id => tags, x, y
    prev_pairs::Vector{UInt64}  # the neighbour pairs then, sorted
    rows::Vector{Vector{Float64}}
    patch_rows::Vector{Vector{Float64}}
    found::Vector{Agent}  # scratch: one agent's neighbours
    pairs::Vector{UInt64}  # scratch: this period's neighbour pairs
    byid::Dict{Int,Agent}  # scratch: the living agents by id
end

CultureReadings() = CultureReadings(
    false, Dict{Int,Tuple{UInt64,Int,Int}}(), UInt64[], Vector{Float64}[], Vector{Float64}[],
    Agent[], UInt64[], Dict{Int,Agent}(),
)

"""
    culture_neighbors!(out, m, a) -> out

Replaces `out` with the agents in rule K's reach of `a` now: the four von Neumann sites, or with xxl rule 4 on the sites
at `near_offsets(m, interaction_radius)`, wrapped.
"""
function culture_neighbors!(out::Vector{Agent}, m::Model, a::Agent)
    empty!(out)
    if xxl_on(m.config, :radius)
        for (dx, dy) in near_offsets(m, m.config.xxl.interaction_radius)
            other = agent_at(m, a.x + dx, a.y + dy)
            other === nothing || push!(out, other)
        end
    else
        for (dx, dy) in VON_NEUMANN
            other = agent_at(m, a.x + dx, a.y + dy)
            other === nothing || push!(out, other)
        end
    end
    return out
end

"""The agents in rule K's reach of `a` now, in a fresh vector (see [`culture_neighbors!`](@ref))."""
culture_neighbors(m::Model, a::Agent) = culture_neighbors!(Agent[], m, a)

pair_key(i::Int, j::Int) = (UInt64(min(i, j)) << 32) | UInt64(max(i, j))
pair_lo(k::UInt64) = Int(k >> 32)
pair_hi(k::UInt64) = Int(k & 0xffffffff)

"""
    culture_period!(r, m)

The end of a period, after `step!` (or period 0, before the first): reads the period's culture rows, and the patches when
`m.t` is a multiple of `CULTURE_PATCH_EVERY`. Call it once per period, in order, from period 0.
"""
function culture_period!(r::CultureReadings, m::Model)
    cfg, t = m.config, m.t
    L = cfg.tag_length
    agents = m.agents
    n = length(agents)
    blue = 0
    flips = 0
    moved = 0.0
    nmoved = 0
    zeros_at = zeros(Int, max(L, CULTURE_ZERO_POSITIONS))
    cur = Dict{Int,Tuple{UInt64,Int,Int}}()
    sizehint!(cur, n)
    byid = empty!(r.byid)
    w, h = cfg.width, cfg.height
    for a in agents
        cur[a.id] = (a.tags, a.x, a.y)
        byid[a.id] = a
        blue += tribe(a) === :blue
        for i in 1:L
            zeros_at[i] += (a.tags >> (i - 1)) & 1 == 0
        end
        old = get(r.prev, a.id, nothing)
        if old !== nothing
            flips += count_ones(old[1] ⊻ a.tags)
            moved += torus_dist(w, h, old[2], old[3], a.x, a.y)
            nmoved += 1
        end
    end

    # the neighbour pairs, and how many neighbours each agent has
    pairs = empty!(r.pairs)
    total_neighbours = alone = 0
    for a in agents
        culture_neighbors!(r.found, m, a)
        total_neighbours += length(r.found)
        alone += isempty(r.found)
        for b in r.found
            b === a || push!(pairs, pair_key(a.id, b.id))
        end
    end
    sort!(pairs)
    unique!(pairs)
    closeness_sum = 0.0
    for k in pairs
        closeness_sum += closeness(byid[pair_lo(k)].tags, byid[pair_hi(k)].tags, L)
    end

    # the pairs of the previous call with both agents alive now, and how many of them are still neighbours
    base = kept = 0
    if r.seen
        for k in r.prev_pairs
            (haskey(cur, pair_lo(k)) && haskey(cur, pair_hi(k))) || continue
            base += 1
            kept += insorted(k, pairs)
        end
    end

    chance = NaN
    if n >= 2 && L > 0
        s = 0.0
        for i in 1:L
            s += 2 * zeros_at[i] * (n - zeros_at[i])
        end
        chance = 1 - s / (L * n * (n - 1))
    end

    speed = xxl_on(cfg, :speed)
    push!(
        r.rows,
        Float64[
            t,
            n,
            n == 0 ? NaN : blue / n,
            (r.seen && n > 0) ? flips / n : NaN,
            length(pairs),
            (isempty(pairs) || L == 0) ? NaN : closeness_sum / length(pairs),
            chance,
            n == 0 ? NaN : total_neighbours / n,
            n == 0 ? NaN : alone / n,
            base,
            base == 0 ? NaN : kept / base,
            nmoved == 0 ? NaN : moved / nmoved,
            (speed && n > 0) ? sum(a -> a.speed, agents) / n : NaN,
            [(n == 0 || i > L) ? NaN : zeros_at[i] / n for i in 1:CULTURE_ZERO_POSITIONS]...,
        ],
    )

    t % CULTURE_PATCH_EVERY == 0 && patch_period!(r, m)

    r.prev = cur
    r.prev_pairs = copy(pairs)
    r.seen = true
    return nothing
end

"""Adds a row for each patch holding an agent, at the model's period."""
function patch_period!(r::CultureReadings, m::Model)
    counts = Dict{Tuple{Int,Int},Tuple{Int,Int}}()  # (px, py) => agents, blue
    for a in m.agents
        key = (a.x ÷ CULTURE_PATCH, a.y ÷ CULTURE_PATCH)
        c = get(counts, key, (0, 0))
        counts[key] = (c[1] + 1, c[2] + (tribe(a) === :blue))
    end
    for key in sort!(collect(keys(counts)))
        c = counts[key]
        push!(r.patch_rows, Float64[m.t, key[1], key[2], c[1], c[2] / c[1]])
    end
    return nothing
end

"""
    culture_rows(r) -> (header, rows)

One row per period read, t = 0 included, in the order of [`CULTURE_COLUMNS`](@ref). A column with nothing to average is
NaN; `mean_speed` is NaN in a world without speed.
"""
culture_rows(r::CultureReadings) = (copy(CULTURE_COLUMNS), r.rows)

"""
    culture_patch_rows(r) -> (header, rows)

One row per patch holding an agent, at each t with `t % CULTURE_PATCH_EVERY == 0`, in the order of
[`CULTURE_PATCH_COLUMNS`](@ref). The patch is `(x ÷ CULTURE_PATCH, y ÷ CULTURE_PATCH)`, 0-based.
"""
culture_patch_rows(r::CultureReadings) = (copy(CULTURE_PATCH_COLUMNS), r.patch_rows)

"""
    patch_polarization(rows; min_agents=CULTURE_PATCH_MIN) -> Float64

Over one period's patch rows: the agent-weighted mean of `abs(2 * blue_share - 1)` over the patches with at least
`min_agents` agents; NaN when there are none.
"""
function patch_polarization(rows; min_agents::Int=CULTURE_PATCH_MIN)
    weight = total = 0.0
    for row in rows
        row[4] >= min_agents || continue
        weight += row[4]
        total += row[4] * abs(2 * row[5] - 1)
    end
    return weight == 0 ? NaN : total / weight
end
