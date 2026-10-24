# Ports the transform tests of tests/test_xl_config.py; checks to_xl against Python's for every experiment.
using Sugarscape, Test

@testset "test_xl_follows_the_spec_table" begin
    cfg = Config(;
        initial_population=400,
        vision=(1, 6),
        placement="block",
        block=(0, 0, 20, 19),
        diffusion_period=2,
        pollution=(1.0, 1.0),
        metabolism=(1, 4),
        seed=3,
    )
    xl = to_xl(cfg)
    @test (xl.width, xl.height, xl.sugar_map) == (500, 500, "sugar-map-xl.txt")
    @test xl.initial_population == 40_000 && xl.vision == (10, 60)
    @test xl.block == (0, 0, 200, 190) && xl.diffusion_passes == 100
    back = replace_config(
        xl;
        width=50,
        height=50,
        sugar_map="sugar-map.txt",
        initial_population=400,
        vision=(1, 6),
        block=(0, 0, 20, 19),
        diffusion_passes=1,
    )
    @test back == cfg  # nothing else changed
end

@testset "test_tribal_blocks_scale_coordinates_by_10_and_counts_by_100" begin
    xl = to_xl(find_experiment(load_registry(), "III-12").config)
    @test xl.initial_blocks ==
        [("blue", 0, 0, 200, 200, 37_000), ("red", 300, 300, 200, 200, 37_000)]
end

@testset "test_xl_refuses_a_world_that_is_not_the_50x50_map" begin
    @test_throws ArgumentError to_xl(to_xl(Config()))
    @test_throws ArgumentError to_xl(replace_config(Config(); width=60, height=60))
end

@testset "test_xl_refuses_a_50x50_world_on_another_map" begin
    err = try
        to_xl(Config(; sugar_map="other-map.txt"))
    catch e
        e
    end
    @test err isa ArgumentError && occursin("other-map.txt", err.msg)
end

@testset "to_xl matches Python for every registered experiment" begin
    sha = map_sha256(XL_MAP)
    for e in load_registry()
        @test to_xl(e.config) == e.xl_config
        @test endswith(e.xl_fingerprint, "xl map sha256=$sha\n")
    end
end
