# xxl (stage 6): the sex study's run and command line. VI-1 in three worlds (the book's, the xl one and today's xxl
# defaults), with the sex readings (julia/src/xxl/sex_readings.jl) kept for each seed. It follows `run_trade_arm`
# (julia/xxl_sex_study.jl is its command line): a seed with the observer can't be paused, so a stopped one runs again
# from period 0.

const SEX_WORLDS = ("book", "xl", "today")  # the worlds the study runs

"""The periods of the agent snapshot: the last [`SEX_WINDOW`](@ref) of the run."""
sex_window(periods::Int) = (max(1, periods - SEX_WINDOW + 1), periods)

"""`sex-<world>-VI-1-s<first>-<seeds>-p<periods>`: the folder name of a world's run."""
sex_name(world, first_seed, seeds, periods) = "sex-$world-VI-1-s$first_seed-$seeds-p$periods"

sex_path(folder::AbstractString, k::Int, kind::AbstractString) = joinpath(folder, "seed$k-$kind.csv")

"""
What a world's run was produced from. Today's is the extinction run's fingerprint; the book's and the xl one's are the
registry's own text (which keeps its `steps=` line), then the code's checksum and the periods as the extinction
fingerprint writes them (the `periods=` line governs). Each ends with a line naming the world and the readings' window.
"""
function sex_fingerprint(exp::Experiment, world::AbstractString, periods::Int)
    lo, hi = sex_window(periods)
    text = if world == "today"
        extinction_fingerprint(exp, XXL_DEFAULTS, periods)
    else
        base = world == "book" ? exp.fingerprint : exp.xl_fingerprint
        endswith(base, "\n") || (base *= "\n")
        base * "code sha256=$(source_sha256(dirname(@__DIR__)))\nperiods=$periods\n"
    end
    return text * "sex readings: world=$world window=($lo, $hi)\n"
end

"""The experiment of a world's run (VI-1 over `periods`), its folder and its fingerprint. Refuses another world."""
function sex_plan(world::AbstractString, out, first_seed, seeds, periods)
    world in SEX_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    exp = with_steps(find_experiment(load_registry(), "VI-1"), periods)
    folder = joinpath(out, sex_name(world, first_seed, seeds, periods))
    return (; exp, folder, fingerprint=sex_fingerprint(exp, world, periods))
end

"""Whether seed `k` is whole: its CSV and its sex table (`periods + 1` rows each), its agent table and its timing file."""
function sex_seed_done(folder::AbstractString, k::Int, periods::Int)
    seed_done(joinpath(folder, "seed$k.csv"), periods) || return false
    seed_done(sex_path(folder, k, "sex"), periods) || return false
    isfile(sex_path(folder, k, "agents")) || return false
    return isfile(joinpath(folder, "seed$k.timing.csv"))
end

"""Removes whatever a stopped run left of seed `k`: its files and their temporary names."""
function remove_sex_seed(folder::AbstractString, k::Int)
    for p in (joinpath(folder, "seed$k.csv"), joinpath(folder, "seed$k.timing.csv"), sex_path(folder, k, "sex"),
              sex_path(folder, k, "agents"))
        rm(p; force=true)
        rm(p * ".tmp"; force=true)
    end
    return nothing
end

"""
    sex_seed!(exp, world, k, folder, window) -> SeedOutcome

Runs seed `k` of `exp` in `world` with a [`SexReadings`](@ref) of `window`, and writes `seed<k>-agents.csv`,
`seed<k>-sex.csv`, `seed<k>.timing.csv` and, last, `seed<k>.csv` (the world's standard columns), each through a temporary
name. The observer is made here, so that a worker has its own. Runs in a worker.
"""
function sex_seed!(exp::Experiment, world::AbstractString, k::Int, folder::AbstractString, window::Tuple{Int,Int})
    readings = SexReadings(; window=window)
    rows, timing, _ = if world == "today"
        seed_job(exp, k, false; xxl=XXL_DEFAULTS, sex_readings=readings)
    else
        seed_job(exp, k, world == "xl"; sex_readings=readings)
    end
    header, sex = sex_rows(readings)
    write_table_csv(sex_path(folder, k, "sex"), header, sex)
    header, agents = sex_agent_rows(readings)
    write_table_csv(sex_path(folder, k, "agents"), header, agents)
    write_timing_csv(joinpath(folder, "seed$k.timing.csv"), [timing])
    cfg = world == "today" ? to_xxl(exp.config, XXL_DEFAULTS) : world == "xl" ? to_xl(exp.config) : exp.config
    columns = metric_columns(cfg)
    path = joinpath(folder, "seed$k.csv")
    write_seed_csv(path * ".tmp", rows; columns=columns)
    mv(path * ".tmp", path; force=true)
    seconds = timing.setup_s + timing.stepping_s + timing.metrics_s
    return seed_outcome(stack(rows; dims=1), ["t"; columns], k; seconds=seconds)
end

"""
    run_sex_world(world; seeds=20, first_seed=80, periods=500, jobs=1, out=RESULTS_XXL, io=stdout) -> String

Runs seeds `first_seed` to `first_seed + seeds - 1` of VI-1 in `world` (`"book"`, `"xl"` or `"today"`) over `periods`, with
the sex readings, into `<out>/sex-<world>-VI-1-s<first>-<seeds>-p<periods>/` and returns that folder. Each seed leaves
`seed<k>.csv`, `seed<k>-sex.csv`, `seed<k>-agents.csv` and `seed<k>.timing.csv`; the agent snapshot covers the last
[`SEX_WINDOW`](@ref) periods. A seed with all of them is skipped, so a stopped study resumes by running again, any seed
cut short running from period 0. A folder made under another fingerprint is refused (`ArgumentError`) before anything
runs. With `jobs > 1` the seeds run in that many worker processes.
"""
function run_sex_world(
    world::AbstractString;
    seeds::Int=20,
    first_seed::Int=80,
    periods::Int=500,
    jobs::Int=1,
    out::AbstractString=RESULTS_XXL,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    exp, folder, fingerprint = sex_plan(world, out, first_seed, seeds, periods)
    check_extinction_folder(folder, fingerprint; create=true)
    window = sex_window(periods)
    todo = [k for k in first_seed:(first_seed + seeds - 1) if !sex_seed_done(folder, k, periods)]
    foreach(k -> remove_sex_seed(folder, k), todo)
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], "sex study $world")
        run_seed_calls!(
            sex_seed!, [(exp, world, k, abspath(folder), window) for k in todo], seeds, periods, jobs, io,
        )
    end
    return folder
end

const SEX_USAGE = "usage: julia --project=julia julia/xxl_sex_study.jl --world book|xl|today [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]"

"""
The study's command line: `--world book|xl|today` (required), `--seeds N` (20), `--first-seed K` (80), `--periods P`
(500), `--jobs J` (1) and `--out DIR`. Throws `ArgumentError` on a usage error.
"""
function sex_study_args(args::Vector{String})
    world = nothing
    seeds, first_seed, periods, jobs, out = 20, 80, 500, 1, RESULTS_XXL
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("--world", "--seeds", "--first-seed", "--periods", "--jobs", "--out")
            i += 1
            i <= length(args) || throw(ArgumentError("$a needs a value"))
            v = args[i]
            if a == "--world"
                world = v
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
    world === nothing && throw(ArgumentError("--world is required"))
    world in SEX_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    return (; world, seeds, first_seed, periods, jobs, out)
end

"""
    sex_study_main(args) -> exit code

The command line of julia/xxl_sex_study.jl: runs [`run_sex_world`](@ref). Returns 1 after printing the usage on a usage
error: the arguments or a folder made under another fingerprint; anything that goes wrong after is thrown.
"""
function sex_study_main(args::Vector{String})
    a = try
        a = sex_study_args(args)
        # The run checks the folder again; checking it here makes a refusal a usage error.
        _, folder, fingerprint = sex_plan(a.world, a.out, a.first_seed, a.seeds, a.periods)
        check_extinction_folder(folder, fingerprint; create=true)
        a
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, SEX_USAGE, "\n", e.msg)
        return 1
    end
    folder = run_sex_world(
        a.world; seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, jobs=a.jobs, out=a.out,
    )
    println("-> $folder")
    return 0
end
