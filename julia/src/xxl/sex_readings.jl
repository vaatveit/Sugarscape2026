# xxl (stage 6): the sex readings (docs/superpowers/specs/2026-11-07-xxl-sex-design.md, "Part 1: the readings"). An
# observer that reads, period by period, how many agents are fertile, how many of those have a fertile mate of the other
# sex in the rule's reach and anywhere within their vision, the period's births and failed attempts from rule S's log
# (`m.mate_log`), and the traits selection acts on; and keeps a snapshot of the fertile lives that end in a window.
# `timed_seed` calls `sex_period!` once before the first step (period 0) and after each step. Its first call turns the
# log on; each call reads the log of the step just run, so every event counts in the period being read (an event's own
# `t` is the model's period mid-step and is not used). The model empties the log at the start of each step.
#
# The reach count is the scorecard's X2 count (`push_fertility!`): the same agents in the same order, with the looks
# drawn from the observer's own copy of the RNG, taken at its first call, so the run is unchanged. The within-vision
# count is exact, on every site of the shape the world's look is drawn from: under round vision the disc
# 0 < dx² + dy² ≤ V² (torus distance), else the four lattice lines, every site out to the look's farthest
# possible distance, stride·(V ÷ stride) + stride − 1 (V at stride 1, the book; the xl look's jitter reaches past V), not
# the look's strided sample.
#
# The snapshot: an agent's fertile life ends when its age reaches its fertility end (end reason 0), or when it dies
# after reaching childbearing age (end reason 1). Its period counts are over its whole observed life. An agent first
# seen already at or past its fertility end (a founder) ended its fertile life before the run and is not followed.

"""The periods the sex snapshot covers by default: the last 200 of a run, t = 301–500 for 500 periods."""
const SEX_WINDOW = 200

"""The columns of a per-period row, [`sex_rows`](@ref)."""
const SEX_COLUMNS = [
    "t",
    "population",
    "eligible",
    "fertile",
    "fertile_reach",
    "fertile_vision",
    "births",
    "no_site",
    "mean_distance",
    "median_distance",
    "mean_distance_share",
    "median_distance_share",
    "mean_vision",
    "sd_vision",
    "mean_metabolism",
    "sd_metabolism",
    "mean_spice_metabolism",
    "sd_spice_metabolism",
    "mean_speed",
    "sd_speed",
]

"""The columns of an agent's snapshot row, [`sex_agent_rows`](@ref)."""
const SEX_AGENT_COLUMNS = [
    "id",
    "sex",
    "end_t",
    "end_reason",
    "periods_eligible",
    "periods_fertile",
    "periods_fertile_reach",
    "periods_fertile_vision",
    "children",
    "vision",
    "metabolism",
    "speed",
]

"""The side of a bucket of the fertile-agent grid under round vision, in sites."""
const SEX_BUCKET = 8

"""
An agent followed through its fertile life: the periods it was of childbearing age, fertile, and fertile with a mate,
and its children (counted from the log, as a dead agent's list is emptied).
"""
mutable struct FertileLife
    eligible::Int
    fertile::Int
    reach::Int
    vision::Int
    children::Int
end

"""
The fertile agents of one sex by bucket of `SEX_BUCKET` × `SEX_BUCKET` sites, laid out as one sorted array: bucket b's
agents are at `first[b]:first[b + 1] - 1` of `xs` and `ys`.
"""
struct SexBuckets
    first::Vector{Int}
    xs::Vector{Int}
    ys::Vector{Int}
end
SexBuckets() = SexBuckets(Int[], Int[], Int[])

"""
    SexReadings(; window)

The sex observer of a run. `window = (first, last)` is the periods the snapshot covers: every agent whose fertile life
ends in them gets a row in [`sex_agent_rows`](@ref). [`sex_rows`](@ref) has a row for every period read, t = 0
included. Feed it with [`sex_period!`](@ref).
"""
mutable struct SexReadings
    window::Tuple{Int,Int}
    rng::Union{Nothing,AbstractRNG}  # a copy of the model's RNG at the first call: the reach looks draw from it
    lives::Dict{Int,FertileLife}  # agent id => its fertile life so far, while it lasts
    rows::Vector{Vector{Float64}}
    agents::Vector{Vector{Float64}}  # the snapshot's rows, in order of end period, then id
    ended::Vector{Vector{Float64}}  # scratch: this period's ends in the window
    fertile::Vector{Bool}  # scratch, by position in m.agents
    reach::Vector{Bool}
    vision::Vector{Bool}
    buckets::Tuple{SexBuckets,SexBuckets}  # scratch: the fertile women, the fertile men
    bx::Vector{Int}  # scratch: the buckets a disc spans, along x and y
    by::Vector{Int}
    distances::Vector{Float64}  # scratch: the period's birth distances, and as shares of vision
    shares::Vector{Float64}
end

function SexReadings(; window::Tuple{Int,Int})
    0 <= window[1] <= window[2] || throw(ArgumentError("the window needs 0 <= first <= last, got $window"))
    return SexReadings(
        window, nothing, Dict{Int,FertileLife}(), Vector{Float64}[], Vector{Float64}[], Vector{Float64}[],
        Bool[], Bool[], Bool[], (SexBuckets(), SexBuckets()), Int[], Int[], Float64[], Float64[],
    )
end

"""Of childbearing age, with a sex."""
sex_eligible(a::Agent) = a.sex !== :none && a.fertility_start <= a.age < a.fertility_end

"""The mean and population sd of `f` over `agents`, NaN for none."""
function mean_sd(f, agents::Vector{Agent})
    n = length(agents)
    n == 0 && return NaN, NaN
    mean = sum(f, agents) / n
    return mean, sqrt(sum(a -> (f(a) - mean)^2, agents) / n)
end

"""
    sex_period!(r, m)

The end of a period, after `step!` (or period 0, before the first): reads the period's fertile agents, their mates in
reach and within vision, the step's mating attempts from `m.mate_log` (then empties it), the traits, and the fertile
lives that end. The first call copies `m.rng` and turns the log on. Call it once per period, in order, from period 0.
"""
function sex_period!(r::SexReadings, m::Model)
    cfg, t = m.config, m.t
    threshold = cfg.fertility_threshold
    r.rng === nothing && (r.rng = copy(m.rng))
    m.mate_log === nothing && (m.mate_log = MateEvent[])
    empty!(r.ended)

    # the step's attempts: births and failures, and each parent's children
    births = no_site = 0
    distances, shares = empty!(r.distances), empty!(r.shares)
    for e in m.mate_log
        if e.born
            births += 1
            push!(distances, e.distance)
            push!(shares, e.distance / e.seeker_vision)
            for id in (e.seeker, e.partner)
                life = get(r.lives, id, nothing)
                life === nothing || (life.children += 1)
            end
        else
            no_site += 1
        end
    end
    mean_distance = births == 0 ? NaN : sum(distances) / births
    mean_share = births == 0 ? NaN : sum(shares) / births
    empty!(m.mate_log)
    speed = xxl_on(cfg, :speed)

    # the step's deaths: a fertile life ends with a death after childbearing age began
    for a in m.dead_this_step
        life = pop!(r.lives, a.id, nothing)
        life === nothing && continue
        a.age >= a.fertility_start && end_life!(r, a, life, t, a.age >= a.fertility_end ? 0 : 1, speed)
    end

    agents = m.agents
    n = length(agents)
    fertile = resize!(r.fertile, n)
    reach = fill!(resize!(r.reach, n), false)
    nfertile = nreach = neligible = 0
    own, m.rng = m.rng, r.rng  # a look in sight draws random numbers: the observer's, so the run is unchanged
    try
        for (i, a) in enumerate(agents)  # as push_fertility!: the same agents, in the same order
            neligible += sex_eligible(a)
            fertile[i] = is_fertile(a, threshold)
            fertile[i] || continue
            nfertile += 1
            reach[i] = any(o -> o.sex !== a.sex && is_fertile(o, threshold), mate_reach(m, a))
            nreach += reach[i]
        end
    finally
        m.rng = own
    end
    vision = fill!(resize!(r.vision, n), false)
    if xxl_on(cfg, :disc)
        disc_vision!(r, m)
    else
        lattice_vision!(r, m)
    end
    nvision = count(vision)

    for (i, a) in enumerate(agents)
        life = get(r.lives, a.id, nothing)
        if life === nothing
            (a.sex === :none || a.age >= a.fertility_end) && continue  # no sex, or past its fertile life when first seen
            life = r.lives[a.id] = FertileLife(0, 0, 0, 0, length(a.children))
        end
        if a.age >= a.fertility_end
            delete!(r.lives, a.id)
            end_life!(r, a, life, t, 0, speed)
            continue
        end
        sex_eligible(a) || continue
        life.eligible += 1
        fertile[i] || continue
        life.fertile += 1
        life.reach += reach[i]
        life.vision += vision[i]
    end
    sort!(r.ended; by=row -> row[1])
    append!(r.agents, r.ended)
    t % 100 == 0 && forget_gone!(r, m)

    vision_mean, vision_sd = mean_sd(a -> a.vision, agents)
    metabolism_mean, metabolism_sd = mean_sd(a -> a.metabolism, agents)
    spice_mean, spice_sd = mean_sd(a -> a.spice_metabolism, agents)
    speed_mean, speed_sd = speed ? mean_sd(a -> a.speed, agents) : (NaN, NaN)
    push!(
        r.rows,
        Float64[
            t, n, neligible, nfertile, nreach, nvision, births, no_site,
            mean_distance, median!(distances), mean_share, median!(shares),
            vision_mean, vision_sd, metabolism_mean, metabolism_sd, spice_mean, spice_sd, speed_mean, speed_sd,
        ],
    )
    return nothing
end

"""Records the end of `a`'s fertile life at period `t` in the snapshot, if `t` is in the window."""
function end_life!(r::SexReadings, a::Agent, life::FertileLife, t::Int, reason::Int, speed::Bool)
    r.window[1] <= t <= r.window[2] || return nothing
    push!(
        r.ended,
        Float64[
            a.id, a.sex === :M ? 1 : 0, t, reason, life.eligible, life.fertile, life.reach, life.vision,
            life.children, a.vision, a.metabolism, speed ? a.speed : NaN,
        ],
    )
    return nothing
end

"""Drops the lives of agents no longer living, a guard against an agent that left without a recorded death."""
function forget_gone!(r::SexReadings, m::Model)
    living = Set(a.id for a in m.agents)
    filter!(p -> p.first in living, r.lives)
    return nothing
end

"""
Marks in `r.vision` each fertile agent with a fertile agent of the other sex on one of the four lattice lines from it,
at every distance its look can reach: 1 to stride·(V ÷ stride) + stride − 1 (1 to V at stride 1).
"""
function lattice_vision!(r::SexReadings, m::Model)
    threshold = m.config.fertility_threshold
    s = m.config.look_stride
    for (i, a) in enumerate(m.agents)
        r.fertile[i] || continue
        found = false
        for (dx, dy) in VON_NEUMANN, k in 1:(s * (a.vision ÷ s) + s - 1)
            o = agent_at(m, a.x + dx * k, a.y + dy * k)
            if o !== nothing && o.sex !== a.sex && is_fertile(o, threshold)
                found = true
                break
            end
        end
        r.vision[i] = found
    end
    return nothing
end

"""
Marks in `r.vision` each fertile agent with a fertile agent of the other sex within its vision disc,
0 < dx² + dy² ≤ V² in torus distance, from a bucket grid of the fertile agents by sex.
"""
function disc_vision!(r::SexReadings, m::Model)
    w, h = m.config.width, m.config.height
    nbx, nby = cld(w, SEX_BUCKET), cld(h, SEX_BUCKET)
    women, men = r.buckets
    fill_buckets!(women, r, m, :F, nbx, nby)
    fill_buckets!(men, r, m, :M, nbx, nby)
    for (i, a) in enumerate(m.agents)
        r.fertile[i] || continue
        b = a.sex === :F ? men : women
        v = a.vision
        v2 = v * v
        span_buckets!(r.bx, a.x, v, w, nbx)
        span_buckets!(r.by, a.y, v, h, nby)
        found = false
        for byi in r.by, bxi in r.bx
            k = byi * nbx + bxi + 1
            for j in b.first[k]:(b.first[k + 1] - 1)
                d2 = torus_dist2(w, h, a.x, a.y, @inbounds(b.xs[j]), @inbounds(b.ys[j]))
                if 0 < d2 <= v2
                    found = true
                    break
                end
            end
            found && break
        end
        r.vision[i] = found
    end
    return nothing
end

"""Sorts the fertile agents of sex `sex` into `b` by bucket (a counting sort)."""
function fill_buckets!(b::SexBuckets, r::SexReadings, m::Model, sex::Symbol, nbx::Int, nby::Int)
    first = fill!(resize!(b.first, nbx * nby + 1), 0)
    bucket(a) = (a.y ÷ SEX_BUCKET) * nbx + a.x ÷ SEX_BUCKET + 1
    for (i, a) in enumerate(m.agents)  # count each bucket's agents
        (r.fertile[i] && a.sex === sex) && (first[bucket(a)] += 1)
    end
    running = 1
    for k in eachindex(first)  # first[k]: one past bucket k's end
        running += first[k]
        first[k] = running
    end
    total = first[end] - 1
    xs, ys = resize!(b.xs, total), resize!(b.ys, total)
    for (i, a) in enumerate(m.agents)  # fill each bucket from its end, so first[k] counts down to its start
        (r.fertile[i] && a.sex === sex) || continue
        k = bucket(a)
        first[k] -= 1
        xs[first[k]], ys[first[k]] = a.x, a.y
    end
    return b
end

"""The buckets (0-based) along an axis of length `len` that the sites p - v .. p + v span, wrapped."""
function span_buckets!(out::Vector{Int}, p::Int, v::Int, len::Int, nb::Int)
    empty!(out)
    if 2v + 1 >= len
        append!(out, 0:(nb - 1))
        return out
    end
    q, left = p - v, 2v + 1
    while left > 0
        u = mod(q, len)
        k = u ÷ SEX_BUCKET
        push!(out, k)
        step = min((k + 1) * SEX_BUCKET, len) - u
        q += step
        left -= step
    end
    return out
end

"""
    sex_rows(r) -> (header, rows)

One row per period read, t = 0 included, in the order of [`SEX_COLUMNS`](@ref). A column with nothing to average is NaN;
the speed columns are NaN in a world without speed.
"""
sex_rows(r::SexReadings) = (copy(SEX_COLUMNS), r.rows)

"""
    sex_agent_rows(r) -> (header, rows)

The snapshot, one row per agent whose fertile life ended in the window, in the order of [`SEX_AGENT_COLUMNS`](@ref),
by end period and then id. `sex` is 0 for F and 1 for M; `speed` is NaN in a world without speed.
"""
sex_agent_rows(r::SexReadings) = (copy(SEX_AGENT_COLUMNS), r.agents)
