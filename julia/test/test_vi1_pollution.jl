# VI-1-pollution and VI-1-pollution-t0 (docs/superpowers/specs/2026-11-11-vi1-pollution-design.md, "The experiments"):
# VI-1-assim-k4 with pollution and diffusion on, over 600 periods.

using Sugarscape, Test
using Sugarscape: JULIA_COMBAT_EXPS, world_config, vi1_assim_k4_experiment,
    vi1_pollution_experiment, vi1_pollution_t0_experiment

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
