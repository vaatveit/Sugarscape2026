# VI-1-combat (docs/superpowers/specs/2026-11-08-vi1-combat-design.md, "The experiment"): VI-1 with rule C at
# alpha = Inf, taking sugar and spice, run through the combat study in each world.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: vi1_combat_experiment, VI1_COMBAT_ID, combat_plan, run_combat_world, load_registry, find_experiment

@testset "test_vi1_combat_config" begin
    e = vi1_combat_experiment()
    @test VI1_COMBAT_ID == "VI-1-combat"
    @test e.id == "VI-1-combat"
    @test e.config.combat_alpha == Inf && e.xl_config.combat_alpha == Inf
    @test e.config.spice && e.config.credit == (10, 10.0) && e.config.sex && e.config.culture
    @test !e.config.replacement && !e.config.replacement_same_tribe
    @test e.steps == 500
end

@testset "test_vi1_combat_fingerprint" begin
    e = vi1_combat_experiment()
    vi1 = find_experiment(load_registry(), "VI-1")
    @test startswith(e.fingerprint, vi1.fingerprint)
    @test e.fingerprint != vi1.fingerprint
    @test occursin("variant: VI-1-combat", e.fingerprint)
    @test startswith(e.xl_fingerprint, vi1.xl_fingerprint)
    @test e.xl_fingerprint != vi1.xl_fingerprint
    @test occursin("variant: VI-1-combat", e.xl_fingerprint)
end

@testset "test_vi1_combat_plan" begin
    tmp = mktempdir()
    p = combat_plan("today", "VI-1-combat", tmp, 0, 2, 5)
    @test p.exp.id == "VI-1-combat" && p.periods == 5
    @test basename(p.folder) == "combat-today-VI-1-combat-s0-2-p5"
    @test occursin("variant: VI-1-combat", p.fingerprint)
    @test combat_plan("book", "VI-1-combat", tmp, 0, 1, nothing).periods == 500
    @test_throws ArgumentError combat_plan("book", "VI-1", tmp, 0, 1, nothing)
end

@testset "test_vi1_combat_runs_in_each_world" begin
    for w in ("book", "xl", "today")
        tmp = mktempdir()
        folder = run_combat_world(w, "VI-1-combat"; seeds=1, periods=4, out=tmp, io=devnull)
        for f in ("seed0.csv", "seed0-combat.csv")
            @test isfile(joinpath(folder, f))
            @test countlines(joinpath(folder, f)) == 1 + 5
        end
    end
end

@testset "test_vi1_combat_victim_never_acts" begin
    m = tiny_model(
        zeros(Int, 12, 12);
        tag_length=1,
        combat_alpha=Inf,
        vision=(1, 4),
        spice=true,
        sex=true,
        culture=true,
        trade=true,
        credit=(10, 10.0),
        disease_list=3,
        replacement=false,
    )
    killer = tag!(put_agent(m, 1, 1; vision=4, sugar=20.0), [0])
    victim = tag!(put_agent(m, 3, 1; vision=4, sugar=8.0), [1])
    killer.spice, victim.spice = 20.0, 8.0
    killer.spice_metabolism = victim.spice_metabolism = 1
    victim.vision = 0  # it stays where it is, whenever it comes in the order, for the killer to reach along the row
    before = length(m.agents)
    step!(m)
    @test !victim.alive
    @test victim ∉ m.agents
    @test victim.id in m.killed
    @test victim.sugar == 0 && victim.spice == 0
    @test killer.alive
    @test length(m.agents) == before - 1
end

@testset "test_vi1_combat_loot_of_a_negative_holding_is_zero" begin
    # Rule S's gift can leave a living agent below 0 in spice until its own turn: the loot takes nothing of it.
    m = tiny_model(zeros(Int, 12, 12); tag_length=1, combat_alpha=Inf, spice=true)
    victim = put_agent(m, 3, 1; sugar=8.0)
    victim.spice = -3.0
    @test Sugarscape.loot(m, victim) == (8.0, 0.0)
    victim.sugar = -1.0
    @test Sugarscape.loot(m, victim) == (0.0, 0.0)
end
