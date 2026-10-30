# xxl: the extinction test (stage-2 spec, "The test"). Whether VI-1 under the defaults has under a 5% chance of going
# extinct in 2,000 periods: the upper limit on that chance from the seeds run, one seed's outcome, the verdict and the
# markdown report, and the run that makes the seeds and resumes after a stop (julia/xxl_extinction.jl is its command
# line).

const EXTINCTION_BAR = 0.05  # the claim: the chance of extinction is below this
const DECLINE_LINE = 0.9  # a seed is falling when its last quarter's mean is below this share of the one before
const EXTINCTION_LAST = 200  # births and deaths are counted over the last this many periods

"""
    extinction_limit(extinct, seeds) -> Float64

The one-sided 95% upper confidence limit on the chance of extinction (exact binomial, Clopper–Pearson): the p at which
`extinct` or fewer of `seeds` going extinct has probability 0.05, by bisection. 1 when `seeds` is 0 or all went extinct.
With no extinctions it is 1 - 0.05^(1 / seeds).
"""
function extinction_limit(extinct::Int, seeds::Int)
    (seeds == 0 || extinct >= seeds) && return 1.0
    # P(X <= extinct) for X ~ Binomial(seeds, p), by the ratio of successive terms.
    function cdf(p)
        term = (1 - p)^seeds
        total = term
        for i in 0:(extinct - 1)
            term *= (seeds - i) / (i + 1) * p / (1 - p)
            total += term
        end
        return total
    end
    lo, hi = 0.0, 1.0  # the cdf falls from 1 at p = 0 to 0 at p = 1
    for _ in 1:100
        mid = (lo + hi) / 2
        cdf(mid) > EXTINCTION_BAR ? (lo = mid) : (hi = mid)
    end
    return (lo + hi) / 2
end

"""
    SeedOutcome

What one seed's run shows, for periods t = 1 to `p` (`p` the last period): the `lowest` population and the first period
`lowest_t` it came at, the population `at_quarters` (t = p÷4, p÷2, 3p÷4, p), `extinct_t` (the first period at 0, else
`nothing`), `births_last` and `deaths_last` over the last `min(EXTINCTION_LAST, p)` periods, the mean population over
the third quarter (p÷2 < t ≤ 3p÷4) and the fourth (3p÷4 < t ≤ p), and the `seconds` the run took (NaN if unknown).
"""
struct SeedOutcome
    seed::Int
    lowest::Float64
    lowest_t::Int
    at_quarters::NTuple{4,Float64}
    extinct_t::Union{Nothing,Int}
    births_last::Int
    deaths_last::Int
    mean_third::Float64
    mean_fourth::Float64
    seconds::Float64
end

"""
    seed_outcome(M, header, seed; seconds=NaN) -> SeedOutcome

One seed's outcome from its run `M` (rows t = 0 to `p`, columns named by `header`; only `t`, `population` and
`agents_ever` are read). Births over the last `w` periods are the change in `agents_ever`; deaths are those births
minus the change in `population`.
"""
function seed_outcome(M::Matrix{Float64}, header::Vector{String}, seed::Int; seconds::Float64=NaN)
    pop, ever = (findfirst(==(name), header) for name in ("population", "agents_ever"))
    p = round(Int, M[end, 1])
    at(t) = M[t + 1, pop]  # row t + 1 is period t
    lowest, lowest_t = findmin(M[2:end, pop])
    dead = findfirst(==(0), M[2:end, pop])
    w = min(EXTINCTION_LAST, p)
    births = round(Int, M[end, ever] - M[end - w, ever])
    return SeedOutcome(
        seed,
        lowest,
        lowest_t,
        (at(p ÷ 4), at(p ÷ 2), at(3p ÷ 4), at(p)),
        dead,
        births,
        births - round(Int, M[end, pop] - M[end - w, pop]),
        mean_of([at(t) for t in (p ÷ 2 + 1):(3p ÷ 4)]),
        mean_of([at(t) for t in (3p ÷ 4 + 1):p]),
        seconds,
    )
end

"""Whether a living seed fell by more than 10% from its third quarter's mean to its fourth's."""
is_falling(o::SeedOutcome) = o.extinct_t === nothing && o.mean_fourth < DECLINE_LINE * o.mean_third

"""
    extinction_verdict(outcomes) -> (; verdict, extinct, limit)

`PASS` when the upper limit on the chance of extinction is below the bar, else `TOO FEW SEEDS` when none went extinct
(more seeds would pass), else `FAIL`.
"""
function extinction_verdict(outcomes::Vector{SeedOutcome})
    extinct = count(o -> o.extinct_t !== nothing, outcomes)
    limit = extinction_limit(extinct, length(outcomes))
    verdict = limit < EXTINCTION_BAR ? "PASS" : extinct == 0 ? "TOO FEW SEEDS" : "FAIL"
    return (; verdict, extinct, limit)
end

"""A share as a percent with two decimals: `4.87`."""
function percent_text(x::Real)
    hundredths = round(Int, 10_000x)
    return "$(hundredths ÷ 100).$(lpad(hundredths % 100, 2, '0'))"
end

seconds_text(s) = isnan(s) ? "—" : string(round(Int, s))

"""
    extinction_report(outcomes; label, rules, first_seed, seeds, periods, jobs, wall) -> String

The markdown report: the verdict and the upper limit, the seeds finished of the `seeds` planned (from `first_seed`) over
`periods`, how many living seeds were falling at the end, the run time (`jobs` and `wall` may be `nothing`), then one
table row per outcome.
"""
function extinction_report(outcomes; label, rules, first_seed, seeds, periods, jobs, wall)
    v = extinction_verdict(collect(SeedOutcome, outcomes))
    finished = length(outcomes)
    living = filter(o -> o.extinct_t === nothing, outcomes)
    falling = count(is_falling, living)
    w = min(EXTINCTION_LAST, periods)
    times = filter(!isnan, [o.seconds for o in outcomes])
    run_time = if isempty(times)
        "—"
    else
        "$(round(Int, sum(times))) s in all, $(round(Int, mean_of(times))) s per seed"
    end
    wall === nothing || (run_time *= "; wall $(round(Int, wall)) s")
    jobs === nothing || (run_time *= " with --jobs $jobs")
    lines = [
        "# Extinction test: $label",
        "",
        "- Verdict: $(v.verdict)",
        "- Bar: below $(fmt(100EXTINCTION_BAR))%, at 95% confidence",
        "- Upper limit on the chance of extinction: $(percent_text(v.limit))%",
        "- Extinct: $(v.extinct) of $finished seeds",
        "- Seeds finished: $finished of $seeds ($(seed_text(first_seed, seeds)))",
        "- Periods: $periods",
        "- Rules: `$(rules_line(rules))`",
        "- Falling at the end: $falling of $(length(living)) living seeds (fell more than 10%, " *
        "t = $(periods ÷ 2 + 1)–$(3periods ÷ 4) against t = $(3periods ÷ 4 + 1)–$periods)",
        "- Run time: $run_time",
    ]
    finished < seeds && push!(
        lines,
        "",
        "**Unfinished: $(seeds - finished) seeds have not run. The verdict covers only those finished.**",
    )
    2falling > length(living) && push!(
        lines,
        "",
        "**Most living seeds were falling at the end: this result says little about longer runs.**",
    )
    push!(
        lines,
        "",
        "| Seed | Lowest | Lowest at t | t = $(periods ÷ 4) | t = $(periods ÷ 2) | t = $(3periods ÷ 4) | " *
        "t = $periods | Extinct at | Births, last $w | Deaths, last $w | Mean, third quarter | " *
        "Mean, fourth quarter | Falling | Seconds |",
        "|" * "---|"^14,
    )
    for o in sort(collect(outcomes); by=o -> o.seed)
        push!(
            lines,
            "| $(o.seed) | $(fmt(o.lowest)) | $(o.lowest_t) | " *
            join((fmt(x) for x in o.at_quarters), " | ") *
            " | $(o.extinct_t === nothing ? "—" : o.extinct_t) | $(o.births_last) | $(o.deaths_last) | " *
            "$(fmt(o.mean_third)) | $(fmt(o.mean_fourth)) | $(is_falling(o) ? "yes" : "no") | " *
            "$(seconds_text(o.seconds)) |",
        )
    end
    return join(lines, "\n") * "\n"
end

"""`extinction-<label>-s<first>-<seeds>-p<periods>`: the folder and report name of an extinction run."""
function extinction_name(label, first_seed, seeds, periods)
    return "extinction-$label-s$first_seed-$seeds-p$periods"
end

"""
What an extinction run was produced from: the xxl fingerprint and the periods (`with_steps` keeps the original `steps=`
in the text).
"""
function extinction_fingerprint(exp::Experiment, rules::XxlRules, periods::Int)
    return xxl_fingerprint(exp, rules) * "periods=$periods\n"
end

function check_extinction_size(; seeds, first_seed, periods, jobs)
    seeds >= 1 || throw(ArgumentError("--seeds must be at least 1, not $seeds"))
    jobs >= 1 || throw(ArgumentError("--jobs must be at least 1, not $jobs"))
    first_seed >= 0 || throw(ArgumentError("--first-seed must be at least 0, not $first_seed"))
    periods >= 4 || throw(ArgumentError("--periods must be at least 4, not $periods"))
    return nothing
end

"""Writes `text` to a temporary file and moves it onto `path`, so a stop never leaves half a file there."""
function write_atomic(path::AbstractString, text::AbstractString)
    write(path * ".tmp", text)
    mv(path * ".tmp", path; force=true)
    return nothing
end

"""Whether a seed's CSV is whole: its header and periods + 1 rows, t = 0 to `periods`."""
seed_done(path::AbstractString, periods::Int) = isfile(path) && countlines(path) == periods + 2

"""Setup, stepping and metrics seconds of a seed's timing file; NaN if it is absent or unreadable."""
function timing_seconds(path::AbstractString)
    isfile(path) || return NaN
    lines = readlines(path)
    length(lines) == 2 || return NaN
    cells = Dict(zip(split(lines[1], ","), split(lines[2], ",")))
    return sum(something(tryparse(Float64, get(cells, c, "")), NaN) for c in ("setup_s", "stepping_s", "metrics_s"))
end

"""The seconds spent running so far, from the folder's `elapsed.txt`; `nothing` if it is absent or unreadable."""
function read_elapsed(folder::AbstractString)
    path = joinpath(folder, "elapsed.txt")
    return isfile(path) ? tryparse(Float64, strip(read(path, String))) : nothing
end

"""
    extinction_seed!(exp, k, rules, folder) -> SeedOutcome

Runs seed `k` of `exp` (already set to the run's periods) under `rules` and writes its timing file and its CSV, the
standard xxl columns with no scorecard ones, into `folder`. The CSV goes to a temporary name and is moved onto its own
only when whole. Runs in a worker.
"""
function extinction_seed!(exp::Experiment, k::Int, rules::XxlRules, folder::AbstractString)
    rows, timing, _ = seed_job(exp, k, false; xxl=rules)
    write_timing_csv(joinpath(folder, "seed$k.timing.csv"), [timing])
    columns = metric_columns(to_xxl(exp.config, rules))
    path = joinpath(folder, "seed$k.csv")
    write_seed_csv(path * ".tmp", rows; columns=columns)
    mv(path * ".tmp", path; force=true)
    seconds = timing.setup_s + timing.stepping_s + timing.metrics_s
    return seed_outcome(stack(rows; dims=1), ["t"; columns], k; seconds=seconds)
end

"""
Makes sure `folder` holds the run of `fingerprint`: creates it (writing the fingerprint) when new, otherwise throws
`ArgumentError` if its fingerprint differs or is missing. With `create` false, a missing folder is an error too.
"""
function check_extinction_folder(folder::AbstractString, fingerprint::AbstractString; create::Bool)
    path = joinpath(folder, "fingerprint.txt")
    if isfile(path)
        read(path, String) == fingerprint && return nothing
        throw(ArgumentError("$folder was made under other rules, code or periods; choose another --label"))
    end
    create || throw(ArgumentError("$folder has no results to report"))
    isdir(folder) && !isempty(readdir(folder)) && throw(
        ArgumentError("$folder has no fingerprint, so what it holds is unknown; choose another --label"),
    )
    mkpath(folder)
    write_atomic(path, fingerprint)
    return nothing
end

"""The outcomes of the seeds of `indices` that are done, in order, with their seconds from the timing files."""
function finished_outcomes(folder::AbstractString, indices, periods::Int)
    outcomes = SeedOutcome[]
    for k in indices
        path = joinpath(folder, "seed$k.csv")
        seed_done(path, periods) || continue
        header, M = read_seed_csv(path)
        seconds = timing_seconds(joinpath(folder, "seed$k.timing.csv"))
        push!(outcomes, seed_outcome(M, header, k; seconds=seconds))
    end
    return outcomes
end

"""Reads the finished seeds, writes the report beside the folder and prints it to `io`. Returns the verdict."""
function write_extinction_report(rules, folder; label, seeds, first_seed, periods, jobs, io)
    outcomes = finished_outcomes(folder, first_seed:(first_seed + seeds - 1), periods)
    report = extinction_report(
        outcomes; label=label, rules=rules, first_seed=first_seed, seeds=seeds, periods=periods, jobs=jobs,
        wall=read_elapsed(folder),
    )
    path = folder * ".md"
    write_atomic(path, report)
    println(io, "\n", report, "\n-> $path")
    flush(io)
    return extinction_verdict(outcomes)
end

"""One progress line: the seed just finished, `done` of `total`, and the hours left at this run's pace."""
function extinction_progress(o::SeedOutcome, fresh, periods, done, total, workers)
    left = (total - done) * mean_of([f.seconds for f in fresh]) / workers / 3600
    extinct = o.extinct_t === nothing ? "" : ", EXTINCT at t = $(o.extinct_t)"
    return "seed $(o.seed): $(seconds_text(o.seconds)) s ($(fmt(o.seconds / periods)) s per period), " *
           "lowest $(fmt(o.lowest)), end $(fmt(o.at_quarters[4]))$extinct; $done of $total done, " *
           "about $(round(left; digits=1)) h left"
end

"""
    run_extinction(rules; label="defaults", seeds=60, first_seed=20, periods=2000, jobs=10, out=RESULTS_XXL,
                   experiment=nothing, io=stdout) -> (; verdict, extinct, limit)

Runs seeds `first_seed` to `first_seed + seeds - 1` of VI-1 (or `experiment`, for tests) under `rules` over `periods`
into `<out>/<extinction_name>/`, then writes `<out>/<extinction_name>.md` and prints it. Each seed's CSV and timing file
are written as it ends; a seed whose CSV is whole (`periods + 2` lines) is skipped, so a stopped run resumes by running
again. A folder made under other rules, code or periods is refused (`ArgumentError`) before anything runs. With
`jobs > 1` the seeds run in that many worker processes. `elapsed.txt` adds the running time across resumes.
"""
function run_extinction(
    rules::XxlRules;
    label::AbstractString="defaults",
    seeds::Int=60,
    first_seed::Int=20,
    periods::Int=2000,
    jobs::Int=10,
    out::AbstractString=RESULTS_XXL,
    experiment::Union{Nothing,Experiment}=nothing,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    exp = with_steps(experiment === nothing ? find_experiment(load_registry(), "VI-1") : experiment, periods)
    folder = joinpath(out, extinction_name(label, first_seed, seeds, periods))
    check_extinction_folder(folder, extinction_fingerprint(exp, rules, periods); create=true)
    indices = first_seed:(first_seed + seeds - 1)
    todo = [k for k in indices if !seed_done(joinpath(folder, "seed$k.csv"), periods)]
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], "extinction $label")
        before, t0 = something(read_elapsed(folder), 0.0), time_ns()
        fresh = SeedOutcome[]
        guard = ReentrantLock()
        workers = jobs > 1 && length(todo) > 1 ? min(jobs, length(todo)) : 1
        function record!(o::SeedOutcome)
            lock(guard) do
                push!(fresh, o)
                write_atomic(joinpath(folder, "elapsed.txt"), string(before + seconds_since(t0)))
                done = seeds - length(todo) + length(fresh)
                println(io, extinction_progress(o, fresh, periods, done, seeds, workers))
                flush(io)
            end
        end
        if workers > 1
            procs = addprocs(workers)
            try
                remotecall_eval(Main, procs, :(using Sugarscape))
                pool = WorkerPool(procs)
                asyncmap(todo; ntasks=workers) do k
                    record!(remotecall_fetch(Sugarscape.extinction_seed!, pool, exp, k, rules, abspath(folder)))
                end
            finally
                rmprocs(procs)
            end
        else
            for k in todo
                record!(extinction_seed!(exp, k, rules, folder))
            end
        end
    end
    return write_extinction_report(rules, folder; label=label, seeds=seeds, first_seed=first_seed, periods=periods,
                                   jobs=jobs, io=io)
end

"""
    rebuild_extinction_report(rules; label, seeds, first_seed, periods, out=RESULTS_XXL, experiment=nothing,
                              jobs=nothing, io=stdout) -> (; verdict, extinct, limit)

Writes the report of an extinction run from the seeds it has finished, running nothing. `ArgumentError` if the folder is
absent or was made under other rules, code or periods, so a report cannot be rewritten under the wrong ones.
"""
function rebuild_extinction_report(
    rules::XxlRules;
    label::AbstractString,
    seeds::Int,
    first_seed::Int,
    periods::Int,
    out::AbstractString=RESULTS_XXL,
    experiment::Union{Nothing,Experiment}=nothing,
    jobs::Union{Nothing,Int}=nothing,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=something(jobs, 1))
    exp = with_steps(experiment === nothing ? find_experiment(load_registry(), "VI-1") : experiment, periods)
    folder = joinpath(out, extinction_name(label, first_seed, seeds, periods))
    check_extinction_folder(folder, extinction_fingerprint(exp, rules, periods); create=false)
    return write_extinction_report(rules, folder; label=label, seeds=seeds, first_seed=first_seed, periods=periods,
                                   jobs=jobs, io=io)
end

"""
    same_run(a, b; periods) -> Bool

Whether the seed CSVs `a` and `b` agree on every column of `a`, matched by name, for t = 0 to `periods` (compared with
`isequal`, as some cells are NaN). False if `b` lacks a column of `a`, or either has fewer rows than those periods.
"""
function same_run(a::AbstractString, b::AbstractString; periods::Int)
    (ha, Ma), (hb, Mb) = read_seed_csv(a), read_seed_csv(b)
    for M in (Ma, Mb)
        size(M, 1) > periods && M[1:(periods + 1), 1] == 0:periods || return false
    end
    for (i, name) in enumerate(ha)
        j = findfirst(==(name), hb)
        j === nothing && return false
        isequal(Ma[1:(periods + 1), i], Mb[1:(periods + 1), j]) || return false
    end
    return true
end

const EXTINCTION_USAGE = "usage: julia --project=julia julia/xxl_extinction.jl [--rules v1|defaults] [--label NAME] [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR] [--report-only]"

"""
The extinction test's command line: `--rules v1|defaults`, `--label NAME`, `--seeds N`, `--first-seed K`, `--periods P`,
`--jobs J`, `--out DIR` and `--report-only`. Throws `ArgumentError` on a usage error.
"""
function extinction_args(args::Vector{String})
    rules, label, report_only, out = "defaults", nothing, false, RESULTS_XXL
    seeds, first_seed, periods, jobs = 60, 20, 2000, 10
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--report-only"
            report_only = true
        elseif a in ("--rules", "--label", "--seeds", "--first-seed", "--periods", "--jobs", "--out")
            i += 1
            i <= length(args) || throw(ArgumentError("$a needs a value"))
            v = args[i]
            if a == "--rules"
                haskey(SCORECARD_BASES, v) || throw(ArgumentError("--rules is v1 or defaults, not $(repr(v))"))
                rules = v
            elseif a == "--label"
                label = v
            elseif a == "--seeds"
                seeds = parse(Int, v)
            elseif a == "--first-seed"
                first_seed = parse(Int, v)
            elseif a == "--periods"
                periods = parse(Int, v)
            elseif a == "--jobs"
                jobs = parse(Int, v)
            else
                out = v
            end
        else
            throw(ArgumentError("unexpected argument $a"))
        end
        i += 1
    end
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    return (; rules=SCORECARD_BASES[rules], label=something(label, rules), seeds, first_seed, periods, jobs, out,
            report_only)
end

"""
    extinction_main(args) -> exit code

The command line of julia/xxl_extinction.jl: runs [`run_extinction`](@ref), or with `--report-only`
[`rebuild_extinction_report`](@ref). Returns 2 on a usage error, a missing folder or a folder made under other rules; a
`FAIL` verdict is a result, so 0.
"""
function extinction_main(args::Vector{String})
    try
        a = extinction_args(args)
        if a.report_only
            rebuild_extinction_report(
                a.rules; label=a.label, seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, out=a.out,
            )
        else
            run_extinction(
                a.rules; label=a.label, seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, jobs=a.jobs,
                out=a.out,
            )
        end
        return 0
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, EXTINCTION_USAGE, "\n", e.msg)
        return 2
    end
end
