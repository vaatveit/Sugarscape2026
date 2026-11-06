# xxl (stage 5c): the trade step switch, rule 15 (docs/superpowers/specs/2026-11-05-xxl-trade-step-design.md,
# "Part 1"). One XxlRules setting, trade_step, the share of the book's unit a step trades. This file tests the switch
# only: the setting, its refusals, the reset and the fingerprint. At 1 the rules and every run's bytes are the book's.
using Sugarscape, Test

@testset "xxl trade step: the switch" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    ii4 = find_experiment(reg, "II-4")
    TS = replace_rules(XXL_DEFAULTS; trade_step=0.1)

    @testset "trade step: book settings change nothing" begin
        @test XXL_BOOK.trade_step == 1.0 && XXL_V1.trade_step == 1.0 && XXL_DEFAULTS.trade_step == 1.0
        @test !occursin("trade_step", Sugarscape.rules_line(XXL_DEFAULTS))
        @test !occursin("trade_step", Sugarscape.xxl_fingerprint(vi1, XXL_DEFAULTS))
        @test !xxl_on(to_xxl(vi1.config, XXL_DEFAULTS), :trade_step)
    end

    @testset "trade step: the setting reaches the config" begin
        c = to_xxl(vi1.config, TS)
        @test c.xxl.trade_step == 0.1
        @test xxl_on(c, :trade_step)
        @test c.xxl.trade_price === nothing
    end

    @testset "trade step: the fingerprint names it when it's on" begin
        @test endswith(Sugarscape.rules_line(TS), "disease_lengths=(9, 10) trade_step=0.1")
        both = replace_rules(XXL_DEFAULTS; trade_price="meeting", trade_step=0.1)
        @test endswith(Sugarscape.rules_line(both), "trade_price=\"meeting\" trade_step=0.1")
        @test occursin("trade_step=0.1", Sugarscape.xxl_fingerprint(vi1, TS))
        @test TS != XXL_DEFAULTS
        @test hash(TS) != hash(XXL_DEFAULTS)
    end

    @testset "trade step: refusals" begin
        for s in (0.0, -0.1, 1.5, NaN, Inf)
            @test_throws ArgumentError to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; trade_step=s))
        end
        down = replace_config(vi1.config; trade_rounding="down")
        @test_throws ArgumentError to_xxl(down, TS)
        @test to_xxl(down, XXL_DEFAULTS).xxl.trade_step == 1.0
    end

    @testset "trade step: an experiment without trade resets it" begin
        c = to_xxl(ii4.config, TS)
        @test !c.trade
        @test c.xxl.trade_step == 1.0
        @test !xxl_on(c, :trade_step)
        @test Sugarscape.xxl_fingerprint(ii4, TS) == Sugarscape.xxl_fingerprint(ii4, XXL_DEFAULTS)
    end

    @testset "trade step: rules that skip to_xxl are refused" begin
        R0 = replace_rules(XXL_V1; season_gradient=false)
        @test !to_xl(ii4.config).trade
        @test_throws ArgumentError replace_config(to_xl(ii4.config); xxl=replace_rules(R0; trade_step=0.1))
        @test replace_config(to_xl(vi1.config); xxl=replace_rules(R0; trade_step=0.1)).xxl.trade_step == 0.1
    end

    @testset "trade step: --set reads the setting" begin
        @test Sugarscape.rule_setting("trade_step=0.1") == (:trade_step => 0.1)
    end
end
