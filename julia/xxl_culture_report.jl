# Reads the culture study's three finished folders (julia/xxl_culture_study.jl's: book, xl and today) against Part 1's
# bars (docs/superpowers/specs/2026-11-07-xxl-culture-design.md): the drift check against stage 6's folders (each seed's
# standard CSV byte for byte), W1 and W2 (culture is weak), F (culture keeps moving and both tribes live), the readings
# and the outcome. A folder whose fingerprint names another world is refused. It reads only finished seeds and runs
# nothing. The report goes to --md (results-julia-xxl/culture-part1.md by default).
#   julia --project=julia julia/xxl_culture_report.jl --book DIR --xl DIR --today DIR --ref-book DIR --ref-xl DIR
#         --ref-today DIR [--md PATH]
using Sugarscape

exit(Sugarscape.culture_report_main(ARGS))
