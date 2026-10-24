# Ports tests/test_welfare.py.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function agent_with(m1, m2; sugar=0.0, spice=0.0, tags=[0])
    a = loose(tags...)
    a.metabolism, a.spice_metabolism, a.sugar, a.spice = m1, m2, sugar, spice
    return a
end

@testset "test_appendix_c_preferences_depend_on_wealth" begin  # App. C, p.189
    a = agent_with(1, 1)
    @test welfare(a, 20 + 3, 50 + 3) > welfare(a, 20 + 2, 50 + 5)  # 23*53 > 22*55
    @test welfare(a, 150 + 3, 250 + 3) < welfare(a, 150 + 2, 250 + 5)  # 153*253 < 152*255
end

@testset "test_welfare_weights_by_metabolism" begin  # p.97
    @test welfare(agent_with(3, 1), 16, 1) ≈ 16^0.75 * 1^0.25
end

@testset "test_negative_holdings_count_as_zero" begin
    @test welfare(agent_with(1, 1), -5, 10) == 0.0
end

@testset "test_mrs_matches_times_to_starvation" begin  # eq. 3, p.102
    @test mrs(agent_with(2, 1; sugar=10, spice=5)) ≈ (5 / 1) / (10 / 2)
end

@testset "test_cultural_welfare_extremes" begin  # eq. 5, p.124
    allzero = agent_with(1, 1; sugar=10, spice=10, tags=[0, 0, 0])  # f = 1: values sugar only
    @test welfare(allzero, 5, 100, true) ≈ 5.0
    @test mrs(allzero, true) == Inf  # would give any spice for sugar
    mixed = agent_with(1, 1; sugar=10, spice=10, tags=[0, 1, 1])  # f = 1/3
    @test mrs(mixed, true) ≈ (10 / (2 / 3)) / (10 / (1 / 3))
    @test mrs(mixed) ≈ 1.0  # non-cultural form ignores tags
end

@testset "mrs degenerate cases" begin
    @test mrs(agent_with(1, 1; sugar=0, spice=5)) == Inf
    @test isnan(mrs(agent_with(1, 1; sugar=0, spice=0)))
    @test mrs(agent_with(1, 0; sugar=5, spice=5)) == Inf  # no spice metabolism: numerator inf
    @test mrs(agent_with(0, 1; sugar=5, spice=5)) == 0.0
    @test isnan(mrs(agent_with(0, 0; sugar=5, spice=5)))
end

@testset "test_moves_toward_scarce_commodity" begin
    cap, spice = zeros(Int, 9, 9), zeros(Int, 9, 9)
    cap[5, 7] = 4
    spice[7, 5] = 2  # 4 sugar north vs 2 spice east
    m = tiny_model(cap; spice=true, vision=(1, 3))
    set_spice!(m.landscape, spice)
    g = put_agent(m, 4, 4; vision=3)
    g.sugar, g.spice, g.metabolism, g.spice_metabolism = 50.0, 2.0, 1, 1
    move!(m, g)
    @test (g.x, g.y) == (6, 4) && g.spice == 4.0 && m.landscape.spice[7, 5] == 0.0
end

@testset "test_dies_of_spice_starvation" begin  # p.97
    m = tiny_model(ones(Int, 5, 5); spice=true)
    g = put_agent(m, 2, 2; sugar=100.0)
    g.spice, g.spice_metabolism = 1.0, 2
    metabolize!(m, g)
    @test !g.alive
end

@testset "test_foresight_shifts_choice" begin  # eq. 6, p.129
    for (phi, expected) in ((0, (3, 4)), (5, (4, 3)))
        cap, spice = zeros(Int, 9, 9), zeros(Int, 9, 9)
        cap[4, 5] = 4
        spice[5, 4] = 1
        m = tiny_model(cap; spice=true, foresight=(0, 10))
        set_spice!(m.landscape, spice)
        g = put_agent(m, 3, 3)
        g.sugar, g.spice, g.metabolism, g.spice_metabolism, g.foresight = 20.0,
        20.0, 1, 3,
        phi
        move!(m, g)
        @test (g.x, g.y) == expected
    end
end

@testset "test_pollution_stops" begin
    m = tiny_model(
        ones(Int, 5, 5); pollution=(1.0, 1.0), pollution_start=0, pollution_stop=5
    )
    m.t = 5
    g = put_agent(m, 2, 2)
    move!(m, g)
    metabolize!(m, g)
    @test sum(m.landscape.pollution) == 0.0
end

@testset "test_spawned_agents_get_spice_and_foresight" begin
    m = Model(
        Config(; spice=true, foresight=(0, 10), initial_population=50, endowment=(25, 50))
    )
    @test all(
        25 <= a.spice == a.initial_spice <= 50 && 1 <= a.spice_metabolism <= 5 for
        a in m.agents
    )
    @test all(0 <= a.foresight <= 10 for a in m.agents)
    @test m.landscape.spice_capacity == reverse(m.landscape.capacity; dims=1)
end

@testset "test_pollution_devalues_the_site_not_the_agent" begin  # p.47
    cap = zeros(Int, 7, 7)
    cap[4, 5] = 4
    m = tiny_model(cap; spice=true, pollution=(1.0, 1.0))
    set_spice!(m.landscape, zeros(Int, 7, 7))
    m.landscape.pollution[4, 5] = 1.0
    g = put_agent(m, 3, 3)
    g.sugar, g.spice, g.metabolism, g.spice_metabolism = 50.0, 50.0, 1, 1
    move!(m, g)
    @test (g.x, g.y) == (3, 4)
end
