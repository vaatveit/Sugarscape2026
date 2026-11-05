# xxl (stage 5b): the meeting's price, rule 14 (docs/superpowers/specs/2026-11-05-xxl-meeting-price-design.md, "Part 1").
# With trade_price = "meeting", `bargain!` sets the price once, at the start of a meeting, and trades every unit at it
# under the book's tests; off, it is the book's rule T, the price set afresh at each unit.
using Sugarscape, Test
using Sugarscape: welfare_rises, run_extinction
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

# A 5 x 5 market, Rule 14 at `trade_price` (nothing: the book's price); `xxl=false` gives a config with no xxl rules.
function meeting_market(trade_price; rounding="exact", xxl=true)
    rules = xxl ? replace_rules(XXL_BOOK; trade_price=trade_price) : nothing
    return tiny_model(ones(Int, 5, 5); spice=true, trade=true, trade_rounding=rounding, xxl=rules)
end

function meeting_trader(m, x, y, sugar, spice, m1, m2)
    a = put_agent(m, x, y; sugar=sugar, metabolism=m1)
    a.spice, a.spice_metabolism = spice, m2
    return a
end

# The pair: MRSs 6 and 0.06, so the meeting's price is 0.6; the book trades 14 units, the meeting 11.
meeting_pair(m) = (meeting_trader(m, 1, 1, 10.0, 30.0, 4, 2), meeting_trader(m, 1, 2, 25.0, 6.0, 1, 4))

@testset "xxl meeting price" begin
    @testset "every unit of a meeting trades at its starting price" begin
        m = meeting_market("meeting")
        a, b = meeting_pair(m)
        p = sqrt(mrs(a) * mrs(b))
        bargain!(m, a, b)
        @test length(m.trade_log) == 11
        @test all(e -> e.price == p, m.trade_log)
        @test all(e -> e.a === a && e.b === b, m.trade_log)  # a, the higher MRS, buys sugar throughout
        @test a.last_price == b.last_price == p
    end

    @testset "the meeting stops at the first unit that would not raise both welfares" begin
        m = meeting_market("meeting")
        a, b = meeting_pair(m)
        p = sqrt(mrs(a) * mrs(b))
        bargain!(m, a, b)
        sugar, spice = 1.0 / p, 1.0  # p < 1: 1/p sugar for 1 spice
        s1, p1, s2, p2 = a.sugar + sugar, a.spice - spice, b.sugar - sugar, b.spice + spice
        @test min(s1, p1, s2, p2) > 0  # not the holdings
        @test !(welfare_rises(a, s1, p1, a.sugar, a.spice, false) && welfare_rises(b, s2, p2, b.sugar, b.spice, false))
        bargain!(m, a, b)  # a second meeting at the new MRSs trades again, at its own price
        @test length(m.trade_log) > 11 && m.trade_log[12].price != p
    end

    @testset "the book's rule on the same pair: other prices, other units" begin
        logs = map((true, false)) do xxl
            m = meeting_market(nothing; xxl=xxl)
            bargain!(m, meeting_pair(m)...)
            m.trade_log
        end
        book = logs[1]
        @test length(book) == 14
        @test length(unique(e.price for e in book)) == 14
        @test book[1].price == 0.6 && book[end].price > book[1].price
        @test [(e.price, e.sugar, e.spice) for e in logs[2]] == [(e.price, e.sugar, e.spice) for e in book]  # no xxl rules
    end

    @testset "a meeting whose first unit fails logs nothing" begin
        for tp in ("meeting", nothing)
            m = meeting_market(tp)
            a, b = meeting_trader(m, 1, 1, 10.0, 10.2, 1, 1), meeting_trader(m, 1, 2, 10.0, 10.0, 1, 1)
            @test mrs(a) != mrs(b)
            bargain!(m, a, b)
            @test isempty(m.trade_log)
            @test (a.sugar, a.spice, b.sugar, b.spice) == (10.0, 10.2, 10.0, 10.0)
            @test isnan(a.last_price) && isnan(b.last_price)
        end
    end

    @testset "rounded down: whole units of at least 1" begin
        m = meeting_market("meeting"; rounding="down")
        a, b = meeting_pair(m)
        p = sqrt(mrs(a) * mrs(b))
        bargain!(m, a, b)
        @test !isempty(m.trade_log)
        @test all(e -> e.price == p && isinteger(e.sugar) && isinteger(e.spice), m.trade_log)
        @test all(e -> e.sugar >= 1 && e.spice >= 1, m.trade_log)
    end

    @testset "VI-1: off gives today's bytes; on, and with Rule 13, runs" begin
        vi1 = find_experiment(load_registry(), "VI-1")
        kw = (label="mp", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1)
        name = Sugarscape.extinction_name("mp", 20, 1, 12)
        a, b = mktempdir(), mktempdir()
        run_extinction(XXL_DEFAULTS; kw..., out=a)
        run_extinction(replace_rules(XXL_DEFAULTS; trade_price=nothing); kw..., out=b)
        @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
        on, both = mktempdir(), mktempdir()
        @test run_extinction(replace_rules(XXL_DEFAULTS; trade_price="meeting"); kw..., out=on) !== nothing
        @test isfile(joinpath(on, name, "seed20.csv"))
        @test run_extinction(
            replace_rules(XXL_DEFAULTS; trade_price="meeting", trade_move="local"); kw..., out=both
        ) !== nothing
        @test isfile(joinpath(both, name, "seed20.csv"))
    end
end
