# xxl rule 1: round vision (spec, "Round vision"). Uses `look!`, `xxl_move!` and `disc_in_sight`.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Random: Xoshiro

const DISC = XxlRules(; vision_shape="disc")

# A disc-vision model on an all-zero grid of side `side`, with one agent of the given vision at its centre.
function disc_world(; side=21, vision=5, speed=0)
    m = tiny_model(zeros(Int, side, side); xxl=DISC, vision=(vision, vision))
    a = put_agent(m, side ÷ 2, side ÷ 2; vision=vision)
    a.speed = speed
    return m, a
end

@testset "look!" begin
    @testset "near sites" begin
        m, a = disc_world()
        adjacent = [wrap(m, a.x + dx, a.y + dy) for (dx, dy) in VON_NEUMANN]
        ok = true
        for _ in 1:200
            sites = look!(m, a)
            ok &= all(s -> s in sites, adjacent) && (a.x, a.y) == first(sites)
        end
        @test ok
    end

    @testset "a speed widens the near disc" begin
        m, a = disc_world(; side=31, vision=10, speed=3)
        near_sites = [wrap(m, a.x + dx, a.y + dy) for (dx, dy) in disc_offsets(3.0)]
        @test all(s -> s in look!(m, a), near_sites)
    end

    @testset "no duplicates" begin
        m, a = disc_world(; side=41, vision=20)
        ok = true
        for _ in 1:500
            sites = look!(m, a)
            ok &= length(sites) == length(unique(sites))
        end
        @test ok
    end

    @testset "ring only in range" begin
        for speed in (0, 3)
            m, a = disc_world(; side=41, vision=18, speed=speed)
            n = speed == 0 ? 1.0 : Float64(speed)
            near_set = Set(wrap(m, a.x + dx, a.y + dy) for (dx, dy) in disc_offsets(n))
            push!(near_set, (a.x, a.y))
            ok, ring_seen = true, 0
            for _ in 1:300
                for s in look!(m, a)
                    s in near_set && continue
                    d = torus_dist(41, 41, a.x, a.y, s[1], s[2])
                    ok &= n < d <= 18
                    ring_seen += 1
                end
            end
            @test ok
            @test ring_seen > 0
            # Each look draws ring_draws(V) points, so it holds at most that many beyond the near disc.
            @test length(look!(m, a)) <= length(near_set) + ring_draws(18)
        end
    end

    @testset "the lattice look is on the axes" begin
        m = tiny_model(zeros(Int, 21, 21); vision=(5, 5))   # book rules: lattice vision
        a = put_agent(m, 10, 10; vision=5)
        sites = look!(m, a)
        @test first(sites) == (10, 10)
        @test length(sites) == 1 + 4 * 5
        @test all(s -> s[1] == 10 || s[2] == 10, sites)
    end
end

# Where a move of (dx, dy) falls among the 8 octants [kπ/4, (k+1)π/4), counting a move on an axis or diagonal half to
# each neighbouring octant. Adds into `counts`.
function count_octant!(counts, dx, dy)
    if dx == 0 || dy == 0 || abs(dx) == abs(dy)
        θ = atan(dy, dx)
        k = round(Int, θ / (π / 4))   # the boundary lies on a multiple of π/4
        counts[mod(k - 1, 8) + 1] += 0.5   # the octant below the boundary
        counts[mod(k, 8) + 1] += 0.5   # and above it
    else
        θ = mod(atan(dy, dx), 2π)
        counts[floor(Int, θ / (π / 4)) + 1] += 1
    end
    return counts
end

# Runs `periods` periods and returns the displacements (dx, dy) of every move longer than one site.
function long_moves(m, periods)
    w, h = m.config.width, m.config.height
    moves = Tuple{Int,Int}[]
    for _ in 1:periods
        before = Dict(a => (a.x, a.y) for a in m.agents)
        step!(m)
        for a in m.agents
            haskey(before, a) || continue
            x0, y0 = before[a]
            dx, dy = torus_delta(w, x0, a.x), torus_delta(h, y0, a.y)
            dx * dx + dy * dy > 1 && push!(moves, (dx, dy))
        end
    end
    return moves
end

@testset "isotropy" begin
    side = 200
    cap = rand(Xoshiro(7), 0:4, side, side)
    kw = (
        vision=(30, 30),
        metabolism=(1, 1),
        endowment=(1000, 1000),
        initial_population=2000,
        seed=7,
    )
    @testset "disc vision has no preferred direction" begin
        m = tiny_model(cap; xxl=DISC, kw...)
        moves = long_moves(m, 20)
        @test length(moves) > 5_000
        # The octant count alone passes a lattice look (axis moves fall evenly across the octants), so the moves must
        # also leave the axes.
        @test count(mv -> mv[1] != 0 && mv[2] != 0, moves) > length(moves) ÷ 2
        counts = zeros(8)
        foreach(mv -> count_octant!(counts, mv...), moves)
        expected = length(moves) / 8
        chi2 = sum((counts .- expected) .^ 2 ./ expected)
        @test chi2 < 24.3   # 7 degrees of freedom, p = 0.001
    end
    @testset "lattice vision stays on the axes" begin
        m = tiny_model(cap; kw...)   # book rules
        moves = long_moves(m, 5)
        @test length(moves) > 1_000
        @test all(mv -> mv[1] == 0 || mv[2] == 0, moves)
    end
end

@testset "xxl_move!" begin
    @testset "goes to the best adjacent site and harvests it" begin
        cap = zeros(Int, 9, 9)
        cap[4, 3] = 4   # the site east of the agent (the sites are 0-based, the matrix 1-based)
        m = tiny_model(cap; xxl=DISC)
        a = put_agent(m, 2, 2; vision=3, sugar=0.0)
        a.sugar = 0.0
        a.moved_dist = 99.0
        a.target_remembered = true
        move!(m, a)
        @test (a.x, a.y) == (3, 2)
        @test a.moved
        @test a.moved_dist == 1.0
        @test !a.target_remembered
        @test a.sugar == 4.0
        @test a.last_income == 4.0
        @test m.landscape.sugar[4, 3] == 0.0
    end

    @testset "stays when its own site is best" begin
        cap = zeros(Int, 9, 9)
        cap[3, 3] = 4
        m = tiny_model(cap; xxl=DISC)
        a = put_agent(m, 2, 2; vision=3)
        a.sugar = 0.0
        move!(m, a)
        @test (a.x, a.y) == (2, 2)
        @test !a.moved
        @test a.moved_dist == 0.0
        @test a.sugar == 4.0
    end

    @testset "ties go to the nearest site" begin
        cap = zeros(Int, 21, 21)
        for x in (12, 13, 14)
            cap[x + 1, 11] = 4   # three equal sites, 2, 3 and 4 east of (10, 10)
        end
        m = tiny_model(cap; xxl=DISC)
        a = put_agent(m, 10, 10; vision=5)
        a.speed = 5   # all three lie in the near disc, so each is looked at
        move!(m, a)
        @test (a.x, a.y) == (12, 10)
    end

    @testset "an occupied site is not a candidate" begin
        cap = zeros(Int, 9, 9)
        cap[4, 3] = 4
        cap[5, 3] = 4
        m = tiny_model(cap; xxl=DISC)
        a = put_agent(m, 2, 2; vision=3)
        a.speed = 3
        put_agent(m, 3, 2)   # sits on the nearer of the two
        move!(m, a)
        @test (a.x, a.y) == (4, 2)
    end
end

@testset "partners after moving" begin
    m, a = disc_world(; side=21, vision=5, speed=3)
    move_agent!(m, a, 5, 10)   # the agent has moved; its look starts from here
    d = put_agent(m, 5, 13)   # 3 away
    c = put_agent(m, 7, 10)   # 2 away
    b = put_agent(m, 5, 9)   # 1 away
    @test disc_in_sight(m, a) == [b, c, d]
    @test in_sight(m, a) == [b, c, d]
    @test !(a in in_sight(m, a))
    # A site next to the new position (and 6 from the old one) is always in the near disc.
    e = put_agent(m, 4, 11)
    ok = true
    for _ in 1:50
        ok &= e in disc_in_sight(m, a)
    end
    @test ok
end
