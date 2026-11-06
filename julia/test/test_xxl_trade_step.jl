# xxl (stage 5c): the trade step, rule 15 (docs/superpowers/specs/2026-11-05-xxl-trade-step-design.md, "Part 1").
# With trade_step below 1, every exchange of `bargain!` moves that share of the book's unit at its price; the meeting
# goes on until a step fails the book's tests. At 1 it is the book's rule T.
using Sugarscape, Test
using Sugarscape: run_extinction
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

# A 5 x 5 market with the trade step (and Rule 14, when `trade_price` is given).
function step_market(step; trade_price=nothing)
    rules = replace_rules(XXL_BOOK; trade_step=step, trade_price=trade_price)
    return tiny_model(ones(Int, 5, 5); spice=true, trade=true, trade_rounding="exact", xxl=rules)
end

function step_trader(m, x, y, sugar, spice, m1, m2)
    a = put_agent(m, x, y; sugar=sugar, metabolism=m1)
    a.spice, a.spice_metabolism = spice, m2
    return a
end

# The pair of the meeting-price tests: MRSs 6 and 0.06; a buys sugar. The second pair is its mirror: p > 1.
step_pair(m) = (step_trader(m, 1, 1, 10.0, 30.0, 4, 2), step_trader(m, 1, 2, 25.0, 6.0, 1, 4))
rich_pair(m) = (step_trader(m, 1, 1, 30.0, 10.0, 2, 4), step_trader(m, 1, 2, 6.0, 25.0, 4, 1))

@testset "xxl trade step" begin
    @testset "each exchange moves a tenth of the book's unit at its price" begin
        # under Rule 14 the price stays on one side of 1 (the book's price drifts across it within a meeting)
        m = step_market(0.1; trade_price="meeting")
        a, b = step_pair(m)
        bargain!(m, a, b)
        @test !isempty(m.trade_log)
        @test all(e -> e.price < 1 && isapprox(e.spice, 0.1) && isapprox(e.sugar, 0.1 / e.price), m.trade_log)
        m = step_market(0.1; trade_price="meeting")
        a, b = rich_pair(m)
        @test mrs(a) < mrs(b) && sqrt(mrs(a) * mrs(b)) > 1
        bargain!(m, b, a)
        @test !isempty(m.trade_log)
        @test all(e -> e.price > 1 && isapprox(e.sugar, 0.1) && isapprox(e.spice, 0.1 * e.price), m.trade_log)
    end

    @testset "the meeting takes more steps and moves at least as much sugar" begin
        logs = map((1.0, 0.1)) do step
            m = step_market(step)
            bargain!(m, step_pair(m)...)
            m.trade_log
        end
        @test all(logs[2]) do e  # the book's price drifts across 1 within a meeting: judge each entry by its own price
            e.price > 1 ? isapprox(e.sugar, 0.1) && isapprox(e.spice, 0.1 * e.price) :
            e.price < 1 ? isapprox(e.spice, 0.1) && isapprox(e.sugar, 0.1 / e.price) :
            isapprox(e.sugar, 0.1) && isapprox(e.spice, 0.1)
        end
        @test any(e -> e.price < 1, logs[2]) && any(e -> e.price > 1, logs[2])
        @test length(logs[2]) > length(logs[1])
        @test sum(e.sugar for e in logs[2]) >= sum(e.sugar for e in logs[1])
        @test length(logs[2]) < 10_000
    end

    @testset "with Rule 14, every step has the meeting's starting price" begin
        m = step_market(0.1; trade_price="meeting")
        a, b = step_pair(m)
        p = sqrt(mrs(a) * mrs(b))
        bargain!(m, a, b)
        @test length(m.trade_log) > 11
        @test length(m.trade_log) < 10_000
        @test all(e -> e.price == p && isapprox(e.spice, 0.1) && e.a === a, m.trade_log)
    end

    @testset "VI-1: step 1 gives today's bytes; 0.1 runs, alone and with Rule 14" begin
        vi1 = find_experiment(load_registry(), "VI-1")
        kw = (label="ts", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1)
        name = Sugarscape.extinction_name("ts", 20, 1, 12)
        a, b = mktempdir(), mktempdir()
        run_extinction(XXL_DEFAULTS; kw..., out=a)
        run_extinction(replace_rules(XXL_DEFAULTS; trade_step=1.0); kw..., out=b)
        @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
        for rules in (replace_rules(XXL_DEFAULTS; trade_step=0.1),
                      replace_rules(XXL_DEFAULTS; trade_step=0.1, trade_price="meeting"))
            out = mktempdir()
            @test run_extinction(rules; kw..., out=out) !== nothing
            @test isfile(joinpath(out, name, "seed20.csv"))
        end
    end
end
