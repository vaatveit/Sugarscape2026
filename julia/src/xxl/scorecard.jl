# xxl: the scorecard (revised spec, "The scorecard"). It runs II-4, IV-A3 and VI-1 under one xxl rule set, with the
# scorecard columns, and their xl versions over the same seeds as the reference level; scores the fifteen checks S1-S5
# and X1-X10; and writes a markdown report. julia/xxl_scorecard.jl is its command line.

const SCORECARD_EXPERIMENTS = ["II-4", "IV-A3", "VI-1"]

"""
    Check

One scorecard check: its `id` (S1 ... X10), the `aspect` it measures, the `value` its threshold applies to, the
bounds `low` and `high` (inclusive, except X4's strict `low`), whether it passes, and a `detail`: the per-seed range,
or the failing seeds and why.
"""
struct Check
    id::String
    aspect::String
    value::Float64
    low::Float64
    high::Float64
    pass::Bool
    detail::String
end

# The spec's names for the checks, for the report.
const CHECK_TITLES = Dict(
    "S1" => "No extinction",
    "S2" => "No near-extinction",
    "S3" => "Recovery",
    "S4" => "Survivors, one good",
    "S5" => "Survivors, two goods",
    "X1" => "Births keep up",
    "X2" => "Mates in reach",
    "X3" => "Both cultures live",
    "X4" => "Culture moves",
    "X5" => "Agents trade",
    "X6" => "Prices agree",
    "X7" => "Credit persists",
    "X8" => "Loans are repaid",
    "X9" => "Disease is endemic",
    "X10" => "Disease is bounded",
)
const SCORECARD_ASPECTS = ["Survival", "Sex", "Culture", "Trade", "Credit", "Disease"]

const END_PERIODS = 100  # "end" is the mean over the last this many periods
const X1_PERIODS = 200  # X1 counts births and deaths over VI-1's last this many periods
const X3_T = 200  # X3 looks at the tribes in this period
const X7_AFTER = 100  # X7 wants loans outstanding in every period after this one
const X9_T = 500  # X9 looks for a circulating disease in this period
const DEATH_COLUMNS = ["deaths_sugar", "deaths_spice", "deaths_old_age", "deaths_killed"]

"""A check from its value: inclusive bounds, but strict above `low` for X4; a NaN value fails."""
function check(id, aspect, value, low, high, detail)
    above = id == "X4" ? value > low : value >= low
    return Check(
        id, aspect, value, low, high, !isnan(value) && above && value <= high, detail
    )
end

"""A number for the report: NaN, ∞, else four significant digits, a whole number printed as an integer."""
function fmt(x::Real)
    isnan(x) && return "NaN"
    isinf(x) && return x > 0 ? "∞" : "-∞"
    r = round(x; sigdigits=4)
    return isinteger(r) && abs(r) < 1e15 ? string(Int(r)) : string(r)
end

function range_text(v)
    return minimum(v) == maximum(v) ? fmt(v[1]) : "$(fmt(minimum(v)))–$(fmt(maximum(v)))"
end
mean_of(v) = sum(v) / length(v)
nanmean(v) = (w=filter(!isnan, v); isempty(w) ? NaN : mean_of(w))

# The first of these rows whose column `j` meets `test`, as its period t for a detail.
first_period(M, rows, j, test) = fmt(M[rows[findfirst(test, M[rows, j])], 1])

# Every check skips t = 0: the matrix rows from t = 1 on, where `keep(t)` holds.
periods(M, keep=_ -> true) = [r for r in axes(M, 1) if M[r, 1] >= 1 && keep(M[r, 1])]
row_at(M, t) = findfirst(==(t), view(M, :, 1))
end_mean(M, j) = nanmean(M[periods(M, t -> t > M[end, 1] - END_PERIODS), j])

"""
    over_seeds(values, ids, extinct; why="no value") -> (mean, detail)

The mean of per-seed values with the per-seed range as detail; NaN when any seed has no value, the detail then naming
those seeds: `extinct in seed k`, else `<why> in seed k`.
"""
function over_seeds(values, ids, extinct; why="no value")
    bad = findall(isnan, values)
    isempty(bad) && return mean_of(values), "per seed " * range_text(values)
    return NaN, missing_text(bad, ids, extinct, why)
end

function missing_text(bad, ids, extinct, why)
    return join(((extinct[i] ? "extinct" : why) * " in seed $(ids[i])" for i in bad), "; ")
end

"""The failing seeds as `seed k (note)`, the note `extinct` for a seed that reached 0, else `note(i)`."""
function failing_text(failing, ids, extinct, note)
    return "fails in " * join(
        ("seed $(ids[i]) (" * (extinct[i] ? "extinct" : note(i)) * ")" for i in failing),
        ", ",
    )
end

"""
    score(xxl_rows, xl_rows, columns; first_seed=0) -> Vector{Check}

The fifteen checks of the revised spec ("The checks"), with the plan's thresholds, from each experiment's seeds in
order: `xxl_rows[id]` the xxl scorecard runs of II-4, IV-A3 and VI-1, `xl_rows[id]` their xl runs over the same
seeds, `columns[id]` the names of the xxl matrices' columns, `t` first. An xl matrix has the leading `t` and
[`METRIC_COLUMNS`](@ref) of the xxl one, which are all it is read for. `first_seed` numbers the seeds in the details.

Every check skips t = 0; "end" is the mean over the last 100 periods, skipping NaN. A seed is extinct when its
population reaches 0. Per check:

- S1: the VI-1 seeds extinct, = 0. S2: the lowest VI-1 seed's minimum population ÷ its founders (t = 0), ≥ 0.1.
- S3, S4, S5: the mean over seeds of the end population of VI-1, II-4, IV-A3, ÷ the same mean for xl; ≥ 0.5, 0.9,
  0.9.
- X1: per seed, births ÷ deaths (the four causes) over the last 200 periods; their mean, 0.9-1.1.
- X2: per seed, `n_fertile_with_mate ÷ n_fertile` at the trough (the first period of the lowest population); their
  mean, ≥ 0.5.
- X3: the share of seeds where both tribes hold ≥ 5% of the population at t = 200, ≥ 0.8.
- X4: the lowest tag flips per agent in any period of any seed, > 0.
- X5: per seed, the end share of agents who traded in the last 10 periods; their mean, ≥ 0.5.
- X6: the mean over seeds of the end price sd ÷ the same mean for xl, ≤ 1.5.
- X7: the fewest loans outstanding in any period after t = 100 of any seed, ≥ 1.
- X8: per seed, the loans voided ÷ (voided + repaid), summed over the run; their mean, ≤ 0.2.
- X9: the share of seeds with a disease circulating at t = 500, ≥ 0.9.
- X10: per seed, the end share sick; their mean, 0.01-0.2.

X1, X2, X5, X6 and X10 need a population at the end: an extinct seed makes them NaN, failing, with the detail
`extinct in seed k`. So does any seed without a value, as do X3, X7 and X9 when the run has no such period.
"""
function score(
    xxl_rows::Dict{String,Vector{Matrix{Float64}}},
    xl_rows::Dict{String,Vector{Matrix{Float64}}},
    columns::Dict{String,Vector{String}};
    first_seed::Int=0,
)
    col(id) = name -> begin
        j = findfirst(==(name), columns[id])
        j === nothing && throw(ArgumentError("$id has no column $name"))
        j
    end
    pop = col("VI-1")("population")
    vi = xxl_rows["VI-1"]
    n = length(vi)
    ids = first_seed .+ (0:(n - 1))
    lowest = [minimum(M[periods(M), pop]) for M in vi]
    extinct = lowest .== 0
    gate(v) = [extinct[i] ? NaN : v[i] for i in eachindex(v)]
    checks = Check[]

    # Survival.
    dead = findall(extinct)
    detail = if isempty(dead)
        "lowest population per seed " * range_text(lowest)
    else
        join(
            (
                "extinct in seed $(ids[i]) (t = $(fmt(vi[i][findfirst(==(0), vi[i][:, pop]), 1])))"
                for i in dead
            ),
            ", ",
        )
    end
    push!(checks, check("S1", "Survival", length(dead), 0.0, 0.0, detail))
    shares = [lowest[i] / vi[i][1, pop] for i in 1:n]
    low = findall(<(0.1), shares)
    detail = "per seed " * range_text(shares)
    isempty(low) || (detail *= "; " * failing_text(low, ids, extinct, i -> fmt(shares[i])))
    push!(checks, check("S2", "Survival", minimum(shares), 0.1, Inf, detail))
    for (id, s, bound) in (("VI-1", "S3", 0.5), ("II-4", "S4", 0.9), ("IV-A3", "S5", 0.9))
        push!(
            checks,
            xl_ratio(
                s,
                "Survival",
                xxl_rows[id],
                xl_rows[id],
                col(id)("population"),
                bound,
                Inf;
                ids=ids,
            ),
        )
    end

    # Sex.
    c = col("VI-1")
    born, deaths = c("births"), c.(DEATH_COLUMNS)
    ratios = map(vi) do M
        rows = periods(M, t -> t > M[end, 1] - X1_PERIODS)
        return sum(M[rows, born]) / sum(M[rows, deaths])
    end
    v, d = over_seeds(gate(ratios), ids, extinct; why="no births or deaths")
    push!(checks, check("X1", "Sex", v, 0.9, 1.1, d))
    fertile, mated = c("n_fertile"), c("n_fertile_with_mate")
    at_trough = map(vi) do M
        rows = periods(M)
        r = rows[argmin(M[rows, pop])]
        return M[r, mated] / M[r, fertile]
    end
    v, d = over_seeds(gate(at_trough), ids, extinct; why="no fertile agent at the trough")
    push!(checks, check("X2", "Sex", v, 0.5, Inf, d))

    # Culture.
    blue, red = c("n_blue"), c("n_red")
    minority = map(vi) do M
        r = row_at(M, X3_T)
        return r === nothing ? NaN : min(M[r, blue], M[r, red]) / M[r, pop]
    end
    if any(M -> row_at(M, X3_T) === nothing, vi)
        push!(checks, check("X3", "Culture", NaN, 0.8, 1.0, "no t = $X3_T in the run"))
    else
        failing = findall(x -> !(x >= 0.05), minority)  # an empty population fails too
        detail = "smaller tribe per seed " * range_text(minority)
        isempty(failing) ||
            (detail = failing_text(failing, ids, extinct, i -> fmt(minority[i])))
        push!(checks, check("X3", "Culture", 1 - length(failing) / n, 0.8, 1.0, detail))
    end
    flips = c("tag_flips_per_agent")
    lowest_flips = [minimum(M[periods(M), flips]) for M in vi]  # NaN when any period is
    if any(isnan, lowest_flips)
        push!(
            checks,
            check(
                "X4",
                "Culture",
                NaN,
                0.0,
                Inf,
                missing_text(
                    findall(isnan, lowest_flips), ids, extinct, "a period without a value"
                ),
            ),
        )
    else
        failing = findall(<=(0), lowest_flips)
        detail = "lowest per seed " * range_text(lowest_flips)
        first_t = i -> first_period(vi[i], periods(vi[i]), flips, <=(0))
        isempty(failing) || (
            detail = failing_text(
                failing, ids, extinct, i -> "0 first at t = $(first_t(i))"
            )
        )
        push!(checks, check("X4", "Culture", minimum(lowest_flips), 0.0, Inf, detail))
    end

    # Trade.
    traded = c("share_traded_10")
    v, d = over_seeds(gate([end_mean(M, traded) for M in vi]), ids, extinct)
    push!(checks, check("X5", "Trade", v, 0.5, Inf, d))
    push!(
        checks,
        xl_ratio(
            "X6",
            "Trade",
            vi,
            xl_rows["VI-1"],
            c("price_sd"),
            -Inf,
            1.5;
            extinct=extinct,
            ids=ids,
        ),
    )

    # Credit.
    loans = c("n_loans")
    fewest = [
        isempty(periods(M, >(X7_AFTER))) ? NaN : minimum(M[periods(M, >(X7_AFTER)), loans])
        for M in vi
    ]
    if any(isnan, fewest)
        push!(
            checks,
            check(
                "X7",
                "Credit",
                NaN,
                1.0,
                Inf,
                missing_text(
                    findall(isnan, fewest), ids, extinct, "no period after t = $X7_AFTER"
                ),
            ),
        )
    else
        failing = findall(<(1), fewest)
        detail = "fewest per seed " * range_text(fewest)
        first_none = i -> first_period(vi[i], periods(vi[i], >(X7_AFTER)), loans, <(1))
        isempty(failing) || (
            detail = failing_text(
                failing, ids, extinct, i -> "none first at t = $(first_none(i))"
            )
        )
        push!(checks, check("X7", "Credit", minimum(fewest), 1.0, Inf, detail))
    end
    voided, repaid = c("loans_voided"), c("loans_repaid")
    share_voided = map(vi) do M
        rows = periods(M)
        return sum(M[rows, voided]) / (sum(M[rows, voided]) + sum(M[rows, repaid]))
    end
    v, d = over_seeds(share_voided, ids, falses(n); why="no loan ended")
    push!(checks, check("X8", "Credit", v, -Inf, 0.2, d))

    # Disease.
    circulating = c("diseases_circulating")
    if any(M -> row_at(M, X9_T) === nothing, vi)
        push!(checks, check("X9", "Disease", NaN, 0.9, 1.0, "no t = $X9_T in the run"))
    else
        counts = [M[row_at(M, X9_T), circulating] for M in vi]
        failing = findall(<=(0), counts)
        detail = "diseases per seed " * range_text(counts)
        isempty(failing) || (detail = failing_text(failing, ids, extinct, _ -> "none"))
        push!(checks, check("X9", "Disease", 1 - length(failing) / n, 0.9, 1.0, detail))
    end
    sick = c("fraction_sick")
    v, d = over_seeds(gate([end_mean(M, sick) for M in vi]), ids, extinct)
    push!(checks, check("X10", "Disease", v, 0.01, 0.2, d))
    return checks
end

"""
A ratio of means: the mean over seeds of the xxl end value of column `j`, ÷ the same mean for xl. With `extinct`, an
extinct seed's xxl value is NaN, and any NaN makes the ratio NaN, its detail naming the seeds.
"""
function xl_ratio(
    id, aspect, xxl, xl, j, low, high; extinct=falses(length(xxl)), ids=0:(length(xxl) - 1)
)
    ours = [extinct[i] ? NaN : end_mean(xxl[i], j) for i in eachindex(xxl)]
    theirs = [end_mean(M, j) for M in xl]
    if any(isnan, ours) || any(isnan, theirs)
        bad = findall(isnan, ours)
        detail = join(
            filter(
                !isempty,
                [
                    missing_text(bad, ids, extinct, "no value"),
                    missing_text(
                        findall(isnan, theirs), ids, falses(length(xl)), "no xl value"
                    ),
                ],
            ),
            "; ",
        )
        return check(id, aspect, NaN, low, high, detail)
    end
    detail = "end per seed: xxl $(range_text(ours)), xl $(range_text(theirs))"
    return check(id, aspect, mean_of(ours) / mean_of(theirs), low, high, detail)
end

"""The threshold as the report prints it."""
function threshold_text(c::Check)
    c.id == "X4" && return "> $(fmt(c.low))"
    c.low == c.high && return "= $(fmt(c.low))"
    c.high == Inf && return "≥ $(fmt(c.low))"
    c.low == -Inf && return "≤ $(fmt(c.high))"
    return "$(fmt(c.low))–$(fmt(c.high))"
end

"""`scorecard-<label>-s<first>-<seeds>`: the folder and report name of a scorecard, carrying its seed range."""
scorecard_name(label, first_seed, seeds) = "scorecard-$label-s$first_seed-$seeds"

function seed_text(first_seed, seeds)
    return seeds == 1 ? "$first_seed" : "$(first_seed)–$(first_seed + seeds - 1)"
end

"""
    scorecard_report(checks; label, rules, seeds, first_seed, steps, jobs, wall, times) -> String

The markdown report: a header with the label, the rules line, the seeds, the periods and the wall time (`times`
gives each run's seconds, `nothing` for a reused xl run), then one table per aspect with each check's value, its
threshold, PASS or FAIL, and the detail.
"""
function scorecard_report(checks; label, rules, seeds, first_seed, steps, jobs, wall, times)
    run_text(kind) = join(
        (
            "$id " * (
                if times[(kind, id)] === nothing
                    "reused"
                else
                    "$(round(Int, times[(kind, id)])) s"
                end
            ) for id in SCORECARD_EXPERIMENTS
        ),
        ", ",
    )
    lines = [
        "# Scorecard: $label",
        "",
        "- Rules: `$(rules_line(rules))`",
        "- Seeds: $(seed_text(first_seed, seeds)) ($seeds seed$(seeds == 1 ? "" : "s"))",
        "- Periods: " * join(("$id $(steps[id])" for id in SCORECARD_EXPERIMENTS), ", "),
        "- Wall time: $(round(Int, wall)) s with --jobs $jobs on $(Sys.CPU_THREADS) threads " *
        "(xxl: $(run_text(:xxl)); xl: $(run_text(:xl)))",
        "- Passing: $(count(c -> c.pass, checks)) of $(length(checks)) checks",
    ]
    for aspect in SCORECARD_ASPECTS
        push!(
            lines,
            "",
            "## $aspect",
            "",
            "| Check | Value | Threshold | Result | Detail |",
            "|---|---|---|---|---|",
        )
        for c in checks
            c.aspect == aspect || continue
            push!(
                lines,
                "| $(c.id) $(CHECK_TITLES[c.id]) | $(fmt(c.value)) | $(threshold_text(c)) | " *
                "$(c.pass ? "PASS" : "FAIL") | $(c.detail) |",
            )
        end
    end
    return join(lines, "\n") * "\n"
end

"""A seed CSV as the runner writes it: (header, rows as a matrix)."""
function read_seed_csv(path::AbstractString)
    lines = readlines(path)
    header = String.(split(lines[1], ","))
    M = Matrix{Float64}(undef, length(lines) - 1, length(header))
    for r in 1:(length(lines) - 1)
        values = split(lines[r + 1], ",")
        length(values) == length(header) || throw(
            ArgumentError(
                "$path: row $r has $(length(values)) values, not $(length(header))"
            ),
        )
        for (j, v) in enumerate(values)
            M[r, j] = parse(Float64, v)
        end
    end
    return header, M
end

"""Whether an xl folder holds these seeds of `exp`, with a current fingerprint and `exp.steps + 1` rows each."""
function xl_current(folder::AbstractString, exp::Experiment, indices)
    fp = joinpath(folder, "fingerprint.txt")
    (isfile(fp) && read(fp, String) == "julia\n" * exp.xl_fingerprint) || return false
    for k in indices
        path = joinpath(folder, "seed$k.csv")
        (isfile(path) && countlines(path) == exp.steps + 2) || return false
    end
    return true
end

"""A copy of `exp` with `steps` periods; its fingerprints still name the original steps."""
function with_steps(e::Experiment, steps::Int)
    return Experiment(
        e.id,
        e.title,
        e.rules,
        steps,
        e.seeds,
        e.config,
        e.fingerprint,
        e.xl_config,
        e.xl_fingerprint,
    )
end

"""
    run_scorecard(rules; label, seeds=20, first_seed=0, jobs=1, out="results-julia-xxl", steps_override=nothing,
                  io=stdout) -> Vector{Check}

Runs II-4, IV-A3 and VI-1 under `rules` with the scorecard columns into `<out>/scorecard-<label>-s<first>-<seeds>/<id>/`,
and their xl versions into `<out>/scorecard-xl-s<first>-<seeds>/<id>/`, reusing an xl folder that already holds these
seeds with a current fingerprint and the expected row count. Scores them ([`score`](@ref)), writes the report to
`<out>/scorecard-<label>-s<first>-<seeds>.md` and prints progress and the report to `io`. The folder names carry the
seed range, so a confirmation run never overwrites the choosing run, and either can be re-scored from its CSVs.
`steps_override` shortens every experiment, for tests only.
"""
function run_scorecard(
    rules::XxlRules;
    label::String,
    seeds::Int=20,
    first_seed::Int=0,
    jobs::Int=1,
    out::AbstractString=RESULTS_XXL,
    steps_override::Union{Nothing,Int}=nothing,
    io::IO=stdout,
)
    t0 = time_ns()
    reg = load_registry()
    exps = map(SCORECARD_EXPERIMENTS) do id
        e = find_experiment(reg, id)
        return steps_override === nothing ? e : with_steps(e, steps_override)
    end
    foreach(e -> to_xxl(e.config, rules), exps)  # invalid rules fail here, before any run
    indices = first_seed:(first_seed + seeds - 1)
    name = scorecard_name(label, first_seed, seeds)
    xxl_out = joinpath(out, name)
    xl_out = joinpath(out, scorecard_name("xl", first_seed, seeds))
    times = Dict{Tuple{Symbol,String},Union{Nothing,Float64}}()
    xxl_rows = Dict{String,Vector{Matrix{Float64}}}()
    xl_rows = Dict{String,Vector{Matrix{Float64}}}()
    columns = Dict{String,Vector{String}}()
    for exp in exps
        id = exp.id
        t1 = time_ns()
        folder = run_experiment(
            exp;
            seeds=seeds,
            first_seed=first_seed,
            jobs=jobs,
            out=xxl_out,
            xxl=rules,
            scorecard=true,
            note="scorecard $label",
        )
        times[(:xxl, id)] = seconds_since(t1)
        println(io, "$id xxl: $seeds seeds -> $folder ($(round(Int, times[(:xxl, id)])) s)")
        xl_folder = result_dir(xl_out, id)
        if xl_current(xl_folder, exp, indices)
            times[(:xl, id)] = nothing
            println(io, "$id xl: reusing $xl_folder")
        else
            t1 = time_ns()
            run_experiment(
                exp; seeds=seeds, first_seed=first_seed, jobs=jobs, out=xl_out, xl=true
            )
            times[(:xl, id)] = seconds_since(t1)
            println(
                io, "$id xl: $seeds seeds -> $xl_folder ($(round(Int, times[(:xl, id)])) s)"
            )
        end
        flush(io)  # progress shows in a log file while the next experiment runs
        read_all(dir) = [read_seed_csv(joinpath(dir, "seed$k.csv")) for k in indices]
        ours, theirs = read_all(folder), read_all(xl_folder)
        header = ours[1][1]
        all(h == header for (h, _) in ours) ||
            throw(ArgumentError("$folder: the seeds' columns differ"))
        for (h, _) in theirs
            h == header[1:min(length(h), end)] ||
                throw(ArgumentError("$xl_folder: its columns do not lead the xxl ones"))
        end
        columns[id] = header
        xxl_rows[id] = [M for (_, M) in ours]
        xl_rows[id] = [M for (_, M) in theirs]
    end
    checks = score(xxl_rows, xl_rows, columns; first_seed=first_seed)
    report = scorecard_report(
        checks;
        label=label,
        rules=rules,
        seeds=seeds,
        first_seed=first_seed,
        steps=Dict(e.id => e.steps for e in exps),
        jobs=jobs,
        wall=seconds_since(t0),
        times=times,
    )
    mkpath(out)
    path = joinpath(out, name * ".md")
    write(path, report)
    println(io, "\n", report, "\n-> $path")
    return checks
end

const SCORECARD_BASES = Dict("v1" => XXL_V1, "defaults" => XXL_DEFAULTS)

"""A `--set` value as the field's type reads it: `nothing` or an integer, `nothing` or `lo,hi`, else by type."""
function parse_rule_value(T::Type, v::AbstractString)
    T === String && return String(v)
    T === Float64 && return parse(Float64, v)
    T === Int && return parse(Int, v)
    T === Bool && return parse(Bool, v)
    v == "nothing" && Nothing <: T && return nothing
    T === Union{Nothing,Int} && return parse(Int, v)
    if T === Union{Nothing,Tuple{Int,Int}}
        parts = split(strip(v, ['(', ')']), ",")
        length(parts) == 2 ||
            throw(ArgumentError("expected nothing or lo,hi, not $(repr(v))"))
        return (parse(Int, strip(parts[1])), parse(Int, strip(parts[2])))
    end
    return throw(ArgumentError("cannot read a $T from the command line"))
end

"""
The scorecard's command line: `--rules v1|defaults`, repeated `--set field=value`, `--label NAME`, `--seeds N`,
`--first-seed K`, `--jobs J` and `--out DIR`. Throws `ArgumentError` on a usage error.
"""
function scorecard_args(args::Vector{String})
    base, sets, label = "defaults", Pair{Symbol,Any}[], nothing
    texts = String[]
    seeds, first_seed, jobs, out = 20, 0, 1, RESULTS_XXL
    i = 1
    while i <= length(args)
        a = args[i]
        a in
        ("--rules", "--set", "--label", "--seeds", "--first-seed", "--jobs", "--out") ||
            throw(ArgumentError("unexpected argument $a"))
        i += 1
        i <= length(args) || throw(ArgumentError("$a needs a value"))
        v = args[i]
        if a == "--rules"
            haskey(SCORECARD_BASES, v) ||
                throw(ArgumentError("--rules is v1 or defaults, not $(repr(v))"))
            base = v
        elseif a == "--set"
            eq = findfirst('=', v)
            eq === nothing &&
                throw(ArgumentError("--set wants field=value, not $(repr(v))"))
            field = Symbol(v[1:(eq - 1)])
            field in fieldnames(XxlRules) ||
                throw(ArgumentError("XxlRules has no field $field"))
            push!(
                sets, field => parse_rule_value(fieldtype(XxlRules, field), v[(eq + 1):end])
            )
            push!(texts, v)
        elseif a == "--label"
            label = v
        elseif a == "--seeds"
            seeds = parse(Int, v)
        elseif a == "--first-seed"
            first_seed = parse(Int, v)
        elseif a == "--jobs"
            jobs = parse(Int, v)
        else
            out = v
        end
        i += 1
    end
    rules = replace_rules(SCORECARD_BASES[base]; sets...)
    label = something(label, join([base; texts], "+"))
    return (
        rules=rules, label=label, seeds=seeds, first_seed=first_seed, jobs=jobs, out=out
    )
end

"""
    rules_from_args(args) -> (XxlRules, label)

The rules and label of a scorecard command line: the `--rules` base (`v1` or `defaults`, the default) with each
`--set field=value` applied, the value read by the field's type; the label `--label` gives, else the base followed by
each `--set` as written, joined by `+` (`v1+free_step=1.5`). `--seeds`, `--first-seed`, `--jobs` and `--out` are
passed over.
"""
function rules_from_args(args::Vector{String})
    a = scorecard_args(args)
    return a.rules, a.label
end

const SCORECARD_USAGE = "usage: julia --project=julia julia/xxl_scorecard.jl [--rules v1|defaults] [--set field=value]... [--label NAME] [--seeds N] [--first-seed K] [--jobs J] [--out DIR]"

"""
    scorecard_main(args) -> exit code

The command line of julia/xxl_scorecard.jl: runs [`run_scorecard`](@ref) as `args` say. Returns 2 on a usage error.
"""
function scorecard_main(args::Vector{String})
    a = try
        scorecard_args(args)
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, SCORECARD_USAGE, "\n", e.msg)
        return 2
    end
    run_scorecard(
        a.rules;
        label=a.label,
        seeds=a.seeds,
        first_seed=a.first_seed,
        jobs=a.jobs,
        out=a.out,
    )
    return 0
end
