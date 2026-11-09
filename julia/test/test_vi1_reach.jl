# VI-1-near, VI-1-far and VI-1-far-speed (docs/superpowers/plans/2026-11-09-vi1-reach.md, Task 5): VI-1-distance with
# combat's or culture's reach changed, run through the combat study. VI-1-far-speed needs xxl speed, so only today's world.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: vi1_distance_experiment, vi1_near_experiment, vi1_far_experiment, vi1_far_speed_experiment
using Sugarscape: VI1_NEAR_ID, VI1_FAR_ID, VI1_FAR_SPEED_ID, JULIA_COMBAT_EXPS, COMBAT_EXPS, COMBAT_USAGE
using Sugarscape: combat_study_args, combat_plan, run_combat_world, world_config, xxl_on

const REACH_CASES = (
    (VI1_NEAR_ID, vi1_near_experiment, :combat_reach, "neighbours",
     "variant: VI-1-near combat_reach=neighbours (attack, fear and movement within culture's reach)\n"),
    (VI1_FAR_ID, vi1_far_experiment, :culture_reach, "sight",
     "variant: VI-1-far culture_reach=sight (culture reaches everyone combat sees)\n"),
    (VI1_FAR_SPEED_ID, vi1_far_speed_experiment, :culture_reach, "attack",
     "variant: VI-1-far-speed culture_reach=attack (culture reaches everyone within speed)\n"),
)

@testset "test_reach_ids_and_table" begin
    @test (VI1_NEAR_ID, VI1_FAR_ID, VI1_FAR_SPEED_ID) == ("VI-1-near", "VI-1-far", "VI-1-far-speed")
    @test sort(collect(keys(JULIA_COMBAT_EXPS))) ==
          ["VI-1-assim", "VI-1-assim-random", "VI-1-combat", "VI-1-distance", "VI-1-far", "VI-1-far-speed", "VI-1-near"]
    @test COMBAT_EXPS == ("III-9", "III-11", "III-12", "III-13", "III-14")
    for id in keys(JULIA_COMBAT_EXPS)
        @test occursin(id, COMBAT_USAGE)
        @test JULIA_COMBAT_EXPS[id]().id == id
    end
end

@testset "test_reach_experiment_configs" begin
    d = vi1_distance_experiment()
    for (id, build, field, value, line) in REACH_CASES
        e = build()
        @test e.id == id && e.rules == d.rules && e.steps == d.steps && e.seeds == d.seeds
        for cfg in (e.config, e.xl_config)
            @test getfield(cfg, field) == value
            @test cfg.combat_hostility == 0.5 && cfg.combat_alpha == Inf
        end
        @test startswith(e.fingerprint, d.fingerprint) && e.fingerprint == d.fingerprint * line
        @test startswith(e.xl_fingerprint, d.xl_fingerprint) && e.xl_fingerprint == d.xl_fingerprint * line
    end
    @test d.config.combat_reach == "vision" && d.config.culture_reach == "neighbours"
end

@testset "test_far_speed_today_world_attacks" begin
    e = vi1_far_speed_experiment()
    cfg = world_config(e, "today")
    @test cfg.culture_reach == "attack" && xxl_on(cfg, :speed) && cfg.combat_alpha == Inf
    @test world_config(vi1_far_experiment(), "today").culture_reach == "sight"
    @test world_config(vi1_near_experiment(), "today").combat_reach == "neighbours"
end

@testset "test_reach_study_args" begin
    for id in keys(JULIA_COMBAT_EXPS)
        a = combat_study_args(["--world", "today", "--exp", id])
        @test a.exp == id && a.world == "today"
        @test combat_plan("today", id, mktempdir(), 0, 1, 4).exp.id == id
    end
    for id in (VI1_NEAR_ID, VI1_FAR_ID), w in ("book", "xl")
        @test combat_study_args(["--world", w, "--exp", id]).exp == id
    end
    for w in ("book", "xl")
        @test_throws ArgumentError combat_study_args(["--world", w, "--exp", VI1_FAR_SPEED_ID])
        @test_throws ArgumentError combat_plan(w, VI1_FAR_SPEED_ID, mktempdir(), 0, 1, 4)
    end
    err = try combat_study_args(["--world", "today", "--exp", "nope"]) catch e; e end
    @test err isa ArgumentError
    @test occursin("III-14, VI-1-assim, VI-1-assim-random, VI-1-combat, VI-1-distance, VI-1-far, VI-1-far-speed, VI-1-near", err.msg)
end

@testset "test_reach_runs" begin
    for id in (VI1_NEAR_ID, VI1_FAR_ID)
        folder = run_combat_world("book", id; seeds=1, periods=4, out=mktempdir(), io=devnull)
        for f in ("seed0.csv", "seed0-combat.csv", "seed0-kills.csv")
            @test isfile(joinpath(folder, f))
        end
    end
end
