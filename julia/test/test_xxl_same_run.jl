# A faster hot path must be the same run. These runs were recorded before the first of the speedups went in; regenerate them,
# on purpose only, with fixtures/make_same_run_golden.jl.
using Sugarscape, Test

include(joinpath(@__DIR__, "fixtures", "make_same_run_golden.jl"))

@testset "xxl: the same runs, to the bit" begin
    recorded = Dict(Pair(split(line)...) for line in readlines(SAME_RUN_FILE))
    for (name, cfg) in same_run_cases(load_registry())
        @testset "$name" begin
            @test same_run_digest(cfg).digest == recorded[name]
        end
    end
end
