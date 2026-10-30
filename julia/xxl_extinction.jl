# Tests whether VI-1 under one xxl rule set has under a 5% chance of going extinct (stage-2 spec): runs its seeds over
# 2,000 periods into results-julia-xxl/extinction-<label>-s<first>-<seeds>-p<periods>/ and writes the report beside
# them. A stopped run resumes where it was left; --report-only rebuilds the report from the finished seeds:
#   julia --project=julia julia/xxl_extinction.jl [--rules v1|defaults] [--label NAME] [--seeds N] [--first-seed K]
#         [--periods P] [--jobs J] [--out DIR] [--report-only]
using Sugarscape

exit(Sugarscape.extinction_main(ARGS))
