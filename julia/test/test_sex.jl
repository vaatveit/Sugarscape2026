# Ports tests/test_sex.py.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

@testset "test_child_born_with_half_of_each_initial_endowment" begin  # p.55
    m = tiny_model(ones(Int, 6, 6); sex=true)
    f, h = couple(m)
    kids = mate!(m, f)
    @test length(kids) == 1 && kids[1].sugar == kids[1].initial_sugar == 60.0
    @test f.sugar == h.sugar == 30.0 && kids[1] in f.children && kids[1] in h.children
    k = kids[1]
    @test abs(k.x - f.x) + abs(k.y - f.y) == 1 || abs(k.x - h.x) + abs(k.y - h.y) == 1
    @test agent_at(m, k.x, k.y) === k && k in m.agents
end

@testset "test_fertility_window" begin
    m = tiny_model(ones(Int, 6, 6); sex=true)
    f, _ = couple(m)
    @test is_fertile(f)
    f.age = 11
    @test !is_fertile(f)
    f.age = 40
    @test !is_fertile(f)  # childbearing ends at fertility_end
end

@testset "test_infertile_cases" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, fertility_threshold=1.0)
    f, h = couple(m; sugar=59.0)
    @test isempty(mate!(m, f))  # wealth below initial endowment
    f.sugar = h.sugar = 60.0
    h.sex = :F
    @test isempty(mate!(m, f))  # same sex
    h.sex, h.age = :M, 50
    @test isempty(mate!(m, f))  # too old
end

@testset "test_no_room_no_child_no_cost" begin
    m = tiny_model(ones(Int, 3, 3); sex=true)
    f, h = couple(m)
    for x in 0:2, y in 0:2
        agent_at(m, x, y) === nothing && put_agent(m, x, y)
    end
    @test isempty(mate!(m, f)) && f.sugar == 60.0
end

@testset "test_child_genes_come_from_parents" begin  # Table III-1, p.78
    m = tiny_model(ones(Int, 6, 6); sex=true, tag_length=3)
    f, h = couple(m)
    f.vision, f.metabolism, h.vision, h.metabolism = 1, 4, 3, 2
    tag!(f, [0, 0, 1])
    tag!(h, [0, 0, 0])
    child = mate!(m, f)[1]
    @test child.vision in (1, 3) &&
        child.metabolism in (4, 2) &&
        tags_of(child)[1:2] == [0, 0]
    @test child.ntags == 3
    @test child.age == 0 && child.sex in (:F, :M) && child.max_age in (f.max_age, h.max_age)
end

@testset "test_mates_with_every_viable_neighbor" begin  # p.56
    m = tiny_model(ones(Int, 7, 7); sex=true)
    f, h = couple(m; sugar=200.0)
    h2 = put_agent(m, 1, 2; sugar=200.0)
    h2.sex, h2.fertility_start, h2.fertility_end, h2.initial_sugar, h2.age = :M,
    12, 50, 60.0,
    20
    @test length(mate!(m, f)) == 2 && f.sugar == 200.0 - 60.0
end

@testset "test_mating_near_full_lattice_runs" begin
    cfg = Config(;
        initial_population=2400, sex=true, endowment=(50, 100), max_age=(60, 100), seed=1
    )
    m = Model(cfg)
    for _ in 1:3
        step!(m)
    end
    @test length(m.agents) <= 2500
    @test count(!isnothing, m.grid) == length(m.agents)
end

@testset "test_fertility_needs_only_the_sugar_endowment" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, spice=true, foresight=(0, 10))
    f, h = couple(m)
    for a in (f, h)
        a.initial_spice, a.spice, a.spice_metabolism, a.foresight = 40.0, 10.0, 1, 2
    end
    @test is_fertile(f) && is_fertile(h)  # spice below its endowment doesn't matter
    child = mate!(m, f)[1]
    @test child.spice == child.initial_spice == 40.0  # each parent still gives half its initial spice
    @test f.spice == h.spice == 10.0 - 20.0
    @test child.spice_metabolism == 1 && child.foresight == 2
end

@testset "test_sugar_only_children_have_no_spice" begin
    m = tiny_model(ones(Int, 6, 6); sex=true)
    f, h = couple(m)
    child = mate!(m, f)[1]
    @test child.spice == 0.0 && child.spice_metabolism == 0
end

@testset "test_fertility_threshold_variant" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, fertility_threshold=0.8)
    f, h = couple(m; sugar=48.0)  # endowed with 60: the variant asks for 48
    @test is_fertile(f, 0.8) && !is_fertile(f)
    @test length(mate!(m, f)) == 1
end

@testset "test_child_share_variant" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, child_share=0.25)
    f, h = couple(m)
    kid = mate!(m, f)[1]
    @test kid.sugar == kid.initial_sugar == 30.0 && f.sugar == h.sugar == 45.0
end

@testset "test_mates_within_vision_variant" begin
    for (contact, born) in (("neighbors", 0), ("vision", 1))
        m = tiny_model(ones(Int, 8, 8); sex=true, mate_contact=contact)
        f, h = couple(m)
        move_agent!(m, h, 2, 4)  # two sites along a lattice line
        f.vision = 2
        @test length(mate!(m, f)) == born
    end
    m = tiny_model(ones(Int, 8, 8); sex=true, mate_contact="vision")
    f, h = couple(m)
    move_agent!(m, h, 3, 3)  # diagonal: out of sight
    f.vision = 2
    @test isempty(mate!(m, f))
end

@testset "test_capped_gift_variant" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, child_gift="capped")
    f, h = couple(m)
    kid = mate!(m, f)[1]
    @test kid.sugar == kid.initial_sugar == 10.0 && f.sugar == h.sugar == 55.0
    m = tiny_model(ones(Int, 6, 6); sex=true, child_gift="capped")
    f, h = couple(m; sugar=4.0)
    f.initial_sugar = h.initial_sugar = 3.0
    kid = mate!(m, f)[1]
    @test kid.sugar == 8.0 && f.sugar == h.sugar == 0.0
end

@testset "test_integer_gift_variant" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, gift_rounding="down")
    f, h = couple(m; sugar=61.0)
    f.initial_sugar, h.initial_sugar = 61.0, 57.0  # halves 30.5 and 28.5 round down to 30 and 28
    kid = mate!(m, f)[1]
    @test kid.sugar == kid.initial_sugar == 58.0 && (f.sugar, h.sugar) == (31.0, 33.0)
end

@testset "test_integer_gift_variant_rounds_spice_and_capped_gifts" begin
    m = tiny_model(ones(Int, 6, 6); sex=true, spice=true, gift_rounding="down")
    f, h = couple(m)
    for a in (f, h)
        a.initial_spice, a.spice = 41.0, 10.0
    end
    kid = mate!(m, f)[1]
    @test kid.spice == kid.initial_spice == 40.0 && f.spice == h.spice == 10.0 - 20.0
    m = tiny_model(ones(Int, 6, 6); sex=true, child_gift="capped", gift_rounding="down")
    f, h = couple(m; sugar=4.5)
    f.initial_sugar = h.initial_sugar = 3.0
    kid = mate!(m, f)[1]
    @test kid.sugar == kid.initial_sugar == 8.0 && f.sugar == h.sugar == 0.5
end

@testset "test_redrawn_threshold_variant" begin
    m = tiny_model(
        ones(Int, 6, 6);
        sex=true,
        child_gift="capped",
        child_threshold="redraw",
        endowment=(50, 100),
    )
    f, h = couple(m)
    kid = mate!(m, f)[1]
    @test kid.sugar == 10.0 &&
        50 <= kid.initial_sugar <= 100 &&
        isinteger(kid.initial_sugar)
end

@testset "child placement is uniform over the parents' empty neighbours" begin
    seen = Set{Tuple{Int,Int}}()
    for seed in 0:99
        m = tiny_model(ones(Int, 6, 6); sex=true, seed=seed)
        f, h = couple(m)
        k = mate!(m, f)[1]
        push!(seen, (k.x, k.y))
    end
    # f at (2,2) and h at (2,3): six distinct empty sites next to either
    @test seen == Set([(3, 2), (1, 2), (2, 1), (3, 3), (1, 3), (2, 4)])
end
