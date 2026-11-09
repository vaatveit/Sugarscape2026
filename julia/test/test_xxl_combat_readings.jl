# xxl (stage 8): the combat readings (docs/superpowers/specs/2026-11-08-xxl-combat-design.md, "Part 1: the readings").
# Hand-built worlds pin the neighbour pairs, the home shares and the deaths by cause; short runs of the combat
# experiments show the kills add up, replacement holds the tribes, and the observer leaves the run alone.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: CombatReadings, combat_period!, combat_rows, COMBAT_COLUMNS, with_steps

const KR_REG = load_registry()
const KR_HEADER = [
    "t", "population", "n_blue", "n_red", "killed_blue", "killed_red", "old_age_blue", "old_age_red", "starved_blue",
    "starved_red", "neighbour_pairs", "cross_pairs", "mixing", "front_share", "home_blue", "home_red", "gini_blue",
    "gini_red", "max_sugar_blue", "max_sugar_red", "tribe_changes",
]

kr_val(row, name) = row[findfirst(==(name), KR_HEADER)]

# A world of tag length 1 (tag 0 is blue, 1 is red), without agents.
kr_world(w=12, h=12; kw...) = tiny_model(ones(Int, w, h); tag_length=1, kw...)

function kr_agent(m, x, y, tag; sugar=10.0, kw...)
    a = put_agent(m, x, y; sugar=sugar, kw...)
    return tag!(a, [tag])
end

function kr_read!(r, m, t)
    m.t = t
    combat_period!(r, m)
    return r.rows[end]
end

@testset "xxl combat readings" begin
    @testset "the columns" begin
        @test COMBAT_COLUMNS == KR_HEADER
        @test combat_rows(CombatReadings()) == (KR_HEADER, Vector{Float64}[])
    end

    @testset "lattice: a red with a blue on each side, one across the torus edge" begin
        m = kr_world()
        kr_agent(m, 0, 0, 1)
        kr_agent(m, 1, 0, 0)
        kr_agent(m, 11, 0, 0)
        row = kr_read!(CombatReadings(), m, 0)
        @test kr_val(row, "neighbour_pairs") == 2 && kr_val(row, "cross_pairs") == 2
        @test kr_val(row, "mixing") == 1.0 && kr_val(row, "front_share") == 1.0
        @test kr_val(row, "population") == 3
    end

    @testset "a red diagonal to a blue is a neighbour only at radius 1.5" begin
        for (radius, pairs) in ((nothing, 0), (1.5, 1))
            m = radius === nothing ? kr_world() : kr_world(; xxl=XxlRules(; interaction_radius=radius))
            kr_agent(m, 0, 0, 0)
            kr_agent(m, 1, 1, 1)
            row = kr_read!(CombatReadings(), m, 0)
            @test kr_val(row, "neighbour_pairs") == pairs && kr_val(row, "cross_pairs") == pairs
            @test kr_val(row, "front_share") == pairs
            @test isnan(kr_val(row, "mixing")) == (pairs == 0)
        end
        # the added red next to the lattice trio: it adds a red-red pair and a cross pair at radius 1.5
        m = kr_world(; xxl=XxlRules(; interaction_radius=1.5))
        kr_agent(m, 0, 0, 1)
        kr_agent(m, 1, 0, 0)
        kr_agent(m, 11, 0, 0)
        kr_agent(m, 1, 1, 1)  # red-red with (0, 0), south of the blue at (1, 0); 2.24 from the blue at (11, 0)
        row = kr_read!(CombatReadings(), m, 0)
        @test kr_val(row, "neighbour_pairs") == 4 && kr_val(row, "cross_pairs") == 3
        @test kr_val(row, "mixing") == 0.75 && kr_val(row, "front_share") == 1.0
    end

    @testset "front share counts agents, mixing counts pairs" begin
        m = kr_world()
        kr_agent(m, 3, 3, 0)
        kr_agent(m, 4, 3, 0)
        kr_agent(m, 5, 3, 1)
        kr_agent(m, 9, 9, 1)  # alone
        row = kr_read!(CombatReadings(), m, 0)
        @test kr_val(row, "neighbour_pairs") == 2 && kr_val(row, "cross_pairs") == 1
        @test kr_val(row, "mixing") == 0.5 && kr_val(row, "front_share") == 0.5  # the middle blue and the red
    end

    @testset "home shares against the blocks' centres" begin
        blocks = Sugarscape.Block[("blue", 0, 0, 20, 20, 0), ("red", 30, 30, 20, 20, 0)]
        m = kr_world(50, 50; initial_blocks=blocks)
        kr_agent(m, 10, 10, 0)  # home
        kr_agent(m, 40, 40, 0)  # in the other block
        kr_agent(m, 25, 25, 0)  # (10, 10) and (40, 40) are both 15 + 15 away: half
        kr_agent(m, 41, 39, 1)  # home for a red
        row = kr_read!(CombatReadings(), m, 0)
        @test kr_val(row, "home_blue") ≈ 1.5 / 3
        @test kr_val(row, "home_red") == 1.0
        # no agents of a tribe: NaN
        m = kr_world(50, 50; initial_blocks=blocks)
        kr_agent(m, 10, 10, 0)
        row = kr_read!(CombatReadings(), m, 0)
        @test kr_val(row, "home_blue") == 1.0 && isnan(kr_val(row, "home_red"))
        # the minimum image: the blue block's centre is (45, 5), 6 from a blue at x = 1 across the edge; the red's is (25, 25)
        m = kr_world(
            50, 50; initial_blocks=Sugarscape.Block[("blue", 40, 0, 10, 10, 0), ("red", 20, 20, 10, 10, 0)]
        )
        kr_agent(m, 1, 5, 0)
        @test kr_val(kr_read!(CombatReadings(), m, 0), "home_blue") == 1.0
    end

    @testset "wealth by tribe" begin
        m = kr_world()
        kr_agent(m, 1, 1, 0; sugar=1.0)
        kr_agent(m, 3, 1, 0; sugar=3.0)
        kr_agent(m, 5, 1, 1; sugar=7.0)
        row = kr_read!(CombatReadings(), m, 0)
        @test kr_val(row, "max_sugar_blue") == 3.0 && kr_val(row, "max_sugar_red") == 7.0
        @test kr_val(row, "gini_blue") ≈ Sugarscape.gini([1.0, 3.0]) && kr_val(row, "gini_red") == 0.0
        @test (kr_val(row, "n_blue"), kr_val(row, "n_red"), kr_val(row, "population")) == (2, 1, 3)
        row = kr_read!(CombatReadings(), kr_world(), 0)
        @test all(isnan, [kr_val(row, c) for c in ("gini_blue", "max_sugar_red", "front_share", "mixing", "home_blue")])
    end

    @testset "deaths: killed, starved, and old age, by the victim's tribe" begin
        m = kr_world(12, 12; combat_alpha=Inf, vision=(1, 4))
        r = CombatReadings()
        kr_read!(r, m, 0)
        attacker = kr_agent(m, 1, 1, 1; sugar=20.0, vision=4)  # a red
        victim = kr_agent(m, 3, 1, 0; sugar=8.0)  # a poorer blue, in reach
        combat_move!(m, attacker)
        @test victim.id in m.killed && !victim.alive
        starver = kr_agent(m, 8, 8, 0; sugar=0.5, metabolism=1)
        Sugarscape.metabolize!(m, starver)
        @test !starver.alive && !(starver.id in m.killed)
        elder = kr_agent(m, 6, 6, 1; sugar=5.0, max_age=5)
        elder.age = 5
        die!(m, elder)
        row = kr_read!(r, m, 1)
        @test kr_val(row, "killed_blue") == 1 && kr_val(row, "killed_red") == 0
        @test kr_val(row, "starved_blue") == 1 && kr_val(row, "starved_red") == 0
        @test kr_val(row, "old_age_red") == 1 && kr_val(row, "old_age_blue") == 0
        @test kr_val(row, "population") == 1
        # the next reading, with the logs cleared as step! does, has none
        empty!(m.dead_this_step)
        empty!(m.killed)
        row = kr_read!(r, m, 2)
        @test sum(kr_val(row, c) for c in KR_HEADER[5:10]) == 0
    end

    @testset "tribe_changes counts agents alive at both calls whose tribe differs" begin
        m = kr_world()
        a = kr_agent(m, 1, 1, 0)
        b = kr_agent(m, 5, 5, 1)
        r = CombatReadings()
        @test isnan(kr_val(kr_read!(r, m, 0), "tribe_changes"))
        @test kr_val(kr_read!(r, m, 1), "tribe_changes") == 0
        tag!(a, [1])
        kr_agent(m, 8, 8, 0)  # born: not counted
        @test kr_val(kr_read!(r, m, 2), "tribe_changes") == 1
        kill!(m, b)
        tag!(a, [0])
        @test kr_val(kr_read!(r, m, 3), "tribe_changes") == 1  # a flipped back; b is gone
    end

    function kr_model(id, steps)
        exp = with_steps(find_experiment(KR_REG, id), steps)
        return Model(replace_config(exp.config; seed=exp.config.seed))
    end

    @testset "III-14 for 30 periods: the kills add up, and tribe_changes is never negative" begin
        m = kr_model("III-14", 30)
        r = CombatReadings()
        combat_period!(r, m)
        recorded = 0
        for _ in 1:30
            step!(m)
            recorded += length(m.killed)
            combat_period!(r, m)
        end
        _, rows = combat_rows(r)
        @test length(rows) == 31 && [row[1] for row in rows] == 0:30
        @test sum(kr_val(row, "killed_blue") + kr_val(row, "killed_red") for row in rows) == recorded
        @test recorded > 0
        @test all(row -> kr_val(row, "tribe_changes") >= 0, rows[2:end])
        @test isnan(kr_val(rows[1], "tribe_changes"))
    end

    @testset "III-11 for 20 periods: replacement holds the tribes, and the deaths are counted" begin
        m = kr_model("III-11", 20)
        r = CombatReadings()
        combat_period!(r, m)
        for _ in 1:20
            step!(m)
            combat_period!(r, m)
        end
        _, rows = combat_rows(r)
        @test all(row -> kr_val(row, "n_blue") == kr_val(rows[1], "n_blue"), rows)
        @test all(row -> kr_val(row, "n_red") == kr_val(rows[1], "n_red"), rows)
        @test all(row -> kr_val(row, "tribe_changes") == 0, rows[2:end])
        @test sum(sum(kr_val(row, c) for c in KR_HEADER[5:10]) for row in rows) > 0
    end

    function kr_csv(rows, cfg)
        path = tempname()
        Sugarscape.write_seed_csv(path, rows; columns=metric_columns(cfg))
        bytes = read(path)
        rm(path)
        return bytes
    end

    for id in ("III-9", "III-11", "III-12", "III-13", "III-14"),
        (name, kw, f) in (
            ("book", (;), identity),
            ("xl", (; xl=true), to_xl),
            ("XXL_DEFAULTS", (; xxl=XXL_DEFAULTS), c -> to_xxl(c, XXL_DEFAULTS)),
        )

        @testset "$id $name: the run is the same with the observer" begin
            exp = with_steps(find_experiment(KR_REG, id), 8)
            plain, _ = Sugarscape.timed_seed(exp, 0; kw...)
            r = CombatReadings()
            watched, _ = Sugarscape.timed_seed(exp, 0; kw..., combat_readings=r)
            @test kr_csv(plain, f(exp.config)) == kr_csv(watched, f(exp.config))
            _, rows = combat_rows(r)
            @test length(rows) == 9 && [row[1] for row in rows] == 0:8
            @test [row[2] for row in rows] == [p[1 + findfirst(==("population"), METRIC_COLUMNS)] for p in plain]
        end
    end

    @testset "not with a checkpoint" begin
        tiny = find_experiment(KR_REG, "TEST-tiny")
        checkpoint = (; restore=() -> nothing, period_done=(m, rows, clock) -> false)
        @test_throws ArgumentError Sugarscape.timed_seed(
            tiny, 0; xxl=XXL_V1, combat_readings=CombatReadings(), checkpoint=checkpoint
        )
    end

    @testset "seed_job passes combat_readings only when it is set" begin
        tiny = find_experiment(KR_REG, "TEST-tiny")
        stand_in(exp, k; xl=false, xxl=nothing) = ([[0.0]], (; seed=k))
        @test Sugarscape.seed_job(tiny, 0, false, stand_in; xxl=XXL_BOOK)[1] == [[0.0]]
        with_readings(exp, k; xl=false, xxl=nothing, scorecard=false, combat_readings=nothing) =
            ([[combat_readings === nothing ? 0.0 : 1.0]], (; seed=k))
        r = CombatReadings()
        @test Sugarscape.seed_job(tiny, 0, false, with_readings; xxl=XXL_BOOK, combat_readings=r)[1] == [[1.0]]
    end
end
