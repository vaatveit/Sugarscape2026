# Pollution decay (docs/superpowers/specs/2026-11-11-pollution-decay-design.md): `pollution_decay` removes a fixed share
# of every site's pollution at the end of each period, after diffusion; 0 (the default) does nothing at all.

isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: validate, diffuse!

# A 5 x 5 world with no agents and distinct positive pollution everywhere.
function decay_model(; kw...)
    m = tiny_model(ones(Int, 5, 5); kw...)
    m.landscape.pollution .= reshape(1.0:25.0, 5, 5) ./ 7
    return m
end

@testset "pollution_decay: the rule" begin
    @testset "default and validation" begin
        @test Config().pollution_decay == 0.0
        for bad in (-0.01, 1.0, 1.5, NaN)
            @test_throws ArgumentError validate(Config(; pollution_decay=bad))
        end
        for ok in (0.0, 0.045, 0.999)
            @test validate(Config(; pollution_decay=ok)).pollution_decay == ok  # validate returns the config
        end
    end

    @testset "needs no pollution" begin
        m = tiny_model(ones(Int, 5, 5); pollution_decay=0.1)
        @test m.config.pollution === nothing
        step!(m)
        @test all(==(0.0), m.landscape.pollution)
    end

    @testset "one step multiplies every site by 1 - delta" begin
        m = decay_model(; pollution_decay=0.1)
        old = copy(m.landscape.pollution)
        step!(m)
        @test m.landscape.pollution == old .* (1 - 0.1)
    end

    @testset "decay comes after diffusion" begin
        m = decay_model(; pollution_decay=0.1, diffusion_period=1, diffusion_start=0, diffusion_passes=1)
        ref = decay_model()
        diffuse!(ref.landscape)
        step!(m)
        @test m.landscape.pollution == ref.landscape.pollution .* (1 - 0.1)
    end

    @testset "decay acts in periods without diffusion" begin
        m = decay_model(; pollution_decay=0.1, diffusion_period=2, diffusion_start=0, diffusion_passes=1)
        step!(m)  # t = 0: diffusion and decay
        @test m.t == 1
        old = copy(m.landscape.pollution)
        step!(m)  # t = 1: decay only
        @test m.landscape.pollution == old .* (1 - 0.1)
    end

    @testset "the total falls by 1 - delta with 100 passes" begin
        m = decay_model(; pollution_decay=0.1, diffusion_period=1, diffusion_start=0, diffusion_passes=100)
        before = sum(m.landscape.pollution)
        step!(m)
        @test isapprox(sum(m.landscape.pollution), before * 0.9; rtol=1e-12)
    end

    @testset "0 leaves the field as it was" begin
        m = decay_model(; pollution_decay=0.0)
        old = copy(m.landscape.pollution)
        step!(m)
        @test m.landscape.pollution == old
    end
end
