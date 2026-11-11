# The xxl viewer's run (julia/viewer/run.jl): its settings, and that a run steps as the combat study steps a seed.
isdefined(@__MODULE__, :XxlViewer) || include(joinpath(@__DIR__, "..", "viewer", "XxlViewer.jl"))
using Sugarscape, Test
using .XxlViewer
using Sugarscape: run_combat_world, world_config, JULIA_COMBAT_EXPS, metric_columns, pollution_path

const VW_STEPS = 12

vw_base(id) = world_config(JULIA_COMBAT_EXPS[id](), "today").seed

# The columns of a study CSV by name, as Float64 (a nan field is NaN).
function vw_csv(path)
    lines = readlines(path)
    names = split(lines[1], ",")
    cols = Dict(n => Float64[] for n in names)
    for line in lines[2:end]
        for (n, v) in zip(names, split(line, ","))
            push!(cols[n], parse(Float64, v))
        end
    end
    return cols
end

@testset "viewer settings" begin
    @test VIEWER_EXPS == ["VI-1-combat", "VI-1-distance", "VI-1-near", "VI-1-far", "VI-1-far-speed", "VI-1-assim",
        "VI-1-assim-random", "VI-1-assim-k4", "VI-1-pollution", "VI-1-pollution-t0"]
    @test DEFAULT_EXP == "VI-1-assim-k4"
    s = viewer_defaults("VI-1-assim-k4")
    @test s.h == 0.5
    @test s.k == 4.0
    @test s.seed == vw_base("VI-1-assim-k4")
    exp = JULIA_COMBAT_EXPS["VI-1-assim-k4"]()
    @test run_index(ViewerSettings(s.exp_id, s.seed + 3, s.h, s.k)) == 3
    @test run_index(ViewerSettings(s.exp_id, s.seed - 1, s.h, s.k)) === nothing
    @test run_index(ViewerSettings(s.exp_id, s.seed + exp.seeds, s.h, s.k)) === nothing
    cfg = viewer_config(ViewerSettings("VI-1-assim-k4", 12345, 0.3, 2.0))
    @test cfg.seed == 12345
    @test cfg.combat_hostility == 0.3
    @test cfg.combat_curve == 2.0
    @test cfg.culture_rule == "distance"
    @test_throws ArgumentError viewer_config(ViewerSettings("VI-1-assim", 1, 1.0, 1.0))
    @test_throws ArgumentError viewer_config(ViewerSettings("VI-9-nothing", 1, 0.5, 1.0))
    @test_throws ArgumentError viewer_defaults("VI-9-nothing")
end

@testset "viewer run" begin
    id = "VI-1-assim-k4"
    folder = run_combat_world("today", id; seeds=1, first_seed=1, periods=VW_STEPS, out=mktempdir(), io=devnull)
    combat = vw_csv(joinpath(folder, "seed1-combat.csv"))
    std = vw_csv(joinpath(folder, "seed1.csv"))
    s = viewer_defaults(id)
    r = ViewerRun(ViewerSettings(id, s.seed + 1, s.h, s.k))
    for _ in 1:VW_STEPS
        @test advance!(r)
    end
    @test length(r.series["t"]) == VW_STEPS + 1

    @testset "matches the study" begin
        @test r.series["t"] == collect(0.0:VW_STEPS)
        for key in ("population", "n_blue", "n_red", "killed_blue", "killed_red", "tribe_changes")
            @test all(isequal.(r.series[key], combat[key]))
        end
        for key in ("gini", "trades", "mean_price", "n_loans", "fraction_sick")
            @test all(isequal.(r.series[key], std[key]))
        end
        @test sum(r.series["killed_blue"]) + sum(r.series["killed_red"]) >= 1
        @test length(r.metric_rows) == VW_STEPS + 1
        cols = metric_columns(r.model.config)
        @test [row[findfirst(==("n_loans"), cols)] for row in r.metric_rows] == r.series["n_loans"]
    end

    @testset "total debt" begin
        due = sum(l.due for l in r.model.loans; init=0.0)
        @test total_debt(r.model) == due
        @test r.series["total_debt"][end] == due
    end

    @testset "series since" begin
        tail = series_since(r, 10)
        @test sort(collect(keys(tail))) == sort(SERIES_KEYS)
        @test tail["t"] == [10.0, 11.0, 12.0]
        @test tail["population"] == r.series["population"][11:13]
    end

    @testset "series keys" begin
        @test series_keys(r.model.config) == SERIES_KEYS
        @test sort(collect(keys(r.series))) == sort(SERIES_KEYS)
    end
end

@testset "pollution run matches the study" begin
    id = "VI-1-pollution-t0"
    folder = run_combat_world("today", id; seeds=1, first_seed=1, periods=VW_STEPS, out=mktempdir(), io=devnull)
    combat = vw_csv(joinpath(folder, "seed1-combat.csv"))
    std = vw_csv(joinpath(folder, "seed1.csv"))
    pollution = vw_csv(pollution_path(folder, 1))
    s = viewer_defaults(id)
    r = ViewerRun(ViewerSettings(id, s.seed + 1, s.h, s.k))
    for _ in 1:VW_STEPS
        @test advance!(r)
    end
    @test POLLUTION_SERIES == ["mean_pollution", "agent_pollution", "share_rich"]
    @test series_keys(r.model.config) == vcat(SERIES_KEYS, POLLUTION_SERIES)
    @test sort(collect(keys(r.series))) == sort(series_keys(r.model.config))
    @test r.series["t"] == collect(0.0:VW_STEPS)
    @test pollution["t"] == r.series["t"]
    for key in POLLUTION_SERIES
        @test all(isequal.(r.series[key], pollution[key]))
    end
    @test r.series["mean_pollution"][end] > 0
    for key in ("population", "n_blue", "n_red", "killed_blue", "killed_red", "tribe_changes")
        @test all(isequal.(r.series[key], combat[key]))
    end
    for key in ("gini", "trades", "mean_price", "n_loans", "fraction_sick")
        @test all(isequal.(r.series[key], std[key]))
    end
    tail = series_since(r, 10)
    @test sort(collect(keys(tail))) == sort(series_keys(r.model.config))
    @test tail["share_rich"] == r.series["share_rich"][11:13]
end

@testset "viewer run stops at extinction" begin
    id = "VI-1-assim-k4"
    s = viewer_defaults(id)
    r = ViewerRun(ViewerSettings(id, s.seed, s.h, s.k))
    empty!(r.model.agents)
    t = r.model.t
    @test advance!(r) == false
    @test r.model.t == t
    @test length(r.series["t"]) == 1
end
