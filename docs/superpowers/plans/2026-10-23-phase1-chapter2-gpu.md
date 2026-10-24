# Sugarscape Chapter II on FLAME GPU 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CUDA C++ FLAME GPU 2 program that runs the Chapter II Sugarscape rules. Its per-period
metrics are scored by the Python Sugarscape2026 project's own targets, beside the Python model's
results, and it is benchmarked on tiled worlds up to the target size of 2500×2500 (about 1M agents).

**Architecture:** One executable, `sugarscape_gpu`, built from the FLAME GPU 2 C++ template.
- The landscape and occupancy live in 1D environment macro properties. There are `cell` and `citizen`
  agent types.
- Movement conflicts are resolved in a sub-model, by rounds of atomic `max` claims.
- Metrics are computed on the host and written as CSV.
- A Python bridge converts registered `Config`s to `run.cfg` files, runs the program per seed, and
  scores the results with `replication.report.evaluate`.
- Tests are pytest, driving the built program. Rule tests compare the program step by step with the
  Python model, on states where sequential and parallel updating must agree.

**Tech Stack:**
- C++20 / CUDA 13.0, FLAME GPU 2 `v2.0.0-rc.5` (fetched by CMake);
- Visual Studio 2022 generator, with the CMake 3.31 bundled in VS;
- Python 3.14 with numpy, matplotlib and pytest in `C:\Projects\FlameGPU\.venv`;
- the Sugarscape2026 Python packages, imported from `SUGARSCAPE_ROOT`.

**Spec:** `docs/superpowers/specs/2026-10-23-phase1-chapter2-gpu-design.md` (read it first; this plan
argues from it).

## Global Constraints

- **FLAME GPU and the build.**
  - FLAME GPU `v2.0.0-rc.5`, set as `FLAMEGPU_VERSION` in `CMakeLists.txt`.
  - `CMAKE_CUDA_ARCHITECTURES=89`.
  - Telemetry off: CMake option `FLAMEGPU_SHARE_USAGE_STATISTICS=OFF`, and env
    `FLAMEGPU_SHARE_USAGE_STATISTICS=OFF` in tests and the bridge.
  - Two build trees:
    - `build/` with `FLAMEGPU_SEATBELTS=ON`: tests and validation;
    - `build-fast/` with `FLAMEGPU_SEATBELTS=OFF`: the benchmark only.
  - The executable is `build/bin/Release/sugarscape_gpu.exe`. Override with env `SUGARSCAPE_GPU_EXE`.
- **The Python project.** `SUGARSCAPE_ROOT` (default `C:\Projects\Sugarscape2026`) is read-only. Never
  write inside it. Its saved results are read from `SUGARSCAPE_ROOT/results`.
- **Macro properties.** Within one layer, a macro property is either only read or only atomically
  written (`exchange`, `max`, `+=`/`addAtomic`), never both. This holds across all functions in the layer.
- **FLAME GPU APIs.** Before writing code against an API, check it in Context7 (`/websites/flamegpu`
  or `/flamegpu/flamegpu2`) for rc.5. If it differs from the plan, keep the spec's behaviour and adapt
  the call.
- **Exit codes:** 0 ok; 2 usage, config or map error (message on stderr naming the key or file); 3 an
  invariant was violated under `--check`; 4 a runtime limit was exceeded (movement rounds > 4095).
- **CSV format.**
  - Header `t,population,mean_vision,mean_metabolism,mean_sugar,gini,mean_neighbors,moved,ne_fraction,on_peak_fraction,north_frac_high_vision,north_frac_low_vision,summer_north`.
  - Numbers are written with `%.17g`, and nan as `nan`, so they read back with
    `experiments.run._parse`.
- **Python version.** The bridge and tests run with `C:\Projects\FlameGPU\.venv\Scripts\python.exe`
  (Python 3.14).
- **Git.** This folder becomes a git repository in Task 1. Commit only with the user's approval; the
  commit steps below assume it was given.

## Review Focus

1. A lattice with every site occupied: nobody can move. Every agent should stay, harvest its own
   site, and the run should continue without errors (Task 3, `test_full_lattice_everyone_stays`).
2. Extinction partway through a run: later rows should have population 0 and nan for every mean and
   fraction, gini nan, `moved` 0, and exit 0 (Task 6, `test_extinction_rows_are_nan`).
3. Vision at the largest allowed value near the torus edges: scans should wrap without reaching the
   agent's own site from the other side (Task 3, parity case `wrap_max_vision`).
4. Broken map files (wrong size, non-integer token, ragged rows): exit 2 with the file and line
   named (Task 2, `test_bad_map_is_rejected`).
5. A world bigger than the compiled maximum (`--tile 51`, i.e. 2550×2550): exit 2 naming `SUGARSCAPE_MAX_CELLS`
   (Task 2, `test_world_over_max_cells_is_rejected`).

---

## File structure

```
CMakeLists.txt                # template's, project sugarscape_gpu, rc.5, SUGARSCAPE_MAX_CELLS option
cmake/flamegpu2.cmake         # template's, unchanged
.gitignore, LICENSE.MD, CPPLINT.cfg   # template's (.gitignore adds results-gpu/, .venv/, build-fast/)
src/main.cu                   # argument parsing, config/map load, population, run, CSV/timing output
src/config.h, src/config.cu   # RunConfig, parse_config(), validate()
src/landscape_io.h, .cu       # load_map(), tile_map(), load_init_agents()
src/model.h, src/model.cu     # build_model(): env, macro properties, agents, layers, sub-model
src/movement.cuh              # scan / resolve agent functions + sub-model exit condition
src/rules.cuh                 # start_period, count_neighbors, metabolize_and_age, cell layers A/B
src/host_state.h, .cu         # RunState (globals for host functions), init fn, replacement, step fn
src/metrics.h, src/metrics.cu # AgentColumns, MetricsRow, compute_metrics(), CSV writer
src/checks.cu                 # --check invariants, --dump-agents / --dump-landscape writers
bridge/paths.py               # SUGARSCAPE_ROOT on sys.path, exe location, env for subprocesses
bridge/config_cfg.py          # unsupported_features(), config_to_cfg()
bridge/gpu_run.py             # CLI: run experiments on the GPU
bridge/gpu_report.py          # CLI: score GPU + Python results, write results-gpu/REPORT.md
bridge/bench.py               # CLI: tiling sweep, bench.csv + bench.png
tests/conftest.py             # exe fixture, tmp run helpers
tests/gpu.py                  # run_gpu(): write cfg/map/init, run exe, read dumps/CSV
tests/reference.py            # run_python(): same scenario through sugarscape.model.Model
tests/test_cli.py, test_parity.py, test_invariants.py, test_metrics.py, test_bridge.py, test_report.py
docs/validation/phase1-chapter2.md   # Task 9's findings
README.md
```

---

### Task 1: Scaffold the project and build a stub executable

**Files:**
- Create: `CMakeLists.txt`, `cmake/flamegpu2.cmake`, `.gitignore`, `LICENSE.MD` and `CPPLINT.cfg`,
  copied from the template clone at
  `C:\Users\genev\AppData\Local\Temp\claude\C--Projects-FlameGPU\4e68d26f-8cc5-409f-af1e-27bc99662d3a\scratchpad\repo\template-cpp`
  (re-clone `https://github.com/FLAMEGPU/FLAMEGPU2-model-template-cpp` if it is gone).
- Create: `src/main.cu`, `tests/conftest.py`, `tests/test_cli.py`, `bridge/paths.py`, `README.md` (build
  section only).

**Interfaces:**
- Produces:
  - the target `sugarscape_gpu`;
  - `bridge.paths`: `SUGARSCAPE_ROOT: Path`, `EXE: Path`, `subprocess_env() -> dict[str, str]`
    (os.environ plus telemetry OFF);
  - the pytest fixture `exe` (a Path; the session is skipped with a "build first: <cmake command>"
    message if missing).

- [ ] **Step 1: Check the prerequisites.** Run `nvcc --version` (expect release 13.0) and
  `echo $CUDA_PATH`. If either is missing, stop and ask the user. Do not install anything.
- [ ] **Step 2: Copy the template files and edit `CMakeLists.txt`.**
  - Set `FLAMEGPU_VERSION` to `v2.0.0-rc.5` and the project name to `sugarscape_gpu`.
  - Set `ALL_SRC` to the `src/*.cu` files that exist.
  - Add `set(SUGARSCAPE_MAX_CELLS 6250000 CACHE STRING "Largest width*height the macro properties hold (2500x2500)")`,
    passed as `target_compile_definitions(... SUGARSCAPE_MAX_CELLS=${SUGARSCAPE_MAX_CELLS}u)`.
  - Set `VS_DEBUGGER_COMMAND_ARGUMENTS` to `--help`.
  - Append `results-gpu/`, `.venv/` and `build-fast/` to `.gitignore`.
- [ ] **Step 3: Write the failing test** `tests/test_cli.py::test_help_lists_options`: `exe --help`
  exits 0, and stdout contains each of `--config`, `--out`, `--init`, `--metrics-every`,
  `--dump-agents`, `--dump-landscape`, `--dump-at`, `--tile`, `--timing` and `--check`.
- [ ] **Step 4: Create the venv.** Run `python -m venv .venv` and
  `.venv\Scripts\python -m pip install numpy matplotlib pytest`. Run `.venv\Scripts\python -m pytest
  tests/test_cli.py`. Expected: skipped, with the build-first message.
- [ ] **Step 5: Implement the `src/main.cu` stub.** It prints the usage text listing those options on
  `--help`, and exits 2 with the usage text on unknown or no arguments. It includes
  `flamegpu/flamegpu.h` so the build exercises FLAME GPU.
- [ ] **Step 6: Configure and build.** The first build compiles FLAME GPU and takes a while:
  ```
  "C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_CUDA_ARCHITECTURES=89 -DFLAMEGPU_SEATBELTS=ON -DFLAMEGPU_SHARE_USAGE_STATISTICS=OFF
  "<same cmake>" --build build --config Release --target sugarscape_gpu --parallel 8
  ```
  Expected: `build/bin/Release/sugarscape_gpu.exe` exists. If the output folder differs, fix
  `bridge.paths.EXE` and the README to the real path.
- [ ] **Step 7: Run the test.** `pytest tests/test_cli.py -v` → PASS.
- [ ] **Step 8: Commit.** Run `git init`, then commit everything except ignored paths with the message
  `chore: scaffold sugarscape_gpu from FLAME GPU 2 C++ template (rc.5)`.

### Task 2: Run config, map loading, tiling and CLI errors

**Files:**
- Create: `src/config.h`, `src/config.cu`, `src/landscape_io.h`, `src/landscape_io.cu`.
- Modify: `src/main.cu`, `tests/test_cli.py`.

**Interfaces:**
- Produces (C++):
  - `struct IntRange { int lo, hi; };`
  - `struct RunConfig` with fields:
    - width, height (int);
    - map_path (std::string);
    - initial_population (int);
    - placement (`"random"` | `"block"`);
    - block (int[4]: x0, y0, w, h);
    - vision, metabolism, endowment (IntRange);
    - max_age (std::optional<IntRange>);
    - founder_ages (`"uniform"` | `"zero"`);
    - replacement (bool);
    - growback_rate (double, `INFINITY` for inf);
    - seasons (std::optional<std::pair<int,int>>: beta, gamma);
    - winter_growback (`"fractional"` | `"pulse"`);
    - pollution (std::optional<std::pair<double,double>>: alpha, beta);
    - pollution_start (int), pollution_stop (std::optional<int>);
    - diffusion_period (std::optional<int>), diffusion_start (int);
    - steps (int), seed (uint64_t);
    - tile (int, default 1).
  - `RunConfig parse_config(const std::string& path)`: throws `ConfigError` (a `std::runtime_error`)
    naming the key and line.
  - `void apply_tile(RunConfig&, int k)`.
  - `void validate(const RunConfig&)`: Python's `Config.__post_init__` rules for these fields, plus
    `width*height <= SUGARSCAPE_MAX_CELLS`.
  - `std::vector<uint32_t> load_map(const std::string& path, int width, int height)`: indexed
    `x + y*width`, first line = northernmost row (y = height-1). Throws `MapError` naming the file and
    line.
  - `std::vector<uint32_t> tile_map(const std::vector<uint32_t>&, int w, int h, int k)`.
- `run.cfg` grammar: one `key = value` per line; `#` comments; blank values mean None; ranges `lo,hi`;
  booleans `true`/`false`; `inf` allowed only for `growback_rate`.

- [ ] **Step 1: Write the failing tests** in `tests/test_cli.py`. They use a helper `write_cfg(tmp_path,
  **overrides)` that writes a valid II-4-like `run.cfg` (50×50, the Python project's `sugar-map.txt`
  path) and returns its path. All run `exe --config <cfg> --print-config`:
  - `test_print_config_round_trips`: exit 0, and stdout has `width = 50`, `growback_rate = 1`,
    `max_age =` (empty) and `map_cells = 2500`.
  - `test_unknown_key_is_rejected`: `colour = red` → exit 2, and stderr contains `colour`.
  - `test_unsupported_feature_key_is_rejected`: `sex = true` → exit 2, and stderr contains `sex`.
  - `test_vision_too_large_is_rejected`: `vision = 1,25` on 50×50 → exit 2, stderr contains `vision`.
  - `test_replacement_needs_max_age`: `replacement = true` with `max_age` blank → exit 2.
  - `test_bad_map_is_rejected`: three cases, each exit 2 with the map file name in stderr — a map with
    49 rows, a row containing `x`, and a ragged row.
  - `test_tile_scales_world`: `--tile 2` → stdout has `width = 100`, `height = 100`,
    `initial_population = 1600` and `map_cells = 10000`, and `map_capacity_sum` is 4× the untiled
    value.
  - `test_world_at_max_cells_is_accepted`: `--tile 50` → exit 0, `width = 2500`, `map_cells = 6250000`.
  - `test_world_over_max_cells_is_rejected`: `--tile 51` → exit 2, and stderr contains
    `SUGARSCAPE_MAX_CELLS`.
- [ ] **Step 2: Run them.** `pytest tests/test_cli.py -v` → the new tests FAIL (unknown option
  `--print-config`).
- [ ] **Step 3: Implement** `parse_config`, `apply_tile`, `validate`, `load_map` and `tile_map`. Then
  add `--print-config` to `main.cu`, which prints the effective config (after tiling) as `key = value`,
  plus `map_cells` and `map_capacity_sum`. `main` maps `ConfigError`/`MapError` to exit 2.
- [ ] **Step 4: Run the tests.** `pytest tests/test_cli.py -v` → all PASS.
- [ ] **Step 5: Commit.** Message: `feat: run.cfg parsing, map loading, tiling and validation`.

### Task 3: The model — initialisation, movement sub-model, metabolism, aging, growback; Python parity

**Files:**
- Create: `src/model.h`, `src/model.cu`, `src/movement.cuh`, `src/rules.cuh`, `src/host_state.h`,
  `src/host_state.cu`, `src/checks.cu`, `tests/gpu.py`, `tests/reference.py` and
  `tests/test_parity.py`.
- Modify: `src/main.cu`, `src/landscape_io.*` (add `load_init_agents`).

**Interfaces:**
- Consumes: `RunConfig`, `load_map`, `tile_map` (Task 2).
- Produces (C++):
  - `flamegpu::ModelDescription build_model(const RunConfig&)`.
  - Environment properties: `width`, `height` (uint32), `growback_rate` (float; `INFINITY` allowed),
    `pollution_alpha`, `pollution_beta` (float), `pollution_active` (uint32, set by a host function at
    the start of each period from t), `diffuse_now` (uint32, likewise), `t` (uint32, the period index
    before the increment), `seasons_beta`, `seasons_gamma` (uint32, 0 = off) and `winter_pulse`
    (uint32).
  - Macro properties (1D, `SUGARSCAPE_MAX_CELLS`): `capacity` (uint32), `sugar`, `sugar_next`,
    `pollution`, `pollution_next` (float), `occupied` (uint32) and `claim` (uint64).
  - Citizen variables:
    - `x`, `y`, `vision`, `metabolism`, `age` (int);
    - `max_age` (int; `INT_MAX` = immortal);
    - `sugar` (float);
    - `moved`, `neighbors`, `settled` (uint32);
    - `priority` (uint32, 20 bits used);
    - `target` (uint32 site index).
  - `struct InitAgent { int x, y, vision, metabolism; float sugar; int age; std::optional<int> max_age; };`
    and `std::vector<InitAgent> load_init_agents(const std::string&)`. The CSV header is
    `x,y,vision,metabolism,sugar,age,max_age`, with `max_age` blank for immortal.
  - `RunState` (in `host_state.h`): the config, the capacity vector, a `std::mt19937_64 rng`
    (seeded from `seed`), the previous population, and the output options. It is reached by host
    functions through `RunState& state()`.
  - Dump CSVs (written in `checks.cu`, at t = `--dump-at`, after that period's end; t = 0 means after
    initialisation):
    - agents: `x,y,vision,metabolism,sugar,age,max_age,moved,neighbors`, sorted by (x, y);
    - landscape: `x,y,capacity,sugar,pollution,occupied`, sorted by (x, y).
- Produces (Python tests):
  - `tests/gpu.py: run_gpu(exe, tmp, cfg: dict, capacity: np.ndarray | None, agents: list[dict] | None,
    steps: int, dump_at: int, extra_args=()) -> Dump`, with
    `Dump(agents: list[dict], landscape: dict[(x,y), dict], csv: list[dict] | None, returncode, stderr)`.
    `capacity` (indexed [x, y]) is written as a map file in `load_map`'s orientation.
  - `tests/reference.py: run_python(cfg: dict, capacity, agents, steps) -> Dump`. It builds a
    `sugarscape.config.Config` with `initial_population=0`, then `Model(config, capacity)`, then calls
    `model.new_agent(...)` and sets `.age` for each agent, then runs `steps` periods and reads
    `model.agents` and `model.landscape` into the same `Dump` shape.

- [ ] **Step 1: Write the failing parity tests** in `tests/test_parity.py`.
  - **Shared setup.** A 20×20 capacity map:
    `capacity = (np.random.default_rng(1).permutation(400) + 2).reshape(20, 20)`. All values are
    distinct and ≥ 2, so no two sites tie.
  - **Agents.** 4 agents at (2,2), (12,2), (2,12) and (12,12), each with vision ≤ 3. They are 10 apart,
    more than `2*3 + 1`, so they never interact and Python's random order cannot matter.
  - **`test_matches_python` parametrized cases:**
    - `g1_move` (G1, vision 1–3, 3 steps);
    - `g_inf` (`growback_rate = inf`, 5 steps);
    - `wrap_max_vision`: one agent only, at (0,19), with vision 9 (its lines cover almost the whole
      row and column); G_inf, 3 steps;
    - `starvation` (metabolism 500, sugar 1: more than any site can give, so dies at t=1);
    - `max_age_death` (max_age 2, no replacement: everyone gone after t=2).
  - **Comparison.** Equal sets of agents by (x, y, vision, metabolism, age), with sugar equal within
    1e-5. At every site, landscape sugar is equal within 1e-5 and `occupied` equals the agent positions.
  - **Two GPU-only tests:**
    - `test_conflict_one_winner`: 10×10 map of zeros except capacity 9 at (5,5), with agents at (3,5)
      and (7,5), vision 2, metabolism 1, sugar 10. After 1 step, exactly one agent is at (5,5) with
      sugar 18, the other is at its start with sugar 9, and `occupied` has exactly two 1s.
    - `test_full_lattice_everyone_stays`: 10×10 map of capacity 3 everywhere, vision 1–4,
      `initial_population = 100`, endowment 25–50. After 1 step every agent has `moved == 0`, there are
      100 agents, and every site's sugar is 1 (harvested, then G1 growback).
  - **Two initialisation tests**, read from the t = 0 dump:
    - `test_block_placement`: 50×50, `placement = block`, `block = 0,0,20,20`, 400 agents → 400 agents
      on distinct sites, all with x < 20 and y < 20.
    - `test_founder_ages_uniform`: the II-4-gini config → every age < its max_age, and not all ages
      are 0. With `founder_ages = zero`, all ages are 0.
- [ ] **Step 2: Run them.** `pytest tests/test_parity.py -v` → FAIL (exe has no `--init`/dumps).
- [ ] **Step 3: Implement initialisation.**
  - The population is built in `main` with `std::mt19937_64(seed)` as the spec describes, or loaded
    from `--init`.
  - It is passed in with `CUDASimulation::setPopulationData`.
  - An init host function writes `capacity`, `sugar = capacity` and `occupied` into the macro
    properties. It also creates one `cell` agent per site, with a `cell` variable `index`.
  - Device RNG seed = `seed` (via the simulation config's random seed).
- [ ] **Step 4: Implement the period layers.** Follow the spec's "One period" steps 1–4 and 7–8, with
  growback G_α/G_∞ only (seasons and pollution come in Task 4: give those properties their off values).
  - `movement.cuh`: `scan` and `resolve` follow the spec, with the key layout
    `(uint64)round << 52 | (uint64)(priority & 0xFFFFF) << 32 | id`. A random direction order comes
    from a Fisher–Yates shuffle of 4 with `FLAMEGPU->random`.
  - Sub-model: citizens bound with auto-mapped variables, and the needed macro and environment
    properties mapped. Exit condition: `count("settled", 0u) == 0`. Rounds over 4095 → the host sets
    an error flag, and `main` exits 4.
  - Cells only compute `sugar_next` and copy it back in this task.
- [ ] **Step 5: Implement the dumps.** `--dump-agents FILE`, `--dump-landscape FILE` and `--dump-at T`,
  written from the step function (or from `main` for T = 0). Also implement `--check`, which runs the
  spec's invariants each period and exits 3 with a message on the first violation.
- [ ] **Step 6: Run the tests.** `pytest tests/test_parity.py -v` → all PASS. Investigate any mismatch
  against the Python rule source (`sugarscape/rules/movement.py`, `sugarscape/model.py`); never relax a
  tolerance to pass.
- [ ] **Step 7: Commit.** Message: `feat: GPU model with movement sub-model, metabolism, aging, growback`.

### Task 4: Seasons, pollution and diffusion

**Files:**
- Modify: `src/rules.cuh`, `src/movement.cuh`, `src/host_state.cu`, `tests/test_parity.py`.

**Interfaces:**
- Consumes: Task 3's environment properties and dumps.

- [ ] **Step 1: Add the failing parity cases** to `test_matches_python`. The four standard agents
  already put 2 north (y = 12) and 2 south (y = 2):
  - `seasons_fractional` (`seasons = 4,3`, `winter_growback = fractional`, 7 steps);
  - `seasons_pulse` (same, `pulse`);
  - `pollution` (`pollution = 1.0,1.0`, `pollution_start = 1`, `pollution_stop = 3`, 5 steps; also
    compare landscape pollution within 1e-4 relative);
  - `pollution_diffusion` (`pollution = 1.0,1.0`, `diffusion_period = 2`, `diffusion_start = 1`, 6 steps).
- [ ] **Step 2: Run them.** `pytest tests/test_parity.py -v` → the four new cases FAIL.
- [ ] **Step 3: Implement the rules.**
  - The start-of-period host function sets `t`, `pollution_active` and `diffuse_now` from the spec's
    conditions.
  - Seasonal growback in cell layer A (north = `y >= height/2`; summer north when
    `t % (2*gamma) < gamma`).
  - Harvest pollution in `resolve`; consumption pollution in `metabolize_and_age`.
  - `pollution_next` in layer A, and the copy in layer B.
- [ ] **Step 4: Run the tests.** `pytest tests/test_parity.py -v` → all PASS.
- [ ] **Step 5: Commit.** Message: `feat: seasonal growback, pollution formation and diffusion`.

### Task 5: Replacement, invariants and determinism

**Files:**
- Modify: `src/host_state.cu`, `src/checks.cu`.
- Create: `tests/test_invariants.py`.

- [ ] **Step 1: Write the failing tests:**
  - `test_replacement_keeps_population`: the II-4-gini config (`initial_population = 250`,
    `max_age = 60,100`, `replacement = true`, 50×50, 120 steps, `--check`). Exit 0, and population =
    250 at every row. Metrics come in Task 6, so this task reads the population from
    `--dump-agents` at t = 120 and relies on `--check`'s accounting.
  - `test_invariants_hold` (parametrized over seeds 0–4 and three configs: II-4, II-8 and II-4-gini,
    150 steps, `--check`): exit 0.
  - `test_same_seed_same_result`: two runs of II-4 with seed 7, 60 steps, give byte-identical agent and
    landscape dumps at t = 60. Different seeds (7 and 8) give different dumps.
- [ ] **Step 2: Run them.** `pytest tests/test_invariants.py -v` → `test_replacement_keeps_population`
  FAILS.
- [ ] **Step 3: Implement the replacement host function** (the spec's step 6), with deaths = previous
  population − current count. Empty sites are listed from the host copy of `occupied` and chosen
  uniformly without replacement. Draws use `state().rng`. Each new agent's site is written into
  `occupied`.
- [ ] **Step 4: Run the tests.** `pytest tests/test_invariants.py -v` → all PASS. If the determinism
  test fails, find the source of non-determinism (for example an atomic float `+=` ordering in
  pollution) and make that path deterministic. If it truly cannot be, ask before weakening the test.
- [ ] **Step 5: Commit.** Message: `feat: replacement R, invariant checks, determinism test`.

### Task 6: Metrics CSV

**Files:**
- Create: `src/metrics.h`, `src/metrics.cu`, `tests/test_metrics.py`.
- Modify: `src/host_state.cu`, `src/main.cu`.

**Interfaces:**
- Produces:
  - `struct AgentColumns { std::vector<int> x, y, vision, metabolism; std::vector<float> sugar;
    std::vector<uint32_t> moved, neighbors; };`
  - `struct MetricsRow { unsigned t; double population, mean_vision, mean_metabolism, mean_sugar, gini,
    mean_neighbors, moved, ne_fraction, on_peak_fraction, north_frac_high_vision, north_frac_low_vision,
    summer_north; };`
  - `MetricsRow compute_metrics(const AgentColumns&, const RunConfig&, const std::vector<uint32_t>&
    capacity, unsigned t)`, following `standard_metrics` field by field (the spec's Metrics section).
  - `class CsvWriter { explicit CsvWriter(const std::string& path); void write(const MetricsRow&); }`
    writes the Global Constraints header and format.
  - `--out FILE` and `--metrics-every N` (default 1).

- [ ] **Step 1: Write the failing tests:**
  - `test_columns_and_rows`: II-4, 10 steps → the header equals the constraint's header, and t runs
    0…10.
  - `test_metrics_every`: `--metrics-every 5`, 12 steps → t values [0, 5, 10].
  - `test_metrics_match_dump` (parametrized t ∈ {0, 7}, II-4 and II-7 configs): recompute every column
    from `--dump-agents`/`--dump-landscape` at t with Python's formulas. That means
    `sugarscape.stats.gini` and `safe_mean`, the `standard_metrics` definitions, and `summer_north`
    from `Landscape.is_summer_north`. Each must equal the CSV row (`math.isclose(rel_tol=1e-9)`, or
    both nan).
  - `test_extinction_rows_are_nan`: metabolism 4,4, endowment 1,1, sugar map of all 0, 5 steps →
    exit 0; rows t ≥ 1 have population 0, moved 0, and nan in every other metric (except
    `summer_north`, nan without seasons).
  - `test_csv_reads_back`: `experiments.run._read_csv` of the output gives ints/floats/nan, and
    `replication.targets.window_mean("population", 0, 10)` of it is a finite number.
- [ ] **Step 2: Run them.** `pytest tests/test_metrics.py -v` → FAIL.
- [ ] **Step 3: Implement.** `main` writes row 0 from the initial `AgentVector`. The step function
  builds `AgentColumns` from `getPopulationData()` on the periods where t % N == 0, and writes the row.
- [ ] **Step 4: Run the tests.** `pytest tests -v` → all PASS (the whole suite, since this touches the
  step function).
- [ ] **Step 5: Commit.** Message: `feat: per-period metrics CSV matching standard_metrics`.

### Task 7: Bridge — config conversion and `gpu_run`

**Files:**
- Create: `bridge/__init__.py`, `bridge/config_cfg.py`, `bridge/gpu_run.py`, `tests/test_bridge.py`.

**Interfaces:**
- Consumes: `bridge.paths`; from the Python project, `experiments.registry.EXPERIMENTS`,
  `experiments.run.matching_ids`, `fingerprint` and `load_results`, and `sugarscape.config.Config`.
- Produces:
  - `class UnsupportedFeature(ValueError)`.
  - `unsupported_features(cfg: Config) -> list[str]`. It names each of these that is set: `sex`,
    `inheritance`, `tag_length`, `culture`, `combat_alpha`, `initial_blocks`, `replacement_same_tribe`,
    `spice`, `trade`, `credit`, `cultural_preferences`, `foresight`, `disease_list` and
    `diseases_per_agent`. It also names `sugar_map` when it is not `sugar-map.txt`.
  - `config_to_cfg(cfg: Config, steps: int, seed: int) -> str`. The map path is
    `SUGARSCAPE_ROOT/sugarscape/maps/<sugar_map>`. It raises `UnsupportedFeature` with the list.
  - `run_experiment_gpu(exp_id: str, seeds: int | None = None, jobs: int = 1,
    out_dir: Path = Path("results-gpu"), exe: Path = EXE) -> list[Path]`. It writes
    `out_dir/<id with / → _>/seed{k}.csv`, the `run.cfg` per seed, and `fingerprint.txt` =
    `"gpu-phase1\n" + fingerprint(exp_id)`.
  - CLI: `python -m bridge.gpu_run <id-or-prefix> [--seeds N] [--jobs J] [--out DIR]`. It skips (and
    lists) experiments with unsupported features when given a prefix, and errors on a single
    unsupported id.

- [ ] **Step 1: Write the failing tests:**
  - `test_cfg_ii1_has_inf_growback`: the cfg for `EXPERIMENTS["II-1"].config` contains
    `growback_rate = inf` and `endowment = 25,50`.
  - `test_cfg_ii8_pollution`: it contains `pollution = 1.0,1.0`, `pollution_start = 50`,
    `diffusion_period = 1` and `diffusion_start = 100`.
  - `test_cfg_none_fields_blank`: II-4 has `max_age =` and `seasons =` blank.
  - `test_unsupported_lists_features`: `Config(sex=True, max_age=(60,100))` → `["sex"]`, and
    `config_to_cfg` raises `UnsupportedFeature` with "sex" in the message.
  - `test_every_chapter_ii_experiment_converts`: every id starting `II-` converts, and the exe accepts
    each cfg with `--print-config` (exit 0).
  - `test_run_tiny_experiment` (GPU): `run_experiment_gpu("TEST-tiny", out_dir=tmp)` gives 2 seed files.
    `experiments.run.load_results("TEST-tiny", tmp)` gives 2 series of 6 rows each, and
    `fingerprint.txt` starts with `gpu-phase1`.
- [ ] **Step 2: Run them.** `pytest tests/test_bridge.py -v` → FAIL (module missing).
- [ ] **Step 3: Implement** `config_to_cfg`, `unsupported_features`, `run_experiment_gpu` (a process pool
  of `jobs` exe runs, seeds = base + k) and the CLI.
- [ ] **Step 4: Run the tests.** `pytest tests/test_bridge.py -v` → all PASS.
- [ ] **Step 5: Commit.** Message: `feat: bridge converts registered configs and runs them on the GPU`.

### Task 8: Bridge — `gpu_report`

**Files:**
- Create: `bridge/gpu_report.py`, `tests/test_report.py`.

**Interfaces:**
- Consumes: `replication.targets.TARGETS`, `replication.report.evaluate` and `Result`, and
  `experiments.run.load_results` and `results_current`.
- Produces:
  - `@dataclass Comparison: target; gpu: Result | None; py: Result | None; py_stale: bool`.
  - `compare(targets, gpu_dir: Path, py_dir: Path) -> list[Comparison]`. A missing results folder
    gives None. `py_stale` comes from `results_current(exp_id, py_dir)` being False. It handles baseline
    targets as `evaluate` does.
  - `write_comparison(rows, path: Path)`. It writes the summary counts for each side, the table
    (columns: Experiment, Target, Book, Band, Python mean [min–max], Python status, GPU mean [min–max],
    GPU status, GPU − Python), and the section "Status changes", listing each target whose status
    differs.
  - CLI: `python -m bridge.gpu_report [--chapter II] [--gpu DIR] [--python DIR]` writes
    `<gpu>/REPORT.md`.

- [ ] **Step 1: Write the failing tests**, with synthetic series written by
  `experiments.run._write_csv` into tmp `gpu/` and `py/` folders for `II-4`:
  - `test_compare_both_sides`: GPU population 230 and Python 220 over t 0–500 → the II-4 carrying
    capacity row has both statuses "pass" and the difference 10.
  - `test_missing_side_is_none`: no GPU folder for II-1 → `gpu is None`, and the report row says
    "not run".
  - `test_status_change_listed`: GPU 300 (fail), Python 220 (pass) → listed under "Status changes".
- [ ] **Step 2: Run them.** `pytest tests/test_report.py -v` → FAIL.
- [ ] **Step 3: Implement** `compare`, `write_comparison` and the CLI.
- [ ] **Step 4: Run the tests.** `pytest tests/test_report.py -v` → PASS.
- [ ] **Step 5: Commit.** Message: `feat: GPU vs Python replication report`.

### Task 9: Chapter II validation run and findings

**Files:**
- Create: `docs/validation/phase1-chapter2.md`.
- Output (not committed): `results-gpu/`.

- [ ] **Step 1: Run** `python -m bridge.gpu_run II --jobs 4`. Expected: 25 experiments × their registered
  seeds; every exit 0.
- [ ] **Step 2: Run** `python -m bridge.gpu_report --chapter II`. Expected: `results-gpu/REPORT.md` with
  53 rows. Python results may be missing or stale; if so, list them and ask the user before running
  anything inside `SUGARSCAPE_ROOT`.
- [ ] **Step 3: Investigate each status change.** For each target that moved down (pass → near/fail,
  near → fail), find out why. Use extra GPU runs or dumps here, never changes to the Python project.
  Separate three causes:
  - a bug, which is fixed with a test added to the owning task's test file;
  - a parallel-update effect named in the spec, which is explained with evidence;
  - seed noise.
- [ ] **Step 4: Write `docs/validation/phase1-chapter2.md`.** It covers the scoreboard for both sides,
  every status change with its explanation and evidence, and the differences in the spec's [parallel]
  list that showed up and how large they were.
- [ ] **Step 5: Commit.** Message: `docs: Phase 1 Chapter II validation findings`.

### Task 10: Benchmark and README

**Files:**
- Create: `bridge/bench.py`.
- Modify: `src/main.cu` (`--timing`, already parsed in Task 1), `README.md`, `tests/test_cli.py`.

**Interfaces:**
- Produces:
  - `--timing FILE` writes JSON with keys `cells`, `agents_initial`, `steps`, `simulate_seconds` and
    `step_seconds_mean`, timed with std::chrono around `simulate()`.
  - `python -m bridge.bench [--tiles 1,2,5,10,25,50] [--steps 500] [--python-tiles 1,2,4]
    [--python-steps 50]`. It uses `build-fast` (`SEATBELTS=OFF`) and II-4's config with `--tile K`
    and `--metrics-every 10`, and writes:
    - `results-gpu/bench.csv`, with columns `engine,tile,cells,agents_initial,steps,step_seconds_mean,
      population_per_tile_450_500`;
    - `results-gpu/bench.png`, two panels: step time against initial agents (log-log, GPU and Python),
      and population per tile against tile.

    Python timing builds `Model(replace(cfg, width=50K, height=50K, initial_population=400K²),
    capacity=np.tile(load_map(...), (K, K)))`, and times `step()` over the Python steps.

- [ ] **Step 1: Write the failing test** `test_timing_json`: II-4, 20 steps, `--timing t.json` → the
  JSON has the five keys, `steps == 20` and `step_seconds_mean > 0`.
- [ ] **Step 2: Run it.** `pytest tests/test_cli.py::test_timing_json -v` → FAIL.
- [ ] **Step 3: Implement `--timing`.** Then configure and build `build-fast` (the Task 1 command with
  `-B build-fast -DFLAMEGPU_SEATBELTS=OFF`).
- [ ] **Step 4: Run the tests.** `pytest tests -v` → all PASS against `build/`.
- [ ] **Step 5: Implement `bench.py` and run it.** Expected: bench.csv has GPU rows for every tile and
  Python rows for the Python tiles. At K=1, population_per_tile is within the II-4 band (205–245) or
  explained in the validation doc.
- [ ] **Step 6: Write the README.** Cover prerequisites (VS 2022, CUDA 13.0, telemetry note,
  AGPL note), the two builds, running tests, `gpu_run`, `gpu_report` and `bench`, and a short results
  section that points to `docs/validation/phase1-chapter2.md` and `results-gpu/bench.png`.
- [ ] **Step 7: Commit.** Message: `feat: tiling benchmark; docs: README`.
