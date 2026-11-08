# Reads the combat study's fifteen finished folders (julia/xxl_combat_study.jl's: III-9, III-11, III-12, III-13 and
# III-14 in the book's world, xl and today's) against Part 1's bars (docs/superpowers/specs/2026-11-08-xxl-combat-design.md):
# the drift check of the book's and xl's standard CSVs against the saved runs (results-julia and results-julia-xl, byte for
# byte where the saved fingerprint is today's), W1 and W2 (combat is weak), F (the wars stay wars and the population
# lives), the readings and the outcome. A folder whose fingerprint names another world or experiment is refused. It reads
# only finished seeds and runs nothing. The report goes to --md (<dir>/combat-part1.md by default).
#   julia --project=julia julia/xxl_combat_report.jl [--dir DIR] [--first-seed K] [--seeds N] [--ref-book DIR]
#         [--ref-xl DIR] [--md PATH]
using Sugarscape

exit(Sugarscape.combat_report_main(ARGS))
