# VI-1 with pollution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two VI-1 experiments with pollution and every other rule on (`VI-1-pollution`, `VI-1-pollution-t0`), their
pollution readings in the combat study, and the xxl viewer's pollution ground, pollution charts and legend fix.

**Architecture:** The experiments are built from `VI-1-assim-k4` in julia/src/xxl/vi1_combat.jl like the other VI-1
variants. The pollution readings ride on `CombatReadings` (filled by `combat_period!` only when the config has
pollution), so the study and the viewer read them from one place. The viewer frame gains one pollution-band byte per cell
(layout `SXV2`); the page maps bands to colours and never computes pollution itself.

**Tech Stack:** Julia 1.13 (package `Sugarscape` in julia/, module `XxlViewer` in julia/viewer/, HTTP.jl 2.x already in
use), browser ES modules in julia/viewer/static/, `node --test` for julia/test/js/.

**Spec:** docs/superpowers/specs/2026-11-11-vi1-pollution-design.md (read it first; this plan argues from it).

## Global Constraints

- Branch `vi1-pollution`; nothing merged or pushed. Commit after each task.
- Never start a study run (the `julia/xxl_*_study.jl` commands with real seeds/periods). Tests may call
  `run_combat_world` with a few periods into `mktempdir()`, as existing tests do.
- Never leave a viewer server running after a check.
- No rule change: `harvest!`, `metabolize!`, `diffuse!`, `step!` and the movement rules stay as they are.
- An experiment without pollution writes exactly the files it writes today, and its legend differs only by the new
  `"pollution" => nothing` entry.
- Existing tests change only where the spec's "Existing tests that change" says: the id lists in
  julia/test/test_vi1_reach.jl, `VIEWER_EXPS` in julia/test/test_xxl_viewer_run.jl, the chart count in
  julia/test/js/charts.test.mjs, the SXV1→SXV2 decoder in julia/test/test_xxl_viewer_frame.jl, and the regenerated
  fixtures in julia/test/js/ (`fixture-frame.bin`, `fixture-frame.json`, `fixture-legend.json`: delete, let
  test_xxl_viewer_frame.jl write them, inspect the diff).
- Before coding against HTTP.jl or any other dependency API, look it up with Context7 (no task here should need a new
  dependency call).
- Run a single Julia test file with: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["<name part>"])'`.
  Run the JS tests with: `node --test julia/test/js/` from the repository root.

## Review Focus

1. A pollution value of exactly 0 must be band 0 (white); a tiny positive value (from diffusion) must be band 1, never 0.
2. Switching the experiment menu between a pollution run and a non-pollution run: the ground menu, legend and charts
   must follow the run actually shown, never the previous one (the adoptRun bug).
3. "Ground shows: pollution" selected, then a non-pollution run adopted: the page must fall back to resources, not
   throw on a missing `cellPollution` palette.
4. A world with no agents: `agent_pollution` and `share_rich` are NaN (chart gaps), not 0 and not an error.
5. Pollution far above the last band edge (1000+) must draw as the last band, not throw.

Each has its test in the owning task (Task 3: 1, 4, 5; Task 5: 1, 3, 5; Task 4/5: 2).

---

### Task 1: The two experiments

**Files:**
- Modify: `julia/src/xxl/vi1_combat.jl` (append after `vi1_assim_k4_experiment`)
- Modify: `julia/src/xxl/combat_study.jl` (`JULIA_COMBAT_EXPS`, `COMBAT_USAGE`, the `combat_study_args` docstring)
- Create: `julia/test/test_vi1_pollution.jl`
- Modify: `julia/test/test_vi1_reach.jl` (the id list at lines 20–21 and the error-message list at line 71: add the two ids)

**Interfaces:**
- Produces: `VI1_POLLUTION_ID = "VI-1-pollution"`, `VI1_POLLUTION_T0_ID = "VI-1-pollution-t0"`,
  `vi1_pollution_experiment(reg=load_registry()) -> Experiment`, `vi1_pollution_t0_experiment(reg=load_registry()) -> Experiment`,
  both in `JULIA_COMBAT_EXPS`.

- [ ] **Step 1: Write the failing tests** in `julia/test/test_vi1_pollution.jl`, testset "VI-1 pollution experiments":

```julia
using Sugarscape, Test
using Sugarscape: JULIA_COMBAT_EXPS, world_config, vi1_assim_k4_experiment,
    vi1_pollution_experiment, vi1_pollution_t0_experiment

const VP_FIELDS = (:pollution, :pollution_start, :pollution_stop, :diffusion_period, :diffusion_start, :diffusion_passes)

for (build, id, start, dstart) in ((vi1_pollution_experiment, "VI-1-pollution", 350, 450),
                                   (vi1_pollution_t0_experiment, "VI-1-pollution-t0", 0, 0))
    e, k4 = build(), vi1_assim_k4_experiment()
    @test e.id == id && JULIA_COMBAT_EXPS[id]().id == id
    @test e.steps == 600 && e.seeds == k4.seeds
    for (world, passes) in (("book", 1), ("xl", 100), ("today", 100))
        c, b = world_config(e, world), world_config(k4, world)
        @test c.pollution == (1.0, 1.0)
        @test c.pollution_start == start && c.pollution_stop === nothing
        @test c.diffusion_period == 1 && c.diffusion_start == dstart && c.diffusion_passes == passes
        # everything else is VI-1-assim-k4's
        @test all(getfield(c, f) == getfield(b, f) for f in fieldnames(typeof(c)) if !(f in VP_FIELDS))
    end
    @test endswith(e.fingerprint, "\n") && occursin("variant: $id ", e.fingerprint)
    @test startswith(e.fingerprint, k4.fingerprint) && startswith(e.xl_fingerprint, k4.xl_fingerprint)
end
```

(If `getfield` comparison hits a field whose type has no `==`, compare `repr` of it instead; `xxl` settings are a struct.)

- [ ] **Step 2: Run** `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["vi1_pollution"])'`. Expected: FAIL, `vi1_pollution_experiment` not defined.
- [ ] **Step 3: Implement** in vi1_combat.jl: the two ids, two variant constants naming the settings (e.g.
  `"variant: VI-1-pollution pollution=(1,1) pollution_start=350 diffusion_period=1 diffusion_start=450 steps=600 (pollution on a settled society, then diffusion)\n"`),
  and the builders: `VI-1-assim-k4` with `replace_config(c; pollution=(1.0, 1.0), pollution_start=s, diffusion_period=1, diffusion_start=d)`
  on both configs, `steps = 600`, the variant appended to both fingerprints. Register both in `JULIA_COMBAT_EXPS`; add both
  ids to `COMBAT_USAGE` and the `combat_study_args` docstring; add both to test_vi1_reach.jl's two lists.
- [ ] **Step 4: Run** `Pkg.test(test_args=["vi1_pollution", "vi1_reach", "xxl_combat_study"])`. Expected: PASS.
- [ ] **Step 5: Commit** `vi1-pollution: VI-1-pollution and VI-1-pollution-t0 experiments`.

### Task 2: Pollution behaves in today's world

Tests only; the deposit arithmetic is already unit-tested (julia/test/test_movement.jl "test_pollution_formation_and_avoidance",
"test_no_pollution_before_start"; julia/test/test_xxl_speed.jl travel cost counts as consumption pollution;
julia/test/test_xxl_combat.jl combat's harvest). These tests check the combination in today's world.

**Files:**
- Modify: `julia/test/test_vi1_pollution.jl` (new testset "VI-1 pollution in today's world")

**Interfaces:**
- Consumes: Task 1's builders.

- [ ] **Step 1: Write the tests:**
  - `"identical to VI-1-assim-k4 before the start"`: `Model(world_config(vi1_pollution_experiment(), "today"))` and
    `Model(world_config(vi1_assim_k4_experiment(), "today"))`, `step!` both 3 times; the agents (sorted by id) have equal
    `id, x, y, sugar, spice, tags`; `m.landscape.sugar` equal; `sum(m.landscape.pollution) == 0`.
  - `"onset"`: today's config of `vi1_pollution_experiment()` with `replace_config(c; pollution_start=2, diffusion_start=10^6)`;
    after steps from t = 0 and 1, `sum(pollution) == 0`; after the step from t = 2 (the model now at t = 3), `sum(pollution) > 0`
    and every cell with pollution > 0 has pollution ≥ 0 (no negative values anywhere).
  - `"diffusion starts at its period"` (small config, no agents): `Config(; width=5, height=5, initial_population=0, pollution=(1.0, 1.0), diffusion_period=1, diffusion_start=2, diffusion_passes=1)`
    (adjust the keywords to whatever the config needs to build a model without agents); set `pollution[3, 3] = 4.0`;
    after the steps from t = 0 and 1, the field is unchanged; after the step from t = 2, `pollution[3, 3] == 0.0` and its four
    neighbours are `1.0`.
  - `"100 passes conserve the total"`: take the onset model above after 3 polluting steps, copy its pollution, run
    `diffuse!(ls)` 100 times; `isapprox(sum(after), sum(before); rtol=1e-12)` and `all(>=(0), after)`.
- [ ] **Step 2: Run** `Pkg.test(test_args=["vi1_pollution"])`. Expected: PASS (the model already implements this; if any
  fails, stop and report it: it is a finding, not something to fix by changing a rule).
- [ ] **Step 3: Commit** `vi1-pollution: tests that pollution behaves in today's world`.

### Task 3: Pollution readings and the study's file

**Files:**
- Modify: `julia/src/xxl/combat_readings.jl`
- Modify: `julia/src/xxl/combat_study.jl` (`combat_seed!`, the done/remove functions, `run_combat_world`)
- Create: `julia/test/test_xxl_pollution_readings.jl`

**Interfaces:**
- Produces:
  - `POLLUTION_COLUMNS = ["t", "mean_pollution", "agent_pollution", "share_rich"]`
  - `rich_cut(ls::Landscape) -> Int`: with `v = vec(ls.capacity .+ ls.spice_capacity)` sorted ascending and `n = length(v)`,
    `v[ceil(Int, 0.75n)]` (today's world: 5, covering 32% of cells).
  - `CombatReadings` gains `pollution_rows::Vector{Vector{Float64}}` (empty) and `rich::Union{Nothing,BitMatrix}`
    (`nothing` until first needed); `CombatReadings()` still takes no arguments.
  - `combat_period!(r, m)` additionally, when `m.config.pollution !== nothing`, pushes
    `[m.t, mean(pollution), mean of pollution[a.x+1, a.y+1] over agents (NaN if none), share of agents with rich[a.x+1, a.y+1] (NaN if none)]`
    to `r.pollution_rows`, with `r.rich = (capacity .+ spice_capacity) .>= rich_cut(ls)` set on first use.
    Without pollution it does nothing new.
  - `pollution_rows(r) -> (header, rows)` like `combat_rows`.
  - `pollution_path(folder, k) = joinpath(folder, "seed$k-pollution.csv")`.
  - `combat_seed_done(folder, k, periods; pollution::Bool=false)`: also requires the pollution table when `pollution`.

- [ ] **Step 1: Write the failing tests** in julia/test/test_xxl_pollution_readings.jl:
  - `rich_cut` on a hand landscape (e.g. 2×2 capacities `[0 1; 2 3]`, spice 0): cut `2`, mask `[0 0; 1 1]` as cells ≥ 2.
  - Readings on a small model with pollution set by hand and two agents placed by hand: `mean_pollution` equals
    `sum/ncells`, `agent_pollution` equals the mean of the two cells, `share_rich` equals the hand count / 2.
  - No agents (Review Focus 4): `agent_pollution` and `share_rich` are `NaN`.
  - A config without pollution: `r.pollution_rows` stays empty after `combat_period!`.
  - Study: `run_combat_world("today", "VI-1-pollution-t0"; seeds=1, first_seed=0, periods=3, out=mktempdir(), io=devnull)`
    writes `seed0-pollution.csv` with header `t,mean_pollution,agent_pollution,share_rich` and 4 rows; row t = 0 has
    `mean_pollution == 0`, a later row `> 0`; `run_combat_world("today", "VI-1-assim-k4"; ...periods=2...)` writes no
    pollution file. Rerunning the t0 study into the same folder skips the seed (done); deleting only its pollution file
    makes it run again.
- [ ] **Step 2: Run** `Pkg.test(test_args=["pollution_readings"])`. Expected: FAIL (`rich_cut` not defined).
- [ ] **Step 3: Implement** the interfaces above. In `combat_seed!`, write the pollution table (through `write_table_csv`,
  as the combat table is) when `world_config(exp, world).pollution !== nothing`; `run_combat_world` passes
  `(f, k, p) -> combat_seed_done(f, k, p; pollution=...)` as the done check; `remove_combat_seed` also removes the
  pollution file and its `.tmp`.
- [ ] **Step 4: Run** `Pkg.test(test_args=["pollution_readings", "xxl_combat_readings", "xxl_combat_study"])`. Expected: PASS.
- [ ] **Step 5: Commit** `vi1-pollution: pollution readings and the study's seed<k>-pollution.csv`.

### Task 4: Viewer, Julia side

**Files:**
- Modify: `julia/viewer/encoding.jl`, `julia/viewer/frame.jl`, `julia/viewer/run.jl`, `julia/viewer/server.jl`,
  `julia/viewer/XxlViewer.jl` (exports)
- Modify: `julia/test/test_xxl_viewer_run.jl` (the `VIEWER_EXPS` list; new testset), `julia/test/test_xxl_viewer_frame.jl`
  (decoder to SXV2 with the new section; new assertions); regenerate the three fixtures in julia/test/js/
- Test: `julia/test/test_xxl_viewer_server.jl` (new assertions on `/api/experiments`)

**Interfaces:**
- Consumes: Task 1's ids, Task 3's `pollution_rows`/`POLLUTION_COLUMNS`, `rich_cut`.
- Produces:
  - `POLLUTION_EDGES = (1.0, 3.0, 10.0, 30.0, 100.0, 300.0, 1000.0)`; `pollution_band(p::Real)::UInt8`: 0 iff `p == 0`,
    1 for `0 < p < 1`, then band b+1 for `EDGES[b] <= p < EDGES[b+1]`, 8 for `p >= 1000`. Nine bands, 0–8.
  - `ViewerFrame` gains `cell_pollution::Vector{UInt8}` (bands, index `y * width + x`), captured from
    `m.landscape.pollution`; `FRAME_MAGIC = b"SXV2"`; the section is appended after cell spice. It is all zeros without
    pollution.
  - `legend(m)` gains `"pollution" => nothing` without pollution, else
    `Dict("palette" => 9 colours, "labels" => ["0 (clean)", "below 1", "1 to < 3", ..., "1000 or more"], "edges" => collect(POLLUTION_EDGES), "start" => cfg.pollution_start, "diffusion_start" => cfg.diffusion_start (or nothing), "rich_cut" => rich_cut(ls), "rich_share" => share of cells rich)`.
    Palette: white `#ffffff` first, then a ramp through a muted tan to a dark olive-brown, chosen so Task 5's distance tests pass
    (every agent colour of every mode ≥ 60 RGB distance from every pollution colour; both mark colours distinct).
  - `VIEWER_EXPS` gains `"VI-1-pollution", "VI-1-pollution-t0"` at the end. `POLLUTION_SERIES = ["mean_pollution", "agent_pollution", "share_rich"]`;
    `series_keys(cfg) = cfg.pollution === nothing ? SERIES_KEYS : vcat(SERIES_KEYS, POLLUTION_SERIES)`; a `ViewerRun`'s
    `series` has exactly `series_keys(cfg)`; `read_period!` copies the three from `r.readings.pollution_rows[end]` by
    column name (never recomputed). `series_since` keeps working for both.
  - `/api/experiments` entries gain `steps` (the experiment's own) and `pollution::Bool`.

- [ ] **Step 1: Write the failing tests:**
  - test_xxl_viewer_frame.jl: `pollution_band` at `0.0 → 0`, `1e-300 → 1`, `0.999 → 1`, `1.0 → 2`, `999.9 → 7`, `1000.0 → 8`,
    `1e9 → 8` (Review Focus 1, 5); a frame of a `VI-1-pollution-t0` run after 2 steps: every cell's band equals
    `pollution_band(model pollution)`, and some are > 0; a `VI-1-assim-k4` frame's bands are all 0; the decoder reads
    `SXV2` and the new section; legend for k4 has `"pollution" => nothing`, for t0 has 9 palette entries, 9 labels,
    `rich_cut == 5`.
  - test_xxl_viewer_run.jl: `VIEWER_EXPS` list with the two new ids; new testset "pollution run matches the study":
    `run_combat_world("today", "VI-1-pollution-t0"; seeds=1, first_seed=1, periods=VW_STEPS, ...)`, a `ViewerRun` of the same
    seed advanced `VW_STEPS` times; for each of `POLLUTION_SERIES`, `all(isequal.(r.series[key], pollution_csv[key]))`;
    the existing series still equal the combat and standard CSVs; `sort(keys(r.series)) == sort(series_keys(r.model.config))`.
  - test_xxl_viewer_server.jl: `/api/experiments` has `steps == 600` and `pollution == true` for both new ids, `steps == 500`
    and `pollution == false` for `VI-1-assim-k4`.
- [ ] **Step 2: Run** `Pkg.test(test_args=["xxl_viewer"])`. Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above; update the `encode_frame` docstring's layout line.
- [ ] **Step 4: Regenerate fixtures**: delete `julia/test/js/fixture-frame.bin`, `fixture-frame.json`, `fixture-legend.json`;
  run `Pkg.test(test_args=["xxl_viewer_frame"])` to write them; check `git diff --stat` shows only those three changed
  among fixtures and the legend JSON's only new key is `"pollution"`.
- [ ] **Step 5: Run** `Pkg.test(test_args=["xxl_viewer", "vi1", "pollution"])`. Expected: PASS except the node test,
  which Task 5 fixes (frame.test.mjs still expects SXV1); note it and go on.
- [ ] **Step 6: Commit** `vi1-pollution: viewer frames, legend, series and experiments carry pollution`.

### Task 5: Viewer, page side

**Files:**
- Modify: `julia/viewer/static/frame.mjs`, `map.mjs`, `charts.mjs`, `app.mjs`, `index.html`, `style.css` (if needed)
- Modify: `julia/test/js/frame.test.mjs`, `map.test.mjs`, `charts.test.mjs` (chart count 7 → 9; new tests)

**Interfaces:**
- Consumes: Task 4's frame layout, legend `pollution` entry, `/api/experiments` `steps` and `pollution`, series keys.
- Produces:
  - `decodeFrame` reads `SXV2` (refuses `SXV1` with its existing "not a frame" error) and returns `cellPollution` (Uint8Array, cells).
  - `GROUNDS = [{value: "resources", label: "resources"}, {value: "pollution", label: "pollution"}]`;
    `paintMap(frame, mode, legend, ground = "resources")`: with `"pollution"` each cell is
    `legend.pollution.palette[frame.cellPollution[c]]`; throws if `legend.pollution` is null or a band has no colour.
    Agents on top as now. `drawMap(ctx, frame, marks, mode, legend, ground)` caches on `ground` too.
  - `hitTest` adds `cell.pollutionBand`.
  - `CHARTS` gains, at the end, `{id: "pollution", title: "Pollution", when: "pollution", panels: [{lines: [mean_pollution "whole world" #6b7280, agent_pollution "where agents stand" brown]}]}`
    and `{id: "rich", title: "On the richest land", when: "pollution", panels: [{fixed: 1, lines: [share_rich]}]}`;
    a chart with `when: "pollution"` is built only when the run's legend has `pollution`.
  - `drawChart(canvas, chart, series, view)`: `view.studyEnd` (the run's experiment `steps`) replaces `STUDY_END`; when
    `view.legend.pollution` is set, dotted vertical lines at `pollution.start` and `pollution.diffusion_start` (skipped
    when 0 or absent) on every chart, labelled "pollution on" / "diffusion on".
  - app.mjs: a "Ground shows" `<select id="ground">` in the legend's menus, shown only when `state.legend.pollution`;
    falls back to "resources" when a run without pollution is adopted (Review Focus 3); the legend section lists the nine
    bands under "Ground: pollution" when chosen; "Under the pointer" adds the cell's pollution band label; the
    "On the richest land" chart's caption says "cells with sugar + spice capacity ≥ {rich_cut}: {rich_share as %} of the world".
  - **adoptRun fix:** `adoptRun` sets `state.legend = null` and `state.frame = null`, rebuilds nothing until `loadLegend()`
    for that run resolves; `drawMapNow` and `drawCharts` already draw nothing without a legend. `loadLegend` then refills the
    colour menu, the ground menu and rebuilds the charts for the new legend.
  - charts note in index.html: "Dashed line: the period where the study stops (the experiment's steps)."

- [ ] **Step 1: Write the failing tests:**
  - frame.test.mjs: the regenerated fixture decodes with `cellPollution` equal to fixture-frame.json's values; an `SXV1`
    buffer is refused.
  - map.test.mjs: `paintMap(..., "pollution")` colours an empty cell of band b with `palette[b]`, band 0 white, band 8 the
    last colour (Review Focus 1, 5); an agent's cell keeps the agent colour; `paintMap(..., "pollution")` with a legend whose
    `pollution` is null throws; every agent colour of every palette ≥ 60 RGB distance from every pollution colour (same helper
    as the existing landscape test); both mark colours (kill black, switch gold) ≥ 60 RGB distance from every pollution colour; `hitTest` returns `pollutionBand`.
  - charts.test.mjs: `CHARTS.length === 9`; the two new charts have `when: "pollution"`; the study-end and start markers'
    x positions come from `view.studyEnd` and `view.legend.pollution` (test through whatever pure geometry helper exposes
    them; add one, e.g. `markerPeriods(view) -> [{t, kind}]`, if none does).
- [ ] **Step 2: Run** `node --test julia/test/js/`. Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** `node --test julia/test/js/` then `Pkg.test(test_args=["xxl_viewer"])`. Expected: PASS.
- [ ] **Step 5: Commit** `vi1-pollution: the page's pollution ground, charts and markers; adoptRun waits for the run's legend`.

### Task 6: Docs

**Files:**
- Modify: `docs/xxl.md`: after the VI-1 experiments' description (search "VI-1-assim-k4"; if they have no section, add
  "## VI-1 with pollution" before "## Viewer"): the two experiments, the spec's settings table, the timing note (first
  polluted row t = 351, first diffused t = 451), the checkerboard note, and `seed<k>-pollution.csv`'s columns and the
  rich-land cut. In "## Viewer": the "Ground shows" menu, the two charts, the markers, the study-end line from the
  experiment's steps; delete "Pollution comes with a later experiment."
- [ ] **Step 1: Edit** as above, in the doc's plain style.
- [ ] **Step 2: Commit** `vi1-pollution: docs`.

After Task 6 (the controller, not an implementer): full suite (`julia --project=julia -e 'using Pkg; Pkg.test()'`,
about 17 minutes, run in the background), whole-branch review subagents, and the live check in the browser pane
(`VI-1-pollution` past t = 350 on the pollution ground; switch to `VI-1-assim-k4` and back), stopping the viewer after.
