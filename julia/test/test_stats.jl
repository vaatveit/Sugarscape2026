# Ports tests/test_stats.py, test_society_metrics.py, test_economic_metrics.py and test_disease_metrics.py. Tribes
# are made by setting tags by hand (tribal blocks arrive with the Chapter III rules).
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

metrics(m) = Dict(zip(METRIC_COLUMNS, collect_metrics(m)))

@testset "metric columns" begin
    @test METRIC_COLUMNS == [
        "population",
        "mean_vision",
        "mean_metabolism",
        "mean_sugar",
        "gini",
        "mean_neighbors",
        "moved",
        "ne_fraction",
        "on_peak_fraction",
        "north_frac_high_vision",
        "north_frac_low_vision",
        "summer_north",
        "n_blue",
        "n_red",
        "blue_fraction",
        "sw_blue",
        "sw_red",
        "ne_blue",
        "ne_red",
        "blue_xy",
        "red_xy",
        "blue_advance",
        "red_advance",
        "mean_children",
        "best_friend_closeness",
        "friend_closeness",
        "agents_ever",
        "mean_spice",
        "trades",
        "mean_price",
        "mean_log_price",
        "price_sd",
        "sugar_traded",
        "spice_traded",
        "mean_foresight",
        "n_loans",
        "n_lenders",
        "n_borrowers",
        "n_both",
        "credit_depth",
        "mean_diseases",
        "sd_diseases",
        "fraction_sick",
        "new_infections",
        "diseases_circulating",
    ]
    @test length(collect_metrics(Model(Config(; seed=2)))) == 45
end

@testset "test_gini_known_values" begin
    @test gini([5, 5, 5, 5]) == 0.0
    @test gini([0, 0, 0, 1]) ≈ 0.75
    @test isapprox(gini(5:25), 20 / 90; atol=0.02)  # U[5,25] ≈ 0.23 (p.37)
    @test isnan(gini(Float64[])) && isnan(gini([0.0, 0.0]))
end

@testset "test_empty_population_gives_nan_not_error" begin
    out = metrics(tiny_model(ones(Int, 3, 3)))
    @test out["population"] == 0 && isnan(out["gini"])
end

@testset "test_empty_model_steps_and_measures" begin  # Review Focus 1
    m = Model(replace_config(Config(); initial_population=0))
    for _ in 1:3
        step!(m)
    end
    out = metrics(m)
    @test out["population"] == 0.0 && out["n_blue"] == 0.0 && out["mean_children"] == 0.0
    @test out["agents_ever"] == 0.0 && out["trades"] == 0.0 && out["new_infections"] == 0.0
    @test all(
        isnan(out[k]) for
        k in ("mean_vision", "gini", "mean_spice", "mean_diseases", "sd_diseases")
    )
end

@testset "test_spatial_fractions" begin
    m = tiny_model(fill(3, 6, 6))
    put_agent(m, 4, 4)  # NE quadrant
    put_agent(m, 1, 1)  # SW quadrant
    out = metrics(m)
    @test out["ne_fraction"] == 0.5 && out["on_peak_fraction"] == 1.0
    @test isnan(out["summer_north"])  # no seasons configured
end

@testset "vision groups and seasons" begin
    m = tiny_model(fill(3, 10, 10); vision=(1, 4), seasons=(8, 50))
    put_agent(m, 0, 7; vision=4)  # north (y >= 5)
    put_agent(m, 1, 1; vision=1)  # south
    put_agent(m, 2, 8; vision=2)  # north
    out = metrics(m)
    @test isnan(out["north_frac_high_vision"]) && out["north_frac_low_vision"] == 0.5
    @test out["summer_north"] == 1.0 && out["mean_vision"] ≈ 7 / 3
end

@testset "test_tribeless_population_gives_zero_counts_and_nan" begin
    out = metrics(Model(Config(; seed=2)))
    @test out["n_blue"] == out["n_red"] == 0.0 &&
        isnan(out["blue_fraction"]) &&
        isnan(out["blue_xy"])
    @test isnan(out["best_friend_closeness"]) && out["mean_children"] == 0.0
end

@testset "test_one_tribe_extinct" begin
    m = tiny_model(ones(Int, 50, 50); tag_length=11)
    for i in 0:4
        tag!(put_agent(m, i, i), zeros(Int, 11))  # blue, south-west of the anti-diagonal
    end
    out = metrics(m)
    @test out["blue_fraction"] == 1.0 && out["n_red"] == 0.0 && isnan(out["red_xy"])
    @test out["sw_blue"] == 5.0 && out["ne_blue"] == 0.0 && out["blue_xy"] == 4.0
end

@testset "test_empty_population" begin
    m = Model(Config(; initial_population=0))
    @test all(v == 0.0 || isnan(v) for v in collect_metrics(m))
end

@testset "test_friend_closeness_uses_current_tags_of_living_friends" begin
    m = Model(Config(; initial_population=0, tag_length=3))
    a = tag!(new_agent!(m, 0, 0, 1, 1, 10.0), [0, 0, 0])
    near, far = loose(0, 0, 0), loose(1, 1, 0)
    a.friends = [(near, 0), (far, 2)]
    out = metrics(m)
    @test out["best_friend_closeness"] == 1.0 && out["friend_closeness"] ≈ (1.0 + 1 / 3) / 2
    near.alive = false
    @test metrics(m)["best_friend_closeness"] ≈ 1 / 3
end

@testset "test_advance_is_toroidal_displacement" begin
    m = Model(Config(; initial_population=0, tag_length=1))
    a = tag!(new_agent!(m, 0, 5, 1, 1, 10.0), [0])
    move_agent!(m, a, 49, 5)
    move_agent!(m, a, 49, 6)
    @test (a.disp_x, a.disp_y) == (-1, 1)
    out = metrics(m)
    @test out["blue_advance"] == 0.0 && isnan(out["red_advance"])
end

@testset "test_agents_ever_counts_the_dead" begin
    m = Model(Config(; initial_population=0))
    agents = [new_agent!(m, i, 0, 1, 1, 10.0) for i in 0:2]
    kill!(m, agents[1])
    @test metrics(m)["agents_ever"] == 3.0
end

@testset "mean children" begin
    m = Model(Config(; initial_population=0))
    a, b = new_agent!(m, 0, 0, 1, 1, 10.0), new_agent!(m, 1, 0, 1, 1, 10.0)
    push!(a.children, b, loose(0))
    @test metrics(m)["mean_children"] == 1.0
end

@testset "test_no_trades_gives_nan" begin
    out = metrics(Model(Config(; seed=1)))
    @test out["trades"] == 0.0 && isnan(out["mean_price"]) && isnan(out["price_sd"])
    @test isnan(out["mean_log_price"]) && out["credit_depth"] == 0.0
end

@testset "test_price_statistics" begin
    m = Model(Config(; initial_population=0, spice=true))
    x = loose(0)
    append!(m.trade_log, [Exchange(2.0, 1.0, 2.0, x, x), Exchange(0.5, 2.0, 1.0, x, x)])
    out = metrics(m)
    @test isapprox(out["mean_price"], 1.0) &&
        isapprox(out["mean_log_price"], 0.0; atol=1e-15)
    @test out["price_sd"] ≈ log(2) && out["trades"] == 2.0
    @test (out["sugar_traded"], out["spice_traded"]) == (3.0, 3.0)
    pop!(m.trade_log)
    @test metrics(m)["price_sd"] == 0.0
end

@testset "test_credit_structure" begin
    m = Model(Config(; initial_population=0, sex=true, credit=(10, 10.0)))
    a, b, c = (new_agent!(m, i, 0, 1, 1, 10.0) for i in 0:2)
    append!(m.loans, [Loan(a, b, 1.0, 2.0, 10), Loan(b, c, 1.0, 2.0, 10)])
    out = metrics(m)
    @test (
        out["n_loans"],
        out["n_lenders"],
        out["n_borrowers"],
        out["n_both"],
        out["credit_depth"],
    ) == (2, 2, 2, 1, 2)
end

@testset "test_credit_depth_survives_cycles" begin
    m = Model(Config(; initial_population=0, sex=true, credit=(10, 10.0)))
    a, b = (new_agent!(m, i, 0, 1, 1, 10.0) for i in 0:1)
    append!(m.loans, [Loan(a, b, 1.0, 2.0, 10), Loan(b, a, 1.0, 2.0, 10)])
    @test metrics(m)["credit_depth"] == 1.0
end

@testset "test_gini_uses_total_wealth" begin
    m = Model(Config(; initial_population=0, spice=true))
    a = new_agent!(m, 0, 0, 1, 1, 10.0)
    a.spice = 0.0
    b = new_agent!(m, 1, 0, 1, 1, 0.0001)
    b.spice = 10.0
    @test isapprox(metrics(m)["gini"], 0.0; atol=1e-4)
end

@testset "test_disease_statistics" begin
    m = Model(Config(; initial_population=0))  # Python adds disease_list=3; the metric ignores the list
    for (i, ds) in enumerate(([1], [1, 2], Int[]))  # interned disease ids
        new_agent!(m, i, 0, 1, 1, 10.0).diseases = ds
    end
    out = metrics(m)
    @test out["mean_diseases"] == 1.0 && out["sd_diseases"] ≈ sqrt(2 / 3)
    @test out["fraction_sick"] ≈ 2 / 3 && out["diseases_circulating"] == 2.0
end

@testset "test_empty_population_is_nan_not_error (disease)" begin
    out = metrics(Model(Config(; initial_population=0)))
    @test isnan(out["mean_diseases"]) && isnan(out["fraction_sick"])
    @test out["new_infections"] == 0.0 && out["diseases_circulating"] == 0.0
end

@testset "tribe" begin
    @test tribe(loose(0, 0, 1)) == :blue && tribe(loose(1, 0, 1)) == :red
    @test tribe(Agent(1, 0, 0, 1, 1, 1.0)) == :none
end
