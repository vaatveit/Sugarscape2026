# xxl (stage 8): the combat study's run and command line. One of the combat experiments (III-9, III-11, III-12, III-13,
# III-14) in one of three worlds (the book's, the xl one and today's xxl defaults), with the combat readings
# (julia/src/xxl/combat_readings.jl) kept for each seed. It follows `run_culture_world` (julia/xxl_combat_study.jl is its
# command line): a seed with the observer cannot be paused, so a stopped one runs again from period 0.

const COMBAT_EXPS = ("III-9", "III-11", "III-12", "III-13", "III-14")  # the experiments the study runs
const COMBAT_WORLDS = ("book", "xl", "today")  # the worlds the study runs

"""`combat-<world>-<exp>-s<first>-<seeds>-p<periods>`: the folder name of a world's run."""
combat_name(world, exp_id, first_seed, seeds, periods) = "combat-$world-$exp_id-s$first_seed-$seeds-p$periods"

combat_path(folder::AbstractString, k::Int) = joinpath(folder, "seed$k-combat.csv")

"""What a run was produced from: the world's fingerprint, then a line naming the world and the experiment."""
function combat_fingerprint(exp::Experiment, world::AbstractString, periods::Int)
    return world_fingerprint(exp, world, periods) * "combat readings: world=$world exp=$(exp.id)\n"
end

"""The experiment (over `periods`, or its own steps), the folder and the fingerprint. Refuses another world or experiment."""
function combat_plan(world::AbstractString, exp_id::AbstractString, out, first_seed, seeds, periods)
    world in COMBAT_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    exp_id in COMBAT_EXPS || throw(ArgumentError("--exp is one of $(join(COMBAT_EXPS, ", ")), not $(repr(exp_id))"))
    exp = find_experiment(load_registry(), exp_id)
    periods === nothing && (periods = exp.steps)
    exp = with_steps(exp, periods)
    folder = joinpath(out, combat_name(world, exp_id, first_seed, seeds, periods))
    return (; exp, periods, folder, fingerprint=combat_fingerprint(exp, world, periods))
end

"""Whether seed `k` is whole: its CSV and combat table (`periods + 1` rows each) and its timing file."""
function combat_seed_done(folder::AbstractString, k::Int, periods::Int)
    seed_done(joinpath(folder, "seed$k.csv"), periods) || return false
    seed_done(combat_path(folder, k), periods) || return false
    return isfile(joinpath(folder, "seed$k.timing.csv"))
end

"""Removes whatever a stopped run left of seed `k`: its files and their temporary names."""
function remove_combat_seed(folder::AbstractString, k::Int)
    for p in (joinpath(folder, "seed$k.csv"), joinpath(folder, "seed$k.timing.csv"), combat_path(folder, k))
        rm(p; force=true)
        rm(p * ".tmp"; force=true)
    end
    return nothing
end

"""
    combat_seed!(exp, world, k, folder) -> SeedOutcome

Runs seed `k` of `exp` in `world` with a [`CombatReadings`](@ref), and writes `seed<k>-combat.csv`, `seed<k>.timing.csv`
and, last, `seed<k>.csv` (the world's standard columns), each through a temporary name. The observer is made here, so that
a worker has its own. Runs in a worker.
"""
function combat_seed!(exp::Experiment, world::AbstractString, k::Int, folder::AbstractString)
    readings = CombatReadings()
    rows, timing, _ = if world == "today"
        seed_job(exp, k, false; xxl=XXL_DEFAULTS, combat_readings=readings)
    else
        seed_job(exp, k, world == "xl"; combat_readings=readings)
    end
    header, combat = combat_rows(readings)
    write_table_csv(combat_path(folder, k), header, combat)
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
    run_combat_world(world, exp_id; seeds=20, first_seed=0, periods=nothing, jobs=1, out=RESULTS_XXL, io=stdout) -> String

Runs seeds `first_seed` to `first_seed + seeds - 1` of experiment `exp_id` (one of [`COMBAT_EXPS`](@ref)) in `world`
(`"book"`, `"xl"` or `"today"`) over `periods` (the experiment's own steps when `nothing`), with the combat readings, into
`<out>/combat-<world>-<exp>-s<first>-<seeds>-p<periods>/` and returns that folder. Seed `k` is the runner's seed index `k`.
Each seed leaves `seed<k>.csv`, `seed<k>-combat.csv` and `seed<k>.timing.csv`. A seed with all of them is skipped, so a
stopped study resumes by running again, any seed cut short running from period 0. A folder made under another fingerprint
is refused (`ArgumentError`) before anything runs. With `jobs > 1` the seeds run in that many worker processes.
"""
function run_combat_world(
    world::AbstractString,
    exp_id::AbstractString;
    seeds::Int=20,
    first_seed::Int=0,
    periods::Union{Nothing,Int}=nothing,
    jobs::Int=1,
    out::AbstractString=RESULTS_XXL,
    io::IO=stdout,
)
    exp, periods, folder, fingerprint = combat_plan(world, exp_id, out, first_seed, seeds, periods)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    check_extinction_folder(folder, fingerprint; create=true)
    todo = [k for k in first_seed:(first_seed + seeds - 1) if !combat_seed_done(folder, k, periods)]
    foreach(k -> remove_combat_seed(folder, k), todo)
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], "combat study $world $exp_id")
        run_seed_calls!(
            combat_seed!, [(exp, world, k, abspath(folder)) for k in todo], seeds, periods, jobs, io,
        )
    end
    return folder
end

const COMBAT_USAGE = "usage: julia --project=julia julia/xxl_combat_study.jl --world book|xl|today --exp III-9|III-11|III-12|III-13|III-14 [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]"

"""
The study's command line: `--world book|xl|today` and `--exp III-9|III-11|III-12|III-13|III-14` (both required),
`--seeds N` (20), `--first-seed K` (0), `--periods P` (the experiment's steps), `--jobs J` (1) and `--out DIR`.
Throws `ArgumentError` on a usage error.
"""
function combat_study_args(args::Vector{String})
    world = exp = periods = nothing
    seeds, first_seed, jobs, out = 20, 0, 1, RESULTS_XXL
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("--world", "--exp", "--seeds", "--first-seed", "--periods", "--jobs", "--out")
            i += 1
            i <= length(args) || throw(ArgumentError("$a needs a value"))
            v = args[i]
            if a == "--world"
                world = v
            elseif a == "--exp"
                exp = v
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
    world === nothing && throw(ArgumentError("--world is required"))
    exp === nothing && throw(ArgumentError("--exp is required"))
    world in COMBAT_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    exp in COMBAT_EXPS || throw(ArgumentError("--exp is one of $(join(COMBAT_EXPS, ", ")), not $(repr(exp))"))
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=something(periods, 4), jobs=jobs)
    return (; world, exp, seeds, first_seed, periods, jobs, out)
end

"""
    combat_study_main(args) -> exit code

The command line of julia/xxl_combat_study.jl: runs [`run_combat_world`](@ref). Returns 1 after printing the usage on a
usage error: the arguments or a folder made under another fingerprint; anything that goes wrong after is thrown.
"""
function combat_study_main(args::Vector{String})
    a = try
        a = combat_study_args(args)
        # The run checks the folder again; checking it here makes a refusal a usage error.
        _, _, folder, fingerprint = combat_plan(a.world, a.exp, a.out, a.first_seed, a.seeds, a.periods)
        check_extinction_folder(folder, fingerprint; create=true)
        a
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, COMBAT_USAGE, "\n", e.msg)
        return 1
    end
    folder = run_combat_world(
        a.world, a.exp; seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, jobs=a.jobs, out=a.out,
    )
    println("-> $folder")
    return 0
end
