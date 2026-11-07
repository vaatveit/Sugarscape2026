# xxl (stage 6): the sex report (julia/src/xxl/sex_report.jl), on hand-written study folders: a fingerprint, and per seed
# the standard CSV, the per-period sex table, the agent snapshot and a timing file, each with known values.
using Sugarscape, Test
using Sugarscape: sex_report, sex_report_args, sex_report_main, read_sex_world, sex_bars, sex_outcome, SEX_COLUMNS,
                  SEX_AGENT_COLUMNS, M_FACTOR, MIN_FERTILE_PERIODS, TROUGH_HALF, MIN_SEEDS, S_SHARE, S_MIN_BOOK_DROP,
                  RESULTS_XXL, bar_figure, run_sex_world

const SR_PERIODS = 30
const SR_WINDOW = (11, 30)

sr_value(x::Real) = isnan(x) ? "NaN" : isinteger(x) ? string(Int(x)) : string(Float64(x))
sr_write(path, header, rows) =
    write(path, join([join(header, ","); [join(sr_value.(r), ",") for r in rows]], "\n") * "\n")
sr_series(x, periods) = x isa AbstractVector ? Float64.(x) : fill(Float64(x), periods + 1)

"""
One seed of a hand-written folder. `population`, `fertile` and `reach` are a number (every period) or a vector over
t = 0..periods; `met` is mean metabolism at t = 0 and at the last period; `agents` the snapshot's (periods_fertile,
children) pairs, each ending at the window's last period.
"""
function sr_seed(folder, k; periods=SR_PERIODS, window=SR_WINDOW, population=100, eligible=50, fertile=100, reach=70,
                 vision=80, births=2, no_site=1, met=(2.0, 1.2), agents=[(10, 1)], speed=NaN)
    pop = sr_series(population, periods)
    metab = fill(met[1], periods + 1)
    metab[end] = met[2]
    sr_write(joinpath(folder, "seed$k.csv"), ["t", "population", "agents_ever", "mean_metabolism"],
             [[t, pop[t + 1], 200, metab[t + 1]] for t in 0:periods])
    f, r = sr_series(fertile, periods), sr_series(reach, periods)
    sex = map(0:periods) do t
        Dict("t" => t, "population" => pop[t + 1], "eligible" => eligible, "fertile" => f[t + 1],
             "fertile_reach" => r[t + 1], "fertile_vision" => vision, "births" => births, "no_site" => no_site,
             "mean_distance" => 2.0, "median_distance" => 1.0, "mean_distance_share" => 0.5,
             "median_distance_share" => 0.25, "mean_vision" => 3.0, "sd_vision" => 1.0,
             "mean_metabolism" => metab[t + 1], "sd_metabolism" => 0.5, "mean_spice_metabolism" => 2.5,
             "sd_spice_metabolism" => 0.5, "mean_speed" => speed, "sd_speed" => speed)
    end
    sr_write(joinpath(folder, "seed$k-sex.csv"), SEX_COLUMNS, [[d[c] for c in SEX_COLUMNS] for d in sex])
    rows = [[i, i % 2, window[2], 0, pf, pf, pf, pf, c, 3, 2, NaN] for (i, (pf, c)) in enumerate(agents)]
    sr_write(joinpath(folder, "seed$k-agents.csv"), SEX_AGENT_COLUMNS, rows)
    write(joinpath(folder, "seed$k.timing.csv"), "setup_s,stepping_s,metrics_s\n0.1,1.0,0.1\n")
    return nothing
end

"""A world's folder of `n` seeds from 80; `kw(i)` gives seed i's (1-based) keywords. Returns its path."""
function sr_folder(out, world; named=world, n=20, periods=SR_PERIODS, window=SR_WINDOW, kw=i -> (;))
    folder = joinpath(out, "sex-$world-VI-1-s80-$n-p$periods")
    mkpath(folder)
    write(joinpath(folder, "fingerprint.txt"),
          "Config(hand-written)\ncode sha256=0\nperiods=$periods\nsex readings: world=$named window=$window\n")
    for i in 1:n
        sr_seed(folder, 79 + i; periods, window, kw(i)...)
    end
    return folder
end

# A snapshot of 10 agents fertile for 10 periods, `none` of them childless.
sr_agents(none) = [(10, i <= none ? 0 : 1) for i in 1:10]
# Tight seeds: a no-mate share of `share` give or take 0.01.
sr_reach(share, i) = round(Int, 100 * (1 - share)) + (isodd(i) ? 1 : -1)

# The three worlds: the book's no-mate and childless shares 0.3, today's 0.6, xl's 0.45; drops 0.4, 0.3, 0.35.
function sr_worlds(out; book=i -> (;), xl=i -> (;), today=i -> (;))
    b = sr_folder(out, "book"; kw=i -> (; reach=sr_reach(0.3, i), agents=sr_agents(3), met=(2.0, 1.2), book(i)...))
    x = sr_folder(out, "xl"; kw=i -> (; reach=sr_reach(0.45, i), agents=sr_agents(4), met=(2.0, 1.3), xl(i)...))
    t = sr_folder(out, "today";
                  kw=i -> (; reach=sr_reach(0.6, i), agents=sr_agents(6), met=(2.0, 1.4), speed=1.5, today(i)...))
    return (; book=b, xl=x, today=t)
end

sr_report(f; md=joinpath(mktempdir(), "sex-part1.md")) = sex_report(; f..., md, io=devnull)

@testset "xxl sex report: the bar constants are the spec's" begin
    @test M_FACTOR == 1.5
    @test MIN_FERTILE_PERIODS == 5
    @test TROUGH_HALF == 25
    @test MIN_SEEDS == 15
    @test S_SHARE == 0.5
    @test S_MIN_BOOK_DROP == 0.1
end

@testset "xxl sex report: a figure on a bar's edge shows the digits that decide it" begin
    @test bar_figure(2.0, 1.5) == "2"
    @test bar_figure(1.49996, 1.5) == "1.49996"
    @test bar_figure(1.00001, 1; strict=true) == "1.00001"
    @test bar_figure(NaN, 1.5) == "—"
end

@testset "xxl sex report: a seed's values are its totals in the window" begin
    out = mktempdir()
    # fertile 100, reach 70, vision 80, eligible 50 of 100, births 2 and 1 no_site per period; 4 snapshot agents, the one
    # fertile for 4 periods not counted; metabolism 2.0 -> 1.2
    folder = sr_folder(out, "book"; n=1, kw=i -> (; agents=[(10, 0), (5, 1), (4, 0), (12, 2)]))
    w = read_sex_world("book", folder)
    @test w.window == SR_WINDOW && w.periods == SR_PERIODS && w.planned == 1
    v = only(w.seeds).values
    @test v.no_mate ≈ 0.3
    @test v.childless ≈ 1 / 3
    @test v.drop ≈ 0.4
    @test v.eligible ≈ 0.5
    @test v.fertile ≈ 1.0
    @test v.blocked ≈ -1.0  # fertile 100 of 50 eligible: a hand value, not a world's
    @test v.no_vision ≈ 0.2
    @test v.births ≈ 0.02
    @test v.no_site ≈ 0.5
    @test v.mean_distance ≈ 2.0 && v.median_distance ≈ 1.0
    @test v.mean_distance_share ≈ 0.5 && v.median_distance_share ≈ 0.25
    @test v.mean_vision_start == 3.0 && v.mean_metabolism_end ≈ 1.2
    @test isnan(v.mean_speed_start)
end

@testset "xxl sex report: the trough window is clipped at t = 1" begin
    out = mktempdir()
    periods = 60
    # the lowest population is at t = 1, so the window is t = 1..26: reach 50 there, 0 at t = 0 and 100 after
    pop = [100; 10; fill(100, periods - 1)]
    reach = [0; fill(50, 26); fill(100, periods - 26)]
    folder = sr_folder(out, "today"; n=1, periods, window=(31, 60), kw=i -> (; population=pop, reach=reach))
    v = only(read_sex_world("today", folder).seeds).values
    @test v.trough ≈ 0.5
    @test v.no_mate ≈ 0.0
    # a trough later on is the first lowest, its window both sides of it
    pop2 = [100; fill(100, 29); 10; fill(100, 9); 10; fill(100, periods - 40)]
    reach2 = [fill(0, 5); fill(40, 51); fill(0, periods - 55)]  # t = 5..55 is the trough's window (30 ± 25)
    folder2 = sr_folder(mktempdir(), "today"; n=1, periods, window=(31, 60), kw=i -> (; population=pop2, reach=reach2))
    @test only(read_sex_world("today", folder2).seeds).values.trough ≈ 0.6
end

@testset "xxl sex report: M1 and M2 read the hand values and hold; M holds" begin
    out = mktempdir()
    f = sr_worlds(out)
    md = joinpath(mktempdir(), "sub", "sex-part1.md")
    text = sex_report(; f..., md, io=devnull)
    @test isfile(md) && read(md, String) == text
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m1.ratio ≈ 2.0
    @test bars.m1.lo > 1
    @test bars.m1.result == :holds
    @test bars.m2.ratio ≈ 2.0
    @test bars.m2.result == :holds
    @test bars.m == :holds
    @test bars.s.ratio ≈ 0.75
    @test bars.s.result == :holds
    @test bars.m1_xl.ratio ≈ 1.5 && bars.m1_today_xl.ratio ≈ 0.6 / 0.45
    @test sex_outcome(bars.m, bars.s.result) == :rule
    @test occursin("rule spec", text)
    for world in ("book", "xl", "today")
        @test occursin(basename(f[Symbol(world)]), text)
    end
    @test occursin("| M1 |", text) && occursin("| M2 |", text) && occursin("| S |", text)
end

@testset "xxl sex report: a ratio of 1.5 or more with the interval's low end at or under 1 doesn't hold" begin
    out = mktempdir()
    # today's no-mate shares alternate 0.96 and 0: a mean of 0.48, 1.6 times the book's, with a wide interval
    f = sr_worlds(out; today=i -> (; reach=isodd(i) ? 4 : 100))
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m1.ratio ≈ 1.6
    @test bars.m1.ratio >= M_FACTOR
    @test bars.m1.lo <= 1
    @test bars.m1.result == :fails
    @test bars.m == :fails
    @test sex_outcome(bars.m, bars.s.result) == :works
    @test occursin("works as intended", sr_report(f))
end

@testset "xxl sex report: S with the book's drop under 0.1 is not judged" begin
    out = mktempdir()
    f = sr_worlds(out; book=i -> (; met=(2.0, 1.9)))  # a drop of 0.05
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.s.result == :not_judged
    @test sex_outcome(bars.m, bars.s.result) == :rule  # S decides nothing
    @test occursin("not judged", sr_report(f))
end

@testset "xxl sex report: S fails on today's drop 0.2 against the book's 0.6, and goes to the user" begin
    out = mktempdir()
    f = sr_worlds(out; book=i -> (; met=(2.0, 0.8)), today=i -> (; met=(2.0, 1.6)))
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.s.ratio ≈ 1 / 3
    @test bars.s.result == :fails
    @test sex_outcome(bars.m, bars.s.result) == :report
    @test occursin("report to the user", sr_report(f))
end

@testset "xxl sex report: six book seeds at population 0 leave 14: M reads missing, the seeds counted" begin
    out = mktempdir()
    gone = [100; fill(50, 10); fill(0, SR_PERIODS - 10)]
    f = sr_worlds(out; book=i -> i <= 6 ? (; population=gone) : (;))
    b = read_sex_world("book", f.book)
    @test length(b.seeds) == 20
    @test count(s -> s.extinct !== nothing, b.seeds) == 6
    bars = sex_bars(b, read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m1.n_base == 14 && bars.m1.result == :missing
    @test bars.m2.result == :missing
    @test bars.m == :missing
    @test bars.s.result == :missing
    @test sex_outcome(bars.m, bars.s.result) == :report
    text = sr_report(f)
    @test occursin("missing", text)
    @test occursin("80, 81, 82, 83, 84, 85", text)
    @test occursin("14 of 20", text)
end

@testset "xxl sex report: M reads missing with S standing: no outcome" begin
    out = mktempdir()
    # six of today's seeds have no snapshot agent fertile for 5 periods: M2 is left with 14
    f = sr_worlds(out; today=i -> i <= 6 ? (; agents=[(4, 0)]) : (;))
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m1.result == :holds
    @test bars.m2.n_run == 14 && bars.m2.result == :missing
    @test bars.m == :missing
    @test bars.s.result == :holds
    @test sex_outcome(bars.m, bars.s.result) == :no_outcome
    @test occursin("no outcome", sr_report(f))
end

@testset "xxl sex report: M1 failing settles M though M2 reads missing" begin
    out = mktempdir()
    # today's no-mate shares alternate 0.96 and 0 (M1 fails on its interval); six of today's seeds have no snapshot agent
    # fertile for 5 periods (M2 is left with 14)
    f = sr_worlds(out; today=i -> (; reach=isodd(i) ? 4 : 100, (i <= 6 ? (; agents=[(4, 0)]) : (;))...))
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m1.result == :fails
    @test bars.m2.n_run == 14 && bars.m2.result == :missing
    @test bars.m == :fails
    @test bars.s.result == :holds
    @test sex_outcome(bars.m, bars.s.result) == :works
    @test occursin("works as intended", sr_report(f))
end

@testset "xxl sex report: every seed left out of M2 reads missing, and the md is written" begin
    out = mktempdir()
    f = sr_worlds(out; book=i -> (; agents=Tuple{Int,Int}[]))  # no snapshot agent in any book seed
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m2.n_base == 0 && bars.m2.result == :missing
    @test isnan(bars.m2.ratio)
    @test bars.m2_xl.result == :missing
    @test bars.m == :missing
    md = joinpath(mktempdir(), "sex-part1.md")
    text = sex_report(; f..., md, io=devnull)
    @test isfile(md)
    @test occursin("| Childless share (M2) | 0 of 20 (left out: $(join(80:99, ", "))) |", text)
    @test occursin("| Childless share (M2) | — | 0.4 | 0.6 |", text)
end

@testset "xxl sex report: real tiny study folders, 1 seed of 4 periods per world" begin
    out = mktempdir()
    f = NamedTuple{(:book, :xl, :today)}(
        Tuple(run_sex_world(w; seeds=1, first_seed=80, periods=4, io=devnull, out=out) for w in ("book", "xl", "today")))
    md = joinpath(out, "report.md")
    text = sex_report(; f..., md, io=devnull)
    @test isfile(md) && read(md, String) == text
    bars = sex_bars(read_sex_world("book", f.book), read_sex_world("xl", f.xl), read_sex_world("today", f.today))
    @test bars.m1.result == :missing && bars.m2.result == :missing && bars.m == :missing
    @test bars.s.result == :missing
    @test sex_outcome(bars.m, bars.s.result) == :report
end

@testset "xxl sex report: speed reads — for the book and xl" begin
    out = mktempdir()
    text = sr_report(sr_worlds(out))
    row = only(filter(l -> startswith(l, "| Mean speed, start |"), split(text, "\n")))
    @test row == "| Mean speed, start | — | — | 1.5 |"
end

@testset "xxl sex report: a folder whose fingerprint names another world is refused" begin
    out = mktempdir()
    f = sr_worlds(out)
    wrong = sr_folder(mktempdir(), "xl"; named="book")
    @test_throws ArgumentError sr_report((; f.book, xl=wrong, f.today))
    @test_throws ArgumentError sr_report((; book=f.xl, f.xl, f.today))
    bare = sr_folder(mktempdir(), "xl")
    write(joinpath(bare, "fingerprint.txt"), "Config(hand-written)\nperiods=$SR_PERIODS\n")
    @test_throws ArgumentError read_sex_world("xl", bare)
end

@testset "xxl sex report: the command line" begin
    a = sex_report_args(["--book", "B", "--xl", "X", "--today", "T"])
    @test a == (; book="B", xl="X", today="T", md=joinpath(RESULTS_XXL, "sex-part1.md"))
    @test sex_report_args(["--book", "B", "--xl", "X", "--today", "T", "--md", "m.md"]).md == "m.md"
    @test_throws ArgumentError sex_report_args(["--book", "B", "--xl", "X"])
    @test_throws ArgumentError sex_report_args(["--book", "B", "--xl", "X", "--today", "T", "--other"])
    @test_throws ArgumentError sex_report_args(["--book", "B", "--book", "B", "--xl", "X", "--today", "T"])
    out = mktempdir()
    f = sr_worlds(out)
    md = joinpath(out, "report.md")
    code = redirect_stdout(devnull) do
        sex_report_main(["--book", f.book, "--xl", f.xl, "--today", f.today, "--md", md])
    end
    @test code == 0 && isfile(md)
    code = redirect_stderr(devnull) do
        sex_report_main(["--book", f.book, "--xl", f.book, "--today", f.today, "--md", joinpath(out, "no.md")])
    end
    @test code == 2 && !isfile(joinpath(out, "no.md"))
end
