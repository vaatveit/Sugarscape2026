# xxl rule 6: the generated landscape (spec, "Generated landscape"). SplitMix64, the bump field, the rank cut, and the
# two committed maps being exactly what the generator makes from its recorded seeds.
using Sugarscape, Test
using Random: Xoshiro
using Sugarscape:
    next!, unit!, draw_bumps, field_value, cut_by_rank, map_text, XXL_SPICE_MAP

xl_counts() = Tuple(count(==(c), load_map("sugar-map-xl.txt")) for c in 0:4)

@testset "SplitMix64" begin
    # Reference outputs for seed 0, from the published algorithm, cross-checked against a separate Python run.
    g = SplitMix64(0)
    @test next!(g) == 0xe220a8397b1dcdaf
    @test next!(g) == 0x6e789e6aa1b965f4
    @test next!(g) == 0x06c45d188009454f
    h = SplitMix64(7)
    u = [unit!(h) for _ in 1:1000]
    @test all(0.0 .<= u .< 1.0)
    @test unit!(SplitMix64(7)) == (next!(SplitMix64(7)) >> 11) * 2.0^-53
end

@testset "bump field" begin
    bumps = draw_bumps(1)
    @test length(bumps) == 400
    @test all(
        b -> 5 <= b.r <= 80 && 0 < b.h <= 1 && 0 <= b.x < 500 && 0 <= b.y < 500, bumps
    )
    f = bump_field(1)
    @test size(f) == (500, 500)
    rng = Xoshiro(3)
    for _ in 1:20
        x, y = rand(rng, 0:499), rand(rng, 0:499)
        @test f[x + 1, y + 1] == field_value(bumps, Float64(x), Float64(y))
    end
end

@testset "periodic" begin
    bumps = draw_bumps(1)
    rng = Xoshiro(11)
    for _ in 1:100
        x, y = 500 * rand(rng), 500 * rand(rng)
        v = field_value(bumps, x, y)
        @test isapprox(field_value(bumps, x + 500, y), v; atol=1e-9)
        @test isapprox(field_value(bumps, x, y + 500), v; atol=1e-9)
    end
end

@testset "cut_by_rank" begin
    field = [0.5 0.1; 0.9 0.3; 0.7 0.2]
    cap, gap = cut_by_rank(field, (1, 2, 1, 1, 1))
    @test cap == [2 0; 4 1; 3 1]
    @test gap ≈ 0.1
    @test cut_by_rank([1.0 1.0; 2.0 3.0], (1, 1, 1, 1, 0))[2] == 0.0  # a tie is a zero gap
end

# Each map is generated once and shared by the tests below.
const SUGAR_GEN = generate_map(XXL_TERRAIN_SEEDS.sugar, xl_counts())
const SPICE_GEN = generate_map(XXL_TERRAIN_SEEDS.spice, xl_counts())

@testset "regenerates the committed maps" begin
    @test SUGAR_GEN[2] == XXL_TERRAIN_SEEDS.sugar
    @test SPICE_GEN[2] == XXL_TERRAIN_SEEDS.spice
    @test SUGAR_GEN[1] == load_map("sugar-map-xxl.txt")
    @test SPICE_GEN[1] == load_map(XXL_SPICE_MAP)
    for (name, gen) in (("sugar-map-xxl.txt", SUGAR_GEN), (XXL_SPICE_MAP, SPICE_GEN))
        text = read(joinpath(MAPS_DIR, name), String)
        @test text == map_text(gen[1])
        @test !occursin('\r', text) && endswith(text, "\n")
        @test length(split(text, '\n'; keepempty=false)) == 500
    end
end

@testset "counts and gaps" begin
    counts = xl_counts()
    for (cap, seed) in (SUGAR_GEN, SPICE_GEN)
        @test Tuple(count(==(c), cap) for c in 0:4) == counts
        @test sum(cap) == sum(load_map("sugar-map-xl.txt"))
        field = bump_field(seed)
        @test cut_by_rank(field, counts)[2] >= 1e-9
    end
    @test XXL_TERRAIN_SEEDS.sugar != XXL_TERRAIN_SEEDS.spice
    @test SPICE_GEN[1] != SUGAR_GEN[1]
end

@testset "spice is its own" begin
    cfg = to_xxl(
        find_experiment(load_registry(), "IV-A3").config, XxlRules(; landscape="generated")
    )
    @test cfg.spice && xxl_on(cfg, :generated)
    m = Model(replace_config(cfg; initial_population=0))
    @test m.landscape.capacity == load_map("sugar-map-xxl.txt")
    @test m.landscape.spice_capacity == load_map(XXL_SPICE_MAP)
    @test m.landscape.spice_capacity != reverse(m.landscape.capacity; dims=1)
end
