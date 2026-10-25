# Runs registered experiments over several seeds and writes the Python runner's results layout
# (experiments/run.py): seed{k}.csv per seed, timing.csv, machine.txt and fingerprint.txt.

const TIMING_COLUMNS = [
    "seed", "periods", "setup_s", "stepping_s", "metrics_s", "agents_start", "agents_end"
]
const RESULTS = "results-julia"
const RESULTS_XL = "results-julia-xl"

"""The id itself, else its sweep points ("II-5" -> "II-5/..."), as `experiments.run.matching_ids`."""
function matching_ids(arg::AbstractString, ids)
    arg in ids && return [String(arg)]
    return [String(i) for i in ids if startswith(i, arg * "/")]
end

result_dir(out::AbstractString, id::AbstractString) = joinpath(out, replace(id, "/" => "_"))

"""A value as Python's `float()` and `experiments.run._parse` read it back."""
format_value(x::Integer) = string(x)
function format_value(x::AbstractFloat)
    isnan(x) && return "nan"
    isinf(x) && return x > 0 ? "inf" : "-inf"
    return string(Float64(x))
end

seconds_since(t0::UInt64) = (time_ns() - t0) / 1e9

"""
    timed_seed(exp, k; xl=false) -> (rows, timing)

Seed k of an experiment (or its xl version), timed as `experiments.run.timed_seed` divides the work (docs/xl.md,
"Timing"): building the model, the model's own steps, and collecting each period's metrics, t = 0 included. Each
row is `t` followed by the metrics in `METRIC_COLUMNS` order.
"""
function timed_seed(exp::Experiment, k::Int; xl::Bool=false)
    cfg = xl ? to_xl(exp.config) : exp.config
    t0 = time_ns()
    m = Model(replace_config(cfg; seed=cfg.seed + k))
    setup = seconds_since(t0)
    agents_start = length(m.agents)
    rows = Vector{Vector{Float64}}()
    stepping = measuring = 0.0
    for period in 0:(exp.steps)
        if period > 0
            t0 = time_ns()
            step!(m)
            stepping += seconds_since(t0)
        end
        t0 = time_ns()
        push!(rows, pushfirst!(collect_metrics(m), m.t))
        measuring += seconds_since(t0)
    end
    timing = (
        seed=k,
        periods=exp.steps,
        setup_s=setup,
        stepping_s=stepping,
        metrics_s=measuring,
        agents_start=agents_start,
        agents_end=length(m.agents),
    )
    return rows, timing
end

const WARMED = Set{String}()

"""
    warm_up!(exp) -> seconds

Compiles this experiment's code paths before any timed seed, by running its regular config for 2 untimed periods
with metrics, once per experiment per process (design, "Warm-up"; a different experiment may use rules not yet
compiled). Returns the seconds it took, 0.0 when already warm.
"""
function warm_up!(exp::Experiment)
    exp.id in WARMED && return 0.0
    t0 = time_ns()
    to_xl(exp.config)  # compile the timed seed's own path: to_xl, replace_config(; seed), Model, step!, metrics
    m = Model(replace_config(exp.config; seed=exp.config.seed))
    pushfirst!(collect_metrics(m), m.t)
    for _ in 1:2
        step!(m)
        pushfirst!(collect_metrics(m), m.t)
    end
    push!(WARMED, exp.id)
    return seconds_since(t0)
end

"""One seed in a worker: warm up first, name the experiment and seed in any error."""
function seed_job(exp::Experiment, k::Int, xl::Bool, run_seed=timed_seed)
    try
        warm = warm_up!(exp)
        rows, timing = run_seed(exp, k; xl=xl)
        return rows, timing, warm
    catch e
        error("$(exp.id) seed $k failed: $(sprint(showerror, e))")
    end
end

"""
    run_experiment(exp; seeds=exp.seeds, jobs=1, out=RESULTS, xl=false, note="", run_seed=timed_seed)

Runs seeds 0..seeds-1 and only then replaces the folder's results, so a failed run leaves the old ones. With
`jobs > 1`, seeds run in that many worker processes, one seed at a time each (one core per seed).
"""
function run_experiment(
    exp::Experiment;
    seeds::Int=exp.seeds,
    jobs::Int=1,
    out::AbstractString=RESULTS,
    xl::Bool=false,
    note::AbstractString="",
    run_seed=timed_seed,
)
    if jobs > 1 && seeds > 1
        workers = addprocs(min(jobs, seeds))
        try
            remotecall_eval(Main, workers, :(using Sugarscape))
            pool = WorkerPool(workers)
            results = pmap(
                k -> Sugarscape.seed_job(exp, k, xl, run_seed), pool, 0:(seeds - 1)
            )
        finally
            rmprocs(workers)
        end
    else
        results = [seed_job(exp, k, xl, run_seed) for k in 0:(seeds - 1)]
    end
    folder = mkpath(result_dir(out, exp.id))
    for old in readdir(folder)
        occursin(r"^seed\d+\.csv$", old) && rm(joinpath(folder, old))
    end
    for (k, (rows, _, _)) in enumerate(results)
        write_seed_csv(joinpath(folder, "seed$(k - 1).csv"), rows)
    end
    write_timing_csv(joinpath(folder, "timing.csv"), [timing for (_, timing, _) in results])
    write(
        joinpath(folder, "fingerprint.txt"),
        "julia\n" * (xl ? exp.xl_fingerprint : exp.fingerprint),
    )
    warm = [w for (_, _, w) in results if w > 0]
    write_machine_note(joinpath(folder, "machine.txt"), jobs, warm, note)
    return folder
end

function write_seed_csv(path::AbstractString, rows)
    open(path, "w") do io
        println(io, "t,", join(METRIC_COLUMNS, ","))
        for row in rows
            print(io, format_value(Int(row[1])))
            for v in @view row[2:end]
                print(io, ",", format_value(v))
            end
            println(io)
        end
    end
end

function write_timing_csv(path::AbstractString, timings)
    open(path, "w") do io
        println(io, join(TIMING_COLUMNS, ","))
        for t in timings
            println(
                io,
                join((format_value(getfield(t, Symbol(c))) for c in TIMING_COLUMNS), ","),
            )
        end
    end
end

"""Where and how the timings were taken."""
function write_machine_note(
    path::AbstractString, jobs::Int, warm::Vector{Float64}, note::AbstractString
)
    lines = [
        "julia = $(VERSION)",
        "platform = $(Sys.KERNEL) $(Sys.MACHINE)",
        "processor = $(strip(Sys.cpu_info()[1].model))",
        "jobs = $jobs",
        "threads = $(Threads.nthreads())",
        "warm_up_s = $(join((format_value(w) for w in warm), ","))",
    ]
    jobs > 1 && push!(lines, "note = timings taken with --jobs $jobs share the processor")
    isempty(note) || push!(lines, "user_note = $note")
    write(path, join(lines, "\n") * "\n")
    return nothing
end

const USAGE = "usage: julia --project=julia julia/run.jl <id-or-prefix> [--seeds N] [--jobs J] [--out DIR] [--xl] [--note TEXT]"

"""
    main(args) -> exit code

The command line of julia/run.jl, mirroring `python -m experiments.run`. Returns 2 on a usage error.
"""
function main(args::Vector{String})
    id = nothing
    seeds = nothing
    jobs, out, xl, note = 1, nothing, false, ""
    i = 1
    try
        while i <= length(args)
            a = args[i]
            if a == "--xl"
                xl = true
            elseif a in ("--seeds", "--jobs", "--out", "--note")
                i += 1
                i <= length(args) || throw(ArgumentError("$a needs a value"))
                v = args[i]
                a == "--seeds" && (seeds = parse(Int, v))
                a == "--jobs" && (jobs = parse(Int, v))
                a == "--out" && (out = v)
                a == "--note" && (note = v)
            elseif startswith(a, "--") || id !== nothing
                throw(ArgumentError("unexpected argument $a"))
            else
                id = a
            end
            i += 1
        end
        id === nothing && throw(ArgumentError("an experiment id is required"))
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, USAGE, "\n", e.msg)
        return 2
    end
    reg = load_registry()
    ids = matching_ids(id, [e.id for e in reg])
    if isempty(ids)
        println(stderr, USAGE, "\nno experiment matches $(repr(id))")
        return 2
    end
    out = out === nothing ? (xl ? RESULTS_XL : RESULTS) : out
    for exp_id in ids
        exp = find_experiment(reg, exp_id)
        folder = run_experiment(
            exp; seeds=something(seeds, exp.seeds), jobs=jobs, out=out, xl=xl, note=note
        )
        println("$exp_id: $(something(seeds, exp.seeds)) seeds -> $folder")
    end
    return 0
end
