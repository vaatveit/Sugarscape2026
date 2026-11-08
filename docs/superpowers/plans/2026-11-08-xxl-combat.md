# Sugarscape xxl, stage 8: combat, Part 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Readings that say what combat does in the book's five combat experiments (III-9, III-11, III-12, III-13,
III-14) in three worlds (book, xl, today), and a report that applies bars W and F and checks the runs against the saved
ones.

**Architecture:**
- **Observer.** `CombatReadings`, like stage 7's `CultureReadings`, reads the model at the end of each period: deaths by
  cause and tribe, tribe sizes, contact between tribes, territory, wealth, tribe changes. It draws no random numbers and
  touches nothing a rule reads. The book's combat move gains one line recording its victims in `m.killed`, as the xxl
  move already does.
- **Study and report.** A study command runs one experiment in one world with the observer. A report command reads the
  fifteen folders, checks each against the saved runs where those are current, and applies the bars.

**Tech Stack:** Julia (`julia/`, module `Sugarscape`), `Test`.

**Spec:** `docs/superpowers/specs/2026-11-08-xxl-combat-design.md` (approved by the user 2026-11-08). Read it first.

## Global Constraints

- **Branch:** `xxl-combat` (worktree `.claude/worktrees/xxl-combat`), from main `0dc0021`. Merging and pushing are the
  user's calls.
- **Nothing changes in a run.** With the observer off, every run is unchanged: `julia/test/test_xxl_same_run.jl`
  digests and `julia/test/fixtures/xxl-v1/*.csv` pass unchanged. With it on, each seed's standard CSV is byte-identical
  to the run without it. The observer draws no random numbers. Recording a victim in `m.killed` draws nothing.
- **Rules stay as they are:** no change to rule C, retaliation, replacement, culture, `XXL_DEFAULTS` or `XXL_V1`; Python,
  the runner's output columns and the viewer don't change.
- **The experiments are the registry's:** III-9, III-11, III-12, III-13, III-14, over each one's own `steps` (1000,
  1000, 200, 200, 1000). Worlds: `book` (`exp.config`), `xl` (`xl=true`), `today` (`xxl=XXL_DEFAULTS`).
- **No study run without the user's go-ahead.** The suite and scratch dry runs (a few periods, 1 seed, scratch folder)
  are fine. Never write into `results-julia-xxl` outside an approved run.
- **Saved runs are read, never written:** `C:/Projects/Sugarscape2026/results-julia/<exp>/` (book world) and
  `C:/Projects/Sugarscape2026/results-julia-xl/<exp>/` (xl).
- **Before each commit to `julia/src`,** run the suite in the background:
  `julia --project=julia -e 'using Pkg; Pkg.test()'` (25–35 min).
- **Style:** files LF; docs in `docs/xxl.md`'s plain style.

## Review Focus

1. **A victim's tribe in III-14,** where tags flip after the moves: a kill counts against the victim's tribe as it was
   at its death (its tags don't change once dead), and the killer is the other tribe. Test in Task 1.
2. **III-11's replacements:** each dead agent is in `m.dead_this_step` and counted by cause, though a replacement of
   its tribe already stands; a replacement is not a tribe change. Test in Task 1.
3. **An agent equally near both block centres** counts half to its tribe's home share. Test in Task 1.
4. **The book's cut in mixing isn't clearly above 0:** W2 reads against xl's cut, and if that isn't clearly above 0
   either, W2 reads missing, and the md says which reference was used. Test in Task 3.
5. **A saved reference folder made under another fingerprint** (xl's III-12, III-13, III-14) reads "no reference", not
   a drift failure; seeds the reference doesn't hold are fine. Test in Task 3.

---

### Task 1: The combat readings

**Files:**
- Modify: `julia/src/rules/combat.jl`: in `combat_move!`, `push!(m.killed, best_v.id)` just before `die!(m, best_v)`;
  update the `killed` field comment in `model.jl:50` and the "a kill by the book's combat move counts as starvation"
  sentence in `julia/src/xxl/scorecard_metrics.jl` (the scorecard runs only under round vision, so its numbers don't
  change).
- Create: `julia/src/xxl/combat_readings.jl`, included after `culture_readings.jl`.
- Modify: `julia/src/runner.jl`: a `combat_readings=nothing` keyword on `timed_seed` and `seed_job`, called after the
  step like `culture_period!`, refused with a checkpoint, passed through `seed_job` as `culture_readings` is.
- Create: `julia/test/test_xxl_combat_readings.jl` (runtests picks it up by name: `combat_readings`).

**Interfaces:**
- **Consumes** `culture_neighbors!(out, m, a)` (`culture_readings.jl`: the agents in rule K's reach: four lattice
  sites, or within `interaction_radius` under xxl), `tribe(a)`, `gini(values)` (`stats.jl`), `torus_dist`
  (`xxl/geometry.jl`) or a minimum-image distance of your own.
- **Produces** `CombatReadings()` and `combat_period!(r::CombatReadings, m::Model)`, called every period from t = 0,
  after the step. It keeps each living agent's tribe by id from the previous call.
- **Produces** `combat_rows(r) -> (header, rows)`, one row per period from t = 0, with `COMBAT_COLUMNS`:
  - `t`, `population`, `n_blue`, `n_red`;
  - `killed_blue`, `killed_red`: this period's deaths whose id is in `m.killed`, by the victim's tribe;
    `old_age_blue`, `old_age_red`: other deaths with `age >= max_age`; `starved_blue`, `starved_red`: the rest. Read
    from `m.dead_this_step` (0 at t = 0);
  - `neighbour_pairs`, `cross_pairs` (pairs of different tribes), `mixing = cross_pairs / neighbour_pairs` (NaN with
    no pairs), `front_share`: the share of agents with at least one neighbour of the other tribe (NaN with no agents);
  - `home_blue`, `home_red`: the share of the tribe's agents nearer (torus Euclidean, minimum image) to the centre of
    their own tribe's block in `m.config.initial_blocks` than to the other block's, a tie counting half (NaN with no
    agents of that tribe); a block's centre is `(x0 + w / 2, y0 + h / 2)`;
  - `gini_blue`, `gini_red`, `max_sugar_blue`, `max_sugar_red` (NaN with no agents of that tribe);
  - `tribe_changes`: agents alive now and at the previous call whose tribe differs (NaN at t = 0).

- [ ] **Step 1: Write the failing tests** on hand-made worlds (build them as `test_xxl_culture_readings.jl` does):
  - Lattice world with a blue at (0, 0), a red at (1, 0) and a blue at (W − 1, 0): `neighbour_pairs == 2`,
    `cross_pairs == 2`, `mixing == 1.0`, `front_share == 1.0`; a red added diagonal to (0, 0) is a neighbour only
    under radius 1.5.
  - Home shares with blocks blue (0, 0, 20, 20) and red (30, 30, 20, 20) on 50 × 50: a blue at (10, 10) is home, a
    blue at (40, 40) isn't, a blue at a point equally near both centres counts half.
  - Deaths: on a model where one blue is killed by `combat_move!` (book rules, a red attacker next to a poorer blue),
    the row has `killed_blue == 1`; an agent starved by `metabolize!` counts in `starved_*`; an agent past `max_age`
    in `old_age_*`.
  - III-14 for 30 periods: the sum of `killed_*` over the run equals the count of ids recorded in `m.killed` across
    the steps, and `tribe_changes` is ≥ 0 every period after 0.
  - III-11 for 20 periods: `n_blue` and `n_red` are constant, deaths are counted though replaced, and
    `tribe_changes == 0` every period after 0.
  - For each of III-9, III-11, III-12, III-13, III-14 in book, xl and `XXL_DEFAULTS` worlds, 8 periods: the standard
    CSV is byte-identical with and without the observer.
- [ ] **Step 2: Run them to see them fail.**
  `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["combat_readings"])'`. Expected: `CombatReadings` not
  defined.
- [ ] **Step 3: Implement** as the Interfaces say.
- [ ] **Step 4: Run the new tests, then the suite.** Expected: pass; digests and goldens unchanged.
- [ ] **Step 5: Commit** `julia xxl: combat readings, and the book's combat move records its victims`.

### Task 2: The combat study

**Files:**
- Create: `julia/src/xxl/combat_study.jl`, included after `culture_report.jl`.
- Create: `julia/xxl_combat_study.jl` (the command line).
- Create: `julia/test/test_xxl_combat_study.jl` (`combat_study`).

**Interfaces:**
- **Consumes** Task 1's observer, and stage 6's study pieces (`julia/src/xxl/sex_study.jl`: `sex_fingerprint`,
  `sex_seed_done`, `remove_sex_seed`, `sex_study_args`; `seed_done`, `write_seed_csv`, and the job runner the
  culture study uses). Factor the world part of `sex_fingerprint` (everything before its `sex readings:` line) into
  `world_fingerprint(exp, world, periods) -> String` and have `sex_fingerprint` call it; stage 6's and 7's tests pass
  unchanged.
- **Produces** `const COMBAT_EXPS = ("III-9", "III-11", "III-12", "III-13", "III-14")`, `const COMBAT_WORLDS =
  ("book", "xl", "today")` and
  `run_combat_world(world, exp_id; seeds=20, first_seed=0, periods=nothing, jobs=1, out=RESULTS_XXL, io=stdout) ->
  String`, `periods` defaulting to the experiment's `steps`.
- It writes into `<out>/combat-<world>-<exp>-s<first>-<seeds>-p<periods>/`, one set per seed, each through a
  temporary name with `seed<k>.csv` last: `seed<k>.csv` (the world's standard columns, as `results-julia` writes them),
  `seed<k>-combat.csv`, `seed<k>.timing.csv`. Seed `k` is the runner's seed index `k` (config seed + k), as the saved
  runs use.
- **The fingerprint:** `world_fingerprint(exp, world, periods) * "combat readings: world=<world> exp=<exp>\n"`.
- **Resuming:** whole seeds are skipped; a seed cut short is removed and rerun from period 0; a folder with another
  fingerprint is refused (`ArgumentError`) before anything runs.
- **The command line:**
  `julia --project=julia julia/xxl_combat_study.jl --world book|xl|today --exp III-9|III-11|III-12|III-13|III-14 [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]`.
  Another world or experiment, or a missing `--world` or `--exp`, is refused with the usage text.

- [ ] **Step 1: Write the failing tests** into a temporary `out`:
  - Each world with III-13, 2 seeds, 5 periods, writes all three files per seed; the standard and combat CSVs have
    `periods + 1` rows; the fingerprint's last line names the world and experiment.
  - A second call skips both seeds (unchanged timestamps); deleting one seed's `-combat.csv` reruns that seed only.
  - A folder whose fingerprint has another `periods` is refused; `--exp VI-1` and `--world sex` are refused.
  - Book III-9 seed 0, 6 periods: the standard CSV's lines equal the first 7 lines of
    `C:/Projects/Sugarscape2026/results-julia/III-9/seed0.csv` (skip the test with a note if that file is absent).
  - `sex_fingerprint` is unchanged for VI-1 in each world (stage 6's tests).
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the study tests, then the suite.** Expected: pass; stage 6's and 7's study tests unchanged.
- [ ] **Step 5: Commit** `julia xxl: the combat study runs the five combat experiments in three worlds`.

### Task 3: The combat report

**Files:**
- Create: `julia/src/xxl/combat_report.jl`, included after `combat_study.jl`.
- Create: `julia/xxl_combat_report.jl`.
- Create: `julia/test/test_xxl_combat_report.jl` (`combat_report`).

**Interfaces:**
- **Consumes** Task 2's folders, `bootstrap_ratio_apart(run, base; reps=BOOT_REPS, seed=BOOT_SEED)`
  (`disease_list.jl`; `BOOT_REPS = 10_000`, `BOOT_SEED = 20261031` in `credit_compare.jl`) and stage 6's
  `MIN_SEEDS = 15`.
- **Produces** `combat_drift(folder, ref, current_fingerprint; prefix::Bool=false) -> (; status::Symbol,
  matched::Vector{Int}, differ::Vector{Int})`: `status` is `:no_reference` when `ref` doesn't exist or its
  `fingerprint.txt` isn't `current_fingerprint` (the text the runner writes today for that experiment and world: find
  the writer `results-julia` folders come from); otherwise each seed in `folder` with a `seed<k>.csv` in `ref` is
  compared byte for byte (`prefix=true`: its lines against `ref`'s first lines, for a dry run), and `status` is
  `:passes` or `:fails`. Seeds `ref` lacks are skipped, not failures.
- **Produces** `combat_report(; dir=RESULTS_XXL, first_seed=0, seeds=20, ref_book=REF_BOOK, ref_xl=REF_XL, md, io=stdout)`
  reading the fifteen folders `combat-<world>-<exp>-s<first>-<seeds>-p<steps>` in `dir`, with `REF_BOOK =
  "C:/Projects/Sugarscape2026/results-julia"` and `REF_XL = "C:/Projects/Sugarscape2026/results-julia-xl"` (each
  holding `<exp>/`). It refuses a folder whose fingerprint doesn't name the world and experiment it is read as.
- **Produces** the command line
  `julia --project=julia julia/xxl_combat_report.jl [--dir DIR] [--first-seed K] [--seeds N] [--ref-book DIR] [--ref-xl DIR] [--md PATH]`,
  `--md` defaulting to `<dir>/combat-part1.md`.
- **Constants,** the spec's values: `W_SHARE = 0.5`, `F_MIN_SHARE = 0.05`, `F1_SEEDS_SHARE = 0.8`,
  `F3_SEEDS_SHARE = 0.5`, `HOME_MIN = 0.5`, `W2_WINDOW = (101, 200)`, `F1_WINDOW = (501, 1000)`, `F1_BLOCK = 100`.
- **Per-seed values** (a seed whose last population is 0 is left out of every ratio value and counted; a period where
  a value is NaN is skipped; a seed with no defined period is missing for that value only):
  - **W1 (III-9):** the sum of `killed_blue + killed_red` over t = 1 to the end ÷ the population at t = 0.
  - **Mixing (III-12, III-13):** mean `mixing` over `W2_WINDOW`.
- **The bars:**
  - **W1:** today ÷ book with `bootstrap_ratio_apart`; holds when the ratio < `W_SHARE` and the interval's upper end
    < 1; fewer than `MIN_SEEDS` seeds on either side reads missing. xl ÷ book shown.
  - **W2:** the cut in mixing of a world, `1 − mean(III-13) / mean(III-12)` over its seeds. Its interval: the same
    bootstrap scheme (`BOOT_REPS` resamples, `BOOT_SEED`, percentile 95%), resampling each of the sets of seeds apart.
    A reference (book, then xl) counts when its own cut's interval lower end is > 0. W2 = today's cut ÷ the
    reference's cut, with its interval from resampling the four sets apart; holds when < `W_SHARE` and the upper end
    < 1. No reference that counts, or fewer than `MIN_SEEDS` seeds in any of the four sets: missing. The md names the
    reference.
  - **W** holds when both hold, fails when either fails (even if the other is missing), and reads missing only when
    neither fails and one is missing.
  - **F1 (today III-11):** every seed has `killed_blue + killed_red > 0` in each `F1_BLOCK`-period block of
    `F1_WINDOW`, and in at least `F1_SEEDS_SHARE` of seeds `min(mean home_blue, mean home_red)` over `F1_WINDOW` is
    > `HOME_MIN`.
  - **F2 (today III-9 and III-14):** every seed's population at its last period is > 0.
  - **F3 (today III-14):** in at least `F3_SEEDS_SHARE` of seeds both `n_blue` and `n_red` are ≥ `F_MIN_SHARE` of the
    population at the last period.
  - **F** holds when all three hold. Every expected seed counts: a missing or unfinished seed file fails F. F reads
    missing when a today folder holds fewer than `MIN_SEEDS` seed files.
- **The drift check:** `combat_drift` for each book and xl folder against `<ref_…>/<exp>/`; any `:fails` fails it.
  `:no_reference` is listed, not a failure. Today has no reference.
- **The outcome line,** in this order:
  1. Drift check fails: "the runs differ from the saved runs: stop and report to the user".
  2. F fails or reads missing: report to the user, no rule.
  3. W reads missing: no outcome.
  4. W holds: combat is weak in xxl; the readings go to the user with a rule spec.
  5. Otherwise: combat works as intended in xxl.
- **The md** lists each folder with seeds whole, missing and extinct; the drift check per folder; the bars (value,
  interval, bar, result, and W2's reference); then, deciding nothing, for every experiment and world by window
  (t = 1–100, 101–200, 201–500, 501–1000 within the run): kills per period by victim tribe, starvations, deaths of age,
  population and tribe sizes, mixing, front share, home shares, Ginis, largest holdings, tribe changes; III-9's ending
  per seed (one tribe under `F_MIN_SHARE`, or both alive) in each world; and the outcome.

- [ ] **Step 1: Write the failing tests** on hand-written folders (fingerprints, standard CSVs, `-combat.csv`), 15+
  seeds per world where a bar needs them:
  - W1: today's kills per founder 0.1 against the book's 0.6, tight: ratio about 0.17, holds. A ratio of 0.45 whose
    interval reaches 1 doesn't hold.
  - W2 with the book's mixing 0.30 (III-12) and 0.15 (III-13), today's 0.30 and 0.27: book cut 0.5, today's 0.1, ratio
    0.2, holds, reference "book".
  - W2 with the book's cut about 0 (both 0.30, noisy) and xl's 0.4: reference "xl". With xl's also about 0: missing,
    and W with W1 failing reads "fails".
  - F1: a today III-11 seed with no kill in t = 701–800 fails F1; home shares of 0.6 and 0.45 in 5 of 20 seeds (0.75 <
    0.8) fail it.
  - F2: a today III-9 seed at population 0 fails F, outcome "report to the user". F3: 9 of 20 III-14 seeds with both
    tribes ≥ 5% fails.
  - A missing today seed file fails F.
  - `combat_drift`: an identical copy passes; one changed byte fails; a stale fingerprint gives `:no_reference`; a seed
    the reference lacks is skipped; `prefix=true` matches a 7-line file against a longer one. A drift failure puts the
    drift outcome first.
  - A folder read as xl whose fingerprint names book is refused.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the report tests, then the suite.** Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: the combat report applies bars W and F`.

### After the tasks (controller)

- **Review, then dry run:** a final whole-branch review, then a scratch dry run of every world and experiment
  (5 periods, 1 seed, seed 0, scratch `--out`) to time it, check the files, and check `combat_drift(...; prefix=true)`
  against the saved runs. Estimate the full runs from it. Then **ask the user** before any run.
- **On the user's go-ahead:** a script runs all fifteen (book first, then xl, then today; `--jobs 5`, seeds 0–19),
  then the report, writing `results-julia-xxl/combat-part1.md`.
- **Results:** apply the outcome. Write the findings in `docs/xxl.md` as "Stage 8: combat", with combat added to the
  goal, reviewed, and commit with the user's approval.
