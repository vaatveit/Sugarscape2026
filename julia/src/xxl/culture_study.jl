# xxl (stage 7): the culture study's run and command line. VI-1 in three worlds (the book's, the xl one and today's xxl
# defaults), with the culture readings (julia/src/xxl/culture_readings.jl) kept for each seed. It follows
# `run_sex_world` (julia/xxl_culture_study.jl is its command line): a seed with the observer cannot be paused, so a
# stopped one runs again from period 0.

const CULTURE_WORLDS = ("book", "xl", "today")  # the worlds the study runs

"""The length, in periods, of the window the fingerprint names: the last `CULTURE_WINDOW` of the run."""
const CULTURE_WINDOW = 200

culture_window(periods::Int) = (max(1, periods - CULTURE_WINDOW + 1), periods)

"""`culture-<world>-VI-1-s<first>-<seeds>-p<periods>`: the folder name of a world's run."""
culture_name(world, first_seed, seeds, periods) = "culture-$world-VI-1-s$first_seed-$seeds-p$periods"

culture_path(folder::AbstractString, k::Int, kind::AbstractString) = joinpath(folder, "seed$k-$kind.csv")

"""
What a world's run was produced from: stage 6's fingerprint for the same world (so the model text, the code's checksum and
the periods are the same), with its last line replaced by one naming the world and the readings' window.
"""
function culture_fingerprint(exp::Experiment, world::AbstractString, periods::Int)
    lo, hi = culture_window(periods)
    text = sex_fingerprint(exp, world, periods)
    text = text[1:(first(findlast("sex readings:", text)) - 1)]
    return text * "culture readings: world=$world window=($lo, $hi)\n"
end

"""The experiment of a world's run (VI-1 over `periods`), its folder and its fingerprint. Refuses another world."""
function culture_plan(world::AbstractString, out, first_seed, seeds, periods)
    world in CULTURE_WORLDS || throw(ArgumentError("--world is book, xl or today, not $(repr(world))"))
    exp = with_steps(find_experiment(load_registry(), "VI-1"), periods)
    folder = joinpath(out, culture_name(world, first_seed, seeds, periods))
    return (; exp, folder, fingerprint=culture_fingerprint(exp, world, periods))
end

"""Whether seed `k` is whole: its CSV and culture table (`periods + 1` rows each), its patch table and its timing file."""
function culture_seed_done(folder::AbstractString, k::Int, periods::Int)
    seed_done(joinpath(folder, "seed$k.csv"), periods) || return false
    seed_done(culture_path(folder, k, "culture"), periods) || return false
    isfile(culture_path(folder, k, "patches")) || return false
    return isfile(joinpath(folder, "seed$k.timing.csv"))
end

"""Removes whatever a stopped run left of seed `k`: its files and their temporary names."""
function remove_culture_seed(folder::AbstractString, k::Int)
    for p in (joinpath(folder, "seed$k.csv"), joinpath(folder, "seed$k.timing.csv"), culture_path(folder, k, "culture"),
              culture_path(folder, k, "patches"))
        rm(p; force=true)
        rm(p * ".tmp"; force=true)
    end
    return nothing
end

"""
    culture_seed!(exp, world, k, folder) -> SeedOutcome

Runs seed `k` of `exp` in `world` with a [`CultureReadings`](@ref), and writes `seed<k>-culture.csv`,
`seed<k>-patches.csv`, `seed<k>.timing.csv` and, last, `seed<k>.csv` (the world's standard columns), each through a
temporary name. The observer is made here, so that a worker has its own. Runs in a worker.
"""
function culture_seed!(exp::Experiment, world::AbstractString, k::Int, folder::AbstractString)
    readings = CultureReadings()
    rows, timing, _ = if world == "today"
        seed_job(exp, k, false; xxl=XXL_DEFAULTS, culture_readings=readings)
    else
        seed_job(exp, k, world == "xl"; culture_readings=readings)
    end
    header, culture = culture_rows(readings)
    write_table_csv(culture_path(folder, k, "culture"), header, culture)
    header, patches = culture_patch_rows(readings)
    write_table_csv(culture_path(folder, k, "patches"), header, patches)
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
    run_culture_world(world; seeds=20, first_seed=80, periods=500, jobs=1, out=RESULTS_XXL, io=stdout) -> String

Runs seeds `first_seed` to `first_seed + seeds - 1` of VI-1 in `world` (`"book"`, `"xl"` or `"today"`) over `periods`, with
the culture readings, into `<out>/culture-<world>-VI-1-s<first>-<seeds>-p<periods>/` and returns that folder. Each seed
leaves `seed<k>.csv`, `seed<k>-culture.csv`, `seed<k>-patches.csv` and `seed<k>.timing.csv`. A seed with all of them is
skipped, so a stopped study resumes by running again, any seed cut short running from period 0. A folder made under
another fingerprint is refused (`ArgumentError`) before anything runs. With `jobs > 1` the seeds run in that many worker
processes.
"""
function run_culture_world(
    world::AbstractString;
    seeds::Int=20,
    first_seed::Int=80,
    periods::Int=500,
    jobs::Int=1,
    out::AbstractString=RESULTS_XXL,
    io::IO=stdout,
)
    check_extinction_size(; seeds=seeds, first_seed=first_seed, periods=periods, jobs=jobs)
    exp, folder, fingerprint = culture_plan(world, out, first_seed, seeds, periods)
    check_extinction_folder(folder, fingerprint; create=true)
    todo = [k for k in first_seed:(first_seed + seeds - 1) if !culture_seed_done(folder, k, periods)]
    foreach(k -> remove_culture_seed(folder, k), todo)
    if !isempty(todo)
        write_machine_note(joinpath(folder, "machine.txt"), jobs, Float64[], "culture study $world")
        run_seed_calls!(
            culture_seed!, [(exp, world, k, abspath(folder)) for k in todo], seeds, periods, jobs, io,
        )
    end
    return folder
end

const CULTURE_USAGE = "usage: julia --project=julia julia/xxl_culture_study.jl --world book|xl|today [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]"

"""
    culture_study_main(args) -> exit code

The command line of julia/xxl_culture_study.jl: runs [`run_culture_world`](@ref). The options are stage 6's
(`sex_study_args`; the worlds are the same). Returns 1 after printing the usage on a usage error: the arguments or a folder
made under another fingerprint; anything that goes wrong after is thrown.
"""
function culture_study_main(args::Vector{String})
    a = try
        a = sex_study_args(args)
        # The run checks the folder again; checking it here makes a refusal a usage error.
        _, folder, fingerprint = culture_plan(a.world, a.out, a.first_seed, a.seeds, a.periods)
        check_extinction_folder(folder, fingerprint; create=true)
        a
    catch e
        e isa ArgumentError || rethrow()
        println(stderr, CULTURE_USAGE, "\n", e.msg)
        return 1
    end
    folder = run_culture_world(
        a.world; seeds=a.seeds, first_seed=a.first_seed, periods=a.periods, jobs=a.jobs, out=a.out,
    )
    println("-> $folder")
    return 0
end
