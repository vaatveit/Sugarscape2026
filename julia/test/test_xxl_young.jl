# xxl (revised): young founders (docs/superpowers/specs/2026-10-29-xxl-revised-design.md, "Stage 1: survival", change 4).
# With founder_ages = "young" a founder's age is drawn U[0, fertility start] instead of U[0, max age), in the same loop
# and position as the book's draw. It needs sex (the fertility start) and finite lives.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

@testset "xxl young founders" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    young_rules = replace_rules(XXL_V1; founder_ages="young")

    @testset "VI-1: founders start no later than their fertile years" begin
        @test vi1.config.sex &&
            vi1.config.max_age !== nothing &&
            vi1.config.founder_ages == "uniform"
        m = Model(to_xxl(vi1.config, young_rules))
        @test m.config.xxl.founder_ages == "young"
        @test length(m.agents) == 20_000
        @test all(a -> 0 <= a.age <= a.fertility_start, m.agents)
        # a founder of any fertility start can be of any age up to it, so the ages span 0 to the largest start
        top = maximum(a.fertility_start for a in m.agents)
        @test top == last(vi1.config.fertility_start)
        @test minimum(a.age for a in m.agents) == 0
        @test maximum(a.age for a in m.agents) == top
        for fs in unique(a.fertility_start for a in m.agents)
            ages = [a.age for a in m.agents if a.fertility_start == fs]
            @test minimum(ages) == 0 && maximum(ages) == fs
        end
    end

    @testset "VI-1: the book path still spans the lifespan" begin
        m = Model(to_xxl(vi1.config, XXL_V1))
        @test maximum(a.age for a in m.agents) > last(vi1.config.fertility_start)
        @test all(a -> a.age < a.max_age, m.agents)
    end

    @testset "II-4: to_xxl resets young to book, the founders are untouched" begin
        ii4 = find_experiment(reg, "II-4")
        c = to_xxl(ii4.config, young_rules)
        @test c.xxl.founder_ages == "book" && !xxl_on(c, :young)
        @test all(a -> a.age == 0, Model(replace_config(c; initial_population=200)).agents)
    end

    @testset "a young config without sex or finite lives draws nothing extra" begin
        # replace_config skips to_xxl's reset, so the model guards for itself
        base = to_xxl(vi1.config, young_rules)
        no_sex = replace_config(base; sex=false, credit=nothing, initial_population=300)
        @test xxl_on(no_sex, :young)
        ages = [a.age for a in Model(no_sex).agents]  # the book draw, U[0, max age)
        @test maximum(ages) > last(vi1.config.fertility_start)
        immortal = replace_config(base; max_age=nothing, initial_population=300)
        @test all(a -> a.age == 0, Model(immortal).agents)
    end

    @testset "the book's founder_ages = zero is kept" begin
        zero = replace_config(
            to_xxl(vi1.config, young_rules); founder_ages="zero", initial_population=300
        )
        @test all(a -> a.age == 0, Model(zero).agents)
    end
end
