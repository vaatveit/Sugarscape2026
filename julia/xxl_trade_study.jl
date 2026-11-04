# The trade study (docs/superpowers/specs/2026-11-03-xxl-trade-design.md): runs VI-1 (or IV-A3) under one xxl rule set with the
# trade readings kept, into results-julia-xxl/trade-<label>-<experiment>-s<first>-<seeds>-p<periods>/: per seed the usual
# CSV, <seed>-trade.csv (one row a period) and <seed>-agents.csv (the last 20 periods' agents). Running the same command
# again skips the seeds done and reruns from period 0 any cut short. --set field=value (repeatable) changes any xxl rule
# from the defaults, --trade-off turns trade off in the world. --xl runs the xl reference (VI-1's xl version, the one the
# scorecard keeps) instead, and skips it when it is already there.
#   julia --project=julia julia/xxl_trade_study.jl --label NAME [--set field=value]... [--trade-off]
#         [--experiment VI-1|IV-A3] [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]
#   julia --project=julia julia/xxl_trade_study.jl --xl [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]
using Sugarscape

exit(Sugarscape.trade_study_main(ARGS))
