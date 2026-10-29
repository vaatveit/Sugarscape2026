# xxl rule 7: combat under round vision and speed (spec, "Combat (rule C)"). Calls `xxl_combat_move!` directly (not
# `step!`), so metabolism and travel cost don't blur the amounts. Victims and threats sit off the lattice axes, where
# the book's lattice look can't find them.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: xxl_combat_move!, disc_vulnerable

# Rules for combat: the disc or lattice look, speed S (nothing for 0), no travel cost, memory M.
function combat_rules(S; shape="disc", M=0, c=0.0)
    return XxlRules(;
        vision_shape=shape, speed=S == 0 ? nothing : (S, S), travel_cost=c, memory=M
    )
end

# A 30x30 world of bare sites with vision `V` and speed `S` rules, combat with alpha = `alpha`, 11 tag positions.
function combat_world(; S=3, V=S, shape="disc", M=0, alpha=Inf, kw...)
    return tiny_model(
        zeros(Int, 30, 30);
        tag_length=11,
        combat_alpha=alpha,
        xxl=combat_rules(S; shape, M),
        vision=(V, V),
        kw...,
    )
end

# An agent of tribe `side` (:blue tags all 0, :red all 1) at (x, y), holding `sugar`.
function fighter(m, x, y, side, sugar; V, S)
    a = put_agent(m, x, y; vision=V, sugar=sugar)
    a.speed = S
    return tag!(a, fill(side === :red ? 1 : 0, 11))
end

@testset "attack within reach" begin
    m = combat_world(; S=3)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    red = fighter(m, 12, 11, :red, 8.0; V=3, S=3)
    m.landscape.sugar[12 + 1, 11 + 1] = 2.0
    xxl_combat_move!(m, blue)
    @test !red.alive
    @test (blue.x, blue.y) == (12, 11)
    @test blue.sugar == 20 + 8 + 2   # min(alpha, 8) from the victim, then the site's sugar
    @test blue.moved && blue.moved_dist ≈ sqrt(5)
    @test all(iszero, m.landscape.pollution)   # combat harvests without production pollution
    @test m.landscape.sugar[12 + 1, 11 + 1] == 0.0
end

@testset "the reward is capped at alpha" begin
    m = combat_world(; S=3, alpha=3.0)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    red = fighter(m, 12, 11, :red, 8.0; V=3, S=3)
    xxl_combat_move!(m, blue)
    @test !red.alive && blue.sugar == 23.0
end

@testset "no attack beyond reach" begin
    # Red is 3.6 away, in the ring beyond the near radius 2, so a look holds it only by a random ring draw. Find a seed
    # whose look does (the probe and the move make the same first draws), so reach is what spares red.
    build(seed) = begin
        m = combat_world(; S=2, V=6, seed)
        blue = fighter(m, 10, 10, :blue, 20.0; V=6, S=2)
        red = fighter(m, 13, 12, :red, 8.0; V=6, S=2)
        m.landscape.sugar[13 + 1, 12 + 1] = 5.0
        (m, blue, red)
    end
    seed = findfirst(1:500) do s
        m, blue, _ = build(s)
        (13, 12) in look!(m, blue)
    end
    @test seed !== nothing
    m, blue, red = build(seed)
    xxl_combat_move!(m, blue)
    @test red.alive
    @test blue.sugar == 20.0
end

@testset "own tribe and wealthier occupants are passed over" begin
    m = combat_world(; S=3)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    kin = fighter(m, 12, 11, :blue, 1.0; V=3, S=3)
    rich = fighter(m, 11, 12, :red, 25.0; V=3, S=3)
    xxl_combat_move!(m, blue)
    @test kin.alive && rich.alive
    @test blue.sugar == 20.0
end

@testset "retaliation within reach" begin
    m = combat_world(; S=3)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    m.landscape.sugar[12 + 1, 11 + 1] = 9.0   # the best site, 2.2 away
    m.landscape.sugar[8 + 1, 9 + 1] = 5.0     # the next best, 2.2 away the other way
    # Red holds 40 > 20 + 9, 2.2 from the best site; it is 4.5 from blue's own site and 6.7 from the next best.
    fighter(m, 14, 12, :red, 40.0; V=3, S=3)
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (8, 9)
    @test blue.sugar == 25.0
    # Without the threat the best site wins.
    m = combat_world(; S=3)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    m.landscape.sugar[12 + 1, 11 + 1] = 9.0
    m.landscape.sugar[8 + 1, 9 + 1] = 5.0
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (12, 11)
end

@testset "retaliation does not count the attacker or the victim" begin
    m = combat_world(; S=3)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    red = fighter(m, 12, 11, :red, 30.0; V=3, S=3)   # richer than blue: never a candidate, but a check can name it
    # After taking 6 blue would hold 26 < 30: the red agent threatens the site, unless it is the victim.
    @test disc_vulnerable(m, blue, 12, 11, 6.0, nothing)
    @test !disc_vulnerable(m, blue, 12, 11, 6.0, red)
    # Another red agent is not excused. Blue itself (10, 10, in this look) never counts.
    fighter(m, 13, 11, :red, 30.0; V=3, S=3)
    @test disc_vulnerable(m, blue, 12, 11, 6.0, red)
    @test !disc_vulnerable(m, blue, 12, 11, 12.0, red)   # 30 > 32 is false
    @test !disc_vulnerable(m, blue, 10, 10, 100.0, nothing)   # nobody holds 120
end

@testset "walk lands safe" begin
    # A remembered target 9 away (beyond vision 3) with speed 3: the walk's landing sites are k = 3, 2, 1 along x.
    function walk_world(threats)
        m = combat_world(; S=3, M=8)
        blue = fighter(m, 5, 10, :blue, 10.0; V=3, S=3)
        push!(blue.memory, Remembered(14, 10, 40.0, 0.0, 0.0, 0))
        for (x, y) in threats
            fighter(m, x, y, :red, 100.0; V=3, S=3)
        end
        return m, blue
    end
    # Red at (10, 10) is within 3 of k = 3 (8, 10) and k = 2 (7, 10), but not of k = 1 (6, 10).
    m, blue = walk_world([(10, 10)])
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (6, 10)
    @test blue.target_remembered
    @test blue.moved_dist ≈ 1.0
    # With no threat, the walk goes as far as it can.
    m, blue = walk_world(Tuple{Int,Int}[])
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (8, 10)
    @test blue.target_remembered
end

@testset "no safe step" begin
    m = combat_world(; S=3, M=8)
    blue = fighter(m, 5, 10, :blue, 10.0; V=3, S=3)
    push!(blue.memory, Remembered(14, 10, 40.0, 0.0, 0.0, 0))
    m.landscape.sugar[4 + 1, 9 + 1] = 5.0   # the next best, 1.4 away
    # Red at (8, 12) is within 3 of all of (8, 10), (7, 10) and (6, 10), and 3.6 from blue and 5 from (4, 9).
    fighter(m, 8, 12, :red, 100.0; V=3, S=3)
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (4, 9)
    @test !blue.target_remembered
    @test blue.sugar == 15.0
end

@testset "safe ties are fair" begin
    # Three equal sites, all 3 away. Each in turn is the unsafe one (a red agent 3 beyond it, out of the others' reach),
    # so the unsafe tie comes first, between or last in the order looked at.
    sites = ((13, 10), (7, 10), (10, 13))
    threats = ((16, 10), (4, 10), (10, 16))
    trials = 2000
    for (unsafe, threat) in zip(sites, threats)
        counts = Dict(s => 0 for s in sites)
        for seed in 1:trials
            m = combat_world(; S=3, seed)
            blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
            for (x, y) in sites
                m.landscape.sugar[x + 1, y + 1] = 5.0
            end
            fighter(m, threat..., :red, 100.0; V=3, S=3)
            xxl_combat_move!(m, blue)
            counts[(blue.x, blue.y)] = get(counts, (blue.x, blue.y), 0) + 1
        end
        @test counts[unsafe] == 0
        for s in sites
            s == unsafe || @test 0.4 * trials <= counts[s] <= 0.6 * trials
        end
    end
end

@testset "disc only: a jump" begin
    # Round vision without speed: near radius 1, so the target at (2, 1) comes from the ring draws. Find a seed whose
    # look holds it (the probe and the move make the same first draws).
    build(seed) = begin
        m = combat_world(; S=0, V=3, seed)
        blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=0)
        red = fighter(m, 12, 11, :red, 8.0; V=3, S=0)
        m.landscape.sugar[12 + 1, 11 + 1] = 2.0
        (m, blue, red)
    end
    seed = findfirst(1:500) do s
        m, blue, _ = build(s)
        (12, 11) in look!(m, blue)
    end
    @test seed !== nothing
    m, blue, red = build(seed)
    xxl_combat_move!(m, blue)
    @test !red.alive
    @test (blue.x, blue.y) == (12, 11)
    @test blue.sugar == 30.0
end

@testset "combat_move! dispatches to xxl" begin
    m = combat_world(; S=3)
    blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=3)
    red = fighter(m, 12, 11, :red, 8.0; V=3, S=3)
    combat_move!(m, blue)
    @test !red.alive && (blue.x, blue.y) == (12, 11)
end

@testset "book combat again" begin
    # Lattice look, speed = vision, no travel cost, no look draws: the book's choice, when there are no ties.
    function layout(xxl)
        m = tiny_model(
            zeros(Int, 30, 30);
            tag_length=11,
            combat_alpha=Inf,
            vision=(3, 3),
            look_stride=1,
            xxl=xxl,
        )
        blue = fighter(m, 10, 10, :blue, 20.0; V=3, S=xxl === nothing ? 0 : 3)
        red = fighter(m, 12, 10, :red, 8.0; V=3, S=xxl === nothing ? 0 : 3)
        fighter(m, 10, 13, :red, 60.0; V=3, S=xxl === nothing ? 0 : 3)   # a rich red, two sites from (10, 11)
        m.landscape.sugar[10 + 1, 12 + 1] = 3.0
        m.landscape.sugar[8 + 1, 10 + 1] = 4.0
        return m, blue, red
    end
    book, bblue, bred = layout(nothing)
    combat_move!(book, bblue)
    xxl, xblue, xred = layout(combat_rules(3; shape="lattice"))
    xxl_combat_move!(xxl, xblue)
    @test (xblue.x, xblue.y) == (bblue.x, bblue.y) == (12, 10)
    @test xred.alive == bred.alive == false
    @test xblue.sugar == bblue.sugar
end

@testset "combat runs through step! under xxl" begin
    cfg = Config(;
        tag_length=11,
        combat_alpha=Inf,
        endowment=(25, 50),
        seed=0,
        vision=(3, 6),
        initial_blocks=[("blue", 0, 0, 20, 20, 270), ("red", 30, 30, 20, 20, 270)],
        xxl=XxlRules(;
            vision_shape="disc", speed=(1, 3), travel_cost=0.1, memory=4, word_of_mouth=true
        ),
    )
    m = Model(cfg)
    ok = true
    for _ in 1:30
        step!(m)
        ok &= all(a.alive && agent_at(m, a.x, a.y) === a for a in m.agents)
        ok &= length(Set((a.x, a.y) for a in m.agents)) == length(m.agents)
    end
    @test ok
    @test any(!isempty(a.memory) for a in m.agents)
end
