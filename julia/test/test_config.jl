# Ports tests/test_config.py. Invalid configs raise ArgumentError (Python: ValueError).
using Sugarscape, Test

rejects(; kw...) = @test_throws ArgumentError validate(Config(; kw...))

@testset "test_defaults_match_chapter_two" begin
    c = Config()
    @test (c.width, c.height, c.initial_population) == (50, 50, 400)
    @test c.vision == (1, 6) && c.metabolism == (1, 4)
    @test validate(c) === c
end

@testset "test_inverted_range_rejected" begin
    for field in (:vision, :metabolism, :endowment, :max_age)
        rejects(; (field => (5, 2),)...)
    end
end

@testset "test_vision_that_wraps_rejected" begin
    rejects(; vision=(1, 25))  # 25 * 2 >= 50
    @test validate(Config(; vision=(1, 20))).vision == (1, 20)
end

@testset "test_replacement_requires_max_age" begin
    rejects(; replacement=true)
end

@testset "test_unknown_placement_rejected" begin
    rejects(; placement="ring")
end

@testset "test_invalid_values_rejected_early" begin
    rejects(; seasons=(8, 0))
    rejects(; seasons=(0, 50))
    rejects(; diffusion_period=0)
    rejects(; growback_rate=-1.0)
    rejects(; initial_population=-1)
    rejects(; pollution=(-1.0, 1.0))
    rejects(; placement="block", block=(0, 0, 60, 60))
    rejects(; placement="block", block=(0, 0, 0, 5))
    rejects(; winter_growback="sometimes")
    rejects(; diffusion_passes=0)
    rejects(; diffusion_passes=-1)
end

@testset "test_winter_growback_defaults_to_fractional" begin
    @test Config().winter_growback == "fractional"
end

@testset "test_chapter3_defaults_are_off" begin
    c = Config()
    @test !(c.sex || c.inheritance || c.culture) &&
        c.combat_alpha === nothing &&
        c.tag_length == 0
end

@testset "test_chapter3_invalid_values_rejected" begin
    rejects(; tag_length=10)
    rejects(; tag_length=-1)
    rejects(; culture=true)
    rejects(; combat_alpha=2.0)
    rejects(; tag_length=11, combat_alpha=-1.0)
    rejects(; female_fertility_end=(50, 40))
    rejects(; tag_length=11, initial_blocks=[("green", 0, 0, 5, 5, 10)])
    rejects(; tag_length=11, initial_blocks=[("blue", 0, 0, 5, 5, 26)])
    rejects(; tag_length=11, initial_blocks=[("blue", 48, 0, 5, 5, 10)])
    rejects(; initial_blocks=[("blue", 0, 0, 5, 5, 10)])
    rejects(; replacement_same_tribe=true, max_age=(60, 100))
end

@testset "test_chapter4_invalid_values_rejected" begin
    rejects(; trade=true)
    rejects(; foresight=(0, 10))
    rejects(; cultural_preferences=true, spice=true)
    rejects(; spice=true, tag_length=11, combat_alpha=2.0)
    rejects(; credit=(10, 10.0))
    rejects(; sex=true, credit=(0, 10.0))
    rejects(; sex=true, credit=(10, -1.0))
    rejects(; spice=true, spice_metabolism=(5, 1))
    rejects(; spice=true, foresight=(10, 0))
    rejects(; pollution=(1.0, 1.0), pollution_start=100, pollution_stop=100)
end

@testset "test_credit_with_combat_rejected" begin
    rejects(; sex=true, credit=(10, 10.0), tag_length=11, combat_alpha=2.0)
end

@testset "test_chapter5_invalid_values_rejected" begin
    rejects(; disease_list=3, diseases_per_agent=4)
    rejects(; disease_list=5, disease_length=(1, 50))
    rejects(; disease_list=5, disease_length=(0, 4))
    rejects(; disease_list=5, disease_fee=-1.0)
    rejects(; disease_list=5, disease_length=(6, 3))
    rejects(; disease_list=-1)
    rejects(; disease_list=5, diseases_per_agent=-1)
end

@testset "test_credit_allowed_on_the_spice_landscape" begin
    @test validate(Config(; spice=true, sex=true, credit=(10, 10.0))).credit == (10, 10.0)
end

@testset "test_reproduction_variant_values_rejected" begin
    rejects(; sex=true, fertility_threshold=0.0)
    rejects(; sex=true, child_share=0.0)
    rejects(; sex=true, child_share=1.5)
end

@testset "test_unknown_founder_ages_rejected" begin
    rejects(; founder_ages="old")
end

@testset "test_fertility_threshold_defaults_to_p55" begin
    c = Config()
    @test (c.fertility_threshold, c.child_share) == (1.0, 0.5)
end

@testset "test_unknown_rule_s_options_rejected" begin
    rejects(; sex=true, mate_contact="global")
    rejects(; sex=true, child_gift="half")
    rejects(; sex=true, child_threshold="zero")
    rejects(; sex=true, gift_rounding="up")
end

@testset "test_rule_s_options_default_to_integer_gifts_and_partners_in_sight" begin
    c = Config()
    @test (c.mate_contact, c.child_gift, c.child_threshold) ==
        ("vision", "endowment", "endowment")
    @test c.gift_rounding == "down"
end

@testset "test_trade_rounding_defaults_to_exact_and_rejects_unknown" begin
    @test Config().trade_rounding == "exact"
    rejects(; spice=true, trade=true, trade_rounding="up")
end

@testset "bit-field limits (Julia only)" begin
    @test_throws ArgumentError replace_config(Config(); tag_length=65)
    @test_throws ArgumentError replace_config(Config(); immune_length=65)
    @test replace_config(Config(); tag_length=63).tag_length == 63
end

@testset "replace_config copies, changes and validates" begin
    c = replace_config(Config(); seed=7, initial_population=10)
    @test (c.seed, c.initial_population, c.width) == (7, 10, 50)
    @test c == replace_config(c)
    @test c != Config()
end

@testset "registry configs load and validate" begin
    reg = load_registry()
    @test length(reg) == 135
    e = find_experiment(reg, "III-11")
    @test e.steps == 1000 && e.seeds == 5
    @test e.config.combat_alpha == 2.0 && e.config.max_age == (60, 100)
    @test e.config.initial_blocks ==
        [("blue", 0, 0, 20, 20, 200), ("red", 30, 30, 20, 20, 200)]
    @test find_experiment(reg, "II-1").config.growback_rate == Inf
    @test find_experiment(reg, "VI-1").config.credit == (10, 10.0)
    @test startswith(
        find_experiment(reg, "II-4").fingerprint, "({G1}, {M})\nsteps=500\nConfig("
    )
    @test_throws ArgumentError find_experiment(reg, "no-such-id")
end
