# Pollution decay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-period pollution decay rule (`pollution_decay`, default 0), the experiment `VI-1-pollution-decay`, four
new pollution readings in the combat study, and two viewer charts that show them.

**Architecture:** The rule is one config field and a multiply at the end of `step!`, skipped entirely at 0. The
experiment reuses `vi1_pollution_build` in julia/src/xxl/vi1_combat.jl. The readings ride on the existing pollution row
of `CombatReadings`, so the study's CSV and the viewer's series come from one place; the page only draws them.

**Tech Stack:** Julia 1.13 (package `Sugarscape` in julia/, module `XxlViewer` in julia/viewer/), browser ES modules in
julia/viewer/static/, `node --test` for julia/test/js/. No new dependency.

**Spec:** docs/superpowers/specs/2026-11-11-pollution-decay-design.md (read it first; this plan argues from it).

## Global Constraints

- Branch `pollution-decay`; nothing merged or pushed. Commit after each task, ending the message with
  `Co-Authored-By: <your model name> <noreply@anthropic.com>`.
- LF line endings in every file written or edited (the repository is LF; don't let an editor convert to CRLF).
- Never start a study run (the `julia/xxl_*_study.jl` commands with real seeds or periods). Tests may call
  `run_combat_world` with a few periods into `mktempdir()`, as existing tests do.
- Never leave a viewer server running after a check.
- With `pollution_decay = 0` every run is byte-identical to today: the decay code must do nothing at all at 0 (no
  multiply). The golden tests (julia/test/test_xxl_same_run.jl and the lockstep fixtures) must pass unchanged.
- No change to rule P, rule D, `harvest!`, `metabolize!`, `diffuse!`, the movement rules, or the Python original.
- Existing tests change only as the spec's "Existing tests that change" says, plus what this plan names: the id lists
  in julia/test/test_vi1_reach.jl; `VIEWER_EXPS` and `POLLUTION_SERIES` in julia/test/test_xxl_viewer_run.jl; the
  column list and header line in julia/test/test_xxl_pollution_readings.jl; and in julia/test/js/charts.test.mjs the
  chart count, the key list and the assertions that take the "Pollution" and "On the richest land" charts to be the
  last two (they become 3rd and 4th from last). Nothing else in an existing test changes.
- Run a single Julia test file with: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["<name part>"])'`.
  Run the JS tests with: `node --test julia/test/js/` from the repository root.
- Docs wrap at 120 columns.

## Review Focus

1. `pollution_decay = 0`: a step must leave the pollution field exactly as it was before the decay point (Task 1 test).
2. `pollution_decay = NaN` must be rejected by `validate` (a naive `δ < 0 || δ >= 1` lets NaN through) (Task 1 test).
3. A world where every cell counts as rich (uniform capacity): `pollution_other` must be NaN, not an error (Task 3
   test).
4. No agents: `agents_rich` and `agents_other` are 0 and the pollution means are still defined (Task 3 test).
5. An experiment with decay whose pollution starts at 0: no start marker, but the legend still states the decay
   (Task 4 test).

---

### Task 1: The rule `pollution_decay`

**Files:**
- Modify: `julia/src/config.jl` (field beside `pollution_stop`, ~line 108; check in `validate` beside the
  `pollution_stop` check, ~line 316)
- Modify: `julia/src/model.jl` (`step!`, after the diffusion block, before `m.t += 1`, ~line 419)
- Create: `julia/test/test_pollution_decay.jl` (runtests.jl picks up every `test_*.jl` file by itself)

**Interfaces:**
- Produces: `Config.pollution_decay::Float64` (default `0.0`); `validate` throws `ArgumentError` unless
  `0 <= pollution_decay < 1`.

- [ ] **Step 1: Write the failing tests** in julia/test/test_pollution_decay.jl (use `tiny_model` from helpers.jl, as
  julia/test/test_vi1_pollution.jl does):
  - `Config().pollution_decay == 0.0`.
  - `validate(Config(; pollution_decay=x))` throws `ArgumentError` for `x` in `(-0.01, 1.0, 1.5, NaN)`, and returns
    for `0.0`, `0.045`, `0.999`.
  - `pollution_decay=0.1` with `pollution = nothing` validates, and `step!` runs.
  - One step on `tiny_model(ones(Int, 5, 5); pollution_decay=0.1)` (no agents, no diffusion) after setting
    `m.landscape.pollution` to distinct positive values: the field afterwards `==` the old field `.* 0.9`
    (exact; compute the expectation as `old .* (1 - 0.1)`).
  - Same with `diffusion_period=1, diffusion_start=0`: the field afterwards `==` (a copy of the landscape run through
    `diffuse!` once) `.* (1 - 0.1)`: decay comes after diffusion.
  - Decay acts when diffusion doesn't: `diffusion_period=2`, a step taken at an odd `m.t` multiplies by `0.9` with no
    averaging.
  - With `diffusion_passes=100`, `diffusion_period=1`: `sum(after) ≈ sum(before) * 0.9` (rtol 1e-12).
  - `pollution_decay=0.0`: after a step without diffusion the field `==` the old field, element by element.
- [ ] **Step 2: Run** `Pkg.test(test_args=["pollution_decay"])`. Expected: FAIL (no field).
- [ ] **Step 3: Implement.** The field with a one-line comment in the style of the neighbours (Julia-only, an xxl-era
  extension the book doesn't have; default 0 is the book's). The check written so NaN fails it, e.g.
  `0 <= c.pollution_decay < 1 || bad("pollution_decay must be in [0, 1), not $(c.pollution_decay)")`. In `step!`:
  `cfg.pollution_decay > 0 && (ls.pollution .*= 1 - cfg.pollution_decay)` (or an equivalent loop), placed after the
  diffusion block.
- [ ] **Step 4: Run** `Pkg.test(test_args=["pollution_decay"])`, then `Pkg.test(test_args=["config"])` and
  `Pkg.test(test_args=["same_run"])`. Expected: PASS.
- [ ] **Step 5: Commit** "pollution-decay: the rule (pollution_decay, default 0)".

### Task 2: The experiment `VI-1-pollution-decay`

**Files:**
- Modify: `julia/src/xxl/vi1_combat.jl` (after `vi1_pollution_t0_experiment`, ~line 195)
- Modify: `julia/src/xxl/combat_study.jl` (`JULIA_COMBAT_EXPS`, `COMBAT_USAGE` and the docstring's id list, ~lines
  124–129)
- Modify: `julia/viewer/run.jl` (`VIEWER_EXPS`, line ~11)
- Modify: `julia/test/test_vi1_reach.jl` (the two id lists, lines ~21 and ~67), `julia/test/test_xxl_viewer_run.jl`
  (`VIEWER_EXPS`, line ~25)
- Test: `julia/test/test_pollution_decay.jl`

**Interfaces:**
- Consumes: `Config.pollution_decay` (Task 1).
- Produces: `VI1_POLLUTION_DECAY_ID = "VI-1-pollution-decay"`, `vi1_pollution_decay_experiment(reg=load_registry())
  -> Experiment`; `vi1_pollution_build` gains keywords `steps::Int=VI1_POLLUTION_STEPS, decay::Float64=0.0` (existing
  calls unchanged).

- [ ] **Step 1: Write the failing tests** (new testset in julia/test/test_pollution_decay.jl):
  - `e = vi1_pollution_decay_experiment(); p = vi1_pollution_experiment()`: `e.id == "VI-1-pollution-decay"`,
    `JULIA_COMBAT_EXPS[e.id]().id == e.id`, `e.steps == 1000`, `e.seeds == p.seeds`.
  - For each world in `("book", "xl", "today")`: `world_config(e, w).pollution_decay == 0.045`, and every other field
    `repr`-equals `world_config(p, w)`'s.
  - `startswith(e.fingerprint, vi1_assim_k4_experiment().fingerprint)` and the same for `xl_fingerprint`;
    `occursin("variant: VI-1-pollution-decay ", e.fingerprint)`; `endswith(e.fingerprint, "\n")`.
  - Today's world: `Model(world_config(e, "today"))` and the same for `p`, three `step!`s each: agents (id, x, y,
    sugar, spice, tags) and the pollution field identical (pollution starts at 350, so the decay has nothing to act on).
- [ ] **Step 2: Run** `Pkg.test(test_args=["pollution_decay"])`. Expected: FAIL.
- [ ] **Step 3: Implement.** `vi1_pollution_build(...; steps, decay)` sets `pollution_decay=decay` in `change` and
  uses `steps`. The variant line, exactly:
  `"variant: VI-1-pollution-decay pollution=(1,1) pollution_start=350 pollution_decay=0.045 diffusion_period=1 diffusion_start=450 steps=1000 (pollution decaying 4.5% a period on a settled society, then diffusion)\n"`.
  A docstring for the new builder in the style of its neighbours. Add the id to `JULIA_COMBAT_EXPS`, `COMBAT_USAGE`,
  the docstring list and `VIEWER_EXPS` (after `"VI-1-pollution-t0"`), and to the three test lists.
- [ ] **Step 4: Run** `Pkg.test(test_args=["pollution_decay"])`, `Pkg.test(test_args=["vi1_reach"])`,
  `Pkg.test(test_args=["vi1_pollution"])`. Expected: PASS. (`test_xxl_viewer_run` may fail on `POLLUTION_SERIES`
  only after Task 4 changes it; it must pass here.)
- [ ] **Step 5: Commit** "pollution-decay: the experiment VI-1-pollution-decay".

### Task 3: The readings

**Files:**
- Modify: `julia/src/xxl/combat_readings.jl` (`POLLUTION_COLUMNS` line 74, `pollution_period!` ~line 219)
- Modify: `julia/test/test_xxl_pollution_readings.jl` (column list line 18, header line 58, plus new hand values)

**Interfaces:**
- Produces: `POLLUTION_COLUMNS == ["t", "mean_pollution", "agent_pollution", "share_rich", "agents_rich",
  "agents_other", "pollution_rich", "pollution_other"]`; each pollution row has those 8 values in that order.

- [ ] **Step 1: Write the failing tests** in julia/test/test_xxl_pollution_readings.jl:
  - The column list and the CSV header line as above.
  - On the file's existing 4×4 hand world: `agents_rich` and `agents_other` equal hand counts,
    `agents_rich + agents_other == length(m.agents)`, `pollution_rich` and `pollution_other` equal the hand means of
    the pollution over the rich and the other cells.
  - No agents: `agents_rich == 0 && agents_other == 0`, `pollution_rich` and `pollution_other` finite.
  - Uniform capacity (every cell at the cut, so all rich): `pollution_other` is NaN, `pollution_rich` is the world mean.
- [ ] **Step 2: Run** `Pkg.test(test_args=["pollution_readings"])`. Expected: FAIL.
- [ ] **Step 3: Implement** in `pollution_period!`: count agents on rich and other cells in the existing loop; the two
  means over `r.rich` and `.!r.rich` (NaN for an empty set); push the 8 values. Update the comment above it and the
  `pollution_rows` docstring if it names the columns.
- [ ] **Step 4: Run** `Pkg.test(test_args=["pollution_readings"])` and `Pkg.test(test_args=["combat"])`. Expected:
  PASS.
- [ ] **Step 5: Commit** "pollution-decay: four new pollution readings (agents and pollution on and off rich land)".

### Task 4: The viewer

**Files:**
- Modify: `julia/viewer/run.jl` (`POLLUTION_SERIES`, line 61)
- Modify: `julia/viewer/encoding.jl` (`pollution_legend`, ~line 107: add `"decay" => cfg.pollution_decay`)
- Modify: `julia/viewer/static/charts.mjs` (two `CHARTS` entries after `"rich"`; `markerPeriods`)
- Modify: `julia/viewer/static/app.mjs` (the legend's pollution section: one line stating the decay when above 0)
- Modify: `julia/test/test_xxl_viewer_run.jl` (`POLLUTION_SERIES` line ~102), `julia/test/test_xxl_viewer_frame.jl`
  (legend: add assertions only), `julia/test/js/charts.test.mjs`

**Interfaces:**
- Consumes: the 4 new columns (Task 3), `VI-1-pollution-decay` (Task 2), `Config.pollution_decay` (Task 1).
- Produces: series keys `agents_rich`, `agents_other`, `pollution_rich`, `pollution_other`; legend key
  `pollution.decay` (a number, 0 without decay); chart ids `"rich_count"` and `"rich_pollution"`.

- [ ] **Step 1: Write the failing tests.**
  - Julia: `POLLUTION_SERIES == ["mean_pollution", "agent_pollution", "share_rich", "agents_rich", "agents_other",
    "pollution_rich", "pollution_other"]`; the existing "pollution run matches the study" testset then checks all seven
    against the study's CSV (it loops over `POLLUTION_SERIES`, line ~107; no change there). Legend: `pollution_legend` gives
    `"decay" => 0.0` for `VI-1-pollution` and `0.045` for `VI-1-pollution-decay` (today's world, at t = 0).
  - JS (charts.test.mjs): `CHARTS.length == 11`; the key list gains the four keys; the "two pollution charts" test
    finds them at `CHARTS.length - 4` and `- 3` instead of the last two (only that changes); a new test: the last two
    charts are `rich_count` ("Agents on rich land": lines `agents_rich` "on rich land" and `agents_other` "elsewhere",
    no fixed axis) and `rich_pollution` ("Pollution on rich land and elsewhere": lines `pollution_rich` and
    `pollution_other`), both `when: "pollution"`, shown by `chartsFor({ pollution })` and not by
    `chartsFor({ pollution: null })`. `markerPeriods` with `decay: 0.045, start: 350` labels the pollution marker
    `"pollution on, decays 4.5%"`; with `decay: 0` it stays `"pollution on"`; with `start: 0, decay: 0.045` there is no
    pollution marker.
- [ ] **Step 2: Run** `node --test julia/test/js/` and `Pkg.test(test_args=["xxl_viewer"])`. Expected: FAIL.
- [ ] **Step 3: Implement.** Append the four keys to `POLLUTION_SERIES` (`read_period!` already copies by column
  name). The legend key. The two chart entries, using the file's existing colour constants (`BROWN` for rich land,
  `NEUTRAL` or the grey `#6b7280` for elsewhere). The marker label: `decays ${+(p.decay * 100).toFixed(1)}%` appended
  when `p.decay > 0`. In app.mjs, the legend's pollution section gets a line such as "decays 4.5% a period" when
  `decay > 0`.
- [ ] **Step 4: Run** `node --test julia/test/js/` and `Pkg.test(test_args=["xxl_viewer"])`. Expected: PASS. If a JS
  fixture (`fixture-legend.json`) is regenerated by the Julia tests, inspect its diff: only for a pollution legend may
  it gain `decay`; the existing fixture's `"pollution": null` must stay.
- [ ] **Step 5: Commit** "pollution-decay: viewer series, legend and the two charts".

### Task 5: Docs

**Files:**
- Modify: `docs/xxl.md` (section "VI-1 with pollution": a "Decay" part; the "Viewer" section's chart list)

- [ ] **Step 1:** In "VI-1 with pollution", add a part on the decay rule: what it does and where in the step, the
  default 0 and that the book has no such rule, Julia only, no scaling between worlds, the `VI-1-pollution-decay`
  settings table (as the spec's, with steps 1000), the rate's meaning (nine-tenths gone in 50 periods, half in about
  15, the world mean expected near 21), and how to run it (`--exp VI-1-pollution-decay`). Extend the
  `seed<k>-pollution.csv` column table with the four new columns (for every pollution experiment).
- [ ] **Step 2:** In "Viewer", add the two charts and the decay line in the legend and marker.
- [ ] **Step 3:** Check every line is at most 120 columns (`awk 'length > 120' docs/xxl.md` shows nothing new).
- [ ] **Step 4: Commit** "pollution-decay: docs".

After Task 5 the controller runs the full suite, a live check in the browser pane (a `VI-1-pollution-decay` run past
t = 450 with the ground on pollution and both new charts drawing, then the server stopped), and the final review.
