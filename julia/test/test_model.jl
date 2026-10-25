# Ports tests/test_model.py (the numpy-stream pins have no Julia counterpart).
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

@testset "test_random_placement_is_distinct_and_seeded" begin
    a, b = Model(Config(; seed=7)), Model(Config(; seed=7))
    pos = [(g.x, g.y) for g in a.agents]
    @test length(pos) == 400 == length(Set(pos))
    @test pos == [(g.x, g.y) for g in b.agents]
    @test all(agent_at(a, g.x, g.y) === g for g in a.agents)
    @test pos != [(g.x, g.y) for g in Model(Config(; seed=8)).agents]
end

@testset "test_genetics_within_ranges" begin
    m = Model(Config(; seed=1))
    @test issubset(Set(g.vision for g in m.agents), 1:6)
    @test issubset(Set(g.metabolism for g in m.agents), 1:4)
    @test all(5 <= g.sugar <= 25 && g.sugar == g.initial_sugar for g in m.agents)
    @test length(Set(g.vision for g in m.agents)) == 6  # every value drawn
end

@testset "test_block_placement_inside_block" begin
    m = Model(Config(; placement="block", block=(0, 0, 20, 20), initial_population=300))
    @test length(m.agents) == 300
    @test all(g.x < 20 && g.y < 20 for g in m.agents)
end

@testset "test_overfull_placement_raises" begin
    cfg = Config(; placement="block", block=(0, 0, 10, 10), initial_population=101)
    @test_throws ArgumentError Model(cfg)
end

@testset "test_random_empty_site_none_when_full" begin
    m = tiny_model(ones(Int, 3, 3))
    for x in 0:2, y in 0:2
        put_agent(m, x, y)
    end
    @test random_empty_site(m) === nothing
end

@testset "test_random_empty_site_finds_the_last_empty_site" begin
    m = tiny_model(ones(Int, 10, 10))
    for x in 0:9, y in 0:9
        (x, y) == (7, 2) || put_agent(m, x, y)
    end
    @test all(random_empty_site(m) == (7, 2) for _ in 1:200)
end

@testset "test_spawn_on_full_lattice_raises" begin
    m = tiny_model(ones(Int, 3, 3))
    for x in 0:2, y in 0:2
        put_agent(m, x, y)
    end
    @test_throws ArgumentError spawn_random_agent!(m)
end

@testset "random_empty_site is uniform over the empty sites" begin
    m = tiny_model(ones(Int, 4, 4))
    for x in 0:3, y in 0:3
        (x, y) in ((0, 0), (3, 3)) || put_agent(m, x, y)
    end
    picks = [random_empty_site(m) for _ in 1:2000]
    @test Set(picks) == Set([(0, 0), (3, 3)])
    @test 850 < count(==((0, 0)), picks) < 1150
end

@testset "test_old_age_death_and_replacement_keep_population_constant" begin
    m = Model(Config(; initial_population=50, max_age=(1, 1), replacement=true, seed=3))
    step!(m)
    @test length(m.agents) == 50 && all(g.age == 0 for g in m.agents)
    @test deaths_this_step(m) == 50
    @test agents_ever(m) == 100
end

@testset "test_kill_frees_site" begin
    m = tiny_model(ones(Int, 3, 3))
    g = put_agent(m, 1, 1)
    h = put_agent(m, 0, 0)
    kill!(m, g)
    @test agent_at(m, 1, 1) === nothing && !g.alive && !(g in m.agents)
    @test m.agents == [h] && h.slot == 1
end

@testset "test_move_agent_updates_occupancy" begin
    m = tiny_model(ones(Int, 3, 3))
    g = put_agent(m, 0, 0)
    move_agent!(m, g, 2, 1)
    @test (g.x, g.y) == (2, 1) && agent_at(m, 2, 1) === g && agent_at(m, 0, 0) === nothing
    @test (g.disp_x, g.disp_y) == (-1, 1)  # the short way round the torus
    @test_throws ArgumentError move_agent!(m, put_agent(m, 1, 1), 2, 1)
end

@testset "test_run_calls_observer_before_and_after_each_step" begin
    seen = Int[]
    run!(tiny_model(ones(Int, 3, 3)), 3; observer=m -> push!(seen, m.t))
    @test seen == [0, 1, 2, 3]
end

@testset "test_step_regrows_sites_at_end_of_period" begin
    m = tiny_model(fill(4, 3, 3))
    m.landscape.sugar .= 0
    step!(m)
    @test maximum(m.landscape.sugar) == 1.0 && m.t == 1
end

@testset "test_model_uses_configured_winter_mode" begin
    for (mode, expected) in (("fractional", 0.25), ("pulse", 1.0))
        m = tiny_model(fill(4, 3, 4); seasons=(8, 50), winter_growback=mode)
        m.landscape.sugar .= 0
        step!(m)
        step!(m)  # t=0,1: north summer, south winter
        @test m.landscape.sugar[1, 1] == expected && m.landscape.sugar[1, 4] == 2.0
    end
end

@testset "test_founders_with_finite_lives_start_at_spread_ages" begin
    # Python's test also turns sex on; sex arrives with the Chapter III rules, and ages don't depend on it.
    m = Model(Config(; max_age=(60, 100), endowment=(50, 100), seed=3))
    ages = [a.age for a in m.agents]
    @test all(0 <= a.age < a.max_age for a in m.agents)
    @test minimum(ages) < 10 && maximum(ages) > 60 && 35 < sum(ages) / length(ages) < 45
end

@testset "test_founder_ages_zero_option_and_immortals_start_at_zero" begin
    @test all(
        a.age == 0 for a in Model(Config(; max_age=(60, 100), founder_ages="zero")).agents
    )
    @test all(a.age == 0 for a in Model(Config(; seed=1)).agents)
end

@testset "test_newcomers_start_at_age_zero" begin
    m = Model(Config(; max_age=(60, 100), replacement=true, seed=4))
    @test spawn_random_agent!(m).age == 0
end

@testset "starvation, pollution and diffusion in step!" begin
    m = Model(
        Config(; pollution=(1.0, 1.0), diffusion_period=1, diffusion_passes=3, seed=2)
    )
    total = sum(m.landscape.pollution)
    step!(m)
    @test sum(m.landscape.pollution) > total  # agents polluted, diffusion conserves
    n = length(m.agents)
    @test n == 400 - deaths_this_step(m)
    @test all(a.alive && agent_at(m, a.x, a.y) === a for a in m.agents)
    @test count(!isnothing, m.grid) == n
end

@testset "old-age deaths are processed in creation order" begin
    m = tiny_model(zeros(Int, 9, 9))
    agents = [put_agent(m, x, 0; max_age=1) for x in 0:6]
    kill!(m, agents[2])  # swap-removal reorders m.agents
    kill!(m, agents[4])
    empty!(m.dead_this_step)
    step!(m)
    @test [a.id for a in m.dead_this_step] == [0, 2, 4, 5, 6]
end
