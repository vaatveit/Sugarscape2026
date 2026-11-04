# xxl (stage 5): the trade study's run and command line (docs/superpowers/specs/2026-11-03-xxl-trade-design.md). One arm of
# the study: VI-1 (or IV-A3) under one rule set, with the trade readings (julia/src/xxl/trade_readings.jl) kept for each
# seed, and the xl reference VI-1 the scorecard keeps. It follows `run_loan_trace` (julia/xxl_trade_study.jl is its command
# line): a seed with the observer can't be paused, so a stopped one runs again from period 0, and the folder is
# the extinction test's own, so `read_list_run` reads it.

const TRADE_EXPERIMENTS = ("VI-1", "IV-A3")  # the experiments the study runs
const TRADE_SNAPSHOT = 100  # the agent snapshot covers the last this many periods

"""The periods of the agent snapshot: the last [`TRADE_SNAPSHOT`](@ref) of the run, t = 401–500 for 500 periods."""
trade_window(periods::Int) = (max(1, periods - TRADE_SNAPSHOT + 1), periods)

"""`trade-<label>-<experiment, with / as _>-s<first>-<seeds>-p<periods>`: the folder name of a study arm."""
function trade_name(label, experiment, first_seed, seeds, periods)
    return "trade-$label-$(replace(experiment, "/" => "_"))-s$first_seed-$seeds-p$periods"
end

"""
What a study arm was produced from: the extinction run's fingerprint (rules, credit options, trade off, code, periods)
and a last line naming the readings' window.
"""
function trade_fingerprint(exp::Experiment, rules::XxlRules, periods::Int, options::CreditOptions)
    lo, hi = trade_window(periods)
    return extinction_fingerprint(exp, rules, periods; options=options) * "trade readings: window=($lo, $hi)\n"
end

trade_path(folder::AbstractString, k::Int, kind::AbstractString) = joinpath(folder, "seed$k-$kind.csv")

"""Writes a table (`header`, `rows` of numbers) as CSV through a temporary name, so a stop never leaves half a file. The first column is a whole number."""
function write_table_csv(path::AbstractString, header, rows)
    open(path * ".tmp", "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join([format_value(Int(row[1])); [format_value(v) for v in @view row[2:end]]], ","))
        end
    end
    mv(path * ".tmp", path; force=true)
    return nothing
end

"""
Whether seed `k` of a study arm is whole: its standard CSV (`periods + 1` rows, t = 0 to `periods`), its trade table (a row
for each period from 1, so `periods + 1` lines with the header) and its agent snapshot are all there. The CSV is written
last, each file through a temporary name.
"""
function trade_seed_done(folder::AbstractString, k::Int, periods::Int)
    seed_done(joinpath(folder, "seed$k.csv"), periods) || return false
    seed_done(trade_path(folder, k, "trade"), periods - 1) || return false  # `seed_done` counts rows from t = 0
    return isfile(trade_path(folder, k, "agents"))
end

"""Removes whatever a stopped run left of seed `k`: its files and their temporary names."""
function remove_trade_seed(folder::AbstractString, k::Int)
    for p in (joinpath(folder, "seed$k.csv"), joinpath(folder, "seed$k.timing.csv"), trade_path(folder, k, "trade"),
              trade_path(folder, k, "agents"))
        rm(p; force=true)
        rm(p * ".tmp"; force=true)
    end
    return nothing
end

"""
    trade_seed!(exp, k, rules, folder, window) -> SeedOutcome

Runs seed `k` of `exp` (already set to the run's periods) under `rules` with a [`TradeReadings`](@ref) of `window`, and writes
`seed<k>-agents.csv`, `seed<k>-trade.csv`, `seed<k>.timing.csv` and, last, `seed<k>.csv` (the extinction run's columns),
each through a temporary name. The observer is made here, so that a worker has its own. Runs in a worker.
"""
function trade_seed!(exp::Experiment, k::Int, rules::XxlRules, folder::AbstractString, window::Tuple{Int,Int})
    readings = TradeReadings(; window=window)
    rows, timing, _ = seed_job(exp, k, false; xxl=rules, trade_readings=readings)
    header, trade = trade_rows(readings)
    write_table_csv(trade_path(folder, k, "trade"), header, trade)
    header, agents = agent_rows(readings)
    write_table_csv(trade_path(folder, k, "agents"), header, agents)
    write_timing_csv(joinpath(folder, "seed$k.timing.csv"), [timing])
    columns = metric_columns(to_xxl(exp.config, rules))
    path = joinpath(folder, "seed$k.csv")
    write_seed_csv(path * ".tmp", rows; columns=columns)
    mv(path * ".tmp", path; force=true)
    seconds = timing.setup_s + timing.stepping_s + timing.metrics_s
    return seed_outcome(stack(rows; dims=1), ["t"; columns], k; seconds=seconds)
end

"""The experiment of a study arm (`experiment` over `periods`, the credit `options` set), its folder and its fingerprint."""
function trade_plan(
    rules::XxlRules, experiment::AbstractString, out, label, first_seed, seeds, periods; options::CreditOptions=CreditOptions()
)
    experiment in TRADE_EXPERIMENTS ||
        throw(ArgumentError("--experiment is $(join(TRADE_EXPERIMENTS, " or ")), not $(repr(experiment))"))
    exp = with_options(with_steps(find_experiment(load_registry(), experiment), periods), options)
    to_xxl(exp.config, rules)  # rules the experiment refuses fail here, before a folder is made
    folder = joinpath(out, trade_name(label, experiment, first_seed, seeds, periods))
    return (; exp, folder, fingerprint=trade_fingerprint(exp, rules, periods, options))
end

"""
    run_trade_arm(rules; label, experiment="VI-1", options=CreditOptions(), seeds=20, first_seed=80, periods=500, jobs=1,
                  out=RESULTS_XXL, io=stdout) -> String

Runs seeds `first_seed` to `first_seed + seeds - 1` of `experiment` (VI-1 or IV-A3) under `rules` over `periods`, with
the trade readings, into `<out>/trade-<label>-<experiment>-s<first>-<seeds>-p<periods>/` and returns that folder. Each seed
leaves `seed<k>.csv` (the extinction run's columns, so [`read_list_run`](@ref) reads the folder), `seed<k>-trade.csv`,
`seed<k>-agents.csv` and `seed<k>.timing.csv`; the readings' window is the last [`TRADE_SNAPSHOT`](@ref) periods. A seed
with all of them is skipped, so a stopped study resumes by running again, any seed cut short running from period 0 (the
observer can't be paused). A folder made under other rules, credit options, trade setting, code or periods is refused
(`ArgumentError`) before anything runs. With `jobs > 1` the seeds run in that many worker processes.
"""
function run_trade_arm(
    rules::XxlRules;
    label::AbstractString,
    experiment::AbstractString="VI-1",
    options::CreditOptions=CreditOptions(),
    seeds::Int=20,
    first_seed::Int=80,
    periods::Int=500,
    jobs::Int=1,
    out::AbstractString=RESULTS_XXL,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    exp, folder, fingerprint = trade_plan(rules, experiment, out, label, first_seed, seeds, periods; options)
    check_extinction_folder(folder, fingerprint; create=true)
    window = trade_window(periods)
    todo = [k for k in first_seed:(first_seed + seeds - 1) if !trade_seed_done(folder, k, periods)]
    foreach(k -> remove_trade_seed(folder, k), todo)
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], "trade study $label")
        fresh = SeedOutcome[]
        guard = ReentrantLock()
        workers = jobs > 1 && length(todo) > 1 ? min(jobs, length(todo)) : 1
        function record!(o::SeedOutcome)
            lock(guard) do
                push!(fresh, o)
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
                    record!(remotecall_fetch(Sugarscape.trade_seed!, pool, exp, k, rules, abspath(folder), window))
                    return nothing
                end
            finally
                rmprocs(procs)
            end
        else
            for k in todo
                record!(trade_seed!(exp, k, rules, folder, window))
            end
        end
    end
    return folder
end

"""
The folder of the xl reference for `exp` over `periods`: the scorecard's own (`<out>/scorecard-xl-s<first>-<seeds>/<id>`,
see [`scorecard_name`](@ref)) when `periods` is the experiment's registry steps, else beside it with `-p<periods>` added to
the name, so that the scorecard's runs are only ever written at their own length.
"""
function trade_xl_folder(out::AbstractString, exp::Experiment, first_seed::Int, seeds::Int, periods::Int)
    name = scorecard_name("xl", first_seed, seeds)
    periods == find_experiment(load_registry(), exp.id).steps || (name *= "-p$periods")
    return result_dir(joinpath(out, name), exp.id)
end

"""
    run_trade_xl(; first_seed=80, seeds=20, periods=500, jobs=1, out=RESULTS_XXL, io=stdout) -> String

The study's xl reference: VI-1's xl version over `periods`, seeds `first_seed` to `first_seed + seeds - 1`, into the
folder the scorecard keeps its xl runs in ([`trade_xl_folder`](@ref); for `periods` other than VI-1's 500 a folder of its
own), skipped when that folder already holds them ([`xl_current`](@ref)). Returns the folder.
"""
function run_trade_xl(;
    first_seed::Int=80, seeds::Int=20, periods::Int=500, jobs::Int=1, out::AbstractString=RESULTS_XXL, io::IO=stdout
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    exp = with_steps(find_experiment(load_registry(), "VI-1"), periods)
    folder = trade_xl_folder(out, exp, first_seed, seeds, periods)
    if xl_current(folder, exp, first_seed:(first_seed + seeds - 1))
        println(io, "$(exp.id) xl: reusing $folder")
    else
        t0 = time_ns()
        run_experiment(exp; seeds=seeds, first_seed=first_seed, jobs=jobs, out=dirname(folder), xl=true)
        println(io, "$(exp.id) xl: $seeds seeds -> $folder ($(round(Int, seconds_since(t0))) s)")
    end
    flush(io)
    return folder
end

const TRADE_USAGE = "usage: julia --project=julia julia/xxl_trade_study.jl --label NAME [--set field=value]... [--trade-off] [--experiment VI-1|IV-A3] [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]\n       julia --project=julia julia/xxl_trade_study.jl --xl [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]"

"""
The study's command line: `--label NAME` (required for an arm; a name, without `/` or `\\`), repeated `--set
field=value` (any [`XxlRules`](@ref) field of the xxl defaults, read as the scorecard reads it, by
[`rule_setting`](@ref)), `--trade-off` (a [`CreditOptions`](@ref) in `options`), `--experiment VI-1|IV-A3`, `--seeds N`
(20), `--first-seed K` (80), `--periods P` (500), `--jobs J` (1) and `--out DIR`; or `--xl`, the xl reference, which
takes only the last four and `--seeds`. Throws `ArgumentError` on a usage error.
"""
function trade_study_args(args::Vector{String})
    sets, label, xl, trade_off, experiment = Pair{Symbol,Any}[], nothing, false, false, "VI-1"
    seeds, first_seed, periods, jobs, out = 20, 80, 500, 1, RESULTS_XXL
    arm_only = String[]  # the options an xl run has no use for
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--xl"
            xl = true
        elseif a == "--trade-off"
            trade_off = true
            push!(arm_only, a)
        elseif a in ("--set", "--label", "--experiment", "--seeds", "--first-seed", "--periods", "--jobs", "--out")
            i += 1
            i <= length(args) || throw(ArgumentError("$a needs a value"))
            v = args[i]
            if a == "--set"
                push!(sets, rule_setting(v))
            elseif a == "--label"
                # a name in the folder's name, so no path
                (occursin(r"[/\\]", v) || isempty(v)) && throw(ArgumentError("--label is a name, not $(repr(v))"))
                label = v
            elseif a == "--experiment"
                experiment = v
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
            a in ("--set", "--label", "--experiment") && push!(arm_only, a)
        else
            throw(ArgumentError("unexpected argument $a"))
        end
        i += 1
    end
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    if xl
        isempty(arm_only) || throw(ArgumentError("--xl runs the xl reference; not with $(join(unique(arm_only), ", "))"))
    else
        label === nothing && throw(ArgumentError("--label is required"))
        experiment in TRADE_EXPERIMENTS ||
            throw(ArgumentError("--experiment is $(join(TRADE_EXPERIMENTS, " or ")), not $(repr(experiment))"))
    end
    return (; rules=replace_rules(XXL_DEFAULTS; sets...), label, options=CreditOptions(; trade_off), experiment, xl,
            seeds, first_seed, periods, jobs, out)
end

"""
    trade_study_main(args) -> exit code

The command line of julia/xxl_trade_study.jl: runs [`run_trade_arm`](@ref), or with `--xl` [`run_trade_xl`](@ref). Returns
1 after printing the usage on a usage error: the arguments, rules the experiment refuses, or a folder made under other
rules; anything that goes wrong after is thrown with its stack trace.
"""
function trade_study_main(args::Vector{String})
    a = try
        a = trade_study_args(args)
        # The run checks the folder again; checking it here makes a refusal a usage error.
        if !a.xl
            _, folder, fingerprint = trade_plan(
                a.rules, a.experiment, a.out, a.label, a.first_seed, a.seeds, a.periods; options=a.options,
            )
            check_extinction_folder(folder, fingerprint; create=true)
        end
        a
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, TRADE_USAGE, "\n", e.msg)
        return 1
    end
    if a.xl
        run_trade_xl(; seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, jobs=a.jobs, out=a.out)
    else
        folder = run_trade_arm(
            a.rules; label=a.label, experiment=a.experiment, options=a.options, seeds=a.seeds, first_seed=a.first_seed,
            periods=a.periods, jobs=a.jobs, out=a.out,
        )
        println("-> $folder")
    end
    return 0
end
