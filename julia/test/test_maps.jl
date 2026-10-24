# Ports tests/test_maps.py and pins the xl map (docs/xl.md, "The map").
using Sugarscape, Test

@testset "test_shape_and_range" begin
    cap = load_map("sugar-map.txt")
    @test size(cap) == (50, 50)
    @test extrema(cap) == (0, 4)
    @test sum(cap) == 4622
end

@testset "test_peaks_are_northeast_and_southwest" begin
    cap = load_map("sugar-map.txt")  # site (x, y) is cap[x + 1, y + 1]
    @test cap[1, 1] == 1
    @test cap[36, 36] == 4
    @test cap[16, 16] == 4
end

@testset "the xl map" begin
    xl = load_map(XL_MAP)
    @test size(xl) == (500, 500)
    @test sum(xl) == 462024
    @test xl[356, 356] == 4
    @test map_sha256(XL_MAP) ==
        "014091e7bc6ade8a6887c37f94c3edc4806c470a887fdfafbc2eefa84234c43d"
end
