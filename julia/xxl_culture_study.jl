# The culture study: runs VI-1 in one of three worlds (the book's, the xl one, today's xxl defaults) with the culture
# readings kept, into results-julia-xxl/culture-<world>-VI-1-s<first>-<seeds>-p<periods>/: per seed the usual CSV,
# <seed>-culture.csv (one row a period) and <seed>-patches.csv (the tribe mix in each patch, every 10th period).
# Running the same command again skips the seeds done and reruns from period 0 any cut short.
#   julia --project=julia julia/xxl_culture_study.jl --world book|xl|today [--seeds N] [--first-seed K] [--periods P]
#         [--jobs J] [--out DIR]
using Sugarscape

exit(Sugarscape.culture_study_main(ARGS))
