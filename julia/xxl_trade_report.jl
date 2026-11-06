# Reads finished trade study folders (julia/xxl_trade_study.jl's) against the bars fixed before the runs
# (docs/superpowers/specs/2026-11-03-xxl-trade-design.md). --part1: today's runs (trade on, trade off, no disease, IV-A3)
# and the xl reference, the row of "What Part 1 decides" that fires, the readings, traders against similar non-traders and
# trade on ÷ off. Screening: the arms (NAME=VI1,NODISEASE,IVA3, the arm's three folders) against the baseline, the
# reading table with pass, near or fail, the arm chosen and the result row, the readings, the ratios to the baseline and
# trade on ÷ off. --confirm: the confirmation's study run, its traders against similar non-traders against the bar, and
# trade on ÷ off. Every folder is under --out (results-julia-xxl/ by default). It reads only finished seeds and runs
# nothing. The report goes to <out>/trade-<label>.md (the label is part1, screen or confirm unless given).
#   julia --project=julia julia/xxl_trade_report.jl --part1 --on FOLDER --off FOLDER --nodisease FOLDER --iva3 FOLDER
#         --xl FOLDER [--out DIR] [--label NAME]
#   julia --project=julia julia/xxl_trade_report.jl --base NAME=VI1,NODISEASE,IVA3 --arms NAME=VI1,NODISEASE,IVA3,...
#         --off FOLDER --xl FOLDER [--out DIR] [--label NAME]
#   julia --project=julia julia/xxl_trade_report.jl --confirm --vi1 FOLDER --off FOLDER [--out DIR] [--label NAME]
using Sugarscape

exit(Sugarscape.trade_report_main(ARGS))
