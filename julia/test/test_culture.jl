# Ports tests/test_culture.py. Tags are bit fields; `tags_of` reads them back as 0/1 vectors.
using Sugarscape, Test
using Random: Xoshiro
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

@testset "test_tribe_majority" begin
    @test tribe(loose(0, 0, 1)) == :blue && tribe(loose(1, 1, 0)) == :red
end

@testset "test_random_tags_respects_tribe" begin
    rng = Xoshiro(0)
    count_tribe(t, n) = 2 * count_ones(t) < n ? :blue : :red
    @test all(count_tribe(random_tags(rng, 11, :red), 11) == :red for _ in 1:50)
    @test all(count_tribe(random_tags(rng, 11, :blue), 11) == :blue for _ in 1:50)
    @test random_tags(rng, 11, :none) >> 11 == 0  # only the low 11 bits
    @test length(Set(random_tags(rng, 11, :none) for _ in 1:200)) > 150  # uniform over 2048 strings
end

@testset "test_cross_tags_copies_agreement" begin  # p.78 Table III-2
    a, b = bits([0, 1, 0, 1]), bits([0, 1, 1, 0])
    child = cross_tags(Xoshiro(0), a, b, 4)
    @test child & 0b0011 == 0b0010  # positions 1-2 agree: copied
    seen = Set((cross_tags(Xoshiro(s), a, b, 4) >> 2) for s in 0:39)
    @test length(seen) == 4  # coin flips at disagreeing positions
end

@testset "test_hamming_and_closeness" begin
    @test hamming(bits([0, 1, 1]), bits([1, 1, 0])) == 2
    @test closeness(bits([0, 1, 1]), bits([1, 1, 0]), 3) ≈ 1 / 3
end

@testset "test_transmit_flips_neighbor_toward_agent" begin  # p.73
    m = tiny_model(ones(Int, 5, 5); tag_length=1)
    a = tag!(put_agent(m, 2, 2), [0])
    b = tag!(put_agent(m, 2, 3), [1])
    culture_transmit!(m, a)
    @test tags_of(b) == [0] && tags_of(a) == [0]  # flippee changes, flipper doesn't
end

@testset "test_transmit_one_position_per_neighbor" begin
    m = tiny_model(ones(Int, 5, 5); tag_length=11)
    a = tag!(put_agent(m, 2, 2), zeros(Int, 11))
    b = tag!(put_agent(m, 2, 3), ones(Int, 11))
    culture_transmit!(m, a)
    @test sum(tags_of(b)) == 10
end

@testset "test_friends_keep_five_closest_and_drop_dead" begin  # p.79-80
    me = loose(zeros(Int, 11)...)
    others = [loose(vcat(ones(Int, k), zeros(Int, 11 - k))...) for k in (5, 4, 3, 2, 1, 0)]
    update_friends!(me, others)
    @test sort([d for (_, d) in me.friends]) == [0, 1, 2, 3, 4]
    others[6].alive = false
    update_friends!(me, Agent[])
    @test sort([d for (_, d) in me.friends]) == [1, 2, 3, 4]
end

@testset "test_friends_not_duplicated_or_self" begin
    me = loose(0, 0, 0)
    f = loose(0, 0, 1)
    update_friends!(me, [f, f, me])
    @test [x for (x, _) in me.friends] == [f]
end

@testset "a newcomer displaces the farthest friend only when strictly closer" begin
    me = loose(0, 0, 0)
    far = [loose(1, 1, 0) for _ in 1:5]
    update_friends!(me, far)
    update_friends!(me, [loose(1, 0, 1)])  # also distance 2: not strictly closer
    @test all(f in far for (f, _) in me.friends)
    newcomer = loose(1, 0, 0)
    update_friends!(me, [newcomer])
    @test any(f === newcomer for (f, _) in me.friends) && length(me.friends) == 5
end
