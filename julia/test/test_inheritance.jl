# Ports tests/test_inheritance.py, plus the Chapter III founder checks.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

@testset "test_inheritance_splits_wealth_among_living_children" begin  # p.67
    m = tiny_model(ones(Int, 5, 5); inheritance=true)
    p = put_agent(m, 0, 0; sugar=30.0)
    kids = [put_agent(m, 2, y) for y in (0, 1, 2)]
    append!(p.children, kids)
    kill!(m, kids[3])
    die!(m, p)
    @test [k.sugar for k in kids[1:2]] == [25.0, 25.0] && !p.alive
end

@testset "test_no_inheritance_when_off" begin
    m = tiny_model(ones(Int, 5, 5))
    p = put_agent(m, 0, 0; sugar=30.0)
    k = put_agent(m, 2, 2)
    push!(p.children, k)
    die!(m, p)
    @test k.sugar == 10.0
end

@testset "test_negative_wealth_is_not_inherited" begin
    m = tiny_model(ones(Int, 5, 5); inheritance=true)
    p = put_agent(m, 0, 0; sugar=-2.0)
    k = put_agent(m, 2, 2)
    push!(p.children, k)
    die!(m, p)
    @test k.sugar == 10.0
end

@testset "test_same_batch_deaths_do_not_inherit" begin
    m = tiny_model(zeros(Int, 5, 5); inheritance=true)  # no harvest: sugar only falls by 1
    p = put_agent(m, 0, 0; sugar=40.0, max_age=1)
    k = put_agent(m, 2, 2; max_age=1)
    q = put_agent(m, 4, 4)
    append!(p.children, [k, q])
    step!(m)
    @test !k.alive && q.sugar == 9.0 + 39.0  # q gets all of p's 39; k died in the same batch
end

const BLOCKS = [("blue", 0, 0, 20, 20, 270), ("red", 30, 30, 20, 20, 270)]

@testset "test_blocks_are_tagged_by_tribe" begin
    m = Model(Config(; tag_length=11, initial_blocks=BLOCKS))
    @test length(m.agents) == 540
    @test all(tribe(a) == (a.x < 20 ? :blue : :red) for a in m.agents)
    @test all(a.x < 20 && a.y < 20 || 30 <= a.x && 30 <= a.y for a in m.agents)
end

@testset "test_same_tribe_replacement" begin  # p.86
    cfg = Config(;
        tag_length=11,
        max_age=(1, 1),
        replacement=true,
        replacement_same_tribe=true,
        initial_blocks=[("red", 30, 30, 20, 20, 50)],
    )
    m = Model(cfg)
    step!(m)
    @test length(m.agents) == 50 && all(tribe(a) == :red && a.age == 0 for a in m.agents)
    @test deaths_this_step(m) == 50
end

@testset "test_random_agents_get_tags_and_sex_only_when_enabled" begin
    plain = Model(Config(; initial_population=20))
    @test all(a.ntags == 0 && a.sex == :none for a in plain.agents)
    rich = Model(Config(; initial_population=20, tag_length=11, sex=true))
    @test all(a.ntags == 11 && a.sex in (:F, :M) for a in rich.agents)
    f = [a for a in rich.agents if a.sex == :F]
    @test all(12 <= a.fertility_start <= 15 && 40 <= a.fertility_end <= 50 for a in f)
    males = [a for a in rich.agents if a.sex == :M]
    @test all(50 <= a.fertility_end <= 60 for a in males)
end

@testset "test_chapter2_draws_unaffected_by_chapter3_fields" begin
    # Placement is drawn before any founder; the first founder's Chapter II draws precede its tags (Python's order).
    a, b = Model(Config(; seed=5)), Model(Config(; seed=5, tag_length=11, sex=true))
    @test [(g.x, g.y) for g in a.agents] == [(g.x, g.y) for g in b.agents]
    first(m) = m.agents[findfirst(g -> g.id == 0, m.agents)]
    @test (first(a).vision, first(a).metabolism, first(a).sugar) ==
        (first(b).vision, first(b).metabolism, first(b).sugar)
end

@testset "test_iii12_xl_builds" begin  # Review Focus 3
    cfg = to_xl(find_experiment(load_registry(), "III-12").config)
    m = Model(cfg)
    @test length(m.agents) == 74_000
    @test count(a -> tribe(a) == :blue, m.agents) == 37_000
    @test all(
        tribe(a) == :blue ? (a.x < 200 && a.y < 200) : (a.x >= 300 && a.y >= 300) for
        a in m.agents
    )
end
