# Formats the Julia port in BlueStyle (julia/.JuliaFormatter.toml):
#   julia --project=julia/tools julia/tools/format.jl
using JuliaFormatter

const ROOT = dirname(@__DIR__)
for dir in ("src", "test", "tools")
    format(joinpath(ROOT, dir))
end
isfile(joinpath(ROOT, "run.jl")) && format(joinpath(ROOT, "run.jl"))
