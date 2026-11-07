# The sex study: runs VI-1 in one of three worlds (the book's, the xl one, today's xxl defaults) with the sex readings kept,
# into results-julia-xxl/sex-<world>-VI-1-s<first>-<seeds>-p<periods>/: per seed the usual CSV, <seed>-sex.csv (one row a
# period) and <seed>-agents.csv (the agents that lived in the last 200 periods). Running the same command again skips the
# seeds done and reruns from period 0 any cut short.
#   julia --project=julia julia/xxl_sex_study.jl --world book|xl|today [--seeds N] [--first-seed K] [--periods P]
#         [--jobs J] [--out DIR]
using Sugarscape

exit(Sugarscape.sex_study_main(ARGS))
