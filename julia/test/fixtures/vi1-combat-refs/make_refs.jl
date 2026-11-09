# Writes the reference CSVs that test_vi1_combat_unchanged.jl compares against: seed 0, 10 periods, for III-9, III-11,
# III-12, III-13, III-14 and VI-1 in each of the book, xl and today worlds. Run it only on code known to be right:
#   julia --project=julia julia/test/fixtures/vi1-combat-refs/make_refs.jl
using Sugarscape
using Sugarscape: run_combat_world, run_sex_world, COMBAT_EXPS, COMBAT_WORLDS

const REFS_DIR = @__DIR__

"""The seed 0 CSV of `exp` in `world` over 10 periods, run in a temporary folder."""
function ref_csv(world::AbstractString, exp::AbstractString)
    out = mktempdir()
    folder = exp == "VI-1" ? run_sex_world(world; seeds=1, first_seed=0, periods=10, out=out, io=devnull) :
             run_combat_world(world, exp; seeds=1, first_seed=0, periods=10, out=out, io=devnull)
    return joinpath(folder, "seed0.csv")
end

if abspath(PROGRAM_FILE) == @__FILE__
    for world in COMBAT_WORLDS, exp in (COMBAT_EXPS..., "VI-1")
        cp(ref_csv(world, exp), joinpath(REFS_DIR, "$world-$exp.csv"); force=true)
    end
end
