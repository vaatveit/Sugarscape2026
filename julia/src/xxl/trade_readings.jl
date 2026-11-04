# xxl (stage 5): the trade readings (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 1"). An observer that
# reads who trades with whom, period by period, and keeps the holdings of the agents the traders-against-non-traders
# comparison needs. It draws no random numbers and changes no agent. `timed_seed` calls `trade_period!` after each `step!`
# (and once before the first, for a window that starts at period 1), while `m.trade_log` still holds that period's
# exchanges: `step!` empties it at the start of the next.
#
# Health, at the end of each period: sick has an active disease, recovering has none but had one in the last
# `RECOVERING_PERIODS` periods, healthy is the rest. An exchange is classed by its two agents' health at the end of its
# own period, though one of them may have died later in it: a dead agent keeps its diseases. The exchange counts
# (`exchanges_hh`, `_hs`, `_ss`), the neighbour pairs (`pairs_*`) and the MRS gaps (`gap_healthy`, `gap_sick`) take a
# recovering agent as healthy, as the spec reads the pairs; `healthy_healthy_10` and the snapshot's
# `exchanges_healthy_partner` take only the healthy, which is the column `healthy` (our call).

"""How many periods after its last disease an agent still counts as recovering."""
const RECOVERING_PERIODS = 10

"""Periods a healthy-with-healthy exchange keeps its two agents counted in `healthy_healthy_10`: this one and 9 before."""
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
]

"""An agent of the snapshot as it stood at the end of the period before the window, and its exchanges since."""
mutable struct WindowAgent
    metabolism::Float64
    spice_metabolism::Float64
    vision::Float64
    age::Float64
    sugar::Float64
    spice::Float64
    exchanges::Int
    healthy_partner::Int
end

"""
    TradeReadings(; window)

The trade observer of a run. `window = (first, last)` is the periods the agent snapshot covers: the agents alive at the
end of period `first - 1` and of `last`, and never sick or recovering from `first` to `last`, get a row in
[`agent_rows`](@ref), with their holdings at both ends and their exchanges over the window. [`trade_rows`](@ref) has a row
for every period run, t ≥ 1. Feed it with [`trade_period!`](@ref).
"""
mutable struct TradeReadings
    window::Tuple{Int,Int}
    last_sick::Dict{Int,Int}  # agent id => the last period it was seen sick
    healthy_partner::Dict{Int,Int}  # agent id => the last period it had an exchange with a healthy partner
    rows::Vector{Vector{Float64}}
    candidates::Dict{Int,WindowAgent}  # the snapshot's agents so far, by id
    agents::Vector{Vector{Float64}}  # the snapshot's rows, once the window is over
    sick_seen::Set{Int}  # scratch: the sick agents in this period's exchanges
    gaps_healthy::Vector{Float64}  # scratch: the MRS gaps of a neighbour reading
    gaps_sick::Vector{Float64}
end

function TradeReadings(; window::Tuple{Int,Int})
    1 <= window[1] <= window[2] ||
        throw(ArgumentError("the window needs 1 <= first <= last, got $window"))
    return TradeReadings(
        window,
        Dict{Int,Int}(),
        Dict{Int,Int}(),
        Vector{Float64}[],
        Dict{Int,WindowAgent}(),
        Vector{Float64}[],
        Set{Int}(),
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
        else
            state == RECOVERING ? (recovering += 1) : (sick += 1)
            in_window && delete!(r.candidates, a.id)
        end
        moved += a.moved_dist
    end

    hh = hs = ss = with_recovering = 0
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
        end
        (ha == RECOVERING || hb == RECOVERING) && (with_recovering += 1)
        if ha == HEALTHY && hb == HEALTHY
            r.healthy_partner[e.a.id] = t
            r.healthy_partner[e.b.id] = t
        end
        if in_window
            count_exchange!(r, e.a, hb == HEALTHY)
            count_exchange!(r, e.b, ha == HEALTHY)
        end
    end

    recent = 0  # healthy agents with a healthy partner in the last HEALTHY_PARTNER_PERIODS periods
    for a in m.agents
        health(r, a, t) == HEALTHY || continue
        get(r.healthy_partner, a.id, -HEALTHY_PARTNER_PERIODS) > t - HEALTHY_PARTNER_PERIODS && (recent += 1)
    end

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
        healthy == 0 ? NaN : recent / healthy,
        n == 0 ? NaN : moved / n,
        NaN, NaN, NaN, NaN, NaN,
    ]
    t % NEIGHBOUR_EVERY == 0 && read_neighbours!(row, r, m, t)
    push!(r.rows, row)

    t == w2 && finish_snapshot!(r, m)
    t % 100 == 0 && forget_old!(r, t)
    return nothing
end

function count_exchange!(r::TradeReadings, a::Agent, partner_healthy::Bool)
    w = get(r.candidates, a.id, nothing)
    w === nothing && return nothing
    w.exchanges += 1
    partner_healthy && (w.healthy_partner += 1)
    return nothing
end

"""The start of the snapshot: every living agent as it stands at the end of the period before the window."""
function keep_start!(r::TradeReadings, m::Model)
    empty!(r.candidates)
    for a in m.agents
        r.candidates[a.id] = WindowAgent(
            a.metabolism, a.spice_metabolism, a.vision, a.age, a.sugar, a.spice, 0, 0
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
                w.exchanges, w.healthy_partner,
            ],
        )
    end
    sort!(r.agents; by=row -> row[1])
    empty!(r.candidates)
    return nothing
end

"""
Fills the neighbour columns of `row` for period `t`: the unordered neighbour pairs by health (recovering as healthy), and
the median |log MRS gap| over the (agent, neighbour) pairs whose first agent is not sick (`gap_healthy`; recovering as
healthy) and whose is sick (`gap_sick`), with both MRSs valid. `neighbors_of` returns the model's scratch list, so each agent's is used up before the next call.
"""
function read_neighbours!(row::Vector{Float64}, r::TradeReadings, m::Model, t::Int)
    cultural = m.config.cultural_preferences
    empty!(r.gaps_healthy)
    empty!(r.gaps_sick)
    hh = hs = ss = 0
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
            end
            mb = mrs(b, cultural)
            valid_mrs(ma) && valid_mrs(mb) || continue
            push!(ha == SICK ? r.gaps_sick : r.gaps_healthy, abs(log(ma) - log(mb)))
        end
    end
    row[13], row[14], row[15] = hh, hs, ss
    row[16], row[17] = median!(r.gaps_healthy), median!(r.gaps_sick)
    return nothing
end

"""Drops the records too old to matter, so a long run's tables stay the size of its living."""
function forget_old!(r::TradeReadings, t::Int)
    filter!(p -> t - p.second <= RECOVERING_PERIODS, r.last_sick)
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
