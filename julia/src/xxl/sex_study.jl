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

# The pieces the sex, culture and combat studies share: one run of a world with an observer, the seeds-done test, the
# removal of a stopped seed, the driver over the seeds and the command line's option parser.

"""The config a `world` (`"book"`, `"xl"` or `"today"`) runs `exp` under."""
world_config(exp::Experiment, world::AbstractString) =
    world == "today" ? to_xxl(exp.config, XXL_DEFAULTS) : world == "xl" ? to_xl(exp.config) : exp.config

"""
    study_seed!(write_tables, exp, world, k, folder, readings_keyword, readings) -> SeedOutcome

Runs seed `k` of `exp` in `world` with `readings` passed to the runner as `readings_keyword` (`:sex_readings`, ...), calls
`write_tables(readings)` to write the observer's tables, then writes `seed<k>.timing.csv` and, last, `seed<k>.csv` (the
world's standard columns), each through a temporary name. Runs in a worker.
"""
function study_seed!(write_tables, exp::Experiment, world::AbstractString, k::Int, folder::AbstractString,
                     readings_keyword::Symbol, readings)
    observer = NamedTuple{(readings_keyword,)}((readings,))
    rows, timing, _ = if world == "today"
        seed_job(exp, k, false; xxl=XXL_DEFAULTS, observer...)
    else
        seed_job(exp, k, world == "xl"; observer...)
    end
    write_tables(readings)
    write_timing_csv(joinpath(folder, "seed$k.timing.csv"), [timing])
    columns = metric_columns(world_config(exp, world))
    path = joinpath(folder, "seed$k.csv")
    write_seed_csv(path * ".tmp", rows; columns=columns)
    mv(path * ".tmp", path; force=true)
    seconds = timing.setup_s + timing.stepping_s + timing.metrics_s
    return seed_outcome(stack(rows; dims=1), ["t"; columns], k; seconds=seconds)
end

"""Whether seed `k` is whole: its CSV and its `tables` (`seed<k>-<kind>.csv`, `periods + 1` rows each), its other `kinds` and its timing file."""
function study_seed_done(folder::AbstractString, k::Int, periods::Int, tables, kinds=())
    seed_done(joinpath(folder, "seed$k.csv"), periods) || return false
    all(kind -> seed_done(sex_path(folder, k, kind), periods), tables) || return false
    all(kind -> isfile(sex_path(folder, k, kind)), kinds) || return false
    return isfile(joinpath(folder, "seed$k.timing.csv"))
end

"""Removes whatever a stopped run left of seed `k`: its files (the `kinds` of its observer's tables) and their temporary names."""
function remove_study_seed(folder::AbstractString, k::Int, kinds)
    for p in (joinpath(folder, "seed$k.csv"), joinpath(folder, "seed$k.timing.csv"),
              (sex_path(folder, k, kind) for kind in kinds)...)
        rm(p; force=true)
        rm(p * ".tmp"; force=true)
    end
    return nothing
end

"""
    run_study_seeds(seed_fn, call_args, folder, fingerprint, done, remove, note; seeds, first_seed, periods, jobs, io)

The driver of a study: checks the sizes and the folder (refused under another fingerprint, `ArgumentError`), removes
every seed that is not `done(folder, k, periods)` with `remove(folder, k)`, and runs those with `seed_fn(call_args(k)...)`,
in `jobs` worker processes when `jobs > 1`. Returns `folder`.
"""
function run_study_seeds(seed_fn, call_args, folder, fingerprint, done, remove, note; seeds, first_seed, periods, jobs, io)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    check_extinction_folder(folder, fingerprint; create=true)
    todo = [k for k in first_seed:(first_seed + seeds - 1) if !done(folder, k, periods)]
    foreach(k -> remove(folder, k), todo)
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], note)
        run_seed_calls!(seed_fn, [call_args(k) for k in todo], seeds, periods, jobs, io)
    end
    return folder
end

"""
The options of a study's command line: each of `allowed` takes a value. Returns them as a `Dict`; throws `ArgumentError` on
an unknown option or a missing value.
"""
function parse_study_options(args::Vector{String}, allowed)
    opts = Dict{String,String}()
    i = 1
    while i <= length(args)
        a = args[i]
        a in allowed || throw(ArgumentError("unexpected argument $a"))
        i += 1
        i <= length(args) || throw(ArgumentError("$a needs a value"))
        opts[a] = args[i]
        i += 1
    end
    return opts
end

"""The options common to the studies' command lines (`--seeds`, `--first-seed`, `--periods`, `--jobs`, `--out`) read from `opts`."""
function study_common_options(opts, first_seed::Int, periods::Union{Nothing,Int})
    num(key, default) = haskey(opts, key) ? parse(Int, opts[key]) : default
    return (; seeds=num("--seeds", 20), first_seed=num("--first-seed", first_seed), periods=num("--periods", periods),
            jobs=num("--jobs", 1), out=get(opts, "--out", RESULTS_XXL))
end

"""
What a world's run was produced from, before any readings line. Today's is the extinction run's fingerprint; the book's
and the xl one's are the registry's own text (which keeps its `steps=` line), then the code's checksum and the periods as
the extinction fingerprint writes them (the `periods=` line governs). The sex, culture and combat studies each add a line.
"""
function world_fingerprint(exp::Experiment, world::AbstractString, periods::Int)
    world == "today" && return extinction_fingerprint(exp, XXL_DEFAULTS, periods)
    base = world == "book" ? exp.fingerprint : exp.xl_fingerprint
    endswith(base, "\n") || (base *= "\n")
    return base * "code sha256=$(source_sha256(dirname(@__DIR__)))\nperiods=$periods\n"
end

"""The world's fingerprint, then a line naming the world and the readings' window."""
function sex_fingerprint(exp::Experiment, world::AbstractString, periods::Int)
    lo, hi = sex_window(periods)
    return world_fingerprint(exp, world, periods) * "sex readings: world=$world window=($lo, $hi)\n"
end

"""The experiment of a world's run (VI-1 over `periods`), its folder and its fingerprint. Refuses another world."""
function sex_plan(world::AbstractString, out, first_seed, seeds, periods)
    world in SEX_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    exp = with_steps(find_experiment(load_registry(), "VI-1"), periods)
    folder = joinpath(out, sex_name(world, first_seed, seeds, periods))
    return (; exp, folder, fingerprint=sex_fingerprint(exp, world, periods))
end

"""Whether seed `k` is whole: its CSV and its sex table (`periods + 1` rows each), its agent table and its timing file."""
sex_seed_done(folder::AbstractString, k::Int, periods::Int) = study_seed_done(folder, k, periods, ("sex",), ("agents",))

"""Removes whatever a stopped run left of seed `k`: its files and their temporary names."""
remove_sex_seed(folder::AbstractString, k::Int) = remove_study_seed(folder, k, ("sex", "agents"))

"""
    sex_seed!(exp, world, k, folder, window) -> SeedOutcome

Runs seed `k` of `exp` in `world` with a [`SexReadings`](@ref) of `window`, and writes `seed<k>-agents.csv`,
`seed<k>-sex.csv`, `seed<k>.timing.csv` and, last, `seed<k>.csv` (the world's standard columns), each through a temporary
name. The observer is made here, so that a worker has its own. Runs in a worker.
"""
function sex_seed!(exp::Experiment, world::AbstractString, k::Int, folder::AbstractString, window::Tuple{Int,Int})
    readings = SexReadings(; window=window)
    return study_seed!(exp, world, k, folder, :sex_readings, readings) do readings
        header, sex = sex_rows(readings)
        write_table_csv(sex_path(folder, k, "sex"), header, sex)
        header, agents = sex_agent_rows(readings)
        write_table_csv(sex_path(folder, k, "agents"), header, agents)
    end
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
    exp, folder, fingerprint = sex_plan(world, out, first_seed, seeds, periods)
    window = sex_window(periods)
    return run_study_seeds(
        sex_seed!, k -> (exp, world, k, abspath(folder), window), folder, fingerprint, sex_seed_done, remove_sex_seed,
        "sex study $world"; seeds, first_seed, periods, jobs, io,
    )
end

const SEX_USAGE = "usage: julia --project=julia julia/xxl_sex_study.jl --world book|xl|today [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]"

"""
The study's command line: `--world book|xl|today` (required), `--seeds N` (20), `--first-seed K` (80), `--periods P`
(500), `--jobs J` (1) and `--out DIR`. Throws `ArgumentError` on a usage error.
"""
function sex_study_args(args::Vector{String})
    opts = parse_study_options(args, ("--world", "--seeds", "--first-seed", "--periods", "--jobs", "--out"))
    common = study_common_options(opts, 80, 500)
    check_extinction_size(; seeds=common.seeds, first_seed=common.first_seed, periods=common.periods, jobs=common.jobs)
    world = get(opts, "--world", nothing)
    world === nothing && throw(ArgumentError("--world is required"))
    world in SEX_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    return (; world, common...)
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
