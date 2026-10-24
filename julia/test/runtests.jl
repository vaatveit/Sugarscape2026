# Runs every test_*.jl here; with test arguments, only the files whose names contain one of them:
#   julia --project=julia -e 'using Pkg; Pkg.test(test_args=["config"])'
using Test

const FILES = sort(
    filter(f -> startswith(f, "test_") && endswith(f, ".jl"), readdir(@__DIR__))
)
const SELECTED = isempty(ARGS) ? FILES : filter(f -> any(a -> occursin(a, f), ARGS), FILES)

@testset "Sugarscape" begin
    for file in SELECTED
        @testset "$file" begin
            include(joinpath(@__DIR__, file))
        end
    end
end
