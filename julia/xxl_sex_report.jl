# Reads the sex study's three finished folders (julia/xxl_sex_study.jl's: book, xl and today) against Part 1's bars
# (docs/superpowers/specs/2026-11-07-xxl-sex-design.md): M1 and M2 (mate finding limits births), S (selection acts), the
# readings and the outcome. A folder whose fingerprint names another world is refused. It reads only finished seeds and
# runs nothing. The report goes to --md (results-julia-xxl/sex-part1.md by default).
#   julia --project=julia julia/xxl_sex_report.jl --book DIR --xl DIR --today DIR [--md PATH]
using Sugarscape

exit(Sugarscape.sex_report_main(ARGS))
