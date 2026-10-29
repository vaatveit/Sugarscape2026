# xxl: the scorecard's opt-in metric columns (revised spec, "New metrics"). Only a scorecard run appends them, after
# the xxl nine, so ordinary `--xxl` output is unchanged. They need the previous period, which a `ScorecardTracker` keeps.

const SCORECARD_COLUMNS = [
    "deaths_sugar",
    "deaths_spice",
    "deaths_old_age",
    "deaths_killed",
    "births",
    "n_fertile",
    "n_fertile_with_mate",
    "tag_flips_per_agent",
    "share_traded_10",
    "loans_started",
    "loans_rolled",
    "loans_repaid",
    "loans_voided",
    "viable_fallbacks",
]

const TRADE_WINDOW = 10  # share_traded_10: agents with a trade in the last this many periods (X5)

"""
    ScorecardTracker(m)

What the scorecard columns need from the previous period, taken from `m` as it is now: each living agent's tags by
id, the id the next agent will get, and the loan book by object identity; and, kept across periods, each agent's last
trade period by id. Build it with the model and pass it to [`scorecard_metrics!`](@ref) once per period, t = 0
included.
"""
mutable struct ScorecardTracker
    t::Int  # the period last seen
    next_id::Int  # m.next_id then: ids from here on are new agents
    tags::Dict{Int,UInt64}  # the living agents' tags then, by id
    last_trade::Dict{Int,Int}  # each agent's last period with a trade, by id, within the trade window
    loans::Set{Loan}  # the loan book then; Loan is mutable, so the set is by identity
end

function ScorecardTracker(m::Model)
    tr = ScorecardTracker(m.t, m.next_id, Dict{Int,UInt64}(), Dict{Int,Int}(), Set{Loan}())
    remember_period!(tr, m)
    return tr
end

"""Takes this period's tags, next id and loan book as the tracker's previous period."""
function remember_period!(tr::ScorecardTracker, m::Model)
    tr.t, tr.next_id = m.t, m.next_id
    empty!(tr.tags)
    for a in m.agents
        tr.tags[a.id] = a.tags
    end
    empty!(tr.loans)
    union!(tr.loans, m.loans)
    return tr
end

"""
    scorecard_metrics!(out, m, tr) -> out

Pushes [`SCORECARD_COLUMNS`](@ref) in order for the period `m` has just ended, then makes it `tr`'s previous period
(revised spec, "New metrics"). Read after `step!`, so `m.t` is already the next period's number, and this period's
logs (`dead_this_step`, `trade_log`) are still in place.

- **Deaths** by cause, first match wins: killed (the id is in `m.killed`), old age (`age >= max_age`), sugar
  (`sugar <= 0`, so starving of both goods counts as sugar), otherwise spice. Only the xxl combat move
  ([`xxl_combat_move!`](@ref), with round vision or speed) records kills; a kill by the book's combat move counts as
  starvation.
- **Births:** the agents created this period, less one for each death when rule R replaces it.
- **Fertility:** the fertile agents (`is_fertile` with `fertility_threshold`), and those with a fertile agent of the
  other sex among [`neighbors_of`](@ref) (X2).
- **Tag flips:** the bits changed between the periods, summed over the agents alive in both, per living agent (X4).
- **Trade:** the share of the living agents with a trade, as either side of an exchange, in periods t - 9 .. t (X5).
- **Loans,** by identity between the periods. A loan gone from the book is voided if its borrower or lender is dead
  (no death follows `settle_loans!` in a period, so this is exact); otherwise it was settled. A settled loan rolled
  over if a new loan between the same lender and borrower appeared, as [`settle_loans!`](@ref) rolls an unpaid rest
  into one, and was repaid otherwise; those continuations are not started loans, so `loans_started` counts
  [`seek_credit!`](@ref)'s loans. Each chain of a loan and its rollovers thus ends once, repaid or voided (X8).
  Matching is per pair: a loan repaid in the period its pair took out a fresh loan counts as rolled, with the fresh
  loan not started. Under inheritance a dead lender's loans count as voided and their heirs' as started; a loan both
  made and voided within one period is in neither.
- **Placement:** `m.viable_fallbacks`, cumulative.

A column whose rule is off is `NaN`: births and fertility without sex, tag flips without culture, the trade share
without trade, the loans without credit; so are tag flips and the trade share with no living agents. At t = 0 (the
tracker's own period) there is no previous period: tag flips and the trade share are `NaN`, the counts 0.
"""
function scorecard_metrics!(out, m::Model, tr::ScorecardTracker)
    cfg, agents = m.config, m.agents
    n = length(agents)
    first = m.t == tr.t  # t = 0: the tracker was built in this period
    sugar = spice = old = killed = 0
    if !first
        for a in m.dead_this_step
            if a.id in m.killed
                killed += 1
            elseif a.age >= a.max_age
                old += 1
            elseif a.sugar <= 0
                sugar += 1
            else
                spice += 1
            end
        end
    end
    push!(out, sugar, spice, old, killed)
    if cfg.sex
        born = first ? 0 : m.next_id - tr.next_id
        cfg.replacement && !first && (born -= length(m.dead_this_step))
        push!(out, born)
        push_fertility!(out, m)
    else
        push!(out, NaN, NaN, NaN)
    end
    push!(out, cfg.culture && !first && n > 0 ? tag_flips(m, tr) / n : NaN)
    push!(out, cfg.trade && !first && n > 0 ? share_traded(m, tr) : NaN)
    if cfg.credit === nothing
        push!(out, NaN, NaN, NaN, NaN)
    elseif first
        push!(out, 0, 0, 0, 0)
    else
        push!(out, loan_flows(m, tr)...)
    end
    push!(out, m.viable_fallbacks)
    remember_period!(tr, m)
    return out
end

function push_fertility!(out, m::Model)
    threshold = m.config.fertility_threshold
    fertile = with_mate = 0
    for a in m.agents
        is_fertile(a, threshold) || continue
        fertile += 1
        any(o -> o.sex !== a.sex && is_fertile(o, threshold), neighbors_of(m, a)) &&
            (with_mate += 1)
    end
    return push!(out, fertile, with_mate)
end

"""The bits flipped since the previous period, over the agents alive in both."""
function tag_flips(m::Model, tr::ScorecardTracker)
    flips = 0
    for a in m.agents
        old = get(tr.tags, a.id, nothing)
        old === nothing || (flips += count_ones(old ⊻ a.tags))
    end
    return flips
end

"""Records this period's traders in `tr.last_trade` and returns the living share that traded within the window."""
function share_traded(m::Model, tr::ScorecardTracker)
    t, last = m.t, tr.last_trade
    for e in m.trade_log
        last[e.a.id] = t
        last[e.b.id] = t
    end
    since = t - TRADE_WINDOW + 1
    filter!(p -> p.second >= since, last)  # the window's traders only, living or dead
    return count(a -> haskey(last, a.id), m.agents) / length(m.agents)
end

"""(started, rolled, repaid, voided) for this period, from the loan book against the previous period's."""
function loan_flows(m::Model, tr::ScorecardTracker)
    pair(loan) = (loan.lender.id, loan.borrower.id)
    settled = Dict{Tuple{Int,Int},Int}()  # loans settled this period, by (lender, borrower)
    fresh = Dict{Tuple{Int,Int},Int}()  # loans new this period, by (lender, borrower)
    voided = 0
    now = Set{Loan}(m.loans)
    for loan in tr.loans
        loan in now && continue
        if loan.borrower.alive && loan.lender.alive
            settled[pair(loan)] = get(settled, pair(loan), 0) + 1
        else
            voided += 1
        end
    end
    for loan in m.loans
        loan in tr.loans || (fresh[pair(loan)] = get(fresh, pair(loan), 0) + 1)
    end
    rolled = sum((min(k, get(fresh, p, 0)) for (p, k) in settled); init=0)
    repaid = sum(values(settled); init=0) - rolled
    started = sum(values(fresh); init=0) - rolled
    return started, rolled, repaid, voided
end
