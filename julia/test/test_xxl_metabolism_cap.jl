# xxl (revised): max_metabolism caps the metabolism drawn for new agents
# (docs/superpowers/specs/2026-10-29-xxl-revised-design.md, "The changes"). Founders and rule-R replacements draw
# through `spawn_at!`; children inherit by crossover in rule S, so a capped parent generation gives capped children.
using Sugarscape, Test
using Sugarscape: capped_range

# `exp`'s xxl model under `rules`, cut to `n` founders so the periods run quickly.
function cap_model(exp, rules, n)
    cfg = to_xxl(exp.config, rules)
    return Model(replace_config(cfg; initial_population=n))
end

# Steps `m` for `periods` periods; every agent seen alive at the end of a period, by id.
function cap_census(m, periods)
    seen = Dict{Int,Agent}(a.id => a for a in m.agents)
    for _ in 1:periods
        step!(m)
        for a in m.agents
            seen[a.id] = a
        end
    end
    return seen
end

@testset "xxl max_metabolism" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    a80 = find_experiment(reg, "IV-12/a80")
    capped = replace_rules(XXL_V1; max_metabolism=4)

    @testset "capped_range" begin
        x = to_xl(vi1.config)
        flat = replace_rules(XXL_V1; season_gradient=false)  # VI-1 has no seasons to taper
        off = replace_config(x; xxl=flat)
        on = replace_config(x; xxl=replace_rules(flat; max_metabolism=4))
        @test capped_range(off, (1, 5)) == (1, 5)
        @test capped_range(x, (1, 5)) == (1, 5)  # no xxl rules at all
        @test capped_range(on, (1, 5)) == (1, 4)
        @test capped_range(on, (1, 3)) == (1, 3)  # a range already under the cap is left alone
        @test capped_range(on, (2, 4)) == (2, 4)
    end

    @testset "VI-1 founders draw metabolisms of at most 4" begin
        m = cap_model(vi1, capped, 1000)
        @test length(m.agents) == 1000
        @test all(a -> 1 <= a.metabolism <= 4, m.agents)
        @test all(a -> 1 <= a.spice_metabolism <= 4, m.agents)
        @test Set(a.metabolism for a in m.agents) == Set(1:4)
        @test Set(a.spice_metabolism for a in m.agents) == Set(1:4)
    end

    @testset "without the cap VI-1 founders still draw up to 5" begin
        m = cap_model(vi1, XXL_V1, 1000)
        @test maximum(a.metabolism for a in m.agents) == 5
        @test maximum(a.spice_metabolism for a in m.agents) == 5
    end

    @testset "VI-1 children inherit capped metabolisms" begin
        m = cap_model(vi1, capped, 1000)
        n0 = length(m.agents)
        seen = cap_census(m, 20)
        children = [a for a in values(seen) if a.id > n0]
        @test !isempty(children)  # rule S produced some
        @test all(a -> 1 <= a.metabolism <= 4, values(seen))
        @test all(a -> 1 <= a.spice_metabolism <= 4, values(seen))
    end

    @testset "IV-12/a80 replacements draw capped metabolisms" begin
        @test a80.config.metabolism == (1, 5) && a80.config.spice_metabolism == (1, 5)
        @test a80.config.spice && a80.config.replacement
        m = cap_model(a80, capped, 1000)
        n0 = length(m.agents)
        seen = cap_census(m, 20)
        replacements = [a for a in values(seen) if a.id > n0]
        @test !isempty(replacements)  # rule R replaced some who died
        @test all(a -> 1 <= a.metabolism <= 4, replacements)
        @test all(a -> 1 <= a.spice_metabolism <= 4, replacements)
        @test all(a -> 1 <= a.metabolism <= 4, values(seen))
    end
end
