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
end
