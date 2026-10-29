# xxl: seasons by latitude (spec, rule 5): the winter rate tapers to alpha at both equators.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test

# A 4 x 500 landscape at capacity 4 with every level at 0, grown one period at time `t` (alpha 1, beta 2, gamma 10).
function grown_once(t)
    ls = Landscape(fill(4, 4, 500), fill(4, 4, 500))
    fill!(ls.sugar, 0.0)
    fill!(ls.spice, 0.0)
    seasonal_growback_gradient!(ls, t, 1.0, 2, 10)
    return ls
end

@testset "xxl seasons by latitude" begin
    @testset "winter in the north" begin
        ls = grown_once(10)  # t mod 2 gamma = 10: the south is in summer
        @test ls.sugar[1, 376] ≈ 0.5            # y = 375, the middle of the north: alpha / beta
        @test ls.sugar[1, 251] ≈ 1.0 atol = 1e-12  # y = 250, the equator: alpha
        @test abs(ls.sugar[1, 250] - ls.sugar[1, 252]) < 0.01  # y = 249 and 251 (summer / winter)
        @test ls.sugar[1, 250] == 1.0           # y = 249, southern summer
        @test abs(ls.sugar[1, 1] - ls.sugar[1, 500]) < 0.01    # y = 0 and 499 across the seam
        @test ls.sugar[1, 126] == 1.0           # the south is in summer all the way up
        @test ls.spice == ls.sugar              # spice follows the same rule
    end

    @testset "winter in the south" begin
        ls = grown_once(0)  # the north is in summer
        @test ls.sugar[1, 126] ≈ 0.5            # y = 125, the middle of the south
        @test ls.sugar[1, 376] == 1.0
        @test abs(ls.sugar[1, 250] - ls.sugar[1, 252]) < 0.01
        @test abs(ls.sugar[1, 1] - ls.sugar[1, 500]) < 0.01
    end

    @testset "capacity caps the growth" begin
        ls = Landscape(fill(4, 4, 500))
        ls.sugar[1, 376] = 3.8
        seasonal_growback_gradient!(ls, 10, 1.0, 2, 10)
        @test ls.sugar[1, 376] == 4.0
    end

    @testset "step! picks the gradient only when it is on" begin
        kw = (; width=4, height=500, seasons=(2, 10))
        on = tiny_model(fill(4, 4, 500); kw..., xxl=XxlRules(; season_gradient=true))
        off = tiny_model(fill(4, 4, 500); kw...)
        for m in (on, off)
            fill!(m.landscape.sugar, 0.0)
            m.t = 10
            step!(m)
        end
        @test on.landscape.sugar[1, 376] ≈ 0.5   # beta^(-1) at the middle of the north
        @test on.landscape.sugar[1, 251] ≈ 1.0 atol = 1e-12
        @test off.landscape.sugar[1, 376] ≈ 0.5  # the book's alpha / beta
        @test off.landscape.sugar[1, 260] ≈ 0.5  # the book's winter is flat; the gradient's is not
        @test on.landscape.sugar[1, 260] > 0.5 + 0.1
    end

    @testset "allocates nothing" begin
        ls = grown_once(10)
        seasonal_growback_gradient!(ls, 11, 1.0, 2, 10)
        @test (@allocated seasonal_growback_gradient!(ls, 12, 1.0, 2, 10)) == 0
    end
end
