# combat_reach and culture_reach (docs/superpowers/plans/2026-11-09-vi1-reach.md, Task 1): values and dependencies.
using Sugarscape, Test
using Sugarscape: XxlRules

@testset "test_reach_config" begin
    @test Config().combat_reach == "vision"
    @test Config().culture_reach == "neighbours"

    combat = (; tag_length=5, combat_alpha=2.0)
    @test validate(Config(; combat..., combat_reach="neighbours")).combat_reach == "neighbours"
    @test validate(Config(; combat..., combat_reach="vision")).combat_reach == "vision"
    @test_throws ArgumentError validate(Config(; combat..., combat_reach="far"))
    @test_throws ArgumentError validate(Config(; tag_length=5, combat_reach="neighbours"))

    culture = (; tag_length=5, culture=true)
    @test validate(Config(; culture..., culture_reach="sight")).culture_reach == "sight"
    @test_throws ArgumentError validate(Config(; tag_length=5, culture_reach="sight"))
    @test_throws ArgumentError validate(Config(; culture..., culture_reach="nearby"))

    speed = XxlRules(; vision_shape="disc", speed=(3, 3), travel_cost=0.0)
    @test_throws ArgumentError validate(Config(; culture..., culture_reach="attack"))
    @test validate(Config(; culture..., culture_reach="attack", vision=(3, 4), xxl=speed)).culture_reach == "attack"
end
