# Rule C by cultural distance in the xxl move, and the kill log
# (docs/superpowers/specs/2026-11-09-vi1-distance-design.md, "The rule: C by distance" and "Readings"): fight and fear
# drawn with p = h d / L in `xxl_combat_move!` and `disc_vulnerable`, one draw per pair per move; every kill logged as
# (distance, same_label) and read by the combat observer with its period. The xxl tests call `xxl_combat_move!`
# directly on a fresh model (an empty `m.hostile`).
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: xxl_combat_move!, CombatReadings, combat_period!, kill_rows

# A 30x30 world of bare sites with round vision and speed 3 (the near radius is the speed, so a look with vision 3
# sees every site within 3 and draws nothing), no travel cost, combat with alpha = Inf, 5 tag positions, hostility `h`.
function xd_world(h; kw...)
    return tiny_model(
        zeros(Int, 30, 30);
        tag_length=5,
        combat_alpha=Inf,
        combat_hostility=h,
        xxl=XxlRules(; vision_shape="disc", speed=(3, 3), travel_cost=0.0),
        vision=(3, 3),
        kw...,
    )
end

# An agent with tags `tags` at (x, y), holding `sugar`, vision and speed 3.
function xd_agent(m, x, y, tags, sugar)
    a = put_agent(m, x, y; vision=3, sugar=sugar)
    a.speed = 3
    return tag!(a, tags)
end

# The attacker at (10, 10) and a poorer occupant 2.2 away at (12, 11), on a site of sugar 2; true if it was attacked.
function xd_attacked(occupant_tags, seed; attacker_tags=[0, 0, 0, 0, 0])
    m = xd_world(1.0; seed=seed)
    a = xd_agent(m, 10, 10, attacker_tags, 20.0)
    r = xd_agent(m, 12, 11, occupant_tags, 5.0)
    m.landscape.sugar[12 + 1, 11 + 1] = 2.0
    xxl_combat_move!(m, a)
    return !r.alive
end

@testset "test_xxl_identical_tags_never_attacked" begin
    t = [0, 1, 0, 1, 0]
    @test !any(s -> xd_attacked(t, s; attacker_tags=t), 1:200)
end

@testset "test_xxl_distant_occupant_attacked" begin
    @test all(s -> xd_attacked([1, 1, 1, 1, 1], s), 1:50)  # h = 1, d = L: p = 1
    # the same label as the attacker, d = 2, p = 0.4: the label alone would never attack
    hits = count(s -> xd_attacked([0, 0, 0, 1, 1], s), 1:200)
    @test 0 < hits < 200
end

# The attacker at (10, 10), its only target (p = 1) at (12, 11), and a richer watcher at (14, 12): in sight of the
# target (2.2 away), out of the attacker's sight from its own site (4.5 away).
function xd_watched(watcher_tags; seed=1)
    m = xd_world(1.0; seed=seed)
    a = xd_agent(m, 10, 10, [0, 0, 0, 0, 0], 20.0)
    r = xd_agent(m, 12, 11, [1, 1, 1, 1, 1], 5.0)
    xd_agent(m, 14, 12, watcher_tags, 100.0)
    xxl_combat_move!(m, a)
    return r
end

@testset "test_xxl_distant_watcher_feared" begin
    @test all(s -> xd_watched([1, 1, 1, 1, 1]; seed=s).alive, 1:50)  # d = L: p = 1
    # the same label as the attacker, d = 2, p = 0.4: the label alone would never fear it
    spared = count(s -> xd_watched([0, 0, 0, 1, 1]; seed=s).alive, 1:200)
    @test 0 < spared < 200
end

@testset "test_xxl_identical_watcher_not_feared" begin
    @test !xd_watched([0, 0, 0, 0, 0]).alive
end

@testset "test_xxl_watcher_one_answer" begin  # Review Focus 1
    # Two empty sites within reach, (12, 10) of sugar 4 and (10, 12) of sugar 3, both 2 from a richer distant watcher W
    # at (12, 12) (p = 0.5), which the agent also sees from its own site. Feared, W makes all three unsafe and the agent
    # goes to a bare safe site; not feared, it takes (12, 10). One answer per move: never (10, 12).
    ends = map(1:300) do s
        m = xd_world(0.5; seed=s)
        a = xd_agent(m, 10, 10, [0, 0, 0, 0, 0], 10.0)
        m.landscape.sugar[12 + 1, 10 + 1] = 4.0
        m.landscape.sugar[10 + 1, 12 + 1] = 3.0
        xd_agent(m, 12, 12, [1, 1, 1, 1, 1], 100.0)
        xxl_combat_move!(m, a)
        (a.x, a.y)
    end
    @test !((10, 12) in ends)
    @test (12, 10) in ends && any(!=((12, 10)), ends)
end

# The book's move: the attacker 00000 at (1, 1), a poorer occupant at (3, 1).
function kl_model(occupant_tags, seed)
    m = tiny_model(
        zeros(Int, 12, 12);
        tag_length=5,
        combat_alpha=Inf,
        vision=(1, 4),
        combat_hostility=1.0,
        seed=seed,
    )
    a = tag!(put_agent(m, 1, 1; vision=4, sugar=20.0), [0, 0, 0, 0, 0])
    r = tag!(put_agent(m, 3, 1; vision=1, sugar=5.0), occupant_tags)
    return m, a, r
end

@testset "test_kill_log_row" begin  # Review Focus 5
    m, a, r = kl_model([1, 1, 1, 1, 1], 1)  # d = 5, other label: p = 1
    @test isempty(m.kill_log)
    combat_move!(m, a)
    @test !r.alive
    @test m.kill_log == [(5, 0)]
    logged = NTuple{2,Int}[]
    for s in 1:50
        m, a, r = kl_model([0, 0, 0, 1, 1], s)  # d = 2, the same label: p = 0.4
        combat_move!(m, a)
        append!(logged, m.kill_log)
        @test length(m.kill_log) == (r.alive ? 0 : 1)
    end
    @test !isempty(logged) && all(==((2, 1)), logged)
end

@testset "test_readings_collect_kills" begin
    m, a, r = kl_model([1, 1, 1, 1, 1], 1)
    readings = CombatReadings()
    combat_period!(readings, m)
    @test kill_rows(readings) == (["t", "distance", "same_label"], Vector{Int}[])
    step!(m)  # the occupant, seeing no one within 1, stays; the attacker kills it, whichever moves first
    @test !r.alive && m.kill_log == [(5, 0)]
    combat_period!(readings, m)
    @test kill_rows(readings) == (["t", "distance", "same_label"], [[m.t, 5, 0]])
    @test m.t == 1
    step!(m)  # the log is emptied at the start of a step; nothing new to read
    @test isempty(m.kill_log)
    combat_period!(readings, m)
    @test kill_rows(readings)[2] == [[1, 5, 0]]
end
