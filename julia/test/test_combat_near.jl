# VI-1-near in the book's move (docs/superpowers/specs/2026-11-09-vi1-reach-design.md, "VI-1-near"): with
# combat_reach "neighbours", attack, fear and movement reach only the 4 adjacent sites, whatever vision and look_stride.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function near_model(; reach="neighbours", kw...)
    return tiny_model(
        zeros(Int, 12, 12); tag_length=5, combat_alpha=Inf, vision=(1, 4), combat_hostility=1.0,
        combat_reach=reach, kw...
    )
end

near_agent(m, x, y, tags, sugar; vision=4) = tag!(put_agent(m, x, y; vision=vision, sugar=sugar), tags)

const ATTACKER_TAGS = [0, 0, 0, 0, 0]
const OTHER_TAGS = [1, 1, 1, 1, 1]  # d = 5, p = 1

steps(a, x, y) = abs(a.x - x) + abs(a.y - y)

@testset "test_near_far_occupant_not_attacked" begin
    for s in 1:20
        m = near_model(; seed=s)
        a = near_agent(m, 1, 1, ATTACKER_TAGS, 20.0)
        m.landscape.sugar[4, 2] = 10.0  # the occupant's site (3, 1) is sugar-rich
        r = near_agent(m, 3, 1, OTHER_TAGS, 5.0)
        combat_move!(m, a)
        @test r.alive
        @test steps(a, 1, 1) <= 1
    end
end

@testset "test_near_adjacent_occupant_attacked" begin
    for s in 1:20
        m = near_model(; seed=s)
        a = near_agent(m, 1, 1, ATTACKER_TAGS, 20.0)
        r = near_agent(m, 2, 1, OTHER_TAGS, 5.0)
        combat_move!(m, a)
        @test !r.alive
        @test (a.x, a.y) == (2, 1)
    end
end

@testset "test_near_moves_one_step" begin
    for s in 1:20
        m = near_model(; seed=s)
        a = near_agent(m, 1, 1, ATTACKER_TAGS, 20.0)
        m.landscape.sugar[5, 2] = 10.0  # the only sugar, at (4, 1): 3 sites away, within vision 4
        combat_move!(m, a)
        @test steps(a, 1, 1) <= 1
    end
end

# The attacker at (1, 1), its only target (p = 1) at (2, 1), and a richer distant-tag watcher at (wx, 1).
function near_watched(wx; seed=1)
    m = near_model(; seed=seed)
    a = near_agent(m, 1, 1, ATTACKER_TAGS, 20.0)
    r = near_agent(m, 2, 1, OTHER_TAGS, 5.0)
    near_agent(m, wx, 1, OTHER_TAGS, 100.0)
    combat_move!(m, a)
    return r
end

@testset "test_near_far_watcher_not_feared" begin
    @test all(s -> !near_watched(4; seed=s).alive, 1:20)  # 2 sites from the target
end

@testset "test_near_adjacent_watcher_feared" begin
    @test all(s -> near_watched(3; seed=s).alive, 1:20)  # 1 site from the target
end

@testset "test_near_ignores_stride" begin  # Review Focus 1
    for s in 1:20
        m = tiny_model(
            zeros(Int, 100, 100); tag_length=5, combat_alpha=Inf, vision=(10, 40), combat_hostility=1.0,
            combat_reach="neighbours", look_stride=10, seed=s,
        )
        a = near_agent(m, 1, 1, ATTACKER_TAGS, 20.0; vision=40)
        r = near_agent(m, 2, 1, OTHER_TAGS, 5.0; vision=40)
        combat_move!(m, a)
        @test !r.alive
    end
end

@testset "test_vision_reach_unchanged" begin
    m = near_model(; reach="vision", seed=1)
    a = near_agent(m, 1, 1, ATTACKER_TAGS, 20.0)
    m.landscape.sugar[4, 2] = 10.0
    r = near_agent(m, 3, 1, OTHER_TAGS, 5.0)
    combat_move!(m, a)
    @test !r.alive
    @test (a.x, a.y) == (3, 1)
end
