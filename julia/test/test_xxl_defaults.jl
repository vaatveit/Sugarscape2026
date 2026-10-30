# xxl (revised): the stage-1 defaults the scorecard chose (docs/superpowers/specs/2026-10-29-xxl-revised-design.md,
# "Tuning protocol"; docs/xxl.md, "Stage 1: the scorecard and survival"): XXL_V1 with the generated map, the free step
# 1.5, viable founder placement and a travel cost of 0.2; the metabolism cap and young founders stay at their book
# settings.
using Sugarscape, Test

@testset "xxl stage-1 defaults" begin
    reg = load_registry()
    tiny = find_experiment(reg, "TEST-tiny")

    @testset "the chosen values" begin
        @test XXL_DEFAULTS == replace_rules(
            XXL_V1;
            landscape="generated",
            free_step=1.5,
            founder_placement="viable",
            travel_cost=0.2,
        )
        @test XXL_DEFAULTS.landscape == "generated"
        @test XXL_DEFAULTS.free_step == 1.5
        @test XXL_DEFAULTS.founder_placement == "viable"
        @test XXL_DEFAULTS.travel_cost == 0.2
        # not chosen: at their book settings
        @test XXL_DEFAULTS.max_metabolism === nothing
        @test XXL_DEFAULTS.founder_ages == "book"
        # the rest of the first rules, unchanged
        @test XXL_DEFAULTS.vision_shape == "disc"
        @test XXL_DEFAULTS.speed == (1, 6)
        @test XXL_DEFAULTS.memory == 8 && XXL_DEFAULTS.memory_span == 50
        @test XXL_DEFAULTS.word_of_mouth
        @test XXL_DEFAULTS.interaction_radius == 1.5
        @test XXL_DEFAULTS.season_gradient
        # and the first rules themselves are left alone
        @test XXL_V1.landscape == "xl" && XXL_V1.travel_cost == 0.1
        @test XXL_V1.free_step == 0.0 && XXL_V1.founder_placement == "random"
    end

    @testset "the default map is the generated one" begin
        ii4 = find_experiment(reg, "II-4")
        c = to_xxl(ii4.config)  # the defaults
        @test c.sugar_map == "sugar-map-xxl.txt"
        @test c.xxl == replace_rules(XXL_DEFAULTS; season_gradient=false)  # II-4 has no seasons
        @test xxl_on(c, :generated) && xxl_on(c, :viable) && xxl_on(c, :free_step)
        @test !xxl_on(c, :metabolism_cap) && !xxl_on(c, :young)
        @test to_xxl(ii4.config, XXL_V1).sugar_map == "sugar-map-xl.txt"
        iva3 = find_experiment(reg, "IV-A3")
        fp = Sugarscape.xxl_fingerprint(iva3, XXL_DEFAULTS)
        @test occursin("\nxxl map sugar-map-xxl.txt sha256=", fp)
        @test occursin("\nxxl map spice-map-xxl.txt sha256=", fp)  # IV-A3 has spice
    end

    @testset "the --xxl fingerprint of the new defaults" begin
        prefix =
            "julia\nxxl vision_shape=\"disc\" speed=(1, 6) travel_cost=0.2 memory=8 memory_span=50 " *
            "word_of_mouth=true interaction_radius=1.5 season_gradient=false landscape=\"generated\" " *
            "founder_placement=\"viable\" free_step=1.5\n"
        @test startswith(Sugarscape.xxl_fingerprint(tiny, XXL_DEFAULTS), prefix)
        out = mktempdir()
        @test Sugarscape.main(["TEST-tiny", "--xxl", "--seeds", "1", "--out", out]) == 0
        fp = read(joinpath(out, "TEST-tiny", "fingerprint.txt"), String)
        @test startswith(fp, prefix)
        @test occursin("\nxxl map sugar-map-xxl.txt sha256=", fp)
        @test !occursin("spice-map-xxl.txt", fp)  # TEST-tiny has no spice
    end
end
