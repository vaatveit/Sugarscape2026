# Rule C by cultural distance with a curve: p = h (d / L)^k, `combat_curve` k (1 is the linear rule of VI-1-distance).
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

curve_agent(tags) = (a = Agent(0, 0, 0, 1, 1, 0.0, Inf); a.tags = foldl((t, b) -> 2t + b, reverse(tags); init=UInt64(0)); a.ntags = length(tags); a)

@testset "test_fight_chance_curve" begin
    a, b = curve_agent([0, 0, 0, 0, 0]), curve_agent([0, 0, 1, 1, 1])  # d = 3, L = 5
    @test fight_chance(0.5, a, b, 2.0) ≈ 0.5 * 0.6^2
    @test fight_chance(0.5, a, b, 3.0) ≈ 0.5 * 0.6^3
    @test fight_chance(0.5, a, curve_agent([1, 1, 1, 1, 1]), 4.0) == 0.5  # d = L: h whatever k
    @test fight_chance(0.5, a, a, 2.0) == 0.0
    # k = 1 is the linear rule exactly, bit for bit, so VI-1-distance's draws don't change.
    @test fight_chance(0.5, a, b, 1.0) === 0.5 * 3 / 5
    @test fight_chance(0.5, a, b) === fight_chance(0.5, a, b, 1.0)
end

# The attacker at (1, 1), a poorer occupant at (3, 1) with d = 2 of L = 5; true if it was attacked.
function curve_attacked(k, seed)
    m = tiny_model(
        zeros(Int, 12, 12); tag_length=5, combat_alpha=Inf, vision=(1, 4), combat_hostility=1.0,
        combat_curve=k, seed=seed,
    )
    a = tag!(put_agent(m, 1, 1; vision=4, sugar=20.0), [0, 0, 0, 0, 0])
    r = tag!(put_agent(m, 3, 1; vision=4, sugar=5.0), [0, 0, 0, 1, 1])
    combat_move!(m, a)
    return !r.alive
end

@testset "test_move_uses_curve" begin
    linear = count(s -> curve_attacked(1.0, s), 1:400) / 400   # p = 0.4
    steep = count(s -> curve_attacked(3.0, s), 1:400) / 400    # p = 0.4^3 = 0.064
    @test abs(linear - 0.4) <= 0.07
    @test abs(steep - 0.064) <= 0.04
end

@testset "test_curve_config" begin
    combat = (; tag_length=11, combat_alpha=2.0, combat_hostility=0.5)
    @test Config().combat_curve == 1.0
    @test_throws ArgumentError validate(Config(; combat..., combat_curve=0.0))
    @test_throws ArgumentError validate(Config(; combat..., combat_curve=-1.0))
    @test_throws ArgumentError validate(Config(; combat..., combat_curve=Inf))
    @test_throws ArgumentError validate(Config(; combat..., combat_curve=NaN))
    @test_throws ArgumentError validate(Config(; tag_length=11, combat_alpha=2.0, combat_curve=2.0))  # needs h > 0
    @test validate(Config(; combat..., combat_curve=3.0)).combat_curve == 3.0
end
