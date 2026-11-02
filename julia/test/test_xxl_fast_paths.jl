# The hot paths' shortcuts each give what the long way gives: test_xxl_same_run.jl pins whole runs, these the reasoning.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Random: Xoshiro, shuffle!

# A world of two commodities on a random map, with one agent in the middle of it.
function fast_world(seed; M=6, S=4, V=8, c=0.1, kw...)
    cap = rand(Xoshiro(seed), 0:4, 40, 40)
    rules = XxlRules(; vision_shape="disc", speed=(S, S), travel_cost=c, memory=M, memory_span=50)
    m = tiny_model(cap; xxl=rules, vision=(V, V), spice=true, kw...)
    a = put_agent(m, 20, 20; vision=V, sugar=30.0)
    a.spice, a.spice_metabolism, a.speed = 25.0, 2, S
    return m, a
end

@testset "wrap_one is mod, without the division" begin
    @test all(Sugarscape.wrap_one(x, n) == mod(x, n) for n in (1, 2, 7, 50, 500) for x in (-3n):(3n))
    @test Sugarscape.wrap_one(typemin(Int) + 1, 7) == mod(typemin(Int) + 1, 7)
end

@testset "torus_delta: the signed shortest offset" begin
    long_way(w, x1, x2) = (d = mod(x2 - x1, w); 2d > w ? d - w : d)
    @test all(
        Sugarscape.torus_delta(w, x1, x2) == long_way(w, x1, x2) for w in (1, 2, 7, 50) for x1 in (-2w):(2w) for
        x2 in (-2w):(2w)
    )
end
