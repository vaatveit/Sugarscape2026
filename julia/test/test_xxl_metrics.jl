# xxl: the nine added metrics (spec, "Metrics"): movement, clustering, regional prices, memory and the winter weight.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test

col(m, name) = collect_metrics(m)[findfirst(==(name), metric_columns(m.config))]

# Plants an exchange at price `exp(logp)` whose first agent sits at (x, y).
function plant!(m, x, y, logp)
    a = put_agent(m, x, y)
    b = put_agent(m, x, y + 1)
    push!(m.trade_log, Sugarscape.Exchange(exp(logp), 1.0, exp(logp), a, b))
    return a
end

@testset "xxl metrics" begin
    @testset "columns" begin
        @test XXL_METRIC_COLUMNS == [
            "mean_moved",
            "share_settled",
            "clustering_1",
            "clustering_10",
            "clustering_50",
            "regional_price_sd",
            "price_distance_slope",
            "share_remembered_target",
            "mean_winter_weight",
        ]
        m = tiny_model(ones(Int, 12, 12); xxl=XXL_BOOK)
        put_agent(m, 3, 3)
        @test length(collect_metrics(m)) == length(metric_columns(m.config)) == 54
        @test metric_columns(m.config) == vcat(METRIC_COLUMNS, XXL_METRIC_COLUMNS)
        r = tiny_model(ones(Int, 12, 12))
        put_agent(r, 3, 3)
        @test metric_columns(r.config) === METRIC_COLUMNS
        @test length(collect_metrics(r)) == length(METRIC_COLUMNS)
        ii4 = Model(find_experiment(load_registry(), "II-4").config)
        @test length(collect_metrics(ii4)) == length(METRIC_COLUMNS) == 45
    end

    @testset "empty and single" begin
        for n in 0:1
            m = tiny_model(ones(Int, 60, 60); xxl=XXL_BOOK)
            n == 1 && put_agent(m, 5, 5)
            for name in ("clustering_1", "clustering_10", "clustering_50")
                @test isnan(col(m, name))
            end
            @test isnan(col(m, "mean_moved")) == (n == 0)
            @test isnan(col(m, "share_settled")) == (n == 0)
            @test isnan(col(m, "regional_price_sd"))
            @test isnan(col(m, "price_distance_slope"))
            @test isnan(col(m, "share_remembered_target"))
            @test isnan(col(m, "mean_winter_weight"))
        end
    end

    @testset "movement" begin
        m = tiny_model(ones(Int, 12, 12); xxl=XXL_BOOK)
        a, b, c = put_agent(m, 1, 1), put_agent(m, 5, 5), put_agent(m, 9, 9)
        a.moved, a.moved_dist = true, 3.0
        b.moved, b.moved_dist = true, 1.0
        @test col(m, "mean_moved") ≈ 4 / 3
        @test col(m, "share_settled") ≈ 1 / 3
    end

    @testset "memory and winter weight" begin
        rules = XxlRules(; speed=(1, 1), memory=2)
        m = tiny_model(ones(Int, 20, 20); xxl=rules, seasons=(2, 10))
        a, b = put_agent(m, 1, 5), put_agent(m, 1, 10)
        a.target_remembered = true
        @test col(m, "share_remembered_target") == 0.5
        # y = 5 of 20 is a quarter of the way round: weight 1; y = 10 is the pole: weight 0
        @test col(m, "mean_winter_weight") ≈ 0.5
    end

    @testset "clustering" begin
        n = 110
        m = tiny_model(ones(Int, n, n); xxl=XXL_BOOK)
        for x in 0:(n - 1), y in 0:(n - 1)
            put_agent(m, x, y)
        end
        # agents on every site match the sites exactly: ratio 1 in every shell
        for name in ("clustering_1", "clustering_10", "clustering_50")
            @test col(m, name) ≈ 1.0 rtol = 1e-9
        end
        @test length(m.shell_shares) == 3

        # tight pairs: lots of unit-distance pairs, far fewer than a random scatter would give elsewhere
        m = tiny_model(ones(Int, 200, 200); xxl=XXL_BOOK)
        for k in 1:40
            x, y = 4 * k, 4 * k
            put_agent(m, x, y)
            put_agent(m, x + 1, y)
        end
        @test col(m, "clustering_1") > 20
        @test col(m, "clustering_10") < col(m, "clustering_1")
        # the share is cached and the metric repeatable
        @test col(m, "clustering_1") == col(m, "clustering_1")

        # only capacity >= 1 sites count towards P_r: a half-empty landscape gives the same ratio for a full half
        cap = zeros(Int, 60, 60)
        cap[1:30, :] .= 1
        m = tiny_model(cap; xxl=XXL_BOOK)
        for x in 0:29, y in 0:59
            put_agent(m, x, y)
        end
        @test col(m, "clustering_1") ≈ 1.0 rtol = 1e-9
    end

    @testset "regions" begin
        m = tiny_model(zeros(Int, 100, 50); xxl=XXL_BOOK)
        plant!(m, 10, 10, 0.0)
        plant!(m, 12, 10, 0.0)
        plant!(m, 60, 10, 2.0)
        @test col(m, "regional_price_sd") ≈ 1.0
        # a single region with trades has sd 0
        m = tiny_model(zeros(Int, 100, 50); xxl=XXL_BOOK)
        plant!(m, 10, 10, 0.0)
        plant!(m, 12, 10, 1.0)
        @test col(m, "regional_price_sd") == 0.0
    end

    @testset "slope" begin
        m = tiny_model(zeros(Int, 200, 50); xxl=XXL_BOOK)
        for x in (5, 9, 20, 41, 70)
            plant!(m, x, 10, 0.01 * x)
        end
        @test col(m, "price_distance_slope") ≈ 0.01
        # a single exchange, or two (one pair, so no spread in distance): undefined
        m = tiny_model(zeros(Int, 200, 50); xxl=XXL_BOOK)
        plant!(m, 5, 10, 0.0)
        @test isnan(col(m, "price_distance_slope"))
        plant!(m, 5, 20, 1.0)
        @test isnan(col(m, "price_distance_slope"))
    end
end
