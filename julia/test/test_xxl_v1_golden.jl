# xxl: the first rules (XXL_V1) are frozen. Seven seed-0 runs of 25 periods are rerun and must match the committed CSVs
# in fixtures/xxl-v1/ byte for byte, so a later change that alters the first rules' runs fails here. Regenerate them,
# on purpose only, with fixtures/make_xxl_v1_golden.jl.
using Sugarscape, Test

include(joinpath(@__DIR__, "fixtures", "make_xxl_v1_golden.jl"))

@testset "XXL_V1 golden runs" begin
    @test Sugarscape.rules_line(XXL_V1) ==
        "vision_shape=\"disc\" speed=(1, 6) travel_cost=0.1 memory=8 memory_span=50 " *
          "word_of_mouth=true interaction_radius=1.5 season_gradient=true landscape=\"xl\""
    reg = load_registry()
    for (name, exp, rules) in golden_cases(reg)
        @testset "$name" begin
            path = write_golden(tempname(), exp, rules)
            try
                @test read(path, String) ==
                    read(joinpath(GOLDEN_DIR, name * ".csv"), String)
            finally
                rm(path; force=true)
            end
        end
    end
end
