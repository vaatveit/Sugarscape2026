# Ports tests/test_movement.py.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

"""Sugar row at y=1 starting at x=0; zero padding so west/south scans never wrap onto it."""
function line_model(levels, vision; kw...)
    n = length(levels) + 2 * vision + 2
    cap = zeros(Int, n, n)
    cap[1:length(levels), 2] .= levels
    return tiny_model(cap; vision=(1, vision), kw...)
end

@testset "test_moves_to_max_sugar_within_vision" begin
    m = line_model([0, 1, 3, 2], 3)
    g = put_agent(m, 0, 1; vision=3)
    move!(m, g)
    @test (g.x, g.y) == (2, 1) && g.sugar == 13.0 && g.moved
    @test m.landscape.sugar[3, 2] == 0.0
end

@testset "test_cannot_see_beyond_vision" begin
    m = line_model([0, 1, 0, 0, 4], 2)
    g = put_agent(m, 0, 1; vision=2)
    move!(m, g)
    @test g.x == 1
end

@testset "test_no_diagonal_vision" begin
    cap = zeros(Int, 8, 8)
    cap[2, 2] = 4
    cap[1, 4] = 1
    m = tiny_model(cap; vision=(1, 3))
    g = put_agent(m, 0, 0; vision=3)
    move!(m, g)
    @test (g.x, g.y) == (0, 3)
end

@testset "test_skips_occupied_sites" begin
    m = line_model([0, 4, 2], 2)
    put_agent(m, 1, 1)
    g = put_agent(m, 0, 1; vision=2)
    move!(m, g)
    @test g.x == 2
end

@testset "test_nearest_wins_ties" begin
    m = line_model([0, 0, 3, 0, 3], 4)
    g = put_agent(m, 0, 1; vision=4)
    move!(m, g)
    @test g.x == 2
end

@testset "test_equal_distance_ties_are_random_direction" begin
    counts = Dict(2 => 0, 4 => 0)
    for seed in 0:199
        cap = zeros(Int, 7, 7)
        cap[5, 4] = cap[3, 4] = 2
        m = tiny_model(cap; vision=(1, 1), seed=seed)
        g = put_agent(m, 3, 3)
        move!(m, g)
        counts[g.x] += 1
    end
    @test counts[2] >= 60 && counts[4] >= 60
end

@testset "test_stays_when_current_site_is_best" begin
    m = line_model([4, 3], 1)
    g = put_agent(m, 0, 1)
    move!(m, g)
    @test g.x == 0 && !g.moved && g.sugar == 14.0
end

@testset "test_vision_wraps_around_torus" begin
    cap = zeros(Int, 6, 6)
    cap[6, 2] = 3  # one step west of x=0
    m = tiny_model(cap; vision=(1, 2))
    g = put_agent(m, 0, 1; vision=2)
    move!(m, g)
    @test g.x == 5
end

@testset "test_starves_at_zero" begin
    m = line_model([0, 0], 1)
    g = put_agent(m, 0, 1; metabolism=2, sugar=2.0)
    move!(m, g)
    metabolize!(m, g)
    @test !g.alive && agent_at(m, 0, 1) === nothing
end

@testset "test_survives_with_positive_wealth" begin
    m = line_model([0, 0], 1)
    g = put_agent(m, 0, 1; metabolism=2, sugar=2.5)
    metabolize!(m, g)
    @test g.alive && g.sugar == 0.5
end

@testset "test_pollution_formation_and_avoidance" begin
    m = line_model([2, 3, 0], 1; pollution=(1.0, 1.0))
    m.landscape.pollution[2, 2] = 2.0  # score 3/3 = 1 < 2/1 at the current site
    g = put_agent(m, 0, 1; metabolism=1)
    move!(m, g)
    metabolize!(m, g)
    @test g.x == 0 && m.landscape.pollution[1, 2] == 2.0 + 1.0  # alpha*2 + beta*1
end

@testset "test_no_pollution_before_start" begin
    m = line_model([2, 3, 0], 1; pollution=(1.0, 1.0), pollution_start=50)
    g = put_agent(m, 0, 1)
    move!(m, g)
    metabolize!(m, g)
    @test sum(m.landscape.pollution) == 0.0
end

@testset "last_income is harvest minus burn" begin
    m = line_model([0, 5], 1)
    g = put_agent(m, 0, 1; metabolism=2)
    move!(m, g)
    metabolize!(m, g)
    @test g.last_income == 3.0
end
