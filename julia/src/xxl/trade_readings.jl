# xxl (stage 5): the trade readings (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 1"). An observer that
# reads who trades with whom, period by period, and keeps the holdings of the agents the traders-against-non-traders
# comparison needs. It draws no random numbers and changes no agent. `timed_seed` calls `trade_period!` after each `step!`
# (and once before the first, for a window that starts at period 1), while `m.trade_log` still holds that period's
# exchanges: `step!` empties it at the start of the next.
#
# Health, at the end of each period: sick has an active disease, recovering has none but had one in the last
# `RECOVERING_PERIODS` periods, healthy is the rest. An exchange is classed by its two agents' health at the end of its
# own period, though one of them may have died later in it: a dead agent keeps its diseases. The spec's healthy is no
# active disease, so a recovering agent counts as healthy in the exchange counts (`exchanges_hh`, `_hs`, `_ss`), the
# neighbour pairs (`pairs_*`), the MRS gaps (`gap_healthy`, `gap_sick`), `healthy_healthy_10` and the snapshot, and is
# also counted as a group of its own (`recovering`, `exchanges_recovering`, and the snapshot's two recovering flags).
# The columns `healthy`, `recovering` and `sick` are the three groups apart. `healthy_healthy_10_strict` is the same
# share among the strictly healthy, neither sick nor recovering, with a strictly healthy partner. The last columns read
# the strictly healthy apart from the rest: `exchanges_HH` (both), `exchanges_HX` (exactly one), `gap_strict` (the MRS
# gaps of the strictly healthy) and `pairs_HH`, `pairs_HX` (the neighbour pairs). Which of these decide is the report's
# (julia/src/xxl/trade_report.jl): by the user's decision after Part 1, the strict ones. The last two columns read the
# meetings (stage 5b): `bargain!` runs a pair's whole meeting before the next pair's, so a meeting is a maximal run of
# consecutive exchanges in `m.trade_log` between the same two agents (the same pair can meet again later in the period,
# on the other agent's turn: a new meeting). `meetings` counts them; `meeting_price_sd` is the population sd of the log
# of their prices, each taken from its first exchange (NaN with fewer than two meetings).

"""How many periods after its last disease an agent still counts as recovering."""
const RECOVERING_PERIODS = 10

"""
Periods an exchange between two agents with no active disease keeps them counted in `healthy_healthy_10` (and one
between two strictly healthy agents in `healthy_healthy_10_strict`): this one and 9 before.
"""
const HEALTHY_PARTNER_PERIODS = 10

"""Every this many periods the neighbour pairs and MRS gaps are read."""
const NEIGHBOUR_EVERY = 10

const HEALTHY, RECOVERING, SICK = 0, 1, 2

"The columns of a per-period row, `trade_rows`."
const TRADE_COLUMNS = [
    "t",
    "healthy",
    "recovering",
    "sick",
    "exchanges",
    "exchanges_hh",
    "exchanges_hs",
    "exchanges_ss",
    "exchanges_recovering",
    "sick_traders",
    "healthy_healthy_10",
    "walked",
    "pairs_hh",
    "pairs_hs",
    "pairs_ss",
    "gap_healthy",
    "gap_sick",
    "healthy_healthy_10_strict",
    "exchanges_HH",
    "exchanges_HX",
    "gap_strict",
    "pairs_HH",
    "pairs_HX",
    "meetings",
    "meeting_price_sd",
]

"The columns of an agent's snapshot row, `agent_rows`."
const TRADE_AGENT_COLUMNS = [
    "id",
    "metabolism",
    "spice_metabolism",
    "vision",
    "age_start",
    "sugar_start",
    "spice_start",
    "sugar_end",
    "spice_end",
    "exchanges",
    "exchanges_healthy_partner",
    "recovering_start",
    "recovering_in_window",
]

"""
An agent of the snapshot as it stood at the end of the period before the window, and since then its exchanges, those
with a partner with no active disease, and whether it was recovering at the end of any period of the window.
"""
mutable struct WindowAgent
    metabolism::Float64
    spice_metabolism::Float64
    vision::Float64
    age::Float64
    sugar::Float64
    spice::Float64
    recovering_start::Bool
    exchanges::Int
    healthy_partner::Int
    recovering_in_window::Bool
end

"""
    TradeReadings(; window)

The trade observer of a run. `window = (first, last)` is the periods the agent snapshot covers: the agents alive at the
end of period `first - 1` and of `last`, with no active disease at the end of any period from `first` to `last` (a
recovering agent qualifies), get a row in [`agent_rows`](@ref), with their holdings at both ends, their exchanges over the
window, and whether they were recovering at its start and in it, so that the strictly healthy can be told apart.
[`trade_rows`](@ref) has a row for every period run, t ≥ 1. Feed it with [`trade_period!`](@ref).
"""
mutable struct TradeReadings
    window::Tuple{Int,Int}
    last_sick::Dict{Int,Int}  # agent id => the last period it was seen sick
    well_partner::Dict{Int,Int}  # agent id => the last period it and its partner in an exchange had no active disease
    healthy_partner::Dict{Int,Int}  # agent id => the same with both strictly healthy (neither sick nor recovering)
    rows::Vector{Vector{Float64}}
    candidates::Dict{Int,WindowAgent}  # the snapshot's agents so far, by id
    agents::Vector{Vector{Float64}}  # the snapshot's rows, once the window is over
    sick_seen::Set{Int}  # scratch: the sick agents in this period's exchanges
    gaps_healthy::Vector{Float64}  # scratch: the MRS gaps of a neighbour reading
    gaps_sick::Vector{Float64}
    gaps_strict::Vector{Float64}
end

function TradeReadings(; window::Tuple{Int,Int})
    1 <= window[1] <= window[2] ||
        throw(ArgumentError("the window needs 1 <= first <= last, got $window"))
    return TradeReadings(
        window,
        Dict{Int,Int}(),
        Dict{Int,Int}(),
        Dict{Int,Int}(),
        Vector{Float64}[],
        Dict{Int,WindowAgent}(),
        Vector{Float64}[],
        Set{Int}(),
        Float64[],
        Float64[],
        Float64[],
    )
end

"""The health of `a` at the end of period `t`: `HEALTHY`, `RECOVERING` or `SICK`."""
function health(r::TradeReadings, a::Agent, t::Int)
    isempty(a.diseases) || return SICK
    since = get(r.last_sick, a.id, -RECOVERING_PERIODS - 1)
    return t - since <= RECOVERING_PERIODS ? RECOVERING : HEALTHY
end

"""The median of `v` (sorted in place); NaN if it is empty."""
function median!(v::Vector{Float64})
    n = length(v)
    n == 0 && return NaN
    sort!(v)
    return isodd(n) ? v[(n + 1) ÷ 2] : (v[n ÷ 2] + v[n ÷ 2 + 1]) / 2
end

"""
    trade_period!(r, m)

The end of a period, after `step!` (or period 0, before the first step): reads this period's exchanges from
`m.trade_log` and the agents' health, and, every [`NEIGHBOUR_EVERY`](@ref)th period, their neighbours. Call it once per
period, in order.
"""
function trade_period!(r::TradeReadings, m::Model)
    t = m.t
    w1, w2 = r.window
    for a in m.agents
        isempty(a.diseases) || (r.last_sick[a.id] = t)
    end
    t == w1 - 1 && keep_start!(r, m)
    t >= 1 || return nothing

    in_window = w1 <= t <= w2
    healthy = recovering = sick = 0
    moved = 0.0
    for a in m.agents
        state = health(r, a, t)
        if state == HEALTHY
            healthy += 1
        elseif state == RECOVERING
            recovering += 1
            if in_window
                w = get(r.candidates, a.id, nothing)
                w === nothing || (w.recovering_in_window = true)
            end
        else
            sick += 1
            in_window && delete!(r.candidates, a.id)
        end
        moved += a.moved_dist
    end

    hh = hs = ss = with_recovering = strict_both = strict_one = 0
    empty!(r.sick_seen)
    for e in m.trade_log
        ha, hb = health(r, e.a, t), health(r, e.b, t)
        sa, sb = ha == SICK, hb == SICK
        sa && push!(r.sick_seen, e.a.id)
        sb && push!(r.sick_seen, e.b.id)
        if sa && sb
            ss += 1
        elseif sa || sb
            hs += 1
        else
            hh += 1
            r.well_partner[e.a.id] = t
            r.well_partner[e.b.id] = t
        end
        (ha == RECOVERING || hb == RECOVERING) && (with_recovering += 1)
        if ha == HEALTHY && hb == HEALTHY
            strict_both += 1
            r.healthy_partner[e.a.id] = t
            r.healthy_partner[e.b.id] = t
        elseif ha == HEALTHY || hb == HEALTHY
            strict_one += 1
        end
        if in_window
            count_exchange!(r, e.a, !sb)
            count_exchange!(r, e.b, !sa)
        end
    end

    # Agents with no active disease who had a partner with none in the last HEALTHY_PARTNER_PERIODS periods, and the
    # strictly healthy who had a strictly healthy one.
    recent = recent_strict = 0
    since = t - HEALTHY_PARTNER_PERIODS
    for a in m.agents
        state = health(r, a, t)
        state == SICK && continue
        get(r.well_partner, a.id, since) > since && (recent += 1)
        state == HEALTHY && get(r.healthy_partner, a.id, since) > since && (recent_strict += 1)
    end
    well = healthy + recovering

    meetings, meeting_sd = meeting_readings(m.trade_log)

    n = length(m.agents)
    row = Float64[
        t,
        healthy,
        recovering,
        sick,
        length(m.trade_log),
        hh,
        hs,
        ss,
        with_recovering,
        length(r.sick_seen),
        well == 0 ? NaN : recent / well,
        n == 0 ? NaN : moved / n,
        NaN, NaN, NaN, NaN, NaN,
        healthy == 0 ? NaN : recent_strict / healthy,
        strict_both,
        strict_one,
        NaN, NaN, NaN,
        meetings,
        meeting_sd,
    ]
    t % NEIGHBOUR_EVERY == 0 && read_neighbours!(row, r, m, t)
    push!(r.rows, row)

    t == w2 && finish_snapshot!(r, m)
    t % 100 == 0 && forget_old!(r, t)
    return nothing
end

"""
The number of meetings in `exchanges` (maximal runs of consecutive exchanges between the same two agents) and the
population sd of the log of their prices, each meeting's price taken from its first exchange; the sd is NaN with fewer
than two meetings.
"""
function meeting_readings(exchanges::Vector{Exchange})
    prices = Float64[]
    prev = (0, 0)
    for e in exchanges
        pair = minmax(e.a.id, e.b.id)
        pair == prev && continue
        prev = pair
        push!(prices, log(e.price))
    end
    n = length(prices)
    n < 2 && return n, NaN
    mean = sum(prices) / n
    return n, sqrt(sum(x -> (x - mean)^2, prices) / n)
end

function count_exchange!(r::TradeReadings, a::Agent, partner_healthy::Bool)
    w = get(r.candidates, a.id, nothing)
    w === nothing && return nothing
    w.exchanges += 1
    partner_healthy && (w.healthy_partner += 1)
    return nothing
end

"""
The start of the snapshot: every living agent as it stands at the end of the period before the window, with whether it
is recovering then.
"""
function keep_start!(r::TradeReadings, m::Model)
    empty!(r.candidates)
    t = m.t
    for a in m.agents
        r.candidates[a.id] = WindowAgent(
            a.metabolism, a.spice_metabolism, a.vision, a.age, a.sugar, a.spice, health(r, a, t) == RECOVERING, 0, 0,
            false,
        )
    end
    return nothing
end

"""The end of the window: a row for each agent that was kept from the start and is alive still, in order of id."""
function finish_snapshot!(r::TradeReadings, m::Model)
    empty!(r.agents)
    for a in m.agents
        w = get(r.candidates, a.id, nothing)
        w === nothing && continue
        push!(
            r.agents,
            Float64[
                a.id, w.metabolism, w.spice_metabolism, w.vision, w.age, w.sugar, w.spice, a.sugar, a.spice,
                w.exchanges, w.healthy_partner, w.recovering_start, w.recovering_in_window,
            ],
        )
    end
    sort!(r.agents; by=row -> row[1])
    empty!(r.candidates)
    return nothing
end

"""
Fills the neighbour columns of `row` for period `t`: the unordered neighbour pairs by health (recovering as healthy),
and the median |log MRS gap| over the (agent, neighbour) pairs whose first agent is not sick (`gap_healthy`; recovering
as healthy) and whose is sick (`gap_sick`), with both MRSs valid; and the same strictly: the pairs with both agents
strictly healthy (`pairs_HH`) and with exactly one (`pairs_HX`), and the median gap over the pairs whose first agent is
strictly healthy (`gap_strict`). `neighbors_of` returns the model's scratch list, so each agent's is used up before the
next call.
"""
function read_neighbours!(row::Vector{Float64}, r::TradeReadings, m::Model, t::Int)
    cultural = m.config.cultural_preferences
    empty!(r.gaps_healthy)
    empty!(r.gaps_sick)
    empty!(r.gaps_strict)
    hh = hs = ss = strict_both = strict_one = 0
    for a in m.agents
        ha = health(r, a, t)
        ma = mrs(a, cultural)
        for b in neighbors_of(m, a)
            hb = health(r, b, t)
            if a.id < b.id
                if ha == SICK && hb == SICK
                    ss += 1
                elseif ha == SICK || hb == SICK
                    hs += 1
                else
                    hh += 1
                end
                if ha == HEALTHY && hb == HEALTHY
                    strict_both += 1
                elseif ha == HEALTHY || hb == HEALTHY
                    strict_one += 1
                end
            end
            mb = mrs(b, cultural)
            valid_mrs(ma) && valid_mrs(mb) || continue
            gap = abs(log(ma) - log(mb))
            push!(ha == SICK ? r.gaps_sick : r.gaps_healthy, gap)
            ha == HEALTHY && push!(r.gaps_strict, gap)
        end
    end
    row[13], row[14], row[15] = hh, hs, ss
    row[16], row[17] = median!(r.gaps_healthy), median!(r.gaps_sick)
    row[21], row[22], row[23] = median!(r.gaps_strict), strict_both, strict_one
    return nothing
end

"""Drops the records too old to matter, so a long run's tables stay the size of its living."""
function forget_old!(r::TradeReadings, t::Int)
    filter!(p -> t - p.second <= RECOVERING_PERIODS, r.last_sick)
    filter!(p -> t - p.second < HEALTHY_PARTNER_PERIODS, r.well_partner)
    filter!(p -> t - p.second < HEALTHY_PARTNER_PERIODS, r.healthy_partner)
    return nothing
end

"""
    trade_rows(r) -> (header, rows)

One row per period run, t ≥ 1, in the order of [`TRADE_COLUMNS`](@ref). The pair and gap columns are NaN except in
every tenth period.
"""
trade_rows(r::TradeReadings) = (copy(TRADE_COLUMNS), r.rows)

"""
    agent_rows(r) -> (header, rows)

The snapshot, one row per agent in the order of [`TRADE_AGENT_COLUMNS`](@ref), by id; empty until the window's last
period has been read.
"""
agent_rows(r::TradeReadings) = (copy(TRADE_AGENT_COLUMNS), r.agents)
