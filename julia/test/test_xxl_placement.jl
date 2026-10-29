# xxl (revised): viable founder placement (docs/superpowers/specs/2026-10-29-xxl-revised-design.md, "Stage 1:
# survival", change 2). A founder or rule-R newcomer draws its traits first, then a uniformly random empty site that
# feeds it; when none of its candidate sites is left, it takes any empty one of them and the run counts a fallback.
using Sugarscape, Test
using Sugarscape: viable
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

# The test's own reading of the rule: site (x, y) feeds metabolism pair `p` when its sugar capacity is ≥ p[1] and, with
# spice, its spice capacity is ≥ p[2].
function placement_feeds(m, p, x, y)
    ls = m.landscape
    ok = ls.capacity[x + 1, y + 1] >= p[1]
    return m.config.spice ? ok && ls.spice_capacity[x + 1, y + 1] >= p[2] : ok
end
placement_pair(m, a) = (a.metabolism, m.config.spice ? a.spice_metabolism : 0)

# Replays the founders' placement in id order. `groups` maps a key to its candidate sites (disjoint), `group_of(a)` is a
# founder's key. Returns (misplaced, expected, disagree): founders on a site that does not feed them although one of
# their candidates was free, or on one that feeds them although none was; the number placed when no feeding candidate
# was free; and founders on whose site `viable` disagrees with the test's reading.
function replay_placement(m, founders, groups, group_of)
    pairs = unique(placement_pair(m, a) for a in founders)
    left = Dict(
        g => Dict(p => count(s -> placement_feeds(m, p, s...), sites) for p in pairs) for
        (g, sites) in groups
    )
    misplaced = expected = disagree = 0
    for a in sort(founders; by=a -> a.id)
        g, p = group_of(a), placement_pair(m, a)
        fed = placement_feeds(m, p, a.x, a.y)
        fed == viable(m, a, a.x, a.y) || (disagree += 1)
        if left[g][p] == 0
            expected += 1
            fed && (misplaced += 1)
        else
            fed || (misplaced += 1)
        end
        for q in pairs
            placement_feeds(m, q, a.x, a.y) && (left[g][q] -= 1)
        end
    end
    return misplaced, expected, disagree
end

# Every site of a w × h grid.
placement_grid(w, h) = [(x, y) for x in 0:(w - 1) for y in 0:(h - 1)]

@testset "xxl viable founder placement" begin
    reg = load_registry()
    viable_rules = replace_rules(XXL_V1; founder_placement="viable")
    on = XxlRules(; founder_placement="viable")

    @testset "viable reads the capacities" begin
        m = tiny_model(repeat([1, 2, 3], 1, 3); xxl=on)  # x = 0, 1, 2 have capacity 1, 2, 3
        a = put_agent(m, 0, 0; metabolism=2)
        @test !viable(m, a, 0, 0)
        @test viable(m, a, 1, 0)
        @test viable(m, a, 2, 0)
        @test m.viable_fallbacks == 0
    end

    @testset "II-4: founders stand on land that feeds them" begin
        ii4 = find_experiment(reg, "II-4")
        m = Model(to_xxl(ii4.config, viable_rules))
        @test length(m.agents) == 40_000
        misplaced, expected, disagree = replay_placement(
            m, m.agents, Dict(:grid => placement_grid(500, 500)), a -> :grid
        )
        @test disagree == 0
        @test misplaced == 0
        @test m.viable_fallbacks == expected
        @test all(a -> viable(m, a, a.x, a.y), filter(a -> a.metabolism <= 3, m.agents))
        println("II-4, viable placement: $(m.viable_fallbacks) fallbacks of 40000 founders")
    end

    @testset "VI-1 (max_metabolism 4, generated map): fed on both goods" begin
        vi1 = find_experiment(reg, "VI-1")
        rules = replace_rules(viable_rules; max_metabolism=4, landscape="generated")
        m = Model(to_xxl(vi1.config, rules))
        @test length(m.agents) == 20_000
        misplaced, expected, disagree = replay_placement(
            m, m.agents, Dict(:grid => placement_grid(500, 500)), a -> :grid
        )
        @test disagree == 0
        @test misplaced == 0
        @test m.viable_fallbacks == expected
        println("VI-1, viable placement: $(m.viable_fallbacks) fallbacks of 20000 founders")
    end

    @testset "III-9: each tribe in its own block, fed unless counted" begin
        iii9 = find_experiment(reg, "III-9")
        m = Model(to_xxl(iii9.config, viable_rules))
        blocks = m.config.initial_blocks
        groups = Dict(
            Symbol(name) => [(x0 + i, y0 + j) for i in 0:(w - 1) for j in 0:(h - 1)] for
            (name, x0, y0, w, h, n) in blocks
        )
        @test length(m.agents) == sum(b[6] for b in blocks)
        for (name, x0, y0, w, h, n) in blocks
            mine = filter(a -> tribe(a) == Symbol(name), m.agents)
            @test length(mine) == n
            @test all(a -> x0 <= a.x < x0 + w && y0 <= a.y < y0 + h, mine)
        end
        misplaced, expected, disagree = replay_placement(m, m.agents, groups, tribe)
        @test disagree == 0
        @test misplaced == 0
        @test m.viable_fallbacks == expected
        println(
            "III-9, viable placement: $(m.viable_fallbacks) fallbacks of $(length(m.agents)) founders",
        )
    end

    @testset "fallback when viable sites run out" begin
        cap = ones(Int, 5, 5)
        cap[1, 1] = cap[3, 3] = cap[5, 2] = 4  # three sites feed a metabolism of 4
        m = tiny_model(cap; initial_population=10, metabolism=(4, 4), xxl=on)
        @test length(m.agents) == 10
        @test length(Set((a.x, a.y) for a in m.agents)) == 10
        @test m.viable_fallbacks == 7
        @test count(a -> viable(m, a, a.x, a.y), m.agents) == 3
        firsts = filter(a -> a.id < 3, m.agents)  # placed while a viable site was free
        @test all(a -> viable(m, a, a.x, a.y), firsts)
    end

    @testset "block placement applies the rule within the block" begin
        cap = fill(4, 6, 6)  # every site feeds a metabolism of 4 ...
        cap[2:4, 2:4] .= 1  # ... except in the block (1, 1, 3, 3), where two do
        cap[2, 2] = cap[4, 3] = 4
        m = tiny_model(
            cap;
            initial_population=5,
            metabolism=(4, 4),
            placement="block",
            block=(1, 1, 3, 3),
            xxl=on,
        )
        @test length(m.agents) == 5
        @test all(a -> 1 <= a.x <= 3 && 1 <= a.y <= 3, m.agents)
        @test count(a -> viable(m, a, a.x, a.y), m.agents) == 2
        @test m.viable_fallbacks == 3
    end

    @testset "spawn_viable! on given sites" begin
        m = tiny_model(repeat([3, 1, 3, 1], 1, 3); metabolism=(2, 2), xxl=on)
        a = spawn_viable!(m, [(0, 0), (1, 0)])
        @test (a.x, a.y) == (0, 0) && m.viable_fallbacks == 0
        b = spawn_viable!(m, [(0, 0), (1, 0)])
        @test (b.x, b.y) == (1, 0) && m.viable_fallbacks == 1
        @test m.grid[1, 1] === a && m.grid[2, 1] === b && length(m.agents) == 2
        @test_throws ArgumentError spawn_viable!(m, [(0, 0), (1, 0)])
    end

    @testset "uniform over the viable empty sites" begin
        cap = ones(Int, 6, 3)
        cap[2:5, 2] .= 3  # a 1 × 4 strip, sites (1, 1) to (4, 1), in land that does not feed a metabolism of 2
        strip = [(x, 1) for x in 1:4]
        hits = Dict{Tuple{Int,Int},Int}()
        n = 4000
        for seed in 0:(n - 1)
            m = tiny_model(cap; initial_population=1, metabolism=(2, 2), xxl=on, seed=seed)
            a = only(m.agents)
            hits[(a.x, a.y)] = get(hits, (a.x, a.y), 0) + 1
        end
        @test issubset(keys(hits), strip)
        chi2 = sum((get(hits, s, 0) - n / 4)^2 / (n / 4) for s in strip)
        @test chi2 < 16.266  # χ², 3 degrees of freedom, p = 0.001
    end

    @testset "traits drawn in spawn_at!'s order" begin
        vi1 = find_experiment(reg, "VI-1")
        base = replace_config(to_xxl(vi1.config, viable_rules); initial_population=0)
        traits(a) = (
            a.id,
            a.vision,
            a.metabolism,
            a.sugar,
            a.max_age,
            a.tags,
            a.ntags,
            a.sex,
            a.fertility_start,
            a.fertility_end,
            a.spice_metabolism,
            a.spice,
            a.immune_genotype,
            a.speed,
        )
        for seed in 0:9
            cfg = replace_config(base; seed=seed)
            m1, m2 = Model(cfg), Model(cfg)
            @test traits(spawn_at!(m1, 7, 9)) == traits(spawn_viable!(m2, [(7, 9)]))
        end
    end

    @testset "rule R: a newcomer stands on viable land or is counted" begin
        a80 = find_experiment(reg, "IV-12/a80")
        @test a80.config.replacement && !a80.config.sex  # every new agent is a replacement
        cfg = replace_config(to_xxl(a80.config, viable_rules); initial_population=1000)
        m = Model(cfg)
        newcomers = fed = unexplained = 0
        for _ in 1:20
            first_new, before = agents_ever(m), m.viable_fallbacks
            step!(m)
            new = sort!(filter(a -> a.id >= first_new, m.agents); by=a -> a.id)
            fallbacks = 0
            for a in new
                newcomers += 1
                if viable(m, a, a.x, a.y)
                    fed += 1
                    continue
                end
                fallbacks += 1
                # no site that feeds it was free when it came: each is held by an older agent
                p = placement_pair(m, a)
                free = count(placement_grid(500, 500)) do (x, y)
                    placement_feeds(m, p, x, y) || return false
                    o = m.grid[x + 1, y + 1]
                    return o === nothing || o.id > a.id
                end
                free == 0 || (unexplained += 1)
            end
            @test m.viable_fallbacks - before == fallbacks
        end
        @test newcomers > 0 && fed > 0
        @test unexplained == 0
    end
end
