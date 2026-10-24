# Ports tests/test_combat.py.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function combat_model(alpha=Inf)
    return tiny_model(zeros(Int, 12, 12); tag_length=1, combat_alpha=alpha, vision=(1, 4))
end

function tribe_agent(m, x, y, tag, sugar; vision=4)
    return tag!(put_agent(m, x, y; vision=vision, sugar=sugar), [tag])
end

@testset "test_attacks_smaller_enemy_and_takes_wealth" begin  # p.83
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 20.0)
    r = tribe_agent(m, 3, 1, 1, 8.0)
    combat_move!(m, a)
    @test (a.x, a.y) == (3, 1) && a.sugar == 28.0 && !r.alive
end

@testset "test_reward_capped_at_alpha" begin
    m = combat_model(2.0)
    a = tribe_agent(m, 1, 1, 0, 20.0)
    r = tribe_agent(m, 3, 1, 1, 8.0)
    combat_move!(m, a)
    @test a.sugar == 22.0 && !r.alive
end

@testset "test_never_attacks_own_tribe_or_wealthier" begin
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 20.0)
    tribe_agent(m, 2, 1, 0, 1.0)
    tribe_agent(m, 1, 2, 1, 25.0)
    m.landscape.sugar[5, 2] = 1.0  # empty site (4, 1), out of the rich Red's sight lines
    combat_move!(m, a)
    @test (a.x, a.y) == (4, 1)
end

@testset "test_retaliation_blocks_attack" begin  # p.82
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 20.0)
    r = tribe_agent(m, 3, 1, 1, 8.0)
    tribe_agent(m, 5, 1, 1, 30.0)  # bigger Red within vision of the target: 30 > 28
    combat_move!(m, a)
    @test r.alive && (a.x, a.y) != (3, 1)
end

@testset "test_stays_when_nothing_is_safe" begin
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 2.0)
    for (x, y) in ((1, 3), (3, 1), (1, 11), (11, 1))
        tribe_agent(m, x, y, 1, 50.0)
    end
    combat_move!(m, a)
    @test (a.x, a.y) == (1, 1)
end

@testset "test_dead_victim_never_acts" begin
    cfg = Config(;
        tag_length=11,
        combat_alpha=Inf,
        endowment=(25, 50),
        seed=0,
        initial_blocks=[("blue", 0, 0, 20, 20, 270), ("red", 30, 30, 20, 20, 270)],
    )
    m = Model(cfg)
    ok = true
    for _ in 1:30
        step!(m)
        ok &= all(a.alive && agent_at(m, a.x, a.y) === a for a in m.agents)
        ok &= length(Set((a.x, a.y) for a in m.agents)) == length(m.agents)
    end
    @test ok
end

@testset "test_culture_runs_in_the_turn" begin
    m = Model(Config(; tag_length=11, culture=true, initial_population=400, seed=0))
    before = Dict(a.id => a.tags for a in m.agents)
    run!(m, 5)
    @test any(a.tags != before[a.id] for a in m.agents if haskey(before, a.id))
    @test any(!isempty(a.friends) for a in m.agents)
end
