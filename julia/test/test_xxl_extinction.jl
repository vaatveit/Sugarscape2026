# xxl: the extinction test (stage-2 spec): the limit, one seed's outcome, the report, the resumable run.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape:
    extinction_limit,
    seed_outcome,
    is_falling,
    extinction_verdict,
    extinction_report,
    SeedOutcome,
    extinction_name,
    source_sha256,
    run_extinction,
    rebuild_extinction_report,
    same_run,
    extinction_main,
    extinction_fingerprint,
    read_seed_csv,
    with_steps,
    run_experiment

# A run from population per period (t = 0 on), with agents_ever given or constant.
function ext_run(pops; ever=fill(100.0, length(pops)))
    M = hcat(Float64.(0:(length(pops) - 1)), Float64.(pops), Float64.(ever))
    return M, ["t", "population", "agents_ever"]
end
ext_outcome(pops; seed=0, kw...) = seed_outcome(ext_run(pops; kw...)..., seed)

const EXT_ALIVE = [100, 90, 80, 85, 90, 95, 100, 110, 120]
const EXT_FALLING = [100, 100, 100, 100, 100, 100, 100, 90, 90]

@testset "xxl extinction: the limit" begin
    @test extinction_limit(0, 59) < 0.05
    @test extinction_limit(0, 58) > 0.05
    @test extinction_limit(1, 93) < 0.05
    @test extinction_limit(1, 92) > 0.05
    @test extinction_limit(0, 60) ≈ 1 - 0.05^(1 / 60)
    @test extinction_limit(0, 40) ≈ 1 - 0.05^(1 / 40)
    @test extinction_limit(0, 0) == 1
    @test extinction_limit(3, 3) == 1
end

@testset "xxl extinction: one seed, alive" begin
    ever = [100, 100, 100, 105, 110, 115, 120, 130, 140]
    o = ext_outcome(EXT_ALIVE; seed=7, ever=ever)
    @test o.seed == 7
    @test o.lowest == 80
    @test o.lowest_t == 2
    @test o.at_quarters == (80.0, 90.0, 100.0, 120.0)
    @test o.extinct_t === nothing
    @test o.mean_third == 97.5  # t = 5, 6
    @test o.mean_fourth == 115  # t = 7, 8
    @test o.births_last == 40  # w = 8
    @test o.deaths_last == 20
    @test isnan(o.seconds)
    @test !is_falling(o)
    @test seed_outcome(ext_run(EXT_ALIVE)..., 7; seconds=12.5).seconds == 12.5
end

@testset "xxl extinction: one seed, extinct at the first period and at the last" begin
    first_t = ext_outcome([100, 0, 0, 0, 0, 0, 0, 0, 0])
    @test first_t.extinct_t == 1
    @test first_t.lowest == 0
    @test first_t.mean_third == 0 && first_t.mean_fourth == 0
    @test !is_falling(first_t)
    last_t = ext_outcome([100, 90, 80, 70, 60, 50, 40, 30, 0])
    @test last_t.extinct_t == 8
    @test last_t.lowest == 0
    @test last_t.lowest_t == 8
    @test !is_falling(last_t)
    for o in (first_t, last_t)
        r = extinction_report([o]; label="x", rules=XXL_DEFAULTS, first_seed=0, seeds=1, periods=8,
                              jobs=nothing, wall=nothing)
        @test !occursin("NaN", r)
    end
end

@testset "xxl extinction: falling at exactly the line is not falling" begin
    @test !is_falling(ext_outcome(EXT_FALLING))  # 100 and 90
    @test is_falling(ext_outcome([100, 100, 100, 100, 100, 100, 100, 89, 89]))  # 100 and 89
end

@testset "xxl extinction: the verdict" begin
    alive(n) = [ext_outcome(EXT_ALIVE; seed=i) for i in 1:n]
    dead = ext_outcome([100, 0, 0, 0, 0, 0, 0, 0, 0])
    @test extinction_verdict(alive(59)).verdict == "PASS"
    @test extinction_verdict(alive(58)).verdict == "TOO FEW SEEDS"
    v = extinction_verdict([alive(59); dead])
    @test v.verdict == "FAIL"
    @test v.extinct == 1
    @test extinction_verdict([alive(92); dead]).verdict == "PASS"  # 1 of 93 meets the bar
    @test extinction_verdict(alive(59)).limit == extinction_limit(0, 59)
end

@testset "xxl extinction: the report" begin
    kw = (label="defaults", rules=XXL_DEFAULTS, first_seed=20, periods=2000, jobs=10, wall=3600.0)
    # 60 seeds over 2,000 periods: the quarters are 500, 1,000, 1,500 and 2,000.
    pops = fill(100, 2001)
    r = extinction_report([seed_outcome(ext_run(pops)..., 19 + i; seconds=60.0) for i in 1:60]; seeds=60, kw...)
    @test occursin("# Extinction test: defaults", r)
    @test occursin("- Verdict: PASS", r)
    @test occursin("- Bar: below 5%, at 95% confidence", r)
    @test occursin("- Upper limit on the chance of extinction: 4.87%", r)
    @test occursin("- Extinct: 0 of 60 seeds", r)
    @test occursin("- Seeds finished: 60 of 60 (20–79)", r)
    @test occursin("- Periods: 2000", r)
    @test occursin("| Seed | Lowest | Lowest at t | t = 500 | t = 1000 | t = 1500 | t = 2000 |", r)
    @test occursin("Births, last 200 | Deaths, last 200", r)
    @test occursin("| 20 | 100 | 1 | 100 | 100 | 100 | 100 | — | 0 | 0 | 100 | 100 | no | 60 |", r)
    @test occursin("t = 1001–1500 against t = 1501–2000", r)
    @test occursin("- Falling at the end: 0 of 60 living seeds", r)
    @test occursin("- Run time: ", r)
    @test !occursin("Unfinished", r)
    @test !occursin("Most living seeds", r)
    @test !occursin("NaN", r)

    r = extinction_report([ext_outcome(pops; seed=19 + i) for i in 1:40]; seeds=60, kw...)
    @test occursin("- Seeds finished: 40 of 60 (20–79)", r)
    @test occursin("**Unfinished: 20 seeds have not run.", r)
    @test occursin("- Verdict: TOO FEW SEEDS", r)

    falling = [fill(100, 1501); fill(80, 500)]
    r = extinction_report([ext_outcome(falling; seed=19 + i) for i in 1:60]; seeds=60, kw...)
    @test occursin("**Most living seeds were falling at the end", r)
    @test occursin("- Falling at the end: 60 of 60 living seeds", r)

    # Populations are exact: four significant figures would show 62989 as 62990.
    big = [63000, 63000, 62989, 63000, 63000, 62980, 62990, 63000, 63000]
    r = extinction_report([ext_outcome(big)]; label="x", rules=XXL_DEFAULTS, first_seed=0, seeds=1, periods=8,
                          jobs=nothing, wall=nothing)
    @test occursin("| 0 | 62980 | 5 | 62989 | 63000 | 62990 | 63000 | — | 0 | 0 | 62985 | 63000 | no |", r)

    # jobs and wall are optional.
    @test extinction_report([ext_outcome(pops)]; seeds=1, kw..., jobs=nothing, wall=nothing) isa String
end

const EXT_REG = load_registry()
const EXT_TINY = find_experiment(EXT_REG, "TEST-tiny")
function ext_exp(e::Experiment=EXT_TINY; kw...)
    return Experiment(
        e.id, e.title, e.rules, e.steps, e.seeds, replace_config(e.config; kw...),
        e.fingerprint, e.xl_config, e.xl_fingerprint,
    )
end
const EXT_DOOMED = ext_exp(; max_age=(2, 2))  # all dead of old age within a few periods
const EXT_FED = ext_exp(; metabolism=(1, 1), endowment=(50, 50))  # all alive throughout

# A small run into `out`: two seeds from 5 over 12 periods, in this process, quietly.
function ext_go(exp, out; rules=XXL_V1, kw...)
    return run_extinction(
        rules; label="t", seeds=2, first_seed=5, periods=12, jobs=1, out=out, experiment=exp, io=devnull, kw...
    )
end
function ext_dir(out; label="t", first=5, seeds=2, periods=12)
    return joinpath(out, extinction_name(label, first, seeds, periods))
end
ext_report(out; kw...) = read(ext_dir(out; kw...) * ".md", String)
ext_rows(text) = [l for l in split(text, "\n") if startswith(l, "| ")]  # the table: its header and the seed rows
ext_wall(folder) = parse(Float64, read(joinpath(folder, "elapsed.txt"), String))
ext_times(folder) = [mtime(joinpath(folder, "seed$k.csv")) for k in (5, 6)]

@testset "xxl extinction: the name" begin
    @test extinction_name("defaults", 20, 60, 2000) == "extinction-defaults-s20-60-p2000"
end

@testset "xxl extinction: an extinct world fails, and its CSV reads back" begin
    out = mktempdir()
    v = ext_go(EXT_DOOMED, out)
    @test v.verdict == "FAIL"
    @test v.extinct == 2
    header, M = read_seed_csv(joinpath(ext_dir(out), "seed5.csv"))
    @test size(M, 1) == 13
    @test M[end, findfirst(==("population"), header)] == 0
    @test occursin("- Extinct: 2 of 2 seeds", ext_report(out))
end

@testset "xxl extinction: VI-1 runs on with nobody left" begin
    out = mktempdir()
    doomed = ext_exp(find_experiment(EXT_REG, "VI-1"); max_age=(2, 2))
    v = run_extinction(
        XXL_DEFAULTS; label="vi", seeds=1, first_seed=5, periods=10, jobs=1, out=out, experiment=doomed, io=devnull
    )
    @test v.extinct == 1
    _, M = read_seed_csv(joinpath(ext_dir(out; label="vi", seeds=1, periods=10), "seed5.csv"))
    @test size(M, 1) == 11
end

@testset "xxl extinction: a fed world has too few seeds" begin
    out = mktempdir()
    v = ext_go(EXT_FED, out)
    @test v.verdict == "TOO FEW SEEDS"
    @test v.extinct == 0
    folder = ext_dir(out)
    @test sort(readdir(folder)) == sort([
        "elapsed.txt", "fingerprint.txt", "machine.txt", "seed5.csv", "seed6.csv", "seed5.timing.csv",
        "seed6.timing.csv",
    ])
    header, _ = read_seed_csv(joinpath(folder, "seed5.csv"))
    @test "population" in header
    @test !("n_fertile" in header)
    @test occursin("- Verdict: TOO FEW SEEDS", ext_report(out))
end

@testset "xxl extinction: a re-run skips finished seeds" begin
    out = mktempdir()
    ext_go(EXT_FED, out)
    folder = ext_dir(out)
    times, report, wall = ext_times(folder), ext_report(out), ext_wall(folder)
    ext_go(EXT_FED, out)
    @test ext_times(folder) == times
    @test ext_rows(ext_report(out)) == ext_rows(report)
    @test ext_wall(folder) >= wall
end

@testset "xxl extinction: a seed cut short runs again" begin
    out = mktempdir()
    ext_go(EXT_FED, out)
    folder = ext_dir(out)
    path6 = joinpath(folder, "seed6.csv")
    whole, seed5_time = read(path6), mtime(joinpath(folder, "seed5.csv"))
    write(path6, join(readlines(path6)[1:3], "\n") * "\n")
    write(joinpath(folder, "seed5.csv.tmp"), "stray")
    ext_go(EXT_FED, out)
    @test countlines(path6) == 14
    @test read(path6) == whole
    @test mtime(joinpath(folder, "seed5.csv")) == seed5_time
end

@testset "xxl extinction: a seed cut inside its last row runs again" begin
    out = mktempdir()
    ext_go(EXT_FED, out)
    folder = ext_dir(out)
    path6 = joinpath(folder, "seed6.csv")
    whole = read(path6)
    write(path6, whole[1:(end - 4)])  # the right number of lines, the last cut mid-cell, no final newline
    @test countlines(path6) == 14
    ext_go(EXT_FED, out)
    @test read(path6) == whole
end

@testset "xxl extinction: other rules or periods are refused" begin
    out = mktempdir()
    ext_go(EXT_FED, out)
    folder = ext_dir(out)
    times = ext_times(folder)
    @test_throws ArgumentError ext_go(EXT_FED, out; rules=replace_rules(XXL_V1; travel_cost=0.05))
    @test ext_times(folder) == times
    fp = joinpath(folder, "fingerprint.txt")
    write(fp, replace(read(fp, String), "periods=12" => "periods=13"))
    @test_throws ArgumentError ext_go(EXT_FED, out)
    @test ext_times(folder) == times
end

@testset "xxl extinction: the code is part of the fingerprint" begin
    tree(dir) = (mkpath(joinpath(dir, "sub")); write(joinpath(dir, "a.jl"), "x = 1
"); write(joinpath(dir, "sub", "b.jl"), "y = 2
"); dir)
    a, b = tree(mktempdir()), tree(mktempdir())
    base = source_sha256(a)
    @test length(base) == 64
    @test source_sha256(b) == base  # an identical copy elsewhere
    write(joinpath(b, "a.jl"), "x = 2
")
    @test source_sha256(b) != base  # a file's content
    write(joinpath(b, "a.jl"), "x = 1
")
    write(joinpath(b, "sub", "c.jl"), "")
    @test source_sha256(b) != base  # a file added in a subfolder
    rm(joinpath(b, "sub", "c.jl"))
    @test source_sha256(b) == base
    mv(joinpath(b, "sub", "b.jl"), joinpath(b, "sub", "d.jl"))
    @test source_sha256(b) != base  # a file renamed
    write(joinpath(a, "notes.txt"), "not code")
    @test source_sha256(a) == base  # only .jl files count
    out = mktempdir()
    ext_go(EXT_FED, out)
    folder = ext_dir(out)
    @test occursin(r"^code sha256=[0-9a-f]{64}$"m, read(joinpath(folder, "fingerprint.txt"), String))
    times = ext_times(folder)
    fp = joinpath(folder, "fingerprint.txt")
    write(fp, replace(read(fp, String), r"code sha256=[0-9a-f]" => "code sha256=x"))
    @test_throws ArgumentError ext_go(EXT_FED, out)
    @test ext_times(folder) == times
end

@testset "xxl extinction: the report can be rebuilt" begin
    out = mktempdir()
    kw = (label="t", seeds=2, first_seed=5, periods=12, out=out, experiment=EXT_FED, io=devnull)
    ext_go(EXT_FED, out)
    md = ext_dir(out) * ".md"
    verdict_line(text) = only(filter(startswith("- Verdict"), split(text, "\n")))
    verdict = verdict_line(read(md, String))
    rm(md)
    v = rebuild_extinction_report(XXL_V1; kw...)
    @test v.verdict == "TOO FEW SEEDS"
    @test verdict_line(read(md, String)) == verdict
    text = read(md, String)
    @test occursin("- Run time: ", text)
    @test_throws ArgumentError rebuild_extinction_report(XXL_V1; kw..., out=mktempdir())
    @test_throws ArgumentError rebuild_extinction_report(replace_rules(XXL_V1; travel_cost=0.05); kw...)
    @test read(md, String) == text
    # Edited code is a warning, not a refusal; other rules or periods alongside it still refuse.
    fp = joinpath(ext_dir(out), "fingerprint.txt")
    original = read(fp, String)
    write(fp, replace(original, r"code sha256=[0-9a-f]+" => "code sha256=edited"))
    rm(md)
    said = IOBuffer()
    @test rebuild_extinction_report(XXL_V1; kw..., io=said).verdict == "TOO FEW SEEDS"
    @test occursin("warning: the code differs", String(take!(said)))
    @test read(md, String) == text
    @test_throws ArgumentError rebuild_extinction_report(replace_rules(XXL_V1; travel_cost=0.05); kw...)
    @test_throws ArgumentError ext_go(EXT_FED, out)
    write(fp, replace(original, r"code sha256=[0-9a-f]+" => "code sha256=edited", "periods=12" => "periods=13"))
    @test_throws ArgumentError rebuild_extinction_report(XXL_V1; kw...)
    write(fp, original)
    path6 = joinpath(ext_dir(out), "seed6.csv")
    whole = read(path6, String)
    rm(path6)
    rebuild_extinction_report(XXL_V1; kw...)
    @test occursin("- Seeds finished: 1 of 2", read(md, String))
    write(path6, join(split(whole, "\n")[1:3], "\n") * "\n")  # cut short
    rebuild_extinction_report(XXL_V1; kw...)
    @test occursin("- Seeds finished: 1 of 2", read(md, String))
end

@testset "xxl extinction: two workers give the same seeds" begin
    one, two = mktempdir(), mktempdir()
    ext_go(EXT_FED, one)
    ext_go(EXT_FED, two; jobs=2)
    for k in (5, 6)
        @test read(joinpath(ext_dir(one), "seed$k.csv")) == read(joinpath(ext_dir(two), "seed$k.csv"))
    end
    @test occursin("- Seeds finished: 2 of 2", ext_report(two))
end

@testset "xxl extinction: the runs are VI-1's runs" begin
    out, out2 = mktempdir(), mktempdir()
    run_extinction(XXL_DEFAULTS; label="vi", seeds=1, first_seed=20, periods=10, jobs=1, out=out, io=devnull)
    a = joinpath(ext_dir(out; label="vi", first=20, seeds=1, periods=10), "seed20.csv")
    run_experiment(
        with_steps(find_experiment(EXT_REG, "VI-1"), 10);
        seeds=1, first_seed=20, out=out2, xxl=XXL_DEFAULTS, scorecard=true,
    )
    b = joinpath(out2, "VI-1", "seed20.csv")
    @test same_run(a, b; periods=10)
    header, _ = read_seed_csv(a)
    pop = findfirst(==("population"), header)
    lines = readlines(a)
    function derived(change, name)  # a copy of `a` with its lines changed
        path = joinpath(out, name)
        write(path, join(change(lines), "\n") * "\n")
        return path
    end
    edited = derived("edited.csv") do ls  # population at t = 3
        cells = split(ls[5], ",")
        cells[pop] = string(parse(Float64, cells[pop]) + 1)
        return [ls[1:4]; join(cells, ","); ls[6:end]]
    end
    @test !same_run(a, edited; periods=10)
    @test same_run(a, edited; periods=2)
    lacking = derived("lacking.csv") do ls
        return [join(split(l, ",")[setdiff(eachindex(header), pop)], ",") for l in ls]
    end
    @test !same_run(a, lacking; periods=10)
    short = derived(ls -> ls[1:6], "short.csv")
    @test !same_run(a, short; periods=10)
    @test !same_run(short, a; periods=10)
end

@testset "xxl extinction: a malformed CSV is an error, not a usage error" begin
    out = mktempdir()
    args = ["--rules", "v1", "--label", "bad", "--seeds", "1", "--first-seed", "5", "--periods", "12", "--out", out]
    folder = joinpath(out, extinction_name("bad", 5, 1, 12))
    mkpath(folder)
    exp = with_steps(find_experiment(EXT_REG, "VI-1"), 12)
    write(joinpath(folder, "fingerprint.txt"), extinction_fingerprint(exp, XXL_V1, 12))
    rows = ["t,population,agents_ever"; ["$t,100,100" for t in 0:12]]
    rows[6] = "4,100"  # too few cells
    write(joinpath(folder, "seed5.csv"), join(rows, "\n") * "\n")
    @test_throws ArgumentError redirect_stderr(() -> extinction_main([args; "--report-only"]), devnull)
    # Whole again, and the code edited since: a warning, not a usage error.
    rows[6] = "4,100,100"
    write(joinpath(folder, "seed5.csv"), join(rows, "\n") * "\n")
    fp = joinpath(folder, "fingerprint.txt")
    write(fp, replace(read(fp, String), r"code sha256=[0-9a-f]+" => "code sha256=edited"))
    @test redirect_stdout(() -> extinction_main([args; "--report-only"]), devnull) == 0
    @test isfile(folder * ".md")
end

@testset "xxl extinction: the command line" begin
    usage(args) = redirect_stderr(() -> extinction_main(args), devnull)
    for args in (
        ["--seeds", "0"], ["--jobs", "0"], ["--periods", "3"], ["--first-seed", "-1"], ["--nope"], ["--rules", "x"],
        ["--seeds"], ["--seeds", "many"], ["--report-only", "--out", mktempdir()],
    )
        @test usage(args) == 2
    end
end

# --- pause and resume --------------------------------------------------------------------------------------------------

using Serialization: Serialization
using Sugarscape:
    CHECKPOINT_EVERY,
    STOP_FILE,
    save_checkpoint,
    load_checkpoint,
    seed_checkpoint,
    seed_header,
    extinction_plan,
    flat_model,
    model_from_flat,
    collect_metrics,
    timed_seed,
    seed_job

ext_csvs(folder, seeds=(5, 6)) = [read(joinpath(folder, "seed$k.csv")) for k in seeds]
ext_ckpt(folder, k=5) = joinpath(folder, "seed$k.ckpt")
ext_stop(folder) = joinpath(folder, STOP_FILE)
# The CSVs of an unbroken run of `exp`, once per world and rule set: every stop and resume must match them to the byte.
const EXT_UNBROKEN = Dict{Any,Vector{Vector{UInt8}}}()
function ext_unbroken(exp; rules=XXL_V1, kw...)
    return get!(EXT_UNBROKEN, (exp.config, rules, sort(collect(kw); by=first))) do
        out = mktempdir()
        ext_go(exp, out; rules=rules, kw...)
        return ext_csvs(ext_dir(out))
    end
end
# The run's own plan, as run_extinction makes it, and the header it expects of seed k's checkpoint.
function ext_plan(exp, out; rules=XXL_V1)
    return extinction_plan(rules, exp, out, "t", 5, 2, 12)
end
ext_expected(exp, out, k; rules=XXL_V1) = (p = ext_plan(exp, out; rules=rules); seed_header(p.exp, k, rules, p.fingerprint))

const EXT_WORLD = EXT_TINY  # agents move, trade nothing and may die: the plainest run with draws

@testset "xxl extinction: a stop file ends the run at a checkpoint, with no report" begin
    out = mktempdir()
    @test ext_go(EXT_WORLD, out; stop_at=6) === nothing
    folder = ext_dir(out)
    @test isfile(ext_stop(folder))  # kept until the run resumes
    @test isfile(ext_ckpt(folder, 5))
    @test !isfile(joinpath(folder, "seed5.csv"))  # the seed did not finish
    @test !isfile(ext_ckpt(folder, 6)) && !isfile(joinpath(folder, "seed6.csv"))  # the next seed never began
    @test !isfile(folder * ".md")
    @test isfile(joinpath(folder, "elapsed.txt"))
end

@testset "xxl extinction: a stopped run resumes to the same bytes" begin
    for world in (EXT_WORLD, EXT_FED, EXT_DOOMED), at in (0, 1, 6, 11)
        out = mktempdir()
        @test ext_go(world, out; stop_at=at) === nothing
        folder = ext_dir(out)
        @test ext_go(world, out) !== nothing
        @test ext_csvs(folder) == ext_unbroken(world)
        @test !isfile(ext_stop(folder))
        @test !isfile(ext_ckpt(folder, 5)) && !isfile(ext_ckpt(folder, 6))
        @test isfile(folder * ".md")
    end
end

@testset "xxl extinction: a resumed seed goes on from its checkpoint, not from the start" begin
    # Seeds are deterministic, so a seed that ignored its save and began again would give the same bytes. These can tell.
    out = mktempdir()
    ext_go(EXT_WORLD, out; stop_at=6)
    folder = ext_dir(out)
    path, good = ext_ckpt(folder, 5), ext_expected(EXT_WORLD, out, 5)
    said = IOBuffer()
    state = load_checkpoint(path, good)
    state.rows[4][2] = 99999.0  # population at t = 3, already behind the save: only the save can hold this
    a = state.model.agents[1]
    a.max_age = a.age + 1.0  # and its model: this agent now dies of old age in the next period
    save_checkpoint(path, good, state; t=state.model.t)
    @test ext_go(EXT_WORLD, out; io=said) !== nothing
    @test occursin("seed 5: carrying on from t = 6", String(take!(said)))
    header, M = read_seed_csv(joinpath(folder, "seed5.csv"))
    pop = findfirst(==("population"), header)
    _, whole = mktempdir() |> o -> (ext_go(EXT_WORLD, o); read_seed_csv(joinpath(ext_dir(o), "seed5.csv")))
    @test M[4, pop] == 99999
    @test M[[1:3; 5:7], pop] == whole[[1:3; 5:7], pop]  # the rows before the save, as saved
    @test !isequal(M[8:end, :], whole[8:end, :])  # the rows after it, from the saved model
end

@testset "xxl extinction: a save waits out a moment's lock on the old checkpoint" begin
    # Windows refuses to replace a file that is open, as a virus scanner or an indexer may have it for a moment.
    dir = mktempdir()
    path = joinpath(dir, "seed5.ckpt")
    save_checkpoint(path, "h", (; x=1))
    held = open(path)
    release = @async (sleep(0.3); close(held))
    save_checkpoint(path, "h", (; x=2))
    wait(release)
    @test load_checkpoint(path, "h").x == 2
    @test !isfile(path * ".tmp")
end

@testset "xxl extinction: stopped again and again, the bytes stay" begin
    out = mktempdir()
    for at in (2, 5, 9)
        @test ext_go(EXT_WORLD, out; stop_at=at) === nothing
    end
    @test ext_go(EXT_WORLD, out) !== nothing
    @test ext_csvs(ext_dir(out)) == ext_unbroken(EXT_WORLD)
end

@testset "xxl extinction: a stop at the last period is too late to matter" begin
    out = mktempdir()
    @test ext_go(EXT_WORLD, out; stop_at=12) !== nothing  # the last period has no save: the seed ends instead
    @test ext_csvs(ext_dir(out)) == ext_unbroken(EXT_WORLD)
end

@testset "xxl extinction: a resumed seed's timing covers the whole seed" begin
    out = mktempdir()
    ext_go(EXT_WORLD, out; stop_at=6)
    ext_go(EXT_WORLD, out)
    plain = mktempdir()
    ext_go(EXT_WORLD, plain)
    lines(dir) = readlines(joinpath(ext_dir(dir), "seed5.timing.csv"))
    cells(dir) = Dict(zip(split(lines(dir)[1], ","), split(lines(dir)[2], ",")))
    for name in ("seed", "periods", "agents_start", "agents_end")
        @test cells(out)[name] == cells(plain)[name]
    end
end

@testset "xxl extinction: a stale stop file is gone on the next run" begin
    out = mktempdir()
    ext_go(EXT_FED, out; stop_at=6)
    folder = ext_dir(out)
    @test isfile(ext_stop(folder))
    @test ext_go(EXT_FED, out) !== nothing  # it would stop at once if the file still counted
    @test !isfile(ext_stop(folder))
    # With every seed finished there is nothing to run, and the file still goes.
    touch(ext_stop(folder))
    @test ext_go(EXT_FED, out) !== nothing
    @test !isfile(ext_stop(folder))
end

@testset "xxl extinction: --report-only leaves a stop and its checkpoints alone" begin
    out = mktempdir()
    ext_go(EXT_FED, out; stop_at=6)
    folder = ext_dir(out)
    saved = read(ext_ckpt(folder, 5))
    v = rebuild_extinction_report(
        XXL_V1; label="t", seeds=2, first_seed=5, periods=12, out=out, experiment=EXT_FED, io=devnull
    )
    @test v.verdict == "TOO FEW SEEDS"
    @test occursin("- Seeds finished: 0 of 2", read(folder * ".md", String))
    @test isfile(ext_stop(folder))
    @test read(ext_ckpt(folder, 5)) == saved
end

@testset "xxl extinction: resuming with other --jobs gives the same bytes" begin
    # Stopped alone, carried on by two workers.
    out = mktempdir()
    @test ext_go(EXT_WORLD, out; stop_at=6) === nothing
    @test ext_go(EXT_WORLD, out; jobs=2) !== nothing
    @test ext_csvs(ext_dir(out)) == ext_unbroken(EXT_WORLD)
    # Stopped by two workers, carried on alone. Whichever worker writes the stop file, the other stops or finishes.
    out = mktempdir()
    @test ext_go(EXT_WORLD, out; jobs=2, stop_at=4) === nothing
    @test !isfile(ext_dir(out) * ".md")
    @test isfile(ext_ckpt(ext_dir(out), 5)) || isfile(ext_ckpt(ext_dir(out), 6))
    @test ext_go(EXT_WORLD, out; jobs=1) !== nothing
    @test ext_csvs(ext_dir(out)) == ext_unbroken(EXT_WORLD)
end

@testset "xxl extinction: a stop leaves waiting seeds unstarted" begin
    out = mktempdir()
    kw = (label="t", seeds=4, first_seed=5, periods=12, out=out, experiment=EXT_FED, io=devnull)
    @test run_extinction(XXL_V1; kw..., jobs=2, stop_at=3) === nothing
    folder = ext_dir(out; seeds=4)
    done = count(k -> isfile(joinpath(folder, "seed$k.csv")), 5:8)
    @test done < 4
    @test run_extinction(XXL_V1; kw..., jobs=3) !== nothing
    plain = mktempdir()
    run_extinction(XXL_V1; kw..., out=plain, jobs=1)
    @test ext_csvs(folder, 5:8) == ext_csvs(ext_dir(plain; seeds=4), 5:8)
end

@testset "xxl extinction: every so many periods, only the latest checkpoint" begin
    out = mktempdir()
    plan = ext_plan(EXT_WORLD, out)
    mkpath(plan.folder)
    hook = seed_checkpoint(plan.exp, 5, XXL_V1, plan.folder, plan.fingerprint; every=4)
    @test hook.restore() === nothing
    path = ext_ckpt(plan.folder, 5)
    saves = Int[]
    killed = (
        restore=hook.restore,
        period_done=function (m, rows, clock)
            stop = hook.period_done(m, rows, clock)
            @test !stop
            @test isfile(path) == (m.t >= 4)
            @test !isfile(path * ".tmp")
            @test count(endswith(".ckpt"), readdir(plan.folder)) == (m.t >= 4 ? 1 : 0)
            m.t % 4 == 0 && m.t > 0 && push!(saves, filesize(path))
            m.t == 9 && throw(InterruptException())  # killed, between saves, with no chance to save
            return false
        end,
    )
    @test_throws InterruptException timed_seed(plan.exp, 5; xxl=XXL_V1, checkpoint=killed)
    @test length(saves) == 2
    @test load_checkpoint(path, seed_header(plan.exp, 5, XXL_V1, plan.fingerprint)).model.t == 8  # the latest
    write(joinpath(plan.folder, "fingerprint.txt"), plan.fingerprint)
    @test ext_go(EXT_WORLD, out) !== nothing  # the run goes on from t = 8
    @test ext_csvs(plan.folder) == ext_unbroken(EXT_WORLD)
    @test !isfile(path)
    @test CHECKPOINT_EVERY == 100
end

@testset "xxl extinction: the seed loop's hook is optional" begin
    plain, timing = timed_seed(EXT_WORLD, 5; xxl=XXL_V1)
    @test timing !== nothing
    never = (restore=() -> nothing, period_done=(m, rows, clock) -> false)
    hooked, timing2 = timed_seed(EXT_WORLD, 5; xxl=XXL_V1, checkpoint=never)
    @test isequal(hooked, plain)  # some cells are NaN
    @test timing2.agents_end == timing.agents_end
    # Told to stop, a seed gives back its rows so far and no timing.
    at_three = (restore=() -> nothing, period_done=(m, rows, clock) -> m.t == 3)
    rows, stopped = timed_seed(EXT_WORLD, 5; xxl=XXL_V1, checkpoint=at_three)
    @test stopped === nothing
    @test isequal(rows, plain[1:4])
    # Carried on from a save, a seed goes on from the period after it, and its clock runs on from the saved one.
    m = Model(replace_config(EXT_WORLD.config; seed=EXT_WORLD.config.seed + 5))
    saved = (;
        model=m, rows=[[-1.0]], clock=(; setup_s=1000.0, stepping_s=2000.0, metrics_s=3000.0, agents_start=77),
    )
    carried, t3 = timed_seed(EXT_WORLD, 5; checkpoint=(restore=() -> saved, period_done=(m, rows, clock) -> false))
    @test carried[1] == [-1.0]
    @test [row[1] for row in carried[2:end]] == 1:5
    @test t3.setup_s >= 1000 && t3.stepping_s >= 2000 && t3.metrics_s >= 3000
    @test t3.agents_start == 77
    @test_throws ArgumentError timed_seed(EXT_WORLD, 5; xxl=XXL_V1, scorecard=true, checkpoint=never)
    # seed_job passes the hook on only when there is one, so a stand-in without it still works.
    stand_in(exp, k; xl, xxl=nothing) = ([[0.0]], (; seed=k))
    @test seed_job(EXT_WORLD, 5, false, stand_in; xxl=XXL_V1)[1] == [[0.0]]
    with_hook(exp, k; xl, xxl=nothing, scorecard=false, checkpoint) = ([[Float64(checkpoint)]], (; seed=k))
    @test seed_job(EXT_WORLD, 5, false, with_hook; xxl=XXL_V1, checkpoint=7)[1] == [[7.0]]
end

@testset "xxl extinction: a checkpoint from anything else is refused" begin
    out = mktempdir()
    ext_go(EXT_WORLD, out; stop_at=6)
    folder = ext_dir(out)
    path = ext_ckpt(folder, 5)
    original = read(path)
    good = ext_expected(EXT_WORLD, out, 5)
    state = load_checkpoint(path, good)
    @test state.model.t == 6
    refused(header) = begin
        save_checkpoint(path, header, state)
        before = read(path)
        @test_throws ArgumentError load_checkpoint(path, good)
        @test_throws ArgumentError ext_go(EXT_WORLD, out)  # refused before anything runs
        @test read(path) == before  # and kept: it may be someone's hours
        @test !isfile(joinpath(folder, "seed5.csv")) && !isfile(joinpath(folder, "seed6.csv"))
    end
    refused(replace(good, "periods=12" => "periods=13"))
    refused(replace(good, r"code sha256=[0-9a-f]+" => "code sha256=edited"))
    other_rules = replace_rules(XXL_V1; travel_cost=0.05)
    refused(ext_expected(EXT_WORLD, mktempdir(), 5; rules=other_rules))
    refused(ext_expected(EXT_WORLD, out, 6))  # another seed's
    refused(replace(good, r"^julia=[^\n]*"m => "julia=1.0.0"))
    # A world that differs under the same fingerprint (only a test can make one) is another run too.
    refused(ext_expected(EXT_FED, out, 5))
    write(path, original)
    @test ext_go(EXT_WORLD, out) !== nothing
    @test ext_csvs(folder) == ext_unbroken(EXT_WORLD)
end

@testset "xxl extinction: a seed's header names no types, which print by what Main can see" begin
    # A worker's `using Sugarscape` and a main process's `import Sugarscape` would print `Config` differently.
    exp = with_steps(EXT_TINY, 12)
    h = seed_header(exp, 5, XXL_V1, "fp\n")
    @test !occursin("Config(", h) && !occursin("XxlRules(", h)
    @test occursin("seed=5", replace(h, "seed=$(EXT_TINY.config.seed + 5)" => "seed=5"))
    @test h != seed_header(exp, 6, XXL_V1, "fp\n")
    @test h != seed_header(ext_exp(; metabolism=(1, 1)), 5, XXL_V1, "fp\n")
    @test h != seed_header(exp, 5, replace_rules(XXL_V1; travel_cost=0.05), "fp\n")
end

@testset "xxl extinction: a refused checkpoint is a usage error on the command line" begin
    out = mktempdir()
    args = ["--rules", "v1", "--label", "t", "--seeds", "2", "--first-seed", "5", "--periods", "12", "--out", out]
    plan = extinction_plan(XXL_V1, nothing, out, "t", 5, 2, 12)
    mkpath(plan.folder)
    write(joinpath(plan.folder, "fingerprint.txt"), plan.fingerprint)
    save_checkpoint(ext_ckpt(plan.folder, 5), "another run", (; x=1))
    @test redirect_stderr(() -> extinction_main(args), devnull) == 2
    @test !isfile(plan.folder * ".md")
    @test isfile(ext_ckpt(plan.folder, 5))
end

@testset "xxl extinction: a half-written checkpoint cannot be picked up" begin
    out = mktempdir()
    ext_go(EXT_WORLD, out; stop_at=6)
    folder = ext_dir(out)
    path = ext_ckpt(folder, 5)
    whole = read(path)
    good = ext_expected(EXT_WORLD, out, 5)
    @test load_checkpoint(path, good).model.t == 6
    n = length(whole)
    flipped = copy(whole)
    flipped[n ÷ 2] ⊻= 0x01
    damaged = [
        UInt8[],  # nothing written
        whole[1:10],  # cut inside the checksum
        whole[1:40],  # cut inside the header
        whole[1:(n ÷ 2)],  # cut inside the state
        whole[1:(n - 1)],  # one byte short
        [zeros(UInt8, 32); whole[33:end]],  # the checksum never filled in
        flipped,
    ]
    for bytes in damaged
        write(path, bytes)
        @test load_checkpoint(path, good) === nothing
    end
    # A run says so and starts that seed again; the bytes are still those of an unbroken run.
    write(path, damaged[4])
    write(path * ".tmp", whole[1:(n ÷ 2)])  # and a save cut off by a crash, under its temporary name
    said = IOBuffer()
    @test ext_go(EXT_WORLD, out; io=said) !== nothing
    @test occursin("seed 5: its checkpoint is damaged; starting it again", String(take!(said)))
    @test ext_csvs(folder) == ext_unbroken(EXT_WORLD)
    @test !isfile(path * ".tmp")
end

@testset "xxl extinction: a stray temporary checkpoint is never read" begin
    out = mktempdir()
    ext_go(EXT_WORLD, out; stop_at=6)
    folder = ext_dir(out)
    path = ext_ckpt(folder, 5)
    write(ext_ckpt(folder, 6) * ".tmp", read(path))  # whole, but under the temporary name: seed 6 has no checkpoint
    @test ext_go(EXT_WORLD, out) !== nothing
    @test ext_csvs(folder) == ext_unbroken(EXT_WORLD)
    @test !isfile(ext_ckpt(folder, 6) * ".tmp")
end

struct ExtUnsaveable end
Serialization.serialize(::Serialization.AbstractSerializer, ::ExtUnsaveable) = error("the disk is full")

@testset "xxl extinction: a save that fails leaves the last checkpoint" begin
    dir = mktempdir()
    path = joinpath(dir, "seed5.ckpt")
    save_checkpoint(path, "h", (; x=1))
    before = read(path)
    @test_throws ErrorException save_checkpoint(path, "h", (; x=ExtUnsaveable()))
    @test read(path) == before
    @test load_checkpoint(path, "h").x == 1
end

@testset "xxl extinction: a failed periodic save does not end the seed; a failed stop does" begin
    out = mktempdir()
    plan = ext_plan(EXT_WORLD, out)
    mkpath(plan.folder)
    mkpath(ext_ckpt(plan.folder, 5) * ".tmp")  # a folder in the way: every save fails
    hook = seed_checkpoint(plan.exp, 5, XXL_V1, plan.folder, plan.fingerprint; every=4)
    plain, _ = timed_seed(plan.exp, 5; xxl=XXL_V1)
    rows, timing = redirect_stderr(devnull) do
        timed_seed(plan.exp, 5; xxl=XXL_V1, checkpoint=hook)
    end
    @test isequal(rows, plain)
    @test timing !== nothing
    touch(ext_stop(plan.folder))
    @test_throws Exception redirect_stderr(devnull) do
        timed_seed(plan.exp, 5; xxl=XXL_V1, checkpoint=hook)
    end
    @test !isfile(ext_ckpt(plan.folder, 5))
end

# VI-1 itself, where agents link to each other: children, friends, neighbours, the dead that the living still hold, loans.
const EXT_VI1 = find_experiment(EXT_REG, "VI-1")

@testset "xxl extinction: a checkpoint keeps a VI-1 model whole" begin
    m = Model(replace_config(to_xxl(EXT_VI1.config, XXL_DEFAULTS); seed=7))
    for _ in 1:24
        step!(m)
    end
    @test !isempty(m.loans)
    @test any(a -> !isempty(a.children), m.agents)
    @test any(a -> !isempty(a.friends), m.agents)
    @test any(a -> any(c -> !c.alive, a.children) || any(n -> !n.alive, a.neighbors), m.agents)  # the dead still held
    path = joinpath(mktempdir(), "seed.ckpt")
    save_checkpoint(path, "h", (; model=m))
    r = load_checkpoint(path, "h").model
    @test r.t == m.t && r.next_id == m.next_id
    @test r.rng == m.rng
    @test r.config == m.config
    # One agent, one object: the grid, the living, every list and the loans all point at it.
    @test all(r.grid[a.x + 1, a.y + 1] === a for a in r.agents)
    @test all(r.agents[a.slot] === a for a in r.agents)
    by_id = Dict(a.id => a for a in r.agents)
    @test all(n.alive ? by_id[n.id] === n : !haskey(by_id, n.id) for a in r.agents for n in a.neighbors)
    @test all(c.alive ? by_id[c.id] === c : !haskey(by_id, c.id) for a in r.agents for c in a.children)
    book = Set(objectid(l) for l in r.loans)
    @test all(objectid(l) in book for ls in values(r.debts) for l in ls)
    @test sort(collect(keys(r.debts))) == sort(collect(keys(m.debts)))
    @test r.lent == m.lent
    # Every agent field, in the same order, with the dead that are still held.
    plain(x) = [getfield(x, f) for f in fieldnames(Agent) if !(f in (:neighbors, :children, :friends))]
    ids(list) = [(x isa Tuple ? (x[1].id, x[2]) : x.id) for x in list]
    for (a, b) in zip(m.agents, r.agents)
        @test isequal(plain(a), plain(b))
        @test ids(a.neighbors) == ids(b.neighbors)
        @test ids(a.children) == ids(b.children)
        @test ids(a.friends) == ids(b.friends)
    end
    # Both go on as one: the same draws, the same metrics, to the bit.
    for _ in 1:6
        step!(m)
        step!(r)
        @test isequal(collect_metrics(m), collect_metrics(r))
    end
    @test r.rng == m.rng
    @test all(isequal(a.sugar, b.sugar) && a.id == b.id for (a, b) in zip(m.agents, r.agents))
end

@testset "xxl extinction: no field of the model or an agent escapes the flat table" begin
    m = Model(replace_config(EXT_TINY.config; seed=1))
    flat = flat_model(m)
    r = model_from_flat(flat)
    @test all(isequal(getfield(r, f), getfield(m, f)) for f in (:t, :next_id, :rng, :viable_fallbacks))
    # A new field holding agents would drag the whole graph into one recursive save: it must be named, or the save fails.
    linked(T) = occursin(r"\b(Agent|Loan|Exchange)\b", string(T))
    for f in fieldnames(Model)
        linked(fieldtype(Model, f)) && @test f in Sugarscape.MODEL_LINK_FIELDS
    end
    for f in fieldnames(Agent)
        linked(fieldtype(Agent, f)) && @test f in Sugarscape.AGENT_LINK_FIELDS
    end
    for f in Sugarscape.MODEL_LINK_FIELDS
        @test f in fieldnames(Model)
    end
end

@testset "xxl extinction: VI-1 stopped and resumed by other workers gives the same bytes" begin
    kw = (label="vi", seeds=2, first_seed=20, periods=24, io=devnull, experiment=EXT_VI1)
    whole, broken = mktempdir(), mktempdir()
    run_extinction(XXL_DEFAULTS; kw..., jobs=1, out=whole)
    @test run_extinction(XXL_DEFAULTS; kw..., jobs=1, out=broken, stop_at=12) === nothing
    @test run_extinction(XXL_DEFAULTS; kw..., jobs=2, out=broken) !== nothing
    dir(out) = ext_dir(out; label="vi", first=20, seeds=2, periods=24)
    @test ext_csvs(dir(broken), (20, 21)) == ext_csvs(dir(whole), (20, 21))
end
