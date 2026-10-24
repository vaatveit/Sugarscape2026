# Ports tests/test_trade.py.
using Sugarscape, Test
using Random: Xoshiro
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function trader(m, x, y, sugar, spice; m1=1, m2=1, tags=nothing)
    a = put_agent(m, x, y; sugar=sugar)
    a.spice, a.metabolism, a.spice_metabolism = spice, m1, m2
    tags === nothing || tag!(a, tags)
    return a
end

market(; kw...) = tiny_model(ones(Int, 5, 5); spice=true, trade=true, kw...)

function deals_of(m, a, b)
    n = length(m.trade_log)
    bargain!(m, a, b)
    return m.trade_log[(n + 1):end]
end

@testset "test_edgeworth_example_equal_metabolisms" begin  # Fig IV-2 endowments
    m = market()
    A = trader(m, 1, 1, 5.0, 8.0)
    B = trader(m, 1, 2, 15.0, 2.0)
    deals = deals_of(m, A, B)
    @test length(deals) == 2 && all(d.spice == 1.0 && d.price < 1 for d in deals)
    @test A.spice == 6.0 && isapprox(A.sugar, 9.2577; atol=1e-3)
    @test A.sugar + B.sugar ≈ 20.0 && A.spice + B.spice == 10.0
end

@testset "test_price_above_one_moves_p_spice_per_sugar" begin  # p.104
    m = market()
    A = trader(m, 1, 1, 2.0, 40.0)
    B = trader(m, 1, 2, 40.0, 10.0)
    d = deals_of(m, A, B)[1]
    @test d.price ≈ sqrt(5) && d.sugar == 1.0 && d.spice ≈ d.price
    @test d.a === A && d.b === B  # sugar moved to the higher-MRS agent
end

@testset "test_no_trade_when_mrs_equal_or_degenerate" begin
    m = market(; tag_length=3, cultural_preferences=true, culture=true)
    A = trader(m, 1, 1, 10.0, 10.0; tags=[0, 1, 0])
    B = trader(m, 1, 2, 10.0, 10.0; tags=[0, 1, 0])
    @test isempty(deals_of(m, A, B))
    C = trader(m, 1, 0, 10.0, 10.0; tags=[0, 0, 0])  # f = 1: MRS infinite
    @test isempty(deals_of(m, A, C)) && A.sugar == 10.0
    D = trader(m, 2, 1, 0.0, 10.0; tags=[0, 1, 1])  # no sugar
    @test isempty(deals_of(m, A, D))
end

@testset "test_random_pairs_conserve_and_improve" begin
    rng = Xoshiro(7)
    m = market()
    a = trader(m, 1, 1, 1.0, 1.0)
    b = trader(m, 1, 2, 1.0, 1.0)
    ok = true
    for _ in 1:500
        a.sugar, a.spice, b.sugar, b.spice = (1 .+ 99 .* rand(rng, 4))...
        a.metabolism, a.spice_metabolism, b.metabolism, b.spice_metabolism = rand(
            rng, 1:5, 4
        )
        totals = (a.sugar + b.sugar, a.spice + b.spice)
        before = (welfare(a, a.sugar, a.spice), welfare(b, b.sugar, b.spice))
        order = mrs(a) > mrs(b)
        deals = deals_of(m, a, b)
        ok &=
            isapprox(a.sugar + b.sugar, totals[1]) && isapprox(a.spice + b.spice, totals[2])
        if !isempty(deals)
            ok &=
                welfare(a, a.sugar, a.spice) > before[1] &&
                welfare(b, b.sugar, b.spice) > before[2]
            ok &= (mrs(a) > mrs(b)) == order || mrs(a) == mrs(b)
        end
        ok &= min(a.sugar, a.spice, b.sugar, b.spice) > 0
    end
    @test ok
end

@testset "test_trade_runs_in_the_turn_and_logs" begin
    cfg = Config(;
        spice=true,
        trade=true,
        initial_population=200,
        metabolism=(1, 5),
        vision=(1, 5),
        endowment=(25, 50),
        seed=3,
    )
    m = Model(cfg)
    total = 0
    ok = true
    for _ in 1:20
        step!(m)
        total += length(m.trade_log)
        ok &= all(d.sugar > 0 && d.spice > 0 && d.price > 0 for d in m.trade_log)
    end
    @test ok && total > 0
    @test all(a.sugar > 0 && a.spice > 0 for a in m.agents)
end

@testset "test_no_trade_log_without_trade" begin
    m = Model(Config(; spice=true, initial_population=50))
    step!(m)
    @test isempty(m.trade_log)
end

@testset "test_integer_trade_variant_moves_whole_units_at_price_p" begin
    m = market(; trade_rounding="down")
    A = trader(m, 1, 1, 2.0, 40.0)
    B = trader(m, 1, 2, 40.0, 10.0)
    d = deals_of(m, A, B)[1]
    @test d.price ≈ sqrt(5) && (d.sugar, d.spice) == (1.0, 2.0)
end

@testset "test_integer_trade_variant_rounds_sugar_below_price_one" begin
    m = market(; trade_rounding="down")
    A = trader(m, 1, 1, 5.0, 8.0)
    B = trader(m, 1, 2, 15.0, 2.0)
    deals = deals_of(m, A, B)  # 1/p = 2.17, 2.08, then 2.03 would cross the MRSs
    @test [(d.sugar, d.spice) for d in deals] == [(2.0, 1.0), (2.0, 1.0)]
    @test (A.sugar, A.spice, B.sugar, B.spice) == (9.0, 6.0, 11.0, 4.0)
end
