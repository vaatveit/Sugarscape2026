# Rule K by cultural distance (docs/superpowers/specs/2026-11-09-assimilation-distance-design.md, "The rule: K by
# distance"): with culture_rule "distance" or "distance-random", b copies one of a's tags with probability
# 1 - h (d / L)^k (h = combat_hostility, k = combat_curve); "distance" copies a tag where they differ, "distance-random"
# a random position as today. d = 0 draws nothing. An agent a with tags 00000 next to b, one culture_transmit!.
using Sugarscape, Test
using Random: Xoshiro, shuffle!
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

const CD_A = [0, 0, 0, 0, 0]

function cd_world(rule; h=0.5, k=1.0, seed=1)
    return tiny_model(
        zeros(Int, 5, 5); tag_length=5, culture=true, combat_alpha=Inf, combat_hostility=h, combat_curve=k,
        culture_rule=rule, seed=seed,
    )
end

# a (00000) at (2, 2) and b at (3, 2), b a's only neighbour.
function cd_pair(rule, btags; seed=1, kw...)
    m = cd_world(rule; seed=seed, kw...)
    a = tag!(put_agent(m, 2, 2), CD_A)
    b = tag!(put_agent(m, 3, 2), btags)
    return m, a, b
end

# Whether one contact from a changed b's tags.
function cd_changed(rule, btags, seed; kw...)
    m, a, b = cd_pair(rule, btags; seed=seed, kw...)
    culture_transmit!(m, a)
    return tags_of(b) != btags
end

@testset "test_copy_chance" begin
    a = loose(CD_A...)
    @test copy_chance(0.5, a, loose(0, 0, 1, 1, 1), 1.0) ≈ 0.7          # d = 3 of 5
    @test copy_chance(0.5, a, loose(1, 1, 1, 1, 1), 1.0) ≈ 0.5          # d = L: 1 - h
    @test copy_chance(0.5, a, loose(0, 0, 1, 1, 1), 2.0) ≈ 1 - 0.5 * 0.36
    @test copy_chance(0.5, a, loose(0, 0, 0, 0, 1), 1.0) ≈ 0.9          # d = 1
    @test copy_chance(0.5, a, a, 1.0) == 1.0                            # d = 0
    @test copy_chance(0.9, loose(zeros(Int, 11)...), loose(ones(Int, 11)...), 2.0) ≈ 0.1  # d = L = 11
end

@testset "test_distance_changes_one_differing_tag" begin
    btags = [0, 1, 1, 1, 0]
    old = bits(btags)
    differing = old ⊻ bits(CD_A)
    changed, flipped = 0, UInt64(0)
    for s in 1:200
        m, a, b = cd_pair("distance", btags; seed=s)
        culture_transmit!(m, a)
        flip = b.tags ⊻ old
        flip == 0 && continue
        changed += 1
        flipped |= flip
        @test count_ones(flip) == 1                  # exactly one tag
        @test flip & differing == flip               # one where they differed
        @test b.tags & flip == a.tags & flip         # now a's
    end
    @test changed > 0
    @test flipped == differing                       # every differing position gets chosen
end

@testset "test_distance_rate" begin
    share = count(s -> cd_changed("distance", [0, 0, 1, 1, 1], s), 1:600) / 600  # 1 - 0.5 * 3/5 = 0.7
    @test abs(share - 0.7) <= 0.06
end

@testset "test_distance_random_rate" begin
    share = count(s -> cd_changed("distance-random", [0, 0, 1, 1, 1], s), 1:600) / 600  # (3/5) * 0.7 = 0.42
    @test abs(share - 0.42) <= 0.06
end

@testset "test_identical_no_draw" begin
    # The premise of the two-model comparison: shuffling a one-agent list draws nothing.
    r = Xoshiro(1)
    r0 = copy(r)
    shuffle!(r, [1])
    @test r == r0
    for rule in ("distance", "distance-random"), s in 1:20
        m, a, b = cd_pair(rule, CD_A; seed=s)
        before = copy(m.rng)
        culture_transmit!(m, a)
        @test tags_of(b) == CD_A
        @test m.rng == before                         # d = 0: nothing drawn
        alone = cd_world(rule; seed=s)                # the same seed with no b at all
        culture_transmit!(alone, tag!(put_agent(alone, 2, 2), CD_A))
        @test rand(m.rng) == rand(alone.rng)
        # The contrast: one tag apart, the copy draw is made.
        m1, a1, _ = cd_pair(rule, [0, 0, 0, 0, 1]; seed=s)
        before1 = copy(m1.rng)
        culture_transmit!(m1, a1)
        @test m1.rng != before1
    end
end

@testset "test_culture_rule_config" begin
    dist = (; tag_length=5, culture=true, combat_alpha=2.0, combat_hostility=0.5)
    @test Config().culture_rule == "random"
    @test validate(Config(; dist...)).culture_rule == "random"
    @test_throws ArgumentError validate(Config(; dist..., culture_rule="near"))
    for rule in ("distance", "distance-random")
        @test_throws ArgumentError validate(Config(; dist..., culture=false, culture_rule=rule))
        @test_throws ArgumentError validate(Config(; dist..., combat_hostility=0.0, culture_rule=rule))
        @test_throws ArgumentError validate(Config(; dist..., combat_hostility=1.0, culture_rule=rule))
        @test validate(Config(; dist..., culture_rule=rule)).culture_rule == rule
    end
    @test validate(Config(; dist..., combat_hostility=1.0)).culture_rule == "random"  # h = 1 is fine for "random"
end
