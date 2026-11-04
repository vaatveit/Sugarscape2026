# xxl (stage 5): the trade study tool (docs/superpowers/specs/2026-11-03-xxl-trade-design.md). A short arm of VI-1 is the
# extinction run's own plus the readings' files; resuming, the fingerprint, the command line, IV-A3, the disease list's reader
# and the xl reference are checked on runs of a few periods.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape:
    run_trade_arm,
    run_trade_xl,
    trade_study_args,
    trade_study_main,
    trade_name,
    trade_window,
    run_extinction,
    extinction_name,
    read_seed_csv,
    read_list_run,
    CreditOptions,
    RESULTS_XXL,
    scorecard_name,
    result_dir,
    xl_current,
    with_steps

const TS_RULES = replace_rules(XXL_DEFAULTS; trade_move="local", trade_guard=5)

# One seed (20) of a 12-period arm into `out`, quietly.
ts_arm(out; rules=TS_RULES, kw...) = run_trade_arm(rules; label="t", seeds=1, first_seed=20, periods=12, out=out, io=devnull, kw...)

@testset "xxl trade study: the window and the name" begin
    @test trade_window(500) == (401, 500)
    @test trade_window(300) == (201, 300)
    @test trade_window(12) == (1, 12)
    @test trade_name("a", "VI-1", 80, 20, 500) == "trade-a-VI-1-s80-20-p500"
    @test trade_name("a", "II-5/x", 1, 2, 3) == "trade-a-II-5_x-s1-2-p3"
end

@testset "xxl trade study: one seed is the extinction run's, with the readings' files" begin
    out = mktempdir()
    folder = ts_arm(out)
    @test basename(folder) == "trade-t-VI-1-s20-1-p12"
    @test dirname(folder) == out
    text = read(joinpath(folder, "fingerprint.txt"), String)
    @test endswith(text, "periods=12\ntrade readings: window=(1, 12)\n")
    @test !occursin("trade: off", text)

    plain = mktempdir()
    run_extinction(TS_RULES; label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=plain, io=devnull)
    theirs = joinpath(plain, extinction_name("t", 20, 1, 12))
    @test read(joinpath(folder, "seed20.csv")) == read(joinpath(theirs, "seed20.csv"))

    trade, agents = (read_seed_csv(joinpath(folder, "seed20-$kind.csv")) for kind in ("trade", "agents"))
    @test trade[1][1:3] == ["t", "healthy", "recovering"]
    @test trade[2][:, 1] == 1.0:12.0
    @test agents[1][1] == "id"
    @test size(agents[2], 1) > 0
    @test isfile(joinpath(folder, "seed20.timing.csv"))
    @test isfile(joinpath(folder, "machine.txt"))
    @test !any(endswith(".tmp"), readdir(folder))
end

@testset "xxl trade study: a second call skips what is done, another world is refused" begin
    out = mktempdir()
    folder = ts_arm(out)
    names = ("seed20.csv", "seed20-trade.csv", "seed20-agents.csv", "seed20.timing.csv")
    before = [mtime(joinpath(folder, n)) for n in names]
    sleep(0.05)
    @test ts_arm(out) == folder
    @test [mtime(joinpath(folder, n)) for n in names] == before

    @test_throws ArgumentError ts_arm(out; rules=XXL_DEFAULTS)
    @test_throws ArgumentError ts_arm(out; options=CreditOptions(; trade_off=true))
end

@testset "xxl trade study: a seed cut short runs again" begin
    out = mktempdir()
    folder = ts_arm(out)
    whole = read(joinpath(folder, "seed20.csv"))
    for name in ("seed20-trade.csv", "seed20.csv")  # a stop between the files
        rm(joinpath(folder, name))
    end
    write(joinpath(folder, "seed20-agents.csv.tmp"), "half")
    ts_arm(out)
    @test read(joinpath(folder, "seed20.csv")) == whole
    @test isfile(joinpath(folder, "seed20-trade.csv"))
    @test !isfile(joinpath(folder, "seed20-agents.csv.tmp"))
end

@testset "xxl trade study: seeds in workers write the same files" begin
    out1, out2 = mktempdir(), mktempdir()
    kw = (label="t", seeds=2, first_seed=20, periods=6, io=devnull)
    a = run_trade_arm(TS_RULES; kw..., out=out1, jobs=1)
    b = run_trade_arm(TS_RULES; kw..., out=out2, jobs=2)
    for k in (20, 21), name in ("seed$k.csv", "seed$k-trade.csv", "seed$k-agents.csv")
        @test read(joinpath(a, name)) == read(joinpath(b, name))
    end
end

@testset "xxl trade study: IV-A3 runs, with no disease" begin
    out = mktempdir()
    folder = run_trade_arm(TS_RULES; label="a3", experiment="IV-A3", seeds=1, first_seed=20, periods=12, out=out, io=devnull)
    @test basename(folder) == "trade-a3-IV-A3-s20-1-p12"
    header, M = read_seed_csv(joinpath(folder, "seed20-trade.csv"))
    @test all(M[:, findfirst(==("sick"), header)] .== 0)
    @test_throws ArgumentError run_trade_arm(TS_RULES; label="x", experiment="II-4", out=out, io=devnull)
end

@testset "xxl trade study: trade off is in the world and the fingerprint" begin
    out = mktempdir()
    folder = ts_arm(out; options=CreditOptions(; trade_off=true))
    text = read(joinpath(folder, "fingerprint.txt"), String)
    @test occursin("\ntrade: off\n", text)
    @test endswith(text, "trade readings: window=(1, 12)\n")
    header, M = read_seed_csv(joinpath(folder, "seed20.csv"))
    @test all(M[:, findfirst(==("trades"), header)] .== 0)
end

@testset "xxl trade study: the disease list's reader takes a study folder" begin
    out = mktempdir()
    folder = ts_arm(out)
    run = read_list_run("study", folder)
    @test run.periods == 12
    @test run.planned == 1
    @test length(run.seeds) == 1
    @test run.seeds[1].series.seed == 20
    @test run.folder == "trade-t-VI-1-s20-1-p12"
    @test (run.count, run.founder, run.lengths) == (3, 1, (9, 10))  # list D, the defaults
end

@testset "xxl trade study: the command line" begin
    a = trade_study_args(["--label", "x", "--trade-off", "--set", "trade_move=local", "--set", "trade_guard=5",
                          "--experiment", "IV-A3", "--seeds", "3", "--first-seed", "4", "--periods", "50", "--jobs", "2",
                          "--out", "o"])
    @test a.options == CreditOptions(; trade_off=true)
    @test a.rules == replace_rules(XXL_DEFAULTS; trade_move="local", trade_guard=5)
    @test (a.label, a.experiment, a.seeds, a.first_seed, a.periods, a.jobs, a.out, a.xl) ==
          ("x", "IV-A3", 3, 4, 50, 2, "o", false)
    d = trade_study_args(["--label", "x"])
    @test d.options == CreditOptions() && d.rules == XXL_DEFAULTS
    @test (d.experiment, d.seeds, d.first_seed, d.periods, d.jobs, d.out) == ("VI-1", 20, 80, 500, 1, RESULTS_XXL)
    x = trade_study_args(["--xl", "--seeds", "2"])
    @test x.xl && x.seeds == 2

    for bad in (String[], ["--seeds", "3"], ["--label"], ["--label", "x", "--experiment", "II-4"],
                ["--label", "x", "--seeds", "0"], ["--label", "x", "--periods", "2"], ["--label", "x", "--set", "nope=1"],
                ["--label", "x", "--bogus"], ["--xl", "--trade-off"], ["--xl", "--label", "x"], ["--xl", "--set", "free_step=2"])
        @test_throws ArgumentError trade_study_args(bad)
    end
    quiet(f) = redirect_stderr(f, devnull)
    @test quiet(() -> trade_study_main(String[])) == 1
end

@testset "xxl trade study: a refused folder is a usage error, a finished run returns 0" begin
    out = mktempdir()
    args = ["--label", "m", "--seeds", "1", "--first-seed", "20", "--periods", "6", "--out", out]
    @test redirect_stdout(() -> trade_study_main(args), devnull) == 0
    @test isfile(joinpath(out, "trade-m-VI-1-s20-1-p6", "seed20-trade.csv"))
    other = [args; ["--trade-off"]]
    @test redirect_stderr(() -> trade_study_main(other), devnull) == 1
end

@testset "xxl trade study: the xl reference is skipped when it is there" begin
    out = mktempdir()
    exp = with_steps(find_experiment(load_registry(), "VI-1"), 4)
    folder = result_dir(joinpath(out, scorecard_name("xl", 80, 2)), "VI-1")
    mkpath(folder)
    write(joinpath(folder, "fingerprint.txt"), "julia\n" * exp.xl_fingerprint)
    for k in (80, 81)
        write(joinpath(folder, "seed$k.csv"), join(fill("t,x", 6), "\n") * "\n")
    end
    @test xl_current(folder, exp, 80:81)
    before = [mtime(joinpath(folder, n)) for n in readdir(folder)]
    log = IOBuffer()
    @test run_trade_xl(; first_seed=80, seeds=2, periods=4, out=out, io=log) == folder
    @test occursin("reusing", String(take!(log)))
    @test [mtime(joinpath(folder, n)) for n in readdir(folder)] == before
    @test readdir(folder) == ["fingerprint.txt", "seed80.csv", "seed81.csv"]
end
