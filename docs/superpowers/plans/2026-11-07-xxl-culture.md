# Sugarscape xxl, stage 7: culture, Part 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Readings that say whether xxl agents live among culturally like agents, and whether areas take on a colour,
as much as the book's rules do at the book's scale. The readings come from VI-1 in three worlds (book, xl, today), plus a
report that applies bars W and F and checks the runs against stage 6's.

**Architecture:**
- **Observer.** `CultureReadings`, like stage 6's `SexReadings`, reads the agents at the end of each period. It writes a
  per-period table and, every 10 periods, a table of 50 × 50 patches. It draws no random numbers and touches nothing in
  the model that a rule reads.
- **Study and report.** A study command runs a world's seeds with the observer, as stage 6's does. A report command reads
  the three worlds' folders, compares each standard CSV with stage 6's, and applies the bars.

**Tech Stack:** Julia (`julia/`, module `Sugarscape`), `Test`.

**Spec:** `docs/superpowers/specs/2026-11-07-xxl-culture-design.md` (approved by the user 2026-11-07). Read it first.

## Global Constraints

- **Branch:** `xxl-culture` (worktree `.claude/worktrees/xxl-culture`), from main `5e5f69d`. Merging and pushing are
  the user's calls.
- **Nothing changes in a run.** With the observer off, every run is unchanged: the `julia/test/test_xxl_same_run.jl`
  digests and `julia/test/fixtures/xxl-v1/*.csv` pass unchanged. With it on, each seed's standard CSV is byte-identical
  to the run without it. The observer draws no random numbers.
- **Rules stay as they are:** no change to rule K, tag length, group membership or vertical transmission;
  `XXL_DEFAULTS` and `XXL_V1` don't change; Python, the runner's output columns and the viewer don't change.
- **No study run without the user's go-ahead.** That covers `xxl_culture_study.jl` and every other study command. The
  test suite and scratch dry runs (a few periods, 1 seed, into a scratch folder) are fine. Never write into
  `C:\Projects\Sugarscape2026\results-julia-xxl` outside an approved run.
- **Stage 6's result folders are read, never written:**
  `C:\Projects\Sugarscape2026\.claude\worktrees\xxl-sex\results-julia-xxl\sex-{book-VI-1-s80-60,xl-VI-1-s80-20,today-VI-1-s80-20}-p500\`.
- **Before each commit to `julia/src`,** run the suite in the background:
  `julia --project=julia -e 'using Pkg; Pkg.test()'` (12–25 min).
- **Style:** files LF; docs in `docs/xxl.md`'s plain style.

## Review Focus

1. **Neighbour pairs across the torus edge,** in both neighbourhoods (four lattice sites; radius 1.5 with diagonals):
   a pair at x = 0 and x = W − 1 counts once. Test in Task 1.
2. **An agent born or dying this period:** it enters neither persistence nor distance moved (both need the agent alive
   at both ends), but counts in this period's closeness and population. Test in Task 1.
3. **A surviving book seed that is tiny late on:** periods with no neighbour pairs, or with its one patch under 20
   agents, are skipped; a seed with none left in the window is missing for that reading only and doesn't count toward
   15. Test in Task 3.
4. **A today seed that went extinct:** it fails F rather than vanishing. Test in Task 3.
5. **A stopped run started again:** a seed cut short is removed and rerun from period 0, and a folder made under another
   world, code or periods is refused before anything runs. Test in Task 2.

---

### Task 1: The culture readings

**Files:**
- Create: `julia/src/xxl/culture_readings.jl`, included after `sex_readings.jl`'s include.
- Modify: `julia/src/runner.jl` (a `culture_readings=nothing` keyword on `timed_seed` and `seed_job`, called after the
  step like `sex_period!`, refused with a checkpoint, passed through `seed_job` as `sex_readings` is).
- Create: `julia/test/test_xxl_culture_readings.jl`, added to `julia/test/runtests.jl` under the name `culture_readings`.

**Interfaces:**
- **Produces** `CultureReadings()` and `culture_period!(r::CultureReadings, m::Model)`, called every period from t = 0,
  after the step. It keeps, from the previous call: each living agent's tags and position by id, and the set of
  neighbour pairs as `(lo_id, hi_id)`.
- **Produces** `culture_neighbors(m::Model, a::Agent) -> Vector{Agent}`: the agents in rule K's reach of `a` now, found
  from the grid. That's the four von Neumann sites when `xxl_on(m.config, :radius)` is false, else the sites at
  `near_offsets(m, m.config.xxl.interaction_radius)`, wrapped. It uses its own vector, never `m.sight` or `a.neighbors`.
- **Produces** `culture_rows(r) -> (header, rows)`, one row per period from t = 0, with `CULTURE_COLUMNS`:
  - `t`, `population`, `blue_share` (`tribe(a) === :blue` share);
  - `tag_flips_per_agent`: bits changed since last period, summed over agents alive at both, ÷ population (NaN at t = 0
    or with no agents), as `tag_flips` in `scorecard_metrics.jl`;
  - `neighbour_pairs`; `neighbour_closeness`: mean of `closeness(a.tags, b.tags, 11)` over unordered neighbour pairs;
  - `chance_closeness`: mean closeness over all unordered pairs of living agents,
    `1 − Σᵢ 2 zᵢ (n − zᵢ) ÷ (L n (n − 1))`, with zᵢ the count of zeros at position i, n the population, L the tag length;
  - `neighbours_per_agent` (mean count from `culture_neighbors`), `share_no_neighbours`;
  - `persist_base`: last period's neighbour pairs whose two agents are both alive now; `persistence`: the share of those
    that are neighbour pairs now;
  - `mean_moved`: mean torus Euclidean distance (minimum image) between each agent's position now and last period, over
    agents alive at both; `mean_speed`: mean of the speed trait under `xxl_on(cfg, :speed)`, else NaN;
  - `zero_share_1` … `zero_share_11`: the share of agents with a 0 at that position (bit i − 1 is position i).

  A column with nothing to average is NaN.
- **Produces** `culture_patch_rows(r) -> (header, rows)` with `CULTURE_PATCH_COLUMNS = ["t", "px", "py", "agents",
  "blue_share"]`: at every t with `t % CULTURE_PATCH_EVERY == 0`, one row per patch holding at least one agent. Patch
  `(px, py) = (x ÷ CULTURE_PATCH, y ÷ CULTURE_PATCH)`, 0-based. Constants: `CULTURE_PATCH = 50`,
  `CULTURE_PATCH_EVERY = 10`.
- **Produces** `patch_polarization(rows; min_agents=CULTURE_PATCH_MIN) -> Float64` over one period's patch rows: the
  agent-weighted mean of `abs(2 * blue_share - 1)` over patches with `agents >= min_agents`, NaN when none.
  `CULTURE_PATCH_MIN = 20`.

- [ ] **Step 1: Write the failing tests** on hand-made worlds (build them as `test_xxl_sex_readings.jl` does):
  - Lattice world, three agents in a row at x = 0, 1, 2 with known tags: `neighbour_pairs == 2` and
    `neighbour_closeness` equals the hand mean. A fourth at a diagonal of the middle agent isn't a neighbour.
  - Radius 1.5 world: the diagonal agent is a neighbour; agents at x = 0 and x = W − 1 on the same row form one pair.
  - `chance_closeness` equals a brute-force mean over all pairs on a 7-agent world with random tags.
  - Two periods by hand: a pair that moves apart gives `persistence == 0.0` with `persist_base == 1`; an agent moved
    from x = W − 1 to x = 1 gives `mean_moved == 2.0`; an agent removed between the periods enters neither.
  - Patches on a 100 × 100 world: 25 blue agents in patch (0, 0), 15 red and 15 blue in (1, 0), 5 red in (0, 1):
    `patch_polarization` over the rows is `(25 * 1 + 30 * 0) / 55`; the 5-agent patch is left out; with
    `min_agents = 1` it counts.
  - `tag_flips_per_agent` equals the scorecard's `tag_flips_per_agent` on a short scorecard VI-1 run.
  - `mean_speed` is NaN in a book-config world.
  - On a 12-period VI-1 run in each of book, xl and `XXL_DEFAULTS`, the standard CSV is byte-identical with and without
    the observer.
- [ ] **Step 2: Run them to see them fail.**
  `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["culture_readings"])'`. Expected: `CultureReadings` not
  defined.
- [ ] **Step 3: Implement** as the Interfaces say.
- [ ] **Step 4: Run the new tests, then the suite.** Expected: pass; digests and goldens unchanged.
- [ ] **Step 5: Commit** `julia xxl: culture readings, per period and per patch`.

### Task 2: The culture study

**Files:**
- Create: `julia/src/xxl/culture_study.jl`, included after `sex_report.jl`.
- Create: `julia/xxl_culture_study.jl` (the command line).
- Create: `julia/test/test_xxl_culture_study.jl`, added to `runtests.jl` as `culture_study`.

**Interfaces:**
- **Consumes** Task 1's observer, and stage 6's study pieces (`julia/src/xxl/sex_study.jl`: `sex_fingerprint`,
  `sex_plan`, `sex_seed_done`, `remove_sex_seed`, `sex_seed!`, `sex_study_args`). Generalize them where that's cleaner,
  provided stage 6's tests pass unchanged.
- **Produces** `const CULTURE_WORLDS = ("book", "xl", "today")` and
  `run_culture_world(world; seeds=20, first_seed=80, periods=500, jobs=1, out=RESULTS_XXL, io=stdout) -> String`. The
  worlds run VI-1 as stage 6's do (`book`: the registry config; `xl`: `xl=true`; `today`: `xxl=XXL_DEFAULTS`).
- It writes into `<out>/culture-<world>-VI-1-s<first>-<seeds>-p<periods>/`, one set per seed, each through a temporary
  name with `seed<k>.csv` last: `seed<k>.csv` (the world's standard columns), `seed<k>-culture.csv`,
  `seed<k>-patches.csv`, `seed<k>.timing.csv`.
- **The fingerprint:** as stage 6's for the same world, ending with `culture readings: world=<world> window=(lo, hi)`,
  where the window is the last 200 periods (t = 301–500 for 500 periods; `CULTURE_WINDOW = 200`).
- **Resuming:** whole seeds are skipped; a seed cut short is removed and rerun from period 0. A folder with another
  fingerprint is refused (`ArgumentError`) before anything runs.
- **The command line:**
  `julia --project=julia julia/xxl_culture_study.jl --world book|xl|today [--seeds N] [--first-seed K] [--periods P] [--jobs J] [--out DIR]`.
  Any other world, or a missing `--world`, is refused with the usage text.

- [ ] **Step 1: Write the failing tests** into a temporary `out`:
  - Each world, 2 seeds, 6 periods, writes all four files per seed; the standard and culture CSVs have `periods + 1`
    rows; the patch CSV holds rows only at t = 0; the fingerprint's last line names the world.
  - A second call skips both seeds (unchanged timestamps).
  - Deleting one seed's `-patches.csv` makes the next call rerun that seed only.
  - A folder whose fingerprint has a different `periods` is refused.
  - `--world sex` is refused.
  - For one book seed and one today seed, the 6-period standard CSV equals the first 7 data rows of a
    `run_sex_world` folder made in the same test for the same seed (the two studies run the same model).
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the study tests, then the suite.** Expected: pass; stage 6's study tests unchanged.
- [ ] **Step 5: Commit** `julia xxl: the culture study runs VI-1 with the readings in three worlds`.

### Task 3: The culture report

**Files:**
- Create: `julia/src/xxl/culture_report.jl`, included after `culture_study.jl`.
- Create: `julia/xxl_culture_report.jl`.
- Create: `julia/test/test_xxl_culture_report.jl`, added to `runtests.jl` as `culture_report`.

**Interfaces:**
- **Consumes** Task 2's folders, `patch_polarization`, and `bootstrap_ratio_apart(run, base; reps=BOOT_REPS,
  seed=BOOT_SEED)` (`julia/src/xxl/disease_list.jl`; `BOOT_SEED = 20261031` and `BOOT_REPS = 10_000` in
  `credit_compare.jl`, the spec's values).
- **Produces** `culture_drift(folder, ref; prefix::Bool=false) -> (; matched::Vector{Int}, differ::Vector{Int},
  absent::Vector{Int})`: for each seed in `folder`, whether `seed<k>.csv` equals `ref`'s byte for byte (`prefix=true`:
  whether its lines equal `ref`'s first lines, for a dry run). `absent` lists seeds with no file in `ref`.
- **Produces** `culture_report(; book, xl, today, ref_book, ref_xl, ref_today, md, io=stdout)`. It refuses a folder
  whose fingerprint doesn't name the world it is passed as.
- **Produces** the command line
  `julia --project=julia julia/xxl_culture_report.jl --book DIR --xl DIR --today DIR --ref-book DIR --ref-xl DIR --ref-today DIR [--md PATH]`,
  every folder required, `--md` defaulting to `results-julia-xxl/culture-part1.md`.
- **Constants,** the spec's values: `W_SHARE = 0.5`, `F_MIN_SHARE = 0.05`, `F_MIN_SEEDS_SHARE = 0.8`, and stage 6's
  `MIN_SEEDS = 15`.
- **Per-seed values,** each the mean over the window's periods where it's defined (window from the fingerprint,
  t = 301–500), skipped periods counted:
  - **W1 value:** mean `neighbour_closeness` − 0.5.
  - **W2 value:** mean of `patch_polarization` over the window's tenth periods.
  - **Readings,** shown and deciding nothing: blue share, flips per agent, chance closeness, neighbours per agent,
    share with no neighbours, persistence, distance moved, speed; `friend_closeness` and `best_friend_closeness` from
    the standard CSV; per-position polarization `mean |2 zᵢ − 1|` at the last period. Each also for t = 51–100,
    101–200 and 201–300, with W1 and W2 values too.

  A seed whose last population is 0 is left out of every value and counted. A seed with no defined period for a value
  is missing for that value only. Each value's table cell gives seeds used and the share of seed-periods skipped.
- **The bars:**
  - **W1, W2:** today ÷ book with `bootstrap_ratio_apart`. Each holds when the ratio is < `W_SHARE` and the interval's
    upper end is < 1; fewer than `MIN_SEEDS` seeds on either side reads missing. W holds when both hold, fails when
    either fails (even if the other is missing), and reads missing only when neither fails and one is missing. xl ÷ book
    and today ÷ xl are shown beside them.
  - **F:** over every today seed in the folder, extinct ones included as failures: the share with
    `F_MIN_SHARE <= blue_share <= 1 - F_MIN_SHARE` at the last period is ≥ `F_MIN_SEEDS_SHARE`, and every seed's
    smallest `tag_flips_per_agent` over the window is > 0. F reads missing with fewer than `MIN_SEEDS` seed files.
- **The drift check:** `culture_drift` of each world against its `ref_…` folder. Any `differ` seed, or a seed absent
  from the reference, makes the drift check fail.
- **The outcome line,** in this order:
  1. Drift check fails: "the runs differ from stage 6's: stop and report to the user".
  2. F fails or reads missing: report to the user, no rule.
  3. W reads missing: no outcome.
  4. W holds: culture is weak in xxl; the readings go to the user with a rule spec.
  5. Otherwise: culture works as intended in xxl.
- **The md** lists each world's folder, seeds used and left out, the drift check per world, the bars (value, interval,
  bar, result), the readings table per window, and the outcome.

- [ ] **Step 1: Write the failing tests** on hand-written folders (fingerprints, standard CSVs, `-culture.csv`,
  `-patches.csv`), 15+ seeds per world:
  - Today's neighbour closeness 0.6 against the book's 0.9, tight across seeds: W1 ratio 0.25, holds; patches likewise
    for W2; outcome "culture is weak".
  - A W1 ratio of 0.45 whose interval's upper end is ≥ 1 doesn't hold.
  - W1 fails and W2 reads missing (book patches all under 20 agents in 46 of 60 seeds): W fails, outcome "works as
    intended".
  - A book seed with no neighbour pairs in 10 of the window's periods: its value is the mean over the other 190, and
    the skipped share shows.
  - Six of 20 today seeds at population 0: F fails (share 0.7 < 0.8), outcome "report to the user".
  - A today seed with a window period of 0 flips fails F.
  - `culture_drift`: an identical copy matches; one changed byte differs; a 7-line file matches the first 7 lines of a
    longer file with `prefix=true` and differs without it; a seed with no reference file is absent. A drift failure
    puts the drift outcome first.
  - A folder passed as `--xl` whose fingerprint names `book` is refused.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the report tests, then the suite.** Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: the culture report applies bars W and F`.

### After the tasks (controller)

- **Review, then dry run:** a final whole-branch review, then a scratch dry run of each world (5 periods, 1 seed,
  seed 80, scratch `--out`) to time it, check the files, and check `culture_drift(...; prefix=true)` against stage 6's
  folders. Then **ask the user** before any run.
- **On the user's go-ahead:** run `--world book --seeds 60`, then `--world xl` and `--world today` (seeds 80–99), each
  over 500 periods with `--jobs 5`, checking each fingerprint at launch; then the report with the three folders and the
  three stage-6 folders, writing `results-julia-xxl/culture-part1.md`.
- **Results:** apply the outcome. Write the findings in `docs/xxl.md` as "Stage 7: culture", reviewed, and commit them
  with the user's approval.
