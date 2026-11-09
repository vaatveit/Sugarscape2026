# Guards the combat, VI-1, VI-1-combat and VI-1-distance runs: seed 0 over 10 periods must stay byte-identical to the
# CSVs in fixtures/vi1-combat-refs (written by make_refs.jl), which pin each experiment as it stood before the change
# that added them.
using Sugarscape, Test
using Sugarscape: COMBAT_EXPS, COMBAT_WORLDS, VI1_COMBAT_ID, VI1_DISTANCE_ID

include(joinpath(@__DIR__, "fixtures", "vi1-combat-refs", "make_refs.jl"))

@testset "vi1 combat unchanged: $world $exp" for world in COMBAT_WORLDS, exp in (COMBAT_EXPS..., "VI-1", VI1_COMBAT_ID, VI1_DISTANCE_ID)
    fixture = joinpath(REFS_DIR, "$world-$exp.csv")
    @test isfile(fixture)
    @test read(ref_csv(world, exp), String) == read(fixture, String)
end
