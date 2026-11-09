# The combat study: runs one combat experiment (III-9, III-11, III-12, III-13 or III-14) in one of three worlds (the book's,
# the xl one, today's xxl defaults) with the combat readings kept, into
# results-julia-xxl/combat-<world>-<exp>-s<first>-<seeds>-p<periods>/: per seed the usual CSV, <seed>-combat.csv (one row a
# period) and the timing file. The periods default to the experiment's own steps. Running the same command again skips
# the seeds done and reruns from period 0 any cut short.
#   julia --project=julia julia/xxl_combat_study.jl --world book|xl|today --exp III-9|III-11|III-12|III-13|III-14
#         [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]
using Sugarscape

exit(Sugarscape.combat_study_main(ARGS))
