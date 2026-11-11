# VI-1-pollution and VI-1-pollution-t0 (docs/superpowers/specs/2026-11-11-vi1-pollution-design.md, "The experiments"):
# VI-1-assim-k4 with pollution and diffusion on, over 600 periods.

isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: JULIA_COMBAT_EXPS, world_config, vi1_assim_k4_experiment,
    vi1_pollution_experiment, vi1_pollution_t0_experiment, diffuse!

const VP_FIELDS = (:pollution, :pollution_start, :pollution_stop, :diffusion_period, :diffusion_start, :diffusion_passes)

@testset "VI-1 pollution experiments" begin
    for (build, id, start, dstart) in ((vi1_pollution_experiment, "VI-1-pollution", 350, 450),
                                       (vi1_pollution_t0_experiment, "VI-1-pollution-t0", 0, 0))
        e, k4 = build(), vi1_assim_k4_experiment()
        @test e.id == id && JULIA_COMBAT_EXPS[id]().id == id
        @test e.steps == 600 && e.seeds == k4.seeds
        for (world, passes) in (("book", 1), ("xl", 100), ("today", 100))
            c, b = world_config(e, world), world_config(k4, world)
            @test c.pollution == (1.0, 1.0)
            @test c.pollution_start == start && c.pollution_stop === nothing
            @test c.diffusion_period == 1 && c.diffusion_start == dstart && c.diffusion_passes == passes
            # everything else is VI-1-assim-k4's
            @test all(repr(getfield(c, f)) == repr(getfield(b, f)) for f in fieldnames(typeof(c)) if !(f in VP_FIELDS))
        end
        @test endswith(e.fingerprint, "\n") && occursin("variant: $id ", e.fingerprint)
        @test startswith(e.fingerprint, k4.fingerprint) && startswith(e.xl_fingerprint, k4.xl_fingerprint)
    end
end

# Pollution in today's world (about 20,000 agents, 500 x 500): the deposit arithmetic is tested elsewhere; these check
# the combination.
@testset "VI-1 pollution in today's world" begin
    @testset "identical to VI-1-assim-k4 before the start" begin
        a = Model(world_config(vi1_pollution_experiment(), "today"))
        b = Model(world_config(vi1_assim_k4_experiment(), "today"))
        for _ in 1:3
            step!(a)
            step!(b)
        end
        fields(m) = [(g.id, g.x, g.y, g.sugar, g.spice, g.tags) for g in sort!(collect(m.agents); by=g -> g.id)]
        @test fields(a) == fields(b)
        @test a.landscape.sugar == b.landscape.sugar
        @test sum(a.landscape.pollution) == 0
    end

    onset_config() = replace_config(
        world_config(vi1_pollution_experiment(), "today"); pollution_start=2, diffusion_start=10^6
    )

    @testset "onset" begin
        m = Model(onset_config())
        for _ in 1:2
            step!(m)
            @test sum(m.landscape.pollution) == 0
        end
        step!(m)
        @test m.t == 3
        @test sum(m.landscape.pollution) > 0
        @test all(>=(0), m.landscape.pollution)
    end

    @testset "diffusion starts at its period" begin
        m = tiny_model(
            zeros(Int, 5, 5);
            pollution=(1.0, 1.0), diffusion_period=1, diffusion_start=2, diffusion_passes=1,
        )
        m.landscape.pollution[3, 3] = 4.0
        before = copy(m.landscape.pollution)
        for _ in 1:2
            step!(m)
            @test m.landscape.pollution == before
        end
        step!(m)
        p = m.landscape.pollution
        @test p[3, 3] == 0.0
        @test all(==(1.0), (p[2, 3], p[4, 3], p[3, 2], p[3, 4]))
    end

    @testset "100 passes conserve the total" begin
        m = Model(onset_config())
        for _ in 1:3
            step!(m)
        end
        ls = m.landscape
        before = copy(ls.pollution)
        for _ in 1:100
            diffuse!(ls)
        end
        @test isapprox(sum(ls.pollution), sum(before); rtol=1e-12)
        @test all(>=(0), ls.pollution)
    end
end
