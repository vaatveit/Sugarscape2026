# The hot paths' shortcuts each give what the long way gives: test_xxl_same_run.jl pins whole runs, these the reasoning.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Random: Xoshiro, shuffle!

# A world of two commodities on a random map, with one agent in the middle of it.
function fast_world(seed; M=6, S=4, V=8, c=0.1, kw...)
    cap = rand(Xoshiro(seed), 0:4, 40, 40)
    rules = XxlRules(; vision_shape="disc", speed=(S, S), travel_cost=c, memory=M, memory_span=50)
    m = tiny_model(cap; xxl=rules, vision=(V, V), spice=true, kw...)
    a = put_agent(m, 20, 20; vision=V, sugar=30.0)
    a.spice, a.spice_metabolism, a.speed = 25.0, 2, S
    return m, a
end

@testset "wrap_one is mod, without the division" begin
    @test all(Sugarscape.wrap_one(x, n) == mod(x, n) for n in (1, 2, 7, 50, 500) for x in (-3n):(3n))
    @test Sugarscape.wrap_one(typemin(Int) + 1, 7) == mod(typemin(Int) + 1, 7)
end

@testset "torus_delta: the signed shortest offset" begin
    long_way(w, x1, x2) = (d = mod(x2 - x1, w); 2d > w ? d - w : d)
    @test all(
        Sugarscape.torus_delta(w, x1, x2) == long_way(w, x1, x2) for w in (1, 2, 7, 50) for x1 in (-2w):(2w) for
        x2 in (-2w):(2w)
    )
end

@testset "travel_periods: within speed needs no division" begin
    @test all(Sugarscape.travel_periods(d, S) == max(1, ceil(Int, d / S)) for S in 1:7 for d in 0:0.25:30)
    @test Sugarscape.travel_periods(100.0, 0) == 1
end

@testset "net_parts: the arguments of net_value's two powers" begin
    m, a = fast_world(1)
    rng = Xoshiro(2)
    for _ in 1:2000
        a.sugar, a.spice = 40 * rand(rng), 40 * rand(rng)
        d, sugar, spice = 12 * rand(rng), 5 * rand(rng), 5 * rand(rng)
        sw = Sugarscape.SiteWelfare(m, a)
        A, B = Sugarscape.net_parts(a, sw, Sugarscape.sugar_burn(a), 0.1, 0.0, d, sugar, spice)
        v = Sugarscape.net_value(a, sw, true, 0.1, 0.0, d, sugar, spice)
        @test A < 0 ? v == -Inf : v === A^sw.e1 * B^sw.e2
    end
end

@testset "surely_less only says so of a site worth less" begin
    rng = Xoshiro(3)
    said = 0
    for _ in 1:200_000
        e1 = rand(rng)
        e2 = 1 - e1
        pick() = rand(rng) < 0.05 ? 0.0 : (rand(rng) < 0.05 ? 1.0 : 40 * rand(rng))
        A, B, Ar, Br = pick(), pick(), pick(), pick()
        c1, c2 = Sugarscape.prune_weights(e1, e2, Ar, Br)
        Sugarscape.surely_less(c1, c2, A, B) || continue
        said += 1
        A^e1 * B^e2 < Ar^e1 * Br^e2 || @test false
    end
    @test said > 10_000
    # Worth the same is not worth less: a tie goes on to the rule that breaks it.
    c1, c2 = Sugarscape.prune_weights(0.3, 0.7, 5.0, 9.0)
    @test !Sugarscape.surely_less(c1, c2, 5.0, 9.0)
    # A reference worth nothing rules nothing out, whatever the other coefficient says.
    c1, c2 = Sugarscape.prune_weights(0.3, 0.7, 0.0, 9.0)
    @test !Sugarscape.surely_less(c1, c2, 0.0, 1.0) && !Sugarscape.surely_less(c1, c2, 1.0, 1.0)
end

@testset "rank_pool! keeps what ranking every entry would" begin
    for seed in 1:40
        m, a = fast_world(seed; M=5)
        rng = Xoshiro(seed)
        a.sugar, a.spice = 2 + 30 * rand(rng), 2 + 30 * rand(rng)
        pool = empty!(m.pool)
        for _ in 1:60
            s = rand(rng) < 0.3 ? 2.0 : 6 * rand(rng)  # some of equal worth, for the ties
            push!(pool, Remembered(rand(rng, 0:39), rand(rng, 0:39), s, s, rand(rng) < 0.5 ? 0.0 : rand(rng), rand(rng, 0:3)))
        end
        Sugarscape.rank_pool!(m, a)
        value(e) = net_value(m, a, e.x, e.y, Sugarscape.torus_dist(40, 40, a.x, a.y, e.x, e.y), e.sugar / (1 + e.pollution), e.spice / (1 + e.pollution))
        ranked = sort(pool; lt=(e, f) -> Sugarscape.ranks_above(value(e), e, value(f), f))
        @test a.memory == ranked[1:5]
        @test m.pool_values == value.(ranked[1:5])
    end
end

@testset "rank_pool! with a disease fee that isn't whole" begin
    m, a = fast_world(1; M=3)
    a.disease_fee = 0.5
    push!(a.diseases, 1)
    @test Sugarscape.sugar_burn(a) == 1.5
    pool = empty!(m.pool)
    for (s, x) in ((1.0, 1), (5.0, 2), (3.0, 3), (2.0, 4))
        push!(pool, Remembered(x, 0, s, s, 0.0, 0))
    end
    Sugarscape.rank_pool!(m, a)
    @test [e.x for e in a.memory] == [2, 3, 4]
end

@testset "remember! gives what pooling every entry would" begin
    # The long way: the fresh sites, then the entries still in date that no fresh site replaces, all through Sugarscape.rank_pool!.
    function pooled!(m, a)
        ls, pool = m.landscape, empty!(m.pool)
        push!(pool, Sugarscape.seen(ls, m.config.spice, a.x, a.y, m.t))
        for (x, y) in m.looked
            (x, y) == (a.x, a.y) || push!(pool, Sugarscape.seen(ls, m.config.spice, x, y, m.t))
        end
        fresh = length(pool)
        for e in a.memory
            m.t - e.t > m.config.xxl.memory_span && continue
            any(p -> (p.x, p.y) == (e.x, e.y), view(pool, 1:fresh)) || push!(pool, e)
        end
        return Sugarscape.rank_pool!(m, a)
    end
    for seed in 1:40
        m, a = fast_world(seed; M=6)
        rng = Xoshiro(seed)
        m.t = 60
        a.sugar, a.spice = 2 + 30 * rand(rng), 2 + 30 * rand(rng)
        Sugarscape.look!(m, a)
        for _ in 1:6  # some out of date, some on sites just looked at, and the site it stands on
            x, y = rand(rng) < 0.4 ? rand(rng, m.looked) : (rand(rng, 0:39), rand(rng, 0:39))
            push!(a.memory, Remembered(x, y, 6 * rand(rng), 6 * rand(rng), rand(rng), rand(rng, 5:60)))
        end
        old = copy(a.memory)
        pooled!(m, a)
        expected = copy(a.memory)
        a.memory = old
        @test Sugarscape.remember!(m, a) == expected
    end
    # Without both commodities in the ranking, the same answer the same way.
    m, a = fast_world(1; M=4)
    a.spice_metabolism = 0
    Sugarscape.look!(m, a)
    pooled!(m, a)
    expected = copy(a.memory)
    empty!(a.memory)
    @test Sugarscape.remember!(m, a) == expected
end

@testset "welfare_rises answers as comparing the two welfares does" begin
    m, a = fast_world(1)
    rng = Xoshiro(5)
    for cultural in (false, true), _ in 1:50_000
        a.tags, a.ntags = rand(rng, UInt64) & 0xff, 8
        s0, p0 = rand(rng) < 0.02 ? 0.0 : 30 * rand(rng), rand(rng) < 0.02 ? 0.0 : 30 * rand(rng)
        near = rand(rng) < 0.5  # a trade's small steps, where the two welfares are close
        s1, p1 = near ? (s0 + 1e-7 * rand(rng), p0 - 1e-7 * rand(rng)) : (s0 + rand(rng), p0 - rand(rng))
        (s1 > 0 && p1 > 0) || continue
        Sugarscape.welfare_rises(a, s1, p1, s0, p0, cultural) ==
        (Sugarscape.welfare(a, s1, p1, cultural) > Sugarscape.welfare(a, s0, p0, cultural)) || @test false
    end
    @test true
end
