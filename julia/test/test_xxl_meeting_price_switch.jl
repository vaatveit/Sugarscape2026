# xxl (stage 5b): the meeting's price switch, rule 14 (docs/superpowers/specs/2026-11-05-xxl-meeting-price-design.md,
# "Part 1"). One XxlRules setting, trade_price, chooses how two neighbours price a meeting. This file tests the switch
# only: the setting, its refusals, the reset and the fingerprint. At nothing the rules and every run's bytes are the book's.
using Sugarscape, Test

@testset "xxl meeting price: the switch" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    ii4 = find_experiment(reg, "II-4")
    MP = replace_rules(XXL_DEFAULTS; trade_price="meeting")

    @testset "meeting price: book settings change nothing" begin
        @test XXL_BOOK.trade_price === nothing &&
            XXL_V1.trade_price === nothing &&
            XXL_DEFAULTS.trade_price === nothing
        @test !occursin("trade_price", Sugarscape.rules_line(XXL_DEFAULTS))
        @test !occursin("trade_price", Sugarscape.xxl_fingerprint(vi1, XXL_DEFAULTS))
        @test !xxl_on(to_xxl(vi1.config, XXL_DEFAULTS), :trade_price)
    end

    @testset "meeting price: the setting reaches the config" begin
        c = to_xxl(vi1.config, MP)
        @test c.xxl.trade_price == "meeting"
        @test xxl_on(c, :trade_price)
        @test c.xxl.trade_move === nothing
    end

    @testset "meeting price: the fingerprint names it when it's on" begin
        @test endswith(Sugarscape.rules_line(MP), "disease_lengths=(9, 10) trade_price=\"meeting\"")
        @test occursin("trade_price=\"meeting\"", Sugarscape.xxl_fingerprint(vi1, MP))
        @test MP != XXL_DEFAULTS
        @test hash(MP) != hash(XXL_DEFAULTS)
    end

    @testset "meeting price: refusals" begin
        @test_throws ArgumentError to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; trade_price="ask"))
    end

    @testset "meeting price: an experiment without trade resets it" begin
        c = to_xxl(ii4.config, MP)
        @test !c.trade
        @test c.xxl.trade_price === nothing
        @test !xxl_on(c, :trade_price)
        @test Sugarscape.xxl_fingerprint(ii4, MP) == Sugarscape.xxl_fingerprint(ii4, XXL_DEFAULTS)
    end

    @testset "meeting price: rules that skip to_xxl are refused" begin
        R0 = replace_rules(XXL_V1; season_gradient=false)
        @test !to_xl(ii4.config).trade
        @test_throws ArgumentError replace_config(to_xl(ii4.config); xxl=replace_rules(R0; trade_price="meeting"))
        @test replace_config(to_xl(vi1.config); xxl=replace_rules(R0; trade_price="meeting")).xxl.trade_price ==
            "meeting"
    end

    @testset "meeting price: --set reads the setting" begin
        @test Sugarscape.rule_setting("trade_price=meeting") == (:trade_price => "meeting")
        @test Sugarscape.rule_setting("trade_price=nothing") == (:trade_price => nothing)
    end
end
