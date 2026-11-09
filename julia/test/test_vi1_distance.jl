# VI-1-distance (docs/superpowers/specs/2026-11-09-vi1-distance-design.md): VI-1-combat with fight and fear drawn on
# cultural distance (combat_hostility = 0.5), run through the combat study, which also keeps the kills file.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: vi1_combat_experiment, vi1_distance_experiment, VI1_DISTANCE_ID, combat_study_args, run_combat_world

const VARIANT_LINE = "variant: VI-1-distance combat_hostility=0.5 (fight and fear drawn on cultural distance)\n"

@testset "test_vi1_distance_config" begin
    c = vi1_combat_experiment()
    e = vi1_distance_experiment()
    @test VI1_DISTANCE_ID == "VI-1-distance" && e.id == "VI-1-distance"
    @test e.rules == c.rules && e.steps == c.steps
    for cfg in (e.config, e.xl_config)
        @test cfg.combat_hostility == 0.5 && cfg.combat_alpha == Inf
    end
    @test c.config.combat_hostility == 0.0 && c.xl_config.combat_hostility == 0.0
    @test startswith(e.fingerprint, c.fingerprint) && endswith(e.fingerprint, VARIANT_LINE)
    @test startswith(e.xl_fingerprint, c.xl_fingerprint) && endswith(e.xl_fingerprint, VARIANT_LINE)
end

@testset "test_vi1_distance_study_args" begin
    a = combat_study_args(["--world", "today", "--exp", "VI-1-distance"])
    @test a.exp == "VI-1-distance" && a.world == "today"
end

@testset "test_vi1_distance_runs" begin
    a, b = mktempdir(), mktempdir()
    fa = run_combat_world("book", "VI-1-distance"; seeds=1, periods=4, out=a, io=devnull)
    fb = run_combat_world("book", "VI-1-distance"; seeds=1, periods=4, out=b, io=devnull)
    for f in ("seed0.csv", "seed0-combat.csv", "seed0-kills.csv")
        @test isfile(joinpath(fa, f))
        @test read(joinpath(fa, f)) == read(joinpath(fb, f))
    end
    lines = readlines(joinpath(fa, "seed0-kills.csv"))
    @test lines[1] == "t,distance,same_label"
    for l in lines[2:end]
        t, d, s = parse.(Int, split(l, ","))
        @test t in 1:4 && d in 0:11 && s in 0:1
    end
    @test !isfile(joinpath(fa, "seed0-kills.csv.tmp"))
end

@testset "test_no_kills_file_without_hostility" begin
    folder = run_combat_world("book", "VI-1-combat"; seeds=1, periods=4, out=mktempdir(), io=devnull)
    @test isfile(joinpath(folder, "seed0-combat.csv"))
    @test !isfile(joinpath(folder, "seed0-kills.csv"))
end
