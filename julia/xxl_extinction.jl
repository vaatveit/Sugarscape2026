# Tests whether VI-1 under one xxl rule set has under a 5% chance of going extinct (stage-2 spec): runs its seeds over
# 2,000 periods into results-julia-xxl/extinction-<label>-s<first>-<seeds>-p<periods>/ and writes the report beside
# them. A file named `stop` in that folder pauses the run, each seed saving at the end of its current period; running the
# same command again, with any --jobs, carries on, as it does after a crash, from each seed's last save (at most 100
# periods back). --report-only rebuilds the report from the finished seeds:
#   julia --project=julia julia/xxl_extinction.jl [--rules v1|defaults] [--label NAME] [--seeds N] [--first-seed K]
#         [--periods P] [--jobs J] [--out DIR] [--report-only]
using Sugarscape

exit(Sugarscape.extinction_main(ARGS))
