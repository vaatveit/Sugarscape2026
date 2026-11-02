# xxl: the disease list's screening (docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md). Finished runs of
# candidate lists read against the baseline: the readings the study reports and the reading table that says which arms
# pass, which are near, and which is chosen. It reads only finished CSVs and runs nothing, so the table is code that can
# be tested before any result exists.

const LIST_SHARE = 0.9  # X9 and X10 per seed need this share of the seeds, rounded up
const NEAR_BY = 0.05  # a bar is missed narrowly by no more than this share of itself
const SCREEN_END = 500  # the screening table reads t ≤ this, of the arm and of the baseline
const SCREEN_SICK = (451, 500)  # X10 reads the share sick over these periods
const SICK_BAND = (0.01, 0.2)  # X10's bounds, inclusive
const LIST_END = 50  # the share sick by diseases is read over this many last periods
const SPREAD_WINDOW = (301, 500)  # the periods the population and its spread over seeds are read in
const LOSS_FROM = 200  # a seed loses diseases if it has fewer at its last period than in this one
const SETTLE_DIGITS = 12  # a figure is rounded to this many places before it meets a bar

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
    ListRun(name, count, founder, lengths, planned, periods, seeds)

A run folder read for the disease list: the list it ran (`count` diseases, `founder` offered to each founder, lengths
`lengths`), the seeds the folder was planned to hold, its `periods`, and the whole seeds found.
"""
struct ListRun
    name::String
    count::Int
    founder::Int
    lengths::Tuple{Int,Int}
    planned::Int
    periods::Int
    seeds::Vector{ListSeed}
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
    s = list_settings(read(joinpath(folder, "fingerprint.txt"), String))
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
    m = match(r"-s\d+-(\d+)-p\d+$", basename(rstrip(folder, ['/', '\\'])))
    planned = m === nothing ? length(seeds) : parse(Int, m.captures[1])
    return ListRun(name, s.count, s.founder, s.lengths, planned, periods, seeds)
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

"""A seed's lowest population over t = 1 to `SCREEN_END`, or to the run's last period if that is sooner."""
screen_lowest(s::ListSeed) = lowest(cut_series(s.series, min(SCREEN_END, length(s.series.population) - 1)))

"""The period (from t = 1) of a seed's lowest population over the same periods as [`screen_lowest`](@ref)."""
screen_lowest_t(s::ListSeed) = lowest_t(cut_series(s.series, min(SCREEN_END, length(s.series.population) - 1)))

"""The seeds an arm of `n` needs for X9 and for X10 per seed."""
seeds_needed(n::Int) = ceil(Int, LIST_SHARE * n)

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
  other two rows), in `SICK_BAND`. Near if within `NEAR_BY` of the band's ends.
- X10, per seed: seeds with their share sick in the band. Near if one seed short.
- Trough: the mean of the seeds' lowest populations at least the baseline's, and no seed below the baseline's lowest.
  Near if the mean is at least `1 - NEAR_BY` of the baseline's and no more than one seed is below its lowest.
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
    gone = count(s -> extinct_at(s.series) !== nothing, run.seeds)

    return [
        ScreenRow("X9", count_text(x9), count_bar, x9 >= need, x9 == need - 1),
        ScreenRow("X10, mean", fmt(mean_sick), "$(SICK_BAND[1])–$(SICK_BAND[2])", mean_pass,
                  !mean_pass && near_low <= mean_sick <= near_high),
        ScreenRow("X10, per seed", count_text(in_band_n), count_bar, in_band_n >= need, in_band_n == need - 1),
        ScreenRow("Trough", "mean $(fmt(low_mean)), lowest $(fmt(minimum(lows)))",
                  "mean at least $(fmt(base_mean)), none below $(fmt(base_min))", trough_pass,
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

The arm to take to confirmation, or `nothing` if none passes screening against `base`. Among those that pass, the arms
whose longest disease is `10` or less if any pass, else the rest; then the most seeds with their share sick in the band
over `SCREEN_SICK`, then the smallest [`population_spread`](@ref), then the shorter longest disease, then the smaller
list.
"""
function choose_arm(runs::Vector{ListRun}, base::ListRun)
    passing = [r for r in runs if arm_passes(r, screen_arm(r, base))]
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
  them; `price`: the mean, skipping NaN.
"""
function list_readings(run::ListRun; lo::Int=SPREAD_WINDOW[1], hi::Int=SPREAD_WINDOW[2])
    ss = run.seeds
    window(v) = @view v[(lo + 1):(hi + 1)]
    sick = [screen_sick(s) for s in ss]
    per_seed = (;
        trough=Float64[screen_lowest(s) for s in ss],
        trough_t=Float64[screen_lowest_t(s) for s in ss],
        births_100=Float64[window_births(s.series, 1, 100) for s in ss],
        x9=Float64[s.circulating[X9_T + 1] > 0 for s in ss],
        sick_end=sick,
        in_band_end=Float64[in_band(x) for x in sick],
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
