# xxl (stage 7): the culture readings (docs/superpowers/specs/2026-11-07-xxl-culture-design.md, "Part 1: the readings").
# Hand-built worlds pin the neighbour pairs on both reaches, the chance closeness, persistence and distance moved, and
# the patch polarization; short VI-1 runs show the observer leaves the run alone and agrees with the scorecard's flips.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: CultureReadings, culture_period!, culture_rows, culture_patch_rows, culture_neighbors,
    patch_polarization, CULTURE_COLUMNS, CULTURE_PATCH_COLUMNS, CULTURE_PATCH, CULTURE_PATCH_EVERY, CULTURE_PATCH_MIN,
    with_steps

const CR_REG = load_registry()
const CR_HEADER = [
    "t", "population", "blue_share", "tag_flips_per_agent", "neighbour_pairs", "neighbour_closeness",
    "chance_closeness", "neighbours_per_agent", "share_no_neighbours", "persist_base", "persistence", "mean_moved",
    "mean_speed", ["zero_share_$i" for i in 1:11]...,
]

cr_val(row, name) = row[findfirst(==(name), CR_HEADER)]

# A world of tag length 11 with no agents.
cr_world(w=12, h=12; kw...) = tiny_model(ones(Int, w, h); tag_length=11, kw...)

# An agent at (x, y) with the 11 tag bits given by the integer `bits11`.
function cr_agent(m, x, y, bits11)
    a = put_agent(m, x, y)
    a.tags, a.ntags = UInt64(bits11), 11
    return a
end

# One reading of a hand-built world at period `t`: the row it adds.
function cr_read!(r, m, t)
    m.t = t
    culture_period!(r, m)
    return r.rows[end]
end

cr_close(a, b) = 1.0 - count_ones(UInt64(a) ⊻ UInt64(b)) / 11

@testset "xxl culture readings" begin
    @testset "the columns and constants" begin
        @test CULTURE_COLUMNS == CR_HEADER
        @test CULTURE_PATCH_COLUMNS == ["t", "px", "py", "agents", "blue_share"]
        @test (CULTURE_PATCH, CULTURE_PATCH_EVERY, CULTURE_PATCH_MIN) == (50, 10, 20)
        r = CultureReadings()
        @test culture_rows(r) == (CR_HEADER, Vector{Float64}[])
        @test culture_patch_rows(r) == (CULTURE_PATCH_COLUMNS, Vector{Float64}[])
    end

    @testset "lattice: three in a row are two pairs; a diagonal agent is no neighbour" begin
        m = cr_world()
        cr_agent(m, 0, 5, 0b00000000000)
        cr_agent(m, 1, 5, 0b00000000111)
        cr_agent(m, 2, 5, 0b00001111111)
        row = cr_read!(CultureReadings(), m, 0)
        @test cr_val(row, "neighbour_pairs") == 2
        @test cr_val(row, "neighbour_closeness") ≈ (cr_close(0, 0b111) + cr_close(0b111, 0b1111111)) / 2
        @test cr_val(row, "neighbours_per_agent") ≈ 4 / 3 && cr_val(row, "share_no_neighbours") == 0.0
        d = cr_agent(m, 2, 6, 0b11111111111)  # diagonal of the middle agent, next to the third
        row = cr_read!(CultureReadings(), m, 0)
        @test cr_val(row, "neighbour_pairs") == 3  # the third's north neighbour; the middle one's diagonal is not
        @test sort([a.id for a in culture_neighbors(m, m.agents[2])]) == sort([m.agents[1].id, m.agents[3].id])
        @test m.agents[4] === d
    end

    @testset "radius 1.5: the diagonal counts, and the pair across the torus edge is one pair" begin
        m = cr_world(12, 12; xxl=XxlRules(; interaction_radius=1.5))
        cr_agent(m, 0, 5, 0b0)
        cr_agent(m, 1, 5, 0b1)
        cr_agent(m, 2, 6, 0b11)  # diagonal of the second
        cr_agent(m, 11, 9, 0b111)  # x = W - 1, same row as the next
        cr_agent(m, 0, 9, 0b1111)
        row = cr_read!(CultureReadings(), m, 0)
        # (0,5)-(1,5), (1,5)-(2,6), and (11,9)-(0,9); (0,5) and (2,6) are 2.24 apart
        @test cr_val(row, "neighbour_pairs") == 3
        @test cr_val(row, "neighbour_closeness") ≈ (cr_close(0, 1) + cr_close(1, 3) + cr_close(0b111, 0b1111)) / 3
    end

    @testset "the chance closeness against a brute force on 7 agents" begin
        m = cr_world(20, 20)
        tags = [rand(m.rng, 0:2047) for _ in 1:7]
        for (i, t) in enumerate(tags)
            cr_agent(m, 3i, 3i, t)
        end
        row = cr_read!(CultureReadings(), m, 0)
        brute = sum(cr_close(tags[i], tags[j]) for i in 1:7 for j in (i + 1):7) / 21
        @test cr_val(row, "chance_closeness") ≈ brute
        @test cr_val(row, "neighbour_pairs") == 0 && isnan(cr_val(row, "neighbour_closeness"))
        @test cr_val(row, "share_no_neighbours") == 1.0
        for i in 1:11
            @test cr_val(row, "zero_share_$i") ≈ count(t -> (t >> (i - 1)) & 1 == 0, tags) / 7
        end
        @test cr_val(row, "blue_share") ≈ count(t -> 2 * count_ones(t) < 11, tags) / 7
    end

    @testset "t = 0 has no flips, persistence or distance moved" begin
        m = cr_world()
        cr_agent(m, 0, 0, 0)
        cr_agent(m, 1, 0, 1)
        row = cr_read!(CultureReadings(), m, 0)
        @test isnan(cr_val(row, "tag_flips_per_agent")) && isnan(cr_val(row, "persistence"))
        @test isnan(cr_val(row, "mean_moved")) && cr_val(row, "persist_base") == 0
    end

    @testset "two periods: persistence, distance moved, flips, and who enters" begin
        m = cr_world(10, 10)
        a = cr_agent(m, 0, 0, 0)
        b = cr_agent(m, 1, 0, 0)  # a pair with a
        c = cr_agent(m, 5, 5, 0)
        d = cr_agent(m, 9, 9, 0)  # next to nobody
        r = CultureReadings()
        cr_read!(r, m, 0)
        # b walks off; c goes from x = 9... c steps from (5,5) to (5,7); d leaves; e is born next to a
        m.grid[b.x + 1, b.y + 1] = nothing
        b.x, b.y = 3, 3
        m.grid[b.x + 1, b.y + 1] = b
        kill!(m, d)
        e = cr_agent(m, 0, 1, 0b11)
        m.grid[c.x + 1, c.y + 1] = nothing
        c.y = 7
        m.grid[c.x + 1, c.y + 1] = c
        c.tags = 0b101  # two bits flipped
        row = cr_read!(r, m, 1)
        @test cr_val(row, "population") == 4
        @test cr_val(row, "persist_base") == 1 && cr_val(row, "persistence") == 0.0  # a-b moved apart
        @test cr_val(row, "neighbour_pairs") == 1  # a-e
        # moved over a, b, c (d gone, e new): 0, 3*sqrt(2)... b: (1,0)->(3,3), c: 2
        @test cr_val(row, "mean_moved") ≈ (0 + sqrt(2^2 + 3^2) + 2) / 3
        @test cr_val(row, "tag_flips_per_agent") ≈ 2 / 4
    end

    @testset "an agent across the torus edge moves 2, the short way" begin
        m = cr_world(10, 10)
        a = cr_agent(m, 9, 4, 0)
        r = CultureReadings()
        cr_read!(r, m, 0)
        m.grid[a.x + 1, a.y + 1] = nothing
        a.x = 1
        m.grid[a.x + 1, a.y + 1] = a
        @test cr_val(cr_read!(r, m, 1), "mean_moved") == 2.0
    end

    @testset "a pair that stays gives persistence 1" begin
        m = cr_world()
        cr_agent(m, 4, 4, 0)
        cr_agent(m, 5, 4, 0)
        r = CultureReadings()
        cr_read!(r, m, 0)
        row = cr_read!(r, m, 1)
        @test cr_val(row, "persist_base") == 1 && cr_val(row, "persistence") == 1.0
        @test cr_val(row, "mean_moved") == 0.0 && cr_val(row, "tag_flips_per_agent") == 0.0
    end

    @testset "patches and their polarization" begin
        m = cr_world(100, 100)
        blue, red = 0b00000000000, 0b11111111111
        for i in 0:24
            cr_agent(m, i, 0, blue)  # 25 blue in patch (0, 0)
        end
        for i in 0:14
            cr_agent(m, 50 + i, 0, blue)  # 15 blue and 15 red in (1, 0)
            cr_agent(m, 50 + i, 1, red)
        end
        for i in 0:4
            cr_agent(m, i, 50, red)  # 5 red in (0, 1)
        end
        r = CultureReadings()
        cr_read!(r, m, 0)
        cr_read!(r, m, 1)  # not a patch period
        cr_read!(r, m, 10)
        header, rows = culture_patch_rows(r)
        @test header == CULTURE_PATCH_COLUMNS
        @test length(rows) == 6 && unique(row[1] for row in rows) == [0.0, 10.0]
        first = filter(row -> row[1] == 0, rows)
        @test first == [[0.0, 0, 0, 25, 1.0], [0.0, 0, 1, 5, 0.0], [0.0, 1, 0, 30, 0.5]]
        @test patch_polarization(first) ≈ (25 * 1 + 30 * 0) / 55
        @test patch_polarization(first; min_agents=1) ≈ (25 * 1 + 5 * 1 + 30 * 0) / 60
        @test isnan(patch_polarization(first; min_agents=100))
        @test isnan(patch_polarization(Vector{Float64}[]))
    end

    @testset "mean_speed is NaN in a book-config world" begin
        m = cr_world()
        cr_agent(m, 1, 1, 0)
        @test isnan(cr_val(cr_read!(CultureReadings(), m, 0), "mean_speed"))
    end

    vi1 = with_steps(find_experiment(CR_REG, "VI-1"), 12)

    function cr_csv(rows, cfg)
        path = tempname()
        Sugarscape.write_seed_csv(path, rows; columns=metric_columns(cfg))
        bytes = read(path)
        rm(path)
        return bytes
    end

    for (name, kw, cfg) in (
        ("book", (;), vi1.config),
        ("xl", (; xl=true), to_xl(vi1.config)),
        ("XXL_DEFAULTS", (; xxl=XXL_DEFAULTS), to_xxl(vi1.config, XXL_DEFAULTS)),
    )
        @testset "$name VI-1: the run is the same with the observer" begin
            plain, _ = Sugarscape.timed_seed(vi1, 0; kw...)
            r = CultureReadings()
            watched, _ = Sugarscape.timed_seed(vi1, 0; kw..., culture_readings=r)
            @test cr_csv(plain, cfg) == cr_csv(watched, cfg)
            _, rows = culture_rows(r)
            @test length(rows) == 13 && [row[1] for row in rows] == 0:12
            col(n) = [cr_val(row, n) for row in rows]
            @test col("population") == [p[1 + findfirst(==("population"), METRIC_COLUMNS)] for p in plain]
            @test all(0 .<= col("blue_share") .<= 1)
            @test all(c -> 0 <= c <= 1, filter(!isnan, col("neighbour_closeness")))
            @test sum(col("neighbour_pairs")) > 0 && all(!isnan, col("chance_closeness"))
            @test isnan(col("mean_speed")[1]) == (name != "XXL_DEFAULTS")
            _, prows = culture_patch_rows(r)
            @test unique(row[1] for row in prows) == [0.0, 10.0]
        end
    end

    @testset "tag_flips_per_agent is the scorecard's" begin
        r = CultureReadings()
        rows, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_DEFAULTS, scorecard=true, culture_readings=r)
        cols = ["t"; metric_columns(to_xxl(vi1.config, XXL_DEFAULTS); scorecard=true)]
        card = [row[findfirst(==("tag_flips_per_agent"), cols)] for row in rows]
        _, crows = culture_rows(r)
        @test isequal([cr_val(row, "tag_flips_per_agent") for row in crows], card)
        @test sum(filter(!isnan, card)) > 0
    end

    @testset "not with a checkpoint" begin
        tiny = find_experiment(CR_REG, "TEST-tiny")
        checkpoint = (; restore=() -> nothing, period_done=(m, rows, clock) -> false)
        @test_throws ArgumentError Sugarscape.timed_seed(
            tiny, 0; xxl=XXL_V1, culture_readings=CultureReadings(), checkpoint=checkpoint
        )
    end

    @testset "seed_job passes culture_readings only when it is set" begin
        tiny = find_experiment(CR_REG, "TEST-tiny")
        stand_in(exp, k; xl=false, xxl=nothing) = ([[0.0]], (; seed=k))
        @test Sugarscape.seed_job(tiny, 0, false, stand_in; xxl=XXL_BOOK)[1] == [[0.0]]
        with_readings(exp, k; xl=false, xxl=nothing, scorecard=false, culture_readings=nothing) =
            ([[culture_readings === nothing ? 0.0 : 1.0]], (; seed=k))
        r = CultureReadings()
        @test Sugarscape.seed_job(tiny, 0, false, with_readings; xxl=XXL_BOOK, culture_readings=r)[1] == [[1.0]]
    end
end
