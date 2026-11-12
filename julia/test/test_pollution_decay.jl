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

    @testset "after pollution_stop, with agents, the total falls by 1 - delta a period" begin
        m = tiny_model(ones(Int, 5, 5); pollution=(1.0, 1.0), pollution_start=0, pollution_stop=2, pollution_decay=0.1)
        put_agent(m, 2, 2; sugar=50.0)
        step!(m)
        step!(m)  # t = 0 and 1 make pollution
        @test m.t == 2 && sum(m.landscape.pollution) > 0 && length(m.agents) == 1
        for _ in 1:2  # t = 2 and 3: none is made, the agent still moves, harvests and burns
            before = sum(m.landscape.pollution)
            step!(m)
            @test isapprox(sum(m.landscape.pollution), before * 0.9; rtol=1e-12)
        end
        @test length(m.agents) == 1
    end

    @testset "0 leaves the field as it was" begin
        m = decay_model(; pollution_decay=0.0)
        old = copy(m.landscape.pollution)
        step!(m)
        @test m.landscape.pollution == old
    end
end

@testset "VI-1-pollution-decay: the experiment" begin
    e, p = Sugarscape.vi1_pollution_decay_experiment(), Sugarscape.vi1_pollution_experiment()
    k4 = Sugarscape.vi1_assim_k4_experiment()
    @test e.id == "VI-1-pollution-decay" && Sugarscape.JULIA_COMBAT_EXPS[e.id]().id == e.id
    @test e.steps == 1000 && e.seeds == p.seeds
    for world in ("book", "xl", "today")
        c, b = Sugarscape.world_config(e, world), Sugarscape.world_config(p, world)
        @test c.pollution_decay == 0.045
        # everything else is VI-1-pollution's
        @test all(repr(getfield(c, f)) == repr(getfield(b, f)) for f in fieldnames(typeof(c)) if f != :pollution_decay)
    end
    @test startswith(e.fingerprint, k4.fingerprint) && startswith(e.xl_fingerprint, k4.xl_fingerprint)
    @test occursin("variant: VI-1-pollution-decay ", e.fingerprint) && endswith(e.fingerprint, "\n")
    @test occursin("variant: VI-1-pollution-decay ", e.xl_fingerprint)

    @testset "identical to VI-1-pollution before pollution starts (today)" begin
        a = Model(Sugarscape.world_config(e, "today"))
        b = Model(Sugarscape.world_config(p, "today"))
        for _ in 1:3
            step!(a)
            step!(b)
        end
        fields(m) = [(g.id, g.x, g.y, g.sugar, g.spice, g.tags) for g in sort!(collect(m.agents); by=g -> g.id)]
        @test fields(a) == fields(b)
        @test a.landscape.pollution == b.landscape.pollution
    end
end
