# The runner writes the Python runner's results layout (experiments/run.py).
using Sugarscape, Test

const REG = load_registry()
const TINY = find_experiment(REG, "TEST-tiny")

@testset "format_value" begin
    @test Sugarscape.format_value(400.0) == "400.0"
    @test Sugarscape.format_value(NaN) == "nan"
    @test Sugarscape.format_value(Inf) == "inf"
    @test Sugarscape.format_value(-Inf) == "-inf"
    @test Sugarscape.format_value(-0.0) == "-0.0"
    @test Sugarscape.format_value(3) == "3"
    @test parse(Float64, Sugarscape.format_value(1e300)) == 1e300
    @test parse(Float64, Sugarscape.format_value(1e-300)) == 1e-300
    @test parse(Float64, Sugarscape.format_value(0.1 + 0.2)) == 0.1 + 0.2
end

@testset "matching_ids" begin
    ids = [e.id for e in REG]
    sweep = Sugarscape.matching_ids("II-5", ids)
    @test length(sweep) == 18 && all(startswith(i, "II-5/") for i in sweep)
    @test Sugarscape.matching_ids("II-4", ids) == ["II-4"]
    @test isempty(Sugarscape.matching_ids("II", ids))
end

@testset "run_experiment writes the Python layout" begin
    out = mktempdir()
    Sugarscape.run_experiment(TINY; out=out, note="quiet machine")
    folder = joinpath(out, "TEST-tiny")
    @test sort(readdir(folder)) ==
        ["fingerprint.txt", "machine.txt", "seed0.csv", "seed1.csv", "timing.csv"]
    lines = readlines(joinpath(folder, "seed0.csv"))
    @test lines[1] == "t," * join(METRIC_COLUMNS, ",")
    @test length(lines) == 7 && [split(l, ",")[1] for l in lines[2:end]] == string.(0:5)
    @test split(lines[2], ",")[2] == "20.0"  # population at t = 0
    timing = readlines(joinpath(folder, "timing.csv"))
    @test timing[1] == "seed,periods,setup_s,stepping_s,metrics_s,agents_start,agents_end"
    @test length(timing) == 3 &&
        startswith(timing[2], "0,5,") &&
        endswith(timing[3], ",20," * split(timing[3], ",")[end])
    @test read(joinpath(folder, "fingerprint.txt"), String) == "julia\n" * TINY.fingerprint
    machine = read(joinpath(folder, "machine.txt"), String)
    @test occursin("julia = $(VERSION)", machine) && occursin("jobs = 1", machine)
    @test occursin("user_note = quiet machine", machine) &&
        occursin("warm_up_s = ", machine)
    @test !occursin("share the processor", machine)
end

@testset "more jobs than seeds" begin  # Review Focus 5
    out = mktempdir()
    Sugarscape.run_experiment(TINY; jobs=3, seeds=2, out=out)
    folder = joinpath(out, "TEST-tiny")
    @test isfile(joinpath(folder, "seed0.csv")) && isfile(joinpath(folder, "seed1.csv"))
    machine = read(joinpath(folder, "machine.txt"), String)
    @test occursin("jobs = 3", machine)
    @test occursin("note = timings taken with --jobs 3 share the processor", machine)
end

@testset "a failing seed names itself and leaves old results" begin  # Review Focus 5
    out = mktempdir()
    folder = mkpath(joinpath(out, "TEST-tiny"))
    write(joinpath(folder, "seed0.csv"), "old")
    failing(exp, k; xl=false) =
        k == 1 ? error("boom") : Sugarscape.timed_seed(exp, k; xl=xl)
    err = try
        Sugarscape.run_experiment(TINY; out=out, run_seed=failing)
        nothing
    catch e
        sprint(showerror, e)
    end
    @test err !== nothing && occursin("TEST-tiny", err) && occursin("seed 1", err)
    @test read(joinpath(folder, "seed0.csv"), String) == "old"
end

@testset "xl run" begin
    out = mktempdir()
    Sugarscape.run_experiment(TINY; xl=true, seeds=1, out=out)
    folder = joinpath(out, "TEST-tiny")
    @test read(joinpath(folder, "fingerprint.txt"), String) ==
        "julia\n" * TINY.xl_fingerprint
    @test split(readlines(joinpath(folder, "seed0.csv"))[2], ",")[2] == "2000.0"
end

@testset "main" begin
    @test Sugarscape.main(["no-such-id"]) == 2
    @test Sugarscape.main(["TEST-tiny", "--bogus"]) == 2
    out = mktempdir()
    @test Sugarscape.main(["TEST-tiny", "--seeds", "1", "--out", out]) == 0
    @test isfile(joinpath(out, "TEST-tiny", "seed0.csv"))
end
