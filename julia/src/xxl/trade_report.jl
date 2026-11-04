# xxl (stage 5): the trade study's report (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 1" and "Part 3").
# Finished study folders (julia/src/xxl/trade_study.jl) read against bars fixed before any screening run: Part 1's
# readings and the row of "What Part 1 decides" that fires, the screening's reading table, choice and result row, and the
# confirmation's matched ratio, each with the trade-off reading beside it. It reads only finished CSVs and runs nothing,
# so the bars are code that can be tested before any result exists (julia/xxl_trade_report.jl is its command line).
#
# Healthy, in every bar and Part 1 word, is strictly healthy: no disease for 10 periods, neither sick nor recovering
# (julia/src/xxl/trade_readings.jl), by the user's decision after Part 1. The bar's matched ratio is over the snapshot's
# agents with neither recovering flag, and Part 1's words read `healthy_healthy_10_strict`, `exchanges_HH`/`_HX` and
# `gap_strict`. The spec's wider reading, no active disease with a recovering agent counted as healthy, is reported
# beside each and decides nothing. The healthy-trade bar is dropped (the user's): its share is a reading.

# The bars, fixed before any screening run (my call, from the spec's reading table and Part 1's words).
const RICHER_BAR = 1.10  # traders ÷ similar non-traders, strictly healthy, with the interval above 1
# Part 1's "common" only, not a screening bar (controller's ruling after Part 1): healthy_healthy_10_strict, the mean
# over t = 451–500, at least this
const COMMON_SHARE = 0.25
const NO_DISEASE_FACTOR = 2.0  # trades per head with no disease, against today's
const SICK_TRADE_FACTOR = 0.5  # sick agents' trades per head, against today's
const TROUGH_MEAN_SHARE = 0.95
const TROUGH_LOW_SHARE = 0.90
const X6_BAR = 1.5  # mean over seeds of the end (last 100 periods) price_sd, ÷ xl's
const GINI_NOTE = 0.03  # a rise beyond this is said up front
const MOSTLY_SICK = 0.5  # Part 1: share of strictly healthy agents' exchanges with a partner not strictly healthy
const SMALL_GAP = 0.5  # Part 1: strictly healthy median gap ÷ sick median gap at most this
const CELL_MIN = 6  # agents in a matched cell, at least
const AGE_BAND = 10

const READ_WINDOW = (301, 500)  # the periods Part 1's readings are taken over
const HEALTHY_TRADE_T = (451, 500)  # the periods the healthy trade (Part 1's "common") is read over
const STUDY_END = 500  # a VI-1 folder (on, off, no disease) is read to this period
const SEED_EXTRA = ("mean_spice", "price_sd", "mean_moved")  # the CSV's columns read besides `read_list_run`'s

"""
    TradeSeed(list, header, rows, trade, agents)

One whole seed of a study folder: its [`ListSeed`](@ref); its CSV (`header`, `rows` from t = 0); its trade readings,
`trade[column][t]` for t ≥ 1 (see [`TRADE_COLUMNS`](@ref)); and its agent snapshot, one row an agent in the order of
[`TRADE_AGENT_COLUMNS`](@ref).
"""
struct TradeSeed
    list::ListSeed
    header::Vector{String}
    rows::Matrix{Float64}
    trade::Dict{String,Vector{Float64}}
    agents::Matrix{Float64}
end

"""
    TradeRun(run, window, trade_off, seeds)

A study folder read for the report: the [`ListRun`](@ref) [`read_list_run`](@ref) makes of it, the snapshot's `window`
from its fingerprint, whether the fingerprint says `trade: off`, and its whole seeds in `run.seeds`' order.
"""
struct TradeRun
    run::ListRun
    window::Tuple{Int,Int}
    trade_off::Bool
    seeds::Vector{TradeSeed}
end

"""
    TradeArm(name, vi1, nodisease, iva3)

An arm of the study: its VI-1 folder, and its no-disease and IV-A3 folders (`nothing` for confirmation, which reads only
VI-1).
"""
struct TradeArm
    name::String
    vi1::TradeRun
    nodisease::Union{Nothing,TradeRun}
    iva3::Union{Nothing,TradeRun}
end

"""
    read_trade_run(name, folder) -> TradeRun

A study folder (`run_trade_arm`'s), its whole seeds only (see [`read_list_run`](@ref)). `ArgumentError` for a folder whose
fingerprint names no trade readings, a whole seed without its trade readings or snapshot, or a file without the columns
the report reads.
"""
function read_trade_run(name::AbstractString, folder::AbstractString)
    run = read_list_run(name, folder)
    m = match(r"^trade readings: window=\((\d+), (\d+)\)"m, run.fingerprint)
    m === nothing && throw(ArgumentError("$folder is not a trade study folder: its fingerprint names no trade readings"))
    window = (parse(Int, m.captures[1]), parse(Int, m.captures[2]))
    seeds = TradeSeed[]
    for s in run.seeds
        k = s.series.seed
        header, rows = read_seed_csv(joinpath(folder, "seed$k.csv"))
        for c in SEED_EXTRA
            c in header || throw(ArgumentError("seed $k of $folder lacks the $c column"))
        end
        tpath, apath = trade_path(folder, k, "trade"), trade_path(folder, k, "agents")
        (isfile(tpath) && isfile(apath)) ||
            throw(ArgumentError("seed $k of $folder has its CSV but not its trade readings and snapshot"))
        th, tm = read_seed_csv(tpath)
        (th == TRADE_COLUMNS && tm[:, 1] == 1:(run.periods)) ||
            throw(ArgumentError("$tpath isn't the trade readings of t = 1 to $(run.periods)"))
        ah, am = read_seed_csv(apath)
        ah == TRADE_AGENT_COLUMNS || throw(ArgumentError("$apath doesn't have the snapshot's columns"))
        push!(seeds, TradeSeed(s, header, rows, Dict(c => tm[:, j] for (j, c) in enumerate(th)), am))
    end
    return TradeRun(run, window, occursin(r"^trade: off[ \t\r]*$"m, run.fingerprint), seeds)
end

"""The arm of the three folders `vi1`, `nodisease` and `iva3`, each read by [`read_trade_run`](@ref)."""
function read_trade_arm(name::AbstractString, vi1, nodisease, iva3)
    return TradeArm(name, read_trade_run(name, vi1), read_trade_run(name, nodisease), read_trade_run(name, iva3))
end

"""
    read_xl_prices(folder) -> (; folder, prices, partial)

The xl reference for X6: per whole seed of an xl folder (the scorecard's `scorecard-xl-s<first>-<seeds>/VI-1`, or
`…-p<periods>/VI-1` beside it, see [`trade_xl_folder`](@ref)), the end price sd, the mean of `price_sd` over the last
[`END_PERIODS`](@ref) periods (see [`end_mean`](@ref)), in the order of the seeds. A seed is whole when its CSV holds t =
0 to the folder's periods ([`seed_done`](@ref)): those of `-p<periods>`, else the registry's steps for the experiment
the folder is named for. `partial` names the seeds whose CSV isn't whole, which are left out. `ArgumentError` for a
folder with no whole seed or one without `price_sd`.
"""
function read_xl_prices(folder::AbstractString)
    isdir(folder) || throw(ArgumentError("$folder is not a folder"))
    path = rstrip(folder, ['/', '\\'])
    p = match(r"-p(\d+)$", basename(dirname(path)))
    periods = p === nothing ? find_experiment(load_registry(), basename(path)).steps : parse(Int, p.captures[1])
    files = sort!([(parse(Int, m.captures[1]), f) for f in readdir(folder)
                   for m in (match(r"^seed(\d+)\.csv$", f),) if m !== nothing])
    partial = [k for (k, f) in files if !seed_done(joinpath(folder, f), periods)]
    filter!(((k, _),) -> !(k in partial), files)
    isempty(files) && throw(ArgumentError("$folder holds no whole xl seed of $periods periods"))
    prices = map(files) do (_, f)
        header, M = read_seed_csv(joinpath(folder, f))
        j = findfirst(==("price_sd"), header)
        j === nothing && throw(ArgumentError("$(joinpath(folder, f)) lacks the price_sd column"))
        return end_mean(M, j)
    end
    return (; folder="$(basename(dirname(path)))/$(basename(path))", prices, partial)
end

# The line up front for an xl reference with seeds that aren't whole.
function xl_lines(xl)
    (xl === nothing || isempty(xl.partial)) && return String[]
    return ["**The xl reference $(xl.folder) has seeds that aren't whole, left out of X6: " *
            "$(join(xl.partial, ", ")).**", ""]
end

# ---- a seed's readings

seed_id(s::TradeSeed) = s.list.series.seed
is_extinct(s::TradeSeed) = extinct_at(s.list.series) !== nothing

"""The seeds of `r` that never went extinct: the only ones a ratio or a reading over seeds reads."""
live_seeds(r::TradeRun) = [s for s in r.seeds if !is_extinct(s)]

"""Column `name` of a seed's CSV, indexed `[t + 1]`."""
seed_column(s::TradeSeed, name::AbstractString) = @view s.rows[:, findfirst(==(name), s.header)]

"""The mean of a seed's CSV column `name` over periods `lo` to `hi`, skipping NaN."""
seed_mean(s::TradeSeed, name, lo, hi) = nanmean(seed_column(s, name)[(lo + 1):(hi + 1)])

"""The seed's mean of `mean_price` over periods `lo` to `hi`, skipping NaN: p̄, the price its resources are valued at."""
window_price(s::TradeSeed, lo, hi) = nanmean(@view s.list.price[(lo + 1):(hi + 1)])

"""The sum of trade-readings column `name` over periods `lo` to `hi`, skipping NaN."""
trade_sum(s::TradeSeed, name, lo, hi) = sum((x for x in @view(s.trade[name][lo:hi]) if !isnan(x)); init=0.0)

"""The sum of trade-readings column `name` over periods `lo` to `hi` per head (the population summed over them)."""
function per_head(s::TradeSeed, name, lo, hi)
    heads = sum(@view s.list.series.population[(lo + 1):(hi + 1)])
    return heads == 0 ? NaN : trade_sum(s, name, lo, hi) / heads
end

"""
Sick agents' trades per head over periods `lo` to `hi`: `exchanges_hs + 2 exchanges_ss` over `sick`, each summed over them;
NaN if no agent was sick. It reads slightly high: an exchange counts a sick agent who died later in its period, while
`sick` counts only the living.
"""
function sick_trades_per_head(s::TradeSeed, lo, hi)
    sick = trade_sum(s, "sick", lo, hi)
    return sick == 0 ? NaN : (trade_sum(s, "exchanges_hs", lo, hi) + 2trade_sum(s, "exchanges_ss", lo, hi)) / sick
end

"""
The share of healthy agents' exchanges over periods `lo` to `hi` that had a sick partner, `hs ÷ (hs + 2 hh)` summed over
them, from the exchanges (`exchanges_hs`, `exchanges_hh`, a recovering agent counted as healthy), or with `pairs=true`
the share random pairing of neighbours would give (`pairs_hs`, `pairs_hh`). With `strict=true` the same of the strictly
healthy, with a partner who isn't (recovering or sick): `HX ÷ (HX + 2 HH)`, from `exchanges_HX`, `exchanges_HH` (or
`pairs_HX`, `pairs_HH`). NaN if there are none.
"""
function sick_partner_share(s::TradeSeed, lo, hi; pairs::Bool=false, strict::Bool=false)
    one, both = strict ? ("HX", "HH") : ("hs", "hh")
    hs = trade_sum(s, (pairs ? "pairs_" : "exchanges_") * one, lo, hi)
    hh = trade_sum(s, (pairs ? "pairs_" : "exchanges_") * both, lo, hi)
    return hs + 2hh == 0 ? NaN : hs / (hs + 2hh)
end

"""The shares of the exchanges (or with `pairs=true` the neighbour pairs) over `lo` to `hi` that are hh, hs and ss."""
function pair_shares(s::TradeSeed, lo, hi; pairs::Bool=false)
    v = [trade_sum(s, (pairs ? "pairs_" : "exchanges_") * k, lo, hi) for k in ("hh", "hs", "ss")]
    total = sum(v)
    return total == 0 ? fill(NaN, 3) : v ./ total
end

"""
A seed's share of agents with no active disease (recovering included) who had an exchange with a partner with none in
the last 10 periods, `healthy_healthy_10`, the mean over `HEALTHY_TRADE_T`: a reading. With `strict=true` the same of
`healthy_healthy_10_strict`, the strictly healthy with a strictly healthy partner: what Part 1's "common" reads.
"""
function healthy_trade(s::TradeSeed; strict::Bool=false)
    share = s.trade[strict ? "healthy_healthy_10_strict" : "healthy_healthy_10"]
    return nanmean(@view share[HEALTHY_TRADE_T[1]:HEALTHY_TRADE_T[2]])
end

"""
A seed's median |log MRS gap| (`gap_strict`, `gap_healthy` or `gap_sick`), the mean over the tenth periods in `lo` to
`hi`.
"""
mrs_gap(s::TradeSeed, name, lo, hi) = nanmean(@view s.trade[name][lo:hi])

"""
The recovering agents over periods `lo` to `hi`, a group of their own: their share of the agents, and the exchanges with
a recovering agent in them per recovering agent, each summed over the periods; NaN where there are none.
"""
function recovering_readings(s::TradeSeed, lo, hi)
    recovering = trade_sum(s, "recovering", lo, hi)
    agents = recovering + trade_sum(s, "healthy", lo, hi) + trade_sum(s, "sick", lo, hi)
    return [agents == 0 ? NaN : recovering / agents,
            recovering == 0 ? NaN : trade_sum(s, "exchanges_recovering", lo, hi) / recovering]
end

# ---- traders against similar non-traders

"""
What an agent's holdings are worth: `:priced` is `sugar + spice / price` (the spec's resources), `:raw` `sugar + spice`,
`:welfare` the book's Cobb-Douglas welfare without cultural preferences, `sugar^(m1 / (m1 + m2)) spice^(m2 / (m1 + m2))`
for its sugar and spice metabolisms `m1` and `m2`, a holding below 0 counting as 0.
"""
function holding_value(sugar, spice, m1, m2, value::Symbol, price)
    value === :priced && return sugar + spice / price
    value === :raw && return sugar + spice
    value === :welfare && return max(sugar, 0.0)^(m1 / (m1 + m2)) * max(spice, 0.0)^(m2 / (m1 + m2))
    throw(ArgumentError("value is :priced, :raw or :welfare, not $(repr(value))"))
end

"""
    matched_ratio(rows, mean_price; value=:priced) -> (; ratio, kept, dropped)

Traders against similar non-traders in one seed's snapshot (`rows` in the order of [`TRADE_AGENT_COLUMNS`](@ref)), the
agents alive and with no active disease throughout the window (or the strictly healthy of them, [`strict_rows`](@ref)).
Resources are [`holding_value`](@ref)'s `value`, at `mean_price` (p̄, the seed's mean price over the window). The
agents fall into cells of the same metabolism, spice metabolism, vision,
age band (`age_start ÷ AGE_BAND`) and quintile of start resources, the quintile's edges the 20%, 40%, 60% and 80% points
of the seed's start resources (an agent on an edge falls below it, so that equal agents share one). In each cell of at
least [`CELL_MIN`](@ref) agents, ordered by `exchanges` and then id, the last third (rounded down) are traders and the
first third non-traders. `ratio` is Σ n_c · traders' mean end resources ÷ Σ n_c · non-traders', over the cells kept, NaN
if none is; `kept` and `dropped` count the agents in the cells kept and in those too small. Cells are summed in order of
their key, so the rows' order doesn't change the figure.
"""
function matched_ratio(rows::AbstractMatrix{<:Real}, mean_price::Real; value::Symbol=:priced)
    n = size(rows, 1)
    n == 0 && return (; ratio=NaN, kept=0, dropped=0)
    value === :priced && !(isfinite(mean_price) && mean_price > 0) && return (; ratio=NaN, kept=0, dropped=n)
    id, m1, m2, vision, age = (view(rows, :, j) for j in 1:5)
    start = [holding_value(rows[i, 6], rows[i, 7], m1[i], m2[i], value, mean_price) for i in 1:n]
    final = [holding_value(rows[i, 8], rows[i, 9], m1[i], m2[i], value, mean_price) for i in 1:n]
    exchanges = view(rows, :, 10)
    sorted = sort(start)
    edges = [quantile_of(sorted, q) for q in (0.2, 0.4, 0.6, 0.8)]
    cells = Dict{Tuple{Float64,Float64,Float64,Int,Int},Vector{Int}}()
    for i in 1:n
        key = (m1[i], m2[i], vision[i], floor(Int, age[i] / AGE_BAND), 1 + count(<(start[i]), edges))
        push!(get!(cells, key, Int[]), i)
    end
    traders = non_traders = 0.0
    kept = dropped = 0
    for key in sort!(collect(keys(cells)))
        members = cells[key]
        c = length(members)
        if c < CELL_MIN
            dropped += c
            continue
        end
        sort!(members; by=i -> (exchanges[i], id[i]))
        third = c ÷ 3
        non_traders += c * mean_of(final[members[1:third]])
        traders += c * mean_of(final[members[(c - third + 1):c]])
        kept += c
    end
    return (; ratio=kept == 0 ? NaN : traders / non_traders, kept, dropped)
end

"""
    bootstrap_mean(v; reps=BOOT_REPS, seed=BOOT_SEED) -> (; mean, lo, hi)

The mean of `v` with the 2.5% and 97.5% percentiles of the mean over `reps` resamples of `v` with replacement, drawn
from a `Xoshiro(seed)` of their own. NaN throughout for an empty `v`.
"""
function bootstrap_mean(v::Vector{Float64}; reps::Int=BOOT_REPS, seed::Int=BOOT_SEED)
    isempty(v) && return (; mean=NaN, lo=NaN, hi=NaN)
    rng = Xoshiro(seed)
    n = length(v)
    draws = Vector{Float64}(undef, reps)
    for r in 1:reps
        a = 0.0
        for _ in 1:n
            a += v[rand(rng, 1:n)]
        end
        draws[r] = a / n
    end
    lo, hi = percentile_interval(draws)
    return (; mean=mean_of(v), lo, hi)
end

"""
The rows of a snapshot (in the order of [`TRADE_AGENT_COLUMNS`](@ref)) of its strictly healthy agents: recovering
neither at the end of the period before the window (`recovering_start`) nor at the end of any period in it
(`recovering_in_window`). The bar's matched ratio is over these, by the user's decision after Part 1.
"""
function strict_rows(rows::AbstractMatrix{<:Real})
    j1, j2 = (findfirst(==(c), TRADE_AGENT_COLUMNS) for c in ("recovering_start", "recovering_in_window"))
    return rows[(view(rows, :, j1) .== 0) .& (view(rows, :, j2) .== 0), :]
end

"""
    matched_over_seeds(run; value=:priced, strict=false) -> (; ratio, lo, hi, per_seed, kept, dropped, left_out)

[`matched_ratio`](@ref) of each seed of `run` at its own p̄ over the snapshot's window, then the mean over seeds with a
bootstrap of that mean ([`bootstrap_mean`](@ref)). A seed that went extinct, or that has no cell kept, is left out, and
`left_out` says why for each. `kept` and `dropped` are summed over the seeds read. The snapshot is every agent with no
active disease throughout, recovering included, the spec's wider reading; with `strict=true` only its strictly healthy
([`strict_rows`](@ref)), as the bar reads it.
"""
function matched_over_seeds(r::TradeRun; value::Symbol=:priced, strict::Bool=false)
    ratios, left = Float64[], String[]
    kept = dropped = 0
    for s in r.seeds
        e = extinct_at(s.list.series)
        if e !== nothing
            push!(left, "seed $(seed_id(s)) went extinct at t = $e")
            continue
        end
        m = matched_ratio(strict ? strict_rows(s.agents) : s.agents, window_price(s, r.window...); value)
        kept += m.kept
        dropped += m.dropped
        isfinite(m.ratio) ? push!(ratios, m.ratio) :
            push!(left, "seed $(seed_id(s)) has " * (m.kept == 0 ? "no matched cell" : "no finite ratio"))
    end
    b = bootstrap_mean(ratios)
    return (; ratio=b.mean, b.lo, b.hi, per_seed=ratios, kept, dropped, left_out=left)
end

# ---- an arm's figures

"""
The Rule 13 settings of a folder, from its fingerprint's `xxl` line: `move` (`nothing`, "own" or "local"), `blend` (1
unless named) and `guard` (`nothing` unless named).
"""
function rule13_of(fingerprint::AbstractString)
    m = match(r"^xxl (?!map )[^\n]*"m, fingerprint)
    line = m === nothing ? "" : m.match
    move, blend, guard = (match(p, line) for p in (r"\btrade_move=\"(\w+)\"", r"\btrade_blend=([0-9.eE+-]+)",
                                                     r"\btrade_guard=(\d+)"))
    return (; move=move === nothing ? nothing : String(move.captures[1]),
            blend=blend === nothing ? 1.0 : parse(Float64, blend.captures[1]),
            guard=guard === nothing ? nothing : parse(Int, guard.captures[1]))
end

"""A rule's settings as text: `local, blend 0.5, guard 5`, or `the book's` without Rule 13."""
function rule13_text(rule)
    rule.move === nothing && return "the book's"
    return "$(rule.move), blend $(fmt(rule.blend)), guard $(rule.guard === nothing ? "none" : rule.guard)"
end

"""`run` with only the seeds that never went extinct, for [`list_readings`](@ref)."""
function live_list(r::TradeRun)
    l = r.run
    return ListRun(l.name, l.count, l.founder, l.lengths, l.planned, l.periods, [s.list for s in live_seeds(r)],
                   l.folder, l.fingerprint)
end

# The figures of `list_readings` that `arm_figures` takes, for an arm whose every seed went extinct.
const NO_READINGS = (; births_100=NaN, population=NaN, spread=NaN, gini=NaN, sugar=NaN, price=NaN,
                     per_seed=(; population=Float64[], gini=Float64[], sugar=Float64[]))

"""
    arm_figures(arm, xl) -> NamedTuple

Every figure the report reads of an arm, over its seeds that never went extinct unless said. Healthy is strictly healthy
(the user's, after Part 1), the spec's wider reading, recovering included, beside it as `_wide`. From VI-1 over
`READ_WINDOW`: the trades per head (all, by pair: hh, hs, ss, and strictly: HH, HX), the shares of exchanges and of
neighbour pairs by pair, the share of strictly healthy agents' exchanges with a partner who isn't and random pairing's
(`sick_share`, `random_sick_share`), sick agents' trades per head, the median MRS gaps (`gap_ratio` the strictly
healthy's ÷ the sick's) and the recovering agents ([`recovering_readings`](@ref)); the healthy trade over
`HEALTHY_TRADE_T`; the matched ratio over the strictly healthy three ways ([`matched_over_seeds`](@ref)), `matched` the
bar's, and at p̄ recovering included (`matched_wide`); the trough over t ≤ `SCREEN_END`, X9, X10 per seed and the seeds
extinct, over all seeds;
the population, its spread, Gini, mean sugar, mean spice, mean price and distance walked (`mean_moved`) over
`READ_WINDOW`; X6 against `xl` (NaN without it); trades per head with no disease over `READ_WINDOW`; and from IV-A3 its
trades per head and mean price over its snapshot's window and its end population over its last `END_PERIODS` periods,
the last over every seed, an extinct one counting what it has there (0 once it died out), as S5 reads it. `per_seed`
holds the seeds' figures for the ratios between arms.
"""
function arm_figures(a::TradeArm, xl)
    r = a.vi1
    lo, hi = READ_WINDOW
    ss = live_seeds(r)
    per(f, seeds=ss) = Float64[f(s) for s in seeds]
    reads = isempty(ss) ? NO_READINGS : list_readings(live_list(r); lo, hi)
    lows = Float64[screen_lowest(s.list) for s in r.seeds]
    j = isempty(ss) ? 0 : findfirst(==("price_sd"), ss[1].header)
    ends = isempty(ss) ? Float64[] : per(s -> end_mean(s.rows, j))
    x6 = xl === nothing || isempty(ends) ? NaN : mean_of(ends) / mean_of(xl.prices)
    nd = a.nodisease === nothing ? TradeSeed[] : live_seeds(a.nodisease)
    iv = a.iva3 === nothing ? TradeSeed[] : live_seeds(a.iva3)
    iw = a.iva3 === nothing ? (1, 1) : a.iva3.window
    iend = a.iva3 === nothing ? 0 : a.iva3.run.periods
    shares(f) = [nanmean(per(s -> f(s)[k])) for k in 1:3]
    per_seed = (;
        tph=per(s -> trades_per_head(s.list, lo, hi)),
        sick_tph=per(s -> sick_trades_per_head(s, lo, hi)),
        healthy_trade=per(s -> healthy_trade(s; strict=true)),
        sick_share=per(s -> sick_partner_share(s, lo, hi; strict=true)),
        nodisease_tph=per(s -> trades_per_head(s.list, lo, hi), nd),
        iva3_tph=per(s -> trades_per_head(s.list, iw...), iv),
        iva3_price=per(s -> window_price(s, iw...), iv),
        iva3_end=per(s -> window_population(s.list.series, iend - END_PERIODS + 1, iend),
                     a.iva3 === nothing ? TradeSeed[] : a.iva3.seeds),
        population=reads.per_seed.population,
        gini=reads.per_seed.gini,
        sugar=reads.per_seed.sugar,
        spice=per(s -> seed_mean(s, "mean_spice", lo, hi)),
        walked=per(s -> seed_mean(s, "mean_moved", lo, hi)),
        trough=Float64[screen_lowest(s.list) for s in ss],
    )
    gap(name) = nanmean(per(s -> mrs_gap(s, name, lo, hi)))
    gap_t, gap_h, gap_s = gap("gap_strict"), gap("gap_healthy"), gap("gap_sick")
    return (;
        name=a.name, n=length(r.seeds), live=length(ss), rule=rule13_of(r.run.fingerprint),
        finished=all(x -> x === nothing || finished(x.run), (r, a.nodisease, a.iva3)),
        matched=matched_over_seeds(r; strict=true), matched_raw=matched_over_seeds(r; value=:raw, strict=true),
        matched_welfare=matched_over_seeds(r; value=:welfare, strict=true), matched_wide=matched_over_seeds(r),
        tph=nanmean(per_seed.tph),
        tph_pairs=[nanmean(per(s -> per_head(s, "exchanges_$k", lo, hi))) for k in ("hh", "hs", "ss")],
        tph_strict=[nanmean(per(s -> per_head(s, "exchanges_$k", lo, hi))) for k in ("HH", "HX")],
        exchange_shares=shares(s -> pair_shares(s, lo, hi)), random_shares=shares(s -> pair_shares(s, lo, hi; pairs=true)),
        sick_share=nanmean(per_seed.sick_share),
        random_sick_share=nanmean(per(s -> sick_partner_share(s, lo, hi; pairs=true, strict=true))),
        sick_share_wide=nanmean(per(s -> sick_partner_share(s, lo, hi))),
        random_sick_share_wide=nanmean(per(s -> sick_partner_share(s, lo, hi; pairs=true))),
        recovering=[nanmean(per(s -> recovering_readings(s, lo, hi)[k])) for k in 1:2],
        healthy_trade=nanmean(per_seed.healthy_trade), sick_tph=nanmean(per_seed.sick_tph),
        healthy_trade_wide=nanmean(per(healthy_trade)),
        gap_strict=gap_t, gap_healthy=gap_h, gap_sick=gap_s, gap_ratio=gap_t / gap_s, gap_ratio_wide=gap_h / gap_s,
        nodisease_tph=nanmean(per_seed.nodisease_tph),
        nodisease_hh=nanmean(per(s -> per_head(s, "exchanges_hh", lo, hi), nd)),
        iva3_tph=nanmean(per_seed.iva3_tph), iva3_price=nanmean(per_seed.iva3_price), iva3_end=nanmean(per_seed.iva3_end),
        lows, trough=mean_of(lows), lowest=minimum(lows), trough_t=mean_of(Float64[screen_lowest_t(s.list) for s in r.seeds]),
        births_100=reads.births_100, population=reads.population, spread=reads.spread, gini=reads.gini,
        sugar=reads.sugar, spice=nanmean(per_seed.spice), price=reads.price, x6, walked=nanmean(per_seed.walked),
        x9=count(s -> s.list.circulating[X9_T + 1] > 0, r.seeds), x10=count(s -> in_band(screen_sick(s.list)), r.seeds),
        extinct=count(is_extinct, r.seeds),
        per_seed,
    )
end

# ---- the bars

"""
`x` (already settled) for a bar's row: four significant figures, and more while the rounded figure would meet `bar` (`at
least` it, else `at most`) when `x` does not, or miss it when `x` does; `—` if it is not finite.
"""
function edge_text(x::Real, bar::Real, pass::Bool; at_least::Bool=true)
    isfinite(x) || return "—"
    meets(y) = at_least ? y >= bar : y <= bar
    d = 4
    while d < SETTLE_DIGITS && meets(round(x; sigdigits=d)) != pass
        d += 1
    end
    y = round(x; sigdigits=d)
    return isinteger(y) && abs(y) < 1e15 ? string(Int(y)) : string(y)
end

"""`x` to two places, the zeros kept: `1.10`."""
function two_places(x::Real)
    s = string(round(x; digits=2))
    whole, frac = occursin('.', s) ? split(s, '.') : (s, "")
    return "$whole.$(rpad(frac, 2, '0'))"
end

"""`x` as a whole percentage: `25%`."""
percent(x::Real) = "$(round(Int, 100x))%"

# A row of the reading table for a figure `x` that must be at least `bar`: near if it is at least `1 - NEAR_BY` of it.
function at_least_row(name, x, bar, bar_text)
    x, bar = settle(x), settle(bar)
    pass = x >= bar
    return ScreenRow(name, edge_text(x, bar, pass), bar_text, pass, !pass && x >= settle((1 - NEAR_BY) * bar))
end

# A row for seeds counted against `need` of `n`: near if one seed short.
count_row(name, k, n, need, what) = ScreenRow(name, "$k of $n", "at least $need of $n$what", k >= need, k == need - 1)

const RICHER_ROW = "Richer with trade"

"""Whether an arm's matched ratio (the bar's, over the strictly healthy) is missing: no seed has a matched cell."""
ratio_missing(f) = !isfinite(settle(f.matched.ratio))

"""
A reading-table row's result for an arm `f`: pass, near or fail, and missing for the Richer row when the matched ratio
is ([`ratio_missing`](@ref)). A missing ratio decides nothing: the arm can't pass, but it hasn't failed the bar either.
"""
function row_result(f, row::ScreenRow)
    row.name == RICHER_ROW && ratio_missing(f) && return "missing"
    return row.pass ? "pass" : row.near ? "near" : "fail"
end

"""
    screen_trade(arm, base) -> Vector{ScreenRow}

The reading table of an arm's figures (see [`arm_figures`](@ref)) against the baseline's, in the spec's order. Every
figure is settled ([`SETTLE_DIGITS`](@ref)) before it meets its bar. Near is a failing row that misses by no more than
`NEAR_BY` of its bar, or by one seed:

- Richer with trade: the matched ratio over the strictly healthy at least `RICHER_BAR` and its interval's low end above
  1. Near if the ratio is at least `1 - NEAR_BY` of the bar and the low end above `1 - NEAR_BY`. The ratio recovering
  included is printed beside it and decides nothing. With no seed's matched cell the ratio is missing: the row neither
  passes nor is near, and [`row_result`](@ref) reads it as missing, not as a fail.
- Without disease: trades per head with no disease at least `NO_DISEASE_FACTOR` times the baseline's.
- Sick agents still trade: sick agents' trades per head at least `SICK_TRADE_FACTOR` times the baseline's.
- Trough: over all seeds, the mean at least `TROUGH_MEAN_SHARE` of the baseline's and no seed below `TROUGH_LOW_SHARE`
  of the baseline's lowest. Near only when one of the two misses: the mean at least `1 - NEAR_BY` of its bar with no seed
  below, or exactly one seed below with the mean meeting its bar. Missing both ways is a fail.
- Disease: X9 and X10 per seed, each at least `ceil(LIST_SHARE n)` of the `n` seeds, two rows.
- Prices: X6 at most `X6_BAR`. Near if at most `1 + NEAR_BY` of it.
- Extinction: no seed extinct. Near with one extinct, missing the row by one seed, as the spec defines near; two or
  more fail. Near only buys the one further screening round: confirmation still needs 0 of 60 (the user's bar).

The healthy-trade bar is dropped (the user's, after Part 1): its share is a reading.
"""
function screen_trade(f, base)
    n, need = f.n, seeds_needed(f.n)
    m = f.matched
    ratio, lo = settle(m.ratio), settle(m.lo)
    richer = ratio >= RICHER_BAR && lo > 1
    richer_near = !richer && ratio >= settle((1 - NEAR_BY) * RICHER_BAR) && lo > 1 - NEAR_BY
    richer_value = ratio_missing(f) ? "—, no seed has a matched cell" :
                   "$(edge_text(ratio, RICHER_BAR, ratio >= RICHER_BAR)), interval $(interval_text(m.lo, m.hi))"
    nd_bar, sick_bar = NO_DISEASE_FACTOR * base.nodisease_tph, SICK_TRADE_FACTOR * base.sick_tph
    mean_bar, low_bar = settle(TROUGH_MEAN_SHARE * base.trough), settle(TROUGH_LOW_SHARE * base.lowest)
    trough = settle(f.trough)
    below = count(<(low_bar), f.lows)
    mean_ok = trough >= mean_bar
    trough_pass = mean_ok && below == 0
    trough_near = (!mean_ok && trough >= settle((1 - NEAR_BY) * mean_bar) && below == 0) || (mean_ok && below == 1)
    x6 = settle(f.x6)
    x6_pass = x6 <= X6_BAR
    return [
        ScreenRow(RICHER_ROW, "$richer_value (recovering included: $(finite_text(f.matched_wide.ratio)), a reading)",
                  "at least $(two_places(RICHER_BAR)), its 95% interval above 1", richer, richer_near),
        at_least_row("Without disease", f.nodisease_tph, nd_bar,
                     "at least ×$(fmt(NO_DISEASE_FACTOR)) today's $(finite_text(base.nodisease_tph)) = $(finite_text(nd_bar))"),
        at_least_row("Sick agents still trade", f.sick_tph, sick_bar,
                     "at least ×$(fmt(SICK_TRADE_FACTOR)) today's $(finite_text(base.sick_tph)) = $(finite_text(sick_bar))"),
        ScreenRow("Trough", "mean $(edge_text(trough, mean_bar, mean_ok)), lowest $(whole_cell(f.lowest))",
                  "mean at least $(percent(TROUGH_MEAN_SHARE)) of today's $(places(base.trough, TROUGH_DIGITS)) = " *
                  "$(fmt(mean_bar)), none below $(percent(TROUGH_LOW_SHARE)) of today's lowest " *
                  "$(whole_cell(base.lowest)) = $(fmt(low_bar))", trough_pass, trough_near),
        count_row("Disease: X9", f.x9, n, need, ", a disease circulating at t = $X9_T"),
        count_row("Disease: X10 per seed", f.x10, n, need,
                  " inside $(SICK_BAND[1])–$(SICK_BAND[2]), $(period_text(SCREEN_SICK...))"),
        ScreenRow("Prices: X6", edge_text(x6, X6_BAR, x6_pass; at_least=false), "at most $(fmt(X6_BAR))", x6_pass,
                  !x6_pass && x6 <= settle((1 + NEAR_BY) * X6_BAR)),
        ScreenRow("Extinction", "$(f.extinct) of $n", "none", f.extinct == 0, f.extinct == 1),
    ]
end

"""Whether an arm passes screening: every row passes and every planned seed of its three folders finished."""
trade_passes(f, rows) = f.finished && all(r -> r.pass, rows)

"""Whether an arm is near: every planned seed finished, exactly one row fails, and that row is near."""
function trade_near(f, rows)
    failing = [r for r in rows if !r.pass]
    return f.finished && length(failing) == 1 && failing[1].near
end

"""
    choose_trade_arm(figures, base) -> Union{Nothing,Int}

The place in `figures` of the arm to take to confirmation, or `nothing` if none passes. Among those that pass, in the
spec's order: the largest matched ratio (the bar's, over the strictly healthy), then the smallest rise in Gini over the
baseline's, then the higher trough (mean), then the simpler rule (no blend over a blend, then own price over local).
"""
function choose_trade_arm(figures, base)
    passing = [i for i in eachindex(figures) if trade_passes(figures[i], screen_trade(figures[i], base))]
    isempty(passing) && return nothing
    order(f) = (-settle(f.matched.ratio), settle(f.gini - base.gini), -settle(f.trough), f.rule.blend == 1 ? 0 : 1,
                f.rule.move == "own" ? 0 : 1)
    return passing[argmin([order(figures[i]) for i in passing])]
end

# ---- Part 1

"""The rows of the spec's "What Part 1 decides", in its order: (result, reading)."""
const PART1_ROWS = [
    ("Healthy agents are richer with trade today by the bar, and healthy–healthy trade is common",
     "The premise is wrong. Stop and report; what next is the user's call"),
    ("Healthy agents are richer with trade today, but mostly by trading with sick partners",
     "Go on to Part 2. Riches from selling to the sick are still trade that follows sickness, which is what the user " *
     "objected to, and the no-disease bar tests it"),
    ("Healthy trade is mostly with sick partners, and healthy MRS gaps are small", "The diagnosis holds. Go on to Part 2"),
    ("Healthy trade is mostly with sick partners, but healthy MRS gaps aren't small",
     "Go on to Part 2, and say the diagnosis was only half right: something besides movement keeps healthy neighbours " *
     "from trading"),
    ("Healthy agents trade with each other, but it doesn't pay", "Go on to Part 2, and say the diagnosis was only half right"),
]

"""
    part1_decision(; ratio, lo, healthy_trade, sick_share, gap_ratio) -> (; words, row, decided)

The words of Part 1's table applied by the bars, each figure settled first, healthy read as strictly healthy (the
user's, after Part 1): **richer** when the matched `ratio` is at least `RICHER_BAR` and its interval's low end `lo`
above 1; healthy–healthy trade **common** when `healthy_trade` (`healthy_healthy_10_strict`) is at least `COMMON_SHARE`;
**mostly with sick partners** when `sick_share` (with a partner not strictly healthy) is more than `MOSTLY_SICK`; MRS
gaps **small** when `gap_ratio` (strictly healthy ÷ sick) is at most `SMALL_GAP`. `row` is the first of
[`PART1_ROWS`](@ref) that holds, in the table's order (a trade mostly with healthy partners is "trade with each
other"), or `nothing` when none does: richer, not common, and not mostly with sick partners. A missing `ratio` (no seed
with a matched cell) decides nothing: `decided` is false and `row` is `nothing`.
"""
function part1_decision(; ratio, lo, healthy_trade, sick_share, gap_ratio)
    decided = isfinite(settle(ratio))
    words = (; richer=settle(ratio) >= RICHER_BAR && settle(lo) > 1, common=settle(healthy_trade) >= COMMON_SHARE,
             mostly_sick=settle(sick_share) > MOSTLY_SICK, small=settle(gap_ratio) <= SMALL_GAP)
    row = !decided ? nothing :
          words.richer && words.common ? 1 :
          words.richer && words.mostly_sick ? 2 :
          words.mostly_sick && words.small ? 3 :
          words.mostly_sick ? 4 :
          !words.richer ? 5 : nothing
    return (; words, row, decided)
end

# ---- the report

const EXTINCT_EFFECT = "it is left out of every ratio and reading over seeds, and counted only in the trough, X9, X10 " *
                       "and extinction"
# What an extinct seed of the other two worlds does: neither is read for the trough, X9, X10 or extinction.
const EXTINCT_NODISEASE = "it is left out of the trades per head with no disease"
const EXTINCT_IVA3 = "it is left out of IV-A3's trades per head and mean price, and counts in its end population with " *
                     "what it has there, 0 once it died out, as S5 reads it"

# A run's lines up front: its seeds unfinished (`effect` says what that does) and its extinct seeds (`extinct` says
# what is done with each).
function seed_lines(r::TradeRun, who::AbstractString, effect::AbstractString; extinct::AbstractString=EXTINCT_EFFECT)
    lines = String[]
    finished(r.run) || push!(lines, "**Unfinished: $(r.run.planned - length(r.seeds)) of $(r.run.planned) seeds of " *
                                    "$who have not run. $effect**", "")
    for s in r.seeds
        e = extinct_at(s.list.series)
        e === nothing && continue
        push!(lines, "**Seed $(seed_id(s)) of $who went extinct at t = $e: $extinct.**", "")
    end
    return lines
end

# What a missing matched ratio does, said up front: in Part 1 and in screening.
const MISSING_PART1 = "**The matched ratio is missing: no seed has a matched cell, so Part 1's decision can't be made " *
                      "and no row of its table fires.**"
missing_screen(name) = "**The matched ratio of $name is missing: no seed has a matched cell, so its Richer with trade " *
                       "row reads missing and it can't pass.**"

# The lines up front for an arm (`f` its figures): `missing_line` when the matched ratio (the bar's, over the strictly
# healthy) is missing, else each VI-1 seed it leaves out for want of a cell; its three folders' seeds; and a no-disease
# folder with disease.
function arm_lines(a::TradeArm, f, effect; missing_line::AbstractString=missing_screen(a.name))
    lines = String[]
    ratio_missing(f) && push!(lines, missing_line, "")
    for (r, world, extinct) in ((a.vi1, "VI-1", EXTINCT_EFFECT), (a.nodisease, "no disease", EXTINCT_NODISEASE),
                                (a.iva3, "IV-A3", EXTINCT_IVA3))
        r === nothing || append!(lines, seed_lines(r, "$(a.name), $world", effect; extinct))
    end
    for why in f.matched.left_out
        occursin("went extinct", why) || ratio_missing(f) ||
            push!(lines, "**The matched ratio of $(a.name) leaves out $why (cells of at least $CELL_MIN strictly " *
                         "healthy agents).**", "")
    end
    a.nodisease === nothing || a.nodisease.run.founder == 0 ||
        push!(lines, "**The no-disease folder of $(a.name), $(a.nodisease.run.folder), has founder diseases " *
                     "$(a.nodisease.run.founder), not 0.**", "")
    return lines
end

# The lines up front for the trade-off run: its seeds unfinished or extinct, which trade on ÷ off leaves out, and a
# folder that has trade on.
function off_lines(off::TradeRun)
    lines = seed_lines(off, "the trade-off run ($(off.run.folder))", "Trade on ÷ off reads only those finished.";
                       extinct="it is left out of trade on ÷ off")
    off.trade_off ||
        push!(lines, "**The trade-off folder $(off.run.folder) has trade on: its fingerprint has no `trade: off` line.**", "")
    return lines
end

"""The matched ratio's text, for a snapshot over `window` (a folder's, from its fingerprint)."""
function match_text(window)
    return "Traders against similar non-traders: the agents alive throughout the snapshot's window, " *
           "$(period_text(window...)), and strictly healthy in it (no active disease at the end of any period of it " *
           "or of the 11 before it: recovering neither at its start nor in it), in cells of the same metabolism, spice " *
           "metabolism, vision, age band ($AGE_BAND periods) and quintile of resources at its start; in each cell of " *
           "at least $CELL_MIN, the third with most exchanges (ties by id) against the third with fewest, their mean " *
           "resources at its end, pooled over cells by cell size. Resources are sugar + spice ÷ p̄, p̄ the seed's mean " *
           "price over the window. The mean over seeds has a 2.5% to 97.5% interval of $BOOT_REPS resamples of the " *
           "seeds (random seed $BOOT_SEED). The bar reads this, by the user's decision after Part 1. The reading " *
           "beside it, recovering included, is the same over every agent alive and with no active disease throughout " *
           "the window, the spec's wider reading, and decides nothing."
end

const HEALTH_TEXT = "Sick agents' trades per head is (exchanges_hs + 2·exchanges_ss) ÷ sick, each summed over " *
    "$(period_text(READ_WINDOW...)). It reads slightly high: it counts the exchanges of sick agents who died later in the " *
    "same period, while sick counts only the living. Here healthy means strictly healthy (no disease for 10 periods) " *
    "in every bar and Part 1 word, by the user's decision after Part 1: HH and HX are exchanges (or neighbour pairs) " *
    "with both agents strictly healthy and with exactly one, the other recovering or sick. The spec's wider reading, " *
    "which counts a recovering agent (no disease now, one in the last 10 periods) as healthy, is shown beside each and " *
    "decides nothing: hh, hs and ss are healthy–healthy, healthy–sick and sick–sick read that way. Recovering agents " *
    "are read as a group of their own too."

matched_cell(m) = isfinite(m.ratio) ? "$(fmt(m.ratio)) $(interval_text(m.lo, m.hi))" : "—"
slashed(v) = join((places(x, 3) for x in v), " / ")

# The readings table: a row per reading, a column per arm (the baseline first).
function readings_lines(figs)
    rows = [
        ("Traders ÷ similar non-traders, resources at p̄", f -> matched_cell(f.matched)),
        ("Traders ÷ similar non-traders, raw sugar + spice", f -> matched_cell(f.matched_raw)),
        ("Traders ÷ similar non-traders, welfare", f -> matched_cell(f.matched_welfare)),
        ("Agents matched: kept, dropped", f -> "$(f.matched.kept), $(f.matched.dropped)"),
        ("Traders ÷ similar non-traders, recovering included, resources at p̄", f -> matched_cell(f.matched_wide)),
        ("The same: agents matched, kept, dropped", f -> "$(f.matched_wide.kept), $(f.matched_wide.dropped)"),
        ("Trades per head", f -> places(f.tph, 3)),
        ("Trades per head: HH / HX", f -> slashed(f.tph_strict)),
        ("Trades per head: hh / hs / ss", f -> slashed(f.tph_pairs)),
        ("Share of exchanges: hh / hs / ss", f -> slashed(f.exchange_shares)),
        ("Share of neighbour pairs (random pairing): hh / hs / ss", f -> slashed(f.random_shares)),
        ("Strictly healthy agents' exchanges with a partner not strictly healthy", f -> places(f.sick_share, 3)),
        ("The same by random pairing", f -> places(f.random_sick_share, 3)),
        ("The same, recovering included: healthy agents' exchanges with a sick partner", f -> places(f.sick_share_wide, 3)),
        ("The same by random pairing, recovering included", f -> places(f.random_sick_share_wide, 3)),
        ("Strictly healthy agents with a strictly healthy partner in 10 periods, $(period_text(HEALTHY_TRADE_T...))",
         f -> places(f.healthy_trade, 3)),
        ("The same, agents with no disease with a partner with none (recovering included)",
         f -> places(f.healthy_trade_wide, 3)),
        ("Sick agents' trades per head", f -> places(f.sick_tph, 3)),
        ("Recovering agents: share of agents / exchanges with one per recovering agent", f -> slashed(f.recovering)),
        ("Median MRS gap: strictly healthy / sick / ratio", f -> slashed([f.gap_strict, f.gap_sick, f.gap_ratio])),
        ("Median MRS gap, recovering included: healthy / sick / ratio",
         f -> slashed([f.gap_healthy, f.gap_sick, f.gap_ratio_wide])),
        ("Trades per head, no disease: all / hh", f -> slashed([f.nodisease_tph, f.nodisease_hh])),
        ("IV-A3: trades per head / mean price", f -> slashed([f.iva3_tph, f.iva3_price])),
        ("IV-A3: end population (S5's reading)", f -> whole_cell(f.iva3_end)),
        ("Trough, mean / lowest / at t", f -> "$(places(f.trough, TROUGH_DIGITS)) / $(whole_cell(f.lowest)) / " *
                                             places(f.trough_t, 1)),
        ("Births to t = 100", f -> whole_cell(f.births_100)),
        ("Population / spread", f -> "$(whole_cell(f.population)) / $(places(f.spread, 3))"),
        ("Gini", f -> places(f.gini, 3)),
        ("Mean sugar / mean spice", f -> "$(places(f.sugar, 2)) / $(places(f.spice, 2))"),
        ("Mean price / X6", f -> slashed([f.price, f.x6])),
        ("Distance walked per agent per period", f -> places(f.walked, 3)),
        ("X9 / X10 per seed / extinct", f -> "$(f.x9) / $(f.x10) / $(f.extinct) of $(f.n)"),
    ]
    lines = [row_text(["Reading"; [f.name for f in figs]]), "|" * "---|"^(length(figs) + 1)]
    for (name, cell) in rows
        push!(lines, row_text([name; [cell(f) for f in figs]]))
    end
    return lines
end

"""The readings table's text, for the arm `a` the table's windows are read from (its IV-A3 snapshot's, from its fingerprint)."""
function readings_text(a::TradeArm)
    iva3 = a.iva3 === nothing ? "" : " IV-A3 is read over $(period_text(a.iva3.window...)) (its snapshot's window), " *
                                     "its end population over its last $END_PERIODS periods as S5 reads it."
    return "Over the seeds that never went extinct, from VI-1 over $(period_text(READ_WINDOW...)) unless the row says " *
           "otherwise; the trough, X9, X10 and extinction over every seed, the trough over t ≤ $SCREEN_END. The " *
           "no-disease world is read over the same periods.$iva3 X6 is the mean over seeds of the end price sd (the " *
           "last $END_PERIODS periods) ÷ the same for xl. "
end

const RATIO_MEASURES_TRADE = (("Trades per head", :tph), ("Sick agents' trades per head", :sick_tph),
                              ("Healthy trade, strictly healthy", :healthy_trade),
                              ("Trades per head, no disease", :nodisease_tph),
                              ("IV-A3 trades per head", :iva3_tph), ("IV-A3 end population (S5's reading)", :iva3_end),
                              ("Trough", :trough), ("Population", :population), ("Gini", :gini),
                              ("Mean sugar", :sugar), ("Mean spice", :spice), ("Distance walked", :walked))

# Each arm's mean ÷ the baseline's, per measure, each side resampled alone.
function trade_ratio_lines(figs, base)
    lines = [row_text(["Arm", "Reading", "Ratio", "95% interval", "Against 1"]), "|" * "---|"^5]
    for f in figs, (name, key) in RATIO_MEASURES_TRADE
        b = bootstrap_ratio_apart(filter(!isnan, getproperty(f.per_seed, key)),
                                  filter(!isnan, getproperty(base.per_seed, key)))
        push!(lines, row_text([f.name, name, finite_text(b.ratio), interval_text(b.lo, b.hi),
                               state_text(interval_state(b.lo, b.hi, 1), b.lo, b.hi)]))
    end
    return lines
end

"""
    on_off(on, off) -> Vector{(name, (; ratio, lo, hi))}

The trade-off reading: `on`'s mean ÷ `off`'s, over the seeds that never went extinct, each side resampled alone
([`bootstrap_ratio_apart`](@ref)): healthy agents' mean resources at the window's end (the snapshot's agents), the
population over `READ_WINDOW`, and the total resources over it (population × (mean sugar + mean spice ÷ p̄)). With trade
off there is no price, so both sides are valued at `on`'s p̄, the mean over its seeds of their mean price over its window.
"""
function on_off(on::TradeRun, off::TradeRun)
    lo, hi = READ_WINDOW
    ons, offs = live_seeds(on), live_seeds(off)
    p = nanmean(Float64[window_price(s, on.window...) for s in ons])
    function healthy(s)
        a = s.agents
        return size(a, 1) == 0 ? NaN : mean_of([a[i, 8] + a[i, 9] / p for i in axes(a, 1)])
    end
    function total(s)
        pop, sugar, spice = s.list.series.population, s.list.sugar, seed_column(s, "mean_spice")
        return nanmean([pop[t + 1] * (sugar[t + 1] + spice[t + 1] / p) for t in lo:hi])
    end
    population(s) = window_population(s.list.series, lo, hi)
    figures(f, seeds) = filter(!isnan, Float64[f(s) for s in seeds])
    return [(name, bootstrap_ratio_apart(figures(f, ons), figures(f, offs)))
            for (name, f) in (("Healthy agents' mean resources at t = $(on.window[2])", healthy), ("Population", population),
                              ("Total resources", total))]
end

# The trade-off section: each run on ÷ the shared trade-off run.
function on_off_lines(runs::Vector{Pair{String,TradeRun}}, off::TradeRun)
    lines = [
        "Healthy agents' mean resources, population and total resources with trade on ÷ off ($(off.run.folder), " *
        "$(length(live_seeds(off))) seeds), resampling each side independently since seeds don't pair once trade " *
        "changes the draws. A reading, not a bar. With trade off there is no price, so both sides are valued at the " *
        "trade-on run's mean price.",
        "",
        row_text(["Run", "Reading", "On ÷ off", "95% interval", "Against 1"]), "|" * "---|"^5,
    ]
    for (name, on) in runs, (reading, b) in on_off(on, off)
        push!(lines, row_text([name, reading, finite_text(b.ratio), interval_text(b.lo, b.hi),
                               state_text(interval_state(b.lo, b.hi, 1), b.lo, b.hi)]))
    end
    return lines
end

# The matched ratio over the strictly healthy three ways, and recovering included, with the seeds the bar's leaves out;
# `window` is the snapshot's.
function matched_lines(name, f, window)
    lines = [match_text(window), "",
             row_text(["Run", "Resources", "Mean over seeds", "95% interval", "Seeds", "Kept", "Dropped"]), "|" * "---|"^7]
    for (what, m) in (("sugar + spice ÷ p̄ (the bar)", f.matched), ("raw sugar + spice", f.matched_raw),
                      ("welfare", f.matched_welfare), ("sugar + spice ÷ p̄, recovering included (a reading)", f.matched_wide))
        push!(lines, row_text([name, what, finite_text(m.ratio), interval_text(m.lo, m.hi), length(m.per_seed), m.kept,
                               m.dropped]))
    end
    left = f.matched.left_out
    push!(lines, "", isempty(left) ? "The bar's ratio leaves no seed out." : "The bar's ratio leaves out: $(join(left, "; ")).")
    return lines
end

# The rows of a reading table as lines, for one arm or several.
function table_lines(figs, base)
    lines = [row_text(["Arm", "Row", "Reading", "Bar", "Result"]), "|" * "---|"^5]
    for f in figs, row in screen_trade(f, base)
        push!(lines, row_text([f.name, row.name, row.value, row.bar, row_result(f, row)]))
    end
    return lines
end

"""
    check_trade_run(r, what; vi1=true)

`ArgumentError` unless `r` has a finished seed and, for a VI-1 folder, reaches t = `STUDY_END`.
"""
function check_trade_run(r::TradeRun, what::AbstractString; vi1::Bool=true)
    isempty(r.seeds) && throw(ArgumentError("$what ($(r.run.folder)) has no finished seed"))
    vi1 && r.run.periods < STUDY_END &&
        throw(ArgumentError("$what ($(r.run.folder)) stops at t = $(r.run.periods), short of t = $STUDY_END"))
    return nothing
end

function check_trade_arm(a::TradeArm)
    check_trade_run(a.vi1, "$(a.name), VI-1")
    a.nodisease === nothing || check_trade_run(a.nodisease, "$(a.name), no disease")
    a.iva3 === nothing || check_trade_run(a.iva3, "$(a.name), IV-A3"; vi1=false)
    return nothing
end

"""
    trade_report(; label, base, off, xl=nothing, arms=TradeArm[], part1=false, confirm=false) -> String

The trade study's report as markdown, in one of three modes:

- **Part 1** (`part1`): today's `base` arm (VI-1 on, no disease, IV-A3), the trade-off run `off` and the xl reference `xl`
  ([`read_xl_prices`](@ref)): the words of "What Part 1 decides" applied by the bars and the row that fires
  ([`part1_decision`](@ref)), whether today already meets the Richer bar (Part 1 may correct it), the readings, the
  matched ratio three ways and the trade-off reading.
- **Screening** (the default): the `arms` against the baseline `base`, with `off` and `xl`: the arms and their Rule 13,
  the reading table ([`screen_trade`](@ref)), the choice ([`choose_trade_arm`](@ref)) and the result row that fires, the
  readings with the baseline's first, the arms' ratios to the baseline's and the trade-off reading of every run.
- **Confirmation** (`confirm`): the study run `base.vi1` and the trade-off run `off`: the matched ratio against its bar,
  the result row and the trade-off reading.

Healthy, in every bar and Part 1's words, is strictly healthy, no disease for 10 periods (the user's, after Part 1).
The spec's wider readings, a recovering agent counted as healthy, are printed beside them and decide nothing. A
missing matched ratio (no seed with a matched cell) decides nothing either: Part 1 fires no row, screening's Richer row
reads missing and the arm can't pass, and confirmation neither passes nor fails it. Confirmation reads its ratio only
once every planned seed has run. The snapshot's windows are the folders' own, from their fingerprints.

Up front, in bold: a missing matched ratio, seeds unfinished (an arm with any cannot pass or be chosen), seeds extinct
(in VI-1 left out of every ratio and reading over seeds, counted in the trough, X9, X10 and extinction; in the other two
worlds as their lines say), seeds the matched ratio finds no cell in, a trade-off folder whose fingerprint has trade on,
xl seeds that aren't whole, and a rise in Gini beyond `GINI_NOTE`. `ArgumentError` for a folder with no finished seed, a
VI-1 folder that stops short of t = `STUDY_END`, or in screening an arm's folder that covers other seeds, periods or
snapshot window than the baseline's of the same world ([`check_same_seeds`](@ref)).
"""
function trade_report(;
    label::AbstractString, base::TradeArm, off::TradeRun, xl=nothing, arms::Vector{TradeArm}=TradeArm[],
    part1::Bool=false, confirm::Bool=false,
)
    part1 && confirm && throw(ArgumentError("a report is Part 1's or confirmation's, not both"))
    check_trade_arm(base)
    foreach(check_trade_arm, arms)
    check_trade_run(off, "the trade-off run")
    part1 && return part1_report(label, base, off, xl)
    confirm && return confirm_report(label, base, off)
    xl === nothing && throw(ArgumentError("screening needs the xl reference"))
    for a in [base; arms]
        (a.nodisease === nothing || a.iva3 === nothing) &&
            throw(ArgumentError("screening needs three folders of $(a.name): VI-1, no disease and IV-A3"))
    end
    check_same_seeds(base, arms)
    return screen_report(label, base, arms, off, xl)
end

"""The first seed, seed count and periods of a study folder, from its name: `…-s<first>-<seeds>-p<periods>`."""
function folder_seeds(r::TradeRun)
    m = match(r"-s(\d+)-(\d+)-p(\d+)$", r.run.folder)
    m === nothing && throw(ArgumentError("$(r.run.folder) doesn't name its seeds and periods (-s<first>-<seeds>-p<periods>)"))
    return Tuple(parse.(Int, m.captures))
end

"""
`ArgumentError` unless each arm's VI-1, no-disease and IV-A3 folders cover the same first seed, seed count and periods
as the baseline's of the same world ([`folder_seeds`](@ref)), and read the snapshot over the same window (from the
fingerprints): screening compares arms on the same seeds, and its text names the baseline's windows.
"""
function check_same_seeds(base::TradeArm, arms)
    for a in arms, (world, r, b) in (("VI-1", a.vi1, base.vi1), ("no-disease", a.nodisease, base.nodisease),
                                     ("IV-A3", a.iva3, base.iva3))
        s, t = folder_seeds(r), folder_seeds(b)
        s == t || throw(ArgumentError(
            "the $world folder of $(a.name), $(r.run.folder), covers seeds $(s[1]) to $(s[1] + s[2] - 1) over $(s[3]) " *
            "periods, not the baseline's $(t[1]) to $(t[1] + t[2] - 1) over $(t[3]) ($(b.run.folder))"))
        r.window == b.window || throw(ArgumentError(
            "the $world folder of $(a.name), $(r.run.folder), reads its snapshot over $(period_text(r.window...)), not " *
            "the baseline's $(period_text(b.window...)) ($(b.run.folder))"))
    end
    return nothing
end

function part1_report(label, base::TradeArm, off::TradeRun, xl)
    f = arm_figures(base, xl)
    d = part1_decision(; ratio=f.matched.ratio, lo=f.matched.lo, healthy_trade=f.healthy_trade,
                       sick_share=f.sick_share, gap_ratio=f.gap_ratio)
    yes(b) = b ? "yes" : "no"
    w = d.words
    lines = ["# Trade, Part 1: $label", ""]
    append!(lines, arm_lines(base, f, "Its readings cover only those finished."; missing_line=MISSING_PART1),
            off_lines(off), xl_lines(xl))
    push!(lines, "## Runs", "", row_text(["Run", "Folder", "Seeds", "Periods"]), "|---|---|---|---|")
    for (what, r) in (("Trade on", base.vi1), ("Trade off", off), ("No disease", base.nodisease), ("IV-A3", base.iva3))
        r === nothing || push!(lines, row_text([what, r.run.folder, "$(length(r.seeds)) of $(r.run.planned)", r.run.periods]))
    end
    xl === nothing || push!(lines, row_text(["xl", xl.folder, length(xl.prices), "—"]))
    push!(lines, "", "## What Part 1 decides", "",
          "The words of the table, set before Part 1 ran, applied by the bars. Healthy means strictly healthy (no " *
          "disease for 10 periods), by the user's decision after Part 1; the spec's wider reading, recovering " *
          "included, is beside each and decides nothing.", "",
          "- **Richer** with trade: traders ÷ similar non-traders, strictly healthy, $(matched_cell(f.matched)), " *
          "against at least $(two_places(RICHER_BAR)) with its interval above 1: " *
          "$(d.decided ? yes(w.richer) : "missing"). Recovering included, a reading: $(matched_cell(f.matched_wide))",
          "- Healthy–healthy trade **common**: $(places(f.healthy_trade, 3)) of strictly healthy agents traded with a " *
          "strictly healthy partner in the last 10 periods, $(period_text(HEALTHY_TRADE_T...)), against at least " *
          "$(percent(COMMON_SHARE)): $(yes(w.common)). Recovering included, a reading: " *
          "$(places(f.healthy_trade_wide, 3))",
          "- Healthy trade **mostly with sick partners**: $(places(f.sick_share, 3)) of strictly healthy agents' " *
          "exchanges have a partner who isn't (recovering or sick), $(period_text(READ_WINDOW...)), against more than " *
          "$(percent(MOSTLY_SICK)): $(yes(w.mostly_sick)). Recovering included, a reading: " *
          "$(places(f.sick_share_wide, 3))",
          "- Healthy MRS gaps **small**: the strictly healthy median |log MRS gap| ÷ the sick one is " *
          "$(places(f.gap_ratio, 3)), against at most $(fmt(SMALL_GAP)): $(yes(w.small)). Recovering included, a " *
          "reading: $(places(f.gap_ratio_wide, 3))", "")
    if !d.decided
        push!(lines, "No row of the table fires: the matched ratio is missing, so the decision can't be made. What " *
                     "next is the user's call.")
    elseif d.row === nothing
        push!(lines, "No row of the table fires: healthy agents are richer with trade, but healthy–healthy trade isn't " *
                     "common and healthy trade isn't mostly with sick partners. What next is the user's call.")
    else
        result, reading = PART1_ROWS[d.row]
        push!(lines, "The row that fires, the first in the table's order that holds: **$result.** $reading.")
    end
    push!(lines, "", "## Bars today already meets", "",
          !d.decided ? "Whether today meets the Richer with trade bar can't be said: the matched ratio is missing." :
          w.richer ? "Today already meets the Richer with trade bar. Part 1 may correct a bar met today: any change is " *
                     "recorded in the ledger and put to the user before screening." :
          "Today doesn't meet the Richer with trade bar.",
          "", "The healthy-trade bar is dropped (the user's decision after Part 1): its share is a reading.",
          "", "## Readings", "", readings_text(base) * HEALTH_TEXT, "")
    append!(lines, readings_lines([f]))
    push!(lines, "", "## Traders against similar non-traders", "")
    append!(lines, matched_lines(base.name, f, base.vi1.window))
    push!(lines, "", "## Trade on ÷ off", "")
    append!(lines, on_off_lines([base.name => base.vi1], off))
    return join(lines, "\n") * "\n"
end

function confirm_report(label, base::TradeArm, off::TradeRun)
    f = arm_figures(base, nothing)
    row = screen_trade(f, f)[1]  # Richer with trade reads nothing of the baseline
    lines = ["# Trade confirmation: $label", ""]
    append!(lines, seed_lines(base.vi1, "$(base.name), VI-1", "Its readings cover only those finished."), off_lines(off))
    push!(lines, "## Runs", "", row_text(["Run", "Folder", "Seeds", "Periods"]), "|---|---|---|---|",
          row_text(["Study run", base.vi1.run.folder, "$(length(base.vi1.seeds)) of $(base.vi1.run.planned)",
                    base.vi1.run.periods]),
          row_text(["Trade off", off.run.folder, "$(length(off.seeds)) of $(off.run.planned)", off.run.periods]),
          "", "## Richer with trade, confirmed", "",
          row_text(["Arm", "Row", "Reading", "Bar", "Result"]), "|" * "---|"^5,
          row_text([base.name, row.name, row.value, row.bar, row.pass ? "pass" : ratio_missing(f) ? "missing" : "fail"]),
          "",
          !finished(base.vi1.run) ? "The study run is unfinished, so the ratio is not read: run its remaining seeds." :
          ratio_missing(f) ? "The ratio is missing: no seed has a matched cell, so it can't be read, pass or fail." :
          row.pass ? "The ratio passes again on the new seeds." :
          "The ratio fails on the new seeds: report it as not confirmed.",
          "", "Healthy means strictly healthy (no disease for 10 periods), by the user's decision after Part 1.",
          "", "Extinction (0 of 60) and the scorecard (13 of 13 on both) are read from their own runs.", "",
          "## Traders against similar non-traders", "")
    append!(lines, matched_lines(base.name, f, base.vi1.window))
    push!(lines, "", "## Trade on ÷ off", "")
    append!(lines, on_off_lines([base.name => base.vi1], off))
    return join(lines, "\n") * "\n"
end

function screen_report(label, base::TradeArm, arms::Vector{TradeArm}, off::TradeRun, xl)
    bf = arm_figures(base, xl)
    figs = [arm_figures(a, xl) for a in arms]
    lines = ["# Trade screening: $label", ""]
    append!(lines, arm_lines(base, bf, "The bars against today's rest on the seeds finished."), off_lines(off),
            xl_lines(xl))
    for (a, f) in zip(arms, figs)
        append!(lines, arm_lines(a, f, "Its readings cover only those finished, and it cannot pass or be chosen."))
    end
    for f in figs
        rise = settle(f.gini - bf.gini)
        rise > GINI_NOTE && push!(lines, "**Gini rises by $(fmt(rise)) in $(f.name) ($(places(bf.gini, 3)) today, " *
                                         "$(places(f.gini, 3))): more than $(fmt(GINI_NOTE)).**", "")
    end
    push!(lines, "## Arms", "", row_text(["Arm", "Rule 13", "VI-1", "No disease", "IV-A3"]), "|---|---|---|---|---|")
    for (a, f) in zip([base; arms], [bf; figs])
        push!(lines, row_text([a === base ? "$(a.name) (baseline)" : a.name, rule13_text(f.rule),
                               ("$(r.run.folder) ($(length(r.seeds)) of $(r.run.planned))"
                                for r in (a.vi1, a.nodisease, a.iva3))...]))
    end
    push!(lines, "", "## Reading table", "",
          "Each arm against today's. Near is a failing row missed by no more than $(percent(NEAR_BY)) of its bar or " *
          "by one seed. Every figure is rounded to $SETTLE_DIGITS places before it meets its bar. Healthy means " *
          "strictly healthy (no disease for 10 periods), by the user's decision after Part 1; the healthy-trade bar " *
          "is dropped (the user's), its share a reading. A missing matched ratio reads missing, not fail, and its arm " *
          "can't pass.", "")
    append!(lines, table_lines(figs, bf))
    push!(lines, "", "## Choice", "")
    rows = [screen_trade(f, bf) for f in figs]
    passing = [f.name for (f, r) in zip(figs, rows) if trade_passes(f, r)]
    near = ["$(f.name) ($(first(x.name for x in r if !x.pass)))" for (f, r) in zip(figs, rows) if trade_near(f, r)]
    chosen = choose_trade_arm(figs, bf)
    if chosen !== nothing
        push!(lines, "Chosen: $(figs[chosen].name). Passing: $(join(passing, ", ")).", "",
              "Among those that pass: the largest ratio of traders to similar non-traders, then the smallest rise in " *
              "Gini, then the higher trough, then the simpler rule (no blend over a blend, own price over local).", "",
              "Result: one or more arms pass: take the choice to confirmation.")
    elseif !isempty(near)
        push!(lines, "No arm passes. Near passing: $(join(near, "; ")).", "",
              "Result: none passes, but one is near. One further round of at most 3 arms around it, named in the " *
              "ledger before running, on the same seeds. No more without the user. If this is already that round: " *
              "stop, as below.")
    else
        push!(lines, "No arm passes. No arm is near.", "",
              "Result: Stop. Report what failed and what that says about the idea. What next is the user's call. " *
              "No confirmation run.")
    end
    waiting = [f.name for f in figs if !f.finished]
    isempty(waiting) || push!(lines, "", "Not eligible, unfinished: $(join(waiting, ", ")).")
    for (f, r) in zip(figs, rows)
        settle(f.tph) > settle(bf.tph) && !r[1].pass && !ratio_missing(f) &&
            push!(lines, "", "$(f.name): trades per head rise ($(places(f.tph, 3)) against today's " *
                             "$(places(bf.tph, 3))) but healthy agents aren't richer by the bar: more trade isn't the goal.")
    end
    push!(lines, "", "## Readings", "", readings_text(base) * HEALTH_TEXT, "")
    append!(lines, readings_lines([bf; figs]))
    push!(lines, "", match_text(base.vi1.window), "", "## Ratios to today's", "",
          "Each arm's mean ÷ today's, with the 2.5% to 97.5% range of $BOOT_REPS resamples (random seed $BOOT_SEED), " *
          "resampling each side independently since seeds don't pair. A seed with no figure is left out.", "")
    append!(lines, trade_ratio_lines(figs, bf))
    push!(lines, "", "## Trade on ÷ off", "")
    append!(lines, on_off_lines([a.name => a.vi1 for a in [base; arms]], off))
    return join(lines, "\n") * "\n"
end

# ---- the command line

const TRADE_REPORT_USAGE =
    "usage: julia --project=julia julia/xxl_trade_report.jl --part1 --on FOLDER --off FOLDER --nodisease FOLDER " *
    "--iva3 FOLDER --xl FOLDER [--out DIR] [--label NAME]\n" *
    "       julia --project=julia julia/xxl_trade_report.jl --base NAME=VI1,NODISEASE,IVA3 " *
    "--arms NAME=VI1,NODISEASE,IVA3,... --off FOLDER --xl FOLDER [--out DIR] [--label NAME]\n" *
    "       julia --project=julia julia/xxl_trade_report.jl --confirm --vi1 FOLDER --off FOLDER [--out DIR] [--label NAME]"

# `NAME=VI1,NODISEASE,IVA3,NAME=...` as `NAME => [three folders]` pairs: an item with `=` starts an arm.
function trade_arm_specs(v::AbstractString)
    arms = Pair{String,Vector{String}}[]
    for item in split(v, ",")
        eq = findfirst('=', item)
        if eq === nothing
            (isempty(arms) || isempty(item)) && throw(ArgumentError("an arm is NAME=VI1,NODISEASE,IVA3, not $(repr(v))"))
            push!(last(arms[end]), String(item))
        else
            (eq == 1 || eq == lastindex(item)) && throw(ArgumentError("an arm is NAME=VI1,NODISEASE,IVA3, not $(repr(item))"))
            push!(arms, String(item[1:prevind(item, eq)]) => [String(item[nextind(item, eq):end])])
        end
    end
    for (name, folders) in arms
        length(folders) == 3 ||
            throw(ArgumentError("arm $name needs three folders (VI-1, no disease, IV-A3), not $(length(folders))"))
    end
    return arms
end

"""
The report's command line, in one of three modes (see [`TRADE_REPORT_USAGE`](@ref)): `--part1` with `--on`, `--off`,
`--nodisease`, `--iva3` and `--xl`; `--confirm` with `--vi1` and `--off`; else screening, with `--base` (one arm),
`--arms` (`NAME=VI1,NODISEASE,IVA3`, comma-separated, repeatable), `--off` and `--xl`. Every folder is under `--out`
(default `results-julia-xxl`); `--label` defaults to `part1`, `confirm` or `screen`. Returns `(; mode, folders, base,
arms, out, label)`, `folders` by option name without its dashes. Throws `ArgumentError` on a usage error.
"""
function trade_report_args(args::Vector{String})
    folders, part1, confirm = Dict{String,String}(), false, false
    base, arms, out, label = nothing, Pair{String,Vector{String}}[], RESULTS_XXL, nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--part1"
            part1 = true
        elseif a == "--confirm"
            confirm = true
        elseif a in ("--on", "--off", "--nodisease", "--iva3", "--xl", "--vi1", "--base", "--arms", "--out", "--label")
            i += 1
            i <= length(args) || throw(ArgumentError("$a needs a value"))
            v = args[i]
            if a == "--base"
                b = trade_arm_specs(v)
                length(b) == 1 || throw(ArgumentError("--base is one arm"))
                base = b[1]
            elseif a == "--arms"
                append!(arms, trade_arm_specs(v))
            elseif a == "--out"
                out = v
            elseif a == "--label"
                (occursin(r"[/\\]", v) || isempty(v)) && throw(ArgumentError("--label is a name, not $(repr(v))"))
                label = v
            else
                haskey(folders, a[3:end]) && throw(ArgumentError("$a is given twice"))
                folders[a[3:end]] = v
            end
        else
            throw(ArgumentError("unexpected argument $a"))
        end
        i += 1
    end
    part1 && confirm && throw(ArgumentError("--part1 and --confirm are different reports"))
    mode = part1 ? :part1 : confirm ? :confirm : :screen
    need = mode == :part1 ? ["on", "off", "nodisease", "iva3", "xl"] : mode == :confirm ? ["vi1", "off"] : ["off", "xl"]
    for k in keys(folders)
        k in need || throw(ArgumentError("--$k is not for the $mode report"))
    end
    for k in need
        haskey(folders, k) || throw(ArgumentError("--$k is needed"))
    end
    if mode == :screen
        base === nothing && throw(ArgumentError("--base is needed"))
        isempty(arms) && throw(ArgumentError("--arms is needed"))
        allunique([first(base); first.(arms)]) || throw(ArgumentError("an arm is named twice"))
    else
        (base === nothing && isempty(arms)) || throw(ArgumentError("--base and --arms are for screening"))
    end
    return (; mode, folders, base, arms, out, label=something(label, String(mode)))
end

"""
    trade_report_main(args) -> exit code

The command line of julia/xxl_trade_report.jl: reads the folders' finished seeds, writes [`trade_report`](@ref)'s
markdown to `<out>/trade-<label>.md` and prints it with where it went. It runs nothing. Returns 2 on a usage error, a
folder that is missing or isn't a study folder, a folder with no finished seed, or a VI-1 folder that stops short of t =
`STUDY_END`. Anything that goes wrong after is thrown with its stack trace.
"""
function trade_report_main(args::Vector{String})
    a, kw = try
        a = trade_report_args(args)
        function study(name, folder)
            path = joinpath(a.out, folder)
            isdir(path) || throw(ArgumentError("$path is not a folder"))
            return read_trade_run(name, path)
        end
        arm(spec) = TradeArm(first(spec), (study(first(spec), f) for f in last(spec))...)
        f = a.folders
        off = study("off", f["off"])
        kw = if a.mode == :part1
            (; part1=true, base=TradeArm("today", study("today", f["on"]), study("today", f["nodisease"]),
                                         study("today", f["iva3"])), xl=read_xl_prices(joinpath(a.out, f["xl"])), off)
        elseif a.mode == :confirm
            (; confirm=true, base=TradeArm("study", study("study", f["vi1"]), nothing, nothing), off)
        else
            (; base=arm(a.base), arms=TradeArm[arm(s) for s in a.arms], xl=read_xl_prices(joinpath(a.out, f["xl"])), off)
        end
        check_trade_arm(kw.base)
        haskey(kw, :arms) && foreach(check_trade_arm, kw.arms)
        haskey(kw, :arms) && check_same_seeds(kw.base, kw.arms)
        check_trade_run(off, "the trade-off run")
        a, kw
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, TRADE_REPORT_USAGE, "\n", e.msg)
        return 2
    end
    report = trade_report(; label=a.label, kw...)
    path = joinpath(a.out, "trade-$(a.label).md")
    write_atomic(path, report)
    println(report, "-> ", path)
    return 0
end
