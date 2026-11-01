# xxl: the credit study's comparison of finished runs, seed by seed. Hand-made folders of short CSVs: the bootstrap's
# ratio and lift, the states against a line, one series' figures, the lag, the finished seeds, the report and the
# command line.
using Sugarscape, Test

function cmp_folder(dir, name, pops::Dict{Int,<:AbstractVector}; ever=Dict())
    folder = joinpath(dir, name)
    mkpath(folder)
    periods = length(first(values(pops))) - 1
    write(joinpath(folder, "fingerprint.txt"), "julia\nperiods=$periods\n")
    for (k, p) in pops
        e = get(ever, k, 100.0 .+ (0:periods))
        write(joinpath(folder, "seed$k.csv"),
              "t,population,agents_ever\n" *
              join(("$(t - 1),$(p[t]),$(e[t])\n" for t in eachindex(p))))
    end
    return folder
end

@testset "credit compare: the ratio and its interval" begin
    r = Sugarscape.bootstrap_ratio([2.0, 4.0, 6.0], [1.0, 2.0, 3.0])
    @test r.ratio == 2.0 && r.lo == 2.0 && r.hi == 2.0
    a = [1.0, 1.2, 0.9, 1.1, 1.3]; b = [1.0, 1.0, 1.0, 1.0, 1.0]
    @test Sugarscape.bootstrap_ratio(a, b) == Sugarscape.bootstrap_ratio(a, b)  # the same on a rerun
    one, four = Sugarscape.bootstrap_ratio(a, b), Sugarscape.bootstrap_ratio(repeat(a, 4), repeat(b, 4))
    @test four.hi - four.lo < one.hi - one.lo  # narrows as seeds are added
    @test one.lo < 1.1 < one.hi
end

@testset "credit compare: a ratio of means, not a mean of ratios" begin
    @test Sugarscape.bootstrap_ratio([1.0, 3.0], [2.0, 2.0]).ratio == 1.0
    @test Sugarscape.bootstrap_ratio([4.0, 1.0], [2.0, 8.0]).ratio == 0.5
end

@testset "credit compare: the lift kept" begin
    v = Sugarscape.bootstrap_lift([110.0, 110.0], [100.0, 100.0], [120.0, 120.0])
    @test v.lift == 0.5 && v.lo == 0.5 && v.hi == 0.5
    n = Sugarscape.bootstrap_lift([110.0, 110.0], [100.0, 100.0], [100.0, 100.0])
    @test isnan(n.lift) && isnan(n.lo) && isnan(n.hi)
end

@testset "credit compare: three states against a line" begin
    @test Sugarscape.interval_state(1.01, 1.2, 1.0) == :above
    @test Sugarscape.interval_state(0.8, 0.99, 1.0) == :below
    @test Sugarscape.interval_state(0.9, 1.1, 1.0) == :straddles
    @test Sugarscape.interval_state(1.0, 1.1, 1.0) == :straddles  # touching isn't clear of it
    @test Sugarscape.band_state(0.96, 1.04) == :inside
    @test Sugarscape.band_state(1.06, 1.2) == :above
    @test Sugarscape.band_state(0.8, 0.94) == :below
    @test Sugarscape.band_state(0.9, 1.0) == :straddles
    @test Sugarscape.band_state(1.0, 1.1) == :straddles
end

@testset "credit compare: one series" begin
    s = Sugarscape.CompareSeries(1, [10.0, 8.0, 6.0, 7.0, 9.0], [10.0, 11.0, 13.0, 16.0, 20.0])
    @test Sugarscape.lowest(s) == 6.0 && Sugarscape.extinct_at(s) === nothing
    @test Sugarscape.window_population(s, 1, 2) == 7.0
    @test Sugarscape.window_births(s, 1, 2) == 3.0 && Sugarscape.window_births(s, 3, 4) == 7.0
    @test Sugarscape.births_per_head(s, 1, 2) == 3.0 / 14.0
    gone = Sugarscape.CompareSeries(1, [10.0, 5.0, 0.0, 0.0], [10.0, 10.0, 10.0, 10.0])
    @test Sugarscape.extinct_at(gone) == 2 && Sugarscape.lowest(gone) == 0.0
end

@testset "credit compare: the lag" begin
    # A curve falling to t = 20, then climbing 10 a period; the run is the same curve 15 periods later.
    curve(t) = t <= 20 ? 1000.0 - 40t : 200.0 + 10(t - 20)
    pop(shift) = [curve(max(t - shift, 0)) for t in 0:300]
    ever = collect(0.0:300.0)
    base = Sugarscape.CompareSeries(1, pop(0), ever)
    run = Sugarscape.CompareSeries(1, pop(15), ever)
    @test Sugarscape.population_lag(base, run, 100) == 15
    @test Sugarscape.population_lag(base, base, 100) == 0
end

@testset "credit compare: finished seeds only" begin
    dir = mktempdir()
    folder = cmp_folder(dir, "a", Dict(1 => fill(5.0, 11), 2 => fill(5.0, 11)))
    write(joinpath(folder, "seed3.csv"), "t,population,agents_ever\n0,5.0,1.0\n")  # cut short
    write(joinpath(folder, "seed4.ckpt"), "x")
    write(joinpath(folder, "seed2.csv"), read(joinpath(folder, "seed2.csv"), String)[1:(end - 1)])  # no last newline
    @test sort(collect(keys(Sugarscape.read_folder_series(folder)))) == [1]
    @test Sugarscape.folder_periods(folder) == 10
    mkpath(joinpath(dir, "none"))
    @test_throws ArgumentError Sugarscape.folder_periods(joinpath(dir, "none"))
end

@testset "credit compare: the report" begin
    dir = mktempdir()
    flat(v, n) = fill(float(v), n + 1)
    on = cmp_folder(dir, "on", Dict(k => flat(1000, 300) for k in 1:3))
    off = cmp_folder(dir, "off", Dict(k => flat(800, 300) for k in 1:3))
    run = cmp_folder(dir, "run", Dict(k => flat(900, 120) for k in 1:4))  # shorter, with a seed the others lack
    r = Sugarscape.credit_compare(dir; on="on", off="off", runs=["run"])
    @test isfile(joinpath(dir, "credit-compare-credit.md"))
    @test occursin("Seeds shared with on: 3", r)
    @test occursin("run reaches t = 120, on t = 300: compared over t ≤ 120", r)
    @test occursin("| 101–200 |", r) == true  # off against on reaches it
    @test occursin("Lift kept, trough | 0.5", r)
    same = cmp_folder(dir, "same", Dict(k => flat(1000, 300) for k in 1:3))
    r2 = Sugarscape.credit_compare(dir; on="on", off="same", runs=["run"], label="eq")
    @test occursin("Lift kept, trough | —", r2)
end

@testset "credit compare: an extinct seed leaves later windows and is counted" begin
    dir = mktempdir()
    alive = fill(100.0, 301)
    dying = [t <= 150 ? 100.0 : 0.0 for t in 0:300]
    on = cmp_folder(dir, "on", Dict(1 => alive, 2 => alive, 3 => alive))
    off = cmp_folder(dir, "off", Dict(1 => alive, 2 => alive, 3 => dying))
    r = Sugarscape.credit_compare(dir; on="on", off="off", runs=String[])
    @test occursin("Extinct: on 0 of 3, off 1 of 3", r)
    @test occursin("1 pair left out as extinct in t = 201–300", r)
    @test !occursin("Inf", r) && !occursin("NaN", r)
end

@testset "credit compare: the command line" begin
    usage(args) = redirect_stderr(() -> Sugarscape.credit_compare_main(args), devnull)
    dir = mktempdir()
    @test usage(["--on", "x"]) == 2
    @test usage(["--on", "x", "--off", "y", "--out", dir]) == 2
    @test usage(["--nope"]) == 2
end
