# Revised xxl (scorecard and stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a scorecard that measures whether the xxl simulation is well-functioning, and stage 1's four survival
switches, then tune them so the scorecard's survival checks pass.

**Architecture:** The first xxl rules are frozen as `XXL_V1`, and a golden-run test pins them bit for bit. The new
switches are `XxlRules` fields whose book settings change nothing; `rules_line` prints them only when they are on,
so every existing fingerprint stays the same. The scorecard is a library file plus a script. It records opt-in
metric columns through the runner, runs II-4, IV-A3 and VI-1 over many seeds, and scores them against the spec's
checks.

**Tech Stack:** Julia 1.13 (`julia/`, module `Sugarscape`, standard library only), the existing runner (`Distributed`
workers via `--jobs`).

**Spec:** `docs/superpowers/specs/2026-10-29-xxl-revised-design.md`

## Global Constraints

- Julia only. Nothing under `sugarscape/`, `experiments/`, `viewer/`, `tests/` or `julia/bridge/` changes, and
  `julia/registry.toml` is not regenerated or edited.
- The book rules, xl and every non-xxl result stay exactly as they are; `results-julia/` and `results-julia-xl/` stay
  current.
- Existing tests pass unchanged, with one exception (user decision, 2026-10-29): the xxl tests that pin the old
  defaults are repointed at `XXL_V1`, keeping their assertions exactly. These are `test_xxl_runner.jl` (the rules
  line, the `--xxl` fingerprint, the experiment table) and `test_xxl_config.jl` (the default fields and map). No
  assertion is weakened. New tests go in new files `julia/test/test_xxl_*.jl`.
- With every switch at its book setting, xxl still reduces exactly to xl (`test_xxl_reduction.jl`, unchanged).
- `XXL_V1` runs are bit-identical to the runs before this plan (the golden test, Task 1). The 16 `XXL-…`
  experiments are defined from `XXL_V1`, so their rules lines, fingerprints and committed results are unchanged.
- Every new draw, or reordered draw, happens only when its switch is on.
- No hand-placed stabilisers (spec, anti-goals).
- Book settings and candidates, exactly as in the spec:

  | Field | Book | Candidate |
  |---|---|---|
  | `max_metabolism` | `nothing` | 4 |
  | `founder_placement` | `"random"` | `"viable"` |
  | `free_step` | 0.0 | 1.5 |
  | `founder_ages` | `"book"` | `"young"` |
  | `landscape` | `"xl"` | `"generated"` |

- Scorecard thresholds, exactly as in the spec: S1 no VI-1 seed reaches 0; S2 every VI-1 seed's minimum ≥ 10% of
  founders; S3 VI-1 end ≥ 50% of xl's; S4 II-4 end ≥ 90% of xl's; S5 IV-A3 end ≥ 90% of xl's; X1 births ÷ deaths
  over VI-1's last 200 periods in 0.9–1.1; X2 ≥ 50% of fertile agents with a mate in reach at VI-1's trough; X3 both
  tribes ≥ 5% at t = 200 in ≥ 80% of seeds; X4 tag flips per agent per period > 0 in every VI-1 period; X5 ≥ 50% of
  agents traded in the last 10 periods at VI-1's end; X6 VI-1 end price sd ≤ 1.5 × xl's; X7 loans outstanding > 0
  in every period after t = 100 in every seed; X8 ≤ 20% of loans voided by a death; X9 a disease circulates at
  t = 500 in ≥ 90% of seeds; X10 the end share sick in 1–20%. "End" is the mean over the last 100 periods.
- Rounding a real coordinate to a site is `round(Int, v)`. Torus distance is d = √(dx² + dy²) with the short way
  round.
- Commit messages end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Format with
  `julia --project=julia/tools julia/tools/format.jl` before committing, and keep LF line endings (the Python side's
  hygiene test checks them).

## Review Focus

1. **No viable site left.** With more founders of a metabolism pair than empty viable sites, founders fall back to
   a random empty site, the fallback is counted, and nothing throws. Test: `test_xxl_placement.jl` "fallback when
   viable sites run out".
2. **The free step's boundary.** A target at d = √2 is free, d = 1.5 is free, d = 2 is charged in full. The
   valuation agrees with the charge, and the starve-on-the-way cutoff uses the same cost. Test:
   `test_xxl_free_step.jl` "boundary".
3. **`XXL_V1` unchanged.** The new code leaves the first rules' runs bit-identical, the combat path included. Test:
   `test_xxl_v1_golden.jl`.
4. **An extinct seed in the scorecard.** A seed whose population reaches 0 gives NaN metrics where they don't apply.
   The checks still compute: S1 fails, and the others report without throwing. Test: `test_xxl_scorecard.jl`
   "extinct seed".
5. **Seed offsets.** `--first-seed 20 --seeds 20` runs seed indices 20–39 (seed `cfg.seed + k`), writes
   `seed20.csv` to `seed39.csv`, and scores against xl runs of the same indices. Test: `test_xxl_scorecard.jl`
   "first seed".

## Commands

- One test file group: `julia --project=julia -e "using Pkg; Pkg.test(test_args=[\"xxl_placement\"])"`.
- The whole Julia suite: `julia --project=julia -e "using Pkg; Pkg.test()"`. The baseline is 8673 passing.
- The Python side, from `julia/`: `C:/Projects/Sugarscape2026/.venv/Scripts/python -m pytest -q`. The baseline is 30
  passed.

---

### Task 1: Freeze the first rules as `XXL_V1`, with a golden-run guard

**Files:**
- Create: `julia/test/fixtures/make_xxl_v1_golden.jl`, `julia/test/fixtures/xxl-v1/{II-4,IV-A3,VI-1,III-9}.csv`,
  `julia/test/test_xxl_v1_golden.jl`
- Modify: `julia/src/xxl/types.jl` (add `XXL_V1`), `julia/src/xxl/experiments.jl` (the experiment table uses
  `XXL_V1`), `julia/src/Sugarscape.jl` (export `XXL_V1`)
- Modify, as approved (assertions kept exactly; only the rules they are checked against change):
  - `julia/test/test_xxl_config.jl`:
    - lines 6–8: `XXL_DEFAULTS.…` becomes `XXL_V1.…`;
    - lines 12, 15, 19 and 47: every `to_xxl(cfg)` that relies on the implicit default rules becomes
      `to_xxl(cfg, XXL_V1)`;
    - line 13: `replace_rules(XXL_DEFAULTS; …)` becomes `replace_rules(XXL_V1; …)`;
    - and any other implicit-default call there whose assertion pins a first-rules value.
  - `julia/test/test_xxl_runner.jl`:
    - lines 29–31: the `startswith(fp, "julia\nxxl vision_shape=… travel_cost=0.1 ")` assertion keeps its literal,
      but its subject becomes `Sugarscape.xxl_fingerprint(XTINY, XXL_V1)` instead of `main`'s output;
    - line 32: `fp == xxl_fingerprint(XTINY, XXL_DEFAULTS)` stays exactly as it is, since it checks that `--xxl`
      runs *the defaults*, whatever they are;
    - lines 38–41 and 45: `XXL_DEFAULTS` becomes `XXL_V1`;
    - lines 118–128: the experiment table's `XXL_DEFAULTS` becomes `XXL_V1`.

**Interfaces:**
- Produces: `const XXL_V1::XxlRules`, with the same values as today's `XXL_DEFAULTS`. `XXL_DEFAULTS` stays equal to
  `XXL_V1` until Task 9.

- [ ] **Step 1: Generate the golden fixtures on the unchanged code.** Do this first, before any source edit.
  `make_xxl_v1_golden.jl` runs seven configurations, seed index 0, for 25 periods each:
  - II-4, IV-A3, VI-1 and III-9 under `to_xxl(exp.config, XXL_DEFAULTS)`, which today equals the first rules;
  - and three of the experiment table's rule sets on their bases, which take other code paths: `XXL-vision` (round
    vision, no speed), `XXL-speed/c0` (speed without a travel cost) and `XXL-terrain/IV-A3` (the generated map).

  It writes every row of `collect_metrics` (with `t`) through
  `Sugarscape.write_seed_csv(path, rows; columns=metric_columns(cfg))`, into
  `julia/test/fixtures/xxl-v1/<name>.csv`, the experiment id with `/` replaced by `_`. Run it:
  `julia --project=julia julia/test/fixtures/make_xxl_v1_golden.jl`.
  Expected: seven CSVs, 26 data rows each, LF line endings.
- [ ] **Step 2: Write the golden test.** `test_xxl_v1_golden.jl` reruns the seven the same way, with `XXL_V1`, or the
  table's rules, which Step 3 defines from `XXL_V1`. For each, it asserts the CSV it would write is byte-identical
  to the fixture: write it to a temporary file and compare the strings. The test reads `XXL_V1`, so it fails until
  Step 3 defines it.
- [ ] **Step 3: Add `XXL_V1`.** In `types.jl`, write `XXL_V1` out as the current literal, and set
  `XXL_DEFAULTS = XXL_V1` for now. Export `XXL_V1`. In `experiments.jl`, replace every `XXL_DEFAULTS` in
  `XXL_EXPERIMENTS` with `XXL_V1`. Change `make_xxl_v1_golden.jl` to use `XXL_V1` too, so that regenerating it later
  still pins the first rules. Repoint the two test files as listed under Files.
- [ ] **Step 4: Run the tests.** `test_args=["xxl"]`. Expected: all pass, the golden test included.
- [ ] **Step 5: Commit** "julia xxl: freeze the first rules as XXL_V1, with a golden-run guard".

### Task 2: The stage-1 switches: fields, validation and the rules line

**Files:**
- Modify: `julia/src/xxl/types.jl`, `julia/src/xxl/transform.jl` (`xxl_on`), `julia/src/config.jl` (`validate_xxl`),
  `julia/src/xxl/experiments.jl` (`rules_line`)
- Test: `julia/test/test_xxl_stage1_config.jl`

**Interfaces:**
- Produces:
  - New fields at the end of `XxlRules`, with book defaults: `max_metabolism::Union{Nothing,Int} = nothing`,
    `founder_placement::String = "random"`, `free_step::Float64 = 0.0`, `founder_ages::String = "book"`.
  - `const FOUNDER_PLACEMENTS = ("random", "viable")` and `const XXL_FOUNDER_AGES = ("book", "young")`.
  - `xxl_on` features `:metabolism_cap`, `:viable`, `:free_step` and `:young`, each true when its field is off its
    book setting.

- [ ] **Step 1: Write the failing tests.**
  - `rules_line(XXL_V1)` equals today's exact string. Copy the string from `test_xxl_runner.jl`, with
    `landscape="xl"` at its end.
  - `rules_line(replace_rules(XXL_V1; free_step=1.5))` equals that string followed by ` free_step=1.5`.
  - `XxlRules()` has all four new fields at their book values.
  - Validation refuses each of these with an `ArgumentError`:
    - `max_metabolism = 0`;
    - `max_metabolism` below the experiment's lowest sugar metabolism, or with spice its lowest spice metabolism;
    - `founder_placement = "near"`;
    - `free_step = -1`;
    - `free_step > 0` without `speed`;
    - `founder_ages = "old"`.
  - `to_xxl` treats `founder_ages = "young"` as `"book"` on an experiment without sex or without finite lives, as
    it already does for `season_gradient` without seasons (`transform.jl:12`). So
    `to_xxl(II-4, replace_rules(XXL_V1; founder_ages="young")).xxl.founder_ages == "book"`, and its rules line and
    fingerprint are `XXL_V1`'s. On VI-1, `"young"` is kept.
- [ ] **Step 2: Run** `test_args=["xxl_stage1_config"]`. Expected: FAIL, because the fields don't exist.
- [ ] **Step 3: Implement.** `rules_line` prints the original nine fields always, then each new field only when it
  is off its book setting, in field order. This keeps every `XXL_V1` fingerprint unchanged. `validate_xxl` checks
  only that `founder_ages` is one of `XXL_FOUNDER_AGES`; `to_xxl` does the reset above.
- [ ] **Step 4: Run** `test_args=["xxl"]`. Expected: all pass. The golden and runner tests are unchanged because
  `XXL_V1`'s line is unchanged.
- [ ] **Step 5: Commit** "julia xxl: the stage-1 switches as XxlRules fields with book settings".

### Task 3: `max_metabolism`

**Files:**
- Modify: `julia/src/model.jl` (`spawn_at!`, `spawn_chapter_draws!`), `julia/src/xxl/transform.jl` (a helper)
- Test: `julia/test/test_xxl_metabolism_cap.jl`

**Interfaces:**
- Produces: `capped_range(cfg::Config, r::Tuple{Int,Int}) -> Tuple{Int,Int}`. With `:metabolism_cap` on it returns
  `(r[1], min(r[2], cfg.xxl.max_metabolism))`; otherwise it returns `r`.
- Consumes: Task 2's fields.

- [ ] **Step 1: Write the failing tests.**
  - VI-1 under `replace_rules(XXL_V1; max_metabolism=4)` gives every founder a sugar and a spice metabolism ≤ 4,
    and some founder has each of 1–4.
  - Over 20 periods of VI-1, every child also has metabolisms ≤ 4.
  - IV-12/a80, which has metabolism (1, 5), spice and replacement: over 20 periods, every rule-R replacement has
    metabolisms ≤ 4.
  - `capped_range` returns its argument unchanged with the cap off, and `(1, 4)` for `(1, 5)` with M = 4.
  - The narrower range may consume a different number of raw random draws (`rand(rng, a:b)` uses rejection
    sampling). That is allowed, because the change is gated, and no test relies on the count. The golden test
    guards `XXL_V1`.
- [ ] **Step 2: Run** `test_args=["xxl_metabolism_cap"]`. Expected: FAIL.
- [ ] **Step 3: Implement.** `spawn_at!` draws `metabolism` from `capped_range(cfg, cfg.metabolism)`, and
  `spawn_chapter_draws!` draws `spice_metabolism` from `capped_range(cfg, cfg.spice_metabolism)`. Children inherit
  their metabolisms through rule S unchanged.
- [ ] **Step 4: Run** `test_args=["xxl"]`. Expected: all pass.
- [ ] **Step 5: Commit** "julia xxl: cap the metabolism drawn for new agents".

### Task 4: Viable founder placement

**Files:**
- Create: `julia/src/xxl/placement.jl`, included after `model.jl`
- Modify `julia/src/model.jl`:
  - `place_initial_population!`, `place_blocks!` and `spawn_random_agent!` dispatch to `spawn_viable!` when
    `:viable` is on;
  - split `new_agent!` into building an agent and placing it, keeping `new_agent!`'s behaviour and draws exactly;
  - two `Model` fields: `viable_fallbacks::Int`, and a lazily built cache of site lists per metabolism pair for the
    whole grid, which rule-R replacements use (blocks filter their own lists).
- Test: `julia/test/test_xxl_placement.jl`

**Interfaces:**
- Produces:
  - `spawn_viable!(m::Model, sites::AbstractVector{Tuple{Int,Int}}; tribe::Symbol=:none) -> Agent`. It draws the
    new agent's traits in exactly `spawn_at!`'s order (vision, metabolism, endowment, max age, then
    `spawn_chapter_draws!`, speed last), without placing it. It then draws its site uniformly among the empty sites
    of `sites` where sugar capacity ≥ its metabolism and, with spice, spice capacity ≥ its spice metabolism. If no
    such site is empty, it draws uniformly among all empty sites of `sites` and increments `m.viable_fallbacks`.
  - `viable(m::Model, a::Agent, x::Int, y::Int) -> Bool`.
- Consumes: Task 3's capped draws.

- [ ] **Step 1: Write the failing tests.**
  Viable sites can run out for some metabolism pairs; on the xl map the pairs (3, 4), (4, 3) and (4, 4) have none.
  So each test asserts: every founder is viable *or* was a counted fallback, and `viable_fallbacks` equals the
  number of founders placed when no viable empty site was left in their candidate sites.
  - II-4 under `replace_rules(XXL_V1; founder_placement="viable")` meets that assertion. Every founder of
    metabolism 1–3 is viable, since capacities 1–3 are plentiful on the xl map.
  - VI-1 under `founder_placement="viable"` with `max_metabolism=4, landscape="generated"` meets it on both goods.
    The test also prints the fallback count, as a figure for the docs.
  - III-9 with viable placement: each tribe's founders are inside their own block, and viable unless counted as a
    fallback.
  - "fallback when viable sites run out": a tiny world (`tiny_model` from `helpers.jl`) where only 3 sites have
    capacity 4, with 10 founders of metabolism 4. All 10 are placed, 7 by fallback, and `viable_fallbacks == 7`.
  - Uniformity: a 1 × 4 strip of viable sites inside land that is not viable, with 1 founder, repeated over many
    seeds. Each strip site is chosen about a quarter of the time (a χ² test at p = 0.001), and no other site is ever
    chosen.
  - A rule-R replacement under viable placement stands on a viable site, or is counted as a fallback.
- [ ] **Step 2: Run** `test_args=["xxl_placement"]`. Expected: FAIL.
- [ ] **Step 3: Implement.** With `:viable` off, every function runs exactly as before. Make the site draw efficient,
  for example by rejection sampling from a precomputed list of sites per metabolism pair. Fall back to an exact
  scan after a bounded number of misses. The draw must stay uniform over the eligible empty sites.
- [ ] **Step 4: Run** `test_args=["xxl"]`. Expected: all pass, the golden test included.
- [ ] **Step 5: Commit** "julia xxl: viable founder placement".

### Task 5: The free step

**Files:**
- Modify: `julia/src/xxl/speed.jl` (`net_value` and `speed_move!`), `julia/src/xxl/memory.jl` (`rank_pool!`),
  `julia/src/xxl/combat.jl` (`xxl_combat_move!`), `julia/src/rules/movement.jl` (`metabolize!`'s xxl line),
  `julia/src/agent.jl` (a field `travel_free::Bool`, false at birth)
- Test: `julia/test/test_xxl_free_step.jl`

**Interfaces:**
- Produces:
  - `trip_cost(c::Float64, free::Float64, d::Float64) -> Float64 = d <= free ? 0.0 : c * d`.
  - `net_value(a, sw, two, c, free, d, sugar, spice)`, with the travel term and the starve-on-the-way cutoff both
    using `trip_cost`. The model-level `net_value(m, a, x, y, d, sugar, spice)` keeps its signature.
  - `a.travel_free`: set by `speed_move!` and `xxl_combat_move!` to `best_d <= free_step` for the period's target.
    `metabolize!` charges `travel_cost * (a.travel_free ? 0.0 : a.moved_dist)`.
- Consumes: Task 2's `free_step`.

- [ ] **Step 1: Write the failing tests.**
  - "boundary", with `c = 0.1` and `free = 1.5` throughout:
    - `trip_cost` is 0 at d = √2 and at d = 1.5, and 0.2 at d = 2.0;
    - `net_value` at d = √2 equals its value at c = 0, and at d = 2 it is 0.2 lower (one commodity, speed 2, so T = 1);
    - the starve-on-the-way cutoff, for an agent holding 0.15 sugar with speed 1 and metabolism 0: d = 2 gives
      `-Inf`, and d = √2 is finite;
    - a `speed_move!` then `metabolize!` on `tiny_model`: a diagonal step to a full site charges 0, and a 2-site step
      charges 0.2.
  - An agent at metabolism 2 on capacity-2 land that steps to a full Moore neighbour each period keeps a constant
    holding under `free_step = 1.5`, and loses 0.1 per period under `free_step = 0`. Use `tiny_model` with
    `travel_cost = 0.1` and speed (1, 1).
  - A trip to a target 3 sites away at speed 1 is charged 0.1, 0.1 and then 0. By the third period the target is
    1 away, within the free step.
- [ ] **Step 2: Run** `test_args=["xxl_free_step"]`. Expected: FAIL.
- [ ] **Step 3: Implement.** Pass `free_step` to every `net_value` call: `speed_move!`'s candidates and remembered
  sites, `rank_pool!`, and `xxl_combat_move!`'s own site, candidates and remembered sites.
- [ ] **Step 4: Run** `test_args=["xxl"]`, then the whole suite including `test_hot_paths`. Expected: all pass.
- [ ] **Step 5: Commit** "julia xxl: a free step to targets within free_step".

### Task 6: Young founders

**Files:**
- Modify: `julia/src/model.jl` (the founder-age loop in `Model(...)`)
- Test: `julia/test/test_xxl_young.jl`

**Interfaces:**
- Produces: with `:young` on, each founder's age is `rand(m.rng, 0:Int(a.fertility_start))`, drawn in the same loop
  and position as the book's `rand(m.rng, 0:(Int(a.max_age) - 1))`. The raw draw count may differ, which is allowed
  because the change is gated.

- [ ] **Step 1: Write the failing tests.**
  - VI-1 under `replace_rules(XXL_V1; founder_ages="young")`: every founder's age is ≤ its fertility start.
  - The ages span 0 up to the maximum fertility start (12–15 in VI-1).
  - II-4 under `"young"` runs: `to_xxl` reset it to `"book"`, per Task 2.
  - The golden test guards the `"book"` path.
- [ ] **Step 2: Run** `test_args=["xxl_young"]`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `test_args=["xxl"]`. Expected: all pass.
- [ ] **Step 5: Commit** "julia xxl: young founders".

### Task 7: Scorecard metrics, opt-in, through the runner

**Files:**
- Create: `julia/src/xxl/scorecard_metrics.jl`, included after `xxl/metrics.jl`
- Modify:
  - `julia/src/runner.jl`:
    - `run_experiment` gains `first_seed::Int=0` and `scorecard::Bool=false`;
    - `timed_seed` and `seed_job` gain `scorecard::Bool=false` only;
    - `first_seed` stays in `run_experiment`: it maps over `first_seed:(first_seed + seeds - 1)` in both the `pmap`
      and the serial branch, and writes `seed$(k).csv` with the true index, since `timed_seed` already takes `k`;
    - `seed_job` passes `scorecard` to `run_seed` only when it is true, as it passes `xxl` today
      (`runner.jl:119-123`), so existing stand-ins such as `failing(exp, k; xl=false)` keep working;
    - `run_experiment` refuses `scorecard=true` without `xxl` rules;
    - with `first_seed` set, it deletes only the seed files it is about to rewrite (see Task 8's folder names);
  - `julia/src/xxl/combat.jl`: `xxl_combat_move!` records each victim's id in `m.killed::Set{Int}`, emptied at the
    start of `step!`;
  - `julia/src/model.jl`: the field, and the emptying.
- Test: `julia/test/test_xxl_scorecard_metrics.jl`

**Interfaces:**
- Produces:
  - `const SCORECARD_COLUMNS = ["deaths_sugar", "deaths_spice", "deaths_old_age", "deaths_killed", "births",
    "n_fertile", "n_fertile_with_mate", "tag_flips_per_agent", "share_traded_10", "loans_started",
    "loans_rolled", "loans_repaid", "loans_voided", "viable_fallbacks"]`.
  - `mutable struct ScorecardTracker`, with the previous period's tags by agent id, each agent's last trade
    period, and the previous period's loans by object identity.
  - `ScorecardTracker(m::Model)`.
  - `scorecard_metrics!(out, m::Model, tr::ScorecardTracker)`.
- The meanings, per period:
  - **Deaths:** classify each of `m.dead_this_step`, first match wins.
    - Killed: its id is in `m.killed`.
    - Old age: `age >= max_age`.
    - Sugar: `sugar <= 0`; starving of both goods counts as sugar.
    - Spice: otherwise.
    - Kills under the book's combat move, when neither disc nor speed is on, are not recorded. The docstring says so.
  - **Births:** new agent ids this period, less `length(m.dead_this_step)` when `cfg.replacement`.
  - **Fertility:** `n_fertile` counts `is_fertile(a, cfg.fertility_threshold)`. `n_fertile_with_mate` counts those
    with a fertile agent of the other sex in `neighbors_of(m, a)`.
  - **Tag flips:** the sum of `count_ones(old ⊻ new)` over agents alive in both periods, divided by the population.
  - **Trade:** `share_traded_10` is the living agents with a trade in periods t − 9 … t, over the population, from
    `m.trade_log`'s `a` and `b`.
  - **Loans,** tracked by object identity between periods:
    - A loan that has left the book is `loans_voided` iff its borrower or its lender is dead. This is exact, because
      no death happens after `settle_loans!` in a period.
    - Any other loan that left was settled. It is `loans_rolled` if a new loan between the same lender and borrower
      appeared this period, since `settle_loans!` rolls an unpaid rest into a new `Loan` (`credit.jl:119`).
      Otherwise it is `loans_repaid`.
    - A new loan that is a rollover's continuation is not counted in `loans_started`, so `loans_started` counts
      loans made by `seek_credit!` only.
    - Each chain of a loan and its rollovers therefore ends exactly once, as repaid or voided. X8 is
      voided ÷ (voided + repaid).
  - **Placement:** `viable_fallbacks` is `m.viable_fallbacks`, cumulative.
  - **Without the rules:** a column whose rule is off (no sex, no culture, no trade, no credit) is NaN.
  - **The t = 0 row:** `tag_flips_per_agent` and `share_traded_10` are NaN (there is no previous period); births,
    deaths and loan counts are 0. Every check over "every period" skips t = 0.
  - `metric_columns(cfg; scorecard=false)` appends `SCORECARD_COLUMNS` when `scorecard` is true. Ordinary `--xxl`
    output is unchanged.
  - `run_experiment(...; first_seed=K)` runs seed indices K … K + seeds − 1, writing `seed<k>.csv` with the true
    index. The defaults reproduce today's behaviour.
- Consumes: Task 4's `viable_fallbacks`.

- [ ] **Step 1: Write the failing tests.**
  - Each column on a hand-built `tiny_model`:
    - deaths by cause in a world where one agent starves of sugar, one of spice, and one reaches its maximum age;
    - a combat kill under the xxl combat move;
    - births and loans matched against the existing logs over a 30-period VI-1 run (`births` equals the growth of
      `agents_ever`);
    - a tag flip forced by `culture_transmit!`;
    - a trader dropping out of `share_traded_10` after 10 quiet periods.
    Also cover a rollover followed by the borrower's death: one chain, counted once as voided.
  - `run_experiment` with `scorecard=true` writes `t`, the 54 xxl columns and the 14 scorecard columns. Its first 55
    columns equal, value for value, those of the same run with `scorecard=false`, which writes today's header.
  - `scorecard=true` without `xxl` throws an `ArgumentError`.
  - `first_seed=3, seeds=2` writes `seed3.csv` and `seed4.csv` with `cfg.seed + 3` and `cfg.seed + 4`, serially and
    with `jobs=2`.
- [ ] **Step 2: Run** `test_args=["xxl_scorecard_metrics"]`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the whole suite. Expected: all pass, `test_runner`, the golden test and `test_hot_paths`
  included.
- [ ] **Step 5: Commit** "julia xxl: scorecard metrics, opt-in through the runner".

### Task 8: The scorecard: checks, script and report

**Files:**
- Create: `julia/src/xxl/scorecard.jl`, included after `runner.jl`; `julia/xxl_scorecard.jl` (the script). Its
  output lands under `results-julia-xxl/`, which `.gitignore` already covers.
- Test: `julia/test/test_xxl_scorecard.jl`

**Interfaces:**
- Produces:
  - `const SCORECARD_EXPERIMENTS = ["II-4", "IV-A3", "VI-1"]`.
  - `struct Check`, with fields `id::String`, `aspect::String`, `value::Float64`, `low::Float64`, `high::Float64`,
    `pass::Bool` and `detail::String` (per-seed range, or the failing seeds).
  - `score(xxl_rows::Dict{String,Vector{Matrix{Float64}}}, xl_rows::Dict{String,Vector{Matrix{Float64}}},
    columns::Dict{String,Vector{String}}) -> Vector{Check}`, computing S1–S5 and X1–X10 exactly as the Global
    Constraints define them.
  - `run_scorecard(rules::XxlRules; label::String, seeds=20, first_seed=0, jobs=1, out="results-julia-xxl",
    steps_override::Union{Nothing,Int}=nothing) -> Vector{Check}`. `steps_override` shortens every experiment, for
    tests only.
  - **Folder and report names carry the seed range**, so that a confirmation run never overwrites the choosing run
    and either can be re-scored without re-running:
    - xxl runs go to `<out>/scorecard-<label>-s<first>-<seeds>/<id>/`;
    - xl runs go to `<out>/scorecard-xl-s<first>-<seeds>/<id>/`;
    - the report is `<out>/scorecard-<label>-s<first>-<seeds>.md`;
    - an xl folder is reused only if it holds those seed files with a current fingerprint and the expected row
      count, which catches a run shortened by `steps_override`.
  - **The checks:**
    - Bounds are inclusive, except X4's strict > 0.
    - "End" is the mean over the last 100 periods, skipping NaN (`price_sd` is NaN in periods without enough
      trades).
    - S3–S5 compare the mean over seeds of xxl's end population with the mean over seeds of xl's: a ratio of means.
    - Every check over every period skips t = 0.
  - **The script** prints the report's tables to stdout as well as writing the markdown file. It runs the three experiments under `rules` with `scorecard=true` into
    `<out>/scorecard-<label>/<id>/`, and their xl runs into `<out>/scorecard-xl/<id>/`. The xl runs are reused when
    a folder already holds the same seeds with a current fingerprint. It scores them and writes
    `<out>/scorecard-<label>.md`.
  - `rules_from_args(args) -> (XxlRules, label)` for the script:
    - `--rules v1|defaults` picks the base;
    - `--set field=value`, repeatable, changes one field, the value parsed by the field's type. For
      `Union{Nothing,Int}`, the value is `nothing` or an integer; for `Union{Nothing,Tuple{Int,Int}}`, it is
      `nothing` or `lo,hi`;
    - `--label NAME` names the run, by default the base name followed by the changed fields;
    - `--seeds N`, `--first-seed K` and `--jobs J` pass through.
- Consumes: Task 7.

- [ ] **Step 1: Write the failing tests.**
  - `score` on synthetic matrices built to sit just inside and just outside each threshold: one pair per check, 15
    pairs.
  - "extinct seed": one VI-1 seed whose population reaches 0 at t = 40. S1 fails, S2 fails, and no check throws.
    Checks that need a population at the end report NaN with `pass = false` and a detail saying "extinct in seed k".
  - "first seed": `run_scorecard` on a 2-seed, 5-period stand-in, with experiments shortened through a test-only
    keyword `steps_override`. It writes seeds 20 and 21 for both xxl and xl, and the report names them.
  - `rules_from_args(["--rules", "v1", "--set", "free_step=1.5", "--set", "founder_placement=viable"])` returns
    `XXL_V1` with those two fields and the label `v1+free_step=1.5+founder_placement=viable`.
- [ ] **Step 2: Run** `test_args=["xxl_scorecard"]`. Expected: FAIL.
- [ ] **Step 3: Implement.** The report is one markdown table per aspect. Each row gives the check, its value (mean
  and range over seeds), its threshold, PASS or FAIL, and the detail. A header gives the rules line, the seeds and
  the wall time.
- [ ] **Step 4: Run** the whole suite and pytest. Expected: all pass, 30 passed.
- [ ] **Step 5: Smoke-test** with `julia --project=julia julia/xxl_scorecard.jl --rules v1 --seeds 2 --jobs 2`.
  Expected: a report with 15 checks and no errors. Note the wall time per seed, then delete the smoke folders.
- [ ] **Step 6: Commit** "julia xxl: the scorecard".

### Task 9: Tune stage 1, set the defaults, and document

This task is mostly compute. The controller runs the scorecards (each is long; run them in the background with
`--jobs` set to the machine's cores) and records each result in the ledger. The ledger is the plan's
`progress.md` in its subagent-driven-development workspace (`.superpowers/sdd/2026-10-29-xxl-revised/`).

`test_xxl_runner.jl:32` (`fp == xxl_fingerprint(XTINY, XXL_DEFAULTS)`) keeps passing when the defaults change,
because Task 1 left it checking whatever the defaults are. No existing test changes in this task.

**Files:**
- Modify: `julia/src/xxl/types.jl` (`XXL_DEFAULTS` becomes the chosen setting), `docs/xxl.md` (the new switches in
  "The rules", and a new section "Stage 1: the scorecard and survival"), `julia/README.md` (the scorecard command)
- Test: `julia/test/test_xxl_defaults.jl` (the chosen values, the default map, and the `--xxl` fingerprint prefix of
  the new defaults)

- [ ] **Step 1: Baseline.** `--rules v1`, 20 seeds. Commit the report's table into the ledger.
- [ ] **Step 2: One at a time.** Score `v1` plus each change alone, 5 runs:
  - `--set max_metabolism=4`
  - `--set founder_placement=viable`
  - `--set free_step=1.5`
  - `--set landscape=generated`
  - `--set founder_ages=young`
- [ ] **Step 3: Together.** Score all five together, with `travel_cost` ∈ {0.05, 0.1, 0.2} × `founder_ages` ∈
  {book, young}: 6 runs.
- [ ] **Step 4: Trim.** If a single change passes S1–S5, it is the candidate. Otherwise, start from the passing
  setting of Step 3 with the fewest changes, then the higher `travel_cost`. Drop each change in turn, keep any drop
  that still passes, and repeat until no change can be dropped.
- [ ] **Step 5: Choose and confirm** on `--first-seed 20 --seeds 20`, as the spec says.
  - The switches and the landscape count as changes; `travel_cost` does not.
  - If the confirmation fails, confirm the next passing setting.
  - If none confirms, or nothing passes S1–S5, stop and report to the user: which checks fail, by how much, and the
    best setting found.
- [ ] **Step 6: Set `XXL_DEFAULTS`** to the chosen setting; switches not chosen stay at their book settings. Write
  `test_xxl_defaults.jl`. Run the whole suite and pytest. Expected: all pass.
- [ ] **Step 7: Document.**
  - `docs/xxl.md` "The rules": the four new switches, with their book settings and meanings.
  - A new results section: the baseline scorecard, the one-at-a-time and combined scorecards, the trim, the choice,
    and the confirmation, with a short account of what each change did. Report the X checks as the baseline for
    stages 2–4.
  - The existing XXL Results section stays, headed as the record of `XXL_V1`.
  - `julia/README.md`: the scorecard command and its wall time for 20 seeds at the `--jobs` used (spec, "Run time").
- [ ] **Step 8: Commit** "julia xxl: stage-1 defaults chosen by the scorecard; docs".
