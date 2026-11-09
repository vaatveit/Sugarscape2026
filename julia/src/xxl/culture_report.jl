# xxl (stage 7): the culture report (docs/superpowers/specs/2026-11-07-xxl-culture-design.md, "Part 1's bars"). Reads
# the three worlds' finished study folders (julia/src/xxl/culture_study.jl's), checks each world's standard CSVs against
# stage 6's for drift, applies bars W and F, and writes the readings and the outcome by the spec's rules
# (julia/xxl_culture_report.jl is its command line). It reads only finished seeds and runs nothing.
#
# Every per-seed value is the mean, over a window's periods (or its tenth periods, for patch polarization), of the
# per-period values where they are defined; a period where one is undefined (NaN: no neighbour pairs, no pair still alive,
# no patch of CULTURE_PATCH_MIN agents) is skipped and counted. A seed with no defined period is missing for that value
# only. A seed whose last population is 0 is left out of every value and counted.

const W_SHARE = 0.5  # W1 and W2: today ÷ book under this, with the interval's upper end under 1
const F_MIN_SHARE = 0.05  # F: each tribe holds at least this share of a seed's population at the last period
const F_MIN_SEEDS_SHARE = 0.8  # F: in at least this share of today's seeds

"""The windows the readings are also shown for, beside the decision window (those within the run)."""
const CULTURE_READING_WINDOWS = ((51, 100), (101, 200), (201, 300))

"""The bar values, with their names in the report."""
const CULTURE_BAR_VALUES = (
    (:w1, "Neighbour closeness − 0.5 (W1)"),
    (:w2, "Patch polarization (W2)"),
)

"""The readings, shown and deciding nothing: the culture table's columns, then the standard CSV's."""
const CULTURE_READINGS = (
    (:blue_share, "Blue share"),
    (:tag_flips_per_agent, "Tag flips per agent"),
    (:chance_closeness, "Chance closeness"),
    (:neighbours_per_agent, "Neighbours per agent"),
    (:share_no_neighbours, "Share with no neighbours"),
    (:persistence, "Neighbour-pair persistence"),
    (:mean_moved, "Distance moved"),
    (:mean_speed, "Speed"),
    (:friend_closeness, "Friend closeness"),
    (:best_friend_closeness, "Best-friend closeness"),
)

const CULTURE_STANDARD_READINGS = (:friend_closeness, :best_friend_closeness)

"""
    CultureSeed(seed, extinct, windows, position_polarization, last_blue, min_flips)

One whole seed of a culture study folder: the first period its population is 0 (`nothing` unless its last population is
0), its values in each window (`windows[(lo, hi)].w1` is a `(; value, skipped, periods)`), the mean `|2 zᵢ − 1|` over its
tag positions at the last period, its blue share at the last period and its fewest tag flips per agent in the decision
window (NaN if one of them is undefined).
"""
struct CultureSeed
    seed::Int
    extinct::Union{Nothing,Int}
    windows::Dict{Tuple{Int,Int},NamedTuple}
    position_polarization::Float64
    last_blue::Float64
    min_flips::Float64
end

"""
    CultureWorld(world, folder, first_seed, planned, periods, window, windows, unfinished, seeds)

A world's study folder read for the report: the seeds its name plans, its periods, the decision window its fingerprint
names, the windows its readings are shown for, the planned seeds that aren't whole and the whole ones.
"""
struct CultureWorld
    world::String
    folder::String
    first_seed::Int
    planned::Int
    periods::Int
    window::Tuple{Int,Int}
    windows::Vector{Tuple{Int,Int}}
    unfinished::Vector{Int}
    seeds::Vector{CultureSeed}
end

"""The mean of `x` (by `[t + 1]`) over periods `ts` where it is finite, with the periods skipped and counted."""
function window_value(x::AbstractVector{Float64}, ts)
    total = skipped = 0
    s = 0.0
    for t in ts
        total += 1
        v = x[t + 1]
        if isfinite(v)
            s += v
        else
            skipped += 1
        end
    end
    used = total - skipped
    return (; value=used == 0 ? NaN : s / used, skipped, periods=total)
end

"""
    culture_values(std, culture, patches, window) -> NamedTuple

A seed's values in `window`: `std` and `culture` its standard CSV's and culture table's columns by name, `patches` its
patch table (rows in [`CULTURE_PATCH_COLUMNS`](@ref)'s order). `w1` is `neighbour_closeness` − 0.5; `w2` the
[`patch_polarization`](@ref) of the window's tenth periods; then each of [`CULTURE_READINGS`](@ref). Each is a
[`window_value`](@ref).
"""
function culture_values(std::Dict{String,Vector{Float64}}, culture::Dict{String,Vector{Float64}},
                        patches::AbstractMatrix{Float64}, window::Tuple{Int,Int})
    lo, hi = window
    ts = lo:hi
    tenths = [t for t in ts if t % CULTURE_PATCH_EVERY == 0]
    polarization = fill(NaN, maximum(ts) + 1)
    for t in tenths
        polarization[t + 1] = patch_polarization(eachrow(@view patches[patches[:, 1] .== t, :]))
    end
    readings = (key => window_value(key in CULTURE_STANDARD_READINGS ? std[String(key)] : culture[String(key)], ts)
                for (key, _) in CULTURE_READINGS)
    return (; w1=window_value(culture["neighbour_closeness"] .- 0.5, ts), w2=window_value(polarization, tenths),
            readings...)
end

# A table's columns by name, each a vector; `ArgumentError` unless it has `columns`.
function named_table(path::AbstractString, columns)
    header, M = read_seed_csv(path)
    for c in columns
        c in header || throw(ArgumentError("$path lacks the $c column"))
    end
    return Dict(c => M[:, j] for (j, c) in enumerate(header)), M
end

"""The first seed and the seeds planned that a study folder's name gives (`…-s<first>-<seeds>-p<periods>`)."""
function study_folder_seeds(folder::AbstractString)
    name = basename(rstrip(folder, ['/', '\\']))
    n = match(r"-s(\d+)-(\d+)-p\d+$", name)
    n === nothing && throw(ArgumentError("$folder doesn't name its seeds (-s<first>-<seeds>-p<periods>)"))
    return parse(Int, n.captures[1]), parse(Int, n.captures[2])
end

"""The first period from t = 1 at which a population (by `[t + 1]`) is 0, when its last is 0; else `nothing`."""
seed_extinct(pop::AbstractVector, periods::Int) =
    pop[end] == 0 ? something(findfirst(==(0), @view pop[2:end]), periods) : nothing

"""The world a folder's fingerprint names in its last readings line (`<kind> readings: world=<world> …`), or `nothing`."""
function readings_world(folder::AbstractString)
    path = joinpath(folder, "fingerprint.txt")
    isfile(path) || return nothing
    m = match(r"^\S+ readings: world=(\S+)"m, read(path, String))
    return m === nothing ? nothing : String(m.captures[1])
end

"""
    read_culture_world(world, folder) -> CultureWorld

A culture study folder read as `world`'s. Its fingerprint's last line names the world and the window
(`culture readings: world=<world> window=(lo, hi)`); a folder whose fingerprint names another world, or none, is refused
(`ArgumentError`). The periods come from its `periods=` line, the planned seeds from its name
(`…-s<first>-<seeds>-p<periods>`). A planned seed is read when whole (see [`culture_seed_done`](@ref)), else counted as
unfinished.
"""
function read_culture_world(world::AbstractString, folder::AbstractString)
    world in CULTURE_WORLDS || throw(ArgumentError("the world is book, xl or today, not $(repr(world))"))
    isdir(folder) || throw(ArgumentError("$folder is not a folder"))
    path = joinpath(folder, "fingerprint.txt")
    isfile(path) || throw(ArgumentError("$folder has no fingerprint"))
    m = match(r"^culture readings: world=(\S+) window=\((\d+), (\d+)\)[ \t\r]*$"m, read(path, String))
    m === nothing &&
        throw(ArgumentError("$folder is not a culture study folder: its fingerprint names no culture readings"))
    m.captures[1] == world ||
        throw(ArgumentError("$folder is given as $world's, but its fingerprint names the world $(m.captures[1])"))
    window = (parse(Int, m.captures[2]), parse(Int, m.captures[3]))
    periods = folder_periods(folder)
    1 <= window[1] <= window[2] <= periods ||
        throw(ArgumentError("$folder's window $window isn't within t = 1 to $periods"))
    first_seed, planned = study_folder_seeds(folder)
    windows = unique!([[w for w in CULTURE_READING_WINDOWS if w[2] <= periods]; [window]])
    seeds, unfinished = CultureSeed[], Int[]
    for k in first_seed:(first_seed + planned - 1)
        if !culture_seed_done(folder, k, periods)
            push!(unfinished, k)
            continue
        end
        std, _ = named_table(joinpath(folder, "seed$k.csv"),
                             ("population", (String(c) for c in CULTURE_STANDARD_READINGS)...))
        culture, _ = named_table(culture_path(folder, k, "culture"), CULTURE_COLUMNS)
        pheader, patches = read_seed_csv(culture_path(folder, k, "patches"))
        pheader == CULTURE_PATCH_COLUMNS ||
            throw(ArgumentError("$(culture_path(folder, k, "patches"))'s columns aren't $(join(CULTURE_PATCH_COLUMNS, ","))"))
        extinct = seed_extinct(std["population"], periods)
        values = Dict(w => culture_values(std, culture, patches, w) for w in windows)
        zs = filter(!isnan, [culture["zero_share_$i"][periods + 1] for i in 1:CULTURE_ZERO_POSITIONS])
        position = isempty(zs) ? NaN : mean_of(abs.(2 .* zs .- 1))
        flips = @view culture["tag_flips_per_agent"][(window[1] + 1):(window[2] + 1)]
        min_flips = any(isnan, flips) ? NaN : minimum(flips)
        push!(seeds, CultureSeed(k, extinct, values, position, culture["blue_share"][periods + 1], min_flips))
    end
    return CultureWorld(world, String(folder), first_seed, planned, periods, window, windows, unfinished, seeds)
end

"""
    culture_used(w, window, key) -> (; values, out, skipped, periods)

Value `key` of `w` in `window` over its seeds: the values of the seeds it is defined for, the seeds left out (extinct,
missing for it, or unfinished, in seed order), and the seed-periods skipped of those counted over the seeds not extinct.
`key` `:position` is the position polarization at the last period, one seed-period a seed.
"""
function culture_used(w::CultureWorld, window::Tuple{Int,Int}, key::Symbol)
    return seeds_used(w.seeds, w.unfinished) do s
        key == :position ? (; value=s.position_polarization, skipped=Int(isnan(s.position_polarization)), periods=1) :
        s.windows[window][key]
    end
end

"""
    seeds_used(value_of, seeds, unfinished; drop_extinct=true) -> (; values, out, skipped, periods)

A value over a study folder's whole `seeds` (each with `.seed` and `.extinct`), `value_of(s)` giving a seed's
[`window_value`](@ref)-like `(; value, skipped, periods)`: the values of the seeds it is defined for, the seeds left out
(extinct when `drop_extinct`, missing for it, or `unfinished`, in seed order), and the seed-periods skipped of those
counted over the seeds not left out as extinct.
"""
function seeds_used(value_of, seeds, unfinished; drop_extinct::Bool=true)
    values, out = Float64[], collect(Int, unfinished)
    skipped = periods = 0
    for s in seeds
        if drop_extinct && s.extinct !== nothing
            push!(out, s.seed)
            continue
        end
        v = value_of(s)
        skipped += v.skipped
        periods += v.periods
        isfinite(v.value) ? push!(values, v.value) : push!(out, s.seed)
    end
    return (; values, out=sort!(out), skipped, periods)
end

"""The mean over seeds of value `key` of `w` in `window`, NaN for none."""
culture_mean(w::CultureWorld, window, key::Symbol) = (v = culture_used(w, window, key).values; isempty(v) ? NaN : mean_of(v))

"""
    culture_ratio(run, base, key) -> (; ratio, lo, hi, n_run, n_base, result)

Value `key` of world `run` over that of `base` in the decision window: the ratio of their means over seeds, with
[`bootstrap_ratio_apart`](@ref)'s interval. `result` is `:missing` with fewer than [`MIN_SEEDS`](@ref) seeds on either
side or a ratio or upper end that isn't finite, `:holds` when the ratio is under [`W_SHARE`](@ref) and the interval's
upper end under 1, else `:fails`.
"""
function culture_ratio(run::CultureWorld, base::CultureWorld, key::Symbol)
    return ratio_bar(culture_used(run, run.window, key).values, culture_used(base, base.window, key).values)
end

"""
    ratio_bar(a, b) -> (; ratio, lo, hi, n_run, n_base, result)

A W bar on the seed values `a` (the world judged) over `b` (the reference): the ratio of their means with
[`bootstrap_ratio_apart`](@ref)'s interval. `result` is `:missing` with fewer than [`MIN_SEEDS`](@ref) seeds on either
side or a ratio or upper end that isn't finite, `:holds` when the ratio is under [`W_SHARE`](@ref) and the interval's
upper end under 1, else `:fails`.
"""
function ratio_bar(a::Vector{Float64}, b::Vector{Float64})
    r = bootstrap_ratio_apart(a, b)
    missing_ = min(length(a), length(b)) < MIN_SEEDS || !isfinite(r.ratio) || !isfinite(r.hi)
    return (; r.ratio, r.lo, r.hi, n_run=length(a), n_base=length(b), result=w_result(missing_, r.ratio, r.hi))
end

# A W bar's result: missing, else whether the value is under W_SHARE and the interval's upper end under 1.
w_result(missing_::Bool, value, hi) = missing_ ? :missing : settle(value) < W_SHARE && settle(hi) < 1 ? :holds : :fails

"""
Two W bars' results as W: `:fails` when either fails (a missing bar decides nothing, so one failure settles W), else
`:missing` when either reads missing, else `:holds`.
"""
both_bars(a::Symbol, b::Symbol) = (a == :fails || b == :fails) ? :fails : (a == :missing || b == :missing) ? :missing :
                                  :holds

"""
    culture_f(today) -> (; share, both, no_flips, planned, seeds, result)

Bar F over every planned seed of today's folder, an extinct or unfinished one failing both parts: `both` the seeds whose
blue share at the last period is within [`F_MIN_SHARE`](@ref) of 0 and 1 and `share` that over the planned seeds;
`no_flips` the seeds whose fewest tag flips per agent in the decision window aren't above 0; `seeds` the whole ones.
`result` is `:missing` with fewer than [`MIN_SEEDS`](@ref) whole seeds, `:holds` when `share` is at least
[`F_MIN_SEEDS_SHARE`](@ref) and `no_flips` is empty, else `:fails`.
"""
function culture_f(today::CultureWorld)
    whole = Dict(s.seed => s for s in today.seeds)
    both = 0
    no_flips = Int[]
    for k in today.first_seed:(today.first_seed + today.planned - 1)
        s = get(whole, k, nothing)
        if s === nothing || s.extinct !== nothing
            push!(no_flips, k)
            continue
        end
        b = settle(s.last_blue)
        both += F_MIN_SHARE <= b <= 1 - F_MIN_SHARE
        settle(s.min_flips) > 0 || push!(no_flips, k)
    end
    share = today.planned == 0 ? NaN : both / today.planned
    result = length(today.seeds) < MIN_SEEDS ? :missing :
             settle(share) >= F_MIN_SEEDS_SHARE && isempty(no_flips) ? :holds : :fails
    return (; share, both, no_flips, today.planned, seeds=length(today.seeds), result)
end

"""
    culture_drift(folder, ref; prefix=false) -> (; matched, differ, absent)

For each seed with a `seed<k>.csv` in `folder`, whether it equals `ref`'s byte for byte (with `prefix`, whether its lines
equal `ref`'s first lines, for a dry run's shorter files). `absent` lists the seeds with no file in `ref`. Each in seed
order.
"""
function culture_drift(folder::AbstractString, ref::AbstractString; prefix::Bool=false)
    seeds = sort!([parse(Int, m.captures[1]) for m in (match(r"^seed(\d+)\.csv$", f) for f in readdir(folder))
                   if m !== nothing])
    matched, differ, absent = Int[], Int[], Int[]
    for k in seeds
        mine, theirs = joinpath(folder, "seed$k.csv"), joinpath(ref, "seed$k.csv")
        if !isfile(theirs)
            push!(absent, k)
            continue
        end
        same = if prefix
            a, b = readlines(mine; keep=true), readlines(theirs; keep=true)
            length(a) <= length(b) && a == b[1:length(a)]
        else
            read(mine) == read(theirs)
        end
        push!(same ? matched : differ, k)
    end
    return (; matched, differ, absent)
end

"""
    culture_bars(book, xl, today; refs) -> NamedTuple

The bars of the three worlds ([`read_culture_world`](@ref)), with `refs` their stage-6 folders (book, xl, today):

- `w1`, `w2`: today ÷ book of neighbour closeness above chance and of patch polarization ([`culture_ratio`](@ref));
  `w`: `:fails` when either fails (a missing bar decides nothing, so one failure settles W), else `:missing` when
  either reads missing, else `:holds`;
- `w1_xl`, `w1_today_xl`, `w2_xl`, `w2_today_xl`: xl ÷ book and today ÷ xl, shown;
- `f`: [`culture_f`](@ref) of today;
- `drift`: [`culture_drift`](@ref) of each world against its reference, and `drift_ok` whether no seed differs or is
  absent from it.
"""
function culture_bars(book::CultureWorld, xl::CultureWorld, today::CultureWorld; refs)
    w1, w2 = culture_ratio(today, book, :w1), culture_ratio(today, book, :w2)
    w = both_bars(w1.result, w2.result)
    drift = Tuple(culture_drift(wd.folder, r) for (wd, r) in zip((book, xl, today), refs))
    drift_ok = all(d -> isempty(d.differ) && isempty(d.absent), drift)
    return (;
        w1, w2, w,
        w1_xl=culture_ratio(xl, book, :w1), w1_today_xl=culture_ratio(today, xl, :w1),
        w2_xl=culture_ratio(xl, book, :w2), w2_today_xl=culture_ratio(today, xl, :w2),
        f=culture_f(today), drift, drift_ok,
    )
end

"""
    bar_outcome(drift_ok, w, f) -> Symbol

The outcome by the culture and combat specs' rules, in order: the drift check fails, `:drift` (stop and report to the
user); F fails or reads missing, `:report` (to the user, no rule); W reads missing, `:no_outcome`; W holds, `:weak` (the
readings go to the user with a rule spec); else `:works` (it works as intended). `culture_outcome` is this.
"""
function bar_outcome(drift_ok::Bool, w::Symbol, f::Symbol)
    drift_ok || return :drift
    f in (:fails, :missing) && return :report
    w == :missing && return :no_outcome
    w == :holds && return :weak
    return :works
end

const culture_outcome = bar_outcome

const CULTURE_OUTCOME_TEXT = Dict(
    :drift => "**The drift check fails: the runs differ from stage 6's: stop and report to the user.** No bar is read " *
              "until we've talked.",
    :report => "**F fails or reads missing: report to the user with the readings.** No rule is proposed until we've " *
               "talked.",
    :no_outcome => "**W reads missing: no outcome is drawn.** It is reported to the user.",
    :weak => "**W holds and F passes: culture is weak in xxl.** The readings go to the user with a rule spec: the " *
             "mixing readings (persistence, distance moved, neighbours per agent, beside xl's and the book's) with what " *
             "they point to, and any rule gets its own spec with the user.",
    :works => "**W doesn't hold and F passes: culture works as intended in xxl.** It is written up in docs/xxl.md as " *
              "\"Stage 7: culture\" and the stage stops.",
)

const BAR_RESULT_TEXT = Dict(:holds => "holds", :fails => "doesn't hold", :missing => "missing")

# A cell of a value in a world: its mean over seeds, the seeds it uses and the share of seed-periods skipped.
culture_cell(w::CultureWorld, window, key::Symbol; mean::Bool=true) =
    used_cell(culture_used(w, window, key), w.planned; mean)

# A cell of a value over a folder's seeds (`u` from `seeds_used`, of `planned` seeds): its mean over the seeds, the seeds
# it uses and the share of seed-periods skipped; without `mean`, the seeds it uses and those left out.
function used_cell(u, planned::Int; mean::Bool=true)
    m = isempty(u.values) ? NaN : mean_of(u.values)
    skipped = u.periods == 0 ? "—" : fmt(100 * u.skipped / u.periods) * "%"
    used = "$(length(u.values)) of $planned, $skipped skipped"
    return mean ? "$(finite_text(m)) ($used)" : used * (isempty(u.out) ? "" : " (left out: $(join(u.out, ", ")))")
end

# A W bar's row: its value against W_SHARE, its interval (the upper end against 1), the bar (and `note`), the seeds and
# its result.
function w_row(name, b; seeds="$(b.n_run) / $(b.n_base)", note="")
    interval = isfinite(b.lo) && isfinite(b.hi) ? "[$(fmt(b.lo)), $(bar_figure(b.hi, 1))]" : "—"
    return row_text([name, bar_figure(b.ratio, W_SHARE), interval, "under $W_SHARE, interval's upper end under 1" * note,
                     seeds, BAR_RESULT_TEXT[b.result]])
end

"""
    culture_report_text(book, xl, today; refs) -> String

The report as markdown: each world's folder, seeds used and left out, the drift check per world, the bars (value,
interval, bar, result), the readings per window and the outcome.
"""
function culture_report_text(book::CultureWorld, xl::CultureWorld, today::CultureWorld; refs)
    worlds = (book, xl, today)
    bars = culture_bars(book, xl, today; refs)
    outcome = culture_outcome(bars.drift_ok, bars.w, bars.f.result)
    window = today.window
    lines = ["# Culture, Part 1", "", CULTURE_OUTCOME_TEXT[outcome], ""]
    push!(lines, "The book's world has its own density and neighbourhood (4 sites against xxl's 8 within 1.5), so " *
                 "\"half the book's\" compares unlike worlds; xl is shown beside it to say how much is world size and how " *
                 "much is xxl's rules. A $(CULTURE_PATCH) × $(CULTURE_PATCH) patch of a bigger world isn't closed as the " *
                 "book's world is: agents come and go across its edges, which is part of what W2 measures.", "")

    push!(lines, "## Worlds", "", row_text(["World", "Folder", "Seeds whole", "Not run", "Extinct", "Window"]),
          "|---|---|---|---|---|---|")
    for w in worlds
        extinct = [s.seed for s in w.seeds if s.extinct !== nothing]
        push!(lines, row_text([w.world, w.folder, "$(length(w.seeds)) of $(w.planned)", seed_list(w.unfinished),
                               seed_list(extinct), period_text(w.window...)]))
    end
    push!(lines, "", "A seed whose last population is 0 is left out of every value. A period where a value is " *
                     "undefined (no neighbour pairs; no patch of $CULTURE_PATCH_MIN agents) is skipped in the seed's " *
                     "window mean, and a seed with no defined period is left out of that value. A world with fewer " *
                     "than $MIN_SEEDS seeds in a value reads its bar as missing.", "",
          row_text(["Seeds used, $(period_text(window...))", "book", "xl", "today"]), "|---|---|---|---|")
    for (key, name) in CULTURE_BAR_VALUES
        push!(lines, row_text([name; [culture_cell(w, w.window, key; mean=false) for w in worlds]]))
    end

    push!(lines, "", "## Drift check", "",
          "Each seed's standard CSV against stage 6's for the same world and seed, the full files byte for byte.", "",
          row_text(["World", "Reference", "Matched", "Differ", "Absent from the reference", "Result"]),
          "|---|---|---|---|---|---|")
    for (w, r, d) in zip(worlds, refs, bars.drift)
        ok = isempty(d.differ) && isempty(d.absent)
        push!(lines, row_text([w.world, r, length(d.matched), seed_list(d.differ), seed_list(d.absent),
                               ok ? "passes" : "fails"]))
    end

    push!(lines, "", "## Bars", "",
          "Decided at $(period_text(window...)). Ratios of the means over seeds, today ÷ book unless named; 95% interval " *
          "from $(thousands(BOOT_REPS)) bootstrap resamples of each world's seeds apart (random seed $BOOT_SEED). A ratio " *
          "that isn't finite, such as one over a book mean of 0, reads missing.", "",
          row_text(["Bar", "Value", "Interval", "Bar", "Seeds", "Result"]), "|---|---|---|---|---|---|")
    f = bars.f
    push!(lines,
          w_row("W1", bars.w1),
          shown_row("W1, xl ÷ book", bars.w1_xl), shown_row("W1, today ÷ xl", bars.w1_today_xl),
          w_row("W2", bars.w2),
          shown_row("W2, xl ÷ book", bars.w2_xl), shown_row("W2, today ÷ xl", bars.w2_today_xl),
          row_text(["W", "—", "—", "W1 and W2 both hold", "—", BAR_RESULT_TEXT[bars.w]]),
          row_text(["F, both tribes", bar_figure(f.share, F_MIN_SEEDS_SHARE), "—",
                    "both tribes at least $F_MIN_SHARE of the population at t = $(thousands(today.periods)) in at " *
                    "least $F_MIN_SEEDS_SHARE of today's seeds", "$(f.both) of $(f.planned)", "—"]),
          row_text(["F, flips", "$(f.planned - length(f.no_flips)) of $(f.planned)", "—",
                    "every seed's fewest tag flips per agent in a period of $(period_text(window...)) above 0 " *
                    "(not: $(seed_list(f.no_flips)))", "$(f.seeds) whole", "—"]),
          row_text(["F", "—", "—", "both parts, extinct or unfinished seeds failing; missing under $MIN_SEEDS whole " *
                    "seeds", "—", BAR_RESULT_TEXT[f.result]]))

    push!(lines, "", "## Readings", "",
          "Each cell is the mean over seeds of each seed's window mean, then the seeds used and the share of their " *
          "seed-periods skipped. Shown, deciding nothing.")
    for wd in today.windows
        push!(lines, "", "### $(period_text(wd...))", "", row_text(["Reading", "book", "xl", "today"]),
              "|---|---|---|---|")
        for (key, name) in (CULTURE_BAR_VALUES..., CULTURE_READINGS...)
            push!(lines, row_text([name; [wd in w.windows ? culture_cell(w, wd, key) : "—" for w in worlds]]))
        end
    end
    push!(lines, "", "### At the last period", "", row_text(["Reading", "book", "xl", "today"]), "|---|---|---|---|",
          row_text(["Per-position polarization, mean \\|2 zᵢ − 1\\|"; [culture_cell(w, w.window, :position) for w in worlds]]))
    push!(lines, "", "## Outcome", "", CULTURE_OUTCOME_TEXT[outcome])
    return join(lines, "\n") * "\n"
end

"""A stage-6 reference folder for `world`: refused unless it is a folder, or if its fingerprint names another world."""
function check_culture_ref(world::AbstractString, ref::AbstractString)
    isdir(ref) || throw(ArgumentError("$ref is not a folder"))
    named = readings_world(ref)
    named === nothing || named == world ||
        throw(ArgumentError("$ref is given as $world's reference, but its fingerprint names the world $named"))
    return String(ref)
end

"""
    culture_report(; book, xl, today, ref_book, ref_xl, ref_today, md, io=stdout) -> String

Reads the three worlds' study folders ([`read_culture_world`](@ref)), refusing one whose fingerprint names another world,
and their stage-6 references (refusing one whose fingerprint names another world), all before anything is written
(`ArgumentError`); writes [`culture_report_text`](@ref)'s markdown to `md` and prints it to `io` with where it went.
"""
function culture_report(; book::AbstractString, xl::AbstractString, today::AbstractString, ref_book::AbstractString,
                        ref_xl::AbstractString, ref_today::AbstractString, md::AbstractString, io::IO=stdout)
    worlds = (read_culture_world("book", book), read_culture_world("xl", xl), read_culture_world("today", today))
    allequal(w.window for w in worlds) ||
        throw(ArgumentError("the worlds' windows differ: $(join((w.window for w in worlds), ", "))"))
    refs = (check_culture_ref("book", ref_book), check_culture_ref("xl", ref_xl), check_culture_ref("today", ref_today))
    text = culture_report_text(worlds...; refs)
    publish_report(md, text, io)
    return text
end

"""Writes a report's markdown `text` to `md` (making its folder) and prints it to `io` with where it went."""
function publish_report(md::AbstractString, text::AbstractString, io::IO)
    isempty(dirname(md)) || mkpath(dirname(md))
    write_atomic(md, text)
    println(io, text, "-> ", md)
    return nothing
end

const CULTURE_REPORT_USAGE =
    "usage: julia --project=julia julia/xxl_culture_report.jl --book DIR --xl DIR --today DIR --ref-book DIR " *
    "--ref-xl DIR --ref-today DIR [--md PATH]"

const CULTURE_REPORT_FOLDERS = ("book", "xl", "today", "ref-book", "ref-xl", "ref-today")

"""
The report's command line: `--book`, `--xl`, `--today` (each a study folder) and `--ref-book`, `--ref-xl`, `--ref-today`
(each stage 6's folder for that world), all required, and `--md` (default `results-julia-xxl/culture-part1.md`). Returns
`(; book, xl, today, ref_book, ref_xl, ref_today, md)`; throws `ArgumentError` on a usage error.
"""
function culture_report_args(args::Vector{String})
    given = Dict{String,String}()
    i = 1
    while i <= length(args)
        a = args[i]
        (startswith(a, "--") && (a[3:end] in CULTURE_REPORT_FOLDERS || a == "--md")) ||
            throw(ArgumentError("unexpected argument $a"))
        i += 1
        i <= length(args) || throw(ArgumentError("$a needs a value"))
        haskey(given, a[3:end]) && throw(ArgumentError("$a is given twice"))
        given[a[3:end]] = args[i]
        i += 1
    end
    for k in CULTURE_REPORT_FOLDERS
        haskey(given, k) || throw(ArgumentError("--$k is needed"))
    end
    return (; book=given["book"], xl=given["xl"], today=given["today"], ref_book=given["ref-book"],
            ref_xl=given["ref-xl"], ref_today=given["ref-today"],
            md=get(given, "md", joinpath(RESULTS_XXL, "culture-part1.md")))
end

"""
    culture_report_main(args) -> exit code

The command line of julia/xxl_culture_report.jl: runs [`culture_report`](@ref). Returns 2 after printing the usage on a
usage error or a folder that is missing or refused, before anything is written; anything else is thrown.
"""
function culture_report_main(args::Vector{String})
    try
        a = culture_report_args(args)
        culture_report(; a.book, a.xl, a.today, a.ref_book, a.ref_xl, a.ref_today, a.md)
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, CULTURE_REPORT_USAGE, "\n", e.msg)
        return 2
    end
    return 0
end
