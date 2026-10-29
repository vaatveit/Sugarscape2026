# xxl: the rule set's configuration, its validation and the to_xxl transform (docs/superpowers/specs/2026-10-28-xxl-design.md).
using Sugarscape, Test

@testset "XxlRules" begin
    @test XXL_BOOK == XxlRules()
    @test XXL_DEFAULTS.speed == (1, 6) &&
        XXL_DEFAULTS.memory == 8 &&
        XXL_DEFAULTS.vision_shape == "disc"
    @test Config().xxl === nothing
    reg = load_registry()
    ii4 = find_experiment(reg, "II-4")
    c = to_xxl(ii4.config)
    @test c.xxl == replace_rules(XXL_DEFAULTS; season_gradient=false)  # II-4 has no seasons
    @test c.width == 500 && c.sugar_map == "sugar-map-xl.txt"
    @test to_xxl(find_experiment(reg, "II-7").config).xxl.season_gradient
    @test replace_config(c; xxl=nothing) == to_xl(ii4.config)
    @test to_xxl(ii4.config, XxlRules(; landscape="generated")).sugar_map ==
        "sugar-map-xxl.txt"
    @test to_xxl(find_experiment(reg, "III-9").config).combat_alpha == Inf  # combat is supported
    @test_throws ArgumentError to_xxl(to_xl(ii4.config))                     # to_xl refuses
    x = to_xl(ii4.config)
    for bad in (
        XxlRules(; memory=4),                          # memory needs speed
        XxlRules(; speed=(0, 3)),
        XxlRules(; travel_cost=-0.1),
        XxlRules(; interaction_radius=0.5),
        XxlRules(; memory=-1, speed=(1, 2)),
        XxlRules(; memory_span=0),
        XxlRules(; vision_shape="square"),
        XxlRules(; landscape="moon"),
        XxlRules(; travel_cost=0.1),                   # travel cost needs speed
        XxlRules(; speed=(1, 2), word_of_mouth=true),   # word of mouth needs memory
        XxlRules(; landscape="generated"),              # generated needs the xxl sugar map
        XxlRules(; season_gradient=true),               # II-4 has no seasons
        XxlRules(; speed=(1, 20)),
    )                      # speed above II-4's lowest xl vision, 10
        @test_throws ArgumentError replace_config(x; xxl=bad)
    end
    @test_throws ArgumentError replace_config(
        x; xxl=XxlRules(; vision_shape="disc"), vision=(10, 250)
    )  # 2V >= W
    @test replace_config(x; xxl=XxlRules(; vision_shape="disc"), vision=(10, 240)).vision ==
        (10, 240)
    s = to_xl(find_experiment(reg, "II-7").config)
    pulse = replace_config(s; winter_growback="pulse")
    @test_throws ArgumentError replace_config(pulse; xxl=XxlRules(; season_gradient=true))
    @test xxl_on(c, :disc) &&
        !xxl_on(x, :disc) &&
        !xxl_on(replace_config(x; xxl=XXL_BOOK), :speed)
end
