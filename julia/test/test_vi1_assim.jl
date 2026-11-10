# VI-1-assim and VI-1-assim-random (docs/superpowers/plans/2026-11-09-assimilation-distance.md, Task 2): VI-1-distance
# with rule K by cultural distance, run through the combat study. VI-1-assim-k4 is VI-1-assim with combat_curve 4, the
# setting the 11-09 sweep picked.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: vi1_distance_experiment, vi1_assim_experiment, vi1_assim_random_experiment, vi1_assim_k4_experiment
using Sugarscape: VI1_ASSIM_ID, VI1_ASSIM_RANDOM_ID, VI1_ASSIM_K4_ID, JULIA_COMBAT_EXPS, COMBAT_USAGE
using Sugarscape: combat_study_args, combat_plan, run_combat_world, world_config

const ASSIM_CASES = (
    (VI1_ASSIM_ID, vi1_assim_experiment, "distance",
     "variant: VI-1-assim culture_rule=distance (copy a differing tag with p = 1 - fight chance)\n"),
    (VI1_ASSIM_RANDOM_ID, vi1_assim_random_experiment, "distance-random",
     "variant: VI-1-assim-random culture_rule=distance-random (copy a random tag with p = 1 - fight chance)\n"),
    (VI1_ASSIM_K4_ID, vi1_assim_k4_experiment, "distance",
     "variant: VI-1-assim-k4 culture_rule=distance combat_curve=4 (copy a differing tag with p = 1 - 0.5 (d/11)^4)\n"),
)

@testset "test_assim_ids_and_table" begin
    @test (VI1_ASSIM_ID, VI1_ASSIM_RANDOM_ID, VI1_ASSIM_K4_ID) == ("VI-1-assim", "VI-1-assim-random", "VI-1-assim-k4")
    for id in (VI1_ASSIM_ID, VI1_ASSIM_RANDOM_ID, VI1_ASSIM_K4_ID)
        @test haskey(JULIA_COMBAT_EXPS, id) && JULIA_COMBAT_EXPS[id]().id == id
        @test occursin(id, COMBAT_USAGE)
    end
end

@testset "test_assim_experiment_configs" begin
    d = vi1_distance_experiment()
    for (id, build, rule, line) in ASSIM_CASES
        e = build()
        @test e.id == id && e.rules == d.rules && e.steps == d.steps && e.seeds == d.seeds
        for cfg in (e.config, e.xl_config)
            @test cfg.culture_rule == rule && cfg.combat_hostility == 0.5
        end
        @test e.fingerprint == d.fingerprint * line
        @test e.xl_fingerprint == d.xl_fingerprint * line
        @test world_config(e, "today").culture_rule == rule
        @test world_config(e, "xl").culture_rule == rule
    end
    @test d.config.culture_rule == "random"
end

@testset "test_assim_study_args_and_runs" begin
    for (id, _, _, _) in ASSIM_CASES
        a = combat_study_args(["--world", "today", "--exp", id])
        @test a.exp == id && a.world == "today"
        @test combat_plan("today", id, mktempdir(), 0, 1, 4).exp.id == id
        folder = run_combat_world("book", id; seeds=1, periods=4, out=mktempdir(), io=devnull)
        for f in ("seed0.csv", "seed0-combat.csv", "seed0-kills.csv")
            @test isfile(joinpath(folder, f))
        end
    end
end

@testset "test_assim_k4_curve" begin
    e = vi1_assim_k4_experiment()
    for cfg in (e.config, e.xl_config, world_config(e, "today"), world_config(e, "xl"))
        @test cfg.combat_curve == 4.0 && cfg.combat_hostility == 0.5 && cfg.culture_rule == "distance"
    end
    # the other two stay on the straight line
    for build in (vi1_assim_experiment, vi1_assim_random_experiment)
        @test world_config(build(), "today").combat_curve == 1.0
    end
end
