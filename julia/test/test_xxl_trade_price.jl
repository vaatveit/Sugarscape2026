# xxl (stage 5): the expected price of rule 13 (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 2").
# `bargain!` records the price of every exchange: on the two agents (`last_price`) and, for trade_move = "local", at
# their sites. `expected_price` reads those records back for an agent about to move.
using Sugarscape, Test
using Sugarscape: expected_price, LOCAL_PRICE_PERIODS, run_extinction
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

# A 5 x 5 market under Rule 13 (`trade_move` "own" or "local"), or none.
function price_market(trade_move)
    rules = replace_rules(XXL_BOOK; trade_move=trade_move)
    return tiny_model(ones(Int, 5, 5); spice=true, trade=true, xxl=rules)
end

function price_trader(m, x, y, sugar, spice; m1=1, m2=1)
    a = put_agent(m, x, y; sugar=sugar)
    a.spice, a.metabolism, a.spice_metabolism = spice, m1, m2
    return a
end

@testset "xxl trade price" begin
    @testset "a fresh agent has no last price" begin
        m = price_market(nothing)
        @test isnan(price_trader(m, 1, 1, 5.0, 8.0).last_price)
        @test isnan(Agent(1, 0, 0, 1, 1, 10.0).last_price)
    end

    @testset "bargain! leaves each agent the last price" begin
        m = price_market(nothing)  # recorded always, Rule 13 or not
        a = price_trader(m, 1, 1, 5.0, 8.0)
        b = price_trader(m, 1, 2, 15.0, 2.0)
        bargain!(m, a, b)
        @test length(m.trade_log) == 2 && m.trade_log[1].price != m.trade_log[2].price
        @test a.last_price == m.trade_log[end].price && b.last_price == m.trade_log[end].price
        c = price_trader(m, 3, 3, 5.0, 8.0)  # no deal: nothing recorded
        d = price_trader(m, 3, 2, 5.0, 8.0)
        bargain!(m, c, d)
        @test isnan(c.last_price) && isnan(d.last_price)
    end

    @testset "the site records exist only for the local price" begin
        for tm in (nothing, "own")
            m = price_market(tm)
            @test size(m.site_price) == (0, 0) && size(m.site_price_t) == (0, 0)
        end
        m = price_market("local")
        @test size(m.site_price) == (5, 5) && size(m.site_price_t) == (5, 5)
        @test all(==(-1), m.site_price_t)
        a = price_trader(m, 1, 1, 5.0, 8.0)
        b = price_trader(m, 1, 2, 15.0, 2.0)
        m.t = 7
        bargain!(m, a, b)
        p = m.trade_log[end].price
        @test m.site_price[2, 2] == log(p) && m.site_price[2, 3] == log(p)  # the latest exchange wins
        @test m.site_price_t[2, 2] == 7 && m.site_price_t[2, 3] == 7
        @test count(==(7), m.site_price_t) == 2 && count(==(-1), m.site_price_t) == 23
        # off Rule 13 or at "own", bargain! has no record to write to
        for tm in (nothing, "own")
            n = price_market(tm)
            bargain!(n, price_trader(n, 1, 1, 5.0, 8.0), price_trader(n, 1, 2, 15.0, 2.0))
            @test size(n.site_price) == (0, 0)
        end
    end

    @testset "own: the last price, else the MRS, else nothing" begin
        m = price_market("own")
        a = price_trader(m, 2, 2, 5.0, 10.0)
        @test isnan(a.last_price)
        @test expected_price(m, a, m.looked) == mrs(a) == 2.0
        a.last_price = 1.7
        @test expected_price(m, a, m.looked) == 1.7
        a.last_price = NaN
        a.spice = 0.0  # MRS 0: no price
        @test isnan(expected_price(m, a, m.looked))
        a.spice, a.sugar = 4.0, 0.0  # MRS Inf: none either
        @test isnan(expected_price(m, a, m.looked))
        b = price_trader(m, 4, 4, 5.0, 10.0)
        b.last_price = 3.0
        b.spice = 0.0  # a price remembered beats a degenerate MRS
        @test expected_price(m, b, m.looked) == 3.0
    end

    @testset "own: the cultural flag reaches the MRS" begin
        rules = replace_rules(XXL_BOOK; trade_move="own")
        m = tiny_model(
            ones(Int, 5, 5); spice=true, trade=true, tag_length=3, culture=true, cultural_preferences=true, xxl=rules
        )
        a = price_trader(m, 2, 2, 10.0, 10.0)
        tag!(a, [0, 1, 1])  # f = 1/3
        @test mrs(a, true) != mrs(a, false)
        @test expected_price(m, a, m.looked) == mrs(a, true)
    end

    @testset "local: the geometric mean of the prices in sight and in date" begin
        m = price_market("local")
        m.t = 30
        a = price_trader(m, 2, 2, 5.0, 10.0)  # MRS 2
        looked = [(2, 2), (2, 3), (3, 2), (1, 2)]
        @test expected_price(m, a, looked) == mrs(a)  # nothing recorded: the MRS
        m.site_price[3, 4], m.site_price_t[3, 4] = log(4.0), 29  # (2, 3)
        m.site_price[4, 3], m.site_price_t[4, 3] = log(9.0), 25  # (3, 2)
        @test expected_price(m, a, looked) ≈ 6.0
        m.site_price[2, 3], m.site_price_t[2, 3] = log(1.0), 30 - LOCAL_PRICE_PERIODS  # (1, 2): ten periods old
        @test expected_price(m, a, looked) ≈ 6.0  # left out
        m.site_price_t[2, 3] = 30 - LOCAL_PRICE_PERIODS + 1  # nine periods old: in
        @test expected_price(m, a, looked) ≈ (4.0 * 9.0 * 1.0)^(1 / 3)
        m.site_price[3, 3], m.site_price_t[3, 3] = log(16.0), 30  # the agent's own site counts, once
        @test expected_price(m, a, looked) ≈ (4.0 * 9.0 * 1.0 * 16.0)^(1 / 4)
        @test expected_price(m, a, [(2, 3)]) ≈ (4.0 * 16.0)^(1 / 2)  # own site counts though not looked at
        @test expected_price(m, a, [(2, 2), (2, 2)]) ≈ 16.0  # the own site listed in looked counts once
        @test expected_price(m, a, Tuple{Int,Int}[]) ≈ 16.0
        @test expected_price(m, a, [(0, 0), (4, 4)]) ≈ 16.0  # sites of no record
    end

    @testset "local: no price in date gives the MRS, or none" begin
        m = price_market("local")
        m.t = 30
        a = price_trader(m, 2, 2, 5.0, 10.0)
        m.site_price[3, 3], m.site_price_t[3, 3] = log(16.0), 5  # long ago
        @test expected_price(m, a, [(2, 2)]) == mrs(a)
        a.spice = 0.0
        @test isnan(expected_price(m, a, [(2, 2)]))
    end

    @testset "a checkpoint keeps the site prices: a resumed run gives the same bytes" begin
        vi1 = find_experiment(load_registry(), "VI-1")
        rules = replace_rules(XXL_DEFAULTS; trade_move="local")
        kw = (label="tp", seeds=1, first_seed=20, periods=30, jobs=1, io=devnull, experiment=vi1, checkpoint_every=10)
        whole, broken = mktempdir(), mktempdir()
        run_extinction(rules; kw..., out=whole)
        @test run_extinction(rules; kw..., out=broken, stop_at=15) === nothing
        @test run_extinction(rules; kw..., out=broken) !== nothing
        name = Sugarscape.extinction_name("tp", 20, 1, 30)
        @test read(joinpath(broken, name, "seed20.csv")) == read(joinpath(whole, name, "seed20.csv"))
        # Nothing reads the prices yet, so the bytes alone can't show they were kept: compare the records themselves.
        m = Model(replace_config(to_xxl(vi1.config, rules); seed=20))
        for _ in 1:12
            step!(m)
        end
        @test count(>=(0), m.site_price_t) > 0 && any(a -> isfinite(a.last_price), m.agents)
        path = joinpath(mktempdir(), "seed.ckpt")
        Sugarscape.save_checkpoint(path, "tp", (; model=m); t=m.t)
        back = Sugarscape.load_checkpoint(path, "tp").model
        @test back.site_price == m.site_price && back.site_price_t == m.site_price_t
        @test isequal([a.last_price for a in back.agents], [a.last_price for a in m.agents])
    end
end
