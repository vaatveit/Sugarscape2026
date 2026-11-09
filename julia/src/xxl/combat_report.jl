# xxl (stage 8): the combat report (docs/superpowers/specs/2026-11-08-xxl-combat-design.md, "Part 1's bars"). Reads the
# fifteen finished study folders (julia/src/xxl/combat_study.jl's: five experiments in three worlds), checks the book's and
# xl's standard CSVs against the saved runs for drift, applies bars W and F, and writes the readings and the outcome by the
# spec's rules (julia/xxl_combat_report.jl is its command line). It reads only finished seeds and runs nothing.
#
# A seed whose last population is 0 is left out of every ratio value (W1's kills per founder, W2's mixing) and counted. A
# value over a window is the mean of its per-period values where they are defined; a period where one is NaN is skipped,
# and a seed with no defined period is missing for that value only. Bar F counts every expected seed, an unfinished one
# failing it. The bar constants W_SHARE and F_MIN_SHARE are stage 7's (julia/src/xxl/culture_report.jl), the same values.

const F1_SEEDS_SHARE = 0.8  # F1: in at least this share of today's III-11 seeds both tribes hold their ground
const F3_SEEDS_SHARE = 0.5  # F3: in at least this share of today's III-14 seeds both tribes hold F_MIN_SHARE
const HOME_MIN = 0.5  # F1: a tribe holds its ground when its home share over F1_WINDOW is above this
const W2_WINDOW = (101, 200)  # W2: the periods a seed's mixing is the mean over
const F1_WINDOW = (501, 1000)  # F1: the periods of the lasting front
const F1_BLOCK = 100  # F1: every block of this many periods of F1_WINDOW has a kill

const REF_BOOK = "C:/Projects/Sugarscape2026/results-julia"  # the saved runs of the book's world, each in <exp>/
const REF_XL = "C:/Projects/Sugarscape2026/results-julia-xl"  # the saved xl runs, each in <exp>/

"""The windows the readings are shown for (those within the run)."""
const COMBAT_READING_WINDOWS = ((1, 100), (101, 200), (201, 500), (501, 1000))

"""The readings, shown and deciding nothing: the combat table's columns and their names in the report."""
const COMBAT_READINGS = (
    ("killed_blue", "Blue killed per period"),
    ("killed_red", "Red killed per period"),
    ("starved_blue", "Blue starved per period"),
    ("starved_red", "Red starved per period"),
    ("old_age_blue", "Blue dead of age per period"),
    ("old_age_red", "Red dead of age per period"),
    ("population", "Population"),
    ("n_blue", "Blue agents"),
    ("n_red", "Red agents"),
    ("mixing", "Mixing"),
    ("front_share", "Front share"),
    ("home_blue", "Blue home share"),
    ("home_red", "Red home share"),
    ("gini_blue", "Blue Gini"),
    ("gini_red", "Red Gini"),
    ("max_sugar_blue", "Blue largest holding"),
    ("max_sugar_red", "Red largest holding"),
    ("tribe_changes", "Tribe changes per period"),
)

"""
    CombatSeed(seed, extinct, table)

One whole seed of a combat study folder: the first period its population is 0 (`nothing` unless its last population is
0) and its combat table's columns by name (`table["mixing"][t + 1]`).
"""
struct CombatSeed
    seed::Int
    extinct::Union{Nothing,Int}
    table::Dict{String,Vector{Float64}}
end

"""
    CombatWorld(world, exp, folder, first_seed, planned, periods, unfinished, seeds)

A world's study folder of one experiment read for the report: the seeds its name plans, its periods, the planned seeds
that aren't whole and the whole ones.
"""
struct CombatWorld
    world::String
    exp::String
    folder::String
    first_seed::Int
    planned::Int
    periods::Int
    unfinished::Vector{Int}
    seeds::Vector{CombatSeed}
end

planned_seeds(w::CombatWorld) = w.first_seed:(w.first_seed + w.planned - 1)

"""
    read_combat_world(world, exp, folder) -> CombatWorld

A combat study folder read as `world`'s run of `exp`. Its fingerprint's last line names both
(`combat readings: world=<world> exp=<exp>`); a folder whose fingerprint names another world or experiment, or none, is
refused (`ArgumentError`). The periods come from its `periods=` line, the planned seeds from its name
(`…-s<first>-<seeds>-p<periods>`). A planned seed is read when whole (see [`combat_seed_done`](@ref)), else counted as
unfinished.
"""
function read_combat_world(world::AbstractString, exp::AbstractString, folder::AbstractString)
    world in COMBAT_WORLDS || throw(ArgumentError("the world is book, xl or today, not $(repr(world))"))
    exp in COMBAT_EXPS || throw(ArgumentError("the experiment is one of $(join(COMBAT_EXPS, ", ")), not $(repr(exp))"))
    isdir(folder) || throw(ArgumentError("$folder is not a folder"))
    path = joinpath(folder, "fingerprint.txt")
    isfile(path) || throw(ArgumentError("$folder has no fingerprint"))
    m = match(r"^combat readings: world=(\S+) exp=(\S+)[ \t\r]*$"m, read(path, String))
    m === nothing &&
        throw(ArgumentError("$folder is not a combat study folder: its fingerprint names no combat readings"))
    (m.captures[1], m.captures[2]) == (world, exp) ||
        throw(ArgumentError("$folder is read as $world's $exp, but its fingerprint names $(m.captures[1])'s $(m.captures[2])"))
    periods = folder_periods(folder)
    first_seed, planned = study_folder_seeds(folder)
    seeds, unfinished = CombatSeed[], Int[]
    for k in first_seed:(first_seed + planned - 1)
        if !combat_seed_done(folder, k, periods)
            push!(unfinished, k)
            continue
        end
        table, _ = named_table(combat_path(folder, k), COMBAT_COLUMNS)
        push!(seeds, CombatSeed(k, seed_extinct(table["population"], periods), table))
    end
    return CombatWorld(world, exp, String(folder), first_seed, planned, periods, unfinished, seeds)
end

"""
    read_combat_worlds(dir; first_seed=0, seeds=20) -> Dict

The fifteen folders `combat-<world>-<exp>-s<first>-<seeds>-p<steps>` in `dir` (each experiment over its own steps),
read ([`read_combat_world`](@ref)) by `(world, exp)`. A missing or refused folder is an `ArgumentError`.
"""
function read_combat_worlds(dir::AbstractString; first_seed::Int=0, seeds::Int=20)
    registry = load_registry()
    return Dict(
        (world, exp) => read_combat_world(
            world, exp, joinpath(dir, combat_name(world, exp, first_seed, seeds, find_experiment(registry, exp).steps)),
        ) for world in COMBAT_WORLDS for exp in COMBAT_EXPS
    )
end

"""A seed's [`window_value`](@ref) of a combat table column over `window`; undefined if the run doesn't reach it."""
function seed_window(s::CombatSeed, column::AbstractString, window::Tuple{Int,Int})
    x = s.table[column]
    window[2] < length(x) || return (; value=NaN, skipped=0, periods=0)
    return window_value(x, window[1]:window[2])
end

"""A seed's kills (both tribes' victims) from t = 1 to its end over its population at t = 0, as a one-period value."""
function kills_per_founder(s::CombatSeed)
    t = s.table
    founders = t["population"][1]
    kills = sum(@view t["killed_blue"][2:end]) + sum(@view t["killed_red"][2:end])
    v = founders == 0 ? NaN : kills / founders
    return (; value=v, skipped=Int(!isfinite(v)), periods=1)
end

# The values over a world's seeds that a bar reads (a seed at population 0 at its last period left out).
bar_values(value_of, w::CombatWorld) = seeds_used(value_of, w.seeds, w.unfinished).values
mixing_values(w::CombatWorld) = bar_values(s -> seed_window(s, "mixing", W2_WINDOW), w)

"""W1: kills per founder of world `run`'s III-9 over `base`'s, a [`ratio_bar`](@ref)."""
combat_w1(run::CombatWorld, base::CombatWorld) =
    ratio_bar(bar_values(kills_per_founder, run), bar_values(kills_per_founder, base))

# A world's cut in mixing from its III-12 and III-13 means.
mixing_cut(m12, m13) = 1 - m13 / m12

"""
    combat_cut(w12, w13) -> (; cut, lo, hi, n12, n13, counts)

A world's cut in mixing, `1 − mean(III-13) / mean(III-12)` of its seeds' mixing over [`W2_WINDOW`](@ref), with the 95%
interval of [`bootstrap_apart`](@ref) over the two sets of seeds. `counts` (as W2's reference) when the interval's lower
end is above 0.
"""
function combat_cut(w12::CombatWorld, w13::CombatWorld)
    a, b = mixing_values(w12), mixing_values(w13)
    c = bootstrap_apart(mixing_cut, a, b)
    return (; cut=c.value, c.lo, c.hi, n12=length(a), n13=length(b), counts=isfinite(c.lo) && settle(c.lo) > 0)
end

"""
    combat_w2(t12, t13, refs) -> (; ratio, lo, hi, reference, today, cuts, n, result)

W2: today's cut in mixing ([`combat_cut`](@ref) of `t12`, `t13`) over that of the first of `refs` (each
`(name, w12, w13)`, the book's then xl's) whose cut counts, `reference` its name (`nothing` if none counts). Its interval
is [`bootstrap_apart`](@ref)'s over the four sets of seeds (today's III-12 and III-13, the reference's), `n` their sizes.
`result` is `:missing` with no reference that counts, fewer than [`MIN_SEEDS`](@ref) seeds in any of the four sets or a
ratio or upper end that isn't finite, `:holds` when the ratio is under [`W_SHARE`](@ref) and the upper end under 1, else
`:fails`. `today` is today's cut and `cuts` each reference's, by name.
"""
function combat_w2(t12::CombatWorld, t13::CombatWorld, refs)
    today = combat_cut(t12, t13)
    cuts = [(String(name), combat_cut(r12, r13)) for (name, r12, r13) in refs]
    a, b = mixing_values(t12), mixing_values(t13)
    i = findfirst(c -> c[2].counts, cuts)
    if i === nothing
        return (; ratio=NaN, lo=NaN, hi=NaN, reference=nothing, today, cuts, n=(length(a), length(b), 0, 0),
                result=:missing)
    end
    _, r12, r13 = refs[i]
    c, d = mixing_values(r12), mixing_values(r13)
    r = bootstrap_apart((x, y, z, w) -> mixing_cut(x, y) / mixing_cut(z, w), a, b, c, d)
    n = (length(a), length(b), length(c), length(d))
    missing_ = minimum(n) < MIN_SEEDS || !isfinite(r.value) || !isfinite(r.hi)
    return (; ratio=r.value, r.lo, r.hi, reference=cuts[i][1], today, cuts, n, result=w_result(missing_, r.value, r.hi))
end

"""
    combat_f(t9, t11, t14) -> NamedTuple

Bar F over every planned seed of today's III-9, III-11 and III-14 folders, an unfinished seed failing each part it is in:

- F1 (III-11): `f1_no_kill` the seeds without a kill (either tribe's victim) in some [`F1_BLOCK`](@ref)-period block of
  [`F1_WINDOW`](@ref); `f1_home_share` the share of planned seeds whose lesser mean home share over the window is above
  [`HOME_MIN`](@ref). `f1` holds when no seed lacks a kill and that share is at least [`F1_SEEDS_SHARE`](@ref); missing
  when the run doesn't reach the window.
- F2 (III-9, III-14): `f2_dead` the seeds (`"<exp> seed <k>"`) whose population at their last period isn't above 0.
- F3 (III-14): `f3_share` the share of planned seeds with both tribes at least [`F_MIN_SHARE`](@ref) of the population
  at the last period; `f3` holds when it is at least [`F3_SEEDS_SHARE`](@ref).

`seeds` is the whole seeds of each folder; `result` is `:missing` with fewer than [`MIN_SEEDS`](@ref) whole seeds in a
folder or F1 missing, `:holds` when all three hold, else `:fails`.
"""
function combat_f(t9::CombatWorld, t11::CombatWorld, t14::CombatWorld)
    whole(w) = Dict(s.seed => s for s in w.seeds)
    lo, hi = F1_WINDOW
    reach = t11.periods >= hi
    f1_no_kill, holding = Int[], 0
    seeds11 = whole(t11)
    for k in planned_seeds(t11)
        s = get(seeds11, k, nothing)
        if s === nothing || !reach
            push!(f1_no_kill, k)
            continue
        end
        kills = s.table["killed_blue"] .+ s.table["killed_red"]
        all(b -> sum(@view kills[(b + 1):(b + F1_BLOCK)]) > 0, lo:F1_BLOCK:hi) || push!(f1_no_kill, k)
        home = min(seed_window(s, "home_blue", F1_WINDOW).value, seed_window(s, "home_red", F1_WINDOW).value)
        holding += settle(home) > HOME_MIN
    end
    f1_home_share = t11.planned == 0 ? NaN : holding / t11.planned
    f1 = !reach ? :missing : isempty(f1_no_kill) && settle(f1_home_share) >= F1_SEEDS_SHARE ? :holds : :fails

    f2_dead = String[]
    for w in (t9, t14)
        seeds = whole(w)
        for k in planned_seeds(w)
            s = get(seeds, k, nothing)
            (s !== nothing && s.table["population"][end] > 0) || push!(f2_dead, "$(w.exp) seed $k")
        end
    end
    f2 = isempty(f2_dead) ? :holds : :fails

    both = 0
    for s in t14.seeds
        pop = s.table["population"][end]
        both += pop > 0 && settle(s.table["n_blue"][end] / pop) >= F_MIN_SHARE &&
                settle(s.table["n_red"][end] / pop) >= F_MIN_SHARE
    end
    f3_share = t14.planned == 0 ? NaN : both / t14.planned
    f3 = settle(f3_share) >= F3_SEEDS_SHARE ? :holds : :fails

    seeds = (length(t9.seeds), length(t11.seeds), length(t14.seeds))
    result = (minimum(seeds) < MIN_SEEDS || f1 == :missing) ? :missing :
             f1 == f2 == f3 == :holds ? :holds : :fails
    return (; f1_no_kill, f1_home_share, f1, f2_dead, f2, f3_both=both, f3_share, f3, planned=t11.planned, seeds, result)
end

"""
    saved_fingerprint(exp, world; registry=load_registry()) -> String

The `fingerprint.txt` the runner writes today into a saved run of `exp` in `world` (`"book"` or `"xl"`:
[`run_fingerprint`](@ref)), which a saved folder's must equal to count as a reference. Today has no saved run.
"""
function saved_fingerprint(exp::AbstractString, world::AbstractString; registry=load_registry())
    world in ("book", "xl") || throw(ArgumentError("only the book's world and xl have saved runs, not $(repr(world))"))
    return run_fingerprint(find_experiment(registry, exp); xl=world == "xl")
end

"""
    combat_drift(folder, ref, current_fingerprint; prefix=false) -> (; status, matched, differ)

The drift check of a study folder against a saved run `ref`. `status` is `:no_reference` (nothing compared) when `ref`
doesn't exist or its `fingerprint.txt` isn't `current_fingerprint` (Windows line ends read as `\\n`: some saved
fingerprints were rewritten by hand). Otherwise each seed with a `seed<k>.csv` in both is compared by
[`culture_drift`](@ref) (byte for byte, or with `prefix` its lines against `ref`'s first lines, for a dry run), `matched`
and `differ` listing them, and `status` is `:passes` when none differs, else `:fails`. Seeds `ref` lacks are skipped.
"""
function combat_drift(folder::AbstractString, ref::AbstractString, current_fingerprint::AbstractString;
                      prefix::Bool=false)
    path = joinpath(ref, "fingerprint.txt")
    (isfile(path) && replace(read(path, String), "\r\n" => "\n") == current_fingerprint) ||
        return (; status=:no_reference, matched=Int[], differ=Int[])
    d = culture_drift(folder, ref; prefix)
    return (; status=isempty(d.differ) ? :passes : :fails, d.matched, d.differ)
end

"""
    combat_bars(worlds; ref_book, ref_xl) -> NamedTuple

The bars of the fifteen folders ([`read_combat_worlds`](@ref)), with `ref_book` and `ref_xl` the saved runs' folders
(each holding `<exp>/`):

- `w1`: today ÷ book of III-9's kills per founder ([`combat_w1`](@ref)); `w1_xl`: xl ÷ book, shown;
- `w2`: [`combat_w2`](@ref), the book's cut then xl's as the reference; `w`: [`both_bars`](@ref) of W1 and W2;
- `f`: [`combat_f`](@ref) of today;
- `drift`: [`combat_drift`](@ref) of each book and xl folder against `<ref>/<exp>/`, each with its `world`, `exp` and
  `ref`; `drift_ok` whether none fails (no reference isn't a failure);
- `outcome`: [`bar_outcome`](@ref).
"""
function combat_bars(worlds::AbstractDict; ref_book::AbstractString, ref_xl::AbstractString)
    w(world, exp) = worlds[(world, exp)]
    w1 = combat_w1(w("today", "III-9"), w("book", "III-9"))
    w2 = combat_w2(w("today", "III-12"), w("today", "III-13"),
                   [(world, w(world, "III-12"), w(world, "III-13")) for world in ("book", "xl")])
    f = combat_f(w("today", "III-9"), w("today", "III-11"), w("today", "III-14"))
    registry = load_registry()
    drift = map([(world, exp) for world in ("book", "xl") for exp in COMBAT_EXPS]) do (world, exp)
        ref = joinpath(world == "book" ? ref_book : ref_xl, exp)
        d = combat_drift(w(world, exp).folder, ref, saved_fingerprint(exp, world; registry))
        (; world, exp, ref, d...)
    end
    drift_ok = all(d -> d.status != :fails, drift)
    wbar = both_bars(w1.result, w2.result)
    return (; w1, w1_xl=combat_w1(w("xl", "III-9"), w("book", "III-9")), w2, w=wbar, f, drift, drift_ok,
            outcome=bar_outcome(drift_ok, wbar, f.result))
end

const COMBAT_OUTCOME_TEXT = Dict(
    :drift => "**The drift check fails: the runs differ from the saved runs: stop and report to the user.** No bar is " *
              "read until we've talked.",
    :report => "**F fails or reads missing: report to the user with the readings.** No rule is proposed until we've " *
               "talked.",
    :no_outcome => "**W reads missing: no outcome is drawn.** It is reported to the user.",
    :weak => "**W holds and F passes: combat is weak in xxl.** The readings go to the user with a rule spec: kills by " *
             "window, front share and speed's reach, with what they point to; any rule gets its own spec with the user.",
    :works => "**W doesn't hold and F passes: combat works as intended in xxl.** It is written up in docs/xxl.md as " *
              "\"Stage 8: combat\", the goal gains combat, and the stage stops.",
)

const DRIFT_STATUS_TEXT = Dict(:passes => "passes", :fails => "fails", :no_reference => "no reference")

# III-9's ending of a world's seeds at their last period: both tribes alive, one under F_MIN_SHARE, the population 0.
function combat_endings(w::CombatWorld)
    both, blue, red, dead = Int[], Int[], Int[], Int[]
    for s in w.seeds
        pop = s.table["population"][end]
        if pop == 0
            push!(dead, s.seed)
        elseif settle(s.table["n_blue"][end] / pop) < F_MIN_SHARE
            push!(blue, s.seed)
        elseif settle(s.table["n_red"][end] / pop) < F_MIN_SHARE
            push!(red, s.seed)
        else
            push!(both, s.seed)
        end
    end
    return (; both, blue, red, dead)
end

# A cut's row: its value, its interval (the lower end against 0) and whether it counts as W2's reference.
function cut_row(name, c; reference::Bool=true)
    interval = isfinite(c.lo) && isfinite(c.hi) ? "[$(bar_figure(c.lo, 0; strict=true)), $(fmt(c.hi))]" : "—"
    return row_text([name, finite_text(c.cut), interval,
                     reference ? "counts as the reference when the interval's lower end is above 0" : "shown",
                     "$(c.n12) / $(c.n13)", reference ? (c.counts ? "counts" : "doesn't count") : "—"])
end

"""
    combat_report_text(worlds; ref_book, ref_xl) -> String

The report as markdown: each folder with its seeds whole, not run and extinct, the drift check per folder, the bars
(value, interval, bar, result, and W2's reference), the readings of every experiment and world by window, III-9's ending
per seed and the outcome.
"""
function combat_report_text(worlds::AbstractDict; ref_book::AbstractString, ref_xl::AbstractString)
    bars = combat_bars(worlds; ref_book, ref_xl)
    outcome_text = COMBAT_OUTCOME_TEXT[bars.outcome]
    lines = ["# Combat, Part 1", "", outcome_text, ""]
    push!(lines, "The book's world has its own density and neighbourhood (4 sites against xxl's 8 within 1.5), and the " *
                 "generated map has no twin peaks, so \"half the book's\" compares unlike worlds; xl is shown to separate " *
                 "world size from xxl's rules. The book recreation doesn't reproduce the waves, so W2 measures mixing, " *
                 "not wave suppression.", "")

    push!(lines, "## Folders", "", row_text(["World", "Experiment", "Folder", "Seeds whole", "Not run", "Extinct"]),
          "|---|---|---|---|---|---|")
    for world in COMBAT_WORLDS, exp in COMBAT_EXPS
        w = worlds[(world, exp)]
        extinct = [s.seed for s in w.seeds if s.extinct !== nothing]
        push!(lines, row_text([world, exp, w.folder, "$(length(w.seeds)) of $(w.planned)", seed_list(w.unfinished),
                               seed_list(extinct)]))
    end
    push!(lines, "", "A seed whose last population is 0 (extinct) is left out of the ratio values and counted. A period " *
                     "where a value is undefined is skipped in the seed's window mean, and a seed with no defined period " *
                     "is left out of that value. Fewer than $MIN_SEEDS seeds in a value read its bar as missing.")

    push!(lines, "", "## Drift check", "",
          "Each book and xl seed's standard CSV against the saved run's for the same experiment and seed, the full files " *
          "byte for byte, when the saved folder's fingerprint is the one the runner writes today (else no reference, " *
          "not a failure; seeds the saved run lacks are skipped). Today's folders have no reference.", "",
          row_text(["World", "Experiment", "Reference", "Matched", "Differ", "Result"]), "|---|---|---|---|---|---|")
    for d in bars.drift
        push!(lines, row_text([d.world, d.exp, d.ref, length(d.matched), seed_list(d.differ),
                               DRIFT_STATUS_TEXT[d.status]]))
    end

    w1, w2, f = bars.w1, bars.w2, bars.f
    t11 = worlds[("today", "III-11")]
    push!(lines, "", "## Bars", "",
          "W1: each seed's kills (both tribes' victims) from t = 1 to the end over its population at t = 0, in III-9. " *
          "W2: a world's cut in mixing, 1 − mixing(III-13) ÷ mixing(III-12), each the mean over seeds of each seed's mean " *
          "over $(period_text(W2_WINDOW...)); the reference is the book's cut, else xl's, the first whose own interval " *
          "is above 0. Ratios of the means over seeds; 95% intervals from $(thousands(BOOT_REPS)) bootstrap resamples of " *
          "each set of seeds apart (random seed $BOOT_SEED).", "",
          row_text(["Bar", "Value", "Interval", "Bar", "Seeds", "Result"]), "|---|---|---|---|---|---|",
          w_row("W1", w1), shown_row("W1, xl ÷ book", bars.w1_xl),
          [cut_row("Cut in mixing, $name", c) for (name, c) in w2.cuts]...,
          cut_row("Cut in mixing, today", w2.today; reference=false),
          w_row("W2", w2; seeds=join(w2.n, " / "),
                note="; reference: $(something(w2.reference, "none that counts"))"),
          row_text(["W", "—", "—", "W1 and W2 both hold", "—", BAR_RESULT_TEXT[bars.w]]),
          row_text(["F1, kills", "$(t11.planned - length(f.f1_no_kill)) of $(t11.planned)", "—",
                    "every III-11 seed has a kill in each $F1_BLOCK-period block of $(period_text(F1_WINDOW...)) " *
                    "(not: $(seed_list(f.f1_no_kill)))", "$(f.seeds[2]) whole", "—"]),
          row_text(["F1, home", bar_figure(f.f1_home_share, F1_SEEDS_SHARE), "—",
                    "both tribes' mean home share over $(period_text(F1_WINDOW...)) above $HOME_MIN in at least " *
                    "$F1_SEEDS_SHARE of III-11's seeds", "$(f.seeds[2]) whole", "—"]),
          row_text(["F1", "—", "—", "both parts", "—", BAR_RESULT_TEXT[f.f1]]),
          row_text(["F2", "$(length(f.f2_dead)) at population 0 or unfinished", "—",
                    "the population above 0 at the last period in every III-9 and III-14 seed " *
                    "(not: $(seed_list(f.f2_dead)))", "$(f.seeds[1]) / $(f.seeds[3]) whole", BAR_RESULT_TEXT[f.f2]]),
          row_text(["F3", bar_figure(f.f3_share, F3_SEEDS_SHARE), "—",
                    "both tribes at least $F_MIN_SHARE of the population at the last period in at least " *
                    "$F3_SEEDS_SHARE of III-14's seeds", "$(f.f3_both) of $(worlds[("today", "III-14")].planned)",
                    BAR_RESULT_TEXT[f.f3]]),
          row_text(["F", "—", "—", "F1, F2 and F3, unfinished seeds failing; missing under $MIN_SEEDS whole seeds " *
                    "in a folder", "—", BAR_RESULT_TEXT[f.result]]))

    push!(lines, "", "## Readings", "",
          "Each cell is the mean over seeds of each seed's window mean, then the seeds used and the share of their " *
          "seed-periods skipped; extinct seeds count here. Shown, deciding nothing.")
    for exp in COMBAT_EXPS
        push!(lines, "", "### $exp")
        periods = worlds[("today", exp)].periods
        for wd in COMBAT_READING_WINDOWS
            wd[2] <= periods || continue
            push!(lines, "", "#### $(period_text(wd...))", "", row_text(["Reading"; collect(COMBAT_WORLDS)]),
                  "|---|---|---|---|")
            for (column, name) in COMBAT_READINGS
                cells = map(COMBAT_WORLDS) do world
                    w = worlds[(world, exp)]
                    u = seeds_used(s -> seed_window(s, column, wd), w.seeds, w.unfinished; drop_extinct=false)
                    used_cell(u, w.planned)
                end
                push!(lines, row_text([name; collect(cells)]))
            end
        end
    end

    push!(lines, "", "## III-9's ending", "",
          "Each whole seed at its last period: both tribes at least $F_MIN_SHARE of the population, or one under it.", "",
          row_text(["World", "Both alive", "Blue under $F_MIN_SHARE", "Red under $F_MIN_SHARE", "Population 0", "Not run"]),
          "|---|---|---|---|---|---|")
    for world in COMBAT_WORLDS
        w = worlds[(world, "III-9")]
        e = combat_endings(w)
        push!(lines, row_text([world, seed_list(e.both), seed_list(e.blue), seed_list(e.red), seed_list(e.dead),
                               seed_list(w.unfinished)]))
    end
    push!(lines, "", "## Outcome", "", outcome_text)
    return join(lines, "\n") * "\n"
end

"""
    combat_report(; dir=RESULTS_XXL, first_seed=0, seeds=20, ref_book=REF_BOOK, ref_xl=REF_XL, md, io=stdout) -> String

Reads the fifteen study folders in `dir` ([`read_combat_worlds`](@ref)), refusing one whose fingerprint names another
world or experiment, before anything is written (`ArgumentError`); writes [`combat_report_text`](@ref)'s markdown to
`md` (`<dir>/combat-part1.md` by default) and prints it to `io` with where it went.
"""
function combat_report(; dir::AbstractString=RESULTS_XXL, first_seed::Int=0, seeds::Int=20,
                       ref_book::AbstractString=REF_BOOK, ref_xl::AbstractString=REF_XL,
                       md::AbstractString=joinpath(dir, "combat-part1.md"), io::IO=stdout)
    worlds = read_combat_worlds(dir; first_seed, seeds)
    text = combat_report_text(worlds; ref_book, ref_xl)
    publish_report(md, text, io)
    return text
end

const COMBAT_REPORT_USAGE =
    "usage: julia --project=julia julia/xxl_combat_report.jl [--dir DIR] [--first-seed K] [--seeds N] [--ref-book DIR] " *
    "[--ref-xl DIR] [--md PATH]"

"""
The report's command line: `--dir` (`results-julia-xxl`), `--first-seed` (0), `--seeds` (20), `--ref-book` and
`--ref-xl` (the saved runs, [`REF_BOOK`](@ref) and [`REF_XL`](@ref)) and `--md` (`<dir>/combat-part1.md`). Returns
`(; dir, first_seed, seeds, ref_book, ref_xl, md)`; throws `ArgumentError` on a usage error.
"""
function combat_report_args(args::Vector{String})
    opts = parse_study_options(args, ("--dir", "--first-seed", "--seeds", "--ref-book", "--ref-xl", "--md"))
    common = study_common_options(opts, 0, nothing)
    dir = get(opts, "--dir", RESULTS_XXL)
    return (; dir, common.first_seed, common.seeds, ref_book=get(opts, "--ref-book", REF_BOOK),
            ref_xl=get(opts, "--ref-xl", REF_XL), md=get(opts, "--md", joinpath(dir, "combat-part1.md")))
end

"""
    combat_report_main(args) -> exit code

The command line of julia/xxl_combat_report.jl: runs [`combat_report`](@ref). Returns 2 after printing the usage on a
usage error or a folder that is missing or refused, before anything is written; anything else is thrown.
"""
function combat_report_main(args::Vector{String})
    try
        a = combat_report_args(args)
        combat_report(; a...)
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, COMBAT_REPORT_USAGE, "\n", e.msg)
        return 2
    end
    return 0
end
