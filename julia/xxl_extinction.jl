# Tests whether VI-1 under one xxl rule set has under a 5% chance of going extinct (stage-2 spec): runs its seeds over
# 2,000 periods into results-julia-xxl/extinction-<label>-s<first>-<seeds>-p<periods>/ and writes the report beside
# them. A file named `stop` in that folder pauses the run, each seed saving at the end of its current period; running the
# same command again, with any --jobs, carries on, as it does after a crash, from each seed's last save (at most 100
# periods back). --report-only rebuilds the report from the finished seeds. --set field=value (repeatable) changes any
# xxl rule from its --rules base, as in xxl_scorecard.jl, for example the disease list: --set disease_count=4 --set
# founder_diseases=2 --set disease_lengths=9,10. The label then names the sets unless --label is given, and the rules go
# in the fingerprint and the report, so give --report-only the same ones. The credit study's options change the
# world: --no-credit, --inheritance, --claims-outlive-lender (a dead lender's loans stand), --credit-reach K (scales the
# income a borrower is credited with) and --lender-limit (a lender lends at most half its wealth in a period). They go
# in the fingerprint and the report, so use a new --label for each set, and give --report-only the same ones.
#   julia --project=julia julia/xxl_extinction.jl [--rules v1|defaults] [--set field=value]... [--label NAME]
#         [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR] [--report-only] [--no-credit]
#         [--inheritance] [--claims-outlive-lender] [--credit-reach K] [--lender-limit]
using Sugarscape

exit(Sugarscape.extinction_main(ARGS))
