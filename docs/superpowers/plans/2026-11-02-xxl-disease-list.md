# xxl disease list Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a switch for the disease list, screen six candidate lists against a reading table set beforehand, confirm the best one, and write the findings with a recommendation the user decides on.

**Architecture:** Three `XxlRules` fields that `to_xxl` puts into the config, so no rule or draw order changes. `xxl_extinction.jl` gains the scorecard's `--set`. A new `xxl/disease_list.jl` reads finished CSVs, applies the reading table as code tested before any run, and writes the report, so the table can't drift once results exist.

**Tech Stack:** Julia, the `Sugarscape` package in `julia/`, with no new dependency.

**Spec:** `docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md`

## Global Constraints

- With the three settings at `nothing`, a run's CSV stays byte-identical and every fingerprint keeps its text.
- No change to `XXL_DEFAULTS`, `XXL_V1`, X9, X10, or how disease works (`rules/disease.jl` stays as it is). Julia only: no Python, viewer or FLAME GPU change.
- No existing test changes: none assumes thirteen settings (only `types.jl`'s docstring says it). New tests go in new files.
- No edit under `julia/src` once a long run has started: the fingerprint holds the source's hash. Tasks 1–5 finish first.
- Bars, from the spec: X9 at least 18 of 20; X10 mean 0.01–0.2 over t = 451–500; X10 per seed at least 18 of 20 inside 0.01–0.2 over t = 451–500; trough mean at or above the baseline's and no seed below the baseline's lowest; none extinct.
- Bootstrap: `BOOT_REPS` resamples from `BOOT_SEED`, each side resampled independently; percentile 95% interval.
- Long runs: 5 workers, memory watched, resumable by stopping and running the same command. A scorecard isn't resumable: it writes only when all an experiment's seeds finish, so a stop restarts it, which loses time and not results. The machine is shared: leave other sessions' jobs alone.
- Commits end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Commits are on `xxl-disease-list` only. Nothing is merged or pushed. Rerun the Julia suite before any merge.
- Comments and docstrings match the surrounding style: plain sentences.

**Rulings this plan makes where the spec leaves a choice** (each is *my call*):
- **"Near" and an extinct seed:** a seed going extinct is never near, even though it misses a row "by one seed". The bar is the user's, and confirmation needs 0 of 60.
- **"Near" on the trough row:** the mean within 5% of the bar and at most one seed below the lowest.
- **Spread:** sample standard deviation over seeds divided by their mean, of each seed's mean population over t = 301–500.
- **Gini, mean sugar, price, share of trades:** each seed's figure over t = 301–500, then the mean over seeds. Trades per head is a seed's trades over its population summed over the window.
- **Confirmation's per-seed X10 bar of 0.9** reads the end of the run, t = 1,951–2,000, with t = 451–500 reported beside it.
- **The end window is 50 periods here and 100 in the scorecard.** The spec's table reads the last 50, but the scorecard's `END_PERIODS` is 100, so its X10 reads t = 401–500. This table keeps the spec's window and doesn't use `END_PERIODS`. The two figures can differ a little, and at confirmation the scorecard's own X10 is what its 13 of 13 counts.
- **The readings are a Julia tool, not scripts,** so the table is tested before there are results. No `xxl_on` feature: nothing reads one.
- **Confirmation's order:** scorecards, credit off, then extinction, because the short runs report first. The order changes no reading.

## Review Focus

- `--set disease_count=4` alone asks for 10 diseases from a list of 4. Both tools should exit 2 with the refusal, not a stack trace after a run has begun. Test in Task 2.
- Rules with a list set, reaching `Config` through `replace_config` rather than `to_xxl`, must be refused and not run quietly at 25 diseases. Test in Task 1.
- A resume or `--report-only` with a different `--set` from the run's must be refused, and a stop and resume with a list set must give the same bytes. Test in Task 2.
- An extinct seed must read as out of band even if it was sick at a normal rate before it died, and must not produce a NaN that passes. Test in Task 3.
- A report read while an arm is still running must count only whole seeds, and an unfinished arm must not pass or be chosen. Test in Tasks 3 and 4.

---

### Task 1: Rule 12, the switch

**Files:**
- Modify: `julia/src/xxl/types.jl`, `julia/src/xxl/transform.jl`, `julia/src/config.jl` (`validate_xxl`)
- Test: `julia/test/test_xxl_disease_list_switch.jl` (new)

**Interfaces:**
- Produces: `XxlRules` fields, after `founder_ages` and in this order: `disease_count::Union{Nothing,Int}=nothing`, `founder_diseases::Union{Nothing,Int}=nothing`, `disease_lengths::Union{Nothing,Tuple{Int,Int}}=nothing`. `to_xxl` puts them into `disease_list`, `diseases_per_agent` and `disease_length`.

- [ ] **Step 0: Set up the branch**

The controller does this before Task 1, and it isn't part of the implementer's brief:

```bash
git switch -c xxl-disease-list
git add docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md docs/superpowers/plans/2026-11-02-xxl-disease-list.md
git commit -m "docs: the disease list's design and plan"
```

- [ ] **Step 1: Write the failing tests**

`julia/test/test_xxl_disease_list_switch.jl`, one outer `@testset` as in `test_xxl_young.jl`, so that `DL_LIST = (; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))`, and `vi1` and `ii4` from the registry, are local to it. Task 2's file does the same:

```julia
@testset "disease list: book settings change nothing" begin
    @test XXL_BOOK.disease_count === nothing && XXL_DEFAULTS.founder_diseases === nothing && XXL_V1.disease_lengths === nothing
    c = to_xxl(vi1.config, XXL_DEFAULTS)
    @test (c.disease_list, c.diseases_per_agent, c.disease_length) == (25, 10, (1, 10))
    @test Sugarscape.rules_line(XXL_DEFAULTS) ==
        "vision_shape=\"disc\" speed=(1, 6) travel_cost=0.2 memory=8 memory_span=50 word_of_mouth=true " *
        "interaction_radius=1.5 season_gradient=true landscape=\"generated\" founder_placement=\"viable\" free_step=1.5"
    @test !occursin("disease_count", Sugarscape.xxl_fingerprint(vi1, XXL_DEFAULTS))
end

@testset "disease list: each setting reaches the config" begin
    c = to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; DL_LIST...))
    @test (c.disease_list, c.diseases_per_agent, c.disease_length) == (4, 2, (9, 10))
    @test c.xxl.disease_count == 4
    @test to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; founder_diseases=5)).diseases_per_agent == 5
    @test to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; disease_count=30)).disease_list == 30
    @test to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; disease_lengths=(12, 12))).disease_length == (12, 12)
end

@testset "disease list: the founders it makes" begin
    m = Model(to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; DL_LIST...)))
    @test length(m.disease_list) == 4
    @test all(id -> 9 <= m.disease_len[id] <= 10, m.disease_list)
    @test all(a -> length(a.diseases) <= 2, m.agents)
    @test 1.8 <= sum(a -> length(a.diseases), m.agents) / length(m.agents) <= 2.0  # 2 offered, a few immune
    long = Model(to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(12, 12))))
    @test all(id -> m.disease_len[id] in (9, 10), m.disease_list) && all(id -> long.disease_len[id] == 12, long.disease_list)
    none = Model(to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; DL_LIST..., founder_diseases=0)))
    @test length(none.disease_list) == 4 && all(a -> isempty(a.diseases), none.agents)
end

@testset "disease list: refusals" begin
    for bad in (
        (; disease_count=0), (; disease_count=-1), (; founder_diseases=-1),
        (; disease_count=4, founder_diseases=5), (; disease_count=4),  # 10 offered of 4
        (; disease_lengths=(0, 10)), (; disease_lengths=(10, 9)), (; disease_lengths=(1, 50)),  # 50 reaches immune_length
    )
        @test_throws ArgumentError to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; bad...))
    end
end

@testset "disease list: rules that skip to_xxl are refused" begin
    R0 = replace_rules(XXL_V1; season_gradient=false)
    for kw in ((; disease_count=25), (; founder_diseases=0), (; disease_lengths=(1, 10)))
        @test_throws ArgumentError replace_config(to_xl(ii4.config); xxl=replace_rules(R0; kw...))  # no disease to apply to
    end
    for kw in ((; disease_count=4, founder_diseases=2), (; founder_diseases=2), (; disease_lengths=(9, 10)))
        @test_throws ArgumentError replace_config(to_xl(vi1.config); xxl=replace_rules(R0; kw...))  # the config still says otherwise
    end
end

@testset "disease list: an experiment without disease resets them" begin
    c = to_xxl(ii4.config, replace_rules(XXL_V1; season_gradient=false, DL_LIST...))
    @test c.disease_list == 0 && c.xxl.disease_count === nothing && c.xxl.founder_diseases === nothing && c.xxl.disease_lengths === nothing
    @test Sugarscape.xxl_fingerprint(ii4, replace_rules(XXL_DEFAULTS; DL_LIST...)) == Sugarscape.xxl_fingerprint(ii4, XXL_DEFAULTS)
end

@testset "disease list: the fingerprint names a setting when it's on" begin
    @test endswith(Sugarscape.rules_line(replace_rules(XXL_DEFAULTS; DL_LIST...)),
                   "free_step=1.5 disease_count=4 founder_diseases=2 disease_lengths=(9, 10)")
    @test endswith(Sugarscape.rules_line(replace_rules(XXL_DEFAULTS; founder_diseases=2)), "free_step=1.5 founder_diseases=2")
    @test replace_rules(XXL_DEFAULTS; DL_LIST...) != XXL_DEFAULTS
    @test hash(replace_rules(XXL_DEFAULTS; DL_LIST...)) != hash(XXL_DEFAULTS)
end

@testset "disease list: naming the book's list gives the same bytes" begin
    a, b = mktempdir(), mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1)
    run_extinction(XXL_DEFAULTS; kw..., out=a)
    run_extinction(replace_rules(XXL_DEFAULTS; disease_count=25, founder_diseases=10, disease_lengths=(1, 10)); kw..., out=b)
    name = Sugarscape.extinction_name("t", 20, 1, 12)
    @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_disease_list_switch"])'`
Expected: FAIL: `XxlRules has no field disease_count`.

- [ ] **Step 3: Implement**

- `types.jl`: the fields, and the docstring's "thirteen" becomes "sixteen", naming the stage-4 list settings.
- `to_xxl`: when `cfg.disease_list == 0`, reset the three to `nothing` as `founder_ages` is reset. Then pass `disease_list=something(rules.disease_count, xl.disease_list)`, and likewise `diseases_per_agent` and `disease_length`, to the `replace_config` it already calls. Update its docstring.
- `validate_xxl`, beside the other range checks: `disease_count < 1`, `founder_diseases < 0`; any of the three set with `c.disease_list == 0` ("needs disease"); and each set value differing from its config field (the same "go together" check the generated landscape has). Config's own checks already refuse a per-agent count above the list and a bad length range.
- `rules_line` needs no change. Its docstring says "each stage-1 field"; make it "each later field".

- [ ] **Step 4: Run them to verify they pass**

Same command, then `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_stage1_config", "xxl_v1_golden", "xxl_defaults"])'`.
Expected: PASS, and the golden test is unchanged.

- [ ] **Step 5: Commit**

```bash
git add julia/src/xxl/types.jl julia/src/xxl/transform.jl julia/src/config.jl julia/test/test_xxl_disease_list_switch.jl
git commit -m "julia xxl: rule 12, the disease list"
```

---

### Task 2: `--set` on the extinction test

**Files:**
- Modify: `julia/src/xxl/scorecard.jl` (`scorecard_args`, `scorecard_main`), `julia/src/xxl/extinction.jl` (`extinction_args`, `extinction_main`, `EXTINCTION_USAGE`), `julia/xxl_extinction.jl` (its comment)
- Test: `julia/test/test_xxl_disease_list_flags.jl` (new)

**Interfaces:**
- Consumes: the three `XxlRules` fields of Task 1; `parse_rule_value`, `SCORECARD_BASES`.
- Produces: `rule_setting(v::AbstractString) -> Pair{Symbol,Any}` in `scorecard.jl`: reads `field=value` as the scorecard does today, with the same errors. `extinction_args` takes repeated `--set field=value`; its `rules` holds them, and with no `--label` the label is the base then each `--set` as written, joined by `+`, as in the scorecard.

- [ ] **Step 1: Write the failing tests**

```julia
@testset "disease list flags: --set parses on both tools" begin
    args = ["--set", "disease_count=4", "--set", "founder_diseases=2", "--set", "disease_lengths=9,10"]
    list = replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))
    @test Sugarscape.scorecard_args(args).rules == list
    a = Sugarscape.extinction_args(args)
    @test a.rules == list
    @test a.label == "defaults+disease_count=4+founder_diseases=2+disease_lengths=9,10"
    @test Sugarscape.extinction_args(["--set", "disease_count=nothing"]).rules == XXL_DEFAULTS
    @test Sugarscape.extinction_args([]).label == "defaults"
    @test Sugarscape.extinction_args(["--rules", "v1", "--set", "free_step=1.5", "--label", "x"]).label == "x"
end

@testset "disease list flags: refusals are usage errors" begin
    usage(f, args) = redirect_stderr(() -> f(args), devnull)
    for args in (["--set"], ["--set", "nofield=1"], ["--set", "disease_count"], ["--set", "disease_count=x"],
                 ["--set", "disease_lengths=9"], ["--set", "disease_count=4"], ["--set", "disease_count=0"])
        @test usage(Sugarscape.extinction_main, [args; "--out"; mktempdir()]) == 2
        @test usage(Sugarscape.scorecard_main, [args; "--out"; mktempdir()]) == 2
    end
end

@testset "disease list flags: a different --set refuses the folder" begin
    out = mktempdir()
    list = replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))
    kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=out, io=devnull, experiment=vi1)
    run_extinction(list; kw...)
    @test_throws ArgumentError run_extinction(XXL_DEFAULTS; kw...)
    @test_throws ArgumentError run_extinction(replace_rules(list; disease_count=5); kw...)
    @test_throws ArgumentError Sugarscape.rebuild_extinction_report(XXL_DEFAULTS; label="t", seeds=1, first_seed=20, periods=12,
                                                                    out=out, experiment=vi1, io=devnull)
    @test Sugarscape.rebuild_extinction_report(list; label="t", seeds=1, first_seed=20, periods=12, out=out,
                                               experiment=vi1, io=devnull).extinct == 0
    report = read(joinpath(out, Sugarscape.extinction_name("t", 20, 1, 12) * ".md"), String)
    @test occursin("disease_count=4 founder_diseases=2 disease_lengths=(9, 10)", report)
end

@testset "disease list flags: a list through a stop and resume" begin
    whole, broken = mktempdir(), mktempdir()
    list = replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))
    kw = (label="t", seeds=1, first_seed=20, periods=40, jobs=1, io=devnull, experiment=vi1)
    run_extinction(list; kw..., out=whole)
    @test run_extinction(list; kw..., out=broken, stop_at=25, checkpoint_every=10) === nothing
    run_extinction(list; kw..., out=broken, checkpoint_every=10)
    name = Sugarscape.extinction_name("t", 20, 1, 40)
    @test read(joinpath(whole, name, "seed20.csv")) == read(joinpath(broken, name, "seed20.csv"))
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_disease_list_flags"])'`
Expected: FAIL: `unexpected argument --set`.

- [ ] **Step 3: Implement**

- Move `--set`'s reading out of `scorecard_args` into `rule_setting`; both tools call it.
- `extinction_args`: `--set` in the valued list; `rules=replace_rules(SCORECARD_BASES[base]; sets...)`, with the label as above. `extinction_main` already turns `to_xxl`'s refusal into exit 2, through `extinction_plan`.
- `scorecard_main`: inside its `try`, after `scorecard_args`, check the rules against the three experiments the way `run_scorecard` does at its line 503, by a small helper they share, so a refusal exits 2.
- `EXTINCTION_USAGE`, `extinction_args`' docstring and the comment in `julia/xxl_extinction.jl` name `--set`.

- [ ] **Step 4: Run them to verify they pass**

Same command, then `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_extinction", "xxl_credit_flags", "xxl_scorecard"])'`.
Expected: PASS, with those existing tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add julia/src/xxl/scorecard.jl julia/src/xxl/extinction.jl julia/xxl_extinction.jl julia/test/test_xxl_disease_list_flags.jl
git commit -m "julia xxl: --set on the extinction test"
```

---

### Task 3: The readings and the reading table

**Files:**
- Create: `julia/src/xxl/disease_list.jl`, included in `julia/src/Sugarscape.jl` right after `xxl/credit_compare.jl`
- Test: `julia/test/test_xxl_disease_list_readings.jl` (new), `julia/test/disease_list_helpers.jl` (new; no `test_` prefix, so the runner doesn't pick it up, and included under an `isdefined` guard as `helpers.jl` is)

**Interfaces:**
- Consumes: `CompareSeries`, `extinct_at`, `lowest`, `lowest_t`, `window_population`, `window_births`, `quantile_of`, `percentile_interval`, `BOOT_REPS`, `BOOT_SEED`, `folder_periods`, `seed_done`, `read_seed_csv`, `mean_of`.
- Produces, all in `disease_list.jl`:
  - `ListSeed(series::CompareSeries, sick, circulating, gini, sugar, trades, price)`, each a `Vector{Float64}` indexed `[t + 1]`.
  - `ListRun(name::String, count::Int, founder::Int, lengths::Tuple{Int,Int}, planned::Int, periods::Int, seeds::Vector{ListSeed})`.
  - `list_settings(fingerprint::AbstractString) -> (; count, founder, lengths)`: from the `xxl` line's settings where it names them, else the `Config(...)` line's `disease_list=`, `diseases_per_agent=`, `disease_length=`.
  - `read_list_run(name, folder) -> ListRun`: whole seeds only, as `read_folder_series` does. `planned` is the seed count in the folder's name (`-s<first>-<seeds>-p<periods>`), else the seeds found.
  - `window_sick(s::ListSeed, lo, hi) -> Float64`: the mean skipping NaN; NaN if the seed went extinct at or before `hi`.
  - `in_band(x::Real) -> Bool`: 0.01 ≤ x ≤ 0.2; false for NaN.
  - `ScreenRow(name::String, value::String, bar::String, pass::Bool, near::Bool)`.
  - `screen_arm(run::ListRun, base::ListRun) -> Vector{ScreenRow}`, in order: `X9`, `X10, mean`, `X10, per seed`, `Trough`, `Extinction`. Rows read t ≤ 500 for both runs, except Extinction, which reads the whole run.
  - `arm_passes(run, rows) -> Bool`: all rows pass and every planned seed finished.
  - `arm_near(run, rows) -> Bool`: every planned seed finished, exactly one row fails, and that row is near.
  - `population_spread(run; lo=301, hi=500) -> Float64`.
  - `choose_arm(runs::Vector{ListRun}, base::ListRun) -> Union{Nothing,ListRun}`.
  - `bootstrap_ratio_apart(run::Vector{Float64}, base::Vector{Float64}; reps=BOOT_REPS, seed=BOOT_SEED) -> (; ratio, lo, hi)`: the two sides may differ in length, and each is resampled on its own.
  - `list_readings(run::ListRun; lo=301, hi=500)`: a `NamedTuple` of `trough`, `trough_t`, `births_100`, `x9`, `sick_end` (mean over t = 451–500), `in_band_end`, `under_end`, `over_end`, `population`, `spread`, `gini`, `sugar`, `trades_per_head`, `price`, and per-seed vectors of the same figures in `per_seed`, for the intervals.
  - `circulating_at(run, t) -> (; mean, sd, counts::Dict{Int,Int})`.
  - `sick_by_count(run) -> Vector{NamedTuple}`: per count at the last period, `(count, seeds, sick)`, with `sick` over the last 50 periods.
  - `seeds_losing(run) -> Int`: seeds with fewer diseases at the last period than at t = 200.

**Near** (spec, "misses one row by one seed or by no more than 5% of the bar"): X9 and X10 per seed, one seed short of the `ceil(0.9n)` they need. X10 mean, within 0.0095–0.21. Trough, mean ≥ 0.95 × the baseline's and at most one seed below its lowest. Extinction, never.

**Choosing:** among passing arms, those with `lengths[2] <= 10` if any pass, else the rest. Then most seeds in band over t = 451–500, then smallest spread, then lower `lengths[2]`, then smaller `count`.

- [ ] **Step 1: Write the failing tests**

In `disease_list_helpers.jl`, a helper modelled on `cmp_folder` in `test_xxl_credit_compare.jl`, and the small builders over it that the tests below use (`screen`, `dead_run`, `short`, `arm`, `base`):

```julia
# A folder of 500-period seeds: each seed's population, share sick, diseases at t = 500, given per seed.
function list_folder(dir, name; pops, sick, diseases, settings="", periods=500)
```

It writes `fingerprint.txt` with `julia`, `xxl ... $settings`, a `Config(... disease_list=25, diseases_per_agent=10, disease_length=(1, 10) ...)` line and `periods=$periods`, and CSVs with the columns `t,population,agents_ever,fraction_sick,diseases_circulating,gini,mean_sugar,trades,mean_price`. A folder named `extinction-x-s80-20-p500` plans 20 seeds.

Tests, with a baseline of 20 seeds whose lowest populations have mean 5,000 and minimum 3,000, unless a test says otherwise:

```julia
@testset "disease list readings: settings" begin
    @test Sugarscape.list_settings(BOOK_FP) == (count=25, founder=10, lengths=(1, 10))
    @test Sugarscape.list_settings(ARM_FP) == (count=4, founder=2, lengths=(9, 10))   # the xxl line beats the Config line
    @test Sugarscape.list_settings(ONE_FP) == (count=25, founder=2, lengths=(1, 10))  # founder_diseases=2 only
end

@testset "disease list readings: the bars" begin
    pass, near, fail = screen(in_band=18), screen(in_band=17), screen(in_band=16)   # 20 seeds, others in band
    row(rs, n) = rs[findfirst(r -> r.name == n, rs)]
    @test row(pass, "X10, per seed").pass
    @test !row(near, "X10, per seed").pass && row(near, "X10, per seed").near
    @test !row(fail, "X10, per seed").pass && !row(fail, "X10, per seed").near
    @test [r.name for r in pass] == ["X9", "X10, mean", "X10, per seed", "Trough", "Extinction"]
    # the same for X9 at 18, 17 and 16 seeds with a disease at t = 500
    # X10 mean: 0.2 passes, 0.21 is near, 0.211 is neither; 0.01 passes, 0.0095 is near, 0.009 is neither
    # Trough: mean 5,000 and lowest 3,000 pass; mean 4,750 and one seed at 2,999 fail on two counts but are near;
    # mean 4,749 is not near; two seeds below 3,000 are not near
end

@testset "disease list readings: an extinct seed" begin
    # one of 20 seeds sick at 0.1 until it dies at t = 480; the rest healthy and in band
    @test isnan(Sugarscape.window_sick(dead_seed, 451, 500)) && !Sugarscape.in_band(NaN)
    @test Sugarscape.window_sick(dead_seed, 301, 400) ≈ 0.1
    rows = Sugarscape.screen_arm(dead_run, base)
    @test !rows[5].pass && !rows[5].near
    @test occursin("19 of 20", rows[3].value)
    @test !Sugarscape.arm_near(dead_run, rows) && !Sugarscape.arm_passes(dead_run, rows)
end

@testset "disease list readings: passing and near need every seed" begin
    # 19 whole seeds and one cut short: read_list_run keeps 19, planned is 20
    @test length(short.seeds) == 19 && short.planned == 20
    @test !Sugarscape.arm_passes(short, Sugarscape.screen_arm(short, base))
    @test !Sugarscape.arm_near(short, Sugarscape.screen_arm(short, base))
    @test Sugarscape.choose_arm([short], base) === nothing
end

@testset "disease list readings: the choice" begin
    @test Sugarscape.choose_arm([arm(band=18), arm(band=20)], base).name == "band20"
    @test Sugarscape.choose_arm([arm(spread=0.2), arm(spread=0.1)], base).name == "spread0.1"
    @test Sugarscape.choose_arm([arm(hi=12, band=20), arm(hi=10, band=18)], base).lengths == (9, 10)  # the longer can't win
    @test Sugarscape.choose_arm([arm(hi=12, band=20)], base).lengths == (12, 12)  # unless nothing else passes
    @test Sugarscape.choose_arm([arm(band=16)], base) === nothing
end

@testset "disease list readings: an interval with each side on its own" begin
    r = Sugarscape.bootstrap_ratio_apart(fill(2.0, 20), fill(1.0, 60))
    @test r.ratio == 2.0 && r.lo == 2.0 && r.hi == 2.0
    a, b = [1.0, 1.2, 0.9, 1.1, 1.3], [1.0, 0.8, 1.1, 0.9]
    @test Sugarscape.bootstrap_ratio_apart(a, b) == Sugarscape.bootstrap_ratio_apart(a, b)
    @test isnan(Sugarscape.bootstrap_ratio_apart(a, zeros(4)).lo)
    # paired resampling would give this a zero-width interval; each side on its own doesn't
    w = Sugarscape.bootstrap_ratio_apart([1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0])
    @test w.ratio == 1.0 && w.lo < 1.0 < w.hi
end

@testset "disease list readings: the figures" begin
    # two seeds, hand-computed: trades per head is a seed's trades over its population, summed over the window;
    # price skips NaN; spread is the sample sd over the mean; births_100 is agents_ever at t = 100 less t = 0
    # circulating_at gives mean, sample sd and counts; sick_by_count groups by the last period's count;
    # seeds_losing counts a seed with 3 diseases at t = 200 and 2 at the end, and not one with 2 and 2
end
```

The comments in the last testsets name exact values for the implementer to fix in hand-made data; each comment line becomes `@test` lines.

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_disease_list_readings"])'`
Expected: FAIL: functions not defined.

- [ ] **Step 3: Implement** the Interfaces above, with the constants named at the top of the file: `LIST_SHARE = 0.9`, `NEAR_BY = 0.05`, `SCREEN_END = 500`, `SCREEN_SICK = (451, 500)`, `SICK_BAND = (0.01, 0.2)` (X10's bounds), `LIST_END = 50`, and the window `(301, 500)` as `SPREAD_WINDOW`. Use `X9_T` for the X9 period, and not `END_PERIODS`.

- [ ] **Step 4: Run them to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add julia/src/Sugarscape.jl julia/src/xxl/disease_list.jl julia/test/test_xxl_disease_list_readings.jl
git commit -m "julia xxl: the disease list's readings and table"
```

---

### Task 4: The report and its command line

**Files:**
- Modify: `julia/src/xxl/disease_list.jl`
- Create: `julia/xxl_disease_list.jl`
- Test: `julia/test/test_xxl_disease_list_report.jl` (new; takes its folders from `disease_list_helpers.jl`)

**Interfaces:**
- Consumes: Task 3's functions.
- Produces: `disease_list_report(runs::Vector{ListRun}, base::ListRun; label) -> String`; `disease_list_args(args) -> (; base, arms, out, label)`, with `--base FOLDER`, `--arms NAME=FOLDER,NAME=FOLDER,…`, `--out DIR` (default `RESULTS_XXL`; folders are relative to it), `--label NAME` (default `screening`); `disease_list_main(args) -> exit code`, which writes `<out>/disease-list-<label>.md`, prints it, and returns 2 on a usage error or a missing folder. It runs nothing, so it can be used while a run goes.

**The report's sections**, in order: arms and their settings beside the baseline's; the reading table, one row per arm per bar with pass, near or fail; which arm the table chooses, or that none passes and which are near; the readings table with the baseline's first (trough and when, births to t = 100, diseases at t = 100, 200 and 500 with sd and distribution, X9, end share sick and seeds under, inside and over, population at t = 301–500 and its spread, Gini, mean sugar, trades per head, mean price); ratios of means against the baseline with intervals, labelled as resampling each side independently. **Only when a run goes past t = 500:** the same readings at each of t = 501–1,000 and t = 1,501–2,000 that it reaches; diseases at its last period; the end share sick over the last 50 periods with seeds under, inside and over, and whether the inside share reaches 0.9; seeds losing a disease after t = 200; the share sick by count. An arm with unfinished seeds is flagged in bold at the top, as the extinction report flags its own.

- [ ] **Step 1: Write the failing tests**

```julia
@testset "disease list report: a screening" begin
    report = Sugarscape.disease_list_report([armA, armB], base; label="t")
    @test occursin("| X10, per seed |", report) && occursin("Chosen: B", report)
    @test occursin("| A | 6 | 2 | (9, 10) |", report)
    @test !occursin("t = 1,501", report)
    @test occursin("each side independently", report)
    # none passing: "No arm passes." and the near arm's name; nothing near: "No arm is near."
end

@testset "disease list report: past t = 500" begin
    report = Sugarscape.disease_list_report([long], base_long; label="t")
    @test occursin("t = 501–1,000", report) && occursin("t = 1,501–2,000", report)
    @test occursin("Seeds losing a disease after t = 200", report)
    @test occursin("Inside the band at the end: 54 of 60 (0.9 reached)", report)
end

@testset "disease list report: an unfinished arm" begin
    report = Sugarscape.disease_list_report([short], base; label="t")
    @test occursin("**Unfinished: 1 of 20 seeds of short", report)
end

@testset "disease list report: the command line" begin
    usage(args) = redirect_stderr(() -> Sugarscape.disease_list_main(args), devnull)
    out = mktempdir()
    @test usage(["--out", out]) == 2                                  # no --base
    @test usage(["--base", "b", "--out", out]) == 2                   # no --arms
    @test usage(["--base", "b", "--arms", "A", "--out", out]) == 2    # no = in an arm
    @test usage(["--base", "missing", "--arms", "A=missing", "--out", out]) == 2
    # a real pair of folders: returns 0, and disease-list-<label>.md exists and is what was printed
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_disease_list_report"])'`
Expected: FAIL: functions not defined.

- [ ] **Step 3: Implement**, with `julia/xxl_disease_list.jl` in the shape of `julia/xxl_credit_compare.jl`.

- [ ] **Step 4: Run them to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Check it against the baseline's known figures**

Run: `julia --project=julia julia/xxl_disease_list.jl --base extinction-defaults-s20-60-p2000 --arms today=extinction-defaults-s20-60-p2000 --label baseline-check`

Expected, each recomputed from these CSVs for this plan: X9 57 of 60; X10 mean 0.119; X10 per seed 42 of 60, 4 under and 14 over, failing; trough mean 5,787, lowest 3,441, at t ≈ 68; diseases at t = 500 mean 3.32, sd 1.58; births to t = 100 about 12,409; population at t = 301–500 about 57,346, spread 0.110; trades per head 1.645; at t = 1,951–2,000 mean 0.108 and 47 of 60, 3 under and 10 over. A difference is a bug in the tool.

- [ ] **Step 6: Commit**

```bash
git add julia/src/xxl/disease_list.jl julia/xxl_disease_list.jl julia/test/test_xxl_disease_list_report.jl
git commit -m "julia xxl: the disease list's report"
```

---

### Task 5: The docs, the gate and the freeze

**Files:**
- Modify: `docs/xxl.md`

- [ ] **Step 1: Write Rule 12 in `docs/xxl.md`**, after Rule 11 and in its style: book setting, what the setting does, that only the config changes and neither the rules nor their draw order, the reset for an experiment without disease, and "**Stage 4:** being studied; the defaults don't use it." Add the three rows to the settings table (none, none, none, rule 12). Add to refused combinations: a count below 1; founder diseases below 0 or above the count; a length range that isn't lo ≤ hi with lo ≥ 1, or whose hi reaches `immune_length`; any of the three on an experiment without disease, or disagreeing with the config. In "Running", Fingerprint: "each of the four stage-1 settings" becomes "each later setting", and note the base's `Config` line keeps the experiment's own `disease_list`, as it keeps its map, so the `xxl` line is what names the list. Name `julia/xxl_disease_list.jl` and `--set` on the extinction test.

- [ ] **Step 2: Run the full Julia suite**

Run: `julia --project=julia -e 'using Pkg; Pkg.test()'` in the background, output to a file.
Expected: all pass, about 15 minutes.

- [ ] **Step 3: The gate at book settings**

```bash
julia --project=julia julia/xxl_extinction.jl --label gate-book --seeds 1 --first-seed 20 --periods 100 --jobs 1 --out "$TMP_OUT"
diff <(head -n 102 "$TMP_OUT/extinction-gate-book-s20-1-p100/seed20.csv") <(head -n 102 results-julia-xxl/extinction-defaults-s20-60-p2000/seed20.csv)
```

`TMP_OUT` is a new temporary folder outside the repo. Expected: `diff` prints nothing. That's the new code against the result stage 2 recorded.

- [ ] **Step 4: The gate on a candidate**

```bash
julia --project=julia julia/xxl_extinction.jl --set disease_count=4 --set founder_diseases=2 --set disease_lengths=9,10 --label gate-b --seeds 1 --first-seed 80 --periods 50 --jobs 1 --out "$TMP_OUT"
```

Expected: the folder's `fingerprint.txt` has `free_step=1.5 disease_count=4 founder_diseases=2 disease_lengths=(9, 10)`; the CSV's t = 0 row has `diseases_circulating` at most 4 and `mean_diseases` between 1.8 and 2.0.

- [ ] **Step 5: Commit, then freeze**

```bash
git add docs/xxl.md
git commit -m "docs: rule 12, the disease list"
```

The ledger notes the commit. `julia/src` doesn't change from here on, except for a bug that a run exposes (Task 6, Step 2).

---

### Task 6: Screening

The controller runs this itself. No implementer, and no commit. Long commands run in the background.

**Files:**
- Create (git-ignored): `results-julia-xxl/disease-list-scripts/run-screening.sh`, `watch.ps1`

- [ ] **Step 1: Set up the watch and keep the machine awake**

`watch.ps1` is the stage-3 watcher (scratchpad's `watch-mark.ps1`) with its filter narrowed to `*xxl_extinction.jl*` and `*xxl_scorecard.jl*`: it stops only those trees, on free memory under 1 GB for two polls or commit headroom under 0.5 GB. Check that no other session's `xxl_extinction.jl` is running first, since it can't tell them apart; if one is, narrow the filter by this run's label. Ask the host to keep the machine awake for the length of the runs.

- [ ] **Step 2: Run the six arms, one after another**

| Arm | Label | `--set` |
|---|---|---|
| B | `list-b` | `disease_count=4 founder_diseases=2 disease_lengths=9,10` |
| A | `list-a` | `disease_count=6 founder_diseases=2 disease_lengths=9,10` |
| C | `list-c` | `disease_count=4 founder_diseases=2 disease_lengths=10,10` |
| D | `list-d` | `disease_count=3 founder_diseases=1 disease_lengths=9,10` |
| E | `list-e` | `disease_count=10 founder_diseases=4 disease_lengths=9,10` |
| F | `list-f` | `disease_count=4 founder_diseases=2 disease_lengths=12,12` |

Each: `julia --project=julia julia/xxl_extinction.jl --set … --label list-x --seeds 20 --first-seed 80 --periods 500 --jobs 5`, into the default `results-julia-xxl/`. Expected: about 50 minutes per arm. The report's `TOO FEW SEEDS` at 0 extinct is what 20 seeds give, and isn't a result. After a memory stop, wait for room, and run the same command.

If an arm is refused or crashes, that's a bug and not a result: fix it with a failing test first and ledger the ruling. A fix under `julia/src` changes the code's hash, so a finished arm's CSVs still read but its folder won't resume; unfinished arms restart.

- [ ] **Step 3: Read the table**

Run: `julia --project=julia julia/xxl_disease_list.jl --base extinction-defaults-s20-60-p2000 --arms A=extinction-list-a-s80-20-p500,B=extinction-list-b-s80-20-p500,C=extinction-list-c-s80-20-p500,D=extinction-list-d-s80-20-p500,E=extinction-list-e-s80-20-p500,F=extinction-list-f-s80-20-p500 --label screening`

Ledger what the table says, without changing a bar:

| It says | Next |
|---|---|
| One or more pass | Ledger the chosen arm. Go to Task 7 |
| None passes, one is near | Name at most 3 arms around it in the ledger **before running**, labels `list-r-…`, same seeds and terms. Rerun Step 2 for them and Step 3 with all arms and `--label screening-round2`, so the first table survives. There's no third round |
| None passes after that | Skip Task 7. Go to Task 8 and report what failed |

---

### Task 7: Confirmation

The controller runs this itself, with `$SET` the chosen arm's three `--set` flags and `list-x` its label. No implementer and no commit. Skipped if no arm passed.

- [ ] **Step 1: The scorecards**

```bash
julia --project=julia julia/xxl_scorecard.jl $SET --label list-x --seeds 20 --first-seed 0 --jobs 5
julia --project=julia julia/xxl_scorecard.jl $SET --label list-x --seeds 20 --first-seed 20 --jobs 5
```

Expected: about an hour each; `scorecard-list-x-s0-20.md` and `scorecard-list-x-s20-20.md`. The bar is 13 of 13 on both. Ledger which of X1–X10 and S1–S5 moved against today's scorecards on the same seeds, `scorecard-defaults-x2sight-s0-20.md` and `scorecard-defaults-x2sight-s20-20.md`. Those print 13 of 15 with X2 and X8 as FAIL, because they predate those two becoming reported only, so compare check by check and don't read their count against a new 13 of 13.

- [ ] **Step 2: Credit off, a reading and not a bar**

```bash
julia --project=julia julia/xxl_extinction.jl $SET --no-credit --label list-x-nocredit --seeds 20 --first-seed 20 --periods 500 --jobs 5
julia --project=julia julia/xxl_disease_list.jl --base extinction-nocredit-s20-60-p2000 --arms x-off=extinction-list-x-nocredit-s20-20-p500 --label credit-off
```

Expected: about an hour. The figures to take from the report are X9 and the count of diseases. Its pass or fail doesn't count here.

- [ ] **Step 3: The extinction test**

```bash
julia --project=julia julia/xxl_extinction.jl $SET --label list-x --seeds 60 --first-seed 20 --periods 2000 --jobs 5
```

Expected: 12–15 hours, more if population runs well above today's; `extinction-list-x-s20-60-p2000`. The bar is the user's: 0 of 60, limit 4.87%. Resume with the same command after a stop.

- [ ] **Step 4: The readings**

Run: `julia --project=julia julia/xxl_disease_list.jl --base extinction-defaults-s20-60-p2000 --arms x=extinction-list-x-s20-60-p2000 --label confirmation`

Ledger the result against the spec's table, with no reading changed:

| Result | Reading |
|---|---|
| 0 of 60, 13 of 13 on both seed sets, per-seed X10 at 0.9 or better at the end | Recommend adopting it |
| Any seed extinct | Don't recommend it. Report what happened |
| Passes, but per-seed X10 under 0.9 | Report it as an improvement, if it is, and say the lottery is still there |
| A scorecard check fails | Report it. Recommend only if the user would accept that, and say what it costs |

---

### Task 8: Findings

**Files:**
- Modify: `docs/xxl.md`

- [ ] **Step 1: Write "## Stage 4: the disease list"**, between "## Stage 3: why credit's mark lasts" and "## Results of the first rules (`XXL_V1`)", in stage 3's style: the short answer; the user's ruling that credit is working as intended; the table of arms; the reading table with what fired; my guess against what happened (the spec's two extra readings too: A passing without B–D, and E passing X10); what this doesn't show, including that all of it is on one map pair and that a list can draw the same disease twice (per seed about 3.3% for E, 1.1% for A, 0.6% for C, 0.4% for B, 0.2% for D, 0.15% for F, measured by the whole-branch reviewer and to be recomputed), so a seed starting with fewer distinct diseases than listed isn't a die-off; run time; a recommendation that isn't a decision. Anything found after the runs is labelled as found afterwards. Stage 3's line "Whether that's working as intended is still the user's call" gets a pointer to the ruling.

- [ ] **Step 2: A fresh reviewer**

A fresh subagent on the most capable model recomputes the section's figures from the CSVs with its own script, not this tool, and pushes on the strongest claims. Recompute any figure it offers before using it, and rewrite what doesn't hold.

- [ ] **Step 3: Commit**

```bash
git add docs/xxl.md
git commit -m "docs: stage 4, the disease list"
```

- [ ] **Step 4: Hand over**

Put the question to the user: adopt the chosen list or not. Adoption changes `XXL_DEFAULTS`, makes saved default results stale and needs its own run list, so it's a separate step and not part of this plan.
