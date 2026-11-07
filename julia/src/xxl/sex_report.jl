# xxl (stage 6): the sex report (docs/superpowers/specs/2026-11-07-xxl-sex-design.md, "Part 1's bars"). Reads the three
# worlds' finished study folders (julia/src/xxl/sex_study.jl's), applies bars M and S, and writes the readings and the
# outcome by the spec's rules (julia/xxl_sex_report.jl is its command line). It reads only finished seeds and runs
# nothing.
#
# Every per-seed value is the seed's totals in the window, a numerator summed over the periods over a denominator summed
# over them, not a mean of per-period shares. A seed that reached population 0 is left out of every value; a seed with a
# zero denominator is left out of that value. Each is counted in the report.

const M_FACTOR = 1.5  # M1 and M2: today ÷ book at least this, with the interval's lower end above 1
const MIN_FERTILE_PERIODS = 5  # M2 reads the snapshot agents fertile for at least this many periods
const TROUGH_HALF = 25  # the trough window is the lowest population ± this many periods
const MIN_SEEDS = 15  # a world with fewer seeds in a value reads the bar on it as missing
const S_SHARE = 0.5  # S: today's mean metabolism drop at least this share of the book's
const S_MIN_BOOK_DROP = 0.1  # S is not judged when the book's own mean drop is under this

"""
    SexSeed(seed, extinct, values)

One whole seed of a sex study folder: the first period its population is 0 (`nothing` if never), and its per-seed
values ([`sex_values`](@ref)), each NaN where the seed is left out of it.
"""
struct SexSeed
    seed::Int
    extinct::Union{Nothing,Int}
    values::NamedTuple
end

"""
    SexWorld(world, folder, planned, periods, window, unfinished, seeds)

A world's study folder read for the report: the seeds its name plans, its periods, the window its fingerprint names, the
planned seeds that aren't whole and the whole ones.
"""
struct SexWorld
    world::String
    folder::String
    planned::Int
    periods::Int
    window::Tuple{Int,Int}
    unfinished::Vector{Int}
    seeds::Vector{SexSeed}
end

"""The bar values, with their names in the report."""
const SEX_BAR_VALUES = (
    (:no_mate, "No-mate share (M1)"),
    (:childless, "Childless share (M2)"),
    (:drop, "Metabolism drop (S)"),
    (:trough, "Trough no-mate share"),
)

"""The readings, shown and deciding nothing, with their names in the report."""
const SEX_READINGS = (
    (:eligible, "Eligible share"),
    (:fertile, "Fertile share"),
    (:blocked, "Wealth-blocked share"),
    (:no_vision, "No-mate-within-vision share"),
    (:births, "Births per fertile agent-period"),
    (:no_site, "No-site attempts per birth"),
    (:mean_distance, "Mean parent distance"),
    (:median_distance, "Median parent distance (births-weighted mean of period medians)"),
    (:mean_distance_share, "Mean parent distance ÷ vision"),
    (:median_distance_share, "Median parent distance ÷ vision (births-weighted mean of period medians)"),
)

"""The traits read at the start and end of a run, with their names in the report."""
const SEX_TRAITS = (
    ("vision", "vision"), ("metabolism", "metabolism"), ("spice_metabolism", "spice metabolism"), ("speed", "speed"),
)

sex_share(a, b) = b == 0 ? NaN : a / b

"""
    sex_values(population, metabolism, sex, agents, window, periods) -> NamedTuple

A seed's values: `population` and `metabolism` (mean metabolism) the standard CSV's columns by `[t + 1]`, `sex` the
per-period table's columns by name, `agents` the snapshot's. In `window`:

- `no_mate`: 1 − Σ `fertile_reach` ÷ Σ `fertile`;
- `childless`: of the snapshot agents whose fertile life ended in the window and who were fertile for at least
  [`MIN_FERTILE_PERIODS`](@ref) periods, the share with no child;
- `drop`: (mean metabolism at t = 0 − at the last period) ÷ at t = 0, over the whole run;
- `trough`: the no-mate share over the seed's lowest population from t = 1 (the first if tied) ± [`TROUGH_HALF`](@ref),
  clipped to t = 1 and the last period;
- the readings ([`SEX_READINGS`](@ref)): eligible ÷ population, fertile ÷ population, 1 − fertile ÷ eligible,
  1 − `fertile_vision` ÷ fertile, births ÷ fertile, `no_site` ÷ births, and the parent distances: the period means and
  medians weighted by the period's births;
- each trait's mean and sd at t = 0 and the last period (`mean_vision_start`, `sd_speed_end`, …).

NaN where a denominator is 0.
"""
function sex_values(population, metabolism, sex::Dict{String,Vector{Float64}}, agents::Dict{String,Vector{Float64}},
                    window::Tuple{Int,Int}, periods::Int)
    lo, hi = window
    total(name, a=lo, b=hi) = sum(@view sex[name][(a + 1):(b + 1)])
    no_mate(a, b) = 1 - sex_share(total("fertile_reach", a, b), total("fertile", a, b))
    births = @view sex["births"][(lo + 1):(hi + 1)]
    function by_births(name)  # a period's figure weighted by its births; a period with none has no figure
        x = @view sex[name][(lo + 1):(hi + 1)]
        return sex_share(sum((b * v for (b, v) in zip(births, x) if b > 0); init=0.0), sum(births))
    end
    ends, fertile, children = agents["end_t"], agents["periods_fertile"], agents["children"]
    counted = [i for i in eachindex(ends) if lo <= ends[i] <= hi && fertile[i] >= MIN_FERTILE_PERIODS]
    start = metabolism[1]
    trough_t = argmin(@view population[2:(periods + 1)])
    values = (;
        no_mate=no_mate(lo, hi),
        childless=sex_share(count(i -> children[i] == 0, counted), length(counted)),
        drop=start == 0 ? NaN : (start - metabolism[periods + 1]) / start,
        trough=no_mate(max(1, trough_t - TROUGH_HALF), min(periods, trough_t + TROUGH_HALF)),
        eligible=sex_share(total("eligible"), total("population")),
        fertile=sex_share(total("fertile"), total("population")),
        blocked=1 - sex_share(total("fertile"), total("eligible")),
        no_vision=1 - sex_share(total("fertile_vision"), total("fertile")),
        births=sex_share(total("births"), total("fertile")),
        no_site=sex_share(total("no_site"), total("births")),
        mean_distance=by_births("mean_distance"),
        median_distance=by_births("median_distance"),
        mean_distance_share=by_births("mean_distance_share"),
        median_distance_share=by_births("median_distance_share"),
    )
    traits = (Symbol("$(s)_$(c)_$(e)") => sex["$(s)_$c"][e == "start" ? 1 : periods + 1]
              for (c, _) in SEX_TRAITS for s in ("mean", "sd") for e in ("start", "end"))
    return merge(values, (; traits...))
end

# A table's columns by name, each a vector; `ArgumentError` unless it has `columns`.
function sex_table(path::AbstractString, columns)
    header, M = read_seed_csv(path)
    for c in columns
        c in header || throw(ArgumentError("$path lacks the $c column"))
    end
    return Dict(c => M[:, j] for (j, c) in enumerate(header))
end

"""
    read_sex_world(world, folder) -> SexWorld

A sex study folder read as `world`'s. Its fingerprint's last line names the world and the window
(`sex readings: world=<world> window=(lo, hi)`); a folder whose fingerprint names another world, or none, is refused
(`ArgumentError`). The periods come from its `periods=` line, the planned seeds from its name
(`…-s<first>-<seeds>-p<periods>`). A planned seed is read when whole (see [`sex_seed_done`](@ref)), else counted as
unfinished.
"""
function read_sex_world(world::AbstractString, folder::AbstractString)
    world in SEX_WORLDS || throw(ArgumentError("the world is book, xl or today, not $(repr(world))"))
    isdir(folder) || throw(ArgumentError("$folder is not a folder"))
    path = joinpath(folder, "fingerprint.txt")
    isfile(path) || throw(ArgumentError("$folder has no fingerprint"))
    m = match(r"^sex readings: world=(\S+) window=\((\d+), (\d+)\)[ \t\r]*$"m, read(path, String))
    m === nothing && throw(ArgumentError("$folder is not a sex study folder: its fingerprint names no sex readings"))
    m.captures[1] == world ||
        throw(ArgumentError("$folder is given as $world's, but its fingerprint names the world $(m.captures[1])"))
    window = (parse(Int, m.captures[2]), parse(Int, m.captures[3]))
    periods = folder_periods(folder)
    1 <= window[1] <= window[2] <= periods ||
        throw(ArgumentError("$folder's window $window isn't within t = 1 to $periods"))
    name = basename(rstrip(folder, ['/', '\\']))
    n = match(r"-s(\d+)-(\d+)-p\d+$", name)
    n === nothing && throw(ArgumentError("$folder doesn't name its seeds (-s<first>-<seeds>-p<periods>)"))
    first_seed, planned = parse(Int, n.captures[1]), parse(Int, n.captures[2])
    seeds, unfinished = SexSeed[], Int[]
    for k in first_seed:(first_seed + planned - 1)
        if !sex_seed_done(folder, k, periods)
            push!(unfinished, k)
            continue
        end
        std = sex_table(joinpath(folder, "seed$k.csv"), ("population", "mean_metabolism"))
        sex = sex_table(sex_path(folder, k, "sex"), SEX_COLUMNS)
        agents = sex_table(sex_path(folder, k, "agents"), SEX_AGENT_COLUMNS)
        pop = std["population"]
        gone = findfirst(==(0), @view pop[2:end])
        values = sex_values(pop, std["mean_metabolism"], sex, agents, window, periods)
        gone === nothing || (values = map(_ -> NaN, values))
        push!(seeds, SexSeed(k, gone, values))
    end
    return SexWorld(world, String(folder), planned, periods, window, unfinished, seeds)
end

"""The seeds of `w` in value `key`, and those left out of it (extinct or a zero denominator), in seed order."""
function seeds_in(w::SexWorld, key::Symbol)
    used = [s for s in w.seeds if isfinite(s.values[key])]
    return [s.values[key] for s in used], [s.seed for s in w.seeds if !isfinite(s.values[key])]
end

"""The mean over seeds of value `key` in `w`, NaN for none."""
world_mean(w::SexWorld, key::Symbol) = (v = first(seeds_in(w, key)); isempty(v) ? NaN : mean_of(v))

"""
    sex_ratio(run, base, key; factor=M_FACTOR) -> (; ratio, lo, hi, n_run, n_base, result)

Value `key` of world `run` over that of `base`: the ratio of their means over seeds, with
[`bootstrap_ratio_apart`](@ref)'s interval. `result` is `:missing` with fewer than [`MIN_SEEDS`](@ref) seeds on either
side or a ratio or interval that isn't finite, `:holds` when the ratio is at least `factor` and the interval's lower end
above 1, else `:fails`.
"""
function sex_ratio(run::SexWorld, base::SexWorld, key::Symbol; factor::Real=M_FACTOR)
    a, b = first(seeds_in(run, key)), first(seeds_in(base, key))
    r = bootstrap_ratio_apart(a, b)
    missing_ = min(length(a), length(b)) < MIN_SEEDS || !isfinite(r.ratio) || !isfinite(r.lo)
    result = missing_ ? :missing : settle(r.ratio) >= factor && settle(r.lo) > 1 ? :holds : :fails
    return (; r.ratio, r.lo, r.hi, n_run=length(a), n_base=length(b), result)
end

"""
    sex_bars(book, xl, today) -> NamedTuple

The bars of the three worlds ([`read_sex_world`](@ref)):

- `m1`, `m2`: today ÷ book of the no-mate and childless shares ([`sex_ratio`](@ref)); `m`: `:fails` when either fails
  (a missing bar decides nothing, so one failure settles M), else `:missing` when either reads missing, else `:holds`;
- `m1_xl`, `m1_today_xl`, `m2_xl`, `m2_today_xl`: xl ÷ book and today ÷ xl, shown; `trough`: today ÷ book of the trough
  no-mate share, shown;
- `s`: today ÷ book of the mean metabolism drops, with `book_drop` the book's mean; `result` is `:missing` with fewer
  than [`MIN_SEEDS`](@ref) seeds on either side, `:not_judged` when the book's mean drop is under
  [`S_MIN_BOOK_DROP`](@ref), else `:holds` when the ratio is at least [`S_SHARE`](@ref) and `:fails` otherwise. The
  interval is shown and decides nothing.
"""
function sex_bars(book::SexWorld, xl::SexWorld, today::SexWorld)
    m1, m2 = sex_ratio(today, book, :no_mate), sex_ratio(today, book, :childless)
    m = (m1.result == :fails || m2.result == :fails) ? :fails :
        (m1.result == :missing || m2.result == :missing) ? :missing : :holds
    a, b = first(seeds_in(today, :drop)), first(seeds_in(book, :drop))
    r = bootstrap_ratio_apart(a, b)
    book_drop = isempty(b) ? NaN : mean_of(b)
    s_result = min(length(a), length(b)) < MIN_SEEDS ? :missing :
               settle(book_drop) < S_MIN_BOOK_DROP ? :not_judged :
               settle(r.ratio) >= S_SHARE ? :holds : :fails
    s = (; r.ratio, r.lo, r.hi, n_run=length(a), n_base=length(b), book_drop, result=s_result)
    return (;
        m1, m2, m, s,
        m1_xl=sex_ratio(xl, book, :no_mate), m1_today_xl=sex_ratio(today, xl, :no_mate),
        m2_xl=sex_ratio(xl, book, :childless), m2_today_xl=sex_ratio(today, xl, :childless),
        trough=sex_ratio(today, book, :trough),
    )
end

"""
    sex_outcome(m, s) -> Symbol

The outcome by the spec's rules, in order: S fails or reads missing, `:report` (to the user, no rule); M reads missing,
`:no_outcome`; M holds, `:rule` (a rule spec goes to the user); else `:works` (sex works as intended).
"""
function sex_outcome(m::Symbol, s::Symbol)
    s in (:fails, :missing) && return :report
    m == :missing && return :no_outcome
    m == :holds && return :rule
    return :works
end

const SEX_OUTCOME_TEXT = Dict(
    :report => "**S fails or reads missing: report to the user with the readings.** No rule is proposed until we've " *
               "talked.",
    :no_outcome => "**M reads missing: no outcome is drawn.** It is reported to the user.",
    :rule => "**M holds and S doesn't fail: mate finding is a problem in xxl.** The readings with a mate within " *
             "vision say whether a search of the whole shape would be enough, or whether agents need to move toward " *
             "mates; that choice goes to the user with a rule spec.",
    :works => "**M doesn't hold and S doesn't fail: sex works as intended in xxl.** It is written up in docs/xxl.md as " *
              "\"Stage 6: sex\" and the stage stops.",
)

const SEX_RESULT_TEXT = Dict(:holds => "holds", :fails => "doesn't hold", :missing => "missing",
                             :not_judged => "not judged")

# A list of seeds, or "none".
seed_list(v) = isempty(v) ? "none" : join(v, ", ")

# A cell of the seeds a value uses in a world: "18 of 20 (left out: 81, 85)".
function seeds_cell(w::SexWorld, key::Symbol)
    used, out = seeds_in(w, key)
    out = sort!([out; w.unfinished])
    return "$(length(used)) of $(w.planned)" * (isempty(out) ? "" : " (left out: $(join(out, ", ")))")
end

"""
`x` (settled) against `bar` for a bar's row: four significant figures, and more while the rounded figure would fall on
the other side of `bar` (at least it, or above it when `strict`) than `x` does; `—` if it is not finite.
"""
function bar_figure(x::Real, bar::Real; strict::Bool=false)
    isfinite(x) || return "—"
    x = settle(x)
    meets(y) = strict ? y > bar : y >= bar
    d = 4
    while d < SETTLE_DIGITS && meets(round(x; sigdigits=d)) != meets(x)
        d += 1
    end
    y = round(x; sigdigits=d)
    return isinteger(y) && abs(y) < 1e15 ? string(Int(y)) : string(y)
end

# A bar's row: its value against `factor`, its interval (the lower end against 1 when `lo_bar`), the bar, the seeds
# today ÷ book and its result.
function bar_row(name, b, factor, bar_text; result=SEX_RESULT_TEXT[b.result], lo_bar::Bool=true)
    interval = isfinite(b.lo) && isfinite(b.hi) ?
               "[$(lo_bar ? bar_figure(b.lo, 1; strict=true) : fmt(b.lo)), $(fmt(b.hi))]" : "—"
    return row_text([name, bar_figure(b.ratio, factor), interval, bar_text, "$(b.n_run) / $(b.n_base)", result])
end

# A shown ratio's row: no bar, no result.
shown_row(name, b) = row_text([name, finite_text(b.ratio), interval_text(b.lo, b.hi), "shown", "$(b.n_run) / $(b.n_base)",
                               "—"])

"""
    sex_report_text(book, xl, today) -> String

The report as markdown: each world's folder, seeds used and left out, the bars (value, interval, bar, result), the
readings and the outcome.
"""
function sex_report_text(book::SexWorld, xl::SexWorld, today::SexWorld)
    worlds = (book, xl, today)
    bars = sex_bars(book, xl, today)
    outcome = sex_outcome(bars.m, bars.s.result)
    lines = ["# Sex, Part 1", "", SEX_OUTCOME_TEXT[outcome], ""]
    push!(lines, "The book's world has its own density and look, so \"$(M_FACTOR)× the book's\" compares unlike worlds; " *
                 "xl is shown beside it to say how much is world size and how much is xxl's rules.", "")

    push!(lines, "## Worlds", "", row_text(["World", "Folder", "Seeds whole", "Not run", "Extinct", "Window"]),
          "|---|---|---|---|---|---|")
    for w in worlds
        extinct = [s.seed for s in w.seeds if s.extinct !== nothing]
        push!(lines, row_text([w.world, w.folder, "$(length(w.seeds)) of $(w.planned)", seed_list(w.unfinished),
                               seed_list(extinct), period_text(w.window...)]))
    end
    push!(lines, "", "A seed that reached population 0 is left out of every value; a seed with a zero denominator " *
                     "(no fertile agent-period, no snapshot agent fertile for $MIN_FERTILE_PERIODS periods) is left " *
                     "out of that value. A world with fewer than $MIN_SEEDS seeds in a value reads its bar as missing.",
          "", row_text(["Seeds used", "book", "xl", "today"]), "|---|---|---|---|")
    for (key, name) in SEX_BAR_VALUES
        push!(lines, row_text([name; [seeds_cell(w, key) for w in worlds]]))
    end

    push!(lines, "", "## Bars", "",
          "Ratios of the means over seeds, today ÷ book unless named; 95% interval from $(thousands(BOOT_REPS)) bootstrap " *
          "resamples of each world's seeds apart (random seed $BOOT_SEED). A ratio that isn't finite, such as one over a " *
          "book mean of 0, reads missing.", "",
          row_text(["Bar", "Value", "Interval", "Bar", "Seeds", "Result"]), "|---|---|---|---|---|---|")
    m_bar = "at least $M_FACTOR, interval above 1"
    s_result = bars.s.result == :not_judged ?
               "not judged (the book's mean drop $(finite_text(bars.s.book_drop)) is under $S_MIN_BOOK_DROP)" :
               SEX_RESULT_TEXT[bars.s.result]
    push!(lines,
          bar_row("M1", bars.m1, M_FACTOR, m_bar),
          shown_row("M1, xl ÷ book", bars.m1_xl), shown_row("M1, today ÷ xl", bars.m1_today_xl),
          bar_row("M2", bars.m2, M_FACTOR, m_bar),
          shown_row("M2, xl ÷ book", bars.m2_xl), shown_row("M2, today ÷ xl", bars.m2_today_xl),
          row_text(["M", "—", "—", "M1 and M2 both hold", "—", SEX_RESULT_TEXT[bars.m]]),
          shown_row("M1 at the trough", bars.trough),
          bar_row("S", bars.s, S_SHARE, "at least $S_SHARE (the point value)"; result=s_result, lo_bar=false))

    push!(lines, "", "## Readings", "",
          "Means over seeds of each seed's totals in the window; a drop and the traits over the whole run. Fertile " *
          "share is fertile ÷ population; the wealth-blocked share is 1 − fertile ÷ eligible. The parent distances " *
          "are the period means and medians weighted by births.", "",
          row_text(["Reading", "book", "xl", "today"]), "|---|---|---|---|")
    for (key, name) in (SEX_BAR_VALUES..., SEX_READINGS...)
        push!(lines, row_text([name; [finite_text(world_mean(w, key)) for w in worlds]]))
    end
    for (c, name) in SEX_TRAITS, s in ("mean", "sd"), e in ("start", "end")
        key = Symbol("$(s)_$(c)_$(e)")
        push!(lines, row_text(["$(s == "mean" ? "Mean" : "Sd") $name, $e"; [finite_text(world_mean(w, key)) for w in worlds]]))
    end
    push!(lines, "", "## Outcome", "", SEX_OUTCOME_TEXT[outcome])
    return join(lines, "\n") * "\n"
end

"""
    sex_report(; book, xl, today, md, io=stdout) -> String

Reads the three worlds' study folders ([`read_sex_world`](@ref)), refusing one whose fingerprint names another world
(`ArgumentError`), writes [`sex_report_text`](@ref)'s markdown to `md` and prints it to `io` with where it went.
"""
function sex_report(; book::AbstractString, xl::AbstractString, today::AbstractString, md::AbstractString, io::IO=stdout)
    worlds = (read_sex_world("book", book), read_sex_world("xl", xl), read_sex_world("today", today))
    text = sex_report_text(worlds...)
    isempty(dirname(md)) || mkpath(dirname(md))
    write_atomic(md, text)
    println(io, text, "-> ", md)
    return text
end

const SEX_REPORT_USAGE =
    "usage: julia --project=julia julia/xxl_sex_report.jl --book DIR --xl DIR --today DIR [--md PATH]"

"""
The report's command line: `--book`, `--xl` and `--today` (each a study folder, required) and `--md` (default
`results-julia-xxl/sex-part1.md`). Returns `(; book, xl, today, md)`; throws `ArgumentError` on a usage error.
"""
function sex_report_args(args::Vector{String})
    given = Dict{String,String}()
    i = 1
    while i <= length(args)
        a = args[i]
        a in ("--book", "--xl", "--today", "--md") || throw(ArgumentError("unexpected argument $a"))
        i += 1
        i <= length(args) || throw(ArgumentError("$a needs a value"))
        haskey(given, a[3:end]) && throw(ArgumentError("$a is given twice"))
        given[a[3:end]] = args[i]
        i += 1
    end
    for k in ("book", "xl", "today")
        haskey(given, k) || throw(ArgumentError("--$k is needed"))
    end
    return (; book=given["book"], xl=given["xl"], today=given["today"],
            md=get(given, "md", joinpath(RESULTS_XXL, "sex-part1.md")))
end

"""
    sex_report_main(args) -> exit code

The command line of julia/xxl_sex_report.jl: runs [`sex_report`](@ref). Returns 2 after printing the usage on a usage
error or a folder that is missing or refused, before anything is written; anything else is thrown.
"""
function sex_report_main(args::Vector{String})
    try
        a = sex_report_args(args)
        sex_report(; a.book, a.xl, a.today, a.md)
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, SEX_REPORT_USAGE, "\n", e.msg)
        return 2
    end
    return 0
end
