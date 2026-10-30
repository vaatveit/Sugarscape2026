# xxl stage 2: the extinction test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test whether VI-1 under `XXL_DEFAULTS` has less than a 5% chance of extinction over 2,000 periods, and make X2 a reported-only check.

**Architecture:** A new file `julia/src/xxl/extinction.jl` holds pure functions (the limit, one seed's outcome, the report) and a resumable runner that writes each seed as it finishes, with `julia/xxl_extinction.jl` as its command line. It reuses the runner's `seed_job`, `write_seed_csv`, `write_timing_csv`, `write_machine_note` and the scorecard's `with_steps`, `read_seed_csv`, `rules_line`, `SCORECARD_BASES`. X2 changes inside `julia/src/xxl/scorecard.jl`.

**Tech Stack:** Julia 1.13 (project `julia/`), stdlib `Distributed`, `Test`. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-30-xxl-extinction-risk-design.md`

## Global Constraints

- Branch `xxl-x2-contact`, in the main checkout at `C:\Projects\Sugarscape2026`, so results land in its `results-julia-xxl/`. No merge, no push.
- No change to the rules, to `XXL_DEFAULTS`, or to any other experiment's results. Julia only.
- Bar: below 5% (`0.05`), at 95% confidence, one-sided exact binomial (Clopper–Pearson). No new dependency.
- The test: VI-1, `XXL_DEFAULTS`, seeds 20–79, 2,000 periods, 10 workers. Extinct means population 0 at any period from 1 on.
- No scorecard columns in the extinction runs.
- A failing test is reported, not re-run with more seeds until it passes.
- Comments and docstrings match the surrounding code: terse, plain, 120 columns.
- Commit lines end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The user approved this plan's commit steps on this branch on 2026-10-30, by telling the session to start executing once the plan was reviewed. That approval doesn't cover merging or pushing.
- Run every command with the Bash tool, from the repository root (`C:\Projects\Sugarscape2026`).

## Review Focus

1. A seed file cut short by a crash while writing: the resume must run that seed again, never count it as done.
2. A re-run under the same label with other rules or periods: it must refuse before running or changing anything, and must not delete results.
3. A report rebuilt while seeds are missing: it must say how many are unfinished, and its verdict must rest only on those finished.
4. A seed extinct at t = 1, or at the very last period: no division by zero or NaN in the report, and the right extinction period.
5. An extinct seed in a long run: stepping and metrics with no agents must not throw, and its CSV must read back.

Each has its test in Task 2 or Task 3.

---

### Task 1: X2 is reported only

**Files:**
- Modify: `julia/src/xxl/scorecard.jl` (`Check`, `score`, `threshold_text`, `scorecard_report`, the header comment, the X2 line of the docstring near line 120)
- Modify: `julia/test/test_xxl_scorecard.jl`
- Modify: `docs/superpowers/specs/2026-10-29-xxl-revised-design.md`, `docs/xxl.md`

**Interfaces:**
- Produces: `Check` gains a last field `reported_only::Bool`, with an outer 7-argument constructor setting it `false`.

The spec authorizes these test changes.

- [ ] **Step 1: Write the failing tests in `test_xxl_scorecard.jl`**

Remove the X2 entry from the just-inside/just-outside table (the tuple near line 120). In the all-pass test (line 210), change the assertion to `@test all(c -> c.pass || c.reported_only, checks)`. In the extinct-seed test, take `"X2"` out of the loop at line 276 and add the X2 assertions below. Add:

```julia
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
```

In the extinct-seed test add: `x2 = scd_check(checks, "X2"); @test isnan(x2.value) && x2.reported_only; @test occursin("extinct in seed 1", x2.detail)`. If `scd_data()` needs a different data shape than this, follow its use in the neighbouring tests. `length(checks) == 15` and the report's 15 rows stay, because the row stays.

- [ ] **Step 2: Run to see them fail**

Run: `julia --project=julia -e "using Pkg; Pkg.test(test_args=[\"test_xxl_scorecard.jl\"])"`
Expected: FAIL (`Check` has no field `reported_only`).

- [ ] **Step 3: Implement**

`reported_only` as above. In `score`, X2 is `Check("X2", "Sex", v, -Inf, Inf, false, d, true)`. `threshold_text` returns `"—"` for it. The report's Result column prints `reported only`. The `Passing` line counts `c.pass && !c.reported_only` of `!c.reported_only`. Update the file's header comment and the X2 docstring line to say X2 is reported, with no threshold. Grep for other readers of `.pass` and `length(checks)` in `julia/src`.

- [ ] **Step 4: Run to see them pass**

Same command. Expected: PASS.

- [ ] **Step 5: Update the docs**

- Stage-1 spec: X2's row says reported only, no threshold, and points to the stage-2 spec; the stage table's row 2 reads "Extinction risk" with that spec's path.
- `docs/xxl.md`, section "Stage 1": where checks are listed, X2 has no threshold (the check table's row and the check-list paragraph); a note that the counts of checks passed in the tables were out of 15, that 14 apply from stage 2 on, and that the counts don't change because X2 failed in every setting scored; the Outcome paragraph and the baseline bullet no longer call X2 a failing target.

- [ ] **Step 6: Commit**

```bash
git add julia/src/xxl/scorecard.jl julia/test/test_xxl_scorecard.jl docs/xxl.md docs/superpowers/specs/2026-10-29-xxl-revised-design.md
git commit -m "julia xxl: X2 is reported only"
```

---

### Task 2: The limit, one seed's outcome, and the report

**Files:**
- Create: `julia/src/xxl/extinction.jl`; add `include("xxl/extinction.jl")` after `xxl/scorecard.jl` in `julia/src/Sugarscape.jl`
- Test: `julia/test/test_xxl_extinction.jl` (the suite finds `test_*.jl` by itself)

**Interfaces:**
- Produces:
  - `const EXTINCTION_BAR = 0.05`, `const DECLINE_LINE = 0.9`, `const EXTINCTION_LAST = 200`
  - `extinction_limit(extinct::Int, seeds::Int) -> Float64`
  - `struct SeedOutcome` with fields `seed::Int`, `lowest::Float64`, `lowest_t::Int`, `at_quarters::NTuple{4,Float64}`, `extinct_t::Union{Nothing,Int}`, `births_last::Int`, `deaths_last::Int`, `mean_third::Float64`, `mean_fourth::Float64`, `seconds::Float64`
  - `seed_outcome(M::Matrix{Float64}, header::Vector{String}, seed::Int; seconds::Float64=NaN) -> SeedOutcome`
  - `is_falling(o::SeedOutcome) -> Bool`
  - `extinction_verdict(outcomes::Vector{SeedOutcome}) -> (; verdict::String, extinct::Int, limit::Float64)`
  - `extinction_report(outcomes; label, rules, first_seed, seeds, periods, jobs, wall) -> String`, where `jobs` and `wall` may be `nothing`

Definitions, for a run of `p` periods (`p = M[end, 1]`): `lowest` and `lowest_t` over t ≥ 1 (first period of the lowest); `at_quarters` the population at t = p÷4, p÷2, 3p÷4, p; `extinct_t` the first t ≥ 1 with population 0; `mean_third` the mean over p÷2 < t ≤ 3p÷4; `mean_fourth` over 3p÷4 < t ≤ p. Over the last `w = min(EXTINCTION_LAST, p)` periods, `births_last` is the change in `agents_ever` and `deaths_last` is `births_last` minus the change in `population`. So at p = 2,000 the quarters are 500, 1,000, 1,500, 2,000 and the windows are 1,001–1,500 and 1,501–2,000, as the spec says. `is_falling` is `extinct_t === nothing && mean_fourth < DECLINE_LINE * mean_third`.

`extinction_verdict`: `"PASS"` if `limit < EXTINCTION_BAR`, else `"TOO FEW SEEDS"` if `extinct == 0`, else `"FAIL"`.

`extinction_limit`: the p with P(X ≤ extinct | seeds, p) = 0.05, by bisection; `1.0` when `seeds == 0` or `extinct == seeds`.

The report carries these lines, exact wording fixed so tests and docs can rely on it:

```
# Extinction test: <label>

- Verdict: <verdict>
- Bar: below 5%, at 95% confidence
- Upper limit on the chance of extinction: <limit as percent, 2 decimals>%
- Extinct: <k> of <finished> seeds
- Seeds finished: <finished> of <seeds> (<first>–<last>)
- Periods: <p>
- Rules: `<rules_line(rules)>`
- Falling at the end: <n> of <living> living seeds (fell more than 10%, t = <a>–<b> against t = <c>–<d>)
- Run time: ...
```

Optional lines right after the list: `**Unfinished: <n> seeds have not run. The verdict covers only those finished.**` when `finished < seeds`, and `**Most living seeds were falling at the end: this result says little about longer runs.**` when more than half of the living seeds are falling. Run time gives the sum and the mean of the seeds' `seconds` (skipping NaN; `—` if none has one), plus `wall` and `jobs` when given. Then one table row per seed in seed order: seed, lowest, lowest t, population at the four quarters, extinct at (`—` if none), births and deaths over the last `w`, third- and fourth-quarter means, falling (`yes`/`no`), seconds (`—` for NaN).

- [ ] **Step 1: Write the failing tests in `test_xxl_extinction.jl`**

```julia
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
ext_outcome(pops; seed=0, kw...) = seed_outcome(ext_run(pops; kw...)...; seed=seed)
```

(Adjust `ext_outcome` to `seed_outcome`'s positional `seed`.) Tests:

- `"the limit"`: `extinction_limit(0, 59) < 0.05`; `extinction_limit(0, 58) > 0.05`; `extinction_limit(1, 93) < 0.05`; `extinction_limit(1, 92) > 0.05`; `extinction_limit(0, 60) ≈ 1 - 0.05^(1 / 60)`; `extinction_limit(0, 40) ≈ 1 - 0.05^(1 / 40)`; `extinction_limit(0, 0) == 1`; `extinction_limit(3, 3) == 1`.
- `"one seed: alive"`: `pops = [100, 90, 80, 85, 90, 95, 100, 110, 120]` with `ever = [100, 100, 100, 105, 110, 115, 120, 130, 140]`: `lowest == 80`, `lowest_t == 2`, `at_quarters == (80.0, 90.0, 100.0, 120.0)`, `extinct_t === nothing`, `mean_third == 97.5` (t = 5, 6), `mean_fourth == 115` (t = 7, 8), `births_last == 40`, `deaths_last == 20` (w = 8: births 40, population change +20), `!is_falling`.
- `"one seed: extinct at the first period and at the last"` (Review Focus 4): `pops = [100, 0, 0, 0, 0, 0, 0, 0, 0]` gives `extinct_t == 1`, `lowest == 0`, both means 0, `!is_falling`; `pops = [100, 90, 80, 70, 60, 50, 40, 30, 0]` gives `extinct_t == 8`. Neither outcome's report has `NaN` in it.
- `"falling at exactly the line is not falling"`: third-quarter mean 100 and fourth 90 is not falling; 100 and 89 is.
- `"the verdict"`: 59 alive outcomes give `"PASS"`; 58 give `"TOO FEW SEEDS"`; 59 alive and 1 extinct give `"FAIL"` with `extinct == 1`; 92 alive and 1 extinct give `"PASS"` (the rule is the limit, and 1 of 93 meets it).
- `"the report"`: for 60 alive outcomes starting at seed 20 with `periods=2000`, it contains `"- Verdict: PASS"`, `"- Upper limit on the chance of extinction: 4.87%"`, `"- Extinct: 0 of 60 seeds"`, `"- Seeds finished: 60 of 60 (20–79)"`, `"t = 1001–1500 against t = 1501–2000"`, and has no `"Unfinished"`. With `seeds=60` and 40 outcomes (Review Focus 3) it contains `"- Seeds finished: 40 of 60 (20–79)"`, `"**Unfinished: 20 seeds have not run."` and `"- Verdict: TOO FEW SEEDS"`. All falling gives the `"**Most living seeds"` line. `jobs=nothing, wall=nothing` doesn't throw.

- [ ] **Step 2: Run to see them fail**

Run: `julia --project=julia -e "using Pkg; Pkg.test(test_args=[\"test_xxl_extinction.jl\"])"`
Expected: FAIL (`extinction_limit` not defined).

- [ ] **Step 3: Implement in `extinction.jl`, as defined above**

- [ ] **Step 4: Run to see them pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add julia/src/xxl/extinction.jl julia/src/Sugarscape.jl julia/test/test_xxl_extinction.jl
git commit -m "julia xxl: extinction test: the limit, a seed's outcome, the report"
```

---

### Task 3: The resumable run and its command line

**Files:**
- Modify: `julia/src/xxl/extinction.jl`, `julia/test/test_xxl_extinction.jl`, `julia/README.md`, `julia/src/Sugarscape.jl` (add `remotecall_fetch` to its `Distributed` import, which now lists only `WorkerPool, addprocs, pmap, remotecall_eval, rmprocs`)
- Create: `julia/xxl_extinction.jl` (the same three-line shape as `julia/xxl_scorecard.jl`)

**Interfaces:**
- Consumes: Task 2's functions; `seed_job`, `write_seed_csv`, `write_timing_csv`, `write_machine_note`, `xxl_fingerprint`, `metric_columns`, `to_xxl`, `with_steps`, `read_seed_csv`, `SCORECARD_BASES`, `load_registry`, `find_experiment`, `RESULTS_XXL`.
- Produces:
  - `extinction_name(label, first_seed, seeds, periods) -> "extinction-<label>-s<first>-<seeds>-p<periods>"`
  - `run_extinction(rules::XxlRules; label="defaults", seeds=60, first_seed=20, periods=2000, jobs=10, out=RESULTS_XXL, experiment=nothing, io=stdout) -> (; verdict, extinct, limit)`. `experiment` is for tests; `nothing` means VI-1 from the registry.
  - `rebuild_extinction_report(rules::XxlRules; label, seeds, first_seed, periods, out=RESULTS_XXL, experiment=nothing, jobs=nothing, io=stdout) -> (; verdict, extinct, limit)`: reads the finished seeds in the folder, writes the report, runs nothing. `ArgumentError` if the folder doesn't exist or its fingerprint differs, so a report can't be rewritten under the wrong rules. Only seeds that are done, by the rule below, count as finished.
  - `same_run(a::AbstractString, b::AbstractString; periods::Int) -> Bool`: whether two seed CSVs agree on every column of `a` for t = 0..periods, by column name, compared with `isequal` because some cells are NaN. False if `b` lacks a column of `a`, or either lacks one of those periods.
  - `extinction_main(args::Vector{String}) -> Int`

Behaviour:

- **Files.** Everything goes in `<out>/<name>/`: `fingerprint.txt`, `machine.txt`, `elapsed.txt`, `seed<k>.csv`, `seed<k>.timing.csv`. The report is `<out>/<name>.md`.
- **Fingerprint.** `xxl_fingerprint(exp, rules) * "periods=$periods\n"`. If the folder has a different one, throw `ArgumentError` naming the folder and saying to choose another `--label`, before running or changing anything. `with_steps` keeps the original `steps=` in the text, which is why periods are added.
- **A seed is done** when `seed<k>.csv` has exactly `periods + 2` lines. Every other seed in the range runs.
- **Writing a seed.** A function `extinction_seed!(exp, k, rules, folder) -> SeedOutcome` calls `seed_job(exp, k, false; xxl=rules)`, writes the timing file, writes the CSV to `seed<k>.csv.tmp` with the standard xxl columns (`metric_columns(to_xxl(exp.config, rules))`, no scorecard columns), then `mv(...; force=true)` onto the final name. It runs in the worker.
- **Workers.** With `jobs > 1` and more than one seed to run: `addprocs(min(jobs, length(todo)))`, `remotecall_eval(Main, workers, :(using Sugarscape))`, a `WorkerPool`, and `asyncmap` over the seeds with `ntasks` equal to the worker count, each calling `remotecall_fetch(Sugarscape.extinction_seed!, pool, ...)`; `rmprocs` in a `finally`. Otherwise, run in this process. This is `run_experiment`'s pattern, except that the main process hears about each seed as it ends.
- **Progress.** After each seed, on `io`, flushed: seed, its seconds, seconds per period, lowest and end population, `EXTINCT at t = <t>` if so, `<done> of <total>` done, and about how many hours are left (mean seconds per finished seed × seeds left ÷ workers).
- **Wall time adds up across a resume.** `elapsed.txt` in the folder holds the seconds spent running so far. Each invocation reads it at the start and rewrites it (old value + time since this invocation began) after each seed, so a crash loses at most the time since the last finished seed, and a re-run with nothing to do adds almost nothing. The report's `wall` is this file's value, in a run or a rebuild, and is `nothing` if the file is absent.
- **The end.** After the last seed, outcomes are read back from the CSVs and timing files, through the same code as `rebuild_extinction_report`. It writes the report, prints it to `io`, and returns the verdict. A `FAIL` is a result, not an error: exit code 0.
- **Command line.** `--rules v1|defaults` (default `defaults`), `--label` (default: the `--rules` value, with no `--set` here), `--seeds` (60), `--first-seed` (20), `--periods` (2000), `--jobs` (10), `--out`, and `--report-only` (no value; calls `rebuild_extinction_report`). Usage errors print a usage line and return 2: an unknown flag, a missing value, `--seeds` or `--jobs` below 1, `--first-seed` below 0, `--periods` below 4, `--report-only` with no folder.

- [ ] **Step 1: Write the failing tests**

Use TEST-tiny (50 × 50, 20 agents), with `XXL_V1` so no generated map is needed. A helper makes a copy with a changed config, as `sc_cut` in `test_xxl_scorecard_metrics.jl` does:

```julia
const EXT_REG = load_registry()
const EXT_TINY = find_experiment(EXT_REG, "TEST-tiny")
function ext_exp(; kw...)
    e = EXT_TINY
    return Experiment(
        e.id, e.title, e.rules, e.steps, e.seeds, replace_config(e.config; kw...),
        e.fingerprint, e.xl_config, e.xl_fingerprint,
    )
end
const EXT_DOOMED = ext_exp(; max_age=(2, 2))  # all dead of old age within a few periods
const EXT_FED = ext_exp(; metabolism=(1, 1), endowment=(50, 50))  # all alive throughout
```

If `to_xxl` rescales or refuses these values, use others that keep the two meanings: every seed extinct within the run, and every seed alive at its end. Tests, with `out = mktempdir()`, `io=devnull`, `jobs=1`, `periods=12`, `seeds=2`, `first_seed=5` unless named:

- `"an extinct world fails, and its CSV reads back"` (Review Focus 5): with `EXT_DOOMED`, `verdict == "FAIL"`, `extinct == 2`; `read_seed_csv` of `seed5.csv` has 13 rows; the report says `"- Extinct: 2 of 2 seeds"`.
- `"VI-1 runs on with nobody left"` (Review Focus 5, every rule at once): the registry's VI-1 with `max_age=(2, 2)` in its config, `XXL_DEFAULTS`, `seeds=1`, `periods=10`: no throw, `extinct == 1`, and `read_seed_csv` of the seed file has 11 rows.
- `"a fed world has too few seeds"`: with `EXT_FED`, `verdict == "TOO FEW SEEDS"`, `extinct == 0`, and the folder holds `elapsed.txt`, `fingerprint.txt`, `machine.txt`, `seed5.csv`, `seed6.csv`, `seed5.timing.csv`, `seed6.timing.csv`, nothing else; the header has no `n_fertile`.
- `"a re-run skips finished seeds"`: after a full run, record `mtime` of both CSVs, the report text and `elapsed.txt`'s value; re-run; `mtime`s unchanged, the seed rows of the report equal, and `elapsed.txt` no smaller.
- `"a seed cut short runs again"` (Review Focus 1): truncate `seed6.csv` to its first 3 lines, and leave a stray `seed5.csv.tmp`; re-run; `seed6.csv` has 14 lines and equals the original bytes; `seed5.csv`'s `mtime` is unchanged.
- `"other rules or periods are refused"` (Review Focus 2): after a run with `XXL_V1`, the same label with `replace_rules(XXL_V1; travel_cost=0.05)` throws `ArgumentError` and leaves the CSVs' `mtime`s unchanged. Hand-edit the `periods=` line of `fingerprint.txt` and re-run with the original rules: it also throws.
- `"the report can be rebuilt"`: delete the `.md`; `rebuild_extinction_report` restores it with the same verdict line. With `seed6.csv` deleted it says `"- Seeds finished: 1 of 2"`. On an absent folder it throws `ArgumentError`. With other rules it throws `ArgumentError` and leaves the `.md` unchanged. With `seed6.csv` cut to 3 lines it says `"- Seeds finished: 1 of 2"` (Review Focus 3).
- `"two workers give the same seeds"`: `jobs=2` into another folder; `seed5.csv` equals the `jobs=1` run's bytes.
- `"the runs are VI-1's runs"`: `run_extinction(XXL_DEFAULTS; label="vi", seeds=1, first_seed=20, periods=10, jobs=1, out=out, io=devnull)`, and `run_experiment(with_steps(find_experiment(EXT_REG, "VI-1"), 10); seeds=1, first_seed=20, out=out2, xxl=XXL_DEFAULTS, scorecard=true)`; then `same_run(a, b; periods=10)` is true. `same_run` on a CSV whose population was edited is false, and so is `same_run` against a CSV lacking a column or with too few rows.
- `"the command line"`: `extinction_main(["--seeds", "0"]) == 2`; `["--jobs", "0"]`, `["--periods", "3"]`, `["--first-seed", "-1"]`, `["--nope"]`, `["--rules", "x"]` return 2; `["--report-only", "--out", mktempdir()]` returns 2.

- [ ] **Step 2: Run to see them fail.** Same command as Task 2. Expected: FAIL (`run_extinction` not defined).

- [ ] **Step 3: Implement, as described above**

- [ ] **Step 4: Run to see them pass.** Same command. Expected: PASS.

- [ ] **Step 5: Run the smoke run through the script**

Run: `julia --project=julia julia/xxl_extinction.jl --seeds 2 --first-seed 20 --periods 20 --jobs 2 --out <scratch folder>`
Expected: exit 0; a report with `- Verdict: TOO FEW SEEDS` and `- Extinct: 0 of 2 seeds`.

- [ ] **Step 6: Add the commands and the time estimate to `julia/README.md`, beside the scorecard's commands.** Then run the full suite: `julia --project=julia -e "using Pkg; Pkg.test()"`. Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add julia/src/Sugarscape.jl julia/src/xxl/extinction.jl julia/xxl_extinction.jl julia/test/test_xxl_extinction.jl julia/README.md
git commit -m "julia xxl: the extinction test's resumable run and command line"
```

---

### Task 4: The long run and its evidence

**This task runs after the whole-branch review**, so a defect found there doesn't waste the run. The controller does it, not an implementer subagent.

**Files:** Modify `docs/xxl.md`. Results go in `results-julia-xxl/` (git-ignored).

- [ ] **Step 1: The seed-20 gate**

Run this on the final commit, after the whole-branch review's fixes: the code hash makes the folder specific to that commit.

Run: `julia --project=julia julia/xxl_extinction.jl --seeds 1 --first-seed 20 --periods 500 --jobs 1 --label check`
Then: `julia --project=julia -e "using Sugarscape; exit(Sugarscape.same_run(\"results-julia-xxl/extinction-check-s20-1-p500/seed20.csv\", \"results-julia-xxl/scorecard-defaults-x2sight-s20-20/VI-1/seed20.csv\"; periods=500) ? 0 : 1)"`
Expected: exit 0. A failure stops here: the long run does not start, and the user hears why.

- [ ] **Step 2: Launch**

Ask the host to keep the machine awake, then run in the background:
`julia --project=julia julia/xxl_extinction.jl --rules defaults --seeds 60 --first-seed 20 --periods 2000 --jobs 10`, with output to a log file.
Expected: progress lines per seed. Note the real seconds per period once the first batch finishes, and watch free memory through the first batch: the fix to `kill!` should hold each worker well under 1 GB past t = 500. If free memory runs low, stop and resume with fewer workers, and tell the user. If it stops with a non-zero exit, the same command resumes it; stop for good if the same seed fails twice. Nothing under `julia/src` may change until the run ends, and the checkout stays on this commit.

- [ ] **Step 3: Read the report**

`results-julia-xxl/extinction-defaults-s20-60-p2000.md`. Check that it has 60 seeds, and read the falling line.

- [ ] **Step 4: Write the result into `docs/xxl.md`**

A new section after "Stage 1", "Stage 2: the chance of extinction": the bar and whose it is, the test, the verdict, the limit, the lowest population across seeds, the end populations, the falling count, the real run time. X2's new reading goes here too: 0.16 and survival anyway. On a pass, the next stage is the economy (X8). On a fail, say what the extinct seeds did, and stop at that: the rules don't change here.

- [ ] **Step 5: Commit**

```bash
git add docs/xxl.md
git commit -m "docs: stage 2, the chance of extinction under the xxl defaults"
```
