# Traces every loan of VI-1 in one world (the xxl defaults, the xl version or the book's own) to see what the X8
# scorecard check measures: runs the seeds over the periods into
# results-julia-xxl/loans-<label>-s<first>-<seeds>-p<periods>/ and writes the report beside them. A seed counts only
# with its CSV and its three trace files, so running the same command again skips the seeds done and reruns from
# period 0 any that were cut short (a traced seed can't be paused). --report-only rebuilds the report from the finished
# seeds; --compare BASE,A,B,... tabulates folders of --out, over the seeds they share and their first --periods
# periods, into <out>/loans-compare.md. --term D changes the loan term (the rate stays 10); --no-credit and
# --inheritance change the rules, as do --credit-reach K (scales the income a borrower is credited with) and
# --lender-limit (a lender lends at most half its wealth in a period), which need credit; --label defaults to the
# world's name.
#   julia --project=julia julia/xxl_loan_trace.jl [--world defaults|xl|book] [--term D] [--no-credit] [--inheritance]
#         [--credit-reach K] [--lender-limit] [--label NAME] [--seeds N] [--first-seed K] [--periods P] [--jobs J]
#         [--out DIR] [--report-only] [--compare BASE,A,B]
using Sugarscape

exit(Sugarscape.loan_trace_main(ARGS))
