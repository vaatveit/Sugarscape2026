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
