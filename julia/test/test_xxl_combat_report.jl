# xxl (stage 8): the combat report (julia/src/xxl/combat_report.jl), on hand-written study folders: a fingerprint, and per
# seed the standard CSV, the per-period combat table and a timing file, each with known values; and, for the drift check,
# hand-written reference folders standing for the saved runs (results-julia and results-julia-xl).
using Sugarscape, Test
using Sugarscape: combat_report, combat_report_args, combat_report_main, combat_drift, read_combat_world,
                  read_combat_worlds, combat_bars, combat_w1, combat_w2, combat_cut, combat_f, saved_fingerprint,
                  bootstrap_apart, bootstrap_ratio_apart, COMBAT_COLUMNS, COMBAT_EXPS, COMBAT_WORLDS, W_SHARE,
                  F_MIN_SHARE, F1_SEEDS_SHARE, F3_SEEDS_SHARE, HOME_MIN, W2_WINDOW, F1_WINDOW, F1_BLOCK, MIN_SEEDS,
                  BOOT_REPS, BOOT_SEED, REF_BOOK, REF_XL, RESULTS_XXL, load_registry, find_experiment

const CB_STEPS = Dict(e => find_experiment(load_registry(), e).steps for e in COMBAT_EXPS)

cb_value(x::Real) = isnan(x) ? "NaN" : isinteger(x) ? string(Int(x)) : string(Float64(x))
cb_series(x, periods) = x isa AbstractVector ? Float64.(x) : fill(Float64(x), periods + 1)

function cb_write(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for r in rows
            println(io, join(cb_value.(r), ","))
        end
    end
end

"""
One seed of a hand-written folder. `population`, `kills` (blue victims a period, from t = 1), `mixing`, `home` (blue's
home share) and `home_red` are each a number (every period) or a vector over t = 0..periods; `blue` is blue's share of
the population. A period with population 0 has no tribe readings.
"""
function cb_seed(folder, k; periods, population=100, kills=0.05, mixing=0.3, home=0.7, home_red=home, blue=0.5)
    pop, kill, mix = cb_series(population, periods), cb_series(kills, periods), cb_series(mixing, periods)
    hb, hr = cb_series(home, periods), cb_series(home_red, periods)
    cb_write(joinpath(folder, "seed$k.csv"), ["t", "population", "agents_ever"], [[t, pop[t + 1], 200] for t in 0:periods])
    rows = map(0:periods) do t
        p = pop[t + 1]
        alive = p > 0
        r(x) = alive ? x : NaN
        nb = round(Int, p * blue)
        d = Dict("t" => t, "population" => p, "n_blue" => nb, "n_red" => p - nb,
                 "killed_blue" => t == 0 ? 0 : kill[t + 1], "killed_red" => 0, "old_age_blue" => 0, "old_age_red" => 0,
                 "starved_blue" => 0, "starved_red" => 0, "neighbour_pairs" => alive ? 50 : 0,
                 "cross_pairs" => alive ? 50 * mix[t + 1] : 0, "mixing" => r(mix[t + 1]), "front_share" => r(0.2),
                 "home_blue" => r(hb[t + 1]), "home_red" => r(hr[t + 1]), "gini_blue" => r(0.3), "gini_red" => r(0.3),
                 "max_sugar_blue" => r(100), "max_sugar_red" => r(90), "tribe_changes" => t == 0 ? NaN : 0)
        [d[c] for c in COMBAT_COLUMNS]
    end
    cb_write(joinpath(folder, "seed$k-combat.csv"), COMBAT_COLUMNS, rows)
    write(joinpath(folder, "seed$k.timing.csv"), "setup_s,stepping_s,metrics_s\n0.1,1.0,0.1\n")
    return nothing
end

"""
A world's folder of experiment `exp` in `dir`, seeds 0 to n − 1, its name planning `planned` seeds (n by default) and
its fingerprint naming world `named` and experiment `named_exp`; `kw(i)` gives seed i's (1-based) keywords. Returns it.
"""
function cb_folder(dir, world, exp; n=20, planned=n, named=world, named_exp=exp, kw=i -> (;))
    periods = CB_STEPS[exp]
    folder = joinpath(dir, "combat-$world-$exp-s0-$planned-p$periods")
    mkpath(folder)
    write(joinpath(folder, "fingerprint.txt"),
          "Config(hand-written)\ncode sha256=0\nperiods=$periods\ncombat readings: world=$named exp=$named_exp\n")
    for i in 1:n
        cb_seed(folder, i - 1; periods, kw(i)...)
    end
    return folder
end

# A figure give or take 5% by seed, so the seeds are tight but not equal (their mean is the figure).
cb_tight(x, i) = x * (isodd(i) ? 1.05 : 0.95)

# The defaults of each world and experiment: kills per period in III-9 of 0.06 (book), 0.03 (xl), 0.01 (today), so 0.6,
# 0.3 and 0.1 kills per founder; mixing over III-12 and III-13 of 0.30 and 0.15 (book), 0.30 and 0.18 (xl), 0.30 and 0.27
# (today), cuts of 0.5, 0.4 and 0.1.
const CB_KILLS_9 = Dict("book" => 0.06, "xl" => 0.03, "today" => 0.01)
const CB_MIXING = Dict(("book", "III-12") => 0.30, ("book", "III-13") => 0.15, ("xl", "III-12") => 0.30,
                       ("xl", "III-13") => 0.18, ("today", "III-12") => 0.30, ("today", "III-13") => 0.27)

function cb_default(world, exp, i)
    exp == "III-9" && return (; kills=cb_tight(CB_KILLS_9[world], i))
    haskey(CB_MIXING, (world, exp)) && return (; mixing=cb_tight(CB_MIXING[(world, exp)], i))
    return (;)
end

"""All fifteen folders in a fresh `dir`, 20 seeds each; `kw(world, exp, i)` overrides seed i's keywords. Returns `dir`."""
function cb_worlds(; kw=(world, exp, i) -> (;))
    dir = mktempdir()
    for world in COMBAT_WORLDS, exp in COMBAT_EXPS
        cb_folder(dir, world, exp; kw=i -> (; cb_default(world, exp, i)..., kw(world, exp, i)...))
    end
    return dir
end

cb_read(dir, world, exp; n=20) = read_combat_world(world, exp, joinpath(dir, "combat-$world-$exp-s0-$n-p$(CB_STEPS[exp])"))
cb_bars(dir; ref_book=mktempdir(), ref_xl=mktempdir()) = combat_bars(read_combat_worlds(dir); ref_book, ref_xl)
cb_report(dir; ref_book=mktempdir(), ref_xl=mktempdir(), md=joinpath(mktempdir(), "combat-part1.md")) =
    combat_report(; dir, ref_book, ref_xl, md, io=devnull)

@testset "xxl combat report: the bar constants are the spec's" begin
    @test W_SHARE == 0.5
    @test F_MIN_SHARE == 0.05
    @test F1_SEEDS_SHARE == 0.8
    @test F3_SEEDS_SHARE == 0.5
    @test HOME_MIN == 0.5
    @test W2_WINDOW == (101, 200)
    @test F1_WINDOW == (501, 1000)
    @test F1_BLOCK == 100
    @test MIN_SEEDS == 15
    @test REF_BOOK == "C:/Projects/Sugarscape2026/results-julia"
    @test REF_XL == "C:/Projects/Sugarscape2026/results-julia-xl"
end

@testset "xxl combat report: bootstrap_apart resamples each set apart, as bootstrap_ratio_apart does" begin
    a, b = [1.0, 2.0, 4.0, 3.0, 5.0], [2.0, 2.5, 3.0, 4.5]
    r, g = bootstrap_ratio_apart(a, b), bootstrap_apart(/, a, b)
    @test g.value == r.ratio && g.lo == r.lo && g.hi == r.hi
    c = bootstrap_apart((x, y, z, w) -> (1 - y / x) / (1 - w / z), a, a ./ 2, b, b ./ 4)
    @test c.value ≈ 0.5 / 0.75
    @test c.lo <= c.value <= c.hi
    @test isnan(bootstrap_apart(/, a, Float64[]).lo)
end

@testset "xxl combat report: W1 at kills per founder 0.1 against the book's 0.6 holds" begin
    dir = mktempdir()
    book = read_combat_world("book", "III-9", cb_folder(dir, "book", "III-9"; kw=i -> (; kills=cb_tight(0.06, i))))
    today = read_combat_world("today", "III-9", cb_folder(dir, "today", "III-9"; kw=i -> (; kills=cb_tight(0.01, i))))
    w1 = combat_w1(today, book)
    @test w1.ratio ≈ 1 / 6
    @test w1.hi < 1
    @test w1.n_run == 20 && w1.n_base == 20
    @test w1.result == :holds
end

@testset "xxl combat report: a W1 ratio of 0.45 whose interval reaches 1 doesn't hold" begin
    dir = mktempdir()
    # the book's 1 kill per founder in every seed; today's 6.75 in one of 15 seeds and 0 in the rest
    book = read_combat_world("book", "III-9", cb_folder(dir, "book", "III-9"; kw=i -> (; kills=0.1)))
    today = read_combat_world("today", "III-9",
                              cb_folder(dir, "today", "III-9"; n=15, kw=i -> (; kills=i == 1 ? 0.675 : 0.0)))
    w1 = combat_w1(today, book)
    @test w1.ratio ≈ 0.45
    @test w1.ratio < W_SHARE
    @test w1.hi >= 1
    @test w1.result == :fails
    # fewer than 15 seeds on a side reads missing
    short = read_combat_world("today", "III-9", cb_folder(mktempdir(), "today", "III-9"; n=14, kw=i -> (; kills=0.01)))
    @test combat_w1(short, book).result == :missing
end

# The III-12 and III-13 folders of a world with mixing m12 and m13 (each give or take `spread` by seed), read.
function cb_pair(dir, world, m12, m13; spread=0.05)
    tight(x, i) = x * (isodd(i) ? 1 + spread : 1 - spread)
    w12 = read_combat_world(world, "III-12", cb_folder(dir, world, "III-12"; kw=i -> (; mixing=tight(m12, i))))
    w13 = read_combat_world(world, "III-13", cb_folder(dir, world, "III-13"; kw=i -> (; mixing=tight(m13, i))))
    return w12, w13
end

@testset "xxl combat report: W2 against the book's cut of 0.5 holds at today's 0.1" begin
    dir = mktempdir()
    b12, b13 = cb_pair(dir, "book", 0.30, 0.15)
    x12, x13 = cb_pair(dir, "xl", 0.30, 0.18)
    t12, t13 = cb_pair(dir, "today", 0.30, 0.27)
    book_cut = combat_cut(b12, b13)
    @test book_cut.cut ≈ 0.5
    @test book_cut.lo > 0 && book_cut.counts
    @test combat_cut(t12, t13).cut ≈ 0.1
    w2 = combat_w2(t12, t13, [("book", b12, b13), ("xl", x12, x13)])
    @test w2.reference == "book"
    @test w2.ratio ≈ 0.2
    @test w2.hi < 1
    @test w2.result == :holds
    # the mixing of a seed is its mean over t = 101–200: periods outside the window don't count
    mix = fill(0.9, CB_STEPS["III-12"] + 1)
    mix[(101 + 1):(200 + 1)] .= 0.30
    one = read_combat_world("today", "III-12", cb_folder(mktempdir(), "today", "III-12"; kw=i -> (; mixing=mix)))
    @test combat_cut(one, t13).cut ≈ 0.1
end

@testset "xxl combat report: W2 falls back to xl when the book shows no cut, and reads missing when xl shows none" begin
    dir = mktempdir()
    b12, b13 = cb_pair(dir, "book", 0.30, 0.30; spread=0.1)  # a cut about 0, noisy
    x12, x13 = cb_pair(dir, "xl", 0.30, 0.18)
    t12, t13 = cb_pair(dir, "today", 0.30, 0.27)
    @test combat_cut(b12, b13).lo <= 0 && !combat_cut(b12, b13).counts
    w2 = combat_w2(t12, t13, [("book", b12, b13), ("xl", x12, x13)])
    @test w2.reference == "xl"
    @test w2.ratio ≈ 0.25
    @test w2.result == :holds
    y12, y13 = cb_pair(mktempdir(), "xl", 0.30, 0.30; spread=0.1)
    none = combat_w2(t12, t13, [("book", b12, b13), ("xl", y12, y13)])
    @test none.reference === nothing
    @test none.result == :missing
    # fewer than 15 seeds in a set reads missing
    s13 = read_combat_world("today", "III-13", cb_folder(mktempdir(), "today", "III-13"; n=14, kw=i -> (; mixing=0.27)))
    @test combat_w2(t12, s13, [("book", x12, x13)]).result == :missing

    # in the report: W2 missing and W1 failing (today's kills as the book's) make W fail; combat works as intended
    d = cb_worlds(kw=(world, exp, i) ->
        exp == "III-9" && world == "today" ? (; kills=cb_tight(0.06, i)) :
        exp in ("III-12", "III-13") && world != "today" ? (; mixing=cb_tight(0.30, i)) : (;))
    bars = cb_bars(d)
    @test bars.w1.result == :fails
    @test bars.w2.result == :missing && bars.w2.reference === nothing
    @test bars.w == :fails
    @test bars.f.result == :holds && bars.drift_ok
    @test bars.outcome == :works
    @test occursin("combat works as intended in xxl", cb_report(d))
end

# Today's III-9, III-11 and III-14 folders, `kw(exp, i)` overriding seed i's keywords, read.
function cb_today(; kw=(exp, i) -> (;), n=20)
    dir = mktempdir()
    return Tuple(read_combat_world("today", e, cb_folder(dir, "today", e; n, planned=20, kw=i -> kw(e, i)))
                 for e in ("III-9", "III-11", "III-14"))
end

@testset "xxl combat report: F holds when the front lasts, the population lives and both tribes hold" begin
    f = combat_f(cb_today()...)
    @test f.f1 == :holds && f.f2 == :holds && f.f3 == :holds
    @test f.result == :holds
end

@testset "xxl combat report: F1 fails on a seed with no kill in a block, or too few seeds holding their ground" begin
    kills = fill(0.05, CB_STEPS["III-11"] + 1)
    kills[(701 + 1):(800 + 1)] .= 0
    f = combat_f(cb_today(kw=(e, i) -> e == "III-11" && i == 3 ? (; kills) : (;))...)
    @test f.f1_no_kill == [2]
    @test f.f1 == :fails && f.result == :fails
    # a block before the window doesn't count
    early = fill(0.05, CB_STEPS["III-11"] + 1)
    early[(401 + 1):(500 + 1)] .= 0
    @test combat_f(cb_today(kw=(e, i) -> e == "III-11" && i == 3 ? (; kills=early) : (;))...).f1 == :holds
    # home shares of 0.6 and 0.45 in 5 of 20 seeds: 0.75 of seeds hold their ground, under 0.8
    g = combat_f(cb_today(kw=(e, i) -> e == "III-11" && i <= 5 ? (; home=0.6, home_red=0.45) : (;))...)
    @test g.f1_home_share ≈ 0.75
    @test g.f1 == :fails && g.result == :fails
end

@testset "xxl combat report: F2 and F3" begin
    gone = [fill(100, 501); fill(0, CB_STEPS["III-14"] - 500)]
    f = combat_f(cb_today(kw=(e, i) -> e == "III-14" && i == 4 ? (; population=gone) : (;))...)
    @test f.f2_dead == ["III-14 seed 3"]
    @test f.f2 == :fails && f.result == :fails
    # both tribes at least 5% in 9 of 20 III-14 seeds; blue at 2% in the rest
    g = combat_f(cb_today(kw=(e, i) -> e == "III-14" && i > 9 ? (; blue=0.02) : (;))...)
    @test g.f3_share ≈ 0.45
    @test g.f3 == :fails && g.f2 == :holds && g.result == :fails
    @test combat_f(cb_today(kw=(e, i) -> e == "III-14" && i > 10 ? (; blue=0.05) : (;))...).f3 == :holds
end

@testset "xxl combat report: a missing today seed file fails F; fewer than 15 reads missing" begin
    t9, t11, t14 = cb_today()
    rm(joinpath(t14.folder, "seed5-combat.csv"))
    f = combat_f(t9, t11, read_combat_world("today", "III-14", t14.folder))
    @test f.f3_share ≈ 0.95 && f.f2_dead == ["III-14 seed 5"]
    @test f.result == :fails
    g = combat_f(cb_today(n=14)...)
    @test g.result == :missing
end

@testset "xxl combat report: W and F hold; combat is weak; the md" begin
    dir = cb_worlds()
    md = joinpath(mktempdir(), "sub", "combat-part1.md")
    text = combat_report(; dir, ref_book=mktempdir(), ref_xl=mktempdir(), md, io=devnull)
    @test isfile(md) && read(md, String) == text
    bars = cb_bars(dir)
    @test bars.w1.ratio ≈ 1 / 6 && bars.w1.result == :holds
    @test bars.w1_xl.ratio ≈ 0.5
    @test bars.w2.reference == "book" && bars.w2.ratio ≈ 0.2 && bars.w2.result == :holds
    @test bars.w == :holds
    @test bars.f.result == :holds
    @test bars.drift_ok
    @test all(d -> d.status == :no_reference, bars.drift)
    @test length(bars.drift) == 10
    @test bars.outcome == :weak
    @test occursin("combat is weak in xxl", text)
    for world in COMBAT_WORLDS, exp in COMBAT_EXPS
        @test occursin("combat-$world-$exp-s0-20-p$(CB_STEPS[exp])", text)
    end
    @test occursin("| W1 |", text) && occursin("| W2 |", text) && occursin("| W |", text) && occursin("| F |", text)
    @test occursin("| F1, kills |", text) && occursin("| F2 |", text) && occursin("| F3 |", text)
    @test occursin("reference: book", text)
    @test occursin("no reference", text)
    for window in ("t = 1–100", "t = 101–200", "t = 201–500", "t = 501–1,000")
        @test occursin(window, text)
    end
    for exp in COMBAT_EXPS
        @test occursin("### $exp", text)
    end
    @test occursin("Blue killed per period", text)
    @test occursin("## III-9's ending", text)
    @test occursin("| today | 0, 1, 2", text)  # every seed has both tribes alive
    @test endswith(text, "combat is weak in xxl.** The readings go to the user with a rule spec: kills by window, " *
                         "front share and speed's reach, with what they point to; any rule gets its own spec with the " *
                         "user.\n")
end

@testset "xxl combat report: a today III-9 seed at population 0 fails F; report to the user" begin
    gone = [fill(100, 601); fill(0, CB_STEPS["III-9"] - 600)]
    dir = cb_worlds(kw=(world, exp, i) -> world == "today" && exp == "III-9" && i == 1 ? (; population=gone) : (;))
    bars = cb_bars(dir)
    @test bars.f.f2 == :fails && bars.f.result == :fails
    @test bars.w1.n_run == 19  # left out of the ratio value
    @test bars.outcome == :report
    text = cb_report(dir)
    @test occursin("report to the user", text)
    @test occursin("III-9 seed 0", text)
end

@testset "xxl combat report: combat_drift" begin
    a, b = mktempdir(), mktempdir()
    fp = "Config(saved)\nsteps=10\n"
    write(joinpath(b, "fingerprint.txt"), fp)
    lines = ["t,population"; ["$t,$(100 + t)" for t in 0:9]]
    write(joinpath(a, "seed1.csv"), join(lines, "\n") * "\n")
    write(joinpath(b, "seed1.csv"), join(lines, "\n") * "\n")
    write(joinpath(a, "seed2.csv"), join(lines, "\n") * "\n")
    write(joinpath(b, "seed2.csv"), join(replace(lines, "5,105" => "5,106"), "\n") * "\n")  # one byte changed
    write(joinpath(a, "seed3.csv"), join(lines[1:7], "\n") * "\n")  # the first 7 lines
    write(joinpath(b, "seed3.csv"), join(lines, "\n") * "\n")
    write(joinpath(a, "seed4.csv"), join(lines, "\n") * "\n")  # the reference lacks it: skipped
    write(joinpath(a, "seed4-combat.csv"), "not a seed\n")
    d = combat_drift(a, b, fp)
    @test d.status == :fails
    @test d.matched == [1]
    @test d.differ == [2, 3]
    p = combat_drift(a, b, fp; prefix=true)
    @test p.status == :fails && p.matched == [1, 3] && p.differ == [2]
    # an identical copy passes, a seed the reference lacks skipped
    c = mktempdir()
    write(joinpath(c, "seed1.csv"), join(lines, "\n") * "\n")
    write(joinpath(c, "seed4.csv"), join(lines, "\n") * "\n")
    @test combat_drift(c, b, fp) == (; status=:passes, matched=[1], differ=Int[])
    @test combat_drift(a, b, fp; prefix=true).matched == [1, 3]
    # a stale fingerprint, or no reference folder: no reference
    @test combat_drift(a, b, "Config(other)\nsteps=10\n") == (; status=:no_reference, matched=Int[], differ=Int[])
    @test combat_drift(a, joinpath(b, "absent"), fp).status == :no_reference
    # a fingerprint saved with Windows line ends is the same text
    write(joinpath(b, "fingerprint.txt"), replace(fp, "\n" => "\r\n"))
    @test combat_drift(c, b, fp).status == :passes
end

@testset "xxl combat report: the drift check in the report; a failure puts the drift outcome first" begin
    dir = cb_worlds()
    ref_book, ref_xl = mktempdir(), mktempdir()
    saved = joinpath(ref_book, "III-9")
    mkpath(saved)
    write(joinpath(saved, "fingerprint.txt"), saved_fingerprint("III-9", "book"))
    for k in 0:9
        cp(joinpath(dir, "combat-book-III-9-s0-20-p1000", "seed$k.csv"), joinpath(saved, "seed$k.csv"))
    end
    stale = joinpath(ref_xl, "III-12")
    mkpath(stale)
    write(joinpath(stale, "fingerprint.txt"), "julia\nan older fingerprint\n")
    cp(joinpath(dir, "combat-xl-III-12-s0-20-p200", "seed0.csv"), joinpath(stale, "seed0.csv"))
    bars = cb_bars(dir; ref_book, ref_xl)
    d9 = only(d for d in bars.drift if d.world == "book" && d.exp == "III-9")
    @test d9.status == :passes && d9.matched == collect(0:9)
    @test only(d for d in bars.drift if d.world == "xl" && d.exp == "III-12").status == :no_reference
    @test bars.drift_ok && bars.outcome == :weak

    path = joinpath(saved, "seed3.csv")
    text = read(path, String)
    write(path, replace(text, "\n7,100," => "\n7,101,"; count=1))
    @test read(path, String) != text
    bars = cb_bars(dir; ref_book, ref_xl)
    @test !bars.drift_ok
    @test bars.w == :holds && bars.f.result == :holds
    @test bars.outcome == :drift
    report = cb_report(dir; ref_book, ref_xl)
    @test occursin("the runs differ from the saved runs: stop and report to the user", report)
    @test !occursin("combat is weak", report)
end

@testset "xxl combat report: the saved runs' fingerprints, read only" begin
    if isdir(REF_BOOK) && isdir(REF_XL)
        for exp in COMBAT_EXPS
            ref = joinpath(REF_BOOK, exp)
            @test combat_drift(ref, ref, saved_fingerprint(exp, "book")).status == :passes
        end
        for exp in ("III-9", "III-11")
            ref = joinpath(REF_XL, exp)
            @test combat_drift(ref, ref, saved_fingerprint(exp, "xl")).status == :passes
        end
        for exp in ("III-12", "III-13", "III-14")  # saved before xl's centred look
            ref = joinpath(REF_XL, exp)
            @test combat_drift(ref, ref, saved_fingerprint(exp, "xl")).status == :no_reference
        end
    else
        @info "the saved runs ($REF_BOOK, $REF_XL) are absent: their fingerprints aren't checked"
        @test_skip false
    end
    @test_throws ArgumentError saved_fingerprint("III-9", "today")
end

@testset "xxl combat report: a folder that names another world or experiment is refused" begin
    dir = cb_worlds()
    xl9 = joinpath(dir, "combat-xl-III-9-s0-20-p1000", "fingerprint.txt")
    good = read(xl9, String)
    write(xl9, replace(good, "world=xl" => "world=book"))
    md = joinpath(mktempdir(), "combat-part1.md")
    @test_throws ArgumentError cb_report(dir; md)
    @test !isfile(md)
    write(xl9, replace(good, "exp=III-9" => "exp=III-11"))
    @test_throws ArgumentError cb_report(dir)
    write(xl9, "Config(hand-written)\nperiods=1000\n")
    @test_throws ArgumentError cb_report(dir)
    write(xl9, good)
    rm(joinpath(dir, "combat-today-III-13-s0-20-p200"); recursive=true)
    @test_throws ArgumentError cb_report(dir)
end

@testset "xxl combat report: the command line" begin
    a = combat_report_args(String[])
    @test a == (; dir=RESULTS_XXL, first_seed=0, seeds=20, ref_book=REF_BOOK, ref_xl=REF_XL,
                md=joinpath(RESULTS_XXL, "combat-part1.md"))
    b = combat_report_args(["--dir", "D", "--first-seed", "5", "--seeds", "15", "--ref-book", "RB", "--ref-xl", "RX"])
    @test b == (; dir="D", first_seed=5, seeds=15, ref_book="RB", ref_xl="RX", md=joinpath("D", "combat-part1.md"))
    @test combat_report_args(["--dir", "D", "--md", "m.md"]).md == "m.md"
    @test_throws ArgumentError combat_report_args(["--other", "x"])
    @test_throws ArgumentError combat_report_args(["--dir"])
    @test_throws ArgumentError combat_report_args(["--seeds", "many"])
    dir = cb_worlds()
    refs = ["--ref-book", mktempdir(), "--ref-xl", mktempdir()]
    code = redirect_stdout(devnull) do
        combat_report_main(["--dir", dir, refs...])
    end
    @test code == 0 && isfile(joinpath(dir, "combat-part1.md"))
    md = joinpath(dir, "no.md")
    code = redirect_stderr(devnull) do
        combat_report_main(["--dir", dir, "--seeds", "19", "--md", md, refs...])
    end
    @test code == 2 && !isfile(md)
end
