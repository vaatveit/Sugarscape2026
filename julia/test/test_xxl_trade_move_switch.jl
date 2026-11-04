# xxl (stage 5): the trade-move switch, rule 13 (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 2").
# Three XxlRules settings, trade_move, trade_blend and trade_guard, choose how an agent under trade scores a site.
# This file tests the switch only: the settings, their refusals, the reset and the fingerprint. At nothing the
# rules and every run's bytes are the book's.
using Sugarscape, Test
using Sugarscape: run_extinction

@testset "xxl trade move: the switch" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    ii4 = find_experiment(reg, "II-4")
    TM = (; trade_move="local", trade_blend=0.5, trade_guard=5)

    @testset "trade move: book settings change nothing" begin
        @test XXL_BOOK.trade_move === nothing &&
            XXL_V1.trade_move === nothing &&
            XXL_DEFAULTS.trade_move === nothing
        @test XXL_BOOK.trade_blend == 1.0 && XXL_DEFAULTS.trade_blend == 1.0
        @test XXL_BOOK.trade_guard === nothing && XXL_DEFAULTS.trade_guard === nothing
        @test Sugarscape.rules_line(XXL_DEFAULTS) ==
            "vision_shape=\"disc\" speed=(1, 6) travel_cost=0.2 memory=8 memory_span=50 word_of_mouth=true " *
              "interaction_radius=1.5 season_gradient=true landscape=\"generated\" founder_placement=\"viable\" " *
              "free_step=1.5 disease_count=3 founder_diseases=1 disease_lengths=(9, 10)"
        @test !occursin("trade_move", Sugarscape.xxl_fingerprint(vi1, XXL_DEFAULTS))
        @test !xxl_on(to_xxl(vi1.config, XXL_DEFAULTS), :trade_move)
    end

    @testset "trade move: each setting reaches the config" begin
        c = to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; TM...))
        @test c.xxl.trade_move == "local" && c.xxl.trade_blend == 0.5 && c.xxl.trade_guard == 5
        @test xxl_on(c, :trade_move)
        own = to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; trade_move="own"))
        @test own.xxl.trade_move == "own" && own.xxl.trade_blend == 1.0 && own.xxl.trade_guard === nothing
        @test xxl_on(own, :trade_move)
    end

    @testset "trade move: the fingerprint names a setting when it's on" begin
        @test endswith(
            Sugarscape.rules_line(replace_rules(XXL_DEFAULTS; trade_move="local", trade_guard=5)),
            "disease_lengths=(9, 10) trade_move=\"local\" trade_guard=5",
        )
        @test occursin("trade_blend=0.5", Sugarscape.rules_line(replace_rules(XXL_DEFAULTS; TM...)))
        @test occursin("trade_move=\"local\"", Sugarscape.xxl_fingerprint(vi1, replace_rules(XXL_DEFAULTS; TM...)))
        @test replace_rules(XXL_DEFAULTS; TM...) != XXL_DEFAULTS
        @test hash(replace_rules(XXL_DEFAULTS; TM...)) != hash(XXL_DEFAULTS)
    end

    @testset "trade move: refusals" begin
        for bad in (
            (; trade_move="market"),
            (; trade_move="own", trade_blend=-0.1),
            (; trade_move="own", trade_blend=1.5),
            (; trade_move="own", trade_blend=NaN),
            (; trade_move="own", trade_guard=-1),
            (; trade_blend=0.5),  # no trade_move to blend
            (; trade_guard=5),  # no trade_move to guard
        )
            @test_throws ArgumentError to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; bad...))
        end
    end

    @testset "trade move: an experiment without trade resets them" begin
        c = to_xxl(ii4.config, replace_rules(XXL_DEFAULTS; trade_move="own", trade_guard=5))
        @test !c.trade
        @test c.xxl.trade_move === nothing && c.xxl.trade_blend == 1.0 && c.xxl.trade_guard === nothing
        @test !xxl_on(c, :trade_move)
        @test Sugarscape.xxl_fingerprint(ii4, replace_rules(XXL_DEFAULTS; trade_move="own", trade_guard=5)) ==
            Sugarscape.xxl_fingerprint(ii4, XXL_DEFAULTS)
        d = to_xxl(ii4.config, replace_rules(XXL_DEFAULTS; trade_move="local", trade_blend=0.5))
        @test d.xxl.trade_blend == 1.0
    end

    @testset "trade move: rules that skip to_xxl are refused" begin
        R0 = replace_rules(XXL_V1; season_gradient=false)
        @test !to_xl(ii4.config).trade
        @test_throws ArgumentError replace_config(to_xl(ii4.config); xxl=replace_rules(R0; trade_move="own"))
        @test_throws ArgumentError replace_config(to_xl(vi1.config); xxl=replace_rules(R0; trade_blend=0.5))
        @test replace_config(to_xl(vi1.config); xxl=replace_rules(R0; trade_move="own")).xxl.trade_move == "own"
    end

    @testset "trade move: --set reads the settings" begin
        @test Sugarscape.rule_setting("trade_move=local") == (:trade_move => "local")
        @test Sugarscape.rule_setting("trade_move=own") == (:trade_move => "own")
        @test Sugarscape.rule_setting("trade_move=nothing") == (:trade_move => nothing)
        @test Sugarscape.rule_setting("trade_guard=5") == (:trade_guard => 5)
        @test Sugarscape.rule_setting("trade_guard=nothing") == (:trade_guard => nothing)
        @test Sugarscape.rule_setting("trade_blend=0.5") == (:trade_blend => 0.5)
    end

    @testset "trade move: naming it off gives the same bytes" begin
        a, b = mktempdir(), mktempdir()
        kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1)
        run_extinction(XXL_DEFAULTS; kw..., out=a)
        run_extinction(replace_rules(XXL_DEFAULTS; trade_move=nothing); kw..., out=b)
        name = Sugarscape.extinction_name("t", 20, 1, 12)
        @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
    end
end
