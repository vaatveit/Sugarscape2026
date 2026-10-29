# Scores one xxl rule set (revised spec, "The scorecard"): runs II-4, IV-A3 and VI-1 under it, and their xl versions
# as the reference, into results-julia-xxl/scorecard-<label>-s<first>-<seeds>/ and writes the report beside them:
#   julia --project=julia julia/xxl_scorecard.jl [--rules v1|defaults] [--set field=value]... [--label NAME]
#         [--seeds N] [--first-seed K] [--jobs J] [--out DIR]
using Sugarscape

exit(Sugarscape.scorecard_main(ARGS))
