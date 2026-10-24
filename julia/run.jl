# Runs registered experiments in Julia into results-julia/ (or results-julia-xl/ with --xl):
#   julia --project=julia julia/run.jl <id-or-prefix> [--seeds N] [--jobs J] [--out DIR] [--xl] [--note TEXT]
using Sugarscape

exit(Sugarscape.main(ARGS))
