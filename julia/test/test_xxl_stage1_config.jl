# xxl (revised): the stage-1 switches as XxlRules fields, their validation and the rules line
# (docs/superpowers/specs/2026-10-29-xxl-revised-design.md, "The changes").
using Sugarscape, Test

@testset "xxl stage-1 switches: fields, validation, rules line" begin
    reg = load_registry()
    ii4 = find_experiment(reg, "II-4")
    vi1 = find_experiment(reg, "VI-1")
    x = to_xl(ii4.config)
    R0 = replace_rules(XXL_V1; season_gradient=false)  # XXL_V1 as II-4 can run it: it has no seasons
    v1_line =
        "vision_shape=\"disc\" speed=(1, 6) travel_cost=0.1 memory=8 memory_span=50 " *
        "word_of_mouth=true interaction_radius=1.5 season_gradient=true landscape=\"xl\""

    @testset "the new fields default to the book's settings" begin
        r = XxlRules()
        @test r.max_metabolism === nothing
        @test r.founder_placement == "random"
        @test r.free_step == 0.0
        @test r.founder_ages == "book"
        @test Sugarscape.FOUNDER_PLACEMENTS == ("random", "viable")
        @test Sugarscape.XXL_FOUNDER_AGES == ("book", "young")
        @test XXL_V1.max_metabolism === nothing && XXL_V1.free_step == 0.0
    end

    @testset "equality and hash cover the new fields" begin
        for kw in (
            (; max_metabolism=4),
            (; founder_placement="viable"),
            (; free_step=1.5),
            (; founder_ages="young"),
        )
            r = replace_rules(XXL_V1; kw...)
            @test r != XXL_V1
            @test hash(r) != hash(XXL_V1)
            @test r == replace_rules(XXL_V1; kw...)
            @test hash(r) == hash(replace_rules(XXL_V1; kw...))
        end
    end

    @testset "the rules line names a new field only off its book setting" begin
        @test Sugarscape.rules_line(XXL_V1) == v1_line
        @test Sugarscape.rules_line(XXL_BOOK) ==
            "vision_shape=\"lattice\" speed=nothing travel_cost=0.0 memory=0 memory_span=50 " *
              "word_of_mouth=false interaction_radius=1.0 season_gradient=false landscape=\"xl\""
        @test Sugarscape.rules_line(replace_rules(XXL_V1; free_step=1.5)) ==
            v1_line * " free_step=1.5"
        @test Sugarscape.rules_line(
            replace_rules(
                XXL_V1;
                max_metabolism=4,
                founder_placement="viable",
                free_step=1.5,
                founder_ages="young",
            ),
        ) ==
            v1_line *
              " max_metabolism=4 founder_placement=\"viable\" free_step=1.5 founder_ages=\"young\""
    end

    @testset "the xxl_on features are true off the book setting" begin
        for (feature, kw) in (
            (:metabolism_cap, (; max_metabolism=4)),
            (:viable, (; founder_placement="viable")),
            (:free_step, (; free_step=1.5)),
            (:young, (; founder_ages="young")),
        )
            @test !xxl_on(replace_config(x; xxl=XXL_BOOK), feature)
            @test !xxl_on(x, feature)  # no xxl rules at all
            @test xxl_on(replace_config(x; xxl=replace_rules(R0; kw...)), feature)
            @test !xxl_on(replace_config(x; xxl=R0), feature)
        end
    end

    @testset "validation refuses what makes no sense" begin
        for bad in (
            replace_rules(R0; max_metabolism=0),
            replace_rules(R0; max_metabolism=-1),
            replace_rules(R0; founder_placement="near"),
            replace_rules(R0; free_step=-1.0),
            replace_rules(XXL_BOOK; free_step=1.5),  # free_step needs speed
            replace_rules(R0; founder_ages="old"),
        )
            @test_throws ArgumentError replace_config(x; xxl=bad)
        end
        # the cap may not fall below the lowest metabolism an agent can be drawn with
        low = replace_config(x; metabolism=(3, 4))
        @test_throws ArgumentError replace_config(
            low; xxl=replace_rules(R0; max_metabolism=2)
        )
        @test replace_config(low; xxl=replace_rules(R0; max_metabolism=3)).xxl.max_metabolism ==
            3
        spiced = replace_config(x; spice=true, spice_metabolism=(3, 5))
        @test_throws ArgumentError replace_config(
            spiced; xxl=replace_rules(R0; max_metabolism=2)
        )
        @test replace_config(spiced; xxl=replace_rules(R0; max_metabolism=3)).xxl.max_metabolism ==
            3
        # valid settings pass
        ok = replace_rules(
            R0;
            max_metabolism=4,
            founder_placement="viable",
            free_step=1.5,
            founder_ages="young",
        )
        @test replace_config(x; xxl=ok).xxl == ok
    end

    @testset "to_xxl resets founder_ages = young where it has nothing to do" begin
        young = replace_rules(R0; founder_ages="young")
        c = to_xxl(ii4.config, young)  # II-4: no sex, no finite lives
        @test c.xxl.founder_ages == "book"
        @test Sugarscape.rules_line(c.xxl) ==
            Sugarscape.rules_line(to_xxl(ii4.config, R0).xxl)
        @test Sugarscape.xxl_fingerprint(ii4, young) == Sugarscape.xxl_fingerprint(ii4, R0)
        @test !xxl_on(c, :young)
        # VI-1 has sex and finite lives: the setting is kept
        @test vi1.config.sex && vi1.config.max_age !== nothing
        k = to_xxl(vi1.config, young)
        @test k.xxl.founder_ages == "young" && xxl_on(k, :young)
        @test occursin("founder_ages=\"young\"", Sugarscape.rules_line(k.xxl))
        # sex without finite lives, and finite lives without sex, are reset too
        @test to_xxl(replace_config(ii4.config; sex=true), young).xxl.founder_ages == "book"
        @test to_xxl(replace_config(ii4.config; max_age=(60, 100)), young).xxl.founder_ages ==
            "book"
    end
end
