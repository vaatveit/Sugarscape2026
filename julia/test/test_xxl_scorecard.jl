# xxl: the scorecard (revised spec, "The scorecard"): its fifteen checks on synthetic runs built to sit just inside and
# just outside each threshold, an extinct seed, a short real run on seeds 20 and 21, and the script's arguments.
using Sugarscape, Test

const SCD_COLS = ["t"; METRIC_COLUMNS; XXL_METRIC_COLUMNS; SCORECARD_COLUMNS]
const SCD_XL_COLS = ["t"; METRIC_COLUMNS]
const SCD_STEPS = Dict("II-4" => 500, "IV-A3" => 300, "VI-1" => 500)
const SCD_SEEDS = 5

scd_col(name) = findfirst(==(name), SCD_COLS)

# One synthetic seed: 100 agents throughout, every VI-1 check comfortably passing.
function scd_seed(id, steps; xl=false)
    cols = xl ? SCD_XL_COLS : SCD_COLS
    M = zeros(steps + 1, length(cols))
    M[:, 1] = 0:steps
    base = Dict(
        "population" => 100.0,
        "n_blue" => 50.0,
        "n_red" => 50.0,
        "price_sd" => 1.0,
        "n_loans" => 5.0,
        "diseases_circulating" => 1.0,
        "fraction_sick" => 0.1,
    )
    if !xl
        merge!(
            base,
            Dict(
                "deaths_sugar" => 1.0,
                "births" => 1.0,
                "n_fertile" => 100.0,
                "n_fertile_with_mate" => 60.0,
                "tag_flips_per_agent" => 0.5,
                "share_traded_10" => 0.6,
                "loans_repaid" => 1.0,
            ),
        )
    end
    for (name, v) in base
        M[:, scd_col(name)] .= v
    end
    if !xl
        M[1, scd_col("tag_flips_per_agent")] = NaN
        M[1, scd_col("share_traded_10")] = NaN
        id == "VI-1" && (M[251, scd_col("population")] = 50.0)  # the trough, at t = 250
    end
    return M
end

function scd_data()
    xxl = Dict(
        id => [scd_seed(id, SCD_STEPS[id]) for _ in 1:SCD_SEEDS] for
        id in Sugarscape.SCORECARD_EXPERIMENTS
    )
    xl = Dict(
        id => [scd_seed(id, SCD_STEPS[id]; xl=true) for _ in 1:SCD_SEEDS] for
        id in Sugarscape.SCORECARD_EXPERIMENTS
    )
    columns = Dict(id => SCD_COLS for id in Sugarscape.SCORECARD_EXPERIMENTS)
    return xxl, xl, columns
end

# Sets column `name` of the given seeds (1-based positions) to `v` in the periods where `when(t)` holds.
function scd_set!(rows, name, v; seeds=eachindex(rows), when=t -> t >= 1)
    for s in seeds
        M = rows[s]
        for r in axes(M, 1)
            when(M[r, 1]) && (M[r, scd_col(name)] = v)
        end
    end
    return rows
end

scd_at(t0) = t -> t == t0
scd_after(t0) = t -> t > t0

scd_check(checks, id) = only(c for c in checks if c.id == id)

# One (id, inside!, outside!) per check; each mutates (xxl, xl) away from the passing baseline.
const SCD_PAIRS = [
    (
        "S1",
        (x, _) -> scd_set!(x["VI-1"], "population", 1.0; seeds=2:2, when=scd_at(40)),
        (x, _) -> scd_set!(x["VI-1"], "population", 0.0; seeds=2:2, when=scd_at(40)),
    ),
    (
        "S2",
        (x, _) -> scd_set!(x["VI-1"], "population", 11.0; seeds=2:2, when=scd_at(40)),
        (x, _) -> scd_set!(x["VI-1"], "population", 9.0; seeds=2:2, when=scd_at(40)),
    ),
    (
        "S3",
        (x, _) -> scd_set!(x["VI-1"], "population", 51.0; when=scd_after(400)),
        (x, _) -> scd_set!(x["VI-1"], "population", 49.0; when=scd_after(400)),
    ),
    (
        "S4",
        (x, _) -> scd_set!(x["II-4"], "population", 91.0; when=scd_after(400)),
        (x, _) -> scd_set!(x["II-4"], "population", 89.0; when=scd_after(400)),
    ),
    (
        "S5",
        (x, _) -> scd_set!(x["IV-A3"], "population", 91.0; when=scd_after(200)),
        (x, _) -> scd_set!(x["IV-A3"], "population", 89.0; when=scd_after(200)),
    ),
    # Births only in the last 200 periods, so a ratio over the whole run would fall far below 0.9.
    (
        "X1",
        (x, _) -> (
            scd_set!(x["VI-1"], "births", 0.0; when=t -> 1 <= t <= 300);
            scd_set!(x["VI-1"], "births", 1.09; when=scd_after(300))
        ),
        (x, _) -> (
            scd_set!(x["VI-1"], "births", 0.0; when=t -> 1 <= t <= 300);
            scd_set!(x["VI-1"], "births", 1.11; when=scd_after(300))
        ),
    ),
    # Five seeds: one failing seed leaves 80%, two leave 60%; seed 3 sits just inside at 6%.
    (
        "X3",
        (x, _) -> (
            scd_set!(x["VI-1"], "n_blue", 4.0; seeds=1:1, when=scd_at(200));
            scd_set!(x["VI-1"], "n_blue", 6.0; seeds=3:3, when=scd_at(200))
        ),
        (x, _) -> (
            scd_set!(x["VI-1"], "n_blue", 4.0; seeds=1:2, when=scd_at(200));
            scd_set!(x["VI-1"], "n_blue", 6.0; seeds=3:3, when=scd_at(200))
        ),
    ),
    (
        "X4",
        (x, _) ->
            scd_set!(x["VI-1"], "tag_flips_per_agent", 1e-6; seeds=2:2, when=scd_at(77)),
        (x, _) ->
            scd_set!(x["VI-1"], "tag_flips_per_agent", 0.0; seeds=2:2, when=scd_at(77)),
    ),
    (
        "X5",
        (x, _) -> scd_set!(x["VI-1"], "share_traded_10", 0.51; when=scd_after(400)),
        (x, _) -> scd_set!(x["VI-1"], "share_traded_10", 0.49; when=scd_after(400)),
    ),
    # Every other end period has too few trades for a price sd, and is skipped.
    (
        "X6",
        (x, _) -> (
            scd_set!(x["VI-1"], "price_sd", 1.49; when=scd_after(400));
            scd_set!(x["VI-1"], "price_sd", NaN; when=t -> t > 400 && iseven(Int(t)))
        ),
        (x, _) -> (
            scd_set!(x["VI-1"], "price_sd", 1.51; when=scd_after(400));
            scd_set!(x["VI-1"], "price_sd", NaN; when=t -> t > 400 && iseven(Int(t)))
        ),
    ),
    (
        "X7",
        (x, _) -> scd_set!(x["VI-1"], "n_loans", 0.0; when=t -> 90 <= t <= 100),
        (x, _) -> scd_set!(x["VI-1"], "n_loans", 0.0; seeds=3:3, when=scd_at(101)),
    ),
    (
        "X8",
        (x, _) -> (
            scd_set!(x["VI-1"], "loans_repaid", 0.81);
            scd_set!(x["VI-1"], "loans_voided", 0.19)
        ),
        (x, _) -> (
            scd_set!(x["VI-1"], "loans_repaid", 0.79);
            scd_set!(x["VI-1"], "loans_voided", 0.21)
        ),
    ),
    # t = 500 alone decides: no disease at t = 499 anywhere.
    (
        "X9",
        (x, _) -> scd_set!(x["VI-1"], "diseases_circulating", 0.0; when=scd_at(499)),
        (x, _) ->
            scd_set!(x["VI-1"], "diseases_circulating", 0.0; seeds=4:4, when=scd_at(500)),
    ),
    (
        "X10",
        (x, _) -> scd_set!(x["VI-1"], "fraction_sick", 0.19; when=scd_after(400)),
        (x, _) -> scd_set!(x["VI-1"], "fraction_sick", 0.21; when=scd_after(400)),
    ),
]

@testset "the passing baseline" begin
    checks = Sugarscape.score(scd_data()...)
    @test [c.id for c in checks] == [
        "S1",
        "S2",
        "S3",
        "S4",
        "S5",
        "X1",
        "X2",
        "X3",
        "X4",
        "X5",
        "X6",
        "X7",
        "X8",
        "X9",
        "X10",
    ]
    @test all(c -> c.pass || c.reported_only, checks)
    @test [c.aspect for c in checks] == [
        fill("Survival", 5)
        "Sex"
        "Sex"
        "Culture"
        "Culture"
        "Trade"
        "Trade"
        "Credit"
        "Credit"
        "Disease"
        "Disease"
    ]
end

@testset "just inside and just outside: $id" for (id, inside!, outside!) in SCD_PAIRS
    xxl, xl, columns = scd_data()
    inside!(xxl, xl)
    @test scd_check(Sugarscape.score(xxl, xl, columns), id).pass
    xxl, xl, columns = scd_data()
    outside!(xxl, xl)
    c = scd_check(Sugarscape.score(xxl, xl, columns), id)
    @test !c.pass
    @test !isempty(c.detail)
end

@testset "the values the thresholds apply to" begin
    xxl, xl, columns = scd_data()
    scd_set!(xxl["VI-1"], "population", 60.0; when=scd_after(400))
    scd_set!(xl["VI-1"], "population", 120.0; seeds=1:1, when=scd_after(400))
    checks = Sugarscape.score(xxl, xl, columns)
    # S3 is a ratio of means over seeds: 60 / mean(120, 100, 100, 100, 100).
    @test scd_check(checks, "S3").value ≈ 60 / 104
    @test scd_check(checks, "S2").value ≈ 0.5  # the trough
    @test scd_check(checks, "S1").value == 0  # no seed extinct
    @test scd_check(checks, "X4").low == 0 && scd_check(checks, "X4").high == Inf
end

@testset "an extinct seed" begin
    xxl, xl, columns = scd_data()
    dead = t -> t >= 40
    vi1 = xxl["VI-1"]
    for name in (
        "population",
        "n_blue",
        "n_red",
        "n_loans",
        "diseases_circulating",
        "deaths_sugar",
        "births",
        "n_fertile",
        "n_fertile_with_mate",
        "loans_repaid",
        "fraction_sick",
    )
        scd_set!(vi1, name, 0.0; seeds=2:2, when=dead)
    end
    for name in ("tag_flips_per_agent", "share_traded_10", "price_sd")
        scd_set!(vi1, name, NaN; seeds=2:2, when=dead)
    end
    checks = Sugarscape.score(xxl, xl, columns; first_seed=0)  # does not throw
    @test length(checks) == 15
    @test !scd_check(checks, "S1").pass && scd_check(checks, "S1").value == 1
    @test occursin("extinct in seed 1", scd_check(checks, "S1").detail)
    @test !scd_check(checks, "S2").pass
    for id in ("X1", "X5", "X6", "X10")
        c = scd_check(checks, id)
        @test isnan(c.value) && !c.pass
        @test occursin("extinct in seed 1", c.detail)
    end
    x2 = scd_check(checks, "X2")
    @test isnan(x2.value) && x2.reported_only
    @test occursin("extinct in seed 1", x2.detail)
    @test all(c -> c.pass || occursin("seed 1", c.detail), checks)
end

@testset "X2 is reported only" begin
    xxl, xl, columns = scd_data()
    scd_set!(xxl["VI-1"], "n_fertile_with_mate", 1.0; when=scd_at(250))  # far below the old 0.5
    checks = Sugarscape.score(xxl, xl, columns)
    x2 = scd_check(checks, "X2")
    @test x2.reported_only && !x2.pass && x2.value > 0
    @test count(c -> c.reported_only, checks) == 1
    report = Sugarscape.scorecard_report(
        checks;
        label="t",
        rules=XXL_V1,
        seeds=1,
        first_seed=0,
        steps=Dict(id => 1 for id in Sugarscape.SCORECARD_EXPERIMENTS),
        jobs=1,
        wall=1.0,
        times=Dict(
            (k, id) => 1.0 for k in (:xxl, :xl) for id in Sugarscape.SCORECARD_EXPERIMENTS
        ),
    )
    @test occursin("Passing: 14 of 14 checks", report)
    @test occursin(r"\| X2 Mates in reach \| [^|]+ \| — \| reported only \|", report)
end

@testset "run_scorecard on seeds 20 and 21" begin
    out = mktempdir()
    checks = Sugarscape.run_scorecard(
        XXL_V1; label="t8", seeds=2, first_seed=20, out=out, steps_override=5, io=devnull
    )
    @test length(checks) == 15
    for (dir, n_cols) in (("scorecard-t8-s20-2", nothing), ("scorecard-xl-s20-2", 46))
        for id in Sugarscape.SCORECARD_EXPERIMENTS
            folder = joinpath(out, dir, id)
            @test filter(f -> startswith(f, "seed"), readdir(folder)) ==
                ["seed20.csv", "seed21.csv"]
            lines = readlines(joinpath(folder, "seed21.csv"))
            @test length(lines) == 7  # header, t = 0..5
            n_cols === nothing || @test length(split(lines[1], ",")) == n_cols
        end
    end
    @test split(readline(joinpath(out, "scorecard-t8-s20-2", "VI-1", "seed20.csv")), ",") ==
        SCD_COLS
    report = read(joinpath(out, "scorecard-t8-s20-2.md"), String)
    @test occursin("Seeds: 20–21", report)
    @test occursin(Sugarscape.rules_line(XXL_V1), report)
    @test count("| S", report) + count("| X", report) == 15
    for aspect in ("Survival", "Sex", "Culture", "Trade", "Credit", "Disease")
        @test occursin("## $aspect", report)
    end

    # The xl runs are reused when current, and rerun when their length differs.
    xl_seed = joinpath(out, "scorecard-xl-s20-2", "VI-1", "seed20.csv")
    stamp = mtime(xl_seed)
    Sugarscape.run_scorecard(
        XXL_V1; label="t8b", seeds=2, first_seed=20, out=out, steps_override=5, io=devnull
    )
    @test mtime(xl_seed) == stamp
    @test isfile(joinpath(out, "scorecard-t8b-s20-2.md"))
    Sugarscape.run_scorecard(
        XXL_V1; label="t8c", seeds=2, first_seed=20, out=out, steps_override=4, io=devnull
    )
    @test length(readlines(xl_seed)) == 6
end

@testset "rules_from_args" begin
    rules, label = Sugarscape.rules_from_args([
        "--rules", "v1", "--set", "free_step=1.5", "--set", "founder_placement=viable"
    ])
    @test rules == replace_rules(XXL_V1; free_step=1.5, founder_placement="viable")
    @test label == "v1+free_step=1.5+founder_placement=viable"

    @test Sugarscape.rules_from_args(String[]) == (XXL_DEFAULTS, "defaults")
    rules, label = Sugarscape.rules_from_args([
        "--seeds",
        "4",
        "--set",
        "max_metabolism=4",
        "--set",
        "speed=2,5",
        "--jobs",
        "3",
        "--set",
        "word_of_mouth=false",
        "--first-seed",
        "20",
        "--label",
        "mine",
    ])
    @test rules ==
        replace_rules(XXL_DEFAULTS; max_metabolism=4, speed=(2, 5), word_of_mouth=false)
    @test label == "mine"
    @test Sugarscape.rules_from_args(["--rules", "v1", "--set", "speed=nothing"])[1] ==
        replace_rules(XXL_V1; speed=nothing)
    @test Sugarscape.rules_from_args(["--set", "max_metabolism=nothing"])[1].max_metabolism ===
        nothing
    @test_throws ArgumentError Sugarscape.rules_from_args(["--rules", "v2"])
    @test_throws ArgumentError Sugarscape.rules_from_args(["--set", "no_such=1"])
    @test_throws ArgumentError Sugarscape.rules_from_args(["--set", "free_step"])
    @test_throws ArgumentError Sugarscape.rules_from_args(["--set", "speed=1,2,3"])
    @test_throws ArgumentError Sugarscape.rules_from_args(["--bogus"])
    @test Sugarscape.scorecard_main(["--rules", "v9"]) == 2
end
