# xxl: the disease list's screening (docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md). Finished runs of
# candidate lists read against the baseline: the readings the study reports and the reading table that says which arms
# pass, which are near, and which is chosen, and the report and command line that print them (julia/xxl_disease_list.jl).
# It reads only finished CSVs and runs nothing, so the table is code that can be tested before any result exists.

const LIST_SHARE = 0.9  # X9 and X10 per seed need this share of the seeds, rounded up
const NEAR_BY = 0.05  # a bar is missed narrowly by no more than this share of itself
const SCREEN_END = 500  # the screening table reads t ≤ this, of the arm and of the baseline
const SCREEN_SICK = (451, 500)  # X10 reads the share sick over these periods
const SICK_BAND = (0.01, 0.2)  # X10's bounds, inclusive
const LIST_END = 50  # the share sick by diseases is read over this many last periods
const SPREAD_WINDOW = (301, 500)  # the periods the population and its spread over seeds are read in
const LOSS_FROM = 200  # a seed loses diseases if it has fewer at its last period than in this one
const SETTLE_DIGITS = 12  # a figure is rounded to this many places before it meets a bar
const SHARE_DIGITS = 5  # the places a share sick is shown to in the reading table
const TROUGH_DIGITS = 1  # the places a mean trough is shown to in the reading table

# The columns of a run's CSV that the readings need, besides `t`.
const LIST_FIELDS = ("population", "agents_ever", "fraction_sick", "diseases_circulating", "gini", "mean_sugar", "trades",
                     "mean_price")

"""A figure rounded to [`SETTLE_DIGITS`](@ref) places, so that the last bit of a sum can't move it across a bar."""
settle(x::Real) = round(x; digits=SETTLE_DIGITS)

"""The sample standard deviation of `v` (n - 1 in the denominator); NaN for fewer than two."""
function sample_sd(v::AbstractVector{<:Real})
    length(v) < 2 && return NaN
    m = mean_of(v)
    return sqrt(sum(x -> (x - m)^2, v) / (length(v) - 1))
end

"""
    ListSeed(series, sick, circulating, gini, sugar, trades, price)

One seed's run for the disease list: its population and births (a [`CompareSeries`](@ref)) and the columns
`fraction_sick`, `diseases_circulating`, `gini`, `mean_sugar`, `trades` and `mean_price`, each indexed `[t + 1]`.
"""
struct ListSeed
    series::CompareSeries
    sick::Vector{Float64}
    circulating::Vector{Float64}
    gini::Vector{Float64}
    sugar::Vector{Float64}
    trades::Vector{Float64}
    price::Vector{Float64}
end

"""
    ListRun(name, count, founder, lengths, planned, periods, seeds, folder, fingerprint)

A run folder read for the disease list: the list it ran (`count` diseases, `founder` offered to each founder, lengths
`lengths`), the seeds the folder was planned to hold, its `periods`, and the whole seeds found; the `folder`'s base name
and the text of its `fingerprint.txt`, which says what world the seeds ran in (see [`world_differences`](@ref)).
"""
struct ListRun
    name::String
    count::Int
    founder::Int
    lengths::Tuple{Int,Int}
    planned::Int
    periods::Int
    seeds::Vector{ListSeed}
    folder::String
    fingerprint::String
end

# What a fingerprint says of one setting: its numbers on the `xxl` line if that line names it, else on the `Config` line.
function list_setting(xxl_line, xxl_pattern, config_line, config_pattern, what)
    m = match(xxl_pattern, xxl_line)
    m === nothing && (m = match(config_pattern, config_line))
    m === nothing && throw(ArgumentError("the fingerprint does not say $what"))
    return parse.(Int, m.captures)
end

"""
    list_settings(fingerprint) -> (; count, founder, lengths)

The disease list a run was made with, from the text of its `fingerprint.txt`: the `xxl` line's `disease_count`,
`founder_diseases` and `disease_lengths` where it names them, else the `Config(...)` line's `disease_list`,
`diseases_per_agent` and `disease_length`. `ArgumentError` if neither line says one.
"""
function list_settings(fingerprint::AbstractString)
    xxl = match(r"^xxl (?!map )[^\n]*"m, fingerprint)
    config = match(r"^Config\([^\n]*"m, fingerprint)
    xxl_line, config_line = xxl === nothing ? "" : xxl.match, config === nothing ? "" : config.match
    count = list_setting(xxl_line, r"\bdisease_count=(\d+)", config_line, r"\bdisease_list=(\d+)", "the disease count")[1]
    founder = list_setting(xxl_line, r"\bfounder_diseases=(\d+)", config_line, r"\bdiseases_per_agent=(\d+)",
                           "the founder diseases")[1]
    lengths = list_setting(xxl_line, r"\bdisease_lengths=\(\s*(\d+),\s*(\d+)\s*\)", config_line,
                           r"\bdisease_length=\(\s*(\d+),\s*(\d+)\s*\)", "the disease lengths")
    return (; count, founder, lengths=(lengths[1], lengths[2]))
end

"""
    read_list_run(name, folder) -> ListRun

A run folder read for the disease list. Only whole seeds are read (see [`seed_done`](@ref)): anything else in the folder
is ignored, a checkpoint or a seed's CSV cut short included. `planned` is the seed count in the folder's name
(`extinction-<label>-s<first>-<seeds>-p<periods>`), else the seeds found. `ArgumentError` for a whole CSV that lacks a
column the readings need, or a folder without a fingerprint that names the list and the periods.
"""
function read_list_run(name::AbstractString, folder::AbstractString)
    periods = folder_periods(folder)
    fingerprint = read(joinpath(folder, "fingerprint.txt"), String)
    s = list_settings(fingerprint)
    files = Tuple{Int,String}[]
    for file in readdir(folder)
        m = match(r"^seed(\d+)\.csv$", file)
        m === nothing && continue
        seed_done(joinpath(folder, file), periods) && push!(files, (parse(Int, m.captures[1]), joinpath(folder, file)))
    end
    seeds = ListSeed[]
    for (k, path) in sort!(files)
        header, M = read_seed_csv(path)
        cols = [findfirst(==(column), header) for column in LIST_FIELDS]
        any(isnothing, cols) && throw(ArgumentError("$path lacks the $(join(LIST_FIELDS, ", ", " or ")) column"))
        pop, ever, sick, circulating, gini, sugar, trades, price = (M[:, j] for j in cols)
        push!(seeds, ListSeed(CompareSeries(k, pop, ever), sick, circulating, gini, sugar, trades, price))
    end
    folder_name = basename(rstrip(folder, ['/', '\\']))
    m = match(r"-s\d+-(\d+)-p\d+$", folder_name)
    planned = m === nothing ? length(seeds) : parse(Int, m.captures[1])
    return ListRun(name, s.count, s.founder, s.lengths, planned, periods, seeds, folder_name, fingerprint)
end

# A fingerprint's lines as `world_differences` compares them: without the code's checksum, the periods and the three list
# settings on the `xxl` line, and with the blanks and line endings around each line dropped.
function world_lines(fingerprint::AbstractString)
    lines = String[]
    for line in split(fingerprint, '\n')
        line = strip(line)
        (isempty(line) || startswith(line, "code sha256=") || startswith(line, "periods=")) && continue
        if startswith(line, "xxl ") && !startswith(line, "xxl map ")
            line = replace(line, r"\s*\bdisease_count=\S+" => "", r"\s*\bfounder_diseases=\S+" => "",
                           r"\s*\bdisease_lengths=\(\s*\d+,\s*\d+\s*\)" => "")
        end
        push!(lines, String(line))
    end
    return lines
end

# What a fingerprint line is of, so that a changed line is told from an added one: an `xxl map` line by its file, any other
# by its first word (`Config`, `steps`, `credit`, `xl`, ...).
function world_key(line::AbstractString)
    startswith(line, "xxl map ") && return String(split(line)[3])
    return String(match(r"^[^\s(=:]*", line).match)
end

"""
    world_differences(run, base) -> Vector{String}

The lines of `run`'s fingerprint that tell its world from `base`'s, in the fingerprint's order. A line only `run` has is
given as it is, with `(the baseline has …)` after it where `base` has a line of the same kind (the `Config` line, a map
line) that reads otherwise. A line only `base` has is given as `the baseline has …`. The `code sha256=` line, the
`periods=` line and the three list settings on the `xxl` line are left out, since the arms differ in those by design;
anything else is the world, so a credit-off run, another rule set or map, or a changed `Config` line shows. Empty if the
worlds are the same.
"""
function world_differences(run::ListRun, base::ListRun)
    mine, theirs = world_lines(run.fingerprint), world_lines(base.fingerprint)
    only_mine, only_theirs = setdiff(mine, theirs), setdiff(theirs, mine)
    partner = Dict(world_key(l) => l for l in only_theirs)
    out = String[]
    for l in only_mine
        other = get(partner, world_key(l), nothing)
        push!(out, other === nothing ? l : "$l (the baseline has $other)")
    end
    kinds = Set(world_key(l) for l in only_mine)
    for l in only_theirs
        world_key(l) in kinds || push!(out, "the baseline has $l")
    end
    return out
end

"""
The arms whose `code sha256=` lines differ, as `(checksum, names)` groups in the order the arms first show each; empty if
the arms (the baseline is not among them) all ran the same code.
"""
function code_groups(runs::Vector{ListRun})
    groups = Pair{String,Vector{String}}[]
    for r in runs
        m = match(r"^code sha256=(\S*)"m, r.fingerprint)
        code = m === nothing ? "none" : m.captures[1]
        i = findfirst(g -> first(g) == code, groups)
        i === nothing ? push!(groups, code => [r.name]) : push!(last(groups[i]), r.name)
    end
    return length(groups) > 1 ? groups : Pair{String,Vector{String}}[]
end

"""
The mean share sick of a seed over periods `lo` to `hi`, skipping NaN; NaN if the seed went extinct at or before `hi`.
The figure is rounded to [`SETTLE_DIGITS`](@ref) places.
"""
function window_sick(s::ListSeed, lo::Int, hi::Int)
    e = extinct_at(s.series)
    e !== nothing && e <= hi && return NaN
    return settle(nanmean(@view s.sick[(lo + 1):(hi + 1)]))
end

"""Whether a share sick is inside X10's band, `SICK_BAND` inclusive; false for NaN."""
in_band(x::Real) = SICK_BAND[1] <= x <= SICK_BAND[2]

"""A seed's share sick over `SCREEN_SICK`, the periods X10 reads."""
screen_sick(s::ListSeed) = window_sick(s, SCREEN_SICK...)

"""A seed's lowest population over t = 1 to `SCREEN_END`; [`screen_arm`](@ref) refuses a run that stops short of it."""
screen_lowest(s::ListSeed) = lowest(cut_series(s.series, SCREEN_END))

"""The period (from t = 1) of a seed's lowest population over the same periods as [`screen_lowest`](@ref)."""
screen_lowest_t(s::ListSeed) = lowest_t(cut_series(s.series, SCREEN_END))

"""The seeds an arm of `n` needs for X9 and for X10 per seed."""
seeds_needed(n::Int) = ceil(Int, LIST_SHARE * n)

"""
A mean share sick for the reading table: to [`SHARE_DIGITS`](@ref) places, and to more while the rounded figure would be
inside the band if `pass` is false or outside it if true, so that a failing row can't read as meeting its bar.
"""
function share_text(x::Real, pass::Bool)
    isnan(x) && return "NaN"
    d = SHARE_DIGITS
    while d < SETTLE_DIGITS && in_band(round(x; digits=d)) != pass
        d += 1
    end
    return string(round(x; digits=d))
end

"""
A mean trough and the baseline's `bar` for the reading table, as text to the same places: [`TROUGH_DIGITS`](@ref), and
more while a mean below the bar (`pass` false) would round to at least the bar's.
"""
function trough_texts(x::Real, bar::Real, pass::Bool)
    d = TROUGH_DIGITS
    while !pass && d < SETTLE_DIGITS && round(x; digits=d) >= round(bar; digits=d)
        d += 1
    end
    return string(round(x; digits=d)), string(round(bar; digits=d))
end

"""
    ScreenRow(name, value, bar, pass, near)

One row of the reading table for an arm: what it read (`value`) against the `bar` as text, whether it `pass`es, and
whether a row that fails is `near`.
"""
struct ScreenRow
    name::String
    value::String
    bar::String
    pass::Bool
    near::Bool
end

"""
    screen_arm(run, base) -> Vector{ScreenRow}

The reading table of an arm against the baseline `base`, in order: `X9`, `X10, mean`, `X10, per seed`, `Trough` and
`Extinction`. The rows read t ≤ `SCREEN_END` for both runs, except `Extinction`, which reads the whole of `run`. The
count bars are `ceil(LIST_SHARE * n)` for the `n` seeds read.

- X9: seeds with a disease circulating at t = 500 (`X9_T`). Near if one seed short.
- X10, mean: the share sick over `SCREEN_SICK`, the mean of the seeds that have one (an extinct seed has none, and fails the
  other two rows), in `SICK_BAND`. Near if within `NEAR_BY` of the band's ends. Shown to five places, and to more where
  fewer would put a failing mean inside the band.
- X10, per seed: seeds with their share sick in the band. Near if one seed short.
- Trough: the mean of the seeds' lowest populations at least the baseline's, and no seed below the baseline's lowest.
  Near if the mean is at least `1 - NEAR_BY` of the baseline's and no more than one seed is below its lowest. The means
  are shown to one place, and to more where a failing mean would round to the baseline's.
- Extinction: no seed of `run` extinct, at any period. Never near.

`ArgumentError` if either run has no seeds or does not reach t = `SCREEN_END`.
"""
function screen_arm(run::ListRun, base::ListRun)
    for r in (run, base)
        isempty(r.seeds) && throw(ArgumentError("$(r.name) has no finished seeds to screen"))
        r.periods >= SCREEN_END || throw(ArgumentError("$(r.name) stops at t = $(r.periods), short of t = $SCREEN_END"))
    end
    n = length(run.seeds)
    need = seeds_needed(n)
    count_text(k) = "$k of $n"
    count_bar = "at least $need of $n"

    x9 = count(s -> s.circulating[X9_T + 1] > 0, run.seeds)
    sicks = [screen_sick(s) for s in run.seeds]
    seen = filter(!isnan, sicks)
    mean_sick = isempty(seen) ? NaN : settle(mean_of(seen))
    in_band_n = count(in_band, sicks)
    near_low, near_high = settle.((SICK_BAND[1] * (1 - NEAR_BY), SICK_BAND[2] * (1 + NEAR_BY)))
    mean_pass = in_band(mean_sick)

    lows, base_lows = [screen_lowest(s) for s in run.seeds], [screen_lowest(s) for s in base.seeds]
    low_mean, base_mean, base_min = settle(mean_of(lows)), settle(mean_of(base_lows)), minimum(base_lows)
    below = count(<(base_min), lows)
    trough_pass = low_mean >= base_mean && below == 0
    low_text, bar_text = trough_texts(low_mean, base_mean, low_mean >= base_mean)
    gone = count(s -> extinct_at(s.series) !== nothing, run.seeds)

    return [
        ScreenRow("X9", count_text(x9), count_bar, x9 >= need, x9 == need - 1),
        ScreenRow("X10, mean", share_text(mean_sick, mean_pass), "$(SICK_BAND[1])–$(SICK_BAND[2])", mean_pass,
                  !mean_pass && near_low <= mean_sick <= near_high),
        ScreenRow("X10, per seed", count_text(in_band_n), count_bar, in_band_n >= need, in_band_n == need - 1),
        ScreenRow("Trough", "mean $low_text, lowest $(whole_text(minimum(lows)))",
                  "mean at least $bar_text, none below $(whole_text(base_min))", trough_pass,
                  !trough_pass && low_mean >= settle((1 - NEAR_BY) * base_mean) && below <= 1),
        ScreenRow("Extinction", "$gone of $n", "none", gone == 0, false),
    ]
end

"""Whether every planned seed of `run` is finished."""
finished(run::ListRun) = length(run.seeds) >= run.planned

"""Whether an arm passes screening: every row passes and every planned seed finished."""
arm_passes(run::ListRun, rows::Vector{ScreenRow}) = finished(run) && all(r -> r.pass, rows)

"""
Whether an arm is near passing: every planned seed finished, exactly one row fails, and that row is near (see
[`screen_arm`](@ref)).
"""
function arm_near(run::ListRun, rows::Vector{ScreenRow})
    finished(run) || return false
    failing = [r for r in rows if !r.pass]
    return length(failing) == 1 && failing[1].near
end

"""
The spread of the seeds' population over periods `lo` to `hi`: the sample standard deviation of their mean populations
over the mean of them. NaN for fewer than two seeds or a mean of 0.
"""
function population_spread(run::ListRun; lo::Int=SPREAD_WINDOW[1], hi::Int=SPREAD_WINDOW[2])
    v = [window_population(s.series, lo, hi) for s in run.seeds]
    m = isempty(v) ? NaN : mean_of(v)
    return m > 0 ? sample_sd(v) / m : NaN
end

"""
    choose_arm(runs, base) -> Union{Nothing,ListRun}

The arm to take to confirmation, or `nothing` if none passes screening against `base`. An arm with no finished seed does
not pass. Among those that pass, the arms whose longest disease is `10` or less if any pass, else the rest; then the most
seeds with their share sick in the band over `SCREEN_SICK`, then the smallest [`population_spread`](@ref), then the shorter
longest disease, then the smaller list.
"""
function choose_arm(runs::Vector{ListRun}, base::ListRun)
    passing = [r for r in runs if !isempty(r.seeds) && arm_passes(r, screen_arm(r, base))]
    isempty(passing) && return nothing
    book = [r for r in passing if r.lengths[2] <= 10]
    pool = isempty(book) ? passing : book
    function order(r)
        spread = population_spread(r)
        return (-count(s -> in_band(screen_sick(s)), r.seeds), isnan(spread) ? Inf : spread, r.lengths[2], r.count)
    end
    return pool[argmin(order.(pool))]
end

"""
    bootstrap_ratio_apart(run, base; reps=BOOT_REPS, seed=BOOT_SEED) -> (; ratio, lo, hi)

The ratio of the mean of `run` to the mean of `base`, with the 2.5% and 97.5% percentiles of that ratio over `reps`
resamples. Seeds don't pair between two runs, so each side is resampled on its own, with replacement, and may have a
different number of seeds. The draws come from a `Xoshiro(seed)` of their own, so the interval is the same on every run. A
resample whose ratio is not finite is dropped. NaN throughout if the ratio is not finite.
"""
function bootstrap_ratio_apart(
    run::Vector{Float64}, base::Vector{Float64}; reps::Int=BOOT_REPS, seed::Int=BOOT_SEED
)
    ratio = mean_of(run) / mean_of(base)
    isfinite(ratio) || return (; ratio, lo=NaN, hi=NaN)
    rng = Xoshiro(seed)
    n_run, n_base = length(run), length(base)
    draws = Float64[]
    for _ in 1:reps
        a = b = 0.0
        for _ in 1:n_run
            a += run[rand(rng, 1:n_run)]
        end
        for _ in 1:n_base
            b += base[rand(rng, 1:n_base)]
        end
        r = (a / n_run) / (b / n_base)
        isfinite(r) && push!(draws, r)
    end
    lo, hi = percentile_interval(draws)
    return (; ratio, lo, hi)
end

"""
    run_lowest(run) -> (; mean, lowest)

The lowest population of each seed over the whole run from t = 1, as the mean over seeds and the lowest of them. Unlike
the trough of [`list_readings`](@ref), which stops at t = `SCREEN_END`, this sees a later fall. No bar reads it.
"""
function run_lowest(run::ListRun)
    lows = Float64[lowest(s.series) for s in run.seeds]
    return (; mean=mean_of(lows), lowest=minimum(lows))
end

# A seed's trades over its population, both summed over periods `lo` to `hi`; NaN if the population is 0 throughout.
function trades_per_head(s::ListSeed, lo::Int, hi::Int)
    heads = sum(@view s.series.population[(lo + 1):(hi + 1)])
    return heads == 0 ? NaN : sum(@view s.trades[(lo + 1):(hi + 1)]) / heads
end

"""
    list_readings(run; lo=301, hi=500)

The figures the study reports for a run, as a `NamedTuple` over its seeds, with the per-seed figures in `per_seed`
(vectors in the seeds' order, for the intervals):

- `trough` and `trough_t`: the lowest population from t = 1 to t = 500 and the period it was at (the mean over seeds);
- `births_100`: the births in t = 1 to 100, `agents_ever` at t = 100 less t = 0;
- `x9`: the share of seeds with a disease circulating at t = 500;
- `sick_end`: the share sick over t = 451 to 500, the mean of the seeds that have one; `in_band_end`, `under_end` and
  `over_end`: the seeds with it inside, under and over `SICK_BAND` (an extinct seed is none of them);
- `population` over periods `lo` to `hi`, and its `spread` over seeds (see [`population_spread`](@ref));
- `gini` and `sugar`: the mean over `lo` to `hi`; `trades_per_head`: a seed's trades over its population, each summed over
  them; `price`: the mean, skipping NaN;
- `sick` and `in_band`: the share sick over periods `lo` to `hi` (the seeds' means, then their mean, skipping an extinct
  seed's) and the seeds with it inside `SICK_BAND`. Unlike `sick_end` this follows the window the caller gives.
"""
function list_readings(run::ListRun; lo::Int=SPREAD_WINDOW[1], hi::Int=SPREAD_WINDOW[2])
    ss = run.seeds
    window(v) = @view v[(lo + 1):(hi + 1)]
    sick = [screen_sick(s) for s in ss]
    sick_window = [window_sick(s, lo, hi) for s in ss]
    per_seed = (;
        trough=Float64[screen_lowest(s) for s in ss],
        trough_t=Float64[screen_lowest_t(s) for s in ss],
        births_100=Float64[window_births(s.series, 1, 100) for s in ss],
        x9=Float64[s.circulating[X9_T + 1] > 0 for s in ss],
        sick_end=sick,
        in_band_end=Float64[in_band(x) for x in sick],
        sick=sick_window,
        population=Float64[window_population(s.series, lo, hi) for s in ss],
        gini=Float64[nanmean(window(s.gini)) for s in ss],
        sugar=Float64[nanmean(window(s.sugar)) for s in ss],
        trades_per_head=Float64[trades_per_head(s, lo, hi) for s in ss],
        price=Float64[nanmean(window(s.price)) for s in ss],
    )
    return (;
        trough=mean_of(per_seed.trough),
        trough_t=mean_of(per_seed.trough_t),
        births_100=mean_of(per_seed.births_100),
        x9=mean_of(per_seed.x9),
        sick_end=nanmean(sick),
        in_band_end=count(in_band, sick),
        under_end=count(<(SICK_BAND[1]), sick),
        over_end=count(>(SICK_BAND[2]), sick),
        sick=nanmean(sick_window),
        in_band=count(in_band, sick_window),
        population=mean_of(per_seed.population),
        spread=population_spread(run; lo, hi),
        gini=nanmean(per_seed.gini),
        sugar=nanmean(per_seed.sugar),
        trades_per_head=nanmean(per_seed.trades_per_head),
        price=nanmean(per_seed.price),
        per_seed,
    )
end

"""
    circulating_at(run, t) -> (; mean, sd, counts)

The diseases circulating at period `t`: the mean over seeds, the sample standard deviation, and `counts`, the number of
seeds that have each number of diseases.
"""
function circulating_at(run::ListRun, t::Int)
    values = filter(!isnan, Float64[s.circulating[t + 1] for s in run.seeds])
    counts = Dict{Int,Int}()
    for v in values
        counts[round(Int, v)] = get(counts, round(Int, v), 0) + 1
    end
    return (; mean=mean_of(values), sd=sample_sd(values), counts)
end

"""
    sick_by_count(run) -> Vector{NamedTuple}

The seeds grouped by the diseases circulating at the last period, in order of that count, each as `(count, seeds, sick)`:
the number of seeds and their mean share sick over the last `LIST_END` periods (NaN if all are extinct).
"""
function sick_by_count(run::ListRun)
    last = run.periods
    groups = Dict{Int,Vector{ListSeed}}()
    for s in run.seeds
        isnan(s.circulating[last + 1]) && continue
        push!(get!(groups, round(Int, s.circulating[last + 1]), ListSeed[]), s)
    end
    return [
        (; count=c, seeds=length(groups[c]), sick=nanmean([window_sick(s, last - LIST_END + 1, last) for s in groups[c]]))
        for c in sort!(collect(keys(groups)))
    ]
end

"""
The seeds with fewer diseases circulating at the last period than at t = `LOSS_FROM`; `ArgumentError` if the run is
shorter.
"""
function seeds_losing(run::ListRun)
    run.periods >= LOSS_FROM || throw(ArgumentError("$(run.name) stops at t = $(run.periods), short of t = $LOSS_FROM"))
    return count(s -> s.circulating[end] < s.circulating[LOSS_FROM + 1], run.seeds)
end

# ---- the report

const LIST_WINDOWS = ((501, 1000), (1501, 2000))  # past SCREEN_END, the windows the readings are repeated in, where a run reaches them
const LIST_AT = (100, 200, 500)  # the periods the diseases circulating are read at

"""`1234567` as `1,234,567`."""
thousands(n::Integer) = replace(string(n), r"(?<=\d)(?=(?:\d{3})+$)" => ",")

"""`t = 501–1,000`."""
period_text(lo::Int, hi::Int) = "t = $(thousands(lo))–$(thousands(hi))"

"""A figure to `d` places, `—` if it is not finite."""
places(x::Real, d::Int) = isfinite(x) ? string(round(x; digits=d)) : "—"

"""A population or a count as a whole number, `—` if it is not finite."""
whole_cell(x::Real) = isfinite(x) ? whole_text(x) : "—"

"""The seeds by their number of diseases, as `diseases: seeds, …` in order of the number; `—` for none."""
counts_text(counts::Dict{Int,Int}) = isempty(counts) ? "—" : join(("$k: $(counts[k])" for k in sort!(collect(keys(counts)))), ", ")

"""
    check_list_runs(runs, base)

`ArgumentError` unless the baseline has a finished seed and every run, baseline included, reaches t = `SCREEN_END`. An arm
with no finished seed is allowed: the report flags it.
"""
function check_list_runs(runs::Vector{ListRun}, base::ListRun)
    isempty(base.seeds) && throw(ArgumentError("the baseline $(base.name) has no finished seeds to read the arms against"))
    for r in (base, runs...)
        r.periods >= SCREEN_END || throw(ArgumentError("$(r.name) stops at t = $(r.periods), short of t = $SCREEN_END"))
    end
    return nothing
end

# The bold line for a run with seeds not finished; `who` names it and `effect` says what that does to the report.
function unfinished_line(run::ListRun, who::AbstractString, effect::AbstractString)
    return "**Unfinished: $(run.planned - length(run.seeds)) of $(run.planned) seeds of $who have not run. $effect**"
end

# The reading table's rows for each arm: its bars against the baseline, or a single row for an arm with no finished seed.
function screen_lines(runs::Vector{ListRun}, base::ListRun)
    lines = [row_text(["Arm", "Row", "Reading", "Bar", "Result"]), "|" * "---|"^5]
    for r in runs
        if isempty(r.seeds)
            push!(lines, row_text([r.name, "—", "no finished seed", "—", "not screened"]))
            continue
        end
        for row in screen_arm(r, base)
            push!(lines, row_text([r.name, row.name, row.value, row.bar, row.pass ? "pass" : row.near ? "near" : "fail"]))
        end
    end
    return lines
end

# Which arm the reading table chooses, or that none passes and which are near; and the arms that can't be chosen.
function choice_lines(runs::Vector{ListRun}, base::ListRun)
    screened = [(r, screen_arm(r, base)) for r in runs if !isempty(r.seeds)]
    passing = [r.name for (r, rows) in screened if arm_passes(r, rows)]
    near = ["$(r.name) ($(first(x.name for x in rows if !x.pass)))" for (r, rows) in screened if arm_near(r, rows)]
    chosen = choose_arm(runs, base)
    lines = String[]
    if chosen === nothing
        push!(lines, "No arm passes. " * (isempty(near) ? "No arm is near." : "Near passing: $(join(near, "; "))."))
    else
        push!(lines, "Chosen: $(chosen.name). Passing: $(join(passing, ", ")).",
              "",
              "Among those that pass, the arms within the book's lengths are preferred, then the most seeds inside X10's " *
              "band, the smallest spread of population over seeds, the shorter longest disease and the smaller list.")
    end
    waiting = [r.name for r in runs if isempty(r.seeds) || !finished(r)]
    isempty(waiting) || push!(lines, "", "Not eligible, unfinished: $(join(waiting, ", ")).")
    return lines
end

const READING_COLUMNS = ["Run", "Seeds", "Trough, mean", "Trough, lowest", "Trough at t, mean", "Births to t = 100", "X9",
                         "Population", "Spread", "Gini", "Mean sugar", "Trades per head", "Mean price"]
const WINDOW_COLUMNS = ["Run", "Population", "Spread", "Gini", "Mean sugar", "Trades per head", "Mean price", "Share sick",
                        "Seeds in band"]

# The cells of a run's population, spread, Gini, sugar, trades per head and price.
function window_cells(rd)
    return [whole_cell(rd.population), places(rd.spread, 3), places(rd.gini, 3), places(rd.sugar, 2),
            places(rd.trades_per_head, 3), places(rd.price, 3)]
end

# The cells of a run's share sick over the window it was read in, and the seeds inside the band.
function sick_cells(run::ListRun, rd)
    return [places(rd.sick, SHARE_DIGITS), "$(rd.in_band) of $(length(run.seeds))"]
end

# The readings table's row for a run: `rd` is its `list_readings`.
function reading_cells(run::ListRun, rd)
    n = length(run.seeds)
    return [run.name, n, places(rd.trough, TROUGH_DIGITS), whole_cell(minimum(rd.per_seed.trough)), places(rd.trough_t, 1),
            whole_cell(rd.births_100), "$(round(Int, sum(rd.per_seed.x9))) of $n", window_cells(rd)...]
end

const RATIO_MEASURES = (("Trough", :trough), ("Births to t = 100", :births_100), ("X9", :x9),
                        ("Share sick, $(period_text(SCREEN_SICK...))", :sick_end),
                        ("Population", :population), ("Gini", :gini), ("Mean sugar", :sugar),
                        ("Trades per head", :trades_per_head), ("Mean price", :price))
const WINDOW_MEASURES = RATIO_MEASURES[5:end]

# The ratio of each arm's mean to the baseline's, per measure: the seeds' figures that exist, each side resampled alone.
function ratio_lines(arms::Vector{ListRun}, reads, base_read, measures)
    lines = [row_text(["Arm", "Reading", "Ratio", "95% interval", "Against 1"]), "|" * "---|"^5]
    for (r, rd) in zip(arms, reads), (name, key) in measures
        b = bootstrap_ratio_apart(filter(!isnan, getproperty(rd.per_seed, key)),
                                  filter(!isnan, getproperty(base_read.per_seed, key)))
        push!(lines, row_text([r.name, name, finite_text(b.ratio), interval_text(b.lo, b.hi),
                               state_text(interval_state(b.lo, b.hi, 1), b.lo, b.hi)]))
    end
    return lines
end

# The readings of the runs `shown` (the baseline first) at t ≤ 500: the main table, the diseases circulating, the share sick
# over t = 451–500, and the ratios of the arms to the baseline.
function readings_lines(shown::Vector{ListRun})
    reads = [list_readings(r) for r in shown]
    lines = [
        "The trough and X9 read t ≤ $SCREEN_END, births t ≤ 100, the share sick $(period_text(SCREEN_SICK...)), the rest " *
        "$(period_text(SPREAD_WINDOW...)). The baseline comes first.",
        "",
        row_text(READING_COLUMNS), "|" * "---|"^length(READING_COLUMNS),
        (row_text(reading_cells(r, rd)) for (r, rd) in zip(shown, reads))...,
        "",
        "Diseases circulating, by the number of diseases: seeds.",
        "",
        row_text(["Run", "At", "Mean", "SD", "Seeds by diseases"]), "|" * "---|"^5,
    ]
    for t in LIST_AT, r in shown
        c = circulating_at(r, t)
        push!(lines, row_text([r.name, "t = $t", places(c.mean, 2), places(c.sd, 2), counts_text(c.counts)]))
    end
    push!(lines, "", "Share sick over $(period_text(SCREEN_SICK...)), the mean of the seeds that have one, and the seeds " *
                     "under, inside and over $(SICK_BAND[1])–$(SICK_BAND[2]). An extinct seed has none.", "",
          row_text(["Run", "Mean", "Under", "Inside", "Over", "No value"]), "|" * "---|"^6)
    for (r, rd) in zip(shown, reads)
        n = length(r.seeds)
        push!(lines, row_text([r.name, places(rd.sick_end, SHARE_DIGITS), rd.under_end, rd.in_band_end, rd.over_end,
                               n - rd.under_end - rd.in_band_end - rd.over_end]))
    end
    push!(lines, "", "Ratios of each arm's mean to the baseline's, with the 2.5% to 97.5% range of $BOOT_REPS resamples " *
                     "(random seed $BOOT_SEED), resampling each side independently since seeds don't pair. A seed with " *
                     "no figure is left out.", "")
    append!(lines, ratio_lines(shown[2:end], reads[2:end], reads[1], RATIO_MEASURES))
    push!(lines, "")
    return lines
end

# One window past t = 500: the runs that reach it, the baseline first, and the arms' ratios to the baseline if it does.
function window_lines(shown::Vector{ListRun}, base::ListRun, w::Tuple{Int,Int})
    members = [r for r in shown if r.periods >= w[2]]
    reads = [list_readings(r; lo=w[1], hi=w[2]) for r in members]
    lines = ["### $(period_text(w...))", "", row_text(WINDOW_COLUMNS), "|" * "---|"^length(WINDOW_COLUMNS),
             (row_text([r.name, window_cells(rd)..., sick_cells(r, rd)...]) for (r, rd) in zip(members, reads))..., ""]
    if first(members) === base
        append!(lines, ratio_lines(members[2:end], reads[2:end], reads[1], WINDOW_MEASURES))
        push!(lines, "")
    else
        push!(lines, "$(base.name) stops at t = $(base.periods), so there are no ratios for this window.", "")
    end
    return lines
end

# A run past t = 500, to the end: the diseases at its last period, the share sick over its last `LIST_END` periods, the seeds
# losing a disease and the lowest population over the whole run. No screening bar reads any of them.
function past_lines(run::ListRun, title::AbstractString)
    n, last = length(run.seeds), run.periods
    lo = last - LIST_END + 1
    sicks = [window_sick(s, lo, last) for s in run.seeds]
    under, inside, over = count(<(SICK_BAND[1]), sicks), count(in_band, sicks), count(>(SICK_BAND[2]), sicks)
    c = circulating_at(run, last)
    low = run_lowest(run)
    reached = inside >= seeds_needed(n) ? "$LIST_SHARE reached" : "$LIST_SHARE not reached"
    lines = [
        "### $title",
        "",
        "- Diseases at t = $(thousands(last)): mean $(places(c.mean, 2)), sd $(places(c.sd, 2)), seeds by diseases $(counts_text(c.counts))",
        "- Share sick, $(period_text(lo, last)): mean $(places(nanmean(sicks), SHARE_DIGITS)), $under under, " *
        "$inside inside, $over over, $(n - under - inside - over) no value, of $n seeds",
        "- Inside the band at the end: $inside of $n ($reached)",
        "- Seeds losing a disease after t = $LOSS_FROM: $(seeds_losing(run)) of $n",
        "- Lowest population over t = 1–$(thousands(last)): mean $(places(low.mean, TROUGH_DIGITS)), lowest $(whole_cell(low.lowest))",
        "",
        "The share sick by the diseases at t = $(thousands(last)), over $(period_text(lo, last)).",
        "",
        row_text(["Diseases", "Seeds", "Share sick"]), "|---|---|---|",
    ]
    for g in sick_by_count(run)
        push!(lines, row_text([g.count, g.seeds, places(g.sick, SHARE_DIGITS)]))
    end
    push!(lines, "")
    return lines
end

"""
    disease_list_report(runs, base; label) -> String

The screening report of the arms `runs` against the baseline `base`, as markdown: the arms and their lists beside the
baseline's, the reading table (see [`screen_arm`](@ref)) with the arm it chooses (see [`choose_arm`](@ref)), the readings
of each run with the baseline's first, and the arms' ratios to the baseline's with intervals that resample each side on its
own. Where a run goes past t = `SCREEN_END`, a section reads it further: the readings at each of `LIST_WINDOWS` that a run
reaches, and for each such run its diseases at its last period, its share sick over its last `LIST_END` periods, the seeds
losing a disease, the share sick by the number of diseases and its lowest population over the whole run. The Arms table names the folder each run was
read from. An arm whose fingerprint tells its world from the baseline's (see [`world_differences`](@ref)) is flagged in
bold at the top, a line for each difference, and so are arms that ran on different code; neither changes a result, since a
credit-off arm is a reading the reader decides on. An arm with seeds unfinished is flagged in bold at the top, and cannot
pass or be chosen. An arm with no finished seed is flagged and not screened. `ArgumentError` for a baseline with no
finished seed, or a run that stops short of t = `SCREEN_END`.
"""
function disease_list_report(runs::Vector{ListRun}, base::ListRun; label::AbstractString)
    check_list_runs(runs, base)
    arms = [r for r in runs if !isempty(r.seeds)]
    shown = vcat(base, arms)
    lines = ["# Disease list: $label", ""]
    for r in runs
        for line in world_differences(r, base)
            push!(lines, "**$(r.name) isn't the baseline's world: $line**", "")
        end
    end
    groups = code_groups(runs)
    isempty(groups) || push!(lines, "**The arms ran on different code: " *
        join(("$(join(names, ", ")) on $(first(code, 8))" for (code, names) in groups), "; ") * ".**", "")
    finished(base) || push!(lines, unfinished_line(base, "the baseline $(base.name)",
        "The trough bars are read from it, so they rest on the seeds finished."), "")
    for r in runs
        finished(r) && !isempty(r.seeds) && continue
        push!(lines, unfinished_line(r, r.name, isempty(r.seeds) ?
            "It has no finished seed, so it is not screened and cannot be chosen." :
            "Its readings cover only those finished, and it cannot pass or be chosen."), "")
    end
    push!(lines, "## Arms", "",
          row_text(["Run", "Diseases", "Founder diseases", "Lengths", "Seeds", "Periods", "Folder"]), "|" * "---|"^7)
    for r in (base, runs...)
        push!(lines, row_text([r === base ? "$(r.name) (baseline)" : r.name, r.count, r.founder,
                               "($(r.lengths[1]), $(r.lengths[2]))", "$(length(r.seeds)) of $(r.planned)", r.periods,
                               r.folder]))
    end
    push!(lines, "", "## Reading table", "",
          "Each arm against the baseline over t ≤ $SCREEN_END. Near is a failing row missed by one seed or by no more than " *
          "$(round(Int, 100NEAR_BY))% of the bar.", "")
    append!(lines, screen_lines(runs, base))
    push!(lines, "", "## Choice", "",
          "This is the screening table, read at t ≤ $SCREEN_END. It does not decide a confirmation or credit-off reading.", "")
    append!(lines, choice_lines(runs, base))
    push!(lines, "", "## Readings", "")
    append!(lines, readings_lines(shown))
    if any(r -> r.periods > SCREEN_END, arms)
        push!(lines, "## Past t = $SCREEN_END", "",
              "Read for the runs that go past it. No screening bar uses any of it. \"Inside the band at the end\" is the " *
              "per-seed X10 reading that confirmation uses, over each run's last $LIST_END periods.", "")
        for w in LIST_WINDOWS
            any(r -> r.periods >= w[2], arms) && append!(lines, window_lines(shown, base, w))
        end
        for r in shown
            r.periods > SCREEN_END || continue
            append!(lines, past_lines(r, "$(r.name)$(r === base ? " (baseline)" : ""), to the end of the run"))
        end
    end
    return join(lines, "\n") * "\n"
end

# ---- the command line

const LIST_USAGE = "usage: julia --project=julia julia/xxl_disease_list.jl --base FOLDER --arms NAME=FOLDER,NAME=FOLDER,… [--out DIR] [--label NAME]"

"""
The report's command line: `--base` (the baseline's run folder under `--out`), `--arms` (`NAME=FOLDER`, comma-separated, each
folder under `--out`, names all different), `--out` (default `results-julia-xxl`) and `--label` (default `screening`).
Returns `(; base, arms, out, label)` with `arms` as `NAME => FOLDER` pairs. Throws `ArgumentError` on a usage error.
"""
function disease_list_args(args::Vector{String})
    base, arms, out, label = nothing, nothing, RESULTS_XXL, "screening"
    i = 1
    while i <= length(args)
        a = args[i]
        a in ("--base", "--arms", "--out", "--label") || throw(ArgumentError("unexpected argument $a"))
        i += 1
        i <= length(args) || throw(ArgumentError("$a needs a value"))
        v = args[i]
        if a == "--base"
            base = v
        elseif a == "--arms"
            arms = Pair{String,String}[]
            for item in split(v, ",")
                eq = findfirst('=', item)
                (eq === nothing || eq == 1 || eq == lastindex(item)) &&
                    throw(ArgumentError("--arms takes NAME=FOLDER pairs, not $(repr(item))"))
                push!(arms, String(item[1:prevind(item, eq)]) => String(item[nextind(item, eq):end]))
            end
            allunique(first.(arms)) || throw(ArgumentError("--arms names an arm twice"))
        elseif a == "--out"
            out = v
        else
            (occursin(r"[/\\]", v) || isempty(v)) && throw(ArgumentError("--label is a name, not $(repr(v))"))
            label = v
        end
        i += 1
    end
    base === nothing && throw(ArgumentError("--base is needed"))
    arms === nothing && throw(ArgumentError("--arms is needed"))
    return (; base, arms, out, label)
end

"""
    disease_list_main(args) -> exit code

The command line of julia/xxl_disease_list.jl: reads the finished seeds of the folders, writes the report of
[`disease_list_report`](@ref) to `<out>/disease-list-<label>.md` and prints it with where it went. It runs nothing, so it
can be used while a run goes. Returns 2 on a usage error, a folder that is missing or is not a run, a baseline with no
finished seed, or a run that stops short of t = `SCREEN_END`. Anything that goes wrong after (a malformed CSV, say) is thrown
with its stack trace.
"""
function disease_list_main(args::Vector{String})
    a, base, runs = try
        a = disease_list_args(args)
        function read_run(name, folder)
            path = joinpath(a.out, folder)
            isdir(path) || throw(ArgumentError("$path is not a folder"))
            return read_list_run(name, path)
        end
        base = read_run(basename(rstrip(a.base, ['/', '\\'])), a.base)
        runs = ListRun[read_run(name, folder) for (name, folder) in a.arms]
        check_list_runs(runs, base)
        a, base, runs
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, LIST_USAGE, "\n", e.msg)
        return 2
    end
    report = disease_list_report(runs, base; label=a.label)
    path = joinpath(a.out, "disease-list-$(a.label).md")
    write_atomic(path, report)
    println(report, "-> ", path)
    return 0
end
