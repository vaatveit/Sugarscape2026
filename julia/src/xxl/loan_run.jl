# xxl: the loan trace's run and command line (docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md, "The
# runs"). VI-1 under one world, traced: the xxl defaults, the xl version or the book's own. It follows `run_extinction`
# (julia/xxl_loan_trace.jl is its command line) without the stop file or checkpoints: a traced seed can't be paused, so
# a stopped one runs again from period 0. A seed counts as done only with its CSV and its three trace files (see
# `trace_seed_done`), and the CSV is written last.

const TRACE_WORLDS = ("defaults", "xl", "book")
const TRACE_TERM = 10  # the term the tracer assumes with credit off, as the census follow-up needs one
const TRACE_CREDIT = (10, 10.0)  # VI-1's: a term of 10, a rate of 10

"""
    TraceWorld(name, credit, inheritance)

What a loan trace runs: `name` is `defaults` (VI-1 under `XXL_DEFAULTS`), `xl` (its xl version, no xxl rules) or `book`
(the registry's 50 × 50 VI-1, no xxl or xl layer); `credit` is the loan `(term, rate)` or `nothing` for none, and
`inheritance` whether a dead lender's loans pass to its heirs.
"""
struct TraceWorld
    name::String
    credit::Union{Nothing,Tuple{Int,Float64}}
    inheritance::Bool
    function TraceWorld(name, credit, inheritance)
        name in TRACE_WORLDS || throw(ArgumentError("--world is defaults, xl or book, not $(repr(name))"))
        return new(name, credit, inheritance)
    end
end

trace_rules(w::TraceWorld) = w.name == "defaults" ? XXL_DEFAULTS : nothing
trace_xl(w::TraceWorld) = w.name == "xl"

function world_text(w::TraceWorld)
    credit = w.credit === nothing ? "off" : "term $(w.credit[1]), rate $(w.credit[2])"
    return "$(w.name), credit $credit, inheritance $(w.inheritance)"
end

"""VI-1 (or `experiment`, for tests) over `periods`, with the world's credit and inheritance in both its configs."""
function trace_experiment(w::TraceWorld, periods::Int; experiment::Union{Nothing,Experiment}=nothing)
    e = experiment === nothing ? find_experiment(load_registry(), "VI-1") : experiment
    swap(cfg) = replace_config(cfg; credit=w.credit, inheritance=w.inheritance)
    return with_steps(
        Experiment(e.id, e.title, e.rules, e.steps, e.seeds, swap(e.config), e.fingerprint, swap(e.xl_config),
                   e.xl_fingerprint),
        periods,
    )
end

"""The config a seed runs: the xxl version for `defaults`, the xl version for `xl`, the experiment's own for `book`."""
function trace_config(w::TraceWorld, exp::Experiment)
    w.name == "defaults" && return to_xxl(exp.config, XXL_DEFAULTS)
    w.name == "xl" && return to_xl(exp.config)
    return exp.config
end

"""What a loan trace was produced from: the world's fingerprint, credit and inheritance, the code and the periods."""
function trace_fingerprint(exp::Experiment, w::TraceWorld, periods::Int)
    base = if w.name == "defaults"
        xxl_fingerprint(exp, XXL_DEFAULTS)
    elseif w.name == "xl"
        "julia\n" * exp.xl_fingerprint
    else
        "julia\n" * exp.fingerprint
    end
    return base * "world=$(w.name)\ncredit=$(w.credit)\ninheritance=$(w.inheritance)\n" *
           "code sha256=$(source_sha256(dirname(@__DIR__)))\nperiods=$periods\n"
end

"""`loans-<label>-s<first>-<seeds>-p<periods>`: the folder and report name of a loan trace."""
loan_name(label, first_seed, seeds, periods) = "loans-$label-s$first_seed-$seeds-p$periods"

"""
    loan_trace_seed!(exp, k, w, folder; write_files=write_trace_files) -> Float64

Runs seed `k` of `exp` (already set to the run's periods) in the world `w` with a [`LoanTrace`](@ref) of its loan term
(10 with credit off), and writes the trace files (`write_files(folder, k, tracer)`), the timing file and, last, the CSV,
to a temporary name moved onto its own only when whole. Returns the seconds the seed took. Runs in a worker.
"""
function loan_trace_seed!(
    exp::Experiment, k::Int, w::TraceWorld, folder::AbstractString; write_files=write_trace_files
)
    cfg = trace_config(w, exp)
    tr = LoanTrace(cfg.credit === nothing ? TRACE_TERM : first(cfg.credit))
    rows, timing, _ = seed_job(exp, k, trace_xl(w); xxl=trace_rules(w), loan_trace=tr)
    write_files(folder, k, tr)
    write_timing_csv(joinpath(folder, "seed$k.timing.csv"), [timing])
    path = joinpath(folder, "seed$k.csv")
    write_seed_csv(path * ".tmp", rows; columns=metric_columns(cfg))
    mv(path * ".tmp", path; force=true)
    return timing.setup_s + timing.stepping_s + timing.metrics_s
end

"""Removes whatever a stopped run left of seed `k`: its files and their temporary names."""
function remove_trace_seed(folder::AbstractString, k::Int)
    paths = [joinpath(folder, "seed$k.csv"), joinpath(folder, "seed$k.timing.csv")]
    append!(paths, trace_file(folder, k, kind) for kind in ("tally", "census", "loans"))
    for p in paths
        rm(p; force=true)
        rm(p * ".tmp"; force=true)
    end
    return nothing
end

"""The experiment of a loan trace, its folder and its fingerprint."""
function loan_plan(w::TraceWorld, experiment, out, label, first_seed, seeds, periods)
    exp = trace_experiment(w, periods; experiment=experiment)
    folder = joinpath(out, loan_name(label, first_seed, seeds, periods))
    return (; exp, folder, fingerprint=trace_fingerprint(exp, w, periods))
end

"""Reads the finished seeds, writes the report beside the folder and prints it to `io`. Returns the summary."""
function write_loan_report(w::TraceWorld, folder; label, seeds, first_seed, periods, jobs, io)
    s = loan_summary(folder, first_seed:(first_seed + seeds - 1), periods)
    report = loan_report(
        s; label=label, world=world_text(w), first_seed=first_seed, seeds=seeds, periods=periods, jobs=jobs,
        wall=read_elapsed(folder),
    )
    path = folder * ".md"
    write_atomic(path, report)
    println(io, "\n", report, "\n-> $path")
    flush(io)
    return s
end

"""
    run_loan_trace(w; label=w.name, seeds=10, first_seed=20, periods=2000, jobs=5, out=RESULTS_XXL, experiment=nothing,
                   io=stdout) -> summary

Runs seeds `first_seed` to `first_seed + seeds - 1` of VI-1 (or `experiment`, for tests) in the world `w` over
`periods`, traced, into `<out>/<loan_name>/`, then writes `<out>/<loan_name>.md` and prints it. A seed counts as done
only with its CSV and trace files, so a stopped run resumes by running again, rerunning from period 0 each seed that was
not done (its leftover files go first). A folder made under another world, credit, inheritance, code or periods is
refused (`ArgumentError`) before anything runs. With `jobs > 1` the seeds run in that many worker processes.
`elapsed.txt` adds the running time across resumes.
"""
function run_loan_trace(
    w::TraceWorld;
    label::AbstractString=w.name,
    seeds::Int=10,
    first_seed::Int=20,
    periods::Int=2000,
    jobs::Int=5,
    out::AbstractString=RESULTS_XXL,
    experiment::Union{Nothing,Experiment}=nothing,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    exp, folder, fingerprint = loan_plan(w, experiment, out, label, first_seed, seeds, periods)
    check_extinction_folder(folder, fingerprint; create=true)
    indices = first_seed:(first_seed + seeds - 1)
    todo = [k for k in indices if !trace_seed_done(folder, k, periods)]
    foreach(k -> remove_trace_seed(folder, k), todo)
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], "loan trace $label")
        before, t0 = something(read_elapsed(folder), 0.0), time_ns()
        fresh = SeedOutcome[]
        guard = ReentrantLock()
        workers = jobs > 1 && length(todo) > 1 ? min(jobs, length(todo)) : 1
        function record!(k::Int)
            o = only(finished_outcomes(folder, [k], periods))
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
                    remotecall_fetch(Sugarscape.loan_trace_seed!, pool, exp, k, w, abspath(folder))
                    record!(k)
                    return nothing
                end
            finally
                rmprocs(procs)
            end
        else
            for k in todo
                loan_trace_seed!(exp, k, w, folder)
                record!(k)
            end
        end
    end
    return write_loan_report(w, folder; label=label, seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs,
                             io=io)
end

"""
    rebuild_loan_report(w; label, seeds, first_seed, periods, out=RESULTS_XXL, experiment=nothing, io=stdout)

Writes the report of a loan trace from the seeds it has finished, running nothing. `ArgumentError` if the folder is
absent or was made under another world, credit, inheritance or periods. Code that has changed since is only warned of
(to `io`).
"""
function rebuild_loan_report(
    w::TraceWorld;
    label::AbstractString,
    seeds::Int,
    first_seed::Int,
    periods::Int,
    out::AbstractString=RESULTS_XXL,
    experiment::Union{Nothing,Experiment}=nothing,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=1)
    _, folder, fingerprint = loan_plan(w, experiment, out, label, first_seed, seeds, periods)
    check_extinction_folder(folder, fingerprint; create=false, warn_io=io)
    return write_loan_report(w, folder; label=label, seeds=seeds, first_seed=first_seed, periods=periods, jobs=nothing,
                             io=io)
end

# ---- the comparison

const LOAN_FOLDER = r"^loans-.+-s(\d+)-(\d+)-p(\d+)$"

"""A loan trace folder of `out` for the comparison: its seeds that are done, its periods and whether credit was off."""
function compare_folder(out::AbstractString, name::AbstractString)
    folder = joinpath(out, name)
    m = match(LOAN_FOLDER, name)
    m === nothing && throw(ArgumentError("$name is not a loan trace folder"))
    path = joinpath(folder, "fingerprint.txt")
    isfile(path) || throw(ArgumentError("$folder has no results to compare"))
    first_seed, seeds, periods = parse.(Int, m.captures)
    done = Set(k for k in first_seed:(first_seed + seeds - 1) if trace_seed_done(folder, k, periods))
    return (; name, folder, periods, done, credit_off=occursin(r"^credit=nothing$"m, read(path, String)))
end

"""The figures of the seeds `shared` of a compared folder, cut to its first `periods` periods and the windows `ws`."""
function compare_figures(f, shared, periods::Int, ws)
    tallies = [read_tally(trace_file(f.folder, k, "tally")) for k in shared]
    t = merge_tallies(tallies)
    census = merge_census([read_census(trace_file(f.folder, k, "census")) for k in shared])
    x8s = filter(!isnan, [x8_share(tl, filter(<=(2), ws)) for tl in tallies])
    births, troughs, ends = Float64[], Float64[], Float64[]
    for k in shared
        header, M = read_seed_csv(joinpath(f.folder, "seed$k.csv"))
        M = M[1:(periods + 1), :]
        pop, ever = (findfirst(==(name), header) for name in ("population", "agents_ever"))
        push!(births, M[end, ever] - M[1, ever])
        push!(troughs, minimum(M[2:end, pop]))
        push!(ends, M[end, pop])
    end
    age = age_ratios(t, census, ws)
    return (;
        x8=isempty(x8s) ? NaN : mean_of(x8s),
        started=tsum(t, ws, "started"),
        borrower=age.borrower,
        lender=age.lender,
        births=mean_of(births),
        trough=mean_of(troughs),
        population=mean_of(ends),
    )
end

"""
    loan_compare(out, base, others; periods) -> String

One table of the loan trace folders `base` and `others` (names under `out`), a row each, over the seeds finished in all
of them and the first `periods` periods: X8 over t = 1–500, the loans started, the age ratios, the births (the change in
`agents_ever`), the trough and the end population, the last three from each seed's CSV and averaged over seeds. The loan
figures are by whole window (so t = 1–500 for any `periods` up to 500: the windows from 501 on are left out); a folder
that ran more periods is cut, one that ran fewer is refused. For a folder with credit off the table is followed by
[`credit_off_reading`](@ref) against `base`, where it fires. Written to `<out>/loans-compare.md`.
"""
function loan_compare(out::AbstractString, base::AbstractString, others; periods::Int)
    folders = [compare_folder(out, n) for n in (base, others...)]
    for f in folders
        f.periods >= periods ||
            throw(ArgumentError("$(f.name) ran $(f.periods) periods, fewer than the $periods compared"))
    end
    shared = sort!(collect(intersect((f.done for f in folders)...)))
    isempty(shared) && throw(ArgumentError("these folders have no finished seed in common"))
    ws = [w for (w, from) in enumerate((0, 100, 500)) if from < periods]
    figures = [compare_figures(f, shared, periods, ws) for f in folders]
    lines = [
        "# Loan trace comparison",
        "",
        "- Base: $base",
        "- Seeds: $(join(shared, ", ")) ($(length(shared)) in all)",
        "- Periods: $periods",
        "",
        "| Run | X8, t = 1–500 | Loans started | Age ratio, borrowers | Age ratio, lenders | Births | Trough | " *
        "End population |",
        "|" * "---|"^8,
    ]
    for (f, x) in zip(folders, figures)
        push!(
            lines,
            "| $(f.name) | $(num(x.x8)) | $(count_text(x.started)) | $(num(x.borrower)) | $(num(x.lender)) | " *
            "$(num(x.births)) | $(num(x.trough)) | $(num(x.population)) |",
        )
    end
    readings = String[]
    for (f, x) in zip(folders[2:end], figures[2:end])
        f.credit_off || continue
        line = credit_off_reading(figures[1], x)
        line === nothing || push!(readings, "- $(f.name): $line")
    end
    isempty(readings) || push!(lines, "", readings...)
    text = join(lines, "\n") * "\n"
    write_atomic(joinpath(out, "loans-compare.md"), text)
    return text
end

# ---- the command line

const LOAN_USAGE = "usage: julia --project=julia julia/xxl_loan_trace.jl [--world defaults|xl|book] [--term D] [--no-credit] [--inheritance] [--label NAME] [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR] [--report-only] [--compare BASE,A,B]"

"""
The loan trace's command line: `--world defaults|xl|book`, `--term D` (the loan term, keeping the rate 10),
`--no-credit`, `--inheritance`, `--label NAME` (the world's name), `--seeds N` (10), `--first-seed K` (20),
`--periods P` (2000), `--jobs J` (5), `--out DIR`, `--report-only` and `--compare BASE,A,B,…`. Throws `ArgumentError` on
a usage error.
"""
function loan_trace_args(args::Vector{String})
    world, term, credit, inheritance, label = "defaults", nothing, true, false, nothing
    seeds, first_seed, periods, jobs, out, report_only, compare = 10, 20, 2000, 5, RESULTS_XXL, false, nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--no-credit"
            credit = false
        elseif a == "--inheritance"
            inheritance = true
        elseif a == "--report-only"
            report_only = true
        elseif a in ("--world", "--term", "--label", "--seeds", "--first-seed", "--periods", "--jobs", "--out",
                     "--compare")
            i += 1
            i <= length(args) || throw(ArgumentError("$a needs a value"))
            v = args[i]
            if a == "--world"
                world = v
            elseif a == "--term"
                term = parse(Int, v)
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
            elseif a == "--out"
                out = v
            else
                compare = String.(split(v, ","))
            end
        else
            throw(ArgumentError("unexpected argument $a"))
        end
        i += 1
    end
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    term === nothing || credit || throw(ArgumentError("--term and --no-credit don't combine"))
    term === nothing || 1 <= term < CENSUS_EVERY - 1 ||
        throw(ArgumentError("--term must be from 1 to $(CENSUS_EVERY - 2), not $term"))
    compare === nothing || !any(isempty, compare) || throw(ArgumentError("--compare takes folder names, BASE,A,B"))
    w = TraceWorld(world, credit ? (something(term, TRACE_CREDIT[1]), TRACE_CREDIT[2]) : nothing, inheritance)
    return (; w, label=something(label, world), seeds, first_seed, periods, jobs, out, report_only, compare)
end

"""
    loan_trace_main(args) -> exit code

The command line of julia/xxl_loan_trace.jl: runs [`run_loan_trace`](@ref), with `--report-only`
[`rebuild_loan_report`](@ref), or with `--compare` [`loan_compare`](@ref) (cut to `--periods`). Returns 2 on a usage
error, a missing folder or a folder made under another world; anything that goes wrong after is thrown with its stack
trace.
"""
function loan_trace_main(args::Vector{String})
    a = try
        a = loan_trace_args(args)
        if a.compare !== nothing
            print(loan_compare(a.out, a.compare[1], a.compare[2:end]; periods=a.periods))
            return 0
        end
        _, folder, fingerprint = loan_plan(a.w, nothing, a.out, a.label, a.first_seed, a.seeds, a.periods)
        # The run and the rebuild check the folder again; checking it here makes a refusal a usage error.
        check_extinction_folder(folder, fingerprint; create=!a.report_only, warn_io=a.report_only ? devnull : nothing)
        a
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, LOAN_USAGE, "\n", e.msg)
        return 2
    end
    if a.report_only
        rebuild_loan_report(a.w; label=a.label, seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, out=a.out)
    else
        run_loan_trace(
            a.w; label=a.label, seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, jobs=a.jobs, out=a.out,
        )
    end
    return 0
end
