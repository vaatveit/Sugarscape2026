# Rule C by cultural distance in the book's move (docs/superpowers/specs/2026-11-09-vi1-distance-design.md, "The rule:
# C by distance"): fight and fear drawn with p = h d / L, one draw per pair per move.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function distance_model(h; kw...)
    return tiny_model(
        zeros(Int, 12, 12); tag_length=5, combat_alpha=Inf, vision=(1, 4), combat_hostility=h, kw...
    )
end

dist_agent(m, x, y, tags, sugar; vision=4) = tag!(put_agent(m, x, y; vision=vision, sugar=sugar), tags)

# One world per seed: the attacker at (1, 1), a poorer occupant at (3, 1); true if the occupant was attacked.
function attacked(h, occupant_tags, seed; attacker_tags=[0, 0, 0, 0, 0])
    m = distance_model(h; seed=seed)
    a = dist_agent(m, 1, 1, attacker_tags, 20.0)
    r = dist_agent(m, 3, 1, occupant_tags, 5.0)
    combat_move!(m, a)
    return !r.alive
end

@testset "test_fight_chance" begin
    @test fight_chance(1.0, loose(0, 0, 0, 0, 0), loose(0, 0, 0, 0, 0)) == 0.0
    @test fight_chance(0.5, loose(0, 0, 0, 0, 0), loose(1, 1, 1, 1, 1)) == 0.5
    @test fight_chance(0.5, loose(0, 0, 0, 0, 0), loose(0, 0, 1, 1, 1)) ≈ 0.3
end

@testset "test_same_label_far_apart_fights" begin
    # Both blue, d = 2, p = 0.4: the label alone would never fight.
    share = count(s -> attacked(1.0, [0, 0, 0, 1, 1], s), 1:500) / 500
    @test abs(share - 0.4) <= 0.07
    @test all(s -> attacked(1.0, [1, 1, 1, 1, 1], s), 1:50)  # d = 5, p = 1
end

@testset "test_identical_tags_never_attacked" begin
    t = [0, 1, 0, 1, 0]
    @test !any(s -> attacked(1.0, t, s; attacker_tags=t), 1:200)
end

# The attacker at (1, 1), its only target (p = 1) at (3, 1), and a richer watcher at (5, 1) in sight of the target.
function watched(watcher_tags)
    m = distance_model(1.0; seed=1)
    a = dist_agent(m, 1, 1, [0, 0, 0, 0, 0], 20.0)
    r = dist_agent(m, 3, 1, [1, 1, 1, 1, 1], 5.0)
    dist_agent(m, 5, 1, watcher_tags, 100.0)
    combat_move!(m, a)
    return r
end

@testset "test_identical_watcher_not_feared" begin
    r = watched([0, 0, 0, 0, 0])
    @test !r.alive
end

@testset "test_distant_watcher_feared" begin
    r = watched([1, 1, 1, 1, 1])
    @test r.alive
end

@testset "test_one_watcher_one_answer" begin  # Review Focus 1
    ends = map(1:300) do s
        m = distance_model(0.5; seed=s)
        a = dist_agent(m, 1, 1, [0, 0, 0, 0, 0], 10.0)
        m.landscape.sugar[4, 2] = 4.0  # empty site (3, 1)
        m.landscape.sugar[2, 4] = 3.0  # empty site (1, 3)
        dist_agent(m, 3, 3, [1, 1, 1, 1, 1], 100.0)  # W: sees (3, 1) and (1, 3), each two steps away
        combat_move!(m, a)
        (a.x, a.y)
    end
    @test all(p -> p in ((3, 1), (1, 1)), ends)
    @test (3, 1) in ends && (1, 1) in ends
end

@testset "test_cache_cleared_between_moves" begin  # Review Focus 3
    m = distance_model(0.5; seed=1)
    a = dist_agent(m, 1, 1, [0, 0, 0, 0, 0], 20.0)
    r = dist_agent(m, 3, 1, [1, 1, 1, 1, 1], 5.0)
    b = dist_agent(m, 8, 8, [0, 0, 0, 0, 0], 20.0)  # meets nobody: a ends at (1, 1) or (3, 1), out of b's sight
    combat_move!(m, a)
    @test haskey(m.hostile, r.id)
    combat_move!(m, b)
    @test !haskey(m.hostile, r.id) && isempty(m.hostile)
end

@testset "test_label_rule_at_zero" begin
    for s in 1:5
        m = distance_model(0.0; seed=s)
        a = dist_agent(m, 1, 1, [0, 0, 0, 0, 0], 20.0)
        same = dist_agent(m, 3, 1, [0, 0, 0, 1, 1], 5.0)  # blue, as the attacker
        combat_move!(m, a)
        @test same.alive && isempty(m.hostile)
        m = distance_model(0.0; seed=s)
        a = dist_agent(m, 1, 1, [0, 0, 0, 0, 0], 20.0)
        other = dist_agent(m, 3, 1, [1, 1, 1, 0, 0], 5.0)  # red
        combat_move!(m, a)
        @test !other.alive && isempty(m.hostile)
    end
end

@testset "test_hostility_config" begin  # Review Focus 2
    combat = (; tag_length=11, combat_alpha=2.0)
    @test_throws ArgumentError validate(Config(; combat..., combat_hostility=-0.1))
    @test_throws ArgumentError validate(Config(; combat..., combat_hostility=1.1))
    @test_throws ArgumentError validate(Config(; tag_length=11, combat_hostility=0.5))
    @test validate(Config(; combat..., combat_hostility=1.0)).combat_hostility == 1.0
end
