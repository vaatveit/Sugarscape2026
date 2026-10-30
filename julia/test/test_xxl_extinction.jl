# xxl: the extinction test (stage-2 spec): the limit, one seed's outcome, the report, the resumable run.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape:
    extinction_limit, seed_outcome, is_falling, extinction_verdict, extinction_report, SeedOutcome

# A run from population per period (t = 0 on), with agents_ever given or constant.
function ext_run(pops; ever=fill(100.0, length(pops)))
    M = hcat(Float64.(0:(length(pops) - 1)), Float64.(pops), Float64.(ever))
    return M, ["t", "population", "agents_ever"]
end
ext_outcome(pops; seed=0, kw...) = seed_outcome(ext_run(pops; kw...)..., seed)

const EXT_ALIVE = [100, 90, 80, 85, 90, 95, 100, 110, 120]
const EXT_FALLING = [100, 100, 100, 100, 100, 100, 100, 90, 90]

@testset "xxl extinction: the limit" begin
    @test extinction_limit(0, 59) < 0.05
    @test extinction_limit(0, 58) > 0.05
    @test extinction_limit(1, 93) < 0.05
    @test extinction_limit(1, 92) > 0.05
    @test extinction_limit(0, 60) ≈ 1 - 0.05^(1 / 60)
    @test extinction_limit(0, 40) ≈ 1 - 0.05^(1 / 40)
    @test extinction_limit(0, 0) == 1
    @test extinction_limit(3, 3) == 1
end

@testset "xxl extinction: one seed, alive" begin
    ever = [100, 100, 100, 105, 110, 115, 120, 130, 140]
    o = ext_outcome(EXT_ALIVE; seed=7, ever=ever)
    @test o.seed == 7
    @test o.lowest == 80
    @test o.lowest_t == 2
    @test o.at_quarters == (80.0, 90.0, 100.0, 120.0)
    @test o.extinct_t === nothing
    @test o.mean_third == 97.5  # t = 5, 6
    @test o.mean_fourth == 115  # t = 7, 8
    @test o.births_last == 40  # w = 8
    @test o.deaths_last == 20
    @test isnan(o.seconds)
    @test !is_falling(o)
    @test seed_outcome(ext_run(EXT_ALIVE)..., 7; seconds=12.5).seconds == 12.5
end

@testset "xxl extinction: one seed, extinct at the first period and at the last" begin
    first_t = ext_outcome([100, 0, 0, 0, 0, 0, 0, 0, 0])
    @test first_t.extinct_t == 1
    @test first_t.lowest == 0
    @test first_t.mean_third == 0 && first_t.mean_fourth == 0
    @test !is_falling(first_t)
    last_t = ext_outcome([100, 90, 80, 70, 60, 50, 40, 30, 0])
    @test last_t.extinct_t == 8
    @test last_t.lowest == 0
    @test last_t.lowest_t == 8
    @test !is_falling(last_t)
    for o in (first_t, last_t)
        r = extinction_report([o]; label="x", rules=XXL_DEFAULTS, first_seed=0, seeds=1, periods=8,
                              jobs=nothing, wall=nothing)
        @test !occursin("NaN", r)
    end
end

@testset "xxl extinction: falling at exactly the line is not falling" begin
    @test !is_falling(ext_outcome(EXT_FALLING))  # 100 and 90
    @test is_falling(ext_outcome([100, 100, 100, 100, 100, 100, 100, 89, 89]))  # 100 and 89
end

@testset "xxl extinction: the verdict" begin
    alive(n) = [ext_outcome(EXT_ALIVE; seed=i) for i in 1:n]
    dead = ext_outcome([100, 0, 0, 0, 0, 0, 0, 0, 0])
    @test extinction_verdict(alive(59)).verdict == "PASS"
    @test extinction_verdict(alive(58)).verdict == "TOO FEW SEEDS"
    v = extinction_verdict([alive(59); dead])
    @test v.verdict == "FAIL"
    @test v.extinct == 1
    @test extinction_verdict([alive(92); dead]).verdict == "PASS"  # 1 of 93 meets the bar
    @test extinction_verdict(alive(59)).limit == extinction_limit(0, 59)
end

@testset "xxl extinction: the report" begin
    kw = (label="defaults", rules=XXL_DEFAULTS, first_seed=20, periods=2000, jobs=10, wall=3600.0)
    # 60 seeds over 2,000 periods: the quarters are 500, 1,000, 1,500 and 2,000.
    pops = fill(100, 2001)
    r = extinction_report([seed_outcome(ext_run(pops)..., 19 + i; seconds=60.0) for i in 1:60]; seeds=60, kw...)
    @test occursin("# Extinction test: defaults", r)
    @test occursin("- Verdict: PASS", r)
    @test occursin("- Bar: below 5%, at 95% confidence", r)
    @test occursin("- Upper limit on the chance of extinction: 4.87%", r)
    @test occursin("- Extinct: 0 of 60 seeds", r)
    @test occursin("- Seeds finished: 60 of 60 (20–79)", r)
    @test occursin("- Periods: 2000", r)
    @test occursin("| Seed | Lowest | Lowest at t | t = 500 | t = 1000 | t = 1500 | t = 2000 |", r)
    @test occursin("Births, last 200 | Deaths, last 200", r)
    @test occursin("| 20 | 100 | 1 | 100 | 100 | 100 | 100 | — | 0 | 0 | 100 | 100 | no | 60 |", r)
    @test occursin("t = 1001–1500 against t = 1501–2000", r)
    @test occursin("- Falling at the end: 0 of 60 living seeds", r)
    @test occursin("- Run time: ", r)
    @test !occursin("Unfinished", r)
    @test !occursin("Most living seeds", r)
    @test !occursin("NaN", r)

    r = extinction_report([ext_outcome(pops; seed=19 + i) for i in 1:40]; seeds=60, kw...)
    @test occursin("- Seeds finished: 40 of 60 (20–79)", r)
    @test occursin("**Unfinished: 20 seeds have not run.", r)
    @test occursin("- Verdict: TOO FEW SEEDS", r)

    falling = [fill(100, 1501); fill(80, 500)]
    r = extinction_report([ext_outcome(falling; seed=19 + i) for i in 1:60]; seeds=60, kw...)
    @test occursin("**Most living seeds were falling at the end", r)
    @test occursin("- Falling at the end: 60 of 60 living seeds", r)

    # jobs and wall are optional.
    @test extinction_report([ext_outcome(pops)]; seeds=1, kw..., jobs=nothing, wall=nothing) isa String
end
