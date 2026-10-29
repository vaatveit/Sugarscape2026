# Runs registered experiments in Julia into results-julia/ (results-julia-xl/ with --xl, results-julia-xxl/ with --xxl;
# an XXL-... id or prefix, or XXL for all of them, runs the xxl experiments there without a flag):
#   julia --project=julia julia/run.jl <id-or-prefix> [--seeds N] [--jobs J] [--out DIR] [--xl | --xxl] [--note TEXT]
using Sugarscape

exit(Sugarscape.main(ARGS))
