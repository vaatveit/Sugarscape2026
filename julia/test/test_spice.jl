# Ports tests/test_spice.py, plus the paired-seed check for VI-2 and VI-3.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

@testset "test_spice_peaks_northwest_and_southeast" begin  # Fig IV-1
    m = Model(Config(; spice=true, initial_population=0))
    peaks = [
        (i - 1, j - 1) for i in 1:50, j in 1:50 if m.landscape.spice_capacity[i, j] == 4
    ]
    nw = [x < 25 && y >= 25 for (x, y) in peaks]
    se = [x >= 25 && y < 25 for (x, y) in peaks]
    @test any(nw) && any(se) && all(nw .| se)
    @test m.landscape.spice == Float64.(m.landscape.spice_capacity)
end

@testset "test_no_spice_layer_without_spice" begin
    m = Model(Config(; initial_population=0))
    @test sum(m.landscape.spice_capacity) == 0 && sum(m.landscape.spice) == 0
end

@testset "test_spice_grows_back_like_sugar" begin
    ls = Landscape([4 2], [3 1])
    ls.spice .= 0
    growback!(ls, 1.0)
    @test ls.spice == [1.0 1.0]
end

@testset "test_spice_seasons_follow_sugar" begin
    ls = Landscape(fill(4, 1, 2), fill(4, 1, 2))
    ls.sugar .= 0
    ls.spice .= 0
    seasonal_growback!(ls, 0, 1.0, 8, 50, "fractional")
    @test ls.spice == ls.sugar
end

@testset "test_spice_inherited" begin
    m = tiny_model(ones(Int, 5, 5); spice=true, inheritance=true)
    p = put_agent(m, 0, 0; sugar=10.0)
    p.spice = 30.0
    k = put_agent(m, 2, 2)
    k.spice = 5.0
    push!(p.children, k)
    die!(m, p)
    @test k.spice == 35.0
end

@testset "test_replacements_carry_spice" begin
    cfg = Config(;
        spice=true,
        initial_population=30,
        max_age=(1, 1),
        replacement=true,
        endowment=(25, 50),
    )
    m = Model(cfg)
    step!(m)
    @test length(m.agents) == 30
    @test all(25 <= a.spice <= 50 && 1 <= a.spice_metabolism <= 5 for a in m.agents)
end

@testset "test_vi2_vi3_start_identical" begin  # p.159: seed k of each starts from the identical society
    reg = load_registry()
    vi2, vi3 = find_experiment(reg, "VI-2").config, find_experiment(reg, "VI-3").config
    traits(a) = (
        a.id,
        a.x,
        a.y,
        a.vision,
        a.metabolism,
        a.sugar,
        a.spice,
        a.spice_metabolism,
        a.sex,
        a.fertility_start,
        a.fertility_end,
        a.max_age,
        a.age,
    )
    for k in 0:2
        a = Model(replace_config(vi2; seed=vi2.seed + k))
        b = Model(replace_config(vi3; seed=vi3.seed + k))
        @test sort(traits.(a.agents)) == sort(traits.(b.agents))
    end
end
