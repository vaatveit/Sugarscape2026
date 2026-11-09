# VI-1-near in the xxl move (docs/superpowers/specs/2026-11-09-vi1-reach-design.md, "VI-1-near"): with combat_reach
# "neighbours" and round vision, the candidates are the own site and the sites within the interaction radius (1.5),
# each attackable and reached by a jump whatever the speed; remembered sites are not candidates; a site is vulnerable if
# an agent within 1.5 of it passes the fear test. The look and memory run as now. Calls `xxl_combat_move!` directly.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: xxl_combat_move!, Remembered, torus_dist

# A 30x30 world of bare sites with round vision, speed S, vision V, memory M, interaction radius 1.5, no travel cost,
# combat with alpha = Inf, 5 tag positions, h = 1 and combat_reach `reach`.
function xn_world(; S, V=S, M=0, reach="neighbours", seed=1)
    return tiny_model(
        zeros(Int, 30, 30);
        tag_length=5,
        combat_alpha=Inf,
        combat_hostility=1.0,
        combat_reach=reach,
        xxl=XxlRules(;
            vision_shape="disc", speed=(S, S), travel_cost=0.0, memory=M, interaction_radius=1.5
        ),
        vision=(V, V),
        seed=seed,
    )
end

# An agent at (x, y) with tags `tags`, holding `sugar`, vision V and speed S.
function xn_agent(m, x, y, tags, sugar; S, V=S)
    a = put_agent(m, x, y; vision=V, sugar=sugar)
    a.speed = S
    return tag!(a, tags)
end

const XN_A = [0, 0, 0, 0, 0]
const XN_B = [1, 1, 1, 1, 1]  # all different from XN_A: d = L, p = 1 at h = 1

xn_from(m, a, x, y) = torus_dist(m.landscape.width, m.landscape.height, a.x, a.y, x, y)

@testset "test_xxl_near_diagonal_attacked_at_speed_1" begin
    # vision 1 looks at the 4 adjacent sites only; vision 3 adds a sampled ring that may miss the diagonal
    for V in (1, 3), s in 1:20
        m = xn_world(; S=1, V=V, seed=s)
        a = xn_agent(m, 10, 10, XN_A, 20.0; S=1, V=V)
        r = xn_agent(m, 11, 11, XN_B, 5.0; S=1, V=V)
        xxl_combat_move!(m, a)
        @test !r.alive
        @test (a.x, a.y) == (11, 11)
    end
end

@testset "test_xxl_near_far_occupant_not_attacked" begin
    for s in 1:20
        m = xn_world(; S=6, seed=s)
        a = xn_agent(m, 10, 10, XN_A, 20.0; S=6)
        r = xn_agent(m, 13, 10, XN_B, 5.0; S=6)
        m.landscape.sugar[13 + 1, 10 + 1] = 10.0
        xxl_combat_move!(m, a)
        @test r.alive
        @test xn_from(m, a, 10, 10) <= 1.5
    end
end

# The attacker at (10, 10), its only target at (11, 10), and a richer watcher at (wx, 10); speed and vision 3, so
# today's look from the target sees the watcher at (14, 10).
function xn_watched(wx; seed=1)
    m = xn_world(; S=3, seed=seed)
    a = xn_agent(m, 10, 10, XN_A, 20.0; S=3)
    r = xn_agent(m, 11, 10, XN_B, 5.0; S=3)
    xn_agent(m, wx, 10, XN_B, 100.0; S=3)
    xxl_combat_move!(m, a)
    return r
end

@testset "test_xxl_near_watchers" begin
    @test all(s -> !xn_watched(14; seed=s).alive, 1:20)  # 3 sites from the target: not feared
    @test all(s -> xn_watched(12; seed=s).alive, 1:20)  # 1 site from the target: feared
end

@testset "test_xxl_near_memory_kept" begin  # Review Focus 2
    for s in 1:20
        m = xn_world(; S=6, M=8, seed=s)
        a = xn_agent(m, 10, 10, XN_A, 20.0; S=6)
        m.landscape.sugar[14 + 1, 10 + 1] = 40.0  # 4 away, within the look's near radius 6
        xxl_combat_move!(m, a)
        @test xn_from(m, a, 10, 10) <= 1.5
        @test any(e -> (e.x, e.y) == (14, 10), a.memory)
        @test !a.target_remembered
    end
end

@testset "test_xxl_near_no_remembered_targets" begin
    for s in 1:20
        m = xn_world(; S=3, M=8, seed=s)
        a = xn_agent(m, 10, 10, XN_A, 20.0; S=3)
        push!(a.memory, Remembered(16, 10, 40.0, 0.0, 0.0, 0))  # 6 away, beyond vision 3
        xxl_combat_move!(m, a)
        @test xn_from(m, a, 10, 10) <= 1.5
        @test !a.target_remembered
    end
end

@testset "test_xxl_near_vision_reach_unchanged" begin  # the default still attacks 3 away and walks to memory
    m = xn_world(; S=6, reach="vision")
    a = xn_agent(m, 10, 10, XN_A, 20.0; S=6)
    r = xn_agent(m, 13, 10, XN_B, 5.0; S=6)
    m.landscape.sugar[13 + 1, 10 + 1] = 10.0
    xxl_combat_move!(m, a)
    @test !r.alive && (a.x, a.y) == (13, 10)
end
