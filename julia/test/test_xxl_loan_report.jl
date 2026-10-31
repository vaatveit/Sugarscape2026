# xxl: the loan trace's files and report (docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md, "A script
# and a report"). Small tables built by hand pin each number; a short VI-1 run pins the files.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape:
    LoanTrace,
    tally,
    census_row,
    write_trace_files,
    read_tally,
    read_census,
    merge_tallies,
    merge_census,
    x8_share,
    age_ratios,
    matched_ratios,
    child_shares,
    trace_readings,
    credit_off_reading,
    loan_summary,
    summarize_trace,
    window_stats,
    loan_report,
    trace_matches_scorecard,
    with_steps,
    write_seed_csv,
    format_value

const LR_REG = load_registry()

# Window 1: 100 started, the lender in band 60, the borrower in band 20; 75 repaid, 20 voided by the lender, 5 by the
# borrower. Band 60 lost 30 of 100 to old age, band 20 10 of 200 to sugar.
lr_tally() = Dict{NTuple{4,String},Float64}(
    ("1", "started", "", "") => 100.0,
    ("1", "started_bands", "60", "20") => 100.0,
    ("1", "ended", "repaid", "") => 75.0,
    ("1", "ended", "voided_lender", "") => 20.0,
    ("1", "ended", "voided_borrower", "") => 5.0,
)
lr_row(window, group, band; n=0.0, children=0.0, old_age=0.0, sugar=0.0, spice=0.0, killed=0.0) =
    (; window, group, band, n, children, old_age, sugar, spice, killed)
lr_census() = [lr_row("1", "all", "60"; n=100.0, old_age=30.0), lr_row("1", "all", "20"; n=200.0, sugar=10.0)]

# What trace_readings reads: every line quiet, then one thing changed.
lr_quiet() = (;
    age=(borrower=1.5, lender=1.5),
    lender_only=0.3,
    doomed=0.1,
    matched=(borrower=Dict("all" => 1.3, "sugar" => 1.0, "spice" => 1.0), lender=Dict("all" => 1.0), excluded=0),
    child=(borrowing=0.8, could_borrow=0.5),
)
lr_with(s; kw...) = merge(s, NamedTuple(kw))
lr_fires(s, word) = any(occursin(word, l) for l in trace_readings(s))

@testset "loan report: X8" begin
    @test x8_share(lr_tally(), [1]) == 0.25
    @test x8_share(lr_tally(), 1:2) == 0.25
    @test isnan(x8_share(Dict{NTuple{4,String},Float64}(), [1]))
    @test isnan(x8_share(lr_tally(), [2]))
end

@testset "loan report: the age ratio" begin
    r = age_ratios(lr_tally(), lr_census(), [1])
    @test r.lender ≈ 20 / 30
    @test r.borrower == 1
    # Half the loans are still open: expected deaths halve with them, so nothing changes.
    t = lr_tally()
    t[("1", "started", "", "")] = 200.0
    t[("1", "started_bands", "60", "20")] = 200.0
    r = age_ratios(t, lr_census(), [1])
    @test r.lender ≈ 20 / 30 && r.borrower == 1
    # A voided_both counts on both sides.
    t = lr_tally()
    t[("1", "ended", "voided_both", "")] = 5.0
    t[("1", "ended", "repaid", "")] = 70.0
    r = age_ratios(t, lr_census(), [1])
    @test r.lender ≈ 25 / 30 && r.borrower ≈ 10 / 5
    # Two windows add their expected and observed deaths before dividing.
    t2 = merge(lr_tally(), Dict(("2", k[2], k[3], k[4]) => v for (k, v) in lr_tally()))
    c2 = vcat(
        lr_census(), [lr_row("2", c.group, c.band; n=2c.n, old_age=2c.old_age, sugar=2c.sugar) for c in lr_census()]
    )
    @test age_ratios(t2, c2, 1:2).lender ≈ 20 / 30
    # A window with loans and voids but no census at all is left out of both sides.
    t3 = merge(lr_tally(), Dict(("2", k[2], k[3], k[4]) => v for (k, v) in lr_tally()))
    @test isequal(age_ratios(t3, lr_census(), [1, 2]), age_ratios(t3, lr_census(), [1]))
    @test isnan(age_ratios(t3, lr_census(), [2]).lender)
    # No census to give a death rate: nothing to compare with.
    @test isnan(age_ratios(lr_tally(), [], [1]).lender)
end

@testset "loan report: the age ratio by cause" begin
    t = lr_tally()
    t[("1", "void_cause", "lender", "old_age")] = 20.0
    t[("1", "void_cause", "lender", "spice")] = 10.0
    c = [lr_row("1", "all", "60"; n=100.0, old_age=30.0, spice=10.0), lr_row("1", "all", "20"; n=200.0, sugar=10.0)]
    r = age_ratios(t, c, [1])
    @test r.by_cause.lender["old_age"] ≈ 20 / 30 && r.by_cause.lender["spice"] ≈ 1.0
    @test isnan(r.by_cause.lender["killed"]) && isnan(r.by_cause.borrower["old_age"])
    t[("1", "void_cause", "borrower", "sugar")] = 5.0
    @test age_ratios(t, c, [1]).by_cause.borrower["sugar"] ≈ 1.0
    # A window with no census is left out here too.
    t2 = merge(t, Dict(("2", k[2], k[3], k[4]) => v for (k, v) in t))
    @test isequal(age_ratios(t2, c, [1, 2]).by_cause, age_ratios(t, c, [1]).by_cause)
end

@testset "loan report: the matched ratio" begin
    c = [
        lr_row("1", "borrowing", "20"; n=100.0, sugar=10.0),
        lr_row("1", "could_borrow", "20"; n=200.0, sugar=10.0),
        lr_row("1", "lending", "60"; n=50.0, old_age=10.0),
        lr_row("1", "could_lend", "60"; n=100.0, old_age=10.0),
    ]
    r = matched_ratios(c, [1])
    @test r.borrower["sugar"] == 2.0
    @test r.borrower["all"] == 2.0
    @test isnan(r.borrower["spice"])
    @test r.lender["old_age"] == 2.0
    @test r.excluded == 0
    # A band with no comparison group is left out of both sides.
    r = matched_ratios(vcat(c, [lr_row("1", "borrowing", "25"; n=10.0, sugar=9.0)]), [1])
    @test r.borrower["sugar"] == 2.0 && r.excluded == 10
    # A window not asked for isn't read.
    @test isnan(matched_ratios(c, [2]).borrower["sugar"])

    # Each window is compared within itself: borrowers die as often as could-borrow agents in both, but the groups
    # are spread differently over the windows, so pooling them would read 1.4.
    two = [
        lr_row("1", "borrowing", "20"; n=300.0, sugar=60.0),
        lr_row("1", "could_borrow", "20"; n=100.0, sugar=20.0),
        lr_row("2", "borrowing", "20"; n=100.0, sugar=10.0),
        lr_row("2", "could_borrow", "20"; n=300.0, sugar=30.0),
    ]
    @test matched_ratios(two, 1:2).borrower["sugar"] == 1.0 && matched_ratios(two, 1:2).borrower["all"] == 1.0
    # A band with a comparison group in another window only is still left out, and counted.
    r = matched_ratios(vcat(two, [lr_row("1", "borrowing", "25"; n=10.0, sugar=9.0),
                                  lr_row("2", "could_borrow", "25"; n=50.0, sugar=5.0)]), 1:2)
    @test r.borrower["sugar"] == 1.0 && r.excluded == 10
end

@testset "loan report: the child shares" begin
    c = [
        lr_row("1", "borrowing", "20"; n=100.0, children=50.0),
        lr_row("1", "could_borrow", "20"; n=100.0, children=40.0),
    ]
    s = child_shares(c, [1])
    @test s.borrowing == 0.5 && s.could_borrow == 0.4
    @test all(isnan, child_shares(c, [2]))
end

@testset "loan report: the readings" begin
    quiet = lr_quiet()
    @test length(trace_readings(quiet)) == 1  # only the closing line, which names what was checked
    @test occursin("checked", only(trace_readings(quiet)))
    age(b, l) = lr_with(quiet; age=(borrower=b, lender=l))
    for (x, fires) in ((0.9, true), (1.1, true), (0.89, false), (1.11, false))
        @test lr_fires(age(x, 1.0), "lifespan") == fires
        @test lr_fires(age(1.0, x), "lifespan") == fires
    end
    for (x, fires) in ((0.5, false), (0.51, true))
        @test lr_fires(lr_with(quiet; lender_only=x), "old lend") == fires
    end
    for (x, fires) in ((0.25, false), (0.26, true))
        @test lr_fires(lr_with(quiet; doomed=x), "old lend") == fires
    end
    matched(x; key="sugar") = lr_with(
        quiet;
        matched=(borrower=Dict("all" => 1.0, "sugar" => 1.0, "spice" => 1.0, key => x), lender=Dict(), excluded=0),
    )
    for (x, fires) in ((1.1, false), (1.11, true))
        @test lr_fires(matched(x), "defect") == fires
        @test lr_fires(matched(x; key="spice"), "defect") == fires
        @test !lr_fires(matched(x; key="all"), "defect")
    end
    child(x) = lr_with(quiet; child=(borrowing=x, could_borrow=1.0))
    for (x, fires) in ((1.1, true), (1.11, false), (0.5, true))
        @test lr_fires(child(x), "isn't doing its job") == fires
    end
    # The note: the borrowers' age ratio is high but their matched ratio is not.
    note(age, m) = lr_with(
        quiet; age=(borrower=age, lender=1.5), matched=(borrower=Dict("all" => m, "sugar" => 1.0, "spice" => 1.0),
                                                       lender=Dict(), excluded=0)
    )
    @test lr_fires(note(1.2, 1.0), "who borrows, not from the loan")
    @test !lr_fires(note(1.2, 1.3), "who borrows, not from the loan")
    @test !lr_fires(note(1.0, 1.0), "who borrows, not from the loan")
end

@testset "loan report: credit off" begin
    base = (births=1000.0, population=20000.0)
    @test credit_off_reading(base, (births=951.0, population=19020.0)) isa String  # 4.9% below
    @test credit_off_reading(base, (births=1049.0, population=20900.0)) isa String
    @test credit_off_reading(base, (births=949.0, population=19020.0)) === nothing  # 5.1% below
    @test credit_off_reading(base, (births=951.0, population=18980.0)) === nothing
    @test credit_off_reading(base, (births=NaN, population=19020.0)) === nothing
end

@testset "loan report: the figures" begin
    t = lr_tally()
    t[("1", "ended", "voided_both", "")] = 5.0
    for (key, v) in (
        (("void_elapsed", "voided_lender", "4"), 15.0),  # a median of 4 of the 20 lender voids
        (("void_elapsed", "voided_lender", "8"), 5.0),
        (("void_elapsed", "repaid", "10"), 75.0),  # a repaid chain's elapsed time isn't a void's
        (("doomed", "lender", "voided_lender"), 10.0),
        (("doomed", "neither", "voided_lender"), 10.0),
        (("doomed", "neither", "repaid"), 75.0),
        (("principal", "repaid", ""), 750.0),
        (("principal", "voided_lender", ""), 200.0),
        (("received", "repaid", ""), 1500.0),
        (("received", "voided_lender", ""), 50.0),
        (("void_age", "lender", "60"), 8.0),
        (("void_age", "lender", "40"), 2.0),
    )
        t[("1", key...)] = v
    end
    w = window_stats(t, lr_census(), [1])
    @test w.elapsed["voided_lender"] == 4 && isnan(w.elapsed["voided_both"])
    @test w.lender_only == 20 / 30 && w.doomed == 10 / 30
    @test w.voided_share == 200 / 950 && w.received_per_lent == 1550 / 950
    @test w.kept == 150 && w.kept_share == 0.75
    @test w.old_share["lender"] == 0.8 && w.median_age["lender"] == 60
    @test w.census_n == 300
end

@testset "loan report: nothing to divide by" begin
    empty = Dict{NTuple{4,String},Float64}()
    s = summarize_trace(Int[], [], [], Float64[])
    ages = age_ratios(empty, [], 1:2)
    @test all(isnan, (x8_share(empty, 1:2), ages.borrower, ages.lender, values(ages.by_cause.borrower)..., values(ages.by_cause.lender)...))
    reading = join(trace_readings(s.check), " ")
    @test occursin("Could not be read", reading) && occursin("the age ratio", reading) && !occursin("NaN", reading)
    @test occursin("checked", reading) && !lr_fires(s.check, "defect")
    report = loan_report(s; label="none", world="w", first_seed=20, seeds=2, periods=500, jobs=nothing, wall=nothing)
    @test occursin("—", report) && !occursin("NaN", report) && !occursin("nan", report)
    @test occursin("- Seeds finished: 0 of 2 (20–21)", report)
    @test occursin("## Reading", report)
    # A seed that has tallies but no census, and no loans ended.
    t = Dict{NTuple{4,String},Float64}(("1", "started", "", "") => 3.0)
    report = loan_report(
        summarize_trace([20], [t], [[]], [NaN]);
        label="short", world="w", first_seed=20, seeds=1, periods=10, jobs=nothing, wall=nothing,
    )
    @test !occursin("NaN", report) && occursin("- Loans started: 3", report)
end

# A short traced VI-1 and its files, for the next tests.
function lr_run(folder; steps=120, scorecard=false)
    vi1 = with_steps(find_experiment(LR_REG, "VI-1"), steps)
    tr = LoanTrace(10; census_every=40)
    rows, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_DEFAULTS, scorecard=scorecard, loan_trace=tr)
    write_trace_files(folder, 0, tr)
    return tr, rows, vi1
end

@testset "loan report: files read back" begin
    mktempdir() do folder
        tr, _, _ = lr_run(folder)
        @test tally(tr, 1, "started") > 0 && !isempty(tr.sampled)
        t = read_tally(joinpath(folder, "seed0.tally.csv"))
        census = read_census(joinpath(folder, "seed0.census.csv"))
        plain = Dict((string(k[1]), k[2], k[3], k[4]) => v for (k, v) in tr.tallies if !startswith(k[2], "census_"))
        @test t == plain
        @test !isempty(census) && !any(k -> startswith(k[2], "census_"), keys(t))
        for r in census
            row = census_row(tr, parse(Int, r.window), r.group, r.band)
            @test (r.n, r.children, r.old_age, r.sugar, r.spice, r.killed) == Float64.(values(row))
        end
        total_n = sum(v for (k, v) in tr.tallies if k[2] == "census_n" && k[3] == "all")
        @test sum(r.n for r in census if r.group == "all") == total_n
        rows = readlines(joinpath(folder, "seed0.loans.csv"))
        @test split(rows[1], ",") == Sugarscape.TRACE_SAMPLE_COLUMNS && length(rows) == length(tr.sampled) + 1
        @test !any(f -> endswith(f, ".tmp"), readdir(folder))
    end
end

@testset "loan report: the scorecard's counts" begin
    mktempdir() do folder
        tr, rows, vi1 = lr_run(folder; scorecard=true)
        columns = metric_columns(to_xxl(vi1.config, XXL_DEFAULTS); scorecard=true)
        csv = joinpath(folder, "scorecard.csv")
        write_seed_csv(csv, rows; columns=columns)
        tally_path = joinpath(folder, "seed0.tally.csv")
        @test trace_matches_scorecard(tally_path, csv)
        voided = findfirst(==("loans_voided"), ["t"; columns])
        changed = [copy(r) for r in rows]
        changed[50][voided] += 1
        write_seed_csv(csv, changed; columns=columns)
        @test !trace_matches_scorecard(tally_path, csv)
    end
end

@testset "loan report: one seed, and two" begin
    a, b = lr_tally(), lr_tally()
    b[("1", "started", "", "")] = 50.0
    b[("2", "started", "", "")] = 7.0
    m = merge_tallies([a, b])
    @test m[("1", "started", "", "")] == 150.0 && m[("2", "started", "", "")] == 7.0
    @test m[("1", "ended", "repaid", "")] == 150.0
    c = merge_census([lr_census(), lr_census()])
    @test length(c) == 2 && c[1].n + c[2].n == 600.0
    # Seeds at X8 0.2 and 0.3 average 0.25, however many loans each made.
    t2 = Dict{NTuple{4,String},Float64}(
        ("1", "started", "", "") => 10.0,
        ("1", "ended", "repaid", "") => 80.0,
        ("1", "ended", "voided_lender", "") => 20.0,
    )
    t3 = Dict{NTuple{4,String},Float64}(
        ("1", "started", "", "") => 20.0,
        ("1", "ended", "repaid", "") => 140.0,
        ("1", "ended", "voided_lender", "") => 60.0,
    )
    s = summarize_trace([20, 21], [t2, t3], [[], []], [10.0, 20.0])
    @test s.x8 ≈ 0.25 && s.x8 != x8_share(merge_tallies([t2, t3]), 1:2)
    kw = (; label="x", world="w", first_seed=20, periods=500, jobs=nothing, wall=nothing)
    report = loan_report(s; seeds=2, kw...)
    @test occursin("- X8, t = 1–500: 0.25\n", report) && occursin("- Seeds finished: 2 of 2 (20–21)", report)
    @test occursin("- Loans started: 30\n", report) && !occursin("**Unfinished", report)
    one = summarize_trace([20], [t2], [[]], [10.0])
    report = loan_report(one; seeds=2, kw...)
    @test occursin("- Seeds finished: 1 of 2 (20–21)", report)
    @test occursin("**Unfinished: 1 of 2 seeds have not run", report)
    @test occursin("- X8, t = 1–500: 0.2\n", report) && occursin("# Loan trace: x", report)
    @test occursin("The groups aren't randomized, so the matched figures are evidence, not proof.", report)
end

@testset "loan report: X8 is the mean over seeds in every column" begin
    seed(started, repaid, voided) = Dict{NTuple{4,String},Float64}(
        ("$w", k, o, "") => v for w in 1:2 for (k, o, v) in
        (("started", "", started), ("ended", "repaid", repaid), ("ended", "voided_lender", voided))
    )
    a, b = seed(10.0, 80.0, 20.0), seed(20.0, 140.0, 60.0)  # X8 0.2 and 0.3; pooled it is 0.2667
    s = summarize_trace([20, 21], [a, b], [[], []], [1.0, 2.0])
    @test [c.label for c in s.windows] == ["1–100", "101–500", "1–500"]
    @test all(c.x8 ≈ 0.25 for c in s.windows) && s.check.x8 ≈ 0.25 && s.x8 ≈ 0.25
    report = loan_report(s; label="x", world="w", first_seed=20, seeds=2, periods=500, jobs=nothing, wall=nothing)
    @test occursin("- X8, t = 1–500: 0.25
", report) && occursin("| 0.25 | 0.25 | 0.25 |", report)
    @test occursin("| X8, mean over seeds | 0.25 | 0.25 | 0.25 |", report)
end

@testset "loan report: the cohorts and the agents followed" begin
    seed(cohorts) = Dict{NTuple{4,String},Float64}(("1", "started", "", "") => 5.0, ("1", "cohorts", "", "") => cohorts)
    census = [lr_row("1", "all", "20"; n=10.0)]
    s = summarize_trace([20, 21], [seed(2.0), seed(3.0)], [census, census], [1.0, 2.0])
    @test s.windows[1].cohorts == 5 && s.windows[1].census_n == 20
    report = loan_report(s; label="x", world="w", first_seed=20, seeds=2, periods=500, jobs=nothing, wall=nothing)
    @test occursin("| Census cohorts | 5 |", report) && occursin("| Agents followed, counted once per census | 20 |", report)
    @test !occursin("| Agents followed |", report)
end

@testset "loan report: the reading of a later window" begin
    early = Dict{NTuple{4,String},Float64}(("1", "started", "", "") => 5.0, ("1", "ended", "repaid", "") => 5.0)
    late = merge(early, Dict(("3", "started", "", "") => 5.0, ("3", "ended", "repaid", "") => 5.0))
    kw = (; label="x", world="w", first_seed=20, seeds=1, periods=600, jobs=nothing, wall=nothing)
    short = loan_report(summarize_trace([20], [early], [[]], [1.0]); kw...)
    long = loan_report(summarize_trace([20], [late], [[]], [1.0]); kw...)
    @test occursin("### t = 1–500", short) && !occursin("### t = 501–end", short)
    @test occursin("### t = 1–500", long) && occursin("### t = 501–end", long)
    @test findfirst("### t = 1–500", long).start < findfirst("### t = 501–end", long).start
end

@testset "loan report: a seed counts only with all its files" begin
    mktempdir() do folder
        tr, rows, vi1 = lr_run(folder)
        columns = metric_columns(to_xxl(vi1.config, XXL_DEFAULTS))
        write_seed_csv(joinpath(folder, "seed0.csv"), rows; columns=columns)
        @test loan_summary(folder, 0:1, 120).seeds == [0]
        rm(joinpath(folder, "seed0.loans.csv"))
        @test isempty(loan_summary(folder, 0:1, 120).seeds)
        write_trace_files(folder, 0, tr)
        s = loan_summary(folder, 0:1, 120)
        @test s.seeds == [0] && s.started == sum(tally(tr, w, "started") for w in 1:3)
        report = loan_report(s; label="run", world="VI-1", first_seed=0, seeds=2, periods=120, jobs=2, wall=5.0)
        @test !occursin("NaN", report) && occursin("**Unfinished", report)
        @test occursin("| Seed |", report) && occursin("with --jobs 2", report)
        @test report == loan_report(loan_summary(folder, 0:1, 120); label="run", world="VI-1", first_seed=0, seeds=2,
                                    periods=120, jobs=2, wall=5.0)
    end
end
