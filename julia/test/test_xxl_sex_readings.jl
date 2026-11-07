# xxl (stage 6): the sex readings (docs/superpowers/specs/2026-11-07-xxl-sex-design.md, "Part 1: the readings").
# Hand-built worlds pin the fertile counts, the within-vision count on both shapes, the births and their distances and
# the snapshot of fertile lives; short VI-1 runs in the three worlds show the observer leaves the run alone.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: SexReadings, sex_period!, sex_rows, sex_agent_rows, SEX_COLUMNS, SEX_AGENT_COLUMNS, SEX_WINDOW,
    with_steps

const SR_REG = load_registry()
const SR_HEADER = [
    "t", "population", "eligible", "fertile", "fertile_reach", "fertile_vision", "births", "no_site",
    "mean_distance", "median_distance", "mean_distance_share", "median_distance_share",
    "mean_vision", "sd_vision", "mean_metabolism", "sd_metabolism", "mean_spice_metabolism", "sd_spice_metabolism",
    "mean_speed", "sd_speed",
]
const SR_AGENT_HEADER = [
    "id", "sex", "end_t", "end_reason", "periods_eligible", "periods_fertile", "periods_fertile_reach",
    "periods_fertile_vision", "children", "vision", "metabolism", "speed",
]
const SR_DISC = XxlRules(; vision_shape="disc")

sr_val(row, name) = row[findfirst(==(name), SR_HEADER)]
sr_agent(row, name) = row[findfirst(==(name), SR_AGENT_HEADER)]

# A fertile agent of sex `sex` at (x, y): of childbearing age 20 in 12..40, holding its endowment of 60.
function sr_fertile(m, x, y, sex; vision=1)
    a = put_agent(m, x, y; sugar=60.0, vision=vision)
    a.sex, a.fertility_start, a.fertility_end, a.initial_sugar, a.age = sex, 12, 40, 60.0, 20
    return a
end

# One reading of a hand-built world at period `t`, as after a step: the row it adds.
function sr_read!(r, m, t)
    m.t = t
    sex_period!(r, m)
    empty!(m.dead_this_step)  # as the next step! does
    return r.rows[end]
end

@testset "xxl sex readings" begin
    @testset "the columns" begin
        @test SEX_COLUMNS == SR_HEADER
        @test SEX_AGENT_COLUMNS == SR_AGENT_HEADER
        @test SEX_WINDOW == 200
        r = SexReadings(; window=(301, 500))
        @test sex_rows(r) == (SR_HEADER, Vector{Float64}[])
        @test sex_agent_rows(r) == (SR_AGENT_HEADER, Vector{Float64}[])
        @test_throws ArgumentError SexReadings(; window=(5, 4))
    end

    @testset "round vision: a pair out of the look's sample but within vision" begin
        m = tiny_model(zeros(Int, 64, 64); sex=true, xxl=SR_DISC, vision=(30, 30))
        sr_fertile(m, 10, 10, :F; vision=30)
        sr_fertile(m, 22, 26, :M; vision=30)  # 12² + 16² = 20²
        r = SexReadings(; window=(301, 500))
        rng_before = copy(m.rng)
        row = sr_read!(r, m, 0)
        @test m.rng == rng_before  # the looks drew from the observer's copy
        @test sr_val(row, "population") == 2
        @test sr_val(row, "eligible") == 2 && sr_val(row, "fertile") == 2
        @test sr_val(row, "fertile_reach") == 0
        @test sr_val(row, "fertile_vision") == 2
        @test m.mate_log == MateEvent[]  # the first call turns the log on
    end

    @testset "round vision: a pair just out of vision, and one of the same sex, are not counted" begin
        m = tiny_model(zeros(Int, 64, 64); sex=true, xxl=SR_DISC, vision=(5, 5))
        sr_fertile(m, 10, 10, :F; vision=5)
        sr_fertile(m, 14, 14, :M; vision=5)  # 32 > 25
        sr_fertile(m, 6, 10, :F; vision=5)  # 4 from the other woman, 8 from him
        row = sr_read!(SexReadings(; window=(301, 500)), m, 0)
        @test sr_val(row, "fertile") == 3 && sr_val(row, "fertile_vision") == 0
    end

    @testset "round vision: across the torus edge, the short way" begin
        m = tiny_model(zeros(Int, 64, 64); sex=true, xxl=SR_DISC, vision=(6, 6))
        sr_fertile(m, 1, 30, :F; vision=6)
        sr_fertile(m, 61, 34, :M; vision=6)  # dx 4 the short way, dy 4: 32 <= 36
        row = sr_read!(SexReadings(; window=(301, 500)), m, 0)
        @test sr_val(row, "fertile_vision") == 2
        m2 = tiny_model(zeros(Int, 64, 64); sex=true, xxl=SR_DISC, vision=(6, 6))
        sr_fertile(m2, 1, 1, :F; vision=6)
        sr_fertile(m2, 59, 62, :M; vision=6)  # dx 6, dy 3: 45 > 36
        @test sr_val(sr_read!(SexReadings(; window=(301, 500)), m2, 0), "fertile_vision") == 0
    end

    @testset "round vision: only one partner fertile, the other not" begin
        m = tiny_model(zeros(Int, 64, 64); sex=true, xxl=SR_DISC, vision=(8, 8))
        sr_fertile(m, 10, 10, :F; vision=8)
        h = sr_fertile(m, 13, 10, :M; vision=8)
        h.sugar = 59.0
        row = sr_read!(SexReadings(; window=(301, 500)), m, 0)
        @test sr_val(row, "eligible") == 2 && sr_val(row, "fertile") == 1 && sr_val(row, "fertile_vision") == 0
    end

    @testset "the lattice: on a line within vision, and off every line" begin
        m = tiny_model(zeros(Int, 40, 40); sex=true, vision=(5, 5))
        sr_fertile(m, 10, 10, :F; vision=5)
        sr_fertile(m, 10, 14, :M; vision=5)  # on a line at 4
        row = sr_read!(SexReadings(; window=(301, 500)), m, 0)
        @test sr_val(row, "fertile_vision") == 2
        @test sr_val(row, "fertile_reach") == 2  # the book's look covers the line
        m2 = tiny_model(zeros(Int, 40, 40); sex=true, vision=(5, 5))
        sr_fertile(m2, 10, 10, :F; vision=5)
        sr_fertile(m2, 12, 11, :M; vision=5)  # inside the disc, off every line
        row2 = sr_read!(SexReadings(; window=(301, 500)), m2, 0)
        @test sr_val(row2, "fertile") == 2 && sr_val(row2, "fertile_vision") == 0
        # across the edge on a line, and each agent's own vision
        m3 = tiny_model(zeros(Int, 40, 40); sex=true, vision=(1, 5))
        sr_fertile(m3, 1, 20, :F; vision=5)
        sr_fertile(m3, 37, 20, :M; vision=3)  # 4 apart the short way: she sees him, he doesn't see her
        @test sr_val(sr_read!(SexReadings(; window=(301, 500)), m3, 0), "fertile_vision") == 1
    end

    @testset "the lattice look's stride: every site out to the look's reach is read" begin
        m = tiny_model(zeros(Int, 60, 60); sex=true, vision=(10, 20), look_stride=10)
        sr_fertile(m, 10, 10, :F; vision=20)
        sr_fertile(m, 10, 13, :M; vision=10)
        row = sr_read!(SexReadings(; window=(301, 500)), m, 0)
        @test sr_val(row, "fertile_vision") == 2
        # vision 10 at stride 10: the look reaches 10·1 + 10 − 1 = 19, so V + 1 .. V + 9 count and V + 10 doesn't
        for (d, seen) in ((11, 2), (15, 2), (19, 2), (20, 0))
            m2 = tiny_model(zeros(Int, 60, 60); sex=true, vision=(10, 20), look_stride=10)
            sr_fertile(m2, 10, 10, :F; vision=10)
            sr_fertile(m2, 10, 10 + d, :M; vision=10)
            @test sr_val(sr_read!(SexReadings(; window=(301, 500)), m2, 0), "fertile_vision") == seen
        end
    end

    @testset "births and no-site attempts from the log, and a birth at distance 3" begin
        m = tiny_model(ones(Int, 15, 15); sex=true, mate_contact="vision")
        f = sr_fertile(m, 2, 2, :F; vision=6)
        h = sr_fertile(m, 2, 5, :M; vision=3)
        r = SexReadings(; window=(301, 500))
        row0 = sr_read!(r, m, 0)
        @test sr_val(row0, "births") == 0 && sr_val(row0, "no_site") == 0
        @test isnan(sr_val(row0, "mean_distance")) && isnan(sr_val(row0, "median_distance_share"))
        @test length(mate!(m, f)) == 1
        events = copy(m.mate_log)
        @test length(events) == 1 && events[1].born && events[1].distance == 3.0
        row1 = sr_read!(r, m, 1)
        @test sr_val(row1, "births") == 1 && sr_val(row1, "no_site") == 0
        @test sr_val(row1, "mean_distance") == 3.0 && sr_val(row1, "median_distance") == 3.0
        @test sr_val(row1, "mean_distance_share") == 0.5 && sr_val(row1, "median_distance_share") == 0.5
        @test isempty(m.mate_log)  # read, then emptied
        # an attempt with no empty site, and a hand-written mix: the period's own events only
        push!(m.mate_log, MateEvent(1, f.id, h.id, false, 1.0, 6), MateEvent(1, f.id, h.id, true, 2.0, 4),
            MateEvent(1, h.id, f.id, true, 4.0, 2), MateEvent(1, h.id, f.id, true, 9.0, 3))
        row2 = sr_read!(r, m, 2)
        @test sr_val(row2, "births") == 3 && sr_val(row2, "no_site") == 1
        @test sr_val(row2, "mean_distance") == 5.0 && sr_val(row2, "median_distance") == 4.0
        @test sr_val(row2, "mean_distance_share") == (0.5 + 2.0 + 3.0) / 3
        @test sr_val(row2, "median_distance_share") == 2.0
        row3 = sr_read!(r, m, 3)
        @test sr_val(row3, "births") == 0 && isnan(sr_val(row3, "mean_distance"))
    end

    @testset "a full world: logged as no site" begin
        m = tiny_model(ones(Int, 3, 3); sex=true)
        r = SexReadings(; window=(301, 500))
        sr_read!(r, m, 0)
        f, h = couple(m)
        for x in 0:2, y in 0:2
            agent_at(m, x, y) === nothing && put_agent(m, x, y)
        end
        @test isempty(mate!(m, f))
        row = sr_read!(r, m, 1)
        @test sr_val(row, "births") == 0 && sr_val(row, "no_site") == 1 && isnan(sr_val(row, "mean_distance"))
    end

    @testset "the traits: means and sds, and no speed in the book" begin
        m = tiny_model(zeros(Int, 10, 10); sex=true, spice=true)
        for (x, v, mt, sm) in ((0, 1, 2, 3), (2, 3, 4, 1))
            a = put_agent(m, x, 0; vision=v, metabolism=mt)
            a.spice_metabolism = sm
        end
        row = sr_read!(SexReadings(; window=(301, 500)), m, 0)
        @test sr_val(row, "mean_vision") == 2.0 && sr_val(row, "sd_vision") == 1.0
        @test sr_val(row, "mean_metabolism") == 3.0 && sr_val(row, "sd_metabolism") == 1.0
        @test sr_val(row, "mean_spice_metabolism") == 2.0 && sr_val(row, "sd_spice_metabolism") == 1.0
        @test isnan(sr_val(row, "mean_speed")) && isnan(sr_val(row, "sd_speed"))
        bare = tiny_model(zeros(Int, 5, 5); sex=true)
        row0 = sr_read!(SexReadings(; window=(301, 500)), bare, 0)
        @test sr_val(row0, "population") == 0 && isnan(sr_val(row0, "mean_vision")) && isnan(sr_val(row0, "sd_vision"))
    end

    @testset "the snapshot: an aging out, a death after childbearing age, a death before" begin
        m = tiny_model(zeros(Int, 10, 10); sex=true, vision=(1, 1))
        r = SexReadings(; window=(301, 500))
        a = nothing
        h = nothing
        young = nothing
        late = nothing
        for t in 0:320
            if t == 270
                a = put_agent(m, 5, 5; sugar=60.0)
                a.sex, a.fertility_start, a.fertility_end, a.initial_sugar = :F, 12, 40, 60.0
            end
            t == 295 && (h = sr_fertile(m, 5, 6, :M))  # in reach (and vision) for 295..299
            if t == 300
                kill!(m, h)  # dies at 20, after childbearing age: ends at 300, before the window
                young = put_agent(m, 1, 1)
                young.sex, young.fertility_start, young.fertility_end = :M, 12, 50
                late = sr_fertile(m, 8, 8, :M; vision=1)
                late.fertility_end = 50
            end
            if a !== nothing
                a.age = t - 270  # 40 at t = 310
                a.sugar = (t <= 281 || 290 <= t <= 299) ? 60.0 : 10.0  # fertile for 290..299 (too young before 282)
            end
            young === nothing || (young.age = 5)
            t == 305 && kill!(m, young)  # dies at 5, before childbearing
            t == 315 && kill!(m, late)  # dies at 20: ends at 315
            sr_read!(r, m, t)
        end
        @test length(r.rows) == 321 && [row[1] for row in r.rows] == 0:320
        _, rows = sex_agent_rows(r)
        @test [Int(row[1]) for row in rows] == [a.id, late.id]
        ra, rl = rows
        @test sr_agent(ra, "sex") == 0 && sr_agent(ra, "end_t") == 310 && sr_agent(ra, "end_reason") == 0
        @test sr_agent(ra, "periods_eligible") == 28  # ages 12..39, t = 282..309
        @test sr_agent(ra, "periods_fertile") == 10
        @test sr_agent(ra, "periods_fertile_reach") == 5
        @test sr_agent(ra, "periods_fertile_vision") == 5
        @test sr_agent(ra, "children") == 0 && sr_agent(ra, "vision") == 1 && sr_agent(ra, "metabolism") == 1
        @test isnan(sr_agent(ra, "speed"))
        @test sr_agent(rl, "sex") == 1 && sr_agent(rl, "end_t") == 315 && sr_agent(rl, "end_reason") == 1
        @test sr_agent(rl, "periods_eligible") == 15 && sr_agent(rl, "periods_fertile") == 15  # t = 300..314
        @test sr_agent(rl, "periods_fertile_reach") == 0 && sr_agent(rl, "periods_fertile_vision") == 0
    end

    @testset "the snapshot: a parent dying in the step of its child's birth keeps the child" begin
        m = tiny_model(ones(Int, 15, 15); sex=true)
        r = SexReadings(; window=(0, 10))
        f, h = couple(m)
        sr_read!(r, m, 0)
        @test length(mate!(m, f)) == 1
        kill!(m, h)  # kill! empties his list of children
        sr_read!(r, m, 1)
        _, rows = sex_agent_rows(r)
        @test length(rows) == 1
        @test sr_agent(rows[1], "id") == h.id && sr_agent(rows[1], "end_reason") == 1
        @test sr_agent(rows[1], "children") == 1 && sr_agent(rows[1], "periods_fertile") == 1
    end

    # The standard CSV of a 12-period VI-1 seed, with and without the observer.
    function sr_csv(rows, cfg)
        path = tempname()
        Sugarscape.write_seed_csv(path, rows; columns=metric_columns(cfg))
        bytes = read(path)
        rm(path)
        return bytes
    end
    vi1 = with_steps(find_experiment(SR_REG, "VI-1"), 12)
    for (name, kw, cfg) in (
        ("book", (;), vi1.config),
        ("xl", (; xl=true), to_xl(vi1.config)),
        ("XXL_DEFAULTS", (; xxl=XXL_DEFAULTS), to_xxl(vi1.config, XXL_DEFAULTS)),
    )
        @testset "$name VI-1: the run is the same with the observer" begin
            plain, _ = Sugarscape.timed_seed(vi1, 0; kw...)
            r = SexReadings(; window=(3, 12))
            watched, _ = Sugarscape.timed_seed(vi1, 0; kw..., sex_readings=r)
            @test sr_csv(plain, cfg) == sr_csv(watched, cfg)
            _, rows = sex_rows(r)
            @test length(rows) == 13 && [row[1] for row in rows] == 0:12
            col(n) = [sr_val(row, n) for row in rows]
            @test col("population") == [p[1 + findfirst(==("population"), METRIC_COLUMNS)] for p in plain]
            @test all(col("fertile") .<= col("eligible") .<= col("population"))
            @test all(col("fertile_reach") .<= col("fertile")) && all(col("fertile_vision") .<= col("fertile"))
            name == "book" && @test col("fertile_reach") == col("fertile_vision")  # the book's look is every site
            name == "XXL_DEFAULTS" && @test all(col("fertile_reach") .<= col("fertile_vision"))
            name == "xl" && @test all(col("fertile_reach") .<= col("fertile_vision"))  # the look's whole reach
            ever = [p[1 + findfirst(==("agents_ever"), METRIC_COLUMNS)] for p in plain]
            @test col("births")[2:end] == diff(ever)  # no replacement in VI-1: every new agent is a birth
            @test sum(col("births")) > 0
            @test isnan(col("mean_speed")[1]) == (name != "XXL_DEFAULTS")
        end
    end

    @testset "the within-vision count against a brute force: $name VI-1" for (name, cfg) in (
        ("XXL_DEFAULTS", to_xxl(vi1.config, XXL_DEFAULTS)), ("xl", to_xl(vi1.config)),
    )
        disc = xxl_on(cfg, :disc)
        w, h, thr, s = cfg.width, cfg.height, cfg.fertility_threshold, cfg.look_stride
        function sees(a, o)
            dx, dy = torus_delta(w, a.x, o.x), torus_delta(h, a.y, o.y)
            disc && return 0 < dx * dx + dy * dy <= a.vision^2
            return (dx == 0) != (dy == 0) && 0 < abs(dx) + abs(dy) <= s * (a.vision ÷ s) + s - 1  # a line, the short way
        end
        brute(m) = count(
            a -> is_fertile(a, thr) && any(o -> o.sex !== a.sex && is_fertile(o, thr) && sees(a, o), m.agents),
            m.agents,
        )
        m = Model(replace_config(cfg; seed=cfg.seed))
        r = SexReadings(; window=(1, 8))
        sex_period!(r, m)
        counts = Tuple{Int,Int}[]
        for _ in 1:8
            step!(m)
            sex_period!(r, m)
            push!(counts, (Int(sr_val(r.rows[end], "fertile_vision")), brute(m)))
        end
        @test all(c -> c[1] == c[2], counts) && sum(first, counts) > 0
    end

    @testset "fertile and fertile_reach are the scorecard's counts" begin
        r = SexReadings(; window=(3, 12))
        rows, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_DEFAULTS, scorecard=true, sex_readings=r)
        cols = ["t"; metric_columns(to_xxl(vi1.config, XXL_DEFAULTS); scorecard=true)]
        card(n) = [row[findfirst(==(n), cols)] for row in rows]
        _, srows = sex_rows(r)
        @test [sr_val(row, "fertile") for row in srows] == card("n_fertile")
        @test [sr_val(row, "fertile_reach") for row in srows] == card("n_fertile_with_mate")
        @test sum(card("n_fertile")) > 0
    end

    @testset "not with a checkpoint" begin
        tiny = find_experiment(SR_REG, "TEST-tiny")
        checkpoint = (; restore=() -> nothing, period_done=(m, rows, clock) -> false)
        @test_throws ArgumentError Sugarscape.timed_seed(
            tiny, 0; xxl=XXL_V1, sex_readings=SexReadings(; window=(1, 5)), checkpoint=checkpoint
        )
    end

    @testset "seed_job passes sex_readings only when it is set" begin
        tiny = find_experiment(SR_REG, "TEST-tiny")
        stand_in(exp, k; xl=false, xxl=nothing) = ([[0.0]], (; seed=k))
        @test Sugarscape.seed_job(tiny, 0, false, stand_in; xxl=XXL_BOOK)[1] == [[0.0]]
        with_readings(exp, k; xl=false, xxl=nothing, scorecard=false, sex_readings=nothing) =
            ([[sex_readings === nothing ? 0.0 : 1.0]], (; seed=k))
        r = SexReadings(; window=(1, 5))
        @test Sugarscape.seed_job(tiny, 0, false, with_readings; xxl=XXL_BOOK, sex_readings=r)[1] == [[1.0]]
    end
end
