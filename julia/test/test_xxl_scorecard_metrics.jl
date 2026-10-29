# xxl: the scorecard's opt-in metric columns (revised spec, "New metrics") and the runner's `scorecard` and
# `first_seed` keywords. Hand-built worlds pin each column; a short VI-1 run matches births and loans against the
# standard columns.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: ScorecardTracker, scorecard_metrics!, SCORECARD_COLUMNS, Loan

const SC_REG = load_registry()
const SC_TINY = find_experiment(SC_REG, "TEST-tiny")

# The scorecard columns of this period, by name.
function card(m, tr)
    return Dict(zip(SCORECARD_COLUMNS, scorecard_metrics!(Float64[], m, tr)))
end

# An experiment cut to `steps` periods.
function sc_cut(e, steps)
    return Experiment(
        e.id,
        e.title,
        e.rules,
        steps,
        e.seeds,
        e.config,
        e.fingerprint,
        e.xl_config,
        e.xl_fingerprint,
    )
end

@testset "the columns" begin
    @test length(SCORECARD_COLUMNS) == 14 && allunique(SCORECARD_COLUMNS)
    @test SCORECARD_COLUMNS == [
        "deaths_sugar",
        "deaths_spice",
        "deaths_old_age",
        "deaths_killed",
        "births",
        "n_fertile",
        "n_fertile_with_mate",
        "tag_flips_per_agent",
        "share_traded_10",
        "loans_started",
        "loans_rolled",
        "loans_repaid",
        "loans_voided",
        "viable_fallbacks",
    ]
    cfg = to_xxl(SC_TINY.config, XXL_V1)
    @test metric_columns(cfg) == vcat(METRIC_COLUMNS, XXL_METRIC_COLUMNS)
    @test metric_columns(cfg; scorecard=false) == metric_columns(cfg)
    @test metric_columns(cfg; scorecard=true) ==
        vcat(METRIC_COLUMNS, XXL_METRIC_COLUMNS, SCORECARD_COLUMNS)
end

@testset "deaths by cause" begin
    m = tiny_model(zeros(Int, 9, 9); spice=true)
    sugar = put_agent(m, 1, 1; metabolism=5, sugar=3.0)  # starves of sugar
    sugar.spice, sugar.spice_metabolism = 10.0, 1
    spice = put_agent(m, 4, 4; metabolism=1, sugar=20.0)  # starves of spice
    spice.spice, spice.spice_metabolism = 2.0, 5
    both = put_agent(m, 7, 7; metabolism=5, sugar=3.0)  # starves of both: sugar
    both.spice, both.spice_metabolism = 2.0, 5
    old = put_agent(m, 1, 6; metabolism=1, sugar=20.0, max_age=1)  # reaches its max age
    old.spice, old.spice_metabolism = 10.0, 1
    tr = ScorecardTracker(m)
    c0 = card(m, tr)
    @test all(
        c0[k] == 0 for
        k in ("deaths_sugar", "deaths_spice", "deaths_old_age", "deaths_killed")
    )
    step!(m)
    @test length(m.dead_this_step) == 4
    c = card(m, tr)
    @test c["deaths_sugar"] == 2
    @test c["deaths_spice"] == 1
    @test c["deaths_old_age"] == 1
    @test c["deaths_killed"] == 0
    # No sex, culture, trade or credit here: their columns don't apply.
    for k in (
        "births",
        "n_fertile",
        "n_fertile_with_mate",
        "tag_flips_per_agent",
        "share_traded_10",
    )
        @test isnan(c[k])
    end
    for k in ("loans_started", "loans_rolled", "loans_repaid", "loans_voided")
        @test isnan(c[k])
    end
    @test c["viable_fallbacks"] == 0
end

@testset "a combat kill under the xxl combat move" begin
    rules = XxlRules(; vision_shape="disc", speed=(3, 3), travel_cost=0.0)
    m = tiny_model(
        zeros(Int, 30, 30); tag_length=11, combat_alpha=Inf, xxl=rules, vision=(3, 3)
    )
    blue = tag!(put_agent(m, 10, 10; vision=3, sugar=20.0), fill(0, 11))
    blue.speed = 3
    red = tag!(put_agent(m, 12, 11; vision=3, sugar=8.0), fill(1, 11))
    red.speed = 3
    tr = ScorecardTracker(m)
    card(m, tr)
    empty!(m.killed)
    Sugarscape.xxl_combat_move!(m, blue)
    @test !red.alive && red.id in m.killed
    m.t += 1  # as step! ends the period
    c = card(m, tr)
    @test c["deaths_killed"] == 1
    @test c["deaths_sugar"] == c["deaths_spice"] == c["deaths_old_age"] == 0
end

@testset "step! empties the kill record" begin
    m = tiny_model(zeros(Int, 5, 5))
    push!(m.killed, 99)
    step!(m)
    @test isempty(m.killed)
end

@testset "fertility and mates in reach" begin
    m = tiny_model(fill(4, 9, 9); sex=true)
    f, h = couple(m)  # fertile, side by side
    lone = put_agent(m, 7, 7; sugar=60.0)  # fertile, nobody in reach
    lone.sex, lone.fertility_start, lone.fertility_end, lone.initial_sugar = :F,
    12, 40,
    60.0
    lone.age = 20
    child = put_agent(m, 3, 2; sugar=60.0)  # next to f, too young
    child.sex, child.fertility_start, child.fertility_end, child.initial_sugar = :M,
    12, 50,
    60.0
    m.viable_fallbacks = 3
    c = card(m, ScorecardTracker(m))
    @test c["n_fertile"] == 3
    @test c["n_fertile_with_mate"] == 2
    @test c["births"] == 0
    @test c["viable_fallbacks"] == 3
end

@testset "a tag flip forced by culture_transmit!" begin
    m = tiny_model(zeros(Int, 9, 9); tag_length=5, culture=true)
    a = tag!(put_agent(m, 2, 2), [1, 1, 1, 1, 1])
    b = tag!(put_agent(m, 3, 2), [0, 0, 0, 0, 0])
    tag!(put_agent(m, 7, 7), [0, 1, 0, 1, 0])  # out of reach: keeps its tags
    tr = ScorecardTracker(m)
    @test isnan(card(m, tr)["tag_flips_per_agent"])  # t = 0: no previous period
    culture_transmit!(m, a)  # b takes one of a's tags
    m.t += 1
    @test sum(tags_of(b)) == 1
    @test card(m, tr)["tag_flips_per_agent"] == 1 / 3
    m.t += 1
    @test card(m, tr)["tag_flips_per_agent"] == 0.0
end

@testset "a trader drops out of share_traded_10 after 10 quiet periods" begin
    m = tiny_model(zeros(Int, 9, 9); spice=true, trade=true)
    a = put_agent(m, 1, 1)
    b = put_agent(m, 2, 1)
    put_agent(m, 6, 6)
    tr = ScorecardTracker(m)
    @test isnan(card(m, tr)["share_traded_10"])
    push!(m.trade_log, Exchange(1.0, 1.0, 1.0, a, b))
    m.t += 1
    @test card(m, tr)["share_traded_10"] == 2 / 3
    for t in 2:10
        empty!(m.trade_log)
        m.t += 1
        @test card(m, tr)["share_traded_10"] == 2 / 3  # traded in t - 9 .. t
    end
    m.t += 1
    @test card(m, tr)["share_traded_10"] == 0.0  # period 1 is now 10 periods back
end

@testset "a rollover then the borrower's death: one chain, voided once" begin
    m = tiny_model(zeros(Int, 9, 9); sex=true, credit=(5, 0.0))
    lender = put_agent(m, 1, 1; sugar=100.0)
    borrower = put_agent(m, 6, 6; metabolism=4, sugar=10.0)  # sex :none: neither seeks nor lends
    Sugarscape.add_loan!(m, Loan(lender, borrower, 50.0, 50.0, 0))  # due at the end of period 0
    tr = ScorecardTracker(m)
    c0 = card(m, tr)
    @test all(
        c0[k] == 0 for
        k in ("loans_started", "loans_rolled", "loans_repaid", "loans_voided")
    )
    step!(m)  # 10 - 4 = 6 < 50: pays 3, the rest rolls into a new loan
    @test length(m.loans) == 1 && m.loans[1].due == 47.0
    c1 = card(m, tr)
    @test (
        c1["loans_started"], c1["loans_rolled"], c1["loans_repaid"], c1["loans_voided"]
    ) == (0, 1, 0, 0)
    step!(m)  # 3 - 4 < 0: the borrower starves
    @test !borrower.alive && isempty(m.loans)
    c2 = card(m, tr)
    @test (
        c2["loans_started"], c2["loans_rolled"], c2["loans_repaid"], c2["loans_voided"]
    ) == (0, 0, 0, 1)
    @test c2["deaths_sugar"] == 1
end

@testset "a loan repaid, and a loan started, by the model's own rules" begin
    m = tiny_model(zeros(Int, 9, 9); sex=true, credit=(5, 0.0))
    lender = put_agent(m, 1, 1; sugar=100.0)
    borrower = put_agent(m, 6, 6; sugar=80.0)
    Sugarscape.add_loan!(m, Loan(lender, borrower, 20.0, 20.0, 0))
    tr = ScorecardTracker(m)
    card(m, tr)
    step!(m)
    c = card(m, tr)
    @test isempty(m.loans)
    @test (c["loans_started"], c["loans_rolled"], c["loans_repaid"], c["loans_voided"]) ==
        (0, 0, 1, 0)
    # A borrower of childbearing age short of sugar next to a lender beyond it: seek_credit! lends.
    lender.sex, lender.fertility_start, lender.fertility_end, lender.initial_sugar = :F,
    12, 40,
    10.0
    lender.age = 50
    b = put_agent(m, 2, 1; sugar=5.0)
    b.sex, b.fertility_start, b.fertility_end, b.initial_sugar = :M, 12, 50, 30.0
    b.age, b.last_income = 20, 100.0
    tr = ScorecardTracker(m)
    card(m, tr)
    made = seek_credit!(m, b)
    @test length(made) == 1
    m.t += 1
    c = card(m, tr)
    @test (c["loans_started"], c["loans_rolled"], c["loans_repaid"], c["loans_voided"]) ==
        (1, 0, 0, 0)
end

@testset "a 30-period VI-1 run: births and loans against the standard columns" begin
    vi1 = sc_cut(find_experiment(SC_REG, "VI-1"), 30)
    rows, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_V1, scorecard=true)
    plain, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_V1)
    cols = ["t"; metric_columns(to_xxl(vi1.config, XXL_V1); scorecard=true)]
    @test all(length(r) == length(cols) == 69 for r in rows)
    @test all(isequal(r[1:55], p) for (r, p) in zip(rows, plain))
    col(name) = [r[findfirst(==(name), cols)] for r in rows]
    births, ever, loans = col("births"), col("agents_ever"), col("n_loans")
    pop = col("population")
    started, rolled, repaid, voided = col("loans_started"),
    col("loans_rolled"), col("loans_repaid"),
    col("loans_voided")
    deaths =
        col("deaths_sugar") .+ col("deaths_spice") .+ col("deaths_old_age") .+
        col("deaths_killed")
    @test births[1] == 0 && deaths[1] == 0
    @test started[1] == rolled[1] == repaid[1] == voided[1] == 0
    @test isnan(col("tag_flips_per_agent")[1]) && isnan(col("share_traded_10")[1])
    for i in 2:length(rows)
        @test births[i] == ever[i] - ever[i - 1]  # no replacement in VI-1
        @test pop[i] - pop[i - 1] == births[i] - deaths[i]
        # A rollover replaces its loan; every other new loan adds one, every other ending removes one.
        @test loans[i] - loans[i - 1] == started[i] - repaid[i] - voided[i]
    end
    @test sum(births) > 0 && sum(started) > 0 && sum(repaid) + sum(rolled) > 0
    @test all(col("tag_flips_per_agent")[2:end] .> 0)
    @test all(0 .< col("share_traded_10")[2:end] .<= 1)
    @test all(col("n_fertile_with_mate") .<= col("n_fertile"))
    @test all(col("viable_fallbacks") .== 0)  # XXL_V1 places at random
end

@testset "run_experiment with scorecard=true" begin
    out = mktempdir()
    Sugarscape.run_experiment(SC_TINY; out=out, xxl=XXL_V1, scorecard=true)
    with = readlines(joinpath(out, "TEST-tiny", "seed0.csv"))
    out2 = mktempdir()
    Sugarscape.run_experiment(SC_TINY; out=out2, xxl=XXL_V1)
    without = readlines(joinpath(out2, "TEST-tiny", "seed0.csv"))
    @test split(with[1], ",") ==
        ["t"; METRIC_COLUMNS; XXL_METRIC_COLUMNS; SCORECARD_COLUMNS]
    @test without[1] == "t," * join([METRIC_COLUMNS; XXL_METRIC_COLUMNS], ",")
    @test length(with) == length(without) == 7
    for (w, p) in zip(with[2:end], without[2:end])
        fields = split(w, ",")
        @test length(fields) == 69
        @test join(fields[1:55], ",") == p
    end
    @test_throws ArgumentError Sugarscape.run_experiment(SC_TINY; out=out, scorecard=true)
    @test_throws ArgumentError Sugarscape.timed_seed(SC_TINY, 0; scorecard=true)
end

@testset "seed_job passes scorecard only when it is set" begin
    stand_in(exp, k; xl=false, xxl=nothing) = ([[0.0]], (; seed=k))
    @test Sugarscape.seed_job(SC_TINY, 0, false, stand_in; xxl=XXL_BOOK)[1] == [[0.0]]
    with_card(exp, k; xl=false, xxl=nothing, scorecard=false) =
        ([[scorecard ? 1.0 : 0.0]], (; seed=k))
    @test Sugarscape.seed_job(
        SC_TINY, 0, false, with_card; xxl=XXL_BOOK, scorecard=true
    )[1] == [[1.0]]
end

@testset "first_seed runs seed indices K .. K + seeds - 1" begin
    full = mktempdir()
    Sugarscape.run_experiment(SC_TINY; out=full, seeds=5)
    for jobs in (1, 2)
        out = mktempdir()
        folder = mkpath(joinpath(out, "TEST-tiny"))
        write(joinpath(folder, "seed0.csv"), "another seed set")
        write(joinpath(folder, "seed3.csv"), "old")
        Sugarscape.run_experiment(SC_TINY; out=out, seeds=2, first_seed=3, jobs=jobs)
        @test sort(filter(f -> startswith(f, "seed"), readdir(folder))) ==
            ["seed0.csv", "seed3.csv", "seed4.csv"]
        @test read(joinpath(folder, "seed0.csv"), String) == "another seed set"
        for k in (3, 4)  # cfg.seed + k, as in the full run
            @test read(joinpath(folder, "seed$k.csv"), String) ==
                read(joinpath(full, "TEST-tiny", "seed$k.csv"), String)
        end
        timing = readlines(joinpath(folder, "timing.csv"))
        @test startswith(timing[2], "3,") && startswith(timing[3], "4,")
    end
    # The default first seed still clears every old seed file.
    out = mktempdir()
    folder = mkpath(joinpath(out, "TEST-tiny"))
    write(joinpath(folder, "seed7.csv"), "stale")
    Sugarscape.run_experiment(SC_TINY; out=out, seeds=1)
    @test !isfile(joinpath(folder, "seed7.csv")) && isfile(joinpath(folder, "seed0.csv"))
end
