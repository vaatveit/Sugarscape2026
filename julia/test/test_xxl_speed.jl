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

# xxl rule 2: speed and travel cost (spec, "Speed and travel cost"). Uses `net_value`, `step_site`, `travel_periods`
# and the speed branch of `xxl_move!`.
using Random: Xoshiro

# Rules with speed S (no spread), travel cost c, and either vision shape.
function speed_rules(S, c; shape="lattice")
    return XxlRules(; vision_shape=shape, speed=(S, S), travel_cost=c)
end

# A model on the capacity grid `cap` with one agent at (x, y) holding `sugar`, speed S and travel cost c.
function speed_world(cap, x, y; S=5, c=0.1, vision=S, sugar=10.0, shape="lattice", kw...)
    m = tiny_model(cap; xxl=speed_rules(S, c; shape), vision=(vision, vision), kw...)
    a = put_agent(m, x, y; vision=vision, sugar=sugar)
    a.speed = S
    return m, a
end

@testset "travel_periods" begin
    @test travel_periods(0.0, 5) == 1
    @test travel_periods(1.0, 5) == 1
    @test travel_periods(5.0, 5) == 1
    @test travel_periods(sqrt(26), 5) == 2
    @test travel_periods(13.0, 5) == 3
    @test travel_periods(13.0, 0) == 1   # without speed every site is one period away
end

@testset "net value" begin
    @testset "one commodity" begin
        m, a = speed_world(zeros(Int, 30, 30), 10, 10; S=5, c=0.1, vision=6, sugar=20.0)
        a.metabolism = 2
        w = 5.0
        @test net_value(m, a, 10, 10, 0.0, w, 0.0) ≈ 20 + w
        @test net_value(m, a, 13, 10, 3.0, w, 0.0) ≈ 20 - 0.1 * 3 + w   # one period: no metabolism on the way
        @test net_value(m, a, 23, 10, 13.0, w, 0.0) ≈ 20 - 0.1 * 13 - 2 * 2 + w   # three periods: two on the way
    end

    @testset "two commodities" begin
        m, a = speed_world(
            zeros(Int, 30, 30), 10, 10; S=5, c=0.1, vision=6, sugar=30.0, spice=true
        )
        a.metabolism, a.spice_metabolism, a.spice, a.foresight = 2, 3, 25.0, 2
        s, q = 4.0, 3.0
        # Foresight takes 2 periods of burn off the holdings first, then the trip's own cost comes off.
        for (d, T) in ((0.0, 1), (3.0, 1), (13.0, 3))
            h1 = max(30.0 - 2 * 2, 0.0) - 0.1 * d - 2 * (T - 1)
            h2 = max(25.0 - 2 * 3, 0.0) - 3 * (T - 1)
            @test net_value(m, a, 10, 10, d, s, q) ≈ welfare(a, h1 + s, h2 + q)
        end
    end

    @testset "drop on real holdings" begin
        m, a = speed_world(zeros(Int, 30, 30), 10, 10; S=2, c=0.1, vision=10, sugar=3.0)
        a.metabolism = 1
        # sugar - c d - m (T - 1): d = 8 is T = 4, so 3 - 0.8 - 3 = -0.8
        @test net_value(m, a, 18, 10, 8.0, 4.0, 0.0) == -Inf
        @test isfinite(net_value(m, a, 16, 10, 6.0, 4.0, 0.0))   # 3 - 0.6 - 2 > 0
        a.sugar = 0.0
        @test isfinite(net_value(m, a, 10, 10, 0.0, 4.0, 0.0))   # the own site is never dropped
        @test net_value(m, a, 11, 10, 1.0, 4.0, 0.0) == -Inf
    end

    @testset "drop on real spice holdings" begin
        m, a = speed_world(
            zeros(Int, 30, 30), 10, 10; S=2, c=0.0, vision=10, sugar=50.0, spice=true
        )
        a.metabolism, a.spice_metabolism, a.spice = 1, 1, 2.5
        @test isfinite(net_value(m, a, 16, 10, 6.0, 1.0, 1.0))   # T = 3: 2.5 - 2 > 0
        @test net_value(m, a, 18, 10, 8.0, 1.0, 1.0) == -Inf   # T = 4: 2.5 - 3 <= 0
        @test isfinite(net_value(m, a, 10, 10, 0.0, 1.0, 1.0))
    end

    @testset "travel is charged after the clamp" begin
        # Sugar 5 is below foresight 3 x metabolism 2, so b1 = 0, yet the agent still pays 0.1 a site.
        m, a = speed_world(
            zeros(Int, 30, 30), 10, 10; S=6, c=0.1, vision=6, sugar=5.0, spice=true
        )
        a.metabolism, a.spice_metabolism, a.spice, a.foresight = 2, 1, 50.0, 3
        near_v = net_value(m, a, 12, 10, 2.0, 4.0, 4.0)
        far_v = net_value(m, a, 4, 10, 6.0, 4.0, 4.0)
        @test near_v ≈ welfare(a, 0 - 0.2 + 4.0, 47.0 + 4.0)
        @test far_v ≈ welfare(a, 0 - 0.6 + 4.0, 47.0 + 4.0)
        @test near_v > far_v
    end
end

@testset "travel after the clamp, in a move" begin
    cap = zeros(Int, 30, 30)
    cap[13, 11] = 4   # (12, 10): 2 east
    cap[5, 11] = 4    # (4, 10): 6 west
    function poor_world(c)
        m, a = speed_world(
            cap, 10, 10; S=6, c=c, vision=6, sugar=5.0, spice=true, foresight=(0, 10)
        )
        set_spice!(m.landscape, cap)
        a.metabolism, a.spice_metabolism, a.spice, a.foresight = 2, 1, 50.0, 3
        return m, a
    end
    m, a = poor_world(0.1)
    move!(m, a)
    @test (a.x, a.y) == (12, 10)   # moves though b1 = 0, and the nearer of two equal sites wins
    @test a.moved_dist == 2.0

    # The same agent at c = 0 (T = 1): the target is rule M's, the book's welfare move.
    m, a = poor_world(0.0)
    book = tiny_model(cap; spice=true, vision=(6, 6), foresight=(0, 10))
    set_spice!(book.landscape, cap)
    b = put_agent(book, 10, 10; vision=6, sugar=5.0)
    b.metabolism, b.spice_metabolism, b.spice, b.foresight = 2, 1, 50.0, 3
    move!(m, a)
    move!(book, b)
    @test (a.x, a.y) == (b.x, b.y) == (12, 10)
end

@testset "drop on real holdings, in a move" begin
    cap = zeros(Int, 25, 25)
    cap[19, 11] = 4   # (18, 10): 8 east, four periods away at speed 2
    cap[9, 11] = 1    # (8, 10): 2 west
    spice = zeros(Int, 25, 25)
    spice[19, 11] = 4   # spice only at the far site
    for (holding, expected) in ((2.5, (8, 10)), (5.0, (12, 10)))
        m, a = speed_world(cap, 10, 10; S=2, c=0.0, vision=10, sugar=50.0, spice=true)
        set_spice!(m.landscape, spice)
        a.metabolism, a.spice_metabolism, a.spice = 1, 1, holding
        move!(m, a)
        @test (a.x, a.y) == expected   # (12, 10) is two steps toward the rich site
    end
end

@testset "ties" begin
    function trials(offsets; shape="lattice", n=2000)
        m, a = speed_world(zeros(Int, 21, 21), 10, 10; S=5, c=0.0, vision=5, shape)
        counts = Dict(o => 0 for o in offsets)
        for _ in 1:n
            m.landscape.sugar .= 0.0
            for (dx, dy) in offsets
                m.landscape.sugar[10 + dx + 1, 10 + dy + 1] = 4.0
            end
            move_agent!(m, a, 10, 10)
            move!(m, a)
            counts[(a.x - 10, a.y - 10)] += 1
        end
        return counts
    end
    for shape in ("lattice", "disc")
        counts = trials([(3, 0), (-3, 0)]; shape)
        @test 800 <= counts[(3, 0)] <= 1200
        @test 800 <= counts[(-3, 0)] <= 1200
        counts = trials([(2, 0), (4, 0), (0, -5)]; shape)
        @test counts[(2, 0)] == 2000   # equal value, the nearer always wins
    end
end

@testset "near set with speed" begin
    m, a = speed_world(zeros(Int, 31, 31), 15, 15; S=4, c=0.1, vision=8, shape="disc")
    near_sites = [wrap(m, a.x + dx, a.y + dy) for (dx, dy) in disc_offsets(4.0)]
    ok = true
    for _ in 1:100
        sites = look!(m, a)
        ok &= all(s -> s in sites, near_sites)
    end
    @test ok
end

@testset "all candidates dropped" begin
    cap = fill(2, 15, 15)
    m, a = speed_world(cap, 7, 7; S=3, c=0.1, vision=5, sugar=0.05)
    move!(m, a)
    @test (a.x, a.y) == (7, 7)
    @test !a.moved
    @test a.moved_dist == 0.0
    @test a.sugar ≈ 2.05   # harvested the own site
    @test m.landscape.sugar[8, 8] == 0.0
end

@testset "step_site" begin
    @testset "walk" begin
        m, a = speed_world(zeros(Int, 30, 30), 2, 10; S=5, vision=14)
        @test step_site(m, a, 15, 10) == (7, 10)   # 13 away: 5 along the line
        blocker = put_agent(m, 7, 10)
        @test step_site(m, a, 15, 10) == (6, 10)   # that site occupied: 4
        @test step_site(m, a, 15, 10; ok=(x, y) -> x != 6) == (5, 10)   # `ok` refuses it too
        @test step_site(m, a, 4, 10) == (4, 10)   # within reach and empty: onto it
        @test step_site(m, a, 7, 10) == (6, 10)   # within reach, occupied: the walk, from k = floor(d)
        @test step_site(m, a, 2, 10) == (2, 10)   # own site
        @test step_site(m, a, 7, 10; ok=(x, y) -> false) == (2, 10)   # nothing allowed: stay
        @test (a.x, a.y) == (2, 10) && m.grid[8, 11] === blocker   # pure: nothing moved
    end

    @testset "diagonal" begin
        m, a = speed_world(zeros(Int, 30, 30), 10, 10; S=5, vision=14)
        @test step_site(m, a, 18, 16) == (14, 13)   # d = 10: 5 along (0.8, 0.6)
    end

    @testset "crosses the seam" begin
        for (S, expected) in
            ((5, (496, 10)), (6, (496, 10)), (4, (497, 10)), (2, (499, 10)))
            m, a = speed_world(zeros(Int, 500, 20), 1, 10; S=S, vision=S)
            @test step_site(m, a, 496, 10) == expected
        end
    end

    @testset "never lands on an occupied site" begin
        m, a = speed_world(zeros(Int, 30, 30), 10, 10; S=4, vision=8)
        for x in 11:14
            put_agent(m, x, 10)
        end
        @test step_site(m, a, 14, 10) == (10, 10)
        @test step_site(m, a, 18, 10) == (10, 10)
    end
end

@testset "walk, in a move" begin
    cap = zeros(Int, 30, 30)
    cap[16, 11] = 4   # (15, 10): 13 east of (2, 10)
    m, a = speed_world(cap, 2, 10; S=5, vision=14)
    move!(m, a)
    @test (a.x, a.y) == (7, 10)
    @test a.moved_dist == 5.0
    @test a.moved
    @test m.landscape.sugar[16, 11] == 4.0   # not harvested yet

    m, a = speed_world(cap, 2, 10; S=5, vision=14)
    put_agent(m, 7, 10)
    move!(m, a)
    @test (a.x, a.y) == (6, 10)
    @test a.moved_dist == 4.0
end

@testset "travel cost is charged" begin
    cap = zeros(Int, 21, 21)
    cap[10, 11] = 4   # (9, 10): 4 east of (5, 10)
    m, a = speed_world(cap, 5, 10; S=4, c=0.25, vision=5, sugar=10.0, pollution=(0.0, 1.0))
    a.metabolism = 1
    move!(m, a)
    @test (a.x, a.y) == (9, 10)
    @test a.moved_dist == 4.0
    @test a.sugar == 14.0
    metabolize!(m, a)
    @test a.sugar == 14.0 - 1 - 1.0   # the burn and 0.25 x 4
    @test a.last_income == 4.0 - 1 - 1.0   # the credit rule reads it as burn
    @test m.landscape.pollution[10, 11] == 1.0 * (1 + 1.0)   # consumption pollution counts it

    # Without speed in the rules there is no charge.
    plain = tiny_model(cap; vision=(5, 5), pollution=(0.0, 1.0))
    b = put_agent(plain, 5, 10; vision=5)
    move!(plain, b)
    metabolize!(plain, b)
    @test b.sugar == 10.0 + 4.0 - 1
end

@testset "rule M again" begin
    # speed = vision, c = 0, the lattice look: the book's rule M picks the same site (one clear best, so no ties).
    rng = Xoshiro(11)
    ok = true
    for trial in 1:40
        cap = rand(rng, 0:3, 21, 21)
        arm = rand(rng, [(1, 0), (-1, 0), (0, 1), (0, -1)])
        k = rand(rng, 1:6)
        cap[10 + arm[1] * k + 1, 10 + arm[2] * k + 1] = 4
        m, a = speed_world(cap, 10, 10; S=6, c=0.0, vision=6, sugar=5.0, seed=trial)
        book = tiny_model(cap; vision=(6, 6), seed=trial)
        b = put_agent(book, 10, 10; vision=6, sugar=5.0)
        move!(m, a)
        move!(book, b)
        ok &= (a.x, a.y) == (b.x, b.y)
    end
    @test ok
end
