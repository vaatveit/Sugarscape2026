# xxl (stage 8): the combat readings (docs/superpowers/specs/2026-11-08-xxl-combat-design.md, "Part 1: the readings").
# An observer that reads, period by period, the population by tribe, the deaths by cause and tribe, how mixed the two
# tribes are where rule K's neighbours meet, how many agents sit nearer their own tribe's starting block than the other,
# each tribe's wealth, and how many agents changed tribe. `timed_seed` calls `combat_period!` once before the first step
# (period 0) and after each step. It draws no random numbers and changes nothing in the model.
#
# Deaths are read from `m.dead_this_step` with the causes in the scorecard's order (`death_cause`): killed (the id is in
# `m.killed`, which both combat moves fill), then old age (`age >= max_age`), then the rest, as starved. A victim counts
# in the tribe its tags give at its death. Neighbours are rule K's (`culture_neighbors!`). What persists across calls is
# each living agent's tribe by id; `tribe_changes` counts the agents alive at both calls whose tribe differs.

"""The columns of a per-period row, [`combat_rows`](@ref)."""
const COMBAT_COLUMNS = [
    "t",
    "population",
    "n_blue",
    "n_red",
    "killed_blue",
    "killed_red",
    "old_age_blue",
    "old_age_red",
    "starved_blue",
    "starved_red",
    "neighbour_pairs",
    "cross_pairs",
    "mixing",
    "front_share",
    "home_blue",
    "home_red",
    "gini_blue",
    "gini_red",
    "max_sugar_blue",
    "max_sugar_red",
    "tribe_changes",
]

"""
    CombatReadings()

The combat observer of a run. [`combat_rows`](@ref) has a row for every period read, t = 0 included. Feed it with
[`combat_period!`](@ref).
"""
mutable struct CombatReadings
    seen::Bool  # a previous call exists
    prev::Dict{Int,Symbol}  # the living agents' tribes then, by id
    rows::Vector{Vector{Float64}}
    found::Vector{Agent}  # scratch: one agent's neighbours
    pairs::Vector{UInt64}  # scratch: this period's neighbour pairs
    blue_sugar::Vector{Float64}  # scratch
    red_sugar::Vector{Float64}  # scratch
end

CombatReadings() = CombatReadings(
    false, Dict{Int,Symbol}(), Vector{Float64}[], Agent[], UInt64[], Float64[], Float64[]
)

# The shorter way round the torus between two coordinates, as a Float64.
function min_image(size::Int, a::Real, b::Real)
    d = mod(abs(a - b), size)
    return min(d, size - d)
end

"""The centre of the first block of `tribe` in `cfg.initial_blocks`, `(x0 + w / 2, y0 + h / 2)`, or `nothing`."""
function block_centre(cfg::Config, tribe::Symbol)
    for (name, x0, y0, w, h, _) in cfg.initial_blocks
        Symbol(name) === tribe && return (x0 + w / 2, y0 + h / 2)
    end
    return nothing
end

"""
    home_credit(cfg, a, own, other) -> Float64

1 when `a` is nearer (torus Euclidean, minimum image) the block centre `own` than `other`, 0 when farther, 0.5 when
equally near.
"""
function home_credit(cfg::Config, a::Agent, own, other)
    d_own = min_image(cfg.width, a.x, own[1])^2 + min_image(cfg.height, a.y, own[2])^2
    d_other = min_image(cfg.width, a.x, other[1])^2 + min_image(cfg.height, a.y, other[2])^2
    return d_own < d_other ? 1.0 : d_own == d_other ? 0.5 : 0.0
end

"""
    combat_period!(r, m)

The end of a period, after `step!` (or period 0, before the first): reads the period's combat row. Call it once per
period, in order, from period 0.
"""
function combat_period!(r::CombatReadings, m::Model)
    cfg = m.config
    agents = m.agents
    n = length(agents)
    blue = red = 0
    changes = 0
    home_b = home_r = 0.0
    bc, rc = block_centre(cfg, :blue), block_centre(cfg, :red)
    blue_sugar, red_sugar = empty!(r.blue_sugar), empty!(r.red_sugar)
    cur = Dict{Int,Symbol}()
    sizehint!(cur, n)
    for a in agents
        tr = tribe(a)
        cur[a.id] = tr
        old = get(r.prev, a.id, nothing)
        old === nothing || (changes += old !== tr)
        if tr === :blue
            blue += 1
            push!(blue_sugar, a.sugar)
            bc === nothing || rc === nothing || (home_b += home_credit(cfg, a, bc, rc))
        elseif tr === :red
            red += 1
            push!(red_sugar, a.sugar)
            bc === nothing || rc === nothing || (home_r += home_credit(cfg, a, rc, bc))
        end
    end

    # this period's deaths, by cause and the victim's tribe
    killed_b = killed_r = old_b = old_r = starved_b = starved_r = 0
    for a in m.dead_this_step
        tr = tribe(a)
        tr === :blue || tr === :red || continue
        if a.id in m.killed
            tr === :blue ? (killed_b += 1) : (killed_r += 1)
        elseif a.age >= a.max_age
            tr === :blue ? (old_b += 1) : (old_r += 1)
        else
            tr === :blue ? (starved_b += 1) : (starved_r += 1)
        end
    end

    # neighbour pairs, the cross-tribe ones, and the agents on a front
    pairs = empty!(r.pairs)
    front = 0
    for a in agents
        culture_neighbors!(r.found, m, a)
        mine = cur[a.id]
        other = false
        for b in r.found
            b === a && continue
            push!(pairs, pair_key(a.id, b.id))
            other |= cur[b.id] !== mine
        end
        front += other
    end
    sort!(pairs)
    unique!(pairs)
    cross = 0
    for k in pairs
        cross += cur[pair_lo(k)] !== cur[pair_hi(k)]
    end

    has_home = bc !== nothing && rc !== nothing
    push!(
        r.rows,
        Float64[
            m.t,
            n,
            blue,
            red,
            killed_b,
            killed_r,
            old_b,
            old_r,
            starved_b,
            starved_r,
            length(pairs),
            cross,
            isempty(pairs) ? NaN : cross / length(pairs),
            n == 0 ? NaN : front / n,
            (has_home && blue > 0) ? home_b / blue : NaN,
            (has_home && red > 0) ? home_r / red : NaN,
            blue == 0 ? NaN : gini(blue_sugar),
            red == 0 ? NaN : gini(red_sugar),
            blue == 0 ? NaN : maximum(blue_sugar),
            red == 0 ? NaN : maximum(red_sugar),
            r.seen ? changes : NaN,
        ],
    )
    r.prev = cur
    r.seen = true
    return nothing
end

"""
    combat_rows(r) -> (header, rows)

One row per period read, t = 0 included, in the order of [`COMBAT_COLUMNS`](@ref). A column with nothing to read is NaN.
"""
combat_rows(r::CombatReadings) = (copy(COMBAT_COLUMNS), r.rows)
