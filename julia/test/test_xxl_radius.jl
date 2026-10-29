# xxl rule 4: interaction radius (spec, "Interaction radius"). Checks `neighbors_of`, `set_neighbors!`, rule S's
# child placement and trade under R = 1.5 and R = 3, and that R = 1 keeps the book's four von Neumann neighbours.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape:
    radius_neighbors!, radius_empty_sites!, near_offsets, set_neighbors!, torus_dist

# A 12x12 world of sugar-rich sites with interaction radius `R`.
function radius_world(R; kw...)
    return tiny_model(ones(Int, 12, 12); xxl=XxlRules(; interaction_radius=R), kw...)
end

@testset "R = 1.5: the eight Moore neighbours" begin
    m = radius_world(1.5)
    a = put_agent(m, 5, 5)
    ring = [(5 + dx, 5 + dy) for dx in -1:1 for dy in -1:1 if (dx, dy) != (0, 0)]
    others = [put_agent(m, x, y) for (x, y) in ring]
    found = neighbors_of(m, a)
    @test length(found) == 8
    @test Set(found) == Set(others)
    @test [(o.x, o.y) for o in found] == [(5 + dx, 5 + dy) for (dx, dy) in near_offsets(m, 1.5)]
    @test set_neighbors!(m, a) === a.neighbors
    @test a.neighbors == found
    # A stale list is replaced, not appended to.
    set_neighbors!(m, a)
    @test length(a.neighbors) == 8
end

@testset "R = 3 counts (2, 2) and not (3, 1)" begin
    m = radius_world(3.0)
    a = put_agent(m, 5, 5)
    in_reach = put_agent(m, 7, 7)   # √8 ≈ 2.83 ≤ 3
    beyond = put_agent(m, 8, 6)     # √10 ≈ 3.16 > 3
    edge = put_agent(m, 5, 8)       # exactly 3 on an axis
    found = neighbors_of(m, a)
    @test in_reach in found && edge in found
    @test !(beyond in found)
    @test length(found) == 2
    @test length(near_offsets(m, 3.0)) == 28
end

@testset "neighbours wrap round the torus" begin
    m = radius_world(1.5)
    a = put_agent(m, 0, 0)
    corner = put_agent(m, 11, 11)
    far = put_agent(m, 10, 10)
    found = neighbors_of(m, a)
    @test found == [corner]
    @test !(far in found)
end

@testset "R = 1 keeps the book's von Neumann neighbours" begin
    m = radius_world(1.0)
    a = put_agent(m, 5, 5)
    put_agent(m, 6, 6)
    e = put_agent(m, 6, 5)
    w = put_agent(m, 4, 5)
    n = put_agent(m, 5, 6)
    s = put_agent(m, 5, 4)
    @test neighbors_of(m, a) == [e, w, n, s]   # E, W, N, S: the book's order
end

@testset "radius_neighbors! fills the buffer in place" begin
    m = radius_world(1.5)
    a = put_agent(m, 5, 5)
    b = put_agent(m, 6, 6)
    out = Agent[a]   # junk to be cleared
    @test radius_neighbors!(out, m, a) === out
    @test out == [b]
end

@testset "a child is born within R of a parent" begin
    m = radius_world(1.5; sex=true)
    f, h = couple(m)   # (2, 2) and (2, 3)
    # Block every von Neumann site of both parents, so only the diagonal sites are open: the book would find no room.
    for (x, y) in [(1, 2), (3, 2), (2, 1), (1, 3), (3, 3), (2, 4)]
        put_agent(m, x, y)
    end
    sites = Tuple{Int,Int}[]
    radius_empty_sites!(sites, m, f)
    radius_empty_sites!(sites, m, h)
    @test sort(sites) == sort([(1, 1), (3, 1), (1, 4), (3, 4)])
    kids = mate!(m, f)
    @test length(kids) == 1
    k = kids[1]
    near_parent(p) = torus_dist(12, 12, k.x, k.y, p.x, p.y) <= 1.5
    @test near_parent(f) || near_parent(h)
    @test (k.x, k.y) in [(1, 1), (3, 1), (1, 4), (3, 4)]
end

@testset "empty sites keep the parents' order and are not repeated" begin
    m = radius_world(1.5; sex=true)
    f, h = couple(m)
    sites = Tuple{Int,Int}[]
    radius_empty_sites!(sites, m, f)
    radius_empty_sites!(sites, m, h)
    @test allunique(sites)
    @test length(sites) == 8 + 8 - 2 - 4   # both Moore rings, less the two parents' sites and the four shared
    expected = [(2 + dx, 2 + dy) for (dx, dy) in near_offsets(m, 1.5)]
    @test sites[1:length(filter(s -> s != (2, 3), expected))] ==
        filter(s -> s != (2, 3), expected)
end

@testset "R = 3 places a child up to 3 away" begin
    m = radius_world(3.0; sex=true)
    f, h = couple(m)
    # Fill everything within 2 of the pair; only sites between 2 and 3 away stay open.
    for x in 0:11, y in 0:11
        m.grid[x + 1, y + 1] === nothing || continue
        d = min(torus_dist(12, 12, x, y, 2, 2), torus_dist(12, 12, x, y, 2, 3))
        d < 2.5 && put_agent(m, x, y)
    end
    kids = mate!(m, f)
    @test length(kids) == 1
    k = kids[1]
    d = min(torus_dist(12, 12, k.x, k.y, 2, 2), torus_dist(12, 12, k.x, k.y, 2, 3))
    @test 2.5 <= d <= 3.0
end

@testset "R = 1.5: trade with a diagonal neighbour" begin
    # Fig IV-2 endowments: the pair trades under T. The partner is only diagonal.
    function pair(R)
        m = tiny_model(
            ones(Int, 8, 8); spice=true, trade=true, xxl=XxlRules(; interaction_radius=R)
        )
        a = put_agent(m, 3, 3; sugar=5.0)
        a.spice, a.spice_metabolism = 8.0, 1
        b = put_agent(m, 4, 4; sugar=15.0)
        b.spice, b.spice_metabolism = 2.0, 1
        return m, a, b
    end
    m, a, b = pair(1.5)
    trade_with_neighbors!(m, a)
    @test !isempty(m.trade_log)
    @test a.sugar != 5.0 && b.sugar != 15.0
    @test a.sugar + b.sugar ≈ 20.0
    m, a, b = pair(1.0)
    trade_with_neighbors!(m, a)
    @test isempty(m.trade_log) && a.sugar == 5.0   # the book: the diagonal is not a neighbour
end
