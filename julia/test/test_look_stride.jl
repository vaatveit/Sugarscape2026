# Ports tests/test_look_stride.py: Config.look_stride, one random site per stretch of look_stride sites along each
# lattice line (docs/xl.md, "Looking"). Julia scans without building candidate lists, so where Python counts
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

@testset "test_one_distance_from_each_stretch_each_uniform" begin
    m = stride_model(; stride=5, vision=15, size=40)
    looks = [look_distances(m, 15) for _ in 1:3000]
    @test all(
        length(d) == 3 && 1 <= d[1] <= 5 && 6 <= d[2] <= 10 && 11 <= d[3] <= 15 for
        d in looks
    )
    counts = Dict(v => count(d -> d[2] == v, looks) for v in 6:10)
    @test sum(values(counts)) == 3000 && minimum(values(counts)) > 3000 / 5 * 0.8
end

@testset "test_movement_looks_at_one_site_per_stretch_in_each_direction" begin
    # Sugar only at distance 2 east: seen when the first stretch's draw is 2, so about half the time.
    took = 0
    for seed in 1:LOOKS
        m = stride_model(; seed=seed)
        m.landscape.sugar[13, 11] = 3.0
        g = put_agent(m, 10, 10; vision=4)
        move!(m, g)
        took += (g.x, g.y) == (12, 10)
        @test (g.x, g.y) in ((12, 10), (10, 10))
    end
    @test 0.4 < took / LOOKS < 0.6
    # Any distance can be reached: sugar at distance 3 is taken about half the time too.
    took3 = 0
    for seed in 1:LOOKS
        m = stride_model(; seed=seed)
        m.landscape.sugar[11, 14] = 3.0
        g = put_agent(m, 10, 10; vision=4)
        move!(m, g)
        took3 += (g.x, g.y) == (10, 13)
    end
    @test 0.4 < took3 / LOOKS < 0.6
end

@testset "test_partners_in_sight_one_site_per_stretch" begin
    m = stride_model()
    g = put_agent(m, 10, 10; vision=4)
    near, far = put_agent(m, 11, 10), put_agent(m, 12, 10)  # the same stretch of the same line
    outcomes = Set(Tuple(a.id for a in in_sight(m, g)) for _ in 1:LOOKS)
    @test outcomes == Set([(near.id,), (far.id,)])
end

@testset "test_combat_looks_at_one_site_per_stretch" begin
    attacked = 0
    for seed in 1:LOOKS
        m = stride_model(; combat_alpha=2.0, tag_length=3, seed=seed)
        g = tag!(put_agent(m, 10, 10; vision=4, sugar=20.0), [0, 0, 0])
        victim = tag!(put_agent(m, 12, 10; vision=1, sugar=5.0), [1, 1, 1])
        combat_move!(m, g)
        attacked += !victim.alive
    end
    @test 0.4 < attacked / LOOKS < 0.6
end

@testset "test_retaliation_is_looked_for_one_site_per_stretch" begin
    m = stride_model(; combat_alpha=2.0, tag_length=3)
    g = tag!(put_agent(m, 10, 10; vision=4, sugar=1.0), [0, 0, 0])
    tag!(put_agent(m, 13, 10; sugar=50.0), [1, 1, 1])  # distance 1 from (12, 10): seen in about half the looks
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
