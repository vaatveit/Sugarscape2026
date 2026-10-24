# The hot paths stay type-stable and diffusion stays allocation-free (julia-pro: check type stability).
using Sugarscape, Test

@testset "hot paths infer and diffusion allocates nothing" begin
    for id in ("II-4", "IV-A3", "VI-1", "III-9")
        m = Model(find_experiment(load_registry(), id).config)
        for _ in 1:2
            step!(m)
        end
        @test (@inferred step!(m)) === m
        a = m.agents[1]
        @test (@inferred collect_metrics(m)) isa Vector{Float64}
        if m.config.combat_alpha === nothing
            @test (@inferred move!(m, a)) === nothing
        end
    end
    ls = Model(Config(; pollution=(1.0, 1.0), diffusion_period=1)).landscape
    diffuse!(ls)
    @test (@allocated diffuse!(ls)) == 0
    @test (@allocated growback!(ls, 1.0)) == 0
end
