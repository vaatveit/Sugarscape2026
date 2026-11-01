# xxl: the credit study's comparison. Finished runs (the extinction test's folders and the loan trace's) set side by side,
# seed by seed: what a run keeps of the population, the births and the trough against a base, the ratios with bootstrap
# intervals, and how far a run's recovery trails the base's. It reads only finished CSVs and runs nothing, so it may be
# used while a long run is going (julia/xxl_credit_compare.jl is its command line).

const COMPARE_WINDOWS = ((1, 100), (101, 200), (201, 300), (301, 500), (501, 1000), (1001, 1500), (1501, 2000))
const BOOT_REPS = 10_000  # resamples of the seeds for an interval
const BOOT_SEED = 20261031  # the resamples' own random stream: a report is the same on every run
const LAG_TIMES = (100, 150, 200)  # the periods at which the recovery's lag is read
const LAG_HALF = 5  # a population is smoothed over this many periods either side to find its lag
const LAG_AHEAD = 120  # a lag is looked for in the base's population up to this many periods after the run's period

"""
    CompareSeries(seed, population, ever)

One seed's run for the comparison: the `population` and `agents_ever` of each period, `population[t + 1]` the value at
period t (t = 0 to the run's last period).
"""
struct CompareSeries
    seed::Int
    population::Vector{Float64}
    ever::Vector{Float64}
end

"""The periods a run folder ran, from the `periods=` line of its `fingerprint.txt`; `ArgumentError` if it has none."""
function folder_periods(folder::AbstractString)
    path = joinpath(folder, "fingerprint.txt")
    isfile(path) || throw(ArgumentError("$folder has no fingerprint, so its periods are unknown"))
    m = match(r"^periods=(\d+)[ \t\r]*$"m, read(path, String))
    m === nothing && throw(ArgumentError("$path has no periods= line"))
    return parse(Int, m.captures[1])
end

"""
The seeds of a run folder that are whole (see [`seed_done`](@ref)), by seed. Anything else in the folder is ignored: a
checkpoint, a temporary file, a timing or trace file, or a seed's CSV cut short. `ArgumentError` for a whole CSV that
lacks the `population` or `agents_ever` column.
"""
function read_folder_series(folder::AbstractString)
    periods = folder_periods(folder)
    series = Dict{Int,CompareSeries}()
    for name in readdir(folder)
        m = match(r"^seed(\d+)\.csv$", name)
        m === nothing && continue
        path = joinpath(folder, name)
        seed_done(path, periods) || continue
        header, M = read_seed_csv(path)
        pop, ever = (findfirst(==(column), header) for column in ("population", "agents_ever"))
        (pop === nothing || ever === nothing) &&
            throw(ArgumentError("$path lacks the population or agents_ever column"))
        k = parse(Int, m.captures[1])
        series[k] = CompareSeries(k, M[:, pop], M[:, ever])
    end
    return series
end

"""The first period at which the population is 0, else `nothing`."""
function extinct_at(s::CompareSeries)
    return findfirst(==(0), @view s.population[2:end])
end

"""The lowest population from t = 1 on."""
lowest(s::CompareSeries) = minimum(@view s.population[2:end])

"""The period (from t = 1) at which the population is lowest, the first if it is so more than once."""
lowest_t(s::CompareSeries) = argmin(@view s.population[2:end])

"""The mean population over periods `lo` to `hi`."""
window_population(s::CompareSeries, lo::Int, hi::Int) = mean_of(@view s.population[(lo + 1):(hi + 1)])

"""The agents born in periods `lo` to `hi`: the change in `agents_ever` from period `lo - 1` to `hi`."""
window_births(s::CompareSeries, lo::Int, hi::Int) = s.ever[hi + 1] - s.ever[lo]

"""
The births in periods `lo` to `hi` over the sum of the population in them; NaN if the population is 0 throughout.
"""
function births_per_head(s::CompareSeries, lo::Int, hi::Int)
    heads = sum(@view s.population[(lo + 1):(hi + 1)])
    return heads == 0 ? NaN : window_births(s, lo, hi) / heads
end

"""`s` cut to its first `periods` periods."""
cut_series(s::CompareSeries, periods::Int) =
    CompareSeries(s.seed, s.population[1:(periods + 1)], s.ever[1:(periods + 1)])

"""
Whether a seed is out of the window starting at period `lo`: it went extinct before the window, or in its first period,
so that its population is 0 throughout it. Its figures there say nothing of the run, and a ratio against them is 0 or
undefined.
"""
function left_out(s::CompareSeries, lo::Int)
    e = extinct_at(s)
    return e !== nothing && e <= lo
end

"""The `q` quantile (0 to 1) of the sorted `v`, linear between the nearest two."""
function quantile_of(v::Vector{Float64}, q::Float64)
    h = (length(v) - 1) * q + 1
    i = floor(Int, h)
    j = min(i + 1, length(v))
    return v[i] + (h - i) * (v[j] - v[i])
end

"""The 2.5% and 97.5% percentiles of the resampled figures `draws` (sorted by this); NaN, NaN if there are none."""
function percentile_interval(draws::Vector{Float64})
    isempty(draws) && return (NaN, NaN)
    sort!(draws)
    return quantile_of(draws, 0.025), quantile_of(draws, 0.975)
end

"""
    bootstrap_ratio(run, base; reps=BOOT_REPS, seed=BOOT_SEED) -> (; ratio, lo, hi)

The ratio of the mean of `run` to the mean of `base` (the values of the same seeds, pair by pair), with the 2.5% and
97.5% percentiles of that ratio over `reps` resamples that draw seeds with replacement. The draws come from a
`Xoshiro(seed)` of their own, so the interval is the same on every run and no global stream is touched. A resample whose
ratio is not finite is dropped. NaN throughout if the ratio is not finite.
"""
function bootstrap_ratio(run::Vector{Float64}, base::Vector{Float64}; reps::Int=BOOT_REPS, seed::Int=BOOT_SEED)
    length(run) == length(base) || throw(DimensionMismatch("run and base differ in length"))
    n = length(run)
    ratio = sum(run) / sum(base)  # the means have the same count, so it is the ratio of the means
    isfinite(ratio) || return (; ratio, lo=NaN, hi=NaN)
    rng = Xoshiro(seed)
    draws = Float64[]
    for _ in 1:reps
        a = b = 0.0
        for _ in 1:n
            i = rand(rng, 1:n)
            a += run[i]
            b += base[i]
        end
        r = a / b
        isfinite(r) && push!(draws, r)
    end
    lo, hi = percentile_interval(draws)
    return (; ratio, lo, hi)
end

"""
    bootstrap_lift(run, off, on; reps=BOOT_REPS, seed=BOOT_SEED) -> (; lift, lo, hi)

The lift kept: the mean of `run` less the mean of `off`, over the mean of `on` less the mean of `off` (1 for a run as good
as `on`, 0 for one as good as `off`), with the percentile interval over `reps` resamples of the seeds (triples) as in
[`bootstrap_ratio`](@ref). NaN throughout if the means of `on` and `off` are equal; a resample whose two means are equal
is dropped.
"""
function bootstrap_lift(
    run::Vector{Float64}, off::Vector{Float64}, on::Vector{Float64}; reps::Int=BOOT_REPS, seed::Int=BOOT_SEED
)
    n = length(run)
    (length(off) == n && length(on) == n) || throw(DimensionMismatch("run, off and on differ in length"))
    n == 0 && return (; lift=NaN, lo=NaN, hi=NaN)
    lift_of(r, f, o) = (r / n - f / n) / (o / n - f / n)
    full = lift_of(sum(run), sum(off), sum(on))
    sum(on) / n == sum(off) / n && return (; lift=NaN, lo=NaN, hi=NaN)
    rng = Xoshiro(seed)
    draws = Float64[]
    for _ in 1:reps
        r = f = o = 0.0
        for _ in 1:n
            i = rand(rng, 1:n)
            r += run[i]
            f += off[i]
            o += on[i]
        end
        o / n == f / n && continue
        push!(draws, lift_of(r, f, o))
    end
    lo, hi = percentile_interval(draws)
    return (; lift=full, lo, hi)
end

"""Where an interval `lo` to `hi` lies against `line`: `:above`, `:below`, or `:straddles` (touching it is straddling)."""
function interval_state(lo::Real, hi::Real, line::Real)
    lo > line && return :above
    hi < line && return :below
    return :straddles
end

"""Where an interval lies against the band `low` to `high`: `:inside` it, `:above`, `:below`, or `:straddles` an edge."""
function band_state(lo::Real, hi::Real; low::Real=0.95, high::Real=1.05)
    lo > low && hi < high && return :inside
    lo > high && return :above
    hi < low && return :below
    return :straddles
end

"""A population smoothed: its mean over periods `t ± LAG_HALF`, as many of them as the series has."""
function smoothed(s::CompareSeries, t::Int)
    last = length(s.population) - 1
    return mean_of(@view s.population[(max(t - LAG_HALF, 0) + 1):(min(t + LAG_HALF, last) + 1)])
end

"""The periods `population_lag` looks through: from just after `base`'s lowest point to `t + LAG_AHEAD`, or as far as it can be smoothed."""
function lag_periods(base::CompareSeries, t::Int)
    return (lowest_t(base) + 1):min(t + LAG_AHEAD, length(base.population) - 1 - LAG_HALF)
end

"""
    population_lag(base, run, t) -> Int

How many periods `run` trails `base` in its recovery at period `t`: `t - t′`, where `t′` is the period, after `base`'s
lowest point and no later than `t + LAG_AHEAD`, at which `base`'s population (smoothed over `t′ ± LAG_HALF`) is nearest
`run`'s (smoothed likewise) at `t`. The earliest such period if two are as near. Positive when `base` was there first.
`ArgumentError` if there is no such period.
"""
function population_lag(base::CompareSeries, run::CompareSeries, t::Int)
    candidates = lag_periods(base, t)
    isempty(candidates) && throw(ArgumentError("seed $(base.seed): no period after the lowest point to match t = $t"))
    target = smoothed(run, t)
    gaps = [abs(smoothed(base, tp) - target) for tp in candidates]
    return t - candidates[argmin(gaps)]
end

# ---- the report

"""A figure for the report, `—` if it is not finite."""
finite_text(x::Real) = isfinite(x) ? fmt(x) : "—"

interval_text(lo, hi) = isfinite(lo) && isfinite(hi) ? "[$(fmt(lo)), $(fmt(hi))]" : "—"
state_text(state, lo, hi) = isfinite(lo) && isfinite(hi) ? string(state) : "—"
row_text(cells) = "| " * join(cells, " | ") * " |"
plural(n, singular, several) = "$n $(n == 1 ? singular : several)"

"""A run folder for the comparison: its name under the output folder, its periods and its whole seeds."""
function credit_folder(out::AbstractString, name::AbstractString)
    folder = joinpath(out, name)
    return (; name, periods=folder_periods(folder), series=read_folder_series(folder))
end

const COMPARE_MEASURES = (
    ("Mean population", window_population),
    ("Births", window_births),
    ("Births per head", births_per_head),
)

const COMPARE_COLUMNS = ["Window", "Measure", "Ratio", "95% interval", "Against 1", "Against 0.95–1.05",
                         "Per-seed range", "Below base", "Pairs"]

"""One row of a comparison: the ratio of the means of `run_v` and `base_v` (the seeds' figures, in step) and what it shows."""
function ratio_row(window, measure, run_v, base_v)
    b = bootstrap_ratio(run_v, base_v)
    per_seed = filter(isfinite, run_v ./ base_v)
    return row_text([
        window, measure, finite_text(b.ratio), interval_text(b.lo, b.hi),
        state_text(interval_state(b.lo, b.hi, 1), b.lo, b.hi),
        state_text(band_state(b.lo, b.hi), b.lo, b.hi),
        isempty(per_seed) ? "—" : range_text(per_seed),
        count(run_v .< base_v),
        length(run_v),
    ])
end

"""The rows of the lag table: at each of `LAG_TIMES` the run reaches, the seeds extinct on neither side by then."""
function lag_rows(bs, rs, periods::Int)
    alive(s, t) = (e = extinct_at(s); e === nothing || e > t)
    rows = String[]
    for t in LAG_TIMES
        t + LAG_HALF <= periods || continue
        lags = Float64[population_lag(b, r, t) for (b, r) in zip(bs, rs)
                       if alive(b, t) && alive(r, t) && !isempty(lag_periods(b, t))]
        push!(rows, row_text(["t = $t", isempty(lags) ? "—" : fmt(mean_of(lags)),
                              isempty(lags) ? "—" : range_text(lags), length(lags)]))
    end
    return rows
end

"""
The report's section of `run` against `base` (folders of [`credit_folder`](@ref)) under `title`: the seeds they share, how
many went extinct, the table of ratios for the periods both reach, a line for each window that leaves pairs out, and the
lag table.
"""
function compare_section(title, base, run)
    shared = sort!(collect(intersect(keys(base.series), keys(run.series))))
    periods = min(base.periods, run.periods)
    n = length(shared)
    bs = [cut_series(base.series[k], periods) for k in shared]
    rs = [cut_series(run.series[k], periods) for k in shared]
    gone(ss) = count(s -> extinct_at(s) !== nothing, ss)
    lines = [
        "## $title",
        "",
        "- Seeds shared with $(base.name): $n",
        "- Extinct: $(base.name) $(gone(bs)) of $n, $(run.name) $(gone(rs)) of $n",
    ]
    run.periods == base.periods || push!(
        lines,
        "- $(run.name) reaches t = $(run.periods), $(base.name) t = $(base.periods): compared over t ≤ $periods",
    )
    if n == 0
        push!(lines, "", "No seed is finished in both.", "")
        return lines
    end
    reached = [w for w in COMPARE_WINDOWS if w[2] <= periods]
    keep = Dict(w => [i for i in 1:n if !left_out(bs[i], w[1]) && !left_out(rs[i], w[1])] for w in reached)
    rows = [ratio_row("1–$periods", "Trough", [lowest(s) for s in rs], [lowest(s) for s in bs])]
    for (measure, f) in COMPARE_MEASURES, w in reached
        push!(rows, ratio_row("$(w[1])–$(w[2])", measure,
                              Float64[f(rs[i], w...) for i in keep[w]], Float64[f(bs[i], w...) for i in keep[w]]))
    end
    push!(lines, "", row_text(COMPARE_COLUMNS), "|" * "---|"^length(COMPARE_COLUMNS), rows...)
    notes = ["- $(plural(n - length(keep[w]), "pair", "pairs")) left out as extinct in t = $(w[1])–$(w[2])"
             for w in reached if length(keep[w]) < n]
    isempty(notes) || push!(lines, "", notes...)
    lag = lag_rows(bs, rs, periods)
    if !isempty(lag)
        push!(lines, "", "Lag: the periods by which $(run.name) trails $(base.name) in recovery (positive: $(base.name) was " *
                         "there first), after $(base.name)'s lowest point.", "",
              row_text(["At", "Lag, mean", "Per-seed range", "Pairs"]), "|---|---|---|---|", lag...)
    end
    push!(lines, "")
    return lines
end

"""
The lift kept by `run` over the seeds that `on`, `off` and `run` share, as two table rows (the trough, and the births in
periods 1 to 100) with the lift, its interval and where it lies against 0.5. Over the periods all three reach.
"""
function lift_section(on, off, run)
    shared = sort!(collect(intersect(keys(on.series), keys(off.series), keys(run.series))))
    periods = min(on.periods, off.periods, run.periods)
    cut(f) = [cut_series(f.series[k], periods) for k in shared]
    ons, offs, runs = cut(on), cut(off), cut(run)
    function lift_row(name, run_v, off_v, on_v)
        v = bootstrap_lift(run_v, off_v, on_v)
        return row_text([name, finite_text(v.lift), interval_text(v.lo, v.hi),
                         state_text(interval_state(v.lo, v.hi, 0.5), v.lo, v.hi), length(run_v)])
    end
    window = (1, 100)
    triples = periods >= window[2] ? [i for i in eachindex(shared)
                                      if !any(left_out(ss[i], window[1]) for ss in (ons, offs, runs))] : Int[]
    births(ss) = Float64[window_births(ss[i], window...) for i in triples]
    return [
        "Lift kept: the run less off, over on less off (1 if $(run.name) does as well as $(on.name), 0 if as $(off.name)), " *
        "over the $(length(shared)) seeds all three share, t ≤ $periods.",
        "",
        row_text(["Measure", "Lift kept", "95% interval", "Against 0.5", "Seeds"]),
        "|---|---|---|---|---|",
        lift_row("Lift kept, trough", lowest.(runs), lowest.(offs), lowest.(ons)),
        lift_row("Lift kept, births t ≤ $(window[2])", births(runs), births(offs), births(ons)),
        "",
    ]
end

"""
    credit_compare(out; on, off, runs=String[], label="credit") -> String

The report comparing run folders of `out` seed by seed, and written to `<out>/credit-compare-<label>.md`. `on` and `off`
are the folders of the world with credit on and with it off; the first section is `off` against `on`, then each of `runs`
against `on` and against `off`, each with the lift it keeps between the two. A section covers the seeds both folders have
finished and the periods both reach, with one row for the trough and one for each of the windows `COMPARE_WINDOWS` that
fit: the ratio of the run's mean to the base's, over the seeds, its bootstrap interval, where that lies against 1 and
against 0.95–1.05, and the range of the seeds' own ratios. A seed extinct before a window is left out of it, and said so.
"""
function credit_compare(
    out::AbstractString; on::AbstractString, off::AbstractString, runs=String[], label::AbstractString="credit"
)
    f_on, f_off = credit_folder(out, on), credit_folder(out, off)
    f_runs = [credit_folder(out, r) for r in runs]
    finished(f) = "$(f.periods) periods, $(length(f.series)) seeds finished"
    lines = [
        "# Credit comparison: $label",
        "",
        "- On: $on ($(finished(f_on)))",
        "- Off: $off ($(finished(f_off)))",
        ["- Run: $(f.name) ($(finished(f)))" for f in f_runs]...,
        "- A ratio is the run's mean over the base's, the means over the seeds both have finished. Its interval is the " *
        "2.5% to 97.5% range of $BOOT_REPS resamples of those seeds (random seed $BOOT_SEED).",
        "- A pair is left out of a window when either seed was extinct by its first period; the trough keeps every pair.",
        "",
    ]
    append!(lines, compare_section("off against on", f_on, f_off))
    for f in f_runs, (word, base) in (("on", f_on), ("off", f_off))
        append!(lines, compare_section("$(f.name) against $word", base, f))
        append!(lines, lift_section(f_on, f_off, f))
    end
    report = join(lines, "\n") * "\n"
    write_atomic(joinpath(out, "credit-compare-$label.md"), report)
    return report
end

const COMPARE_USAGE = "usage: julia --project=julia julia/xxl_credit_compare.jl --on FOLDER --off FOLDER [--runs FOLDER,FOLDER,…] [--out DIR] [--label NAME]"

"""
The comparison's command line: `--on` and `--off` (run folders under `--out`, both needed), `--runs` (comma-separated
folders), `--out` (default `results-julia-xxl`) and `--label` (default `credit`). Throws `ArgumentError` on a usage error.
"""
function credit_compare_args(args::Vector{String})
    on, off, runs, out, label = nothing, nothing, String[], RESULTS_XXL, "credit"
    i = 1
    while i <= length(args)
        a = args[i]
        a in ("--on", "--off", "--runs", "--out", "--label") || throw(ArgumentError("unexpected argument $a"))
        i += 1
        i <= length(args) || throw(ArgumentError("$a needs a value"))
        v = args[i]
        if a == "--on"
            on = v
        elseif a == "--off"
            off = v
        elseif a == "--runs"
            runs = String.(split(v, ","))
            any(isempty, runs) && throw(ArgumentError("--runs takes folder names, C,D,…"))
        elseif a == "--out"
            out = v
        else
            (occursin(r"[/\\]", v) || isempty(v)) && throw(ArgumentError("--label is a name, not $(repr(v))"))
            label = v
        end
        i += 1
    end
    on === nothing && throw(ArgumentError("--on is needed"))
    off === nothing && throw(ArgumentError("--off is needed"))
    return (; on, off, runs, out, label)
end

"""
    credit_compare_main(args) -> exit code

The command line of julia/xxl_credit_compare.jl: prints the report of [`credit_compare`](@ref) and where it was written.
Returns 2 on a usage error or a folder with no fingerprint (or no `periods=` line in it). Anything that goes wrong after
(a malformed CSV, say) is thrown with its stack trace.
"""
function credit_compare_main(args::Vector{String})
    a = try
        a = credit_compare_args(args)
        for name in (a.on, a.off, a.runs...)
            folder_periods(joinpath(a.out, name))  # a usage error: a name that is not a run folder
        end
        a
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, COMPARE_USAGE, "\n", e.msg)
        return 2
    end
    report = credit_compare(a.out; on=a.on, off=a.off, runs=a.runs, label=a.label)
    println(report, "-> ", joinpath(a.out, "credit-compare-$(a.label).md"))
    return 0
end
