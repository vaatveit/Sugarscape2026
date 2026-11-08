# xxl (stage 7): the culture report (julia/src/xxl/culture_report.jl), on hand-written study folders: a fingerprint, and
# per seed the standard CSV, the per-period culture table, the patch table and a timing file, each with known values; and
# beside each world a hand-written copy of its standard CSVs standing for stage 6's folder, for the drift check.
using Sugarscape, Test
using Sugarscape: culture_report, culture_report_args, culture_report_main, culture_drift, read_culture_world,
                  culture_bars, culture_f, culture_outcome, CULTURE_COLUMNS, CULTURE_PATCH_COLUMNS, W_SHARE, F_MIN_SHARE,
                  F_MIN_SEEDS_SHARE, MIN_SEEDS, RESULTS_XXL

const CR_PERIODS = 500
const CR_WINDOW = (301, 500)

cr_value(x::Real) = isnan(x) ? "NaN" : isinteger(x) ? string(Int(x)) : string(Float64(x))
cr_write(path, header, rows) =
    write(path, join([join(header, ","); [join(cr_value.(r), ",") for r in rows]], "\n") * "\n")
cr_series(x, periods) = x isa AbstractVector ? Float64.(x) : fill(Float64(x), periods + 1)

"""
One seed of a hand-written folder. `population`, `closeness` and `flips` are a number (every period) or a vector over
t = 0..periods; `patches` the (agents, blue share) of each patch at every tenth period; `zeros` the share of 0s at the
first tag positions (the rest NaN). A period with population 0 has no culture readings, and no patch.
"""
function cr_seed(folder, k; periods=CR_PERIODS, population=100, closeness=0.9, flips=0.1, blue=0.5,
                 patches=[(100, 0.9)], zeros=[0.5, 0.5, 0.9, 0.1, 1.0])
    pop, close, flip = cr_series(population, periods), cr_series(closeness, periods), cr_series(flips, periods)
    cr_write(joinpath(folder, "seed$k.csv"), ["t", "population", "agents_ever", "friend_closeness", "best_friend_closeness"],
             [[t, pop[t + 1], 200, pop[t + 1] == 0 ? NaN : 0.7, pop[t + 1] == 0 ? NaN : 0.8] for t in 0:periods])
    rows = map(0:periods) do t
        alive = pop[t + 1] > 0
        r(x) = alive ? x : NaN
        c = r(close[t + 1])
        d = Dict("t" => t, "population" => pop[t + 1], "blue_share" => r(blue), "tag_flips_per_agent" => r(flip[t + 1]),
                 "neighbour_pairs" => isnan(c) ? 0 : 60, "neighbour_closeness" => c, "chance_closeness" => r(0.5),
                 "neighbours_per_agent" => r(1.2), "share_no_neighbours" => r(0.25), "persist_base" => 50,
                 "persistence" => r(0.9), "mean_moved" => r(1.5), "mean_speed" => NaN)
        for i in 1:11
            d["zero_share_$i"] = i <= length(zeros) ? r(zeros[i]) : NaN
        end
        [d[c] for c in CULTURE_COLUMNS]
    end
    cr_write(joinpath(folder, "seed$k-culture.csv"), CULTURE_COLUMNS, rows)
    prows = [[t, j - 1, 0, a, b] for t in 0:10:periods if pop[t + 1] > 0 for (j, (a, b)) in enumerate(patches)]
    cr_write(joinpath(folder, "seed$k-patches.csv"), CULTURE_PATCH_COLUMNS, prows)
    write(joinpath(folder, "seed$k.timing.csv"), "setup_s,stepping_s,metrics_s\n0.1,1.0,0.1\n")
    return nothing
end

"""
A world's folder of `n` seeds from 80, and its reference (a copy of the standard CSVs with a stage-6 fingerprint);
`kw(i)` gives seed i's (1-based) keywords. Returns (folder, ref).
"""
function cr_folder(out, world; named=world, n=20, periods=CR_PERIODS, window=CR_WINDOW, kw=i -> (;))
    folder = joinpath(out, "culture-$world-VI-1-s80-$n-p$periods")
    ref = joinpath(out, "sex-$world-VI-1-s80-$n-p$periods")
    mkpath(folder)
    mkpath(ref)
    write(joinpath(folder, "fingerprint.txt"),
          "Config(hand-written)\ncode sha256=0\nperiods=$periods\nculture readings: world=$named window=$window\n")
    write(joinpath(ref, "fingerprint.txt"),
          "Config(hand-written)\ncode sha256=0\nperiods=$periods\nsex readings: world=$world window=$window\n")
    for i in 1:n
        cr_seed(folder, 79 + i; periods, kw(i)...)
        cp(joinpath(folder, "seed$(79 + i).csv"), joinpath(ref, "seed$(79 + i).csv"))
    end
    return folder, ref
end

# A figure give or take 0.005 by seed, so the seeds are tight but not equal.
cr_tight(x, i) = x + (isodd(i) ? 0.005 : -0.005)

# The three worlds: neighbour closeness 0.9 (book), 0.75 (xl), 0.6 (today); one patch of 100 agents, blue share 0.9,
# 0.7, 0.6 (polarization 0.8, 0.4, 0.2).
function cr_worlds(out; nbook=20, ntoday=20, book=i -> (;), xl=i -> (;), today=i -> (;))
    b, rb = cr_folder(out, "book"; n=nbook,
                      kw=i -> (; closeness=cr_tight(0.9, i), patches=[(100, cr_tight(0.9, i))], book(i)...))
    x, rx = cr_folder(out, "xl"; kw=i -> (; closeness=cr_tight(0.75, i), patches=[(100, cr_tight(0.7, i))], xl(i)...))
    t, rt = cr_folder(out, "today"; n=ntoday,
                      kw=i -> (; closeness=cr_tight(0.6, i), patches=[(60, cr_tight(0.6, i)), (40, cr_tight(0.6, i))],
                               today(i)...))
    return (; book=b, xl=x, today=t, ref_book=rb, ref_xl=rx, ref_today=rt)
end

cr_read(f) = (read_culture_world("book", f.book), read_culture_world("xl", f.xl), read_culture_world("today", f.today))
cr_refs(f) = (f.ref_book, f.ref_xl, f.ref_today)
cr_bars(f) = culture_bars(cr_read(f)...; refs=cr_refs(f))
cr_report(f; md=joinpath(mktempdir(), "culture-part1.md")) = culture_report(; f..., md, io=devnull)

@testset "xxl culture report: the bar constants are the spec's" begin
    @test W_SHARE == 0.5
    @test F_MIN_SHARE == 0.05
    @test F_MIN_SEEDS_SHARE == 0.8
    @test MIN_SEEDS == 15
end

@testset "xxl culture report: W1 and W2 at a quarter of the book's hold; culture is weak" begin
    out = mktempdir()
    f = cr_worlds(out)
    md = joinpath(mktempdir(), "sub", "culture-part1.md")
    text = culture_report(; f..., md, io=devnull)
    @test isfile(md) && read(md, String) == text
    book, xl, today = cr_read(f)
    @test book.window == CR_WINDOW && book.periods == CR_PERIODS && book.planned == 20
    bars = culture_bars(book, xl, today; refs=cr_refs(f))
    @test bars.w1.ratio ≈ 0.25
    @test bars.w1.hi < 1
    @test bars.w1.result == :holds
    @test bars.w2.ratio ≈ 0.25
    @test bars.w2.result == :holds
    @test bars.w == :holds
    @test bars.w1_xl.ratio ≈ 0.25 / 0.4 && bars.w1_today_xl.ratio ≈ 0.1 / 0.25
    @test bars.w2_xl.ratio ≈ 0.5 && bars.w2_today_xl.ratio ≈ 0.5
    @test bars.f.result == :holds
    @test bars.drift_ok
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :weak
    @test occursin("culture is weak", text)
    for world in ("book", "xl", "today")
        @test occursin(basename(f[Symbol(world)]), text)
        @test occursin(basename(f[Symbol("ref_$world")]), text)
    end
    @test occursin("| W1 |", text) && occursin("| W2 |", text) && occursin("| F |", text)
    for window in ("t = 51–100", "t = 101–200", "t = 201–300", "t = 301–500")
        @test occursin(window, text)
    end
    # a seed's readings: per-position polarization at the last period is the mean of |2z − 1| over 5 positions
    s = first(today.seeds)
    @test s.position_polarization ≈ (0 + 0 + 0.8 + 0.8 + 1) / 5
    v = s.windows[CR_WINDOW]
    @test v.w1.value ≈ 0.105 && v.w1.skipped == 0 && v.w1.periods == 200
    @test v.w2.periods == 20
    @test v.friend_closeness.value ≈ 0.7 && v.best_friend_closeness.value ≈ 0.8
    @test v.persistence.value ≈ 0.9 && isnan(v.mean_speed.value)
end

@testset "xxl culture report: a W1 ratio of 0.45 whose interval reaches 1 doesn't hold" begin
    out = mktempdir()
    # the book's neighbour closeness 1 in 18 seeds and 0 in 2 (0.4 above chance); today's 1 in 10 of 15 and 0.04 in 5
    # (0.18 above chance)
    f = cr_worlds(out; ntoday=15, book=i -> (; closeness=i <= 18 ? 1.0 : 0.0),
                  today=i -> (; closeness=i <= 10 ? 1.0 : 0.04))
    bars = cr_bars(f)
    @test bars.w1.ratio ≈ 0.45
    @test bars.w1.ratio < W_SHARE
    @test bars.w1.hi >= 1
    @test bars.w1.result == :fails
    @test bars.w2.result == :holds
    @test bars.w == :fails
    @test bars.f.result == :holds && bars.drift_ok
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :works
    @test occursin("works as intended", cr_report(f))
end

# The book's patches under 20 agents in 46 of 60 seeds: W2 is left with 14 book seeds.
cr_small_book(i) = i <= 46 ? (; patches=[(19, 0.9)]) : (;)

@testset "xxl culture report: W1 failing settles W though W2 reads missing" begin
    out = mktempdir()
    f = cr_worlds(out; nbook=60, book=cr_small_book, today=i -> (; closeness=cr_tight(0.8, i)))
    bars = cr_bars(f)
    @test bars.w1.ratio ≈ 0.75 && bars.w1.result == :fails
    @test bars.w2.n_base == 14 && bars.w2.result == :missing
    @test bars.w == :fails
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :works
    text = cr_report(f)
    @test occursin("works as intended", text)
    @test occursin("14 of 60", text)
    @test occursin("missing", text)
end

@testset "xxl culture report: W2 reading missing with W1 holding: no outcome" begin
    out = mktempdir()
    f = cr_worlds(out; nbook=60, book=cr_small_book)
    bars = cr_bars(f)
    @test bars.w1.result == :holds
    @test bars.w2.result == :missing
    @test bars.w == :missing
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :no_outcome
    @test occursin("no outcome", cr_report(f))
end

@testset "xxl culture report: a period with no neighbour pairs is skipped, and the skipped share shows" begin
    out = mktempdir()
    # the book's first seed: no neighbour pairs at t = 301..310, closeness 0.8 at t = 311..400 and 1.0 at t = 401..500
    close = [fill(0.9, 301); fill(NaN, 10); fill(0.8, 90); fill(1.0, 100)]
    f = cr_worlds(out; book=i -> i == 1 ? (; closeness=close) : (;))
    book = read_culture_world("book", f.book)
    v = first(book.seeds).windows[CR_WINDOW].w1
    @test v.value ≈ (90 * 0.3 + 100 * 0.5) / 190
    @test v.skipped == 10 && v.periods == 200
    text = cr_report(f)
    @test occursin("20 of 20, 0.25% skipped", text)  # 10 of 20 × 200 seed-periods
end

@testset "xxl culture report: six of 20 today seeds at population 0 fail F; report to the user" begin
    out = mktempdir()
    gone = [fill(100, 201); fill(0, CR_PERIODS - 200)]
    f = cr_worlds(out; today=i -> i <= 6 ? (; population=gone) : (;))
    book, xl, today = cr_read(f)
    @test length(today.seeds) == 20
    @test count(s -> s.extinct !== nothing, today.seeds) == 6
    bars = culture_bars(book, xl, today; refs=cr_refs(f))
    @test bars.f.share ≈ 0.7
    @test bars.f.result == :fails
    @test bars.w1.n_run == 14 && bars.w1.result == :missing
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :report
    text = cr_report(f)
    @test occursin("report to the user", text)
    @test occursin("80, 81, 82, 83, 84, 85", text)
end

@testset "xxl culture report: a today seed with a window period of no flips fails F" begin
    out = mktempdir()
    flips = fill(0.1, CR_PERIODS + 1)
    flips[400 + 1] = 0.0
    f = cr_worlds(out; today=i -> i == 3 ? (; flips) : (;))
    bars = cr_bars(f)
    @test bars.f.share ≈ 1.0
    @test bars.f.no_flips == [82]
    @test bars.f.result == :fails
    @test bars.w == :holds
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :report
    # a flip-less period before the window doesn't count
    flips2 = fill(0.1, CR_PERIODS + 1)
    flips2[300 + 1] = 0.0
    f2 = cr_worlds(mktempdir(); today=i -> i == 3 ? (; flips=flips2) : (;))
    @test culture_f(read_culture_world("today", f2.today)).result == :holds
end

@testset "xxl culture report: F reads missing with fewer than 15 seed files" begin
    out = mktempdir()
    f = cr_worlds(out)
    for k in 80:85
        rm(joinpath(f.today, "seed$k-culture.csv"))
    end
    f_ = culture_f(read_culture_world("today", f.today))
    @test f_.seeds == 14 && f_.result == :missing
end

@testset "xxl culture report: the drift check" begin
    a, b = mktempdir(), mktempdir()
    lines = ["t,population"; ["$t,$(100 + t)" for t in 0:9]]
    write(joinpath(a, "seed1.csv"), join(lines, "\n") * "\n")
    write(joinpath(b, "seed1.csv"), join(lines, "\n") * "\n")
    write(joinpath(a, "seed2.csv"), join(lines, "\n") * "\n")
    write(joinpath(b, "seed2.csv"), join(replace(lines, "5,105" => "5,106"), "\n") * "\n")  # one byte changed
    write(joinpath(a, "seed3.csv"), join(lines[1:7], "\n") * "\n")  # the first 7 lines
    write(joinpath(b, "seed3.csv"), join(lines, "\n") * "\n")
    write(joinpath(a, "seed4.csv"), join(lines, "\n") * "\n")  # no reference file
    write(joinpath(a, "seed4-culture.csv"), "not a seed\n")
    d = culture_drift(a, b)
    @test d.matched == [1]
    @test d.differ == [2, 3]
    @test d.absent == [4]
    p = culture_drift(a, b; prefix=true)
    @test p.matched == [1, 3]
    @test p.differ == [2]
    @test p.absent == [4]

    # a drift failure puts the drift outcome first, whatever the bars say
    out = mktempdir()
    f = cr_worlds(out)
    path = joinpath(f.ref_xl, "seed83.csv")
    text = read(path, String)
    write(path, replace(text, "\n7,100," => "\n7,101,"; count=1))
    @test read(path, String) != text
    bars = cr_bars(f)
    @test !bars.drift_ok
    @test bars.w == :holds
    @test culture_outcome(bars.drift_ok, bars.w, bars.f.result) == :drift
    report = cr_report(f)
    @test occursin("differ from stage 6's", report)
    @test !occursin("culture is weak", report)
    # a seed absent from the reference fails it too
    g = cr_worlds(mktempdir())
    rm(joinpath(g.ref_today, "seed90.csv"))
    @test occursin("differ from stage 6's", cr_report(g))
end

@testset "xxl culture report: a folder whose fingerprint names another world is refused" begin
    out = mktempdir()
    f = cr_worlds(out)
    wrong, _ = cr_folder(mktempdir(), "xl"; named="book")
    @test_throws ArgumentError cr_report((; f..., xl=wrong))
    @test_throws ArgumentError cr_report((; f..., book=f.xl))
    @test_throws ArgumentError cr_report((; f..., ref_xl=f.ref_book))  # a reference of another world
    bare, _ = cr_folder(mktempdir(), "xl")
    write(joinpath(bare, "fingerprint.txt"), "Config(hand-written)\nperiods=$CR_PERIODS\n")
    @test_throws ArgumentError read_culture_world("xl", bare)
end

@testset "xxl culture report: the command line" begin
    full = ["--book", "B", "--xl", "X", "--today", "T", "--ref-book", "RB", "--ref-xl", "RX", "--ref-today", "RT"]
    a = culture_report_args(full)
    @test a == (; book="B", xl="X", today="T", ref_book="RB", ref_xl="RX", ref_today="RT",
                md=joinpath(RESULTS_XXL, "culture-part1.md"))
    @test culture_report_args([full; "--md"; "m.md"]).md == "m.md"
    @test_throws ArgumentError culture_report_args(full[1:10])
    @test_throws ArgumentError culture_report_args([full; "--other"])
    @test_throws ArgumentError culture_report_args([full; "--book"; "B"])
    out = mktempdir()
    f = cr_worlds(out)
    args(xl) = ["--book", f.book, "--xl", xl, "--today", f.today, "--ref-book", f.ref_book, "--ref-xl", f.ref_xl,
                "--ref-today", f.ref_today]
    md = joinpath(out, "report.md")
    code = redirect_stdout(devnull) do
        culture_report_main([args(f.xl); "--md"; md])
    end
    @test code == 0 && isfile(md)
    code = redirect_stderr(devnull) do
        culture_report_main([args(f.book); "--md"; joinpath(out, "no.md")])
    end
    @test code == 2 && !isfile(joinpath(out, "no.md"))
end
