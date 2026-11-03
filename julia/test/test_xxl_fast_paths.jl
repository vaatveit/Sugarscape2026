# The hot paths' shortcuts each give what the long way gives: test_xxl_same_run.jl pins whole runs, these the reasoning.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Random: Xoshiro, shuffle!

# A world of two commodities on a random map, with one agent in the middle of it.
function fast_world(seed; M=6, S=4, V=8, c=0.1, side=40, kw...)
    cap = rand(Xoshiro(seed), 0:4, side, side)
    rules = XxlRules(; vision_shape="disc", speed=(S, S), travel_cost=c, memory=M, memory_span=50)
    m = tiny_model(cap; xxl=rules, vision=(V, V), spice=true, kw...)
    a = put_agent(m, side ÷ 2, side ÷ 2; vision=V, sugar=30.0)
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
        m1 = Sugarscape.sugar_burn(a)
        A, B = Sugarscape.net_parts(a, sw, m1, 0.1, 0.0, d, sugar, spice)
        v = Sugarscape.net_value(a, sw, true, 0.1, 0.0, d, sugar, spice)
        # The rule as written out: the arrival's holdings after the trip and the wait.
        wait = max(1, ceil(Int, d / a.speed)) - 1
        trip = 0.1 * d
        if a.sugar - trip - m1 * wait <= 0 || a.spice - 2 * wait <= 0
            @test (A, B) == (-1.0, -1.0) && v == -Inf
        else
            @test A === max(sw.base1 - trip - m1 * wait + sugar, 0.0)
            @test B === max(sw.base2 - 2 * wait + spice, 0.0)
            @test v === A^sw.e1 * B^sw.e2
        end
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
    # Worth the same is not worth less: a tie goes on to the rule that breaks it, and so does anything near one.
    rng = Xoshiro(4)
    tie, near, clear = 0, 0, 0
    for _ in 1:100_000
        e1 = rand(rng)
        e2, Ar, Br = 1 - e1, 40 * rand(rng), 40 * rand(rng)
        c1, c2 = Sugarscape.prune_weights(e1, e2, Ar, Br)
        tie += Sugarscape.surely_less(c1, c2, Ar, Br)
        near += Sugarscape.surely_less(c1, c2, Ar * (1 - 1e-12), Br * (1 - 1e-12))
        clear += Sugarscape.surely_less(c1, c2, Ar * (1 - 1e-6), Br * (1 - 1e-6))
    end
    @test (tie, near, clear) == (0, 0, 100_000)
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
    wrong = 0
    for cultural in (false, true), _ in 1:50_000
        a.tags, a.ntags = rand(rng, UInt64) & 0xff, 8
        s0, p0 = rand(rng) < 0.02 ? 0.0 : 30 * rand(rng), rand(rng) < 0.02 ? 0.0 : 30 * rand(rng)
        near = rand(rng) < 0.5  # a trade's small steps, where the two welfares are close
        s1, p1 = near ? (s0 + 1e-7 * rand(rng), p0 - 1e-7 * rand(rng)) : (s0 + rand(rng), p0 - rand(rng))
        (s1 > 0 && p1 > 0) || continue
        rises = Sugarscape.welfare_rises(a, s1, p1, s0, p0, cultural)
        wrong += rises != (Sugarscape.welfare(a, s1, p1, cultural) > Sugarscape.welfare(a, s0, p0, cultural))
    end
    @test wrong == 0
end

@testset "count_in_sight: the same partners on the same draws as the look" begin
    # From the corner of a small map the look crosses its edges. (A look can't be wider than half the map: `validate`.)
    for seed in 1:30, (S, V, side) in ((4, 8, 40), (2, 15, 40), (0, 6, 40), (5, 5, 40), (2, 4, 9), (3, 5, 11), (1, 2, 5))
        m, a = fast_world(seed; S=max(S, 1), V=V, side=side)
        a.speed = S
        side < 40 && move_agent!(m, a, 0, side - 1)
        rng = Xoshiro(seed)
        for _ in 1:(side * side ÷ 5)
            x, y = rand(rng, 0:(side - 1)), rand(rng, 0:(side - 1))
            m.grid[x + 1, y + 1] === nothing && put_agent(m, x, y)
        end
        before = copy(m.rng)
        expected = length(Sugarscape.disc_in_sight(m, a))
        after = copy(m.rng)
        m.rng = before
        @test Sugarscape.count_in_sight(m, a) == expected
        @test m.rng == after
    end
end

@testset "an infertile agent's mate search: the draws and nothing else" begin
    m, a = fast_world(4; sex=true)
    a.sex, a.fertility_start, a.fertility_end, a.age = :F, 12, 40, 5  # too young
    rng = Xoshiro(4)
    for _ in 1:300
        x, y = rand(rng, 0:39), rand(rng, 0:39)
        if m.grid[x + 1, y + 1] === nothing
            b = put_agent(m, x, y; sugar=1000.0)
            b.sex, b.fertility_start, b.fertility_end, b.age = :M, 12, 40, 20
        end
    end
    for _ in 1:50
        before = copy(m.rng)
        shuffle!(m.rng, Sugarscape.disc_in_sight(m, a))
        after = copy(m.rng)
        m.rng = before
        n = length(m.agents)
        @test isempty(mate!(m, a))
        @test m.rng == after && length(m.agents) == n
        @test isempty(m.sight)  # no one left over for a checkpoint to save
    end
end

@testset "a death's loans settle without copying the book" begin
    function book(; kw...)
        m = tiny_model(ones(Int, 200, 200); sex=true, credit=(10, 10.0), fertility_threshold=1.0, kw...)
        people = [put_agent(m, x, y; sugar=10.0) for x in 0:199 for y in 0:9]
        rng = Xoshiro(6)
        for _ in 1:20_000
            lender, borrower = rand(rng, people), rand(rng, people)
            lender === borrower || Sugarscape.add_loan!(m, Sugarscape.Loan(lender, borrower, 1.0, 2.0, 10))
        end
        return m, people
    end
    m, people = book()
    Sugarscape.credit_on_deaths!(m, Set(people[1:2]), ())  # compiled, and a first look at it
    dying = Set(people[3:4])
    gone = count(l -> l.lender in dying || l.borrower in dying, m.loans)
    n = length(m.loans)
    @test (@allocated Sugarscape.credit_on_deaths!(m, dying, ())) < 20_000
    @test length(m.loans) == n - gone
    @test !any(l -> l.lender in dying || l.borrower in dying, m.loans)
    # The index still says what the book says, in its order.
    @test all(m.debts[id] == filter(l -> l.borrower.id == id, m.loans) for id in keys(m.debts))
    @test Set(keys(m.debts)) == Set(l.borrower.id for l in m.loans)
    @test sum(values(m.lent)) == length(m.loans)
end

@testset "a move and its ranking stay type-stable and allocate nothing" begin
    m, a = fast_world(1; M=6)
    a.sugar, a.spice = 200.0, 200.0
    Sugarscape.speed_move!(m, a)
    Sugarscape.remember!(m, a)
    Sugarscape.count_in_sight(m, a)
    @test (@inferred Sugarscape.speed_move!(m, a)) === nothing
    @test (@allocated Sugarscape.remember!(m, a)) == 0
    @test (@allocated Sugarscape.rank_pool!(m, a)) == 0
    @test (@allocated Sugarscape.count_in_sight(m, a)) == 0
    @test (@allocated Sugarscape.speed_move!(m, a)) == 0
end

@testset "neighbors_of reuses a list" begin
    m, a = fast_world(1; sex=true)
    put_agent(m, 21, 20)
    neighbors_of(m, a)
    @test (@allocated neighbors_of(m, a)) == 0
    @test neighbors_of(m, a) === m.sight
end

@testset "the society metrics use no list per agent" begin
    m, a = fast_world(1; culture=true, tag_length=7)
    for x in 0:39, y in 0:9
        b = put_agent(m, x, y)
        b.tags, b.ntags = rand(Xoshiro(x + 40y), UInt64) & 0xff, 8
        push!(a.friends, (b, 0))
        push!(b.friends, (a, 0))
    end
    a.tags, a.ntags = UInt64(0xf0), 8
    out = Float64[]
    Sugarscape.society_metrics!(out, m)
    empty!(out)
    each = (@allocated Sugarscape.society_metrics!(out, m)) / length(m.agents)
    @test each < 200
end
