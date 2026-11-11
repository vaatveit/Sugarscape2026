# xxl Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A live browser viewer for today's xxl VI-1 runs: a Julia web server steps the real model and serves frames
(map, event marks, hover data) and per-period series to an ES-module page.

**Architecture:** A module `XxlViewer` in `julia/viewer/` (not included by `Sugarscape`, so studies and their load
time are untouched) holds four layers: a run (`ViewerRun`: the model, the combat readings and the series, stepped
exactly as the combat study steps a seed), frame capture and binary encoding, an HTTP.jl server with a background
stepper, and a static page in `julia/viewer/static/`. The page draws what the frames encode; every encoding table
(palettes, bands, steps) lives in Julia and reaches the page through `/api/legend`.

**Tech Stack:** Julia 1.10+, HTTP.jl 2.x (new dependency), Test stdlib; plain HTML/CSS/ES modules, no build step;
Node's built-in test runner for the page's modules.

**Spec:** `docs/superpowers/specs/2026-11-10-xxl-viewer-design.md`

## Global Constraints

- **Nothing the model did is changed or invented.** The viewer runs `step!`, `combat_period!` and `collect_metrics`
  in the study's order (`timed_seed`, julia/src/runner.jl: step, combat readings, metrics) and only *reads* the model
  otherwise. It must never touch `m.rng`.
- **The eight experiments, in order:** `VI-1-combat`, `VI-1-distance`, `VI-1-near`, `VI-1-far`, `VI-1-far-speed`,
  `VI-1-assim`, `VI-1-assim-random`, `VI-1-assim-k4`; default `VI-1-assim-k4`. Built with `JULIA_COMBAT_EXPS[id]()`.
- **Config:** `replace_config(world_config(exp, "today"); seed=raw_seed, combat_hostility=h, combat_curve=k)`. The
  model's own validation is the only check on h and k; its `ArgumentError` message is what the user sees.
- **Raw seed:** any integer ≥ 0. "= run index k" when `0 <= raw - base < exp.seeds`, base = `world_config(exp,
  "today").seed`.
- **Kept frames:** `VIEWER_KEEP = 100`. Marks cover the last `MARK_PERIODS = 10` periods, opacity `1 - age/10` for age
  0–9 (age 0 = the period shown).
- **One new package:** HTTP.jl (`[compat] HTTP = "2"`). No JSON package: responses are written by the viewer's own
  `to_json`; request bodies are form-encoded and read with `HTTP.queryparams`. Look up HTTP.jl in Context7
  (`/juliaweb/http.jl`) before writing code against it.
- **Server binds 127.0.0.1 only.**
- **Extensible lists (for the pollution experiment after v1):** experiments, colour modes (`COLOUR_MODES`) and series
  (`SERIES_KEYS`) are each one list; adding an entry must not need changes to the frame layout's existing fields or the
  page's structure.
- **No study run.** Tests run short runs (≤ 12 periods); the live check in Task 5 is the viewer itself.
- **Suite:** `julia --project=julia -e 'using Pkg; Pkg.test()'`; one area: `Pkg.test(test_args=["xxl_viewer"])`.
- **Line endings:** LF. Edit with the Edit tool or write with `newline=""`.

## Review Focus

1. **A paused page while the model runs ahead:** the period on screen must stay fetchable. The stepper waits while
   `newest_t - last_requested_t >= VIEWER_KEEP ÷ 2`. Test in Task 3 (`test_backpressure`).
2. **Starting a run while one is stepping:** the old stepper stops before the new run starts, and nothing from the old
   run is served under the new run's id (frame and series requests carry `run`; a stale id gets 409). Test in Task 3
   (`test_restart_replaces_run`).
3. **Extinction and undefined values:** a frame with 0 agents encodes and decodes; `gini`, `mean_price` and the Lorenz
   points are NaN there, sent as `null` and drawn as gaps; stepping stops with status `extinct`. Tests in Task 2
   (`test_empty_frame`), Task 3 (`test_series_nan_is_null`) and Task 4 (`charts gap on null`).
4. **Bad start requests** (unknown experiment, seed negative or not an integer, h or k not a number, h refused by the
   model): 400 with the message, and the current run carries on. Test in Task 3 (`test_bad_start_keeps_run`).
5. **Static files:** only files inside `julia/viewer/static/` are served; `..` paths get 404. Test in Task 3
   (`test_static_confined`).

---

### Task 1: The run and its series

**Files:**
- Create: `julia/viewer/XxlViewer.jl` (module; `using Sugarscape`, includes the files below as they are added),
  `julia/viewer/run.jl`
- Modify: `julia/Project.toml` (HTTP dep + compat; `Pkg.add` from `julia/`), `julia/Manifest.toml` if tracked
- Test: `julia/test/test_xxl_viewer_run.jl` (top: `isdefined(@__MODULE__, :XxlViewer) ||
  include(joinpath(@__DIR__, "..", "viewer", "XxlViewer.jl"))`, then `using .XxlViewer`)

**Interfaces — Produces:**
- `VIEWER_EXPS::Vector{String}` (the eight ids, in order), `DEFAULT_EXP = "VI-1-assim-k4"`.
- `struct ViewerSettings; exp_id::String; seed::Int; h::Float64; k::Float64; end`
- `viewer_defaults(exp_id)::ViewerSettings` (base seed, today h and k); `viewer_config(s)::Config` (throws
  `ArgumentError`, also for an id not in `VIEWER_EXPS`); `run_index(s)::Union{Int,Nothing}`.
- `SERIES_KEYS::Vector{String}` = `["t", "population", "n_blue", "n_red", "killed_blue", "killed_red",
  "tribe_changes", "gini", "trades", "mean_price", "n_loans", "total_debt", "fraction_sick"]`.
- `mutable struct ViewerRun` with at least `settings`, `model::Model`, `readings::CombatReadings`,
  `series::Dict{String,Vector{Float64}}`, `frames` (Task 2), `on_period` hook slot (Task 2 fills it).
- `ViewerRun(s::ViewerSettings)`: builds the model and reads period 0 (no step).
- `advance!(r)::Bool`: one period (step, readings, metrics, capture); `false` and no change when the population is
  already 0.
- `series_since(r, t0::Int)::Dict{String,Vector{Float64}}`: the values for periods `t0` to newest.
- `total_debt(m)::Float64 = sum(l.due for l in m.loans; init=0.0)`.

- [ ] **Step 1: Failing tests**
  - `test_viewer_settings`: `VIEWER_EXPS` equals the list above; `viewer_defaults("VI-1-assim-k4")` has
    `h == 0.5`, `k == 4.0`, seed == `world_config(VI-1-assim-k4, "today").seed`; `run_index` of base + 3 is 3, of
    base − 1 and base + exp.seeds is `nothing`; `viewer_config` with `h=0.3, k=2.0, seed=12345` has those values and
    `culture_rule == "distance"`; `h=1.0` on VI-1-assim and an unknown id throw `ArgumentError`.
  - `test_viewer_matches_study` (the anti-goal): `folder = run_combat_world("today", "VI-1-assim-k4"; seeds=1,
    first_seed=1, periods=12, out=mktempdir(), io=devnull)`; a `ViewerRun` of `viewer_defaults` with seed base + 1,
    advanced 12 times. For `population, n_blue, n_red, killed_blue, killed_red, tribe_changes` against
    `seed1-combat.csv` and `gini, trades, mean_price, n_loans, fraction_sick` against `seed1.csv`, all 13 rows:
    `isequal` per value (NaN equals NaN). At least one kill in the 12 periods (else the test proves little).
  - `test_total_debt`: after the 12 periods, `total_debt(m)` equals the hand sum over `m.loans` of `due`, and
    `series["total_debt"][end]` equals it.
  - `test_extinct_stops`: a `ViewerRun` after `empty!(r.model.agents)` returns `false` from `advance!` (it checks
    `isempty(m.agents)` before stepping, so the model is not stepped) and adds no series row.
- [ ] **Step 2:** `Pkg.test(test_args=["xxl_viewer"])` → FAIL (module missing).
- [ ] **Step 3:** Add HTTP.jl; implement. The period loop mirrors `timed_seed`'s: for t > 0 `step!(m)`, then
  `combat_period!(r.readings, m)`, then `collect_metrics(m)`; take each series value from the readings' newest row and
  the metrics row by column name (`metric_columns(m.config)`), never recomputed.
- [ ] **Step 4:** `["xxl_viewer"]` → PASS.
- [ ] **Step 5: Commit** `julia viewer: ViewerRun, a today-world run stepped as the combat study steps a seed`.

### Task 2: Frames: codes, events, Lorenz curve and the binary layout

**Files:**
- Create: `julia/viewer/encoding.jl`, `julia/viewer/frame.jl`, `julia/test/js/fixture-frame.bin` (written by the test
  below, committed)
- Modify: `julia/viewer/run.jl` (capture a frame each period into `r.frames`, newest `VIEWER_KEEP`),
  `julia/viewer/XxlViewer.jl`
- Test: `julia/test/test_xxl_viewer_frame.jl`

**Interfaces — Consumes:** Task 1's `ViewerRun`, `advance!`. **Produces:**
- `COLOUR_MODES = ["tribe", "culture", "wealth", "disease", "credit"]`.
- `WEALTH_EDGES = (1.0, 3.0, 10.0, 30.0, 100.0, 300.0, 1000.0, 3000.0)`; `wealth_band(w)::UInt8` in 0:8 (band 0
  below 1; band b for `WEALTH_EDGES[b] <= w < WEALTH_EDGES[b+1]`; band 8 at 3000 and above). Wealth = sugar + spice.
- `DISEASE_STEPS = (0, 1, 2, 3, 5, 8)`; `disease_step(n)::UInt8` in 0:5 (0, 1, 2, 3–4, 5–7, 8+).
- `tribe_code(a)::UInt8` (0 blue, 1 red, from `tribe(a)`), `culture_ones(a)::UInt8 = count_ones(a.tags)`.
- `ROLE_NONE, ROLE_LENDER, ROLE_BORROWER, ROLE_BOTH = 0, 1, 2, 3`; `credit_roles(m)::Dict{Int,UInt8}` from `m.loans`.
- `cell_eighths(level)::UInt8`: `8level`, throwing `ErrorException` unless it is an integer in 0:255 (the viewer
  refuses to draw a level it cannot show exactly).
- `legend(m_or_cfg)::Dict{String,Any}`: `"modes" => COLOUR_MODES`, `"palettes" => Dict(mode => ["#rrggbb", ...])`
  (`"tribe"` 2 colours `#2563eb` and `#c0392b`; `"culture"` 12, blue to red; `"wealth"` 9; `"disease"` 6, step 0
  neutral grey; `"credit"` 4), `"labels" => Dict(mode => [text per entry])`, `"wealth_edges"`, `"disease_steps"`, `"kill_colour" => "#000000"`, `"change_colour" => "#d4a000"`,
  `"mark_periods" => 10`, `"max_level"` (largest sugar or spice capacity of the landscape), `"ntags"`.
- `struct ViewerFrame` and `capture_frame(m, prev::Dict{Int,Symbol}, seen::Bool)::ViewerFrame`; call it after
  `step!` and **before** `combat_period!` (so `prev` is the readings' previous tribes). Kills: the cells of agents in
  `m.dead_this_step` whose id is in `m.killed`. Changes: living agents with `seen && haskey(prev, a.id) &&
  prev[a.id] != tribe(a)`, at their cell. Lorenz: 101 points, point i = wealth share of the poorest
  `round(Int, i * n / 100)` agents, i = 0:100 (all NaN when n = 0). Gini: `gini` of the same wealths.
- `encode_frame(f)::Vector{UInt8}`, little-endian, in this order (sections by element size, so typed-array views stay
  aligned):

  | Section | Type | Count |
  |---|---|---|
  | magic `"SXV1"`, t (Int32), width, height (UInt16), n_agents, n_kills, n_changes (UInt32), ntags (UInt8), 7 zero bytes | header | 32 bytes |
  | agent sugar, agent spice, lorenz, gini | Float64 | n, n, 101, 1 |
  | agent id | UInt32 | n |
  | agent x, y, tags, age, loans as lender, loans as borrower; kill x, kill y; change x, change y | UInt16 | n ×6, kills ×2, changes ×2 |
  | agent tribe, culture ones, wealth band, disease step, credit role, disease count | UInt8 | n ×6 |
  | cell sugar eighths, cell spice eighths (index `y * width + x`) | UInt8 | width·height ×2 |

  No padding beyond the header's: each section's start offset is already a multiple of its element size.

- [ ] **Step 1: Failing tests**
  - `test_codes`: `wealth_band` at 0, 0.99, 1, 2.99, 3, 2999.9, 3000, 1e9 → 0, 0, 1, 1, 2, 7, 8, 8;
    `disease_step` at 0, 1, 2, 3, 4, 5, 7, 8, 30 → 0, 1, 2, 3, 3, 4, 4, 5, 5; `cell_eighths(2.125) == 17`;
    `cell_eighths(0.1)` and `cell_eighths(40.0)` throw.
  - `test_legend`: one palette per `COLOUR_MODES` entry, sizes 2, 12, 9, 6, 4; colours distinct within each palette;
    `legend(cfg)["max_level"] == 4` on today's VI-1-assim-k4 landscape.
  - `test_frame_counts` (4 periods of a VI-1-assim-k4 `ViewerRun`, base seed): each kept frame has n_agents ==
    series population, n_kills == killed_blue + killed_red, n_changes == tribe_changes of its period; counts of roles
    1 or 3, 2 or 3, and 3 equal the period's `n_lenders`, `n_borrowers`, `n_both` from `collect_metrics`; frame
    gini ≈ series gini (rtol 1e-12); lorenz[1] == 0, lorenz[101] ≈ 1, non-decreasing.
  - `test_encode_layout`: a hand-built `ViewerFrame` (width 3, height 2, 2 agents, 1 kill, 1 change, known values)
    encodes to exactly the expected byte length and, read back by a decoder in the test file, to the same values;
    the test writes the bytes to `julia/test/js/fixture-frame.bin` and fails if the committed file differs.
  - `test_empty_frame`: a frame with 0 agents encodes and decodes; lorenz and gini are NaN.
  - `test_keep`: after `VIEWER_KEEP + 3` captures (use a small stand-in keep via a keyword, `keep=5`, on the run),
    only the newest are kept.
- [ ] **Step 2:** `["xxl_viewer"]` → FAIL.
- [ ] **Step 3:** Implement; `ViewerRun` gains `keep::Int = VIEWER_KEEP` and stores `encode_frame` bytes by t.
- [ ] **Step 4:** `["xxl_viewer"]` → PASS (Task 1's tests included).
- [ ] **Step 5: Commit** `julia viewer: frames, the codes, event marks, Lorenz curve and binary layout`.

### Task 3: The server and the background stepper

**Files:**
- Create: `julia/viewer/json.jl`, `julia/viewer/server.jl`
- Modify: `julia/viewer/XxlViewer.jl`
- Test: `julia/test/test_xxl_viewer_server.jl`

**Interfaces — Consumes:** Tasks 1–2. **Produces:**
- `to_json(x)::String` for `Dict`, `NamedTuple`, `AbstractVector`, `Real` (NaN and ±Inf → `null`; integers without
  `.0`), `AbstractString` (escaped), `Bool`, `nothing` → `null`.
- `start_viewer(; host="127.0.0.1", port=8765, autostep=true, keep=VIEWER_KEEP)` → a `ViewerServer` holding the `HTTP.serve!` server and
  the state; `stop_viewer(s)`; `step_once!(s)::Bool` (what the background stepper calls; tests call it with
  `autostep=false`).
- Routes (all JSON unless said):
  - `GET /` → `static/index.html`; `GET /static/{file}` → that file from `julia/viewer/static/` with a content type by
    extension; anything resolving outside that folder → 404.
  - `GET /api/experiments` → `[{id, title, seed, h, k, seeds}]` in `VIEWER_EXPS` order.
  - `GET /api/legend` → `legend(...)` for the current run (or the default experiment's config before any run).
  - `POST /api/start` (form body `exp`, `seed`, `h`, `k`) → `{run, settings, run_index}`; 400 `{error}` on any bad
    field or a model refusal, leaving the current run as it was. A good start stops the current stepper (waits for it)
    before building the new run; `run` is a new integer id.
  - `POST /api/stop` → stops stepping, keeps the run's frames and series.
  - `GET /api/status` → `{run, settings, run_index, newest, oldest_kept, state, error}` with state one of
    `"idle"`, `"running"`, `"waiting"` (backpressure), `"stopped"`, `"extinct"`, `"failed"`.
  - `GET /api/frame?run=&t=` → `application/octet-stream` frame bytes; 404 if not kept, 409 if `run` is not the
    current run. A frame request sets `last_requested_t = t`.
  - `GET /api/series?run=&from=` → `{run, t0, series: {key: [values]}}` for periods `from` to newest; 409 on a stale
    run.
- Stepper: one task (`Threads.@spawn`) per run; loop `step_once!` until stopped, extinct or failed; before each step,
  wait (sleep 0.05 s, re-check) while `newest - last_requested_t >= VIEWER_KEEP ÷ 2`. An exception sets state
  `"failed"` and `error` to `sprint(showerror, e)`. All shared state behind one `ReentrantLock`; frames are encoded
  inside `advance!`, so handlers only copy bytes under the lock.

- [ ] **Step 1: Failing tests** (server on port 0, `autostep=false`; requests with `HTTP.get` / `HTTP.post` and
  `status_exception=false`):
  - `test_to_json`: for `(a=[1.0, NaN, 2.5], s="q\"\n", n=nothing, b=true)` (a NamedTuple keeps key order) the
    result is the JSON text `{"a":[1,null,2.5],"s":"q\"\n","n":null,"b":true}`, where `\"` and `\n` are the two-character
    JSON escapes.
  - `test_experiments_and_index`: the ids in order; `GET /` returns HTML containing `<canvas`.
  - `test_start_frame_series`: start VI-1-assim-k4 at base seed; `step_once!` twice; `/api/frame?t=2` starts with
    `SXV1` and its t field is 2; `/api/series?from=0` has 3 values per key.
  - `test_series_nan_is_null`: in that series `mean_price[1]` is `null` in the raw JSON text (period 0 has no trades).
  - `test_bad_start_keeps_run`: with a run going, each of `exp=nope`, `seed=-1`, `seed=1.5`, `h=x`, and
    `exp=VI-1-assim&h=1` returns 400 with a non-empty `error` (the last one containing the model's message
    `combat_hostility`), and `/api/status` still shows the old run id.
  - `test_restart_replaces_run`: start, step, start again: the old run's id gets 409 on frame and series; the new
    run's frame 0 is served.
  - `test_backpressure`: with `keep=6` and frames requested only at t=0, the stepper (run `autostep=true` here,
    briefly) stops advancing at newest == 3 and state is `"waiting"`; requesting t=3 lets it continue.
  - `test_static_confined`: `/static/style.css` 200; `/static/../XxlViewer.jl` and `/static/%2e%2e/run.jl` 404.
- [ ] **Step 2:** `["xxl_viewer"]` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `["xxl_viewer"]` → PASS.
- [ ] **Step 5: Commit** `julia viewer: HTTP server, background stepper with backpressure, JSON API`.

### Task 4: The page

**Files:**
- Create in `julia/viewer/static/`: `index.html`, `style.css`, `app.mjs` (controls, fetching, play loop),
  `frame.mjs`, `map.mjs`, `charts.mjs`, `cache.mjs` (adapted from `viewer/static/cache.mjs`)
- Test: `julia/test/js/frame.test.mjs`, `julia/test/js/map.test.mjs`, `julia/test/js/charts.test.mjs`,
  `julia/test/test_xxl_viewer_js.jl` (runs `node --test julia/test/js/` from the repo root; skips with a note when
  `node` is missing; fails with node's output otherwise)

**Interfaces — Consumes:** Task 3's routes and Task 2's layout and legend. **Produces (exports):**
- `frame.mjs`: `decodeFrame(arrayBuffer)` → `{t, width, height, ntags, agents: {sugar, spice, id, x, y, tags, age,
  lent, owed, tribe, ones, wealth, disease, role, ndiseases}, kills: {x, y}, changes: {x, y}, lorenz, gini, cellSugar8,
  cellSpice8}` (typed-array views, no copies).
- `map.mjs`: `landscapeColour(s8, p8, maxLevel) → [r, g, b]` (fixed and one-to-one over all `s8, p8` in
  `0..8*maxLevel`, pale: every channel ≥ 150); `agentColour(frame, i, mode, legend) → "#rrggbb"` (the palette entry
  of the agent's code for that mode: tribe → `tribe`, culture → `ones`, wealth → `wealth`, disease → `disease`, credit
  → `role`); `markOpacity(age) = 1 - age / 10` for 0 ≤ age < 10, else 0; `drawMap(ctx, frame, recentFrames, mode,
  legend)` (landscape, agents one cell each, then crosses for kills and rings for changes from the frames of the last
  10 periods with their ages); `hitTest(frame, x, y)` → `{agent: {...exact values, tags as an 11-character 0/1 string,
  lent, owed}}` or `{cell: {sugar: s8 / 8, spice: p8 / 8}}`.
- `charts.mjs`: `linePath(values, xOf, yOf)` → segments split at `null` (gaps, never zero); `drawCharts(...)` for the
  seven charts of the spec plus the Lorenz curve; a marker at t = 500, a line at the period shown, and periods no
  longer kept for the map shaded; clicking a chart jumps to that period if kept.
- Page behaviour (spec, "What the user sees"): experiment select (from `/api/experiments`), raw seed, h and k fields
  filled from the experiment, the "= run index k" note, Start, Stop; play / pause / step back / step forward, speed
  limit (1, 2, 5, 10 per second, max), slider over kept periods; settings in force always shown; status line from
  `/api/status` (polled once a second) including errors and "waiting"; colour menu from `legend.modes`; legend for the
  active mode and the marks; hover read-out; y increasing upward.

- [ ] **Step 1: Failing tests** (node):
  - `frame.test.mjs`: `decodeFrame` on `fixture-frame.bin` gives the values Task 2's `test_encode_layout` built.
  - `map.test.mjs`: `landscapeColour` distinct over all pairs for `maxLevel = 4`, all channels ≥ 150;
    `agentColour` returns `legend.palettes[mode][code]` for each mode on the fixture; `markOpacity(0) == 1`,
    `markOpacity(9) ≈ 0.1`, `markOpacity(10) == 0`; `hitTest` on an agent's cell returns its exact sugar and its tags
    string, on an empty cell `{cell: ...}` with eighths divided by 8.
  - `charts.test.mjs`: `linePath([1, null, 2, 3], ...)` gives two segments; no segment passes through y of 0 for the
    null.
- [ ] **Step 2:** `["xxl_viewer"]` → FAIL.
- [ ] **Step 3:** Implement; adapt drawing, slider and pacing from `viewer/static/` where they fit.
- [ ] **Step 4:** `["xxl_viewer"]` → PASS.
- [ ] **Step 5: Commit** `julia viewer: the page, map with marks and colour modes, charts, hover`.

### Task 5: The command, docs, suite and a live check

**Files:**
- Create: `julia/xxl_viewer.jl` (`julia --project=julia --threads=2 julia/xxl_viewer.jl [--port 8765]`: includes the
  module, refuses with a one-line message if `Threads.nthreads() < 2`, starts the server, prints the URL, waits)
- Modify: `docs/xxl.md` (a short "Viewer" section: the command, what it shows, the faithfulness checks), `CLAUDE.md`
  or `julia/README` only if one already lists the Julia commands

- [ ] **Step 1:** Full suite → all pass; record the count.
- [ ] **Step 2: Live check** (controller): start the command in the background; open the URL in the browser pane;
  start VI-1-assim-k4 at the base seed; let it reach about t = 15; confirm: the map shows two tribes, crosses appear,
  every chart draws, hover reads an agent, the colour menu switches all five modes, a paused page keeps its frame
  while status shows "waiting", Start with h = 1 on VI-1-assim shows the model's message. Screenshot for the user.
  Stop the server.
- [ ] **Step 3: Commit** `julia viewer: xxl_viewer.jl command and docs`.
