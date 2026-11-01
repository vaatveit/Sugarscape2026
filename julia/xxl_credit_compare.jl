# Compares finished runs seed by seed, for the credit study: what credit adds. --on and --off are run folders of --out
# (the extinction test's or the loan trace's, results-julia-xxl/ by default) made with credit and without it, and --runs
# lists others (credit options, say) to set against both. For each pair it reports, over the seeds both have finished and
# the periods both reach, the ratio of the run's mean to the base's of the trough, the population, the births and the
# births per head, with a bootstrap interval and where it lies against 1 and 0.95–1.05; how far the run's recovery trails
# the base's; and for each of --runs the share of the lift from off to on that it keeps. It reads only finished seeds and
# runs nothing, so it can be used while a run is going. The report goes to <out>/credit-compare-<label>.md.
#   julia --project=julia julia/xxl_credit_compare.jl --on FOLDER --off FOLDER [--runs FOLDER,FOLDER,…] [--out DIR]
#         [--label NAME]
using Sugarscape

exit(Sugarscape.credit_compare_main(ARGS))
