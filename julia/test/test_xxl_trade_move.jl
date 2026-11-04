# xxl (stage 5): rule 13, movement that counts on trade (docs/superpowers/specs/2026-11-03-xxl-trade-design.md,
# "Part 2"). With the rule on, a site scores W^(1-λ) V^λ: W the book's welfare of the bundle after the move, V = A + B / p
# its value in sugar at the expected price p. Uses `SiteWelfare(m, a, looked)`, `score`, `net_value`, the three moves
# and `remember!`.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: SiteWelfare, score, net_parts

# XXL_DEFAULTS as a hand-built world allows them (no seasons for the gradient, no disease list, the speed fixed at 3),
# with Rule 13 as `kw` says.
function trade_rules(; kw...)
    return replace_rules(
        XXL_DEFAULTS;
        season_gradient=false,
        landscape="xl",
        speed=(3, 3),
        disease_count=nothing,
        founder_diseases=nothing,
        disease_lengths=nothing,
        kw...,
    )
end

put_goods!(m, x, y, sugar, spice) = (m.landscape.sugar[x + 1, y + 1] = sugar; m.landscape.spice[x + 1, y + 1] = spice)

# One agent at (7, 7) with plenty of sugar and little spice, metabolisms 1 and 1, no foresight. Two empty sites at the
# same distance `d` in sight: S at (7 + d, 7), rich in sugar only, and P at (7, 7 + d), balanced. The book's welfare
# prefers P; at a price of 1 spice per sugar S is worth more.
function trade_world(rules; vision=3, speed=3, d=2, sugar=50.0, spice=2.0, last_price=NaN)
    m = tiny_model(zeros(Int, 15, 15); spice=true, trade=true, xxl=rules, vision=(vision, vision))
    a = put_agent(m, 7, 7; vision=vision, sugar=sugar)
    a.speed, a.spice, a.metabolism, a.spice_metabolism, a.foresight = speed, spice, 1, 1, 0
    a.last_price = last_price
    put_goods!(m, 7 + d, 7, 20.0, 0.0)
    put_goods!(m, 7, 7 + d, 6.0, 6.0)
    return m, a
end

const S_SITE, P_SITE = (9, 7), (7, 9)

@testset "xxl trade move" begin
    @testset "the speed move: S at the price, P by the book" begin
        m, a = trade_world(trade_rules())
        move!(m, a)
        @test (a.x, a.y) == P_SITE
        m, a = trade_world(trade_rules(; trade_move="own"); last_price=1.0)
        move!(m, a)
        @test (a.x, a.y) == S_SITE
        m, a = trade_world(trade_rules(; trade_move="own"))  # no last price: its MRS, 0.04, prices spice dear
        move!(m, a)
        @test (a.x, a.y) == P_SITE
    end

    @testset "the lattice move and the round look without speed" begin
        # move!'s own loop (neither round vision nor speed): S two east, P two north.
        m, a = trade_world(XxlRules(); vision=2, speed=0)
        move!(m, a)
        @test (a.x, a.y) == P_SITE
        m, a = trade_world(XxlRules(; trade_move="own"); vision=2, speed=0, last_price=1.0)
        move!(m, a)
        @test (a.x, a.y) == S_SITE
        # the local price there reads the agent's own site only: a cheap spice price at P's site doesn't count
        m, a = trade_world(XxlRules(; trade_move="local"); vision=2, speed=0)
        m.t = 3
        m.site_price[8, 8], m.site_price_t[8, 8] = log(1.0), 3
        m.site_price[8, 10], m.site_price_t[8, 10] = log(0.01), 3
        move!(m, a)
        @test (a.x, a.y) == S_SITE
        # xxl_move! (round vision, no speed): the four adjacent sites are always looked at.
        for (rules, expected) in ((XxlRules(; vision_shape="disc"), (7, 8)), (XxlRules(; vision_shape="disc", trade_move="own"), (8, 7)))
            m, a = trade_world(rules; vision=2, speed=0, d=1, last_price=1.0)
            move!(m, a)
            @test (a.x, a.y) == expected
        end
    end

    @testset "the guard sends a short agent to the book's choice" begin
        for (k, sugar, spice, guarded) in (
            (5, 50.0, 2.0, true),  # spice for fewer than 5 periods: P, where the rule alone would take S
            (5, 50.0, 6.0, false),  # enough of both
            (5, 50.0, 5.0, false),  # exactly 5 periods is enough
            (5, 4.0, 6.0, true),  # sugar for fewer than 5 periods
            (15, 50.0, 6.0, true),
        )
            m, a = trade_world(trade_rules(; trade_move="own", trade_guard=k); sugar, spice, last_price=1.0)
            book_m, book_a = trade_world(trade_rules(); sugar, spice)
            @test SiteWelfare(m, a, m.looked).lambda == (guarded ? 0.0 : 1.0)
            move!(m, a)
            move!(book_m, book_a)
            @test (a.x, a.y) == (guarded ? (book_a.x, book_a.y) : S_SITE)
            guarded && sugar == 50.0 && @test (a.x, a.y) == P_SITE
        end
    end

    @testset "no price: the book's rule, and nothing scores NaN" begin
        for tm in ("own", "local")
            m, a = trade_world(trade_rules(; trade_move=tm); spice=0.0)  # MRS 0, no exchange
            book_m, book_a = trade_world(trade_rules(); spice=0.0)
            looked = Sugarscape.look!(m, a)
            sw = SiteWelfare(m, a, looked)
            @test sw.lambda == 0.0
            values = [net_value(a, sw, true, 0.2, 1.5, Sugarscape.torus_dist(15, 15, 7, 7, x, y),
                                m.landscape.sugar[x + 1, y + 1], m.landscape.spice[x + 1, y + 1]) for (x, y) in looked]
            @test !any(isnan, values)
            move!(m, a)
            move!(book_m, book_a)
            @test (a.x, a.y) == (book_a.x, book_a.y)
            # on the lattice nothing starves on the way: the book's choice is P, and so is the rule's
            m, a = trade_world(XxlRules(; trade_move=tm); vision=2, speed=0, spice=0.0)
            @test !any(isnan, [score(SiteWelfare(m, a, Tuple{Int,Int}[]), m.landscape, i, j) for i in 1:15, j in 1:15])
            move!(m, a)
            @test (a.x, a.y) == P_SITE
        end
    end

    @testset "local in the first periods: a site with no exchange has no price" begin
        for t in (0, 3, 8)
            m, a = trade_world(trade_rules(; trade_move="local"))
            m.t = t
            @test Sugarscape.expected_price(m, a, Sugarscape.look!(m, a)) == mrs(a)
        end
    end

    @testset "the rule off, or a blend of 0: the book's welfare" begin
        m, a = trade_world(trade_rules(); last_price=1.0)
        @test SiteWelfare(m, a, m.looked) == SiteWelfare(m, a)
        m, a = trade_world(trade_rules(; trade_move="own", trade_blend=0.0); last_price=1.0)
        @test SiteWelfare(m, a, m.looked) == SiteWelfare(m, a)
        move!(m, a)
        @test (a.x, a.y) == P_SITE
    end

    @testset "the blend: sqrt(W V) at one half" begin
        m, a = trade_world(trade_rules(; trade_move="own", trade_blend=0.5); last_price=2.0)
        sw = SiteWelfare(m, a, m.looked)
        @test sw.lambda == 0.5 && sw.inv_p == 0.5
        for (d, sugar, spice) in ((2.0, 20.0, 0.0), (2.0, 6.0, 6.0), (0.0, 0.0, 0.0))
            trip = d <= 1.5 ? 0.0 : 0.2 * d
            A, B = 50.0 - trip + sugar, 2.0 + spice
            @test net_parts(a, sw, 1.0, 0.2, 1.5, d, sugar, spice) == (A, B)
            @test net_value(a, sw, true, 0.2, 1.5, d, sugar, spice) ≈ sqrt(sqrt(A * B) * (A + B * 0.5))
        end
        # the book's score (move! and xxl_move!): no travel, the empty site cached
        put_goods!(m, 3, 3, 0.0, 0.0)
        @test score(sw, m.landscape, 10, 8) ≈ sqrt(sqrt(70.0 * 2.0) * (70.0 + 2.0 * 0.5))
        @test score(sw, m.landscape, 4, 4) ≈ sqrt(sqrt(50.0 * 2.0) * (50.0 + 2.0 * 0.5))
    end

    @testset "starving on the way stays -Inf" begin
        m, a = trade_world(trade_rules(; trade_move="own", trade_blend=0.5); last_price=1.0)
        sw = SiteWelfare(m, a, m.looked)
        @test sw.lambda == 0.5
        @test net_value(a, sw, true, 0.2, 1.5, 10.0, 30.0, 30.0) == -Inf  # four periods: spice 2 runs out on the way
    end

    @testset "remembered sites are ranked at the move's price" begin
        # Beyond vision: S-like (sugar 20) 5 east, P-like (6, 6) 5 north; the own site empty.
        function remembering(rules)
            m = tiny_model(zeros(Int, 30, 30); spice=true, trade=true, xxl=rules, vision=(3, 3))
            a = put_agent(m, 10, 10; vision=3, sugar=50.0)
            a.speed, a.spice, a.metabolism, a.spice_metabolism, a.foresight = 3, 2.0, 1, 1, 0
            a.last_price = 1.0
            m.t = 5
            empty!(m.looked)
            a.memory = [Remembered(15, 10, 20.0, 0.0, 0.0, 4), Remembered(10, 15, 6.0, 6.0, 0.0, 4)]
            return m, a
        end
        m, a = remembering(trade_rules(; trade_move="own"))
        remember!(m, a)  # no price given: the book's ranking
        @test [(e.x, e.y) for e in a.memory] == [(10, 15), (10, 10), (15, 10)]
        m, a = remembering(trade_rules(; trade_move="own"))
        remember!(m, a; sw=SiteWelfare(m, a, m.looked))
        @test [(e.x, e.y) for e in a.memory] == [(15, 10), (10, 15), (10, 10)]

        # In a move: an occupied site Q (sugar 30) can't be the target but is remembered; after the move to S and its
        # harvest, the book would rank P first and the rule ranks Q first.
        m, a = trade_world(trade_rules(; trade_move="own"); last_price=1.0)
        put_goods!(m, 5, 7, 30.0, 0.0)
        put_agent(m, 5, 7)
        move!(m, a)
        @test (a.x, a.y) == S_SITE
        @test (a.memory[1].x, a.memory[1].y) == (5, 7)
    end

    @testset "the move keeps its blend and price for word of mouth" begin
        m, a = trade_world(trade_rules(; trade_move="own"); last_price=2.0)
        move!(m, a)
        @test (m.move_lambda, m.move_inv_p) == (1.0, 0.5)
        for rules in (trade_rules(), trade_rules(; trade_move="own", trade_guard=5))  # off, and guarded (spice 2)
            m, a = trade_world(rules; last_price=2.0)
            m.move_lambda, m.move_inv_p = 1.0, 0.5  # as another agent's move left them
            move!(m, a)
            @test (m.move_lambda, m.move_inv_p) == (0.0, 0.0)
        end
    end

    @testset "word of mouth ranks at the move's price" begin
        # Room for one entry. The agent at (10, 10) remembers S-like (sugar 20) 5 east; its neighbour's best is P-like
        # (6, 6) 5 north. From here, two periods away: S is (68, 2), P (54, 8). The book's welfare keeps P (√432 over
        # √136); at a price of 1, S is worth 70 against 62.
        function hearing(rules)
            m = tiny_model(zeros(Int, 30, 30); spice=true, trade=true, xxl=replace_rules(rules; memory=1), vision=(3, 3))
            a = put_agent(m, 10, 10; vision=3, sugar=50.0)
            a.speed, a.spice, a.metabolism, a.spice_metabolism, a.foresight = 3, 3.0, 1, 1, 0
            a.last_price = 1.0
            m.t = 5
            a.memory = [Remembered(15, 10, 20.0, 0.0, 0.0, 4)]
            b = put_agent(m, 25, 25)
            b.memory = [Remembered(10, 15, 6.0, 6.0, 0.0, 4)]
            a.neighbors = [b]
            return m, a
        end
        m, a = hearing(trade_rules(; trade_move="own"))
        sw = SiteWelfare(m, a, m.looked)
        @test sw.lambda == 1.0 && sw.inv_p == 1.0
        m.move_lambda, m.move_inv_p = sw.lambda, sw.inv_p  # as the agent's move this turn set them
        word_of_mouth!(m, a)
        @test [(e.x, e.y) for e in a.memory] == [(15, 10)]  # the rule's entry stays
        m, a = hearing(trade_rules(; trade_move="own"))  # the rule on, but the move set no price (guarded, say)
        word_of_mouth!(m, a)
        @test [(e.x, e.y) for e in a.memory] == [(10, 15)]
        m, a = hearing(trade_rules())  # the rule off: the book's best evicts it
        word_of_mouth!(m, a)
        @test [(e.x, e.y) for e in a.memory] == [(10, 15)]
    end
end
