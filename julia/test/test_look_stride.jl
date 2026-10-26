# Ports tests/test_look_stride.py: Config.look_stride, one random site for each whole stride of vision along each
# lattice line, centred on it: stretch k is seen at s k + a - b, a and b uniform on 0 .. s - 1 (docs/xl.md, "Looking"). Julia scans without building candidate lists, so where Python counts
# candidates these tests count what the agent does.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

const LOOKS = 400

rejects_stride(; kw...) = @test_throws ArgumentError validate(Config(; kw...))

@testset "test_look_stride_must_be_a_whole_number_at_least_1" begin
    rejects_stride(; look_stride=0)
    rejects_stride(; look_stride=-1)
end

@testset "test_vision_bounds_must_be_multiples_of_the_stride" begin
    rejects_stride(; width=100, height=100, vision=(5, 20), look_stride=10)
    @test validate(Config(; width=100, height=100, vision=(10, 40), look_stride=10)).look_stride ==
        10
end

@testset "test_vision_plus_the_look_reach_must_stay_under_half_the_grid" begin
    # The farthest look is vision + stride - 1 sites away; opposite scans must not reach the same site.
    rejects_stride(; width=21, height=21, vision=(2, 10), look_stride=2)  # reaches 11
    @test validate(Config(; width=21, height=21, vision=(2, 8), look_stride=2)).vision ==
        (2, 8)  # reaches 9
end

@testset "test_vision_is_drawn_in_whole_strides" begin
    m = Model(Config(; vision=(5, 20), look_stride=5, initial_population=200))
    @test Set(a.vision for a in m.agents) == Set([5, 10, 15, 20])
end

function stride_model(; stride=2, vision=4, size=20, kw...)
    return tiny_model(
        zeros(Int, size, size); vision=(stride, vision), look_stride=stride, kw...
    )
end

@testset "test_stride_1_looks_at_every_site_without_drawing" begin
    m = tiny_model(zeros(Int, 20, 20); vision=(1, 4))
    before = copy(m.rng)
    @test look_distances(m, 4) == [1, 2, 3, 4]
    @test m.rng == before  # regular random streams are unchanged
end

@testset "test_a_stretch_is_seen_at_a_triangular_distance_centred_on_its_stride" begin
    # Where a random site of the regular cell one stride away lies from a random site of one's own cell.
    s, n = 5, 10000
    m = stride_model(; stride=s, vision=s, size=40)
    looks = reduce(vcat, (look_distances(m, s) for _ in 1:n))
    @test Set(looks) == Set(1:(2s - 1))
    for d in 1:(2s - 1)
        expected = n * (s - abs(d - s)) / s^2
        @test abs(count(==(d), looks) - expected) < 5 * sqrt(expected)
    end
end

@testset "test_distances_are_distinct_sorted_and_cover_every_stretch" begin
    s, vision = 5, 15
    m = stride_model(; stride=s, vision=vision, size=40)
    full = Vector{Int}[]
    for _ in 1:3000
        d = look_distances(m, vision)
        @test d == sort(unique(d)) &&
            1 <= d[1] &&
            d[end] <= vision + s - 1 &&
            length(d) <= vision ÷ s
        @test all(any(s * k - (s - 1) <= x <= s * k + (s - 1) for x in d) for k in 1:3)
        length(d) == 3 && push!(full, d)
    end
    @test [round(Int, sum(x[i] for x in full) / length(full)) for i in 1:3] == [5, 10, 15]
end

@testset "test_movement_looks_at_a_site_per_stretch_in_each_direction" begin
    # With stride 2, the first stretch is seen at 1, 2 or 3 (chances 1/4, 1/2, 1/4) and the second at 3, 4 or 5.
    # Sugar only at distance 2 east: seen half the time.
    took = 0
    for seed in 1:LOOKS
        m = stride_model(; seed=seed)
        m.landscape.sugar[13, 11] = 3.0
        g = put_agent(m, 10, 10; vision=4)
        move!(m, g)
        took += (g.x, g.y) == (12, 10)
        @test (g.x, g.y) in ((12, 10), (10, 10))
    end
    @test 0.42 < took / LOOKS < 0.58
    # Distance 3 is in both stretches' reach (seen 1 - (3/4)^2 = 7/16 of the time), and distance 5, past vision, in
    # the second's (1/4).
    for (dist, share) in ((3, 7 / 16), (5, 1 / 4))
        took = 0
        for seed in 1:LOOKS
            m = stride_model(; seed=seed)
            m.landscape.sugar[11, 11 + dist] = 3.0
            g = put_agent(m, 10, 10; vision=4)
            move!(m, g)
            took += (g.x, g.y) == (10, 10 + dist)
        end
        @test abs(took / LOOKS - share) < 0.08
    end
end

@testset "test_partners_in_sight_one_site_per_stretch" begin
    m = stride_model(; stride=2, vision=2)
    g = put_agent(m, 10, 10; vision=2)
    near, far = put_agent(m, 11, 10), put_agent(m, 12, 10)  # the one stretch of the line: seen at 1, 2 or 3
    outcomes = Set(Tuple(a.id for a in in_sight(m, g)) for _ in 1:LOOKS)
    @test outcomes == Set([(near.id,), (far.id,), ()])
end

@testset "test_partners_in_sight_come_nearest_first_across_directions" begin
    m = stride_model()
    g = put_agent(m, 10, 10; vision=4)
    east, north = put_agent(m, 13, 10), put_agent(m, 10, 12)  # east is listed first among equals; north is nearer
    both = [
        copy(found) for found in (in_sight(m, g) for _ in 1:LOOKS) if length(found) == 2
    ]
    @test !isempty(both) && all(found == [north, east] for found in both)
    # The same within one stretch: north at 1 comes before east at 2, though east's line is looked along first.
    m = stride_model()
    g = put_agent(m, 10, 10; vision=4)
    east, north = put_agent(m, 12, 10), put_agent(m, 10, 11)
    both = [
        copy(found) for found in (in_sight(m, g) for _ in 1:LOOKS) if length(found) == 2
    ]
    @test !isempty(both) && all(found == [north, east] for found in both)
    # At equal distances, east, west, north, south (VON_NEUMANN order).
    m = stride_model()
    g = put_agent(m, 10, 10; vision=4)
    north, east = put_agent(m, 10, 12), put_agent(m, 12, 10)
    both = [
        copy(found) for found in (in_sight(m, g) for _ in 1:LOOKS) if length(found) == 2
    ]
    @test !isempty(both) && all(found == [east, north] for found in both)
end

@testset "test_combat_looks_at_a_site_per_stretch" begin
    # The victim, 2 sites east, is seen half the time (the first stretch's chances 1/4, 1/2, 1/4 at 1, 2, 3).
    attacked = 0
    for seed in 1:LOOKS
        m = stride_model(; combat_alpha=2.0, tag_length=3, seed=seed)
        g = tag!(put_agent(m, 10, 10; vision=4, sugar=20.0), [0, 0, 0])
        victim = tag!(put_agent(m, 12, 10; vision=1, sugar=5.0), [1, 1, 1])
        combat_move!(m, g)
        attacked += !victim.alive
    end
    @test 0.42 < attacked / LOOKS < 0.58
end

@testset "test_retaliation_is_looked_for_one_site_per_stretch" begin
    m = stride_model(; combat_alpha=2.0, tag_length=3)
    g = tag!(put_agent(m, 10, 10; vision=4, sugar=1.0), [0, 0, 0])
    tag!(put_agent(m, 13, 10; sugar=50.0), [1, 1, 1])  # distance 1 from (12, 10): seen in about a quarter of looks
    outcomes = Set(vulnerable(m, g, 12, 10, 0.0, nothing) for _ in 1:LOOKS)
    @test outcomes == Set([true, false])
end

@testset "test_xl_agents_are_not_held_to_a_coarse_grid" begin
    m = Model(to_xl(Config(; initial_population=20, seed=1)))  # 2,000 founders
    start = Dict(a.id => (a.x % 10, a.y % 10) for a in m.agents)
    for _ in 1:10
        step!(m)
    end
    kept = count(a -> start[a.id] == (a.x % 10, a.y % 10), m.agents)
    @test kept < 0.2 * length(m.agents)
end
