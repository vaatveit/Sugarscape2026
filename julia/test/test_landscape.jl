# Ports tests/test_landscape.py. Matrix literals are indexed [x, y] as Python's arrays are.
using Sugarscape, Test

@testset "test_starts_full_with_no_pollution" begin
    ls = Landscape([4 2; 0 1])
    @test ls.sugar == [4.0 2.0; 0.0 1.0]
    @test sum(ls.pollution) == 0.0
    @test (ls.width, ls.height) == (2, 2)
end

@testset "test_wrap_is_toroidal" begin
    ls = Landscape(zeros(Int, 5, 4))
    @test wrap(ls, -1, 4) == (4, 0)
    @test wrap(ls, 5, -1) == (0, 3)
end

@testset "test_growback_caps_at_capacity" begin
    ls = Landscape([4 2])
    ls.sugar .= [0.0 1.5]
    growback!(ls, 1.0)
    @test ls.sugar == [1.0 2.0]
end

@testset "test_g_infinity_refills_immediately" begin
    ls = Landscape([4 3])
    ls.sugar .= 0
    growback!(ls, Inf)
    @test ls.sugar == [4.0 3.0]
end

@testset "test_seasons_flip_every_gamma" begin
    @test is_summer_north(0, 50) && is_summer_north(49, 50)
    @test !is_summer_north(50, 50) && is_summer_north(100, 50)
end

@testset "test_winter_grows_alpha_every_beta_periods" begin
    ls = Landscape(fill(4, 1, 2))  # y=0 south, y=1 north
    ls.sugar .= 0
    for t in 0:7  # north summer
        seasonal_growback!(ls, t, 1.0, 8, 50, "pulse")
    end
    @test ls.sugar[1, 2] == 4.0  # north: +1 per period, capped
    @test ls.sugar[1, 1] == 1.0  # south: +1 only at t=0
end

@testset "test_diffusion_averages_von_neumann_neighbors_on_torus" begin
    ls = Landscape(zeros(Int, 3, 3))
    ls.pollution[2, 2] = 4.0
    diffuse!(ls)
    @test ls.pollution[2, 2] == 0.0
    @test ls.pollution[1, 2] == ls.pollution[2, 1] == 1.0
    @test sum(ls.pollution) ≈ 4.0
end

@testset "test_winter_fractional_grows_alpha_over_beta_each_period" begin
    ls = Landscape(fill(4, 1, 2))
    ls.sugar .= 0
    seasonal_growback!(ls, 0, 1.0, 8, 50, "fractional")
    @test ls.sugar[1, 1] == 0.125 && ls.sugar[1, 2] == 1.0
end

@testset "spice capacity is held separately" begin
    ls = Landscape([4 2; 0 1], [1 2; 3 4])
    @test ls.spice == [1.0 2.0; 3.0 4.0]
    @test Landscape([4 2]).spice == [0.0 0.0]
end
