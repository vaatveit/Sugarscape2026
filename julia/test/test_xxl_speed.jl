# xxl: the speed trait (spec, "Speed"): every agent has one, founders, children and replacements alike.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test

# Steps `m` for `periods` periods; whether every living agent's speed lay in `bounds` (0 for none) at every period.
function speeds_within(m, bounds, periods)
    ok = all(a -> bounds[1] <= a.speed <= bounds[2], m.agents)
    for _ in 1:periods
        step!(m)
        ok &= all(a -> bounds[1] <= a.speed <= bounds[2], m.agents)
    end
    return ok
end

@testset "every agent has a speed" begin
    rules = XxlRules(; speed=(2, 4))
    rich = fill(4, 20, 20)
    @testset "children" begin
        kw = (
            sex=true,
            fertility_start=(1, 2),
            female_fertility_end=(40, 50),
            male_fertility_end=(50, 60),
            endowment=(50, 60),
            vision=(4, 6),
            initial_population=40,
        )
        m = tiny_model(rich; xxl=rules, kw...)
        @test speeds_within(m, (2, 4), 30)
        @test agents_ever(m) > 40   # children were born
        plain = tiny_model(rich; xxl=XXL_BOOK, kw...)
        @test speeds_within(plain, (0, 0), 30)
    end
    @testset "replacements" begin
        kw = (max_age=(5, 8), replacement=true, vision=(4, 6), initial_population=40)
        m = tiny_model(rich; xxl=rules, kw...)
        @test speeds_within(m, (2, 4), 30)
        @test agents_ever(m) > 40   # replacements were made
        plain = tiny_model(rich; xxl=XXL_BOOK, kw...)
        @test speeds_within(plain, (0, 0), 30)
    end
end
