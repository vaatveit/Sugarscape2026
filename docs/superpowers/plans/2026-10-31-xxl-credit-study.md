# xxl credit study Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire X8 as a threshold, add three off-by-default credit options and the flags that reach them, add a comparison of finished runs, then run the study and write the findings.

**Architecture:** The options are `Config` fields read by `rules/credit.jl`. A `CreditOptions` value applies them to an `Experiment` for `run_extinction`, and `TraceWorld` carries the two the tracer can follow. A new `xxl/credit_compare.jl` reads only finished CSVs, so it runs nothing.

**Tech Stack:** Julia, the `Sugarscape` package in `julia/`, with no new dependency. `Random.Xoshiro` is already imported.

**Spec:** `docs/superpowers/specs/2026-10-31-xxl-credit-study-design.md`

## Global Constraints

- With the new options at their defaults, a run's CSV stays byte-identical. The tracer may not draw random numbers or alter a loan.
- Options default to `claims_outlive_lender=false`, `credit_reach=1.0`, `lender_limit=false`.
- No change to `XXL_DEFAULTS`. Julia only: no Python, viewer or FLAME GPU change.
- Existing tests change only as Task 1 lists, for X8. New tests go in new files or new testsets.
- No edit under `julia/src` once a long run has started: the fingerprint holds the source's hash.
- Bootstrap: 10,000 resamples of seed pairs from a fixed seed; percentile 95% interval.
- Commits end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Commits are on `xxl-credit-study` only. Nothing is merged or pushed.
- Comments and docstrings match the surrounding style: plain sentences, citing the book's page where a rule comes from it.

## Review Focus

- A seed stopped and resumed while a dead lender's loan is still on the book, with `claims_outlive_lender` on, should give the same bytes as a seed that never stopped. Test in Task 3.
- A comparison run while the main run is in progress should count only finished seeds, and ignore a half-written or missing CSV and checkpoints. Test in Task 4.
- `--claims-outlive-lender --inheritance`, or an option with `--no-credit`, should be a usage error with exit 2, not a stack trace. Test in Task 3.
- A lender's budget from one period must not carry into the next, and rollovers in `settle_loans!` must not draw on it. Test in Task 2.
- A seed that goes extinct in one arm should leave later windows, be counted, and not produce an infinite ratio or a lift from a zero. Test in Task 4.

---

### Task 1: Retire X8

**Files:**
- Modify: `julia/src/xxl/scorecard.jl:1-4,13,44,133,312,379-383`
- Modify: `julia/test/test_xxl_scorecard.jl`
- Modify: `docs/superpowers/specs/2026-10-29-xxl-revised-design.md:133`, `docs/xxl.md:428-431,474`

**Interfaces:**
- Consumes: `Check(id, aspect, value, low, high, pass, detail, reported_only)` as X2 uses it.
- Produces: `CHECK_TITLES["X8"] == "Loans voided by a death"`; X8 has `reported_only == true`.

- [ ] **Step 0: Set up the branch**

The controller does this before Task 1, and it isn't part of the implementer's brief:

```bash
git switch -c xxl-credit-study
git add docs/superpowers/specs/2026-10-31-xxl-credit-study-design.md docs/superpowers/plans/2026-10-31-xxl-credit-study.md
git commit -m "docs: the credit study's design and plan"
```

- [ ] **Step 1: Change the tests first**

In `julia/test/test_xxl_scorecard.jl`:
- Remove the `"X8"` entry from `SCD_PAIRS`, as X2's was removed.
- In the extinct-seed testset, `@test all(c -> c.pass || occursin("seed 1", c.detail), checks)` becomes `@test all(c -> c.pass || c.reported_only || occursin("seed 1", c.detail), checks)`.
- In "X2 is reported only", `count(c -> c.reported_only, checks) == 1` becomes `== 2`, and `"Passing: 14 of 14 checks"` becomes `"Passing: 13 of 13 checks"`.
- Add this testset beside it:

```julia
@testset "X8 is reported only" begin
    xxl, xl, columns = scd_data()
    scd_set!(xxl["VI-1"], "loans_repaid", 1.0)
    scd_set!(xxl["VI-1"], "loans_voided", 9.0)  # 0.9, far above the old 0.2
    checks = Sugarscape.score(xxl, xl, columns)
    x8 = scd_check(checks, "X8")
    @test x8.reported_only && !x8.pass && x8.value ≈ 0.9
    @test Sugarscape.CHECK_TITLES["X8"] == "Loans voided by a death"
    @test Sugarscape.threshold_text(x8) == "—"
end
```

The report-row assertion goes in the same report block as X2's: `@test occursin(r"\| X8 Loans voided by a death \| [^|]+ \| — \| reported only \|", report)`.

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_scorecard"])'`
Expected: FAIL on the new X8 assertions and the 13 of 13 count.

- [ ] **Step 3: Implement**

`score`: `push!(checks, Check("X8", "Credit", v, -Inf, Inf, false, d, true))`. Title as above. Update the file's opening comment, `score`'s docstring line for X8 ("their mean. Reported only: no threshold, no pass or fail."), and `scorecard_report`'s docstring ("`reported only` for X2 and X8").

- [ ] **Step 4: Run them to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: The docs**

- The stage-1 spec's X8 row: reported only, with a pointer to the credit study's design, the same way the X2 row was changed.
- `docs/xxl.md:474`: title and "reported only" in the threshold column.
- `docs/xxl.md:428-431`: say that X2 and X8 are both now reported values, each with its spec named, and that X1 and X3–X7, X9, X10 are the baseline. Past reports aren't re-run and their counts stay as recorded, out of 15 or 14; 13 now apply. Scorecard rows in tables below keep their figures.

- [ ] **Step 6: Commit**

```bash
git add julia/src/xxl/scorecard.jl julia/test/test_xxl_scorecard.jl docs/xxl.md docs/superpowers/specs/2026-10-29-xxl-revised-design.md
git commit -m "julia xxl: X8 is reported only"
```

---

### Task 2: The three credit options

**Files:**
- Modify: `julia/src/config.jl` (fields after `credit`, validation in its `credit` block, and the comment "the one Julia-only field")
- Modify: `julia/src/rules/credit.jl`
- Modify: `julia/src/model.jl` (a `lend_left` field, its constructor call, and clearing it in `step!`)
- Test: `julia/test/test_credit_options.jl` (new)

**Interfaces:**
- Produces: `Config` fields `claims_outlive_lender::Bool=false`, `credit_reach::Float64=1.0`, `lender_limit::Bool=false`, with a comment that they are Julia-only study options. `Model` field `lend_left::Dict{Int,Float64}`: each lender's remaining limit this period, by id. `lending_left(m::Model, a::Agent) -> Float64`, exported beside `available_to_lend`.

- [ ] **Step 1: Write the failing tests**

Create `julia/test/test_credit_options.jl`. Start it with the same `helpers.jl` include as `test_credit.jl`, and local copies of `credit_model` and `person` under other names (`opt_model`, `opt_person`), since test files share a module.

```julia
@testset "credit options: validation" begin
    base = (; sex=true, credit=(10, 10.0))
    @test_throws ArgumentError validate(Config(; sex=true, credit=nothing, claims_outlive_lender=true))
    @test_throws ArgumentError validate(Config(; sex=true, credit=nothing, lender_limit=true))
    @test_throws ArgumentError validate(Config(; sex=true, credit=nothing, credit_reach=2.0))
    @test_throws ArgumentError validate(Config(; base..., credit_reach=0.0))
    @test_throws ArgumentError validate(Config(; base..., claims_outlive_lender=true, inheritance=true))
    validate(Config(; base..., claims_outlive_lender=true, credit_reach=2.0, lender_limit=true))
end

@testset "credit_reach: the limit moves with it" begin
    # income 10 x d 10 = 100 of income; a loan's due is 2 x its principal, so 50 is the most at reach 1.
    m = opt_model(; credit_reach=1.0)
    old = opt_person(m, 3, 3, 50, 1000.0)
    atlimit = opt_person(m, 3, 4, 20, 10.0; initial=60.0)
    @test creditworthy(m, atlimit, 100.0) && !creditworthy(m, atlimit, 100.0001)
    m2 = opt_model(; credit_reach=2.0)
    opt_person(m2, 3, 3, 50, 1000.0)
    a2 = opt_person(m2, 3, 4, 20, 10.0; initial=60.0)
    @test creditworthy(m2, a2, 200.0) && !creditworthy(m2, a2, 200.0001)
end

@testset "claims_outlive_lender: the debt stands and the sugar leaves the world" begin
    m = opt_model(; claims_outlive_lender=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    Sugarscape.credit_on_death!(m, old, ())
    old.alive = false
    @test loan in m.loans && haskey(m.debts, young.id)
    before = old.sugar
    young.sugar = 200.0
    m.t = loan.due_t
    settle_loans!(m)
    @test young.sugar == 200.0 - loan.due
    @test old.sugar == before  # no agent received it
    @test isempty(m.loans) && !haskey(m.lent, old.id)
end

@testset "claims_outlive_lender: an unpaid debt rolls over, and a borrower's death still voids" begin
    m = opt_model(; claims_outlive_lender=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    Sugarscape.credit_on_death!(m, old, ())
    old.alive = false
    young.sugar = 10.0
    m.t = loan.due_t
    settle_loans!(m)
    @test young.sugar == 5.0 && length(m.loans) == 1 && m.loans[1].lender === old
    Sugarscape.credit_on_death!(m, young, ())
    @test isempty(m.loans) && isempty(m.lent)
end

@testset "claims_outlive_lender: both dying together voids" begin
    m = opt_model(; claims_outlive_lender=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    seek_credit!(m, young)
    Sugarscape.credit_on_deaths!(m, (old, young), (old, young))
    @test isempty(m.loans) && isempty(m.lent) && isempty(m.debts)
end

@testset "lender_limit: at most half its wealth in a period, in all" begin
    m = opt_model(; lender_limit=true)
    old = opt_person(m, 3, 3, 50, 100.0)  # past childbearing
    @test lending_left(m, old) == 50.0
    a = opt_person(m, 3, 4, 20, 40.0)  # lacks 20
    b = opt_person(m, 4, 3, 20, 20.0)  # lacks 40, gets the 30 left
    c = opt_person(m, 2, 3, 20, 20.0)
    seek_credit!(m, a)
    seek_credit!(m, b)
    @test isempty(seek_credit!(m, c))
    @test old.sugar == 50.0
    empty!(m.lend_left)  # as step! does at a period's start
    @test lending_left(m, old) == 25.0
    @test length(seek_credit!(m, c)) == 1 && old.sugar == 25.0
end

@testset "lender_limit: a childbearing lender keeps what children need" begin
    m = opt_model(; lender_limit=true)
    rich = opt_person(m, 3, 3, 20, 100.0)  # needs 60, so 40 by the rule, 50 by the limit
    poor = opt_person(m, 3, 4, 20, 0.0)
    @test seek_credit!(m, poor)[1].principal == 40.0
end

@testset "lender_limit: step! clears the budgets and settling draws on none" begin
    m = opt_model(; lender_limit=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    @test haskey(m.lend_left, old.id)
    left = m.lend_left[old.id]
    young.sugar = 0.0
    m.t = loan.due_t
    settle_loans!(m)  # a rollover
    @test m.lend_left[old.id] == left
    step!(m)
    @test !haskey(m.lend_left, old.id) || m.lend_left[old.id] != left
end

@testset "off: lending_left doesn't limit" begin
    m = opt_model()
    @test lending_left(m, opt_person(m, 3, 3, 50, 100.0)) == Inf
end
```

If `opt_person` placement or the `put_agent` neighbour rule makes an arrangement wrong (neighbours must be in vision of the borrower), adjust the sites, not the assertions.

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["credit_options"])'`
Expected: FAIL: `Config has no field` or `lending_left` not defined.

- [ ] **Step 3: Implement**

- `validate`, in or after its `credit` block: each option needs `credit` (messages name the option); `credit_reach > 0`; `claims_outlive_lender && inheritance` is refused, since they answer the same death two ways.
- `creditworthy`: `borrower.last_income * d * m.config.credit_reach - owed >= due`. Multiplying by 1.0 changes no bits.
- `lending_left(m, a)`: `Inf` when the option is off; otherwise `get(m.lend_left, a.id, a.sugar / 2)`. It stores nothing, so the budget is fixed at the lender's first loan of the period, as the spec says, and a refused request doesn't fix it.
- `seek_credit!`: `left = lending_left(m, lender)`, `amount = min(available_to_lend(m, lender), left, need)`, and when the option is on, after the loan is made, `m.lend_left[lender.id] = left - amount`. `available_to_lend` itself doesn't change, so the census's could-lend group doesn't either.
- `credit_on_deaths!`: in `if loan.lender in dying`, first: if `m.config.claims_outlive_lender`, `push!(keep, loan)` and `continue`, with the loan's `m.lent` count left as it is. A borrower dying is tested first already, so "both" still voids.
- `settle_loans!`: paying the lender becomes `lender.alive && (lender.sugar += x)` in both branches. A living lender is unchanged; a dead lender's share leaves the world.
- `Model`: `lend_left::Dict{Int,Float64}` after `loan_trace`, built empty. In `step!`, `cfg.lender_limit && empty!(m.lend_left)` at the top, with the other per-period clears.
- Update `credit_on_deaths!`'s docstring and `Config`'s comment.

`checkpoint.jl` saves `lend_left` as a plain field and needs no change: it holds no agents.

- [ ] **Step 4: Run them to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: The nearby suites**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["credit", "config", "xxl_extinction"])'`
Expected: PASS, with no existing test changed. These include "no field of the model or an agent escapes the flat table".

- [ ] **Step 6: Commit**

```bash
git add julia/src/config.jl julia/src/rules/credit.jl julia/src/model.jl julia/src/Sugarscape.jl julia/test/test_credit_options.jl
git commit -m "julia credit: three study options, off by default"
```

---

### Task 3: The flags on both tools

**Files:**
- Modify: `julia/src/xxl/extinction.jl`, `julia/src/xxl/loan_run.jl`, `julia/xxl_extinction.jl` and `julia/xxl_loan_trace.jl` (their usage comments), `julia/README.md`
- Test: `julia/test/test_xxl_credit_flags.jl` (new)

**Interfaces:**
- Consumes: the `Config` fields from Task 2.
- Produces, in `extinction.jl`:
  - `Base.@kwdef struct CreditOptions; credit_off::Bool=false; inheritance::Bool=false; claims_outlive_lender::Bool=false; credit_reach::Float64=1.0; lender_limit::Bool=false; end`
  - `options_text(o::CreditOptions) -> String`: `""` at the defaults, otherwise a comma-joined list such as `"credit off, inheritance"`.
  - `with_options(exp::Experiment, o::CreditOptions) -> Experiment`: `exp` itself at the defaults, otherwise both configs swapped.
  - An `options::CreditOptions=CreditOptions()` keyword on `extinction_plan`, `run_extinction`, `rebuild_extinction_report`, `write_extinction_report` and `extinction_report`. `extinction_args` returns `options`.
- Produces, in `loan_run.jl`: `TraceWorld(name, credit, inheritance; credit_reach=1.0, lender_limit=false)`, with those two as fields.

- [ ] **Step 1: Write the failing tests**

Create `julia/test/test_xxl_credit_flags.jl`, with the registry loaded as `test_xxl_extinction.jl` does, and the shorter VI-1 run those tests use (`periods=12`, `seeds=1`, `first_seed=20`):

```julia
@testset "credit flags: options" begin
    @test Sugarscape.options_text(CreditOptions()) == ""
    @test Sugarscape.options_text(CreditOptions(; credit_off=true, inheritance=true)) == "credit off, inheritance"
    e = find_experiment(load_registry(), "VI-1")
    @test Sugarscape.with_options(e, CreditOptions()) === e
    off = Sugarscape.with_options(e, CreditOptions(; credit_off=true))
    @test off.config.credit === nothing && off.xl_config.credit === nothing
    reach = Sugarscape.with_options(e, CreditOptions(; credit_reach=2.0, lender_limit=true))
    @test reach.config.credit_reach == 2.0 && reach.config.lender_limit && reach.config.credit == e.config.credit
end

@testset "credit flags: the fingerprint changes only when an option does" begin
    r, e = XXL_DEFAULTS, find_experiment(load_registry(), "VI-1")
    plain = Sugarscape.extinction_plan(r, e, "o", "l", 20, 1, 12)
    same = Sugarscape.extinction_plan(r, e, "o", "l", 20, 1, 12; options=CreditOptions())
    off = Sugarscape.extinction_plan(r, e, "o", "l", 20, 1, 12; options=CreditOptions(; credit_off=true))
    @test plain.fingerprint == same.fingerprint
    @test !occursin("credit options", plain.fingerprint)
    @test occursin("credit options: credit off\n", off.fingerprint)
end

@testset "credit flags: a change of flag refuses the folder" begin
    out = mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=out, io=devnull, experiment=EXT2_VI1)
    run_extinction(XXL_DEFAULTS; kw..., options=CreditOptions(; credit_off=true))
    @test_throws ArgumentError run_extinction(XXL_DEFAULTS; kw...)
    @test_throws ArgumentError run_extinction(XXL_DEFAULTS; kw..., options=CreditOptions(; inheritance=true))
end

@testset "credit flags: options off, the same bytes" begin
    a, b = mktempdir(), mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=EXT2_VI1)
    run_extinction(XXL_DEFAULTS; kw..., out=a)
    run_extinction(XXL_DEFAULTS; kw..., out=b, options=CreditOptions())
    name = Sugarscape.extinction_name("t", 20, 1, 12)
    @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
end

@testset "credit flags: an option changes the run" begin
    a, b = mktempdir(), mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=40, jobs=1, io=devnull, experiment=EXT2_VI1)
    run_extinction(XXL_DEFAULTS; kw..., out=a)
    run_extinction(XXL_DEFAULTS; kw..., out=b, options=CreditOptions(; credit_off=true))
    name = Sugarscape.extinction_name("t", 20, 1, 40)
    @test read(joinpath(a, name, "seed20.csv")) != read(joinpath(b, name, "seed20.csv"))
end

@testset "credit flags: claims outlive the lender through a stop and resume" begin
    whole, broken = mktempdir(), mktempdir()
    o = CreditOptions(; claims_outlive_lender=true)
    kw = (label="t", seeds=1, first_seed=20, periods=40, jobs=1, io=devnull, experiment=EXT2_VI1, options=o)
    run_extinction(XXL_DEFAULTS; kw..., out=whole)
    @test run_extinction(XXL_DEFAULTS; kw..., out=broken, stop_at=25, checkpoint_every=10) === nothing
    run_extinction(XXL_DEFAULTS; kw..., out=broken, checkpoint_every=10)
    name = Sugarscape.extinction_name("t", 20, 1, 40)
    @test read(joinpath(whole, name, "seed20.csv")) == read(joinpath(broken, name, "seed20.csv"))
end

@testset "credit flags: the report names the options" begin
    out = mktempdir()
    o = CreditOptions(; credit_off=true)
    run_extinction(XXL_DEFAULTS; label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=out, io=devnull,
                   experiment=EXT2_VI1, options=o)
    report = read(joinpath(out, Sugarscape.extinction_name("t", 20, 1, 12) * ".md"), String)
    @test occursin("- Credit options: credit off", report)
end

@testset "credit flags: the extinction command line" begin
    usage(args) = redirect_stderr(() -> extinction_main(args), devnull)
    for args in (
        ["--credit-reach"], ["--credit-reach", "0"], ["--credit-reach", "x"],
        ["--claims-outlive-lender", "--inheritance"], ["--no-credit", "--lender-limit"],
        ["--no-credit", "--credit-reach", "2"], ["--no-credit", "--claims-outlive-lender"],
    )
        @test usage([args; "--out"; mktempdir()]) == 2
    end
    a = Sugarscape.extinction_args(["--no-credit", "--inheritance"])
    @test a.options == CreditOptions(; credit_off=true, inheritance=true)
    a = Sugarscape.extinction_args(["--claims-outlive-lender", "--credit-reach", "2", "--lender-limit"])
    @test a.options == CreditOptions(; claims_outlive_lender=true, credit_reach=2.0, lender_limit=true)
end

@testset "credit flags: the loan trace" begin
    w = Sugarscape.loan_trace_args(["--credit-reach", "2", "--lender-limit"]).w
    @test w.credit_reach == 2.0 && w.lender_limit
    plain = TraceWorld("defaults", (10, 10.0), false)
    @test plain.credit_reach == 1.0 && !plain.lender_limit
    e = Sugarscape.trace_experiment(w, 12; experiment=EXT2_VI1)
    @test e.config.credit_reach == 2.0 && e.xl_config.lender_limit
    fp(x) = Sugarscape.trace_fingerprint(Sugarscape.trace_experiment(x, 12; experiment=EXT2_VI1), x, 12)
    @test !occursin("credit_reach", fp(plain)) && occursin("credit_reach=2.0\nlender_limit=true\n", fp(w))
    @test occursin("credit reach 2.0", Sugarscape.world_text(w)) && occursin("lender limit", Sugarscape.world_text(w))
    usage(args) = redirect_stderr(() -> loan_trace_main(args), devnull)
    @test usage(["--no-credit", "--credit-reach", "2"]) == 2
    @test usage(["--no-credit", "--lender-limit"]) == 2
    @test usage(["--credit-reach", "0"]) == 2
end
```

`EXT2_VI1` is `find_experiment(load_registry(), "VI-1")`. Export or qualify `CreditOptions` and `TraceWorld` in the way this package's other tests reach such names.

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["credit_flags"])'`
Expected: FAIL: `CreditOptions` not defined.

- [ ] **Step 3: Implement**

- `extinction_fingerprint(exp, rules, periods; options=CreditOptions())`: after `xxl_fingerprint`, a line `credit options: <text>\n` only when `options_text` isn't empty. So a default folder's fingerprint keeps its shape and `--report-only` still only warns on a code change. `extinction_plan` applies `with_options` and passes the options on.
- The report's header gains `- Credit options: <text>` when not empty.
- `extinction_args`: `--no-credit`, `--inheritance`, `--claims-outlive-lender`, `--lender-limit`, and `--credit-reach K` (a `parse(Float64, v)`). Option conflicts surface as `ArgumentError` inside `extinction_main`'s `try`, through `with_options`'s `replace_config` validation, so they exit 2. `--credit-reach` at or below 0 fails the same way. If `extinction_args` returns before validation runs, make sure `extinction_plan` in that `try` hits it.
- `run_extinction` and `rebuild_extinction_report` pass `options` through to the plan and report; the workers receive the swapped `exp`, so `extinction_seed!` doesn't change.
- `TraceWorld`: the two fields and keywords, both swapped in `trace_experiment`. `trace_fingerprint` appends `credit_reach=<k>\nlender_limit=<b>\n` after `inheritance=` only when either differs from its default, ahead of the code line. `world_text` adds `, credit reach <k>` and `, lender limit` when set. With credit off either option is an `ArgumentError`, from `TraceWorld`'s constructor.
- `loan_trace_args`: `--credit-reach K`, `--lender-limit`. Update `LOAN_USAGE`, `EXTINCTION_USAGE` and both docstrings.
- The scripts' usage comments, and `julia/README.md`'s two tool sections.

- [ ] **Step 4: Run them to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Run the existing tool suites**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["xxl_extinction", "xxl_loan"])'`
Expected: PASS, with no existing test changed.

- [ ] **Step 6: Commit**

```bash
git add julia/src/xxl/extinction.jl julia/src/xxl/loan_run.jl julia/src/Sugarscape.jl julia/xxl_extinction.jl julia/xxl_loan_trace.jl julia/README.md julia/test/test_xxl_credit_flags.jl
git commit -m "julia xxl: credit options on the extinction and loan trace tools"
```

---

### Task 4: The comparison

**Files:**
- Create: `julia/src/xxl/credit_compare.jl`, `julia/xxl_credit_compare.jl`
- Modify: `julia/src/Sugarscape.jl` (include after `xxl/loan_run.jl`), `julia/README.md`
- Test: `julia/test/test_xxl_credit_compare.jl` (new)

**Interfaces:**
- Consumes: `read_seed_csv(path) -> (header, M)`, `seed_done(path, periods)`, `fmt`, `write_atomic`, `RESULTS_XXL`.
- Produces:
  - `COMPARE_WINDOWS = ((1,100),(101,200),(201,300),(301,500),(501,1000),(1001,1500),(1501,2000))`, `BOOT_REPS = 10_000`, `BOOT_SEED = 20261031`, `LAG_TIMES = (100,150,200)`, `LAG_HALF = 5`.
  - `struct CompareSeries; seed::Int; population::Vector{Float64}; ever::Vector{Float64}; end`, with `population[t + 1]` the value at period t.
  - `folder_periods(folder) -> Int`, from the `periods=` line of `fingerprint.txt`; `ArgumentError` if absent.
  - `read_folder_series(folder) -> Dict{Int,CompareSeries}`: seeds with a whole CSV only.
  - `extinct_at(s) -> Union{Nothing,Int}`; `lowest(s) -> Float64` (over t ≥ 1).
  - `window_population(s, lo, hi)`, the mean; `window_births(s, lo, hi)`, `ever[hi + 1] - ever[lo]`; `births_per_head(s, lo, hi)`, births over the sum of population.
  - `bootstrap_ratio(run::Vector{Float64}, base::Vector{Float64}; reps=BOOT_REPS, seed=BOOT_SEED) -> (; ratio, lo, hi)`: ratio of means, resampling pairs.
  - `bootstrap_lift(run, off, on; reps=BOOT_REPS, seed=BOOT_SEED) -> (; lift, lo, hi)`: (mean run − mean off) ÷ (mean on − mean off), resampling triples; `NaN` lift, `lo` and `hi` if the means of `on` and `off` are equal; a resample with a zero denominator is dropped.
  - `interval_state(lo, hi, line) -> Symbol`: `:above` if `lo > line`, `:below` if `hi < line`, otherwise `:straddles`.
  - `band_state(lo, hi; low=0.95, high=1.05) -> Symbol`: `:inside` if `lo > low && hi < high`, `:above` if `lo > high`, `:below` if `hi < low`, otherwise `:straddles`.
  - `population_lag(base::CompareSeries, run::CompareSeries, t::Int) -> Int`: `t − t′`, where `t′` is the period after `base`'s lowest point, within `t + 120`, whose population, smoothed over `t′ ± LAG_HALF`, is nearest `run`'s smoothed at `t`.
  - `credit_compare(out; on, off, runs, label="credit") -> String`: the report, also written to `<out>/credit-compare-<label>.md`.
  - `credit_compare_main(args) -> exit code`, for `--on A --off B [--runs C,D,…] [--out DIR] [--label NAME]`; 2 on a usage error or a folder with no fingerprint.

- [ ] **Step 1: Write the failing tests**

Create `julia/test/test_xxl_credit_compare.jl`. A helper writes a hand-made folder:

```julia
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
```

```julia
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["credit_compare"])'`
Expected: FAIL: `bootstrap_ratio` not defined.

- [ ] **Step 3: Implement `julia/src/xxl/credit_compare.jl`**

The report, for each folder pair, writes:

- A header: the folders, `Seeds shared with <base>: N`, `Extinct: <base> a of N, <run> b of N`, and when the lengths differ, `<run> reaches t = P, <base> t = Q: compared over t ≤ min`.
- A table with one row per measure and window that both reach. Measures: lowest population ("Trough"), mean population by window, births by window, births per head by window. Columns: `Window | Measure | Ratio | 95% interval | Against 1 | Against 0.95–1.05 | Per-seed range | Below base | Pairs`.
- A pair is left out of a window when either side went extinct before the window's start, with a line for each such window, in the form `1 pair left out as extinct in t = 201–300` (`N pairs` above one). The trough row keeps all pairs. Per-seed ratios that aren't finite stay out of the range. `—` is printed wherever a figure isn't finite.
- Lag rows at `LAG_TIMES`: mean and per-seed range of `population_lag`, where both reach them, over seeds extinct on neither side by then.

The report's sections, in order: `off` against `on`; then each of `runs` against `on` and against `off`, each followed by two rows over the seeds all three share: `Lift kept, trough | <lift> | <interval> | <state against 0.5>` and `Lift kept, births t ≤ 100 | …`.

The script `julia/xxl_credit_compare.jl` follows the other two: a usage comment, `using Sugarscape`, `exit(Sugarscape.credit_compare_main(ARGS))`. `julia/README.md` gets a short section.

- [ ] **Step 4: Run them to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: On real data**

Run: `julia --project=julia julia/xxl_credit_compare.jl --on loans-defaults-s20-10-p2000 --off loans-nocredit-s20-5-p500 --label smoke`
Expected: exit 0. In `results-julia-xxl/credit-compare-smoke.md`: 5 shared seeds; births t ≤ 100 near 0.75 and the trough near 0.85 (ratios of means, so close to the earlier means of ratios, not equal), trough interval wholly below 1.

- [ ] **Step 6: The whole suite, then commit**

Run: `julia --project=julia -e 'using Pkg; Pkg.test()'` (about 9 minutes; run it in the background).
Expected: all pass.

```bash
git add julia/src/xxl/credit_compare.jl julia/xxl_credit_compare.jl julia/src/Sugarscape.jl julia/README.md julia/test/test_xxl_credit_compare.jl
git commit -m "julia xxl: compare finished runs, seed by seed"
```

---

### Task 5: The runs, the findings

Run this after the whole-branch review, so a defect found in review can't waste the runs. The controller runs it, not a subagent.

**Files:** Modify `docs/xxl.md`. Results go in `results-julia-xxl/` (git-ignored).

**Interfaces:**
- Consumes: the flags from Task 3 and `julia/xxl_credit_compare.jl` from Task 4.

- [ ] **Step 1: The gate, on the final commit**

```bash
julia --project=julia julia/xxl_extinction.jl --label gate-options --seeds 1 --first-seed 20 --periods 500 --jobs 1
julia --project=julia julia/xxl_loan_trace.jl --label gate-options --seeds 1 --first-seed 20 --periods 500 --jobs 1
```

Compare the first 502 lines of `results-julia-xxl/extinction-gate-options-s20-1-p500/seed20.csv` with those of `results-julia-xxl/extinction-defaults-s20-60-p2000/seed20.csv` by `cmp`. Do the same for the loan trace's `seed20.csv`. `cmp` `results-julia-xxl/loans-gate-options-s20-1-p500/seed20.tally.csv` with `results-julia-xxl/loans-gate-s20-1-p500/seed20.tally.csv`, which is the earlier code's.
Expected: identical bytes, all three. **A failure stops here. No long run starts.**

- [ ] **Step 2: The main run, in the background, with the machine kept awake and memory watched**

Run: `julia --project=julia julia/xxl_extinction.jl --label nocredit --no-credit --seeds 60 --first-seed 20 --periods 2000 --jobs 5`

Use 4 workers if free memory is under 12 GB when it starts. A watcher as in stage 3 stops this run's Julia tree only, on free memory under 1 GB for two polls in a row, or commit headroom under 0.5 GB, and leaves other sessions' jobs alone. If it stops, the same command carries on from each seed's checkpoint, with fewer workers if the shortage was real. If the same seed fails twice, stop and report. Log to `results-julia-xxl/extinction-nocredit-s20-60-p2000.log`, with a dated line at each start, for the real run time.

- [ ] **Step 3: Check the main run**

Read the report: 60 seeds, and does the verdict follow from its table? Run the comparison:

```bash
julia --project=julia julia/xxl_credit_compare.jl --on extinction-defaults-s20-60-p2000 --off extinction-nocredit-s20-60-p2000 --label main
```

Expected: 60 shared seeds; births t ≤ 100 and the trough close to the 5-seed readings. Seeds 20–24's CSVs over t ≤ 500 must equal `loans-nocredit-s20-5-p500/seed<k>.csv`'s first 502 lines by `cmp`. **A failure stops here and gets reported.**

- [ ] **Step 4: The probes, one at a time**

```bash
julia --project=julia julia/xxl_extinction.jl --label inherit --inheritance --seeds 10 --first-seed 20 --periods 500 --jobs 4
julia --project=julia julia/xxl_extinction.jl --label inherit-nocredit --inheritance --no-credit --seeds 10 --first-seed 20 --periods 500 --jobs 4
julia --project=julia julia/xxl_extinction.jl --label claims --claims-outlive-lender --seeds 20 --first-seed 20 --periods 500 --jobs 4
julia --project=julia julia/xxl_loan_trace.jl --label reach2 --credit-reach 2 --seeds 10 --first-seed 20 --periods 500 --jobs 4
julia --project=julia julia/xxl_loan_trace.jl --label limit --lender-limit --seeds 10 --first-seed 20 --periods 500 --jobs 4
```

Then:

```bash
julia --project=julia julia/xxl_credit_compare.jl --on extinction-defaults-s20-60-p2000 --off extinction-nocredit-s20-60-p2000 --runs extinction-inherit-s20-10-p500,extinction-inherit-nocredit-s20-10-p500,extinction-claims-s20-20-p500,loans-reach2-s20-10-p500,loans-limit-s20-10-p500 --label study
```

The reach and limit readings also use the base's rollovers, deaths and lenders' matched sugar ratio. Quote seeds 20–29 from `results-julia-xxl/loans-defaults-s20-10-p2000.md`'s t = 1–500 column, and each probe's own report.

- [ ] **Step 5: Check before writing**

Whether the seeds stayed paired: compute, over the 60 seeds, the correlation of credit-on and credit-off seeds' mean population at t = 1,501–2,000, and report it. Read every interval against its row in the spec's "How the findings are read". Check that the ratio of means and the earlier means of ratios aren't quoted as if the same.

- [ ] **Step 6: Write the findings into `docs/xxl.md`**

A new section after "Stage 3: what X8 measures", "Stage 3: what credit adds". It opens by saying the user chose to retire X8 and study credit. It states: the extinction verdict; the windows table, with intervals; whether seeds stayed paired and so what 60 seeds could resolve; the probes, with the spec's confounds; the written guess and whether it held; which reading rows fired, including every straddle and the largest effect it rules out; the limits (one map pair, 10 or 20 seeds on the probes, not randomized, the census readings from the 5-seed no-credit run); that 13 of 13 doesn't mean credit works; the real run time including any stops, from logs, not `elapsed.txt`; a recommendation, labelled as one. No change to the rules.

Start a fresh reviewer on the section before committing, as for the last findings: give it the section, the reports, the CSV folders and the spec's reading table, ask it to recompute the figures and push on the strongest claims, and recompute any new figure it offers before using it.

- [ ] **Step 7: Commit, then put the decision to the user**

```bash
git add docs/xxl.md
git commit -m "docs: stage 3, what credit adds"
```

Hand over the findings, the ledger's rulings and deferred minors, and the two questions the spec leaves: what to change, and whether helping the society through its worst period counts as credit working as intended. What changes is the user's decision, under a new spec.
