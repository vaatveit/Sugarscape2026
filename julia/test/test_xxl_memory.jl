# xxl rule 3: memory and word of mouth (spec, "Memory and word of mouth"). Uses `remember!`, `word_of_mouth!` and the
# remembered candidates of `speed_move!` / `look!`.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Random: Xoshiro

# Rules with speed S (no spread), travel cost c, memory M and the disc look.
function mem_rules(; S=5, c=0.1, M=8, wom=false, span=50, shape="disc")
    return XxlRules(;
        vision_shape=shape,
        speed=(S, S),
        travel_cost=c,
        memory=M,
        memory_span=span,
        word_of_mouth=wom,
    )
end

# A model on the capacity grid `cap` with one agent at (x, y): vision V, speed S, holding `sugar`.
function mem_world(
    cap, x, y; S=5, V=S, c=0.1, M=8, wom=false, sugar=100.0, span=50, shape="disc", kw...
)
    m = tiny_model(cap; xxl=mem_rules(; S, c, M, wom, span, shape), vision=(V, V), kw...)
    a = put_agent(m, x, y; vision=V, sugar=sugar)
    a.speed = S
    return m, a
end

# The remembered entry for site (x, y) in `a`'s memory, or nothing.
entry_at(a, x, y) = findfirst(e -> (e.x, e.y) == (x, y), a.memory)

@testset "trim and rank" begin
    cap = zeros(Int, 30, 30)
    m, a = mem_world(cap, 10, 10; S=5, c=0.0, M=3)
    for (x, y, s) in ((13, 10, 4.0), (11, 10, 3.0), (9, 10, 2.0), (10, 8, 1.0))
        m.landscape.sugar[x + 1, y + 1] = s
    end
    move!(m, a)
    @test (a.x, a.y) == (13, 10)   # onto the richest, which it harvested
    @test length(a.memory) == 3
    @test [(e.x, e.y) for e in a.memory] == [(11, 10), (9, 10), (10, 8)]
    @test [e.sugar for e in a.memory] == [3.0, 2.0, 1.0]
    @test all(e -> e.t == m.t, a.memory)

    # In general: the kept entries are the best by net value from the new position, best first.
    cap = rand(Xoshiro(3), 0:4, 40, 40)
    m, a = mem_world(cap, 20, 20; S=4, V=8, c=0.1, M=5, sugar=30.0)
    move!(m, a)
    ls = m.landscape
    function value(x, y)
        d = Sugarscape.torus_dist(40, 40, a.x, a.y, x, y)
        dv = 1 + ls.pollution[x + 1, y + 1]
        return net_value(m, a, x, y, d, ls.sugar[x + 1, y + 1] / dv, 0.0)
    end
    sites = unique(vcat(copy(m.looked), [(a.x, a.y)]))
    ranked = sort(sites; by=s -> (-value(s...), s))   # all of equal period: ties by (x, y)
    @test [(e.x, e.y) for e in a.memory] == ranked[1:5]
end

@testset "span" begin
    cap = zeros(Int, 200, 20)
    m, a = mem_world(cap, 10, 10; S=5, V=5, c=0.1, M=8, span=50)
    m.t = 100
    empty!(m.looked)
    a.memory = [
        Remembered(40, 10, 50.0, 0.0, 0.0, 49),   # 51 periods ago: gone
        Remembered(60, 10, 50.0, 0.0, 0.0, 50),   # 50 periods ago: kept
        Remembered(80, 10, 50.0, 0.0, 0.0, 100),
    ]
    remember!(m, a)
    @test entry_at(a, 40, 10) === nothing
    @test entry_at(a, 60, 10) !== nothing
    @test entry_at(a, 80, 10) !== nothing
end

@testset "harvested site" begin
    cap = zeros(Int, 30, 30)
    m, a = mem_world(cap, 10, 10; S=5, c=0.1, M=200)   # room for every site it looked at
    m.landscape.sugar[13, 11] = 4.0   # (12, 10)
    a.memory = [Remembered(12, 10, 4.0, 0.0, 0.0, 0)]   # an old entry for the same site
    move!(m, a)
    @test (a.x, a.y) == (12, 10)
    @test count(e -> (e.x, e.y) == (12, 10), a.memory) == 1
    e = a.memory[entry_at(a, 12, 10)]
    @test e.sugar == 0.0
    @test e.t == m.t

    # A site landed on without being looked at (a walk's step off the lattice's axes) is stored too, as it is after
    # harvest.
    cap = zeros(Int, 100, 60)
    m, a = mem_world(cap, 10, 10; S=5, V=6, c=0.1, M=200, shape="lattice")
    a.memory = [Remembered(40, 30, 100.0, 0.0, 0.0, 0)]   # 36 away, toward (0.83, 0.55)
    m.landscape.sugar[15, 14] = 9.0   # (14, 13): where the walk lands
    move!(m, a)
    @test a.target_remembered
    @test (a.x, a.y) == (14, 13)
    @test !((14, 13) in m.looked)
    e = a.memory[entry_at(a, 14, 13)]
    @test e.sugar == 0.0 && e.t == m.t
end

@testset "beyond vision" begin
    cap = zeros(Int, 100, 30)
    m, a = mem_world(cap, 10, 10; S=5, V=10, c=0.1, M=4)
    a.memory = [Remembered(50, 10, 100.0, 0.0, 0.0, 0)]   # 40 away, vision 10
    move!(m, a)
    @test a.target_remembered
    @test (a.x, a.y) == (15, 10)
    @test a.moved_dist == 5.0
    @test entry_at(a, 50, 10) !== nothing   # still remembered
    xs = Int[]
    for _ in 1:3
        m.t += 1
        move!(m, a)
        push!(xs, a.x)
    end
    @test xs == [20, 25, 30]
    @test a.target_remembered

    # Nothing remembered and nothing in sight: no target.
    m, a = mem_world(cap, 10, 10; S=5, V=10, c=0.1, M=4)
    move!(m, a)
    @test !a.target_remembered
    @test (a.x, a.y) == (10, 10)

    # Memory off: the remembered site is not an option, there is no memory to hold it.
    m = tiny_model(
        cap;
        xxl=XxlRules(; vision_shape="disc", speed=(5, 5), travel_cost=0.1),
        vision=(10, 10),
    )
    a = put_agent(m, 10, 10; vision=10, sugar=100.0)
    a.speed = 5
    a.memory = [Remembered(50, 10, 100.0, 0.0, 0.0, 0)]
    move!(m, a)
    @test !a.target_remembered
    @test (a.x, a.y) == (10, 10)
end

@testset "a remembered site is devalued by its pollution" begin
    cap = zeros(Int, 100, 30)
    m, a = mem_world(cap, 10, 10; S=5, V=6, c=0.0, M=4)
    # Two far entries with equal raw sugar: the unpolluted one is worth twice the polluted one.
    a.memory = [
        Remembered(10, 18, 60.0, 0.0, 1.0, 0),   # 8 away, polluted
        Remembered(48, 10, 60.0, 0.0, 0.0, 0),   # 38 away, clean
    ]
    move!(m, a)
    @test a.target_remembered
    @test a.x > 10   # toward the clean one, though it is farther
end

@testset "occupied remembered site within vision" begin
    ok = true
    for trial in 1:40
        cap = zeros(Int, 40, 30)
        m, a = mem_world(cap, 10, 10; S=3, V=8, c=0.1, M=4, seed=trial)
        b = put_agent(m, 16, 10; vision=1)   # stands on the remembered site, 6 away
        m.landscape.sugar[11, 14] = 2.0   # (10, 13): the only real food in sight
        a.memory = [Remembered(16, 10, 100.0, 0.0, 0.0, 0)]
        move!(m, a)
        ok &= (a.x, a.y) == (10, 13) && !a.target_remembered && m.grid[17, 11] === b
    end
    @test ok
end

@testset "occupied beyond vision" begin
    cap = zeros(Int, 100, 30)
    m, a = mem_world(cap, 10, 10; S=5, V=10, c=0.1, M=4)
    target = put_agent(m, 50, 10; vision=1)   # sits on the remembered site: it can't be seen from here
    block = put_agent(m, 15, 10; vision=1)   # and the farthest step toward it is taken too
    a.memory = [Remembered(50, 10, 100.0, 0.0, 0.0, 0)]
    move!(m, a)
    @test a.target_remembered
    @test (a.x, a.y) == (14, 10)
    @test m.grid[51, 11] === target && m.grid[16, 11] === block

    # Wherever it is headed, it never lands on an occupied site.
    ok = true
    for trial in 1:30
        m, a = mem_world(cap, 10, 10; S=5, V=10, c=0.1, M=4, seed=trial)
        crowd = [
            put_agent(m, 10 + dx, 10 + dy; vision=1) for
            (dx, dy) in ((5, 0), (4, 0), (3, 0))
        ]
        a.memory = [Remembered(50, 10, 100.0, 0.0, 0.0, 0)]
        move!(m, a)
        ok &= a.target_remembered && (a.x, a.y) == (12, 10) && all(c -> c.x > a.x, crowd)
    end
    @test ok
end

@testset "two valuers" begin
    cap = zeros(Int, 30, 30)
    m = tiny_model(cap; spice=true, xxl=mem_rules(; S=6, c=0.0, M=2), vision=(6, 6))
    sugar_poor = put_agent(m, 10, 10; vision=6, sugar=5.0)
    spice_poor = put_agent(m, 11, 10; vision=6, sugar=100.0)
    for (a, spice) in ((sugar_poor, 100.0), (spice_poor, 5.0))
        a.speed = 6
        a.spice_metabolism = 1
        a.spice = spice
        a.foresight = 0
    end
    sugary = Remembered(13, 10, 10.0, 0.0, 0.0, 0)
    spicy = Remembered(10, 13, 0.0, 10.0, 0.0, 0)
    for a in (sugar_poor, spice_poor)
        a.memory = [sugary, spicy]
        empty!(m.looked)
        remember!(m, a)
    end
    # The agent short of sugar puts the sugary site first; the one short of spice, the spicy one.
    @test (sugar_poor.memory[1].x, sugar_poor.memory[1].y) == (13, 10)
    @test (spice_poor.memory[1].x, spice_poor.memory[1].y) == (10, 13)
    @test length(sugar_poor.memory) == length(spice_poor.memory) == 2
end

@testset "dropped entries rank last" begin
    cap = zeros(Int, 200, 20)
    m, a = mem_world(cap, 10, 10; S=5, V=5, c=0.1, M=3, sugar=3.0)
    a.metabolism = 1
    near = Remembered(11, 10, 1.0, 0.0, 0.0, 0)
    far = Remembered(100, 10, 500.0, 0.0, 0.0, 0)   # 90 away: the agent would starve on the way
    a.memory = [far, near]
    empty!(m.looked)
    remember!(m, a)
    @test length(a.memory) == 3
    @test entry_at(a, 100, 10) !== nothing   # kept: fewer than M finite entries exist
    @test a.memory[end] == far
end

@testset "word of mouth" begin
    cap = zeros(Int, 100, 30)
    function pair(; wom=true, seed=1)
        m = tiny_model(cap; xxl=mem_rules(; S=1, c=0.1, M=3, wom), vision=(1, 1), seed)
        a = put_agent(m, 10, 10; vision=1, sugar=50.0)
        b = put_agent(m, 11, 10; vision=1, sugar=50.0)
        a.speed = b.speed = 0   # neither can move: they stay neighbours
        return m, a, b
    end
    best = Remembered(60, 10, 200.0, 0.0, 0.0, 7)
    other = Remembered(70, 10, 10.0, 0.0, 0.0, 6)

    @testset "copies the neighbour's first entry" begin
        m, a, b = pair()
        m.t = 8
        b.memory = [best, other]
        Sugarscape.set_neighbors!(m, a)
        word_of_mouth!(m, a)
        @test best in a.memory   # with its own period
        @test !(other in a.memory)   # only the first
        @test a.memory[1] == best
        @test b.memory == [best, other]   # the neighbour's memory is untouched
    end

    @testset "in a period" begin
        for trial in 1:10   # either acting order
            m, a, b = pair(; seed=trial)
            m.t = 8
            b.memory = [best, other]
            step!(m)
            @test best in a.memory
        end
        m, a, b = pair(; wom=false)
        b.memory = [best, other]
        step!(m)
        @test !(best in a.memory)   # word of mouth off
    end

    @testset "expired news is not copied" begin
        m, a, b = pair()
        m.t = 100
        b.memory = [Remembered(60, 10, 200.0, 0.0, 0.0, 40)]
        Sugarscape.set_neighbors!(m, a)
        word_of_mouth!(m, a)
        @test entry_at(a, 60, 10) === nothing
    end

    @testset "no neighbours, no news" begin
        m, a, b = pair()
        c = put_agent(m, 50, 15; vision=1)
        c.speed = 0
        c.memory = [best]
        Sugarscape.set_neighbors!(m, a)
        word_of_mouth!(m, a)
        @test isempty(a.memory)
    end
end

@testset "one entry per site" begin
    cap = zeros(Int, 40, 20)
    m = tiny_model(cap; xxl=mem_rules(; S=2, c=0.1, M=8, wom=true), vision=(2, 2))
    a = put_agent(m, 10, 10; vision=2, sugar=50.0)
    b = put_agent(m, 9, 10; vision=2, sugar=50.0)
    c = put_agent(m, 11, 10; vision=2, sugar=50.0)
    a.speed = b.speed = c.speed = 0
    m.landscape.sugar[11, 12] = 3.0   # (10, 11): next to a, so always looked at
    site = (10, 11)
    move!(m, a)   # period 0: looked at
    @test a.memory[entry_at(a, site...)].t == 0
    m.t = 1
    move!(m, a)   # period 1: looked at again
    @test count(e -> (e.x, e.y) == site, a.memory) == 1
    @test a.memory[entry_at(a, site...)].t == 1

    # Heard of, once with an older period (b) and once with a newer one (c): memory holds it once, the newest.
    b.memory = [Remembered(site..., 3.0, 0.0, 0.0, 0)]
    m.t = 2
    Sugarscape.set_neighbors!(m, a)
    word_of_mouth!(m, a)
    @test count(e -> (e.x, e.y) == site, a.memory) == 1
    @test a.memory[entry_at(a, site...)].t == 1   # a's own look is newer than b's news
    c.memory = [Remembered(site..., 3.0, 0.0, 0.0, 2)]
    word_of_mouth!(m, a)
    @test count(e -> (e.x, e.y) == site, a.memory) == 1
    @test a.memory[entry_at(a, site...)].t == 2
    # A fresh look beats an entry of the same period.
    m.t = 2
    m.landscape.sugar[11, 12] = 1.0
    move!(m, a)
    @test count(e -> (e.x, e.y) == site, a.memory) == 1
    @test a.memory[entry_at(a, site...)].sugar == 1.0
end

@testset "look! adds remembered sites within vision" begin
    cap = zeros(Int, 60, 40)
    for shape in ("disc", "lattice")
        rules = XxlRules(;
            vision_shape=shape, speed=(3, 3), travel_cost=0.1, memory=4, word_of_mouth=false
        )
        m = tiny_model(cap; xxl=rules, vision=(8, 8))
        a = put_agent(m, 30, 20; vision=8)
        a.speed = 3
        inside = Remembered(36, 24, 5.0, 0.0, 0.0, 0)   # 7.2 away
        outside = Remembered(38, 24, 5.0, 0.0, 0.0, 0)   # 8.9 away
        a.memory = [inside, outside]
        ok = true
        for _ in 1:30
            sites = look!(m, a)
            ok &= (36, 24) in sites && !((38, 24) in sites) && allunique(sites)
        end
        @test ok
        shape == "lattice" &&
            @test !((36, 24) in look!(m.looked, m, a, a.x, a.y; memory=false))
    end
end
