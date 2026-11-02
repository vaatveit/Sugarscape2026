# xxl (stage 4): the disease list's readings and reading table (docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md,
# "Screening" and "The reading table"). Hand-made folders of run CSVs: the settings a fingerprint names, the bars of the
# screening table and what is near one, an extinct seed, a seed not finished, the choice between arms, the interval with
# each side on its own, and the figures of a run.
using Sugarscape, Test
isdefined(@__MODULE__, :list_folder) || include("disease_list_helpers.jl")

@testset "disease list readings" begin
    dir = mktempdir()
    base = list_base(dir)
    row(rs, n) = rs[findfirst(r -> r.name == n, rs)]

    @testset "settings" begin
        config = "Config(width=50, disease_list=25, diseases_per_agent=10, disease_length=(1, 10), immune_length=50)\n"
        fp(xxl) = "julia\nxxl vision_shape=\"disc\" speed=(1, 6) free_step=1.5$xxl\nlook: centred\n$config" * "periods=500\n"
        BOOK_FP = fp("")
        ARM_FP = fp(" disease_count=4 founder_diseases=2 disease_lengths=(9, 10)")
        ONE_FP = fp(" founder_diseases=2")
        @test Sugarscape.list_settings(BOOK_FP) == (count=25, founder=10, lengths=(1, 10))
        @test Sugarscape.list_settings(ARM_FP) == (count=4, founder=2, lengths=(9, 10))  # the xxl line beats the Config line
        @test Sugarscape.list_settings(ONE_FP) == (count=25, founder=2, lengths=(1, 10))  # founder_diseases=2 only
        @test Sugarscape.list_settings(fp(" disease_lengths=(12, 12)")).lengths == (12, 12)
        @test_throws ArgumentError Sugarscape.list_settings("julia\nxxl free_step=1.5\nperiods=500\n")
    end

    @testset "reading a folder" begin
        run = Sugarscape.read_list_run("arm", list_arm_folder(dir, "extinction-arm-s80-20-p500"; count=4, lengths=(9, 10)))
        @test run.name == "arm" && run.periods == 500 && run.planned == 20 && length(run.seeds) == 20
        @test (run.count, run.founder, run.lengths) == (4, 10, (9, 10))  # the founder count is the Config line's
        @test [s.series.seed for s in run.seeds] == collect(80:99)
        @test length(run.seeds[1].sick) == 501 && run.seeds[1].series.population[1] == 10000.0
        @test run.seeds[1].circulating[501] == 5.0 && run.seeds[1].gini[1] == 0.3 && run.seeds[1].price[1] == 1.0
        # a folder with no -s<first>-<seeds>-p<periods> in its name plans the seeds it has
        plain = list_arm_folder(dir, "plain"; n=3)
        @test Sugarscape.read_list_run("plain", plain).planned == 3
        # a CSV cut short, a checkpoint and a trace are not read
        write(joinpath(plain, "seed9.csv"), "t,population\n0,5\n")
        write(joinpath(plain, "seed1.ckpt"), "x")
        @test length(Sugarscape.read_list_run("plain", plain).seeds) == 3
        # a whole CSV without a column the readings need
        write(joinpath(plain, "seed7.csv"), "t,population,agents_ever\n" * join(("$t,1,1\n" for t in 0:500)))
        @test_throws ArgumentError Sugarscape.read_list_run("plain", plain)
    end

    @testset "the bars" begin
        passing, nearly, failing = list_screen(dir, base; in_band=18), list_screen(dir, base; in_band=17), list_screen(dir, base; in_band=16)
        @test row(passing, "X10, per seed").pass
        @test !row(nearly, "X10, per seed").pass && row(nearly, "X10, per seed").near
        @test !row(failing, "X10, per seed").pass && !row(failing, "X10, per seed").near
        @test [r.name for r in passing] == ["X9", "X10, mean", "X10, per seed", "Trough", "Extinction"]
        @test all(r -> r.pass, passing) && row(passing, "X10, per seed").value == "18 of 20"
        @test row(passing, "X10, per seed").bar == "at least 18 of 20"
        # the same for X9 at 18, 17 and 16 seeds with a disease at t = 500
        x9(k) = row(list_screen(dir, base; with_disease=k), "X9")
        @test x9(18).pass && x9(18).value == "18 of 20"
        @test !x9(17).pass && x9(17).near
        @test !x9(16).pass && !x9(16).near
        # n is the seeds read: 10 seeds need 9, and 9 are near
        small(k) = row(Sugarscape.screen_arm(Sugarscape.read_list_run("s", list_arm_folder(dir, "extinction-small-s80-10-p500";
            n=10, with_disease=k, lows=list_base_lows()[1:10])), base), "X9")
        @test small(9).pass && small(9).bar == "at least 9 of 10" && !small(8).pass && small(8).near && !small(7).near
        # X10 mean: 0.2 passes, 0.21 is near, 0.211 is neither; 0.01 passes, 0.0095 is near, 0.009 is neither
        mean_row(c) = row(list_screen(dir, base; sick=fill(c, 20)), "X10, mean")
        @test mean_row(0.2).pass && mean_row(0.01).pass
        @test !mean_row(0.21).pass && mean_row(0.21).near
        @test !mean_row(0.211).pass && !mean_row(0.211).near
        @test !mean_row(0.0095).pass && mean_row(0.0095).near
        @test !mean_row(0.009).pass && !mean_row(0.009).near
        @test mean_row(0.2).value == "0.2" && mean_row(0.2).bar == "0.01–0.2"
        # Trough: mean 5,000 and lowest 3,000 pass; mean 4,750 and one seed at 2,999 fail on two counts but are near;
        # mean 4,749 is not near; two seeds below 3,000 are not near
        trough(lows) = row(list_screen(dir, base; lows), "Trough")
        @test trough(list_base_lows()).pass && !trough(list_base_lows()).near
        t4750 = trough(vcat(2999.0, fill(4842.0, 18), 4845.0))  # mean 4,750
        @test !t4750.pass && t4750.near
        @test !trough(fill(4749.0, 20)).pass && !trough(fill(4749.0, 20)).near
        @test !trough(vcat(2999.0, 2999.0, fill(5560.0, 18))).pass && !trough(vcat(2999.0, 2999.0, fill(5560.0, 18))).near
        @test !trough(vcat(2999.0, fill(5316.0, 19))).pass && trough(vcat(2999.0, fill(5316.0, 19))).near  # the mean is fine
        @test trough(fill(5000.0, 20)).pass  # every seed at the baseline's mean, none under its lowest
    end

    @testset "t ≤ 500 of a longer baseline" begin
        long_base = Sugarscape.read_list_run("long", list_folder(dir, "extinction-long-s20-20-p600";
            pops=[vcat(list_pop(low, 6000.0), zeros(100)) for low in list_base_lows()],  # all extinct after t = 500
            sick=fill(0.1, 20), diseases=fill(5.0, 20), periods=600))
        run = Sugarscape.read_list_run("run", list_arm_folder(dir, "extinction-run-s80-20-p500"; lows=list_base_lows()))
        cells(rows) = [(r.name, r.value, r.bar, r.pass, r.near) for r in rows]
        @test cells(Sugarscape.screen_arm(run, long_base)) == cells(Sugarscape.screen_arm(run, base))
        # Extinction reads the whole run, the other rows t ≤ 500
        late = Sugarscape.read_list_run("late", list_folder(dir, "extinction-late-s80-20-p600";
            pops=[vcat(list_pop(low, 6000.0), i == 1 ? vcat(fill(6000.0, 49), zeros(51)) : fill(6000.0, 100))
                  for (i, low) in enumerate(list_base_lows())],  # seed 80 dies at t = 550
            sick=fill(0.1, 20), diseases=fill(5.0, 20), periods=600))
        rows = Sugarscape.screen_arm(late, base)
        @test all(r -> r.pass, rows[1:4]) && !rows[5].pass && !rows[5].near
        @test occursin("1 of 20", rows[5].value)
    end

    @testset "an extinct seed" begin
        # one of 20 seeds sick at 0.1 until it dies at t = 480; the rest healthy and in band
        dying = vcat(fill(6000.0, 480), zeros(21))
        sick = vcat(fill(0.1, 480), fill(NaN, 21))
        diseases = vcat(fill(5.0, 480), zeros(21))
        dead_run = Sugarscape.read_list_run("dead", list_folder(dir, "extinction-dead-s80-20-p500";
            pops=[i == 1 ? dying : list_pop(low, 6000.0) for (i, low) in enumerate(list_base_lows())],
            sick=[i == 1 ? sick : 0.1 for i in 1:20], diseases=[i == 1 ? diseases : 5.0 for i in 1:20]))
        dead_seed = dead_run.seeds[1]
        @test isnan(Sugarscape.window_sick(dead_seed, 451, 500)) && !Sugarscape.in_band(NaN)
        @test Sugarscape.window_sick(dead_seed, 301, 400) ≈ 0.1
        @test isnan(Sugarscape.window_sick(dead_seed, 301, 480))  # extinct at 480, which is at hi
        @test Sugarscape.window_sick(dead_seed, 301, 479) ≈ 0.1
        rows = Sugarscape.screen_arm(dead_run, base)
        @test !rows[5].pass && !rows[5].near
        @test occursin("19 of 20", rows[3].value)
        @test rows[2].pass && rows[2].value == "0.1"  # the extinct seed drops out of the mean
        @test !Sugarscape.arm_near(dead_run, rows) && !Sugarscape.arm_passes(dead_run, rows)
        @test Sugarscape.choose_arm([dead_run], base) === nothing
    end

    @testset "passing and near need every seed" begin
        # 19 whole seeds and one cut short: read_list_run keeps 19, planned is 20
        folder = list_arm_folder(dir, "extinction-short-s80-20-p500"; n=19, lows=list_base_lows()[1:19])
        write(joinpath(folder, "seed99.csv"), LIST_COLUMNS * "\n0,10000,1,0.1,5,0.3,40,0,1\n1,6000,2,0.1,5,0.3,40,0,1\n")
        short = Sugarscape.read_list_run("short", folder)
        @test length(short.seeds) == 19 && short.planned == 20
        rows = Sugarscape.screen_arm(short, base)
        @test all(r -> r.pass, rows)  # what it has is fine
        @test !Sugarscape.arm_passes(short, rows)
        @test !Sugarscape.arm_near(short, rows)
        @test Sugarscape.choose_arm([short], base) === nothing
        whole = Sugarscape.read_list_run("whole", list_arm_folder(dir, "extinction-whole-s80-20-p500"; lows=list_base_lows()))
        @test Sugarscape.arm_passes(whole, Sugarscape.screen_arm(whole, base))
        # one row failing and near makes an arm near; two failing rows, or one not near, do not
        near_run(; kw...) = Sugarscape.read_list_run("n", list_arm_folder(dir, "extinction-n-s80-20-p500"; lows=list_base_lows(), kw...))
        one_near = near_run(band=17)
        @test Sugarscape.arm_near(one_near, Sugarscape.screen_arm(one_near, base))
        @test !Sugarscape.arm_passes(one_near, Sugarscape.screen_arm(one_near, base))
        one_far = near_run(band=16)
        @test !Sugarscape.arm_near(one_far, Sugarscape.screen_arm(one_far, base))
        two = near_run(band=17, with_disease=17)
        @test !Sugarscape.arm_near(two, Sugarscape.screen_arm(two, base))
        @test !Sugarscape.arm_near(whole, Sugarscape.screen_arm(whole, base))  # nothing failing is a pass, not a near
    end

    @testset "the choice" begin
        arm(; kw...) = list_arm(dir; kw...)
        @test Sugarscape.choose_arm([arm(band=18), arm(band=20)], base).name == "band20"
        @test Sugarscape.choose_arm([arm(spread=0.2), arm(spread=0.1)], base).name == "spread0.1"
        @test Sugarscape.choose_arm([arm(hi=12, band=20), arm(hi=10, band=18)], base).lengths == (9, 10)  # the longer can't win
        @test Sugarscape.choose_arm([arm(hi=12, band=20)], base).lengths == (12, 12)  # unless nothing else passes
        @test Sugarscape.choose_arm([arm(band=16)], base) === nothing
        @test Sugarscape.choose_arm(Sugarscape.ListRun[], base) === nothing
        # the in-band count comes before the spread, then the length, then the count
        @test Sugarscape.choose_arm([arm(band=18, spread=0.05), arm(band=20)], base).name == "band20"
        @test Sugarscape.choose_arm([arm(hi=10, count=6, band=20), arm(hi=10, count=4, band=19, spread=0.1)], base).count == 6
        shorter = [arm(hi=9, band=20, count=6), arm(hi=10, band=20, count=4)]  # the same band and spread: the shorter hi wins
        @test Sugarscape.population_spread(shorter[1]) == Sugarscape.population_spread(shorter[2])
        @test Sugarscape.choose_arm(shorter, base).lengths == (9, 9)
        smaller = [arm(hi=10, band=20, count=6), arm(hi=10, band=20, count=4)]  # all equal but the count: the smaller wins
        @test Sugarscape.choose_arm(smaller, base).count == 4
        @test Sugarscape.population_spread(arm(spread=0.2)) > Sugarscape.population_spread(arm(spread=0.1)) > 0
    end

    @testset "an interval with each side on its own" begin
        r = Sugarscape.bootstrap_ratio_apart(fill(2.0, 20), fill(1.0, 60))
        @test r.ratio == 2.0 && r.lo == 2.0 && r.hi == 2.0
        a, b = [1.0, 1.2, 0.9, 1.1, 1.3], [1.0, 0.8, 1.1, 0.9]
        @test Sugarscape.bootstrap_ratio_apart(a, b) == Sugarscape.bootstrap_ratio_apart(a, b)
        @test Sugarscape.bootstrap_ratio_apart(a, b).ratio ≈ (sum(a) / 5) / (sum(b) / 4)
        @test isnan(Sugarscape.bootstrap_ratio_apart(a, zeros(4)).lo)
        @test isnan(Sugarscape.bootstrap_ratio_apart(Float64[], b).ratio)
        # paired resampling would give this a zero-width interval; each side on its own doesn't
        w = Sugarscape.bootstrap_ratio_apart([1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0])
        @test w.ratio == 1.0 && w.lo < 1.0 < w.hi
        @test Sugarscape.bootstrap_ratio_apart(a, b; reps=100, seed=1) != Sugarscape.bootstrap_ratio_apart(a, b; reps=100, seed=2)
    end

    @testset "the figures" begin
        # Three seeds, hand-computed (periods 0 to 500). Lowest populations 400 (t = 1), 200 (t = 7) and 600 (t = 4); mean
        # populations over t = 301-500 of 600, 800 and 1,000; shares sick of 0.05 (in the band), 0.25 (over) and 0.005 (under);
        # diseases 3 then 2 after t = 300, 2 throughout, and 3 until t = 400 then none.
        pops = [vcat(1000.0, 400.0, fill(600.0, 499)),
                [t == 0 ? 1000.0 : t == 7 ? 200.0 : 800.0 for t in 0:500],
                vcat(1000.0, 900.0, 800.0, 700.0, 600.0, fill(1000.0, 496))]
        fig = Sugarscape.read_list_run("fig", list_folder(dir, "extinction-fig-s1-3-p500";
            pops, sick=[0.05, 0.25, 0.005],
            diseases=[[t <= 300 ? 3.0 : 2.0 for t in 0:500], 2.0, [t <= 400 ? 3.0 : 0.0 for t in 0:500]],
            ever=i -> 100.0 .+ [3, 5, 4][i] .* (0:500), gini=i -> [0.2, 0.4, 0.3][i], sugar=i -> [30.0, 50.0, 40.0][i],
            trades=i -> [60.0, 160.0, 300.0][i],
            price=i -> i == 1 ? [301 <= t <= 310 ? NaN : 2.0 for t in 0:500] : [4.0, 3.0][i - 1]))
        r = Sugarscape.list_readings(fig)
        @test r.trough ≈ 400 && r.trough_t ≈ 4 && r.births_100 ≈ 400  # births 300, 500 and 400
        @test r.x9 ≈ 2 / 3
        @test r.sick_end ≈ (0.05 + 0.25 + 0.005) / 3
        @test (r.in_band_end, r.under_end, r.over_end) == (1, 1, 1)
        @test r.population ≈ 800 && r.spread ≈ 0.25 && Sugarscape.population_spread(fig) ≈ 0.25  # sd 200 over mean 800
        @test r.gini ≈ 0.3 && r.sugar ≈ 40
        @test r.trades_per_head ≈ 0.2  # 0.1, 0.2 and 0.3: a seed's trades over its population, summed over the window
        @test r.price ≈ 3  # 2, 4 and 3: the NaN cells are skipped
        @test r.per_seed.trough == [400, 200, 600] && r.per_seed.trough_t == [1, 7, 4]
        @test r.per_seed.births_100 == [300, 500, 400] && r.per_seed.x9 == [1, 1, 0]
        @test r.per_seed.sick_end ≈ [0.05, 0.25, 0.005] && r.per_seed.in_band_end == [1, 0, 0]
        @test r.per_seed.population == [600, 800, 1000] && r.per_seed.trades_per_head ≈ [0.1, 0.2, 0.3]
        @test r.per_seed.gini ≈ [0.2, 0.4, 0.3] && r.per_seed.sugar ≈ [30, 50, 40] && r.per_seed.price ≈ [2, 4, 3]
        w = Sugarscape.list_readings(fig; lo=1, hi=2)  # a window of the caller's: t = 1-2
        @test w.population ≈ (500 + 800 + 850) / 3
        # diseases circulating: the mean, sample sd and counts at a period
        c = Sugarscape.circulating_at(fig, 100)  # 3, 2 and 3
        @test c.mean ≈ 8 / 3 && c.sd ≈ sqrt(1 / 3) && c.counts == Dict(2 => 1, 3 => 2)
        c = Sugarscape.circulating_at(fig, 500)  # 2, 2 and 0
        @test c.mean ≈ 4 / 3 && c.sd ≈ sqrt(4 / 3) && c.counts == Dict(0 => 1, 2 => 2)
        # the share sick by the diseases at the last period, over the last 50 periods
        by = Sugarscape.sick_by_count(fig)
        @test [b.count for b in by] == [0, 2] && [b.seeds for b in by] == [1, 2]
        @test by[1].sick ≈ 0.005 && by[2].sick ≈ 0.15
        # a seed with 3 diseases at t = 200 and 2 at the end, and one with 3 and none, lose; one with 2 and 2 doesn't
        @test Sugarscape.seeds_losing(fig) == 2
        short_run = Sugarscape.read_list_run("p", list_arm_folder(dir, "p100"; n=2, periods=100))
        @test_throws ArgumentError Sugarscape.seeds_losing(short_run)
    end

    @testset "the reading windows" begin
        # Two seeds over 600 periods, each reading with a value just outside its window that would move the figure: the
        # windows are written out here (t = 1-500, 1-100, 301-500, 451-500 and the last 50), not taken from the constants.
        # Population: 50 at t = 0; 1,800 at t = 301 and 200 at t = 500, so that the window's mean is 1,000 and its lowest
        # point is its last; 5,000 at t = 300 and 100 at t = 501. A seed's second copy has twice the population.
        pop(t) = t == 0 ? 50.0 : t == 300 ? 5000.0 : t == 301 ? 1800.0 : t == 500 ? 200.0 : t == 501 ? 100.0 : 1000.0
        # Share sick: 0.05 at t = 451 and 0.15 at t = 500 around 0.1, and 0.9 at t = 450, 0.5 at t = 501; the same about the last
        # 50 periods (t = 551-600), with 0.9 at t = 550. The second seed's is 1.5 times the first's.
        sick(t) = t in (450, 550) ? 0.9 : t == 501 ? 0.5 : t in (451, 551) ? 0.05 : t in (500, 600) ? 0.15 : 0.1
        # Diseases: 4 at t = 500 for the first seed (none at 499 or 501), and for the second none at 500 but 3 either side.
        diseases1(t) = t == 500 ? 4.0 : t == 600 ? 2.0 : 0.0
        diseases2(t) = t in (499, 501, 600) ? 3.0 : 0.0
        # Births: 3 a period for the first seed and 5 for the second, and 1,000 more at t = 101.
        ever(i) = [100.0 + [3, 5][i] * t + (t >= 101 ? 1000.0 : 0.0) for t in 0:600]
        # Gini, sugar and price average 0.3, 40 and 2 over t = 301-500 (the ends offset each other) and are something else at
        # t = 300 and 501. Trades are 100 a period, 200 at t = 301 (1,800 agents) and none at t = 500 (200 agents), a million
        # outside; the second seed's are three times the first's.
        gini(t) = t == 300 ? 0.9 : t == 301 ? 0.2 : t == 500 ? 0.4 : t == 501 ? 0.8 : 0.3
        sugar(t) = t == 300 ? 99.0 : t == 301 ? 30.0 : t == 500 ? 50.0 : t == 501 ? 7.0 : 40.0
        price(t) = t == 300 ? 50.0 : t == 301 ? 1.0 : t == 500 ? 3.0 : t == 501 ? 60.0 : 2.0
        trades(t) = t in (300, 501) ? 1e6 : t == 301 ? 200.0 : t == 500 ? 0.0 : 100.0
        at(f, k=1) = Float64[f(t) * k for t in 0:600]
        win = Sugarscape.read_list_run("win", list_folder(dir, "extinction-win-s1-2-p600";
            pops=[at(pop), at(pop, 2)], sick=[at(sick), at(sick, 1.5)],
            diseases=[at(diseases1), at(diseases2)], ever=ever,
            gini=i -> at(gini), sugar=i -> at(sugar), price=i -> at(price), trades=i -> at(trades, [1, 3][i]), periods=600))
        r = Sugarscape.list_readings(win)
        @test r.per_seed.trough == [200, 400] && r.per_seed.trough_t == [500, 500]  # not t = 0, and not t = 501
        @test r.trough ≈ 300 && r.trough_t ≈ 500
        @test r.per_seed.births_100 == [300, 500] && r.births_100 ≈ 400  # to t = 100, not 101
        @test r.per_seed.x9 == [1, 0] && r.x9 ≈ 0.5  # t = 500 itself
        @test r.per_seed.sick_end ≈ [0.1, 0.15] && r.sick_end ≈ 0.125  # t = 451-500
        @test (r.in_band_end, r.under_end, r.over_end) == (2, 0, 0)
        @test r.per_seed.population == [1000, 2000] && r.population ≈ 1500  # t = 301-500
        @test r.spread ≈ sqrt(2) / 3 && Sugarscape.population_spread(win) ≈ sqrt(2) / 3
        @test r.per_seed.gini ≈ [0.3, 0.3] && r.gini ≈ 0.3
        @test r.per_seed.sugar ≈ [40, 40] && r.sugar ≈ 40
        @test r.per_seed.price ≈ [2, 2] && r.price ≈ 2
        # Trades per head is a seed's trades over its population, both summed over the window: 20,000 over 200,000, and
        # 60,000 over 400,000. The mean of the periods' ratios would be 0.0996 and 0.1493 instead.
        @test r.per_seed.trades_per_head ≈ [0.1, 0.15] && r.trades_per_head ≈ 0.125
        # the share sick by diseases at the last period reads t = 551-600, not 550
        by = Sugarscape.sick_by_count(win)
        @test [b.count for b in by] == [2, 3] && [b.seeds for b in by] == [1, 1]
        @test by[1].sick ≈ 0.1 && by[2].sick ≈ 0.15
        # the screening rows read t ≤ 500 of a longer run: the trough and the share sick
        rows = Sugarscape.screen_arm(win, base)
        @test row(rows, "X10, mean").value == "0.125" && !row(rows, "Trough").pass
        @test occursin("lowest 200", row(rows, "Trough").value)
        @test row(rows, "X9").value == "1 of 2"  # seed 1 at t = 500; seed 2 has one at t = 499 and 501 but not at 500
        # X9 is worked out apart from the readings, so the screening row is checked too, on four seeds: three with a disease
        # at t = 500 only and one at t = 499 and 501 only. That is 3 of 4 at t = 500, and 1 of 4 at 499 or at 501.
        at_500(t) = t == 500 ? 4.0 : 0.0
        around(t) = t in (499, 501) ? 3.0 : 0.0
        x9run = Sugarscape.read_list_run("x9", list_folder(dir, "extinction-x9-s1-4-p600";
            pops=[vcat(10000.0, fill(6000.0, 600)) for _ in 1:4], sick=fill(0.1, 4),
            diseases=[at(at_500), at(around), at(at_500), at(at_500)], periods=600))
        @test row(Sugarscape.screen_arm(x9run, base), "X9").value == "3 of 4"  # t = 500; 499 or 501 would give 1 of 4
        @test Sugarscape.list_readings(x9run).per_seed.x9 == [1, 0, 1, 1]
        # the share sick over the whole window (t = 301-500 here), apart from the end share sick of t = 451-500: 0.1 but for 0.9
        # at t = 450, 0.05 at t = 451 and 0.15 at t = 500; the second seed's is 1.5 times that
        @test r.per_seed.sick ≈ [0.104, 0.156] && r.sick ≈ 0.13 && r.in_band == 2
        # a window of the caller's: t = 501-600 is 0.5 at t = 501, 0.9 at 550, 0.05 at 551, 0.15 at 600 and 0.1 otherwise
        ws = Sugarscape.list_readings(win; lo=501, hi=600)
        @test ws.per_seed.sick ≈ [0.112, 0.168] && ws.sick ≈ 0.14 && ws.in_band == 2
        # the lowest over the whole run, which no bar reads: 100 and 200 at t = 501
        lowest = Sugarscape.run_lowest(win)
        @test lowest.mean ≈ 150 && lowest.lowest == 100
    end

    @testset "an arm short of its extinction is not near" begin
        # rows 1-4 pass and the only failure is a seed dying at t = 550, which is never near
        late = Sugarscape.read_list_run("late2", list_folder(dir, "extinction-late2-s80-20-p600";
            pops=[vcat(list_pop(low, 6000.0), i == 1 ? vcat(fill(6000.0, 49), zeros(51)) : fill(6000.0, 100))
                  for (i, low) in enumerate(list_base_lows())],
            sick=fill(0.1, 20), diseases=fill(5.0, 20), periods=600))
        rows = Sugarscape.screen_arm(late, base)
        @test all(r -> r.pass, rows[1:4]) && [r.name for r in rows if !r.pass] == ["Extinction"]
        @test !Sugarscape.arm_near(late, rows) && !Sugarscape.arm_passes(late, rows)
    end

    @testset "an arm with no finished seed" begin
        empty_run = Sugarscape.read_list_run("empty", list_arm_folder(dir, "extinction-empty-s80-20-p500"; n=0))
        @test isempty(empty_run.seeds) && empty_run.planned == 20 && !Sugarscape.finished(empty_run)
        whole = Sugarscape.read_list_run("whole2", list_arm_folder(dir, "extinction-whole2-s80-20-p500"; lows=list_base_lows()))
        @test Sugarscape.choose_arm([empty_run, whole], base).name == "whole2"
        @test Sugarscape.choose_arm([empty_run], base) === nothing
        # a folder that plans no seeds and holds none is as empty
        unplanned = Sugarscape.read_list_run("unplanned", list_arm_folder(dir, "unplanned"; n=0))
        @test Sugarscape.choose_arm([unplanned], base) === nothing
    end

    @testset "a row doesn't contradict itself" begin
        # A baseline whose trough mean is 5,787.0, and arms whose mean is just under it: four significant digits would show
        # both as 5787.
        base2 = Sugarscape.read_list_run("base2", list_arm_folder(dir, "extinction-base2-s20-20-p500";
            lows=vcat(3000.0, 4974.0, fill(5987.0, 18))))
        trough(lows) = row(list_screen(dir, base2; lows), "Trough")
        t = trough(vcat(3000.0, 4972.0, fill(5987.0, 18)))  # 5,786.9
        @test !t.pass && t.value == "mean 5786.9, lowest 3000" && t.bar == "mean at least 5787.0, none below 3000"
        # one decimal isn't enough where the mean rounds to the baseline's: it gets the digits that tell them apart
        t = trough(vcat(3000.0, 4973.2, fill(5987.0, 18)))  # 5,786.91 .. 5,786.96
        @test !t.pass && t.value == "mean 5786.96, lowest 3000" && t.bar == "mean at least 5787.0, none below 3000"
        t = trough(vcat(3000.0, 4974.0, fill(5987.0, 18)))  # equal: passes
        @test t.pass && t.value == "mean 5787.0, lowest 3000" && t.bar == "mean at least 5787.0, none below 3000"
        # the lowest is a whole number however big
        big_row = row(list_screen(dir, base; lows=fill(12345.0, 20)), "Trough")
        @test big_row.value == "mean 12345.0, lowest 12345"
        # the share sick's mean to five decimals, and more where that would put a failing mean inside the band
        mean_row(c) = row(list_screen(dir, base; sick=fill(c, 20)), "X10, mean")
        @test !mean_row(0.20004).pass && mean_row(0.20004).value == "0.20004" && mean_row(0.20004).bar == "0.01–0.2"
        @test !mean_row(0.2000004).pass && mean_row(0.2000004).value == "0.2000004"
        @test !mean_row(0.0099996).pass && mean_row(0.0099996).value == "0.0099996"
        @test mean_row(0.0123456).value == "0.01235" && mean_row(0.0123456).pass
    end
end
