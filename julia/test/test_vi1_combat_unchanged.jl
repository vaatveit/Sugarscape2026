# Guards the combat and VI-1 runs: seed 0 over 10 periods must stay byte-identical to the CSVs recorded before combat
# gained spice and credit (fixtures/vi1-combat-refs, written by make_refs.jl).
using Sugarscape, Test
using Sugarscape: COMBAT_EXPS, COMBAT_WORLDS

include(joinpath(@__DIR__, "fixtures", "vi1-combat-refs", "make_refs.jl"))

@testset "vi1 combat unchanged: $world $exp" for world in COMBAT_WORLDS, exp in (COMBAT_EXPS..., "VI-1")
    fixture = joinpath(REFS_DIR, "$world-$exp.csv")
    @test isfile(fixture)
    @test read(ref_csv(world, exp), String) == read(fixture, String)
end
