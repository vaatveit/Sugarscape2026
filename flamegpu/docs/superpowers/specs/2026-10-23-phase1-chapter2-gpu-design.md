# Sugarscape on FLAME GPU 2, Phase 1 (Chapter II rules) — Design

Date: 2026-10-23. Reference model: the Python Sugarscape2026 at `C:\Projects\Sugarscape2026`
(commit 9e66d39), which this project reads but never modifies.

## Intent

Run the Sugarscape model on the GPU so the world and the population can grow far beyond the book's
50×50 lattice with 400 agents. The Python model is a faithful, sequential re-creation of the book. It is
the reference: the GPU model is a *parallel variant* of it. It must be checked against the same book
targets and against the Python model's own results before anyone draws conclusions from large runs.

Phase 1 covers the Chapter II rules only. Later phases add the rules where agents act on each other (sex,
culture, trade, credit, disease, combat), each with its own design.

## Goals

1. A FLAME GPU 2 model in CUDA C++, built from `FLAMEGPU2-model-template-cpp`, implementing:
   - G_α growback, including G_∞ (`growback_rate = inf`);
   - S_αβγ seasonal growback, with both winter modes (`fractional`, `pulse`);
   - M movement on the sugar landscape, with the pollution score s/(1+p);
   - metabolism and death by starvation (sugar ≤ 0);
   - aging and death at maximum age, and R[a,b] replacement;
   - P_αβ pollution formation, with `pollution_start` and `pollution_stop`;
   - D_α pollution diffusion, with `diffusion_start`;
   - initial placement `random` and `block`, and founder ages `uniform` and `zero`.
2. Every Chapter II experiment in the Python registry (25 experiments, 49 targets) runs on the GPU from
   its registered `Config`. The results are written as `seed{k}.csv` files with the same columns and
   meaning as `sugarscape.stats.standard_metrics`.
3. A Python bridge that runs those experiments and scores them with the Python project's own code
   (`replication.targets.TARGETS`, `replication.report.evaluate`). It writes a report that shows, per
   target: the book band, the Python result, the GPU result, and each one's status.
4. A scaling benchmark that tiles the 50×50 map K×K with the population scaled by K² (same density).
   It reports the GPU step time and checks that the per-tile results stay close to the 50×50 results.
   K goes up to 50: the user's target world of 2500×2500 (6.25M sites, about 1M agents at the book's
   density of 400 per 2500 sites), with Python step times measured at the
   sizes Python can run in reasonable time.

## Non-goals

- Bit-for-bit agreement with Python. The random number generators differ, and updating in parallel
  changes the order of events. Agreement is statistical, judged by the targets.
- The rules from Chapters III–VI (S, I, K, C, T, L, E, spice, foresight, Schelling, Ring World).
  Configs that switch any of them on are rejected with a clear error.
- Multiple GPUs, and visualisation. The visualiser stays off; it can come later.
- Running ensembles inside one process (`CUDAEnsemble`). Seeds run as separate processes in Phase 1.
- Any change to the Sugarscape2026 repository.

## Anti-goals (failure even if it runs)

- Changing a rule's meaning to make the GPU faster or to make a target pass. Where the parallel
  version has to differ from the sequential one, the difference is named in this document, and in the
  code where it happens.
- Scoring the GPU model with different targets or bands from the Python model's.
- Silent fallbacks, for example running with a feature quietly ignored. Unsupported settings are errors.

## Constraints

- Machine: RTX 4080 (compute capability 8.9, 16 GB), Windows 11, Visual Studio 2022 Community with its
  bundled CMake 3.31 and the Windows 11 SDK. The CUDA 13.0 toolkit is to be installed by the user.
- FLAME GPU 2 `v2.0.0-rc.5`, fetched by the template's CMake (the template pins rc.4; we bump it).
  `CMAKE_CUDA_ARCHITECTURES=89`.
- Licence: FLAME GPU 2 and the template are AGPL-3.0. This project is for local research. The licence
  matters only if the program is ever distributed or offered as a network service.
- Telemetry: off by default in our CMake and scripts (`FLAMEGPU_SHARE_USAGE_STATISTICS=OFF`). This
  project's call; the user can switch it on.
- The GPU also drives the display (WDDM), so no single kernel may run for close to 2 s. Nothing in
  this design comes near that.

## Decided by the user

- C++ template, not pyflamegpu; results go to files that the existing Python scoring code reads.
- Chapter II first, validated against the Python version at 50×50, then scaled up.

## The parallel model (this project's calls)

### Data layout

- **Landscape and occupancy in environment macro properties.** These are 1D arrays sized to a
  compile-time maximum world (CMake option `SUGARSCAPE_MAX_CELLS`, default 2500 × 2500 = 6,250,000,
  the user's target size; about 200 MB of GPU memory for the arrays). A site's
  index is `x + y * width`, with the width set at run time. Arrays:
  - `capacity` (uint32);
  - `sugar` and `sugar_next` (float);
  - `pollution` and `pollution_next` (float);
  - `occupied` (uint32: 0 or 1);
  - `claim` (uint64).

  Macro property sizes are template parameters in FLAME GPU 2, hence the fixed maximum. A run that
  needs a larger world needs a rebuild with a larger maximum. FLAME GPU messages (array or bucket)
  were the alternative; atomic claims on arrays are simpler and avoid building messages every round.
- **Floats, not doubles, for sugar and pollution.** Every sugar quantity in Chapter II is an integer or a
  multiple of 1/β with β a power of two in the registered runs. Those are exact in float32 up to 2²⁴, so
  ties compare the way they do in Python. Pollution values are not exact; the small differences from
  Python's float64 are accepted.
- **Two agent types.**
  - `cell`: one per site, for the per-site rules (growback, seasons, diffusion, resetting claims).
  - `citizen`: one per Sugarscape agent. Variables: x, y, vision, metabolism, sugar, age, max_age
    (INT_MAX for immortal), moved, neighbors, priority, settled, and target index.
- **One rule for macro properties per layer.** FLAME GPU's run-time checks keep one read/write flag per
  macro property per layer. So within a layer, a property is either only read or only written
  atomically (`exchange`, `max`, `+=`), across all functions and threads in that layer. Two
  consequences:
  - Harvesting uses `sugar[i].exchange(0)`, which returns the harvest.
  - Growback and diffusion write `sugar_next` and `pollution_next`, and a second cell layer copies them
    back.

### One period, in order

*Superseded on 2026-10-25 for movement and neighbour counts* by
[Python's agent order on the GPU](2026-10-25-gpu-sequential-semantics-design.md): movement is deferred acceptance over
a 32-bit order key, and neighbours are counted in that order after metabolism. The steps below record this design.

Python's step order is followed, except where marked **[parallel]**.

1. **Start of period** (cells): reset `claim` to 0. Citizens draw a fresh random 20-bit priority and
   clear `moved`.
2. **Movement sub-model** (unsettled citizens), repeated in rounds until all are settled:
   1. *Scan* (reads `occupied`, `sugar` and `pollution`; writes `claim`): build the candidate list as
      `candidate_sites` does — the own site at distance 0, then the four directions in a random order
      (a new order each round), out to vision, unoccupied sites only. Pick the best site: higher score
      wins; on equal score the nearer wins; on equal distance the first encountered wins. The score is
      `sugar / (1 + pollution)`. If the best is the own site, the target is the own site and no claim is
      made. Otherwise the agent calls `claim[target].max(key)` with
      `key = round << 52 | priority << 32 | id`, where round has 12 bits, priority 20 bits and id 32
      bits.
   2. *Resolve* (reads `claim`; writes `occupied`, `sugar` and `pollution`): an agent wins if its
      target is its own site, or if its key equals `claim[target]`. A winner:
      - clears `occupied` at its old site if it moved, and sets it at the target;
      - harvests `sugar[target].exchange(0)`;
      - adds harvest pollution α·harvest when pollution is active;
      - settles.

      Losers stay unsettled.

      Exit condition: no unsettled citizens. More than 4095 rounds is an error, and never expected.

   **[parallel]** Python gives each agent the whole period in a random order. Here, the random
   priority stands in for that order, and only agents competing for the same site are ordered. An
   agent that loses scans again next round, and then sees the sites that winners have taken or left.
   What can differ from Python:
   - In Python, an agent late in the order sees every earlier agent's final position. Here, in round 1
     it sees only the positions at the start of the period.
   - An agent that dies in Python frees its site immediately, for later agents in the same period. Here
     a site freed by death becomes available in the next period.
3. **Neighbors** (citizens, read-only): count occupied von Neumann sites. **[parallel]** Python counts
   just after each agent's own move, so agents moving later change it. Here it is counted after all
   moves and before deaths.
4. **Metabolize and age** (citizens, one function): `sugar -= metabolism`, plus consumption pollution
   β·metabolism at the agent's site when pollution is active. If `sugar <= 0`, the agent clears its site
   and dies. Otherwise `age += 1`, and if `age >= max_age` the agent clears its site and dies. (Python
   ages everyone at the end of the period; nothing in between reads age, so this is the same.)
5. *(merged into 4)*
6. **Replacement R** (host function): one new agent for each death this period, each at a random empty
   site, with fresh draws of vision, metabolism, endowment, and max age, and age 0. Drawn on the host
   from the period's occupancy. The new agent does not harvest on arrival (Python's default).
7. **Growback and diffusion, layer A** (cells: read `sugar`, `capacity` and `pollution`; write
   `sugar_next` and `pollution_next`):
   - `sugar_next` is G_α or S_αβγ with Python's formulas and its north/south split (y ≥ height/2 is
     north). G_∞ gives capacity.
   - `pollution_next` is the mean of the four von Neumann neighbors' pollution (the site's own value is
     not included) when `diffusion_period` is set, `t >= diffusion_start` and `t % diffusion_period == 0`;
     otherwise it is the site's own pollution.
8. **Layer B** (cells: read the `*_next` arrays; write `sugar`, `pollution` and `claim`): copy back, and
   reset `claim` to 0 for the next period.
9. **Metrics** (host): one CSV row per period. Then `t += 1`.

Here `t` is the number of completed periods, as in Python's `Model.t`. Pollution is active while
`pollution_start <= t` and either `pollution_stop` is unset or `t < pollution_stop`, with `t` taken as
Python takes it (before the increment).

### Initialisation

Host init function, seeded `std::mt19937_64` with the run's seed:
- Read the capacity map. The file format and orientation are those of `sugarscape.maps.load_map`:
  the first line is the northernmost row. Sugar starts at capacity.
- Choose `initial_population` sites without replacement among all sites (`random`) or the block
  (`block`, with Python's wrapping of block coordinates).
- Draw vision, metabolism, endowment, and max age from the inclusive integer ranges. With finite lives
  and `founder_ages = "uniform"`, the founder's age is drawn from U[0, max_age).

The draws do not follow NumPy's random stream. Optionally, `--init agents.csv` loads the starting
population from a file instead. Tests use this to start the GPU and Python models from the same state.

The device random numbers come from FLAME GPU's generator, seeded from the run's seed.

### Metrics (per period, t = 0 … steps)

The column names are those of `standard_metrics`, plus `t`: population, mean_vision, mean_metabolism,
mean_sugar, gini, mean_neighbors, moved, ne_fraction, on_peak_fraction, north_frac_high_vision,
north_frac_low_vision, summer_north. Each column means what it means there:
- `gini` uses the sugar of all agents, with the same formula, and is exact.
- `on_peak_fraction` is the share of agents on a site with capacity ≥ 3.
- High vision is vision ≥ 5; low vision is vision ≤ 2.
- A value with nothing to measure is written as `nan`, just as `safe_mean` and `_fraction` return.

The row for t = 0 is written after initialisation. Every row is computed on the host, by one function,
from a copy of the citizens' variables and the host's copy of the capacity map. `neighbors` and `moved`
are computed on the GPU during the period. Gini is computed in double precision with Python's formula.
For large runs, `--metrics-every N` writes only the rows with t % N == 0 (t = 0 is always written), so
the copy is made only on those periods.

## Program interface

`sugarscape_gpu --config run.cfg --out metrics.csv [--init agents.csv] [--metrics-every N]
[--dump-agents file --dump-at t] [--dump-landscape file --dump-at t] [--tile K]`

- `run.cfg` holds plain `key = value` lines, with the field names and value spelling of the Python
  `Config` fields Phase 1 uses: ranges as `lo,hi`, `inf` for G_∞, and empty for None. It also has
  `steps`, `seed`, and `map` (a path to the map file). Unknown keys and unsupported features are errors.
- `--tile K` tiles the map K×K, multiplies `initial_population` by K², and with `block` placement
  repeats the block in every tile. Each tile starts as a copy of the 50×50 world's setup.
- A world larger than `SUGARSCAPE_MAX_CELLS` is an error naming the limit and the CMake option.
- `--timing file` writes JSON with the cell count, initial agents, steps, and wall-clock seconds for
  the simulation loop and per step.
- Dumps (CSV) of agents and of the landscape at a chosen t exist for the tests.

## Python bridge (`bridge/`)

- **Finding the Python project.** It is found through the `SUGARSCAPE_ROOT` environment variable,
  defaulting to `C:\Projects\Sugarscape2026`. Its packages are imported from there.
- **`gpu_run.py <id-or-prefix> [--seeds N] [--jobs J] [--out results-gpu]`.** For each matching
  registered experiment, it converts the `Config` to `run.cfg`, runs `sugarscape_gpu` once per seed
  (seed = base + k, as `experiments.run`), and saves `results-gpu/<id>/seed{k}.csv` and a fingerprint
  marked as GPU Phase 1. Configs with unsupported features are refused, listing the features.
- **`gpu_report.py [--chapter II]`.** It evaluates every Chapter II target on the GPU results, and on
  the Python project's saved `results/` (read-only; missing Python results are reported as missing,
  not re-run). It writes `results-gpu/REPORT.md`: book band, Python mean and status, GPU mean and status,
  and the GPU − Python difference. It also lists the targets whose status changed.
- **`bench.py`.** Runs the tiling sweep and writes `results-gpu/bench.csv` and a plot: step time
  against agent count, for GPU and Python, plus population per tile against the 50×50 value.

## Verification

1. **Build.** Debug-level checks: FLAME GPU's `SEATBELTS=ON` for all tests and validation runs;
   `SEATBELTS=OFF` only for the benchmark build, after the same runs pass with them on.
2. **Rule tests** (pytest, driving the program on tiny configs and reading the dumps):
   - Growback, seasons (both winter modes), and diffusion against hand-computed landscapes.
   - Movement against Python on states with no conflicts and no ties: starting from the same
     `--init` population, one step lands every agent where Python's `movement.move` sends it.
   - Conflict resolution: two agents with one obviously best site; exactly one gets it, and the
     other's second choice is taken.
   - Pollution formation, and the start and stop of pollution and diffusion.
   - Replacement keeps the population constant when every death is replaced.
3. **Invariants on random configs, every period:** at most one agent per site, and `occupied`
   agrees with the agents; no negative site sugar; sugar ≤ capacity; agents' sugar > 0 after the
   period; population accounting (start + replacements − deaths = end).
4. **Determinism:** the same seed gives an identical CSV twice (with seatbelts on).
5. **Validation:** all 49 Chapter II targets on GPU results with the registered seed counts, reported
   beside Python's. The aim is no target falling from pass to fail between Python and GPU. Where one
   does, it is investigated and explained in the report before Phase 1 ends. Targets that fail for
   Python already are not expected to pass on the GPU.
6. **Scale:** for II-4's rules, population per tile at K = 1…50 against the 50×50 carrying capacity,
   and step times.

## Project layout

```
C:\Projects\FlameGPU
  CMakeLists.txt, cmake/flamegpu2.cmake     # from the template; FLAMEGPU_VERSION v2.0.0-rc.5
  src/main.cu                               # arguments, config, simulation run
  src/model/*.cuh                           # model description, agent functions, host functions, metrics
  bridge/*.py                               # gpu_run, gpu_report, bench, config conversion
  tests/*.py                                # pytest suite that drives the built program
  docs/superpowers/specs, docs/superpowers/plans
  README.md                                 # build, run, validate, benchmark
```

## Left to the builder

- Module boundaries inside `src/model`, and names of the internal variables and functions.
- Skipping settled agents: a `settled` flag with an early return is this design's choice, because it is
  simplest. Agent states can replace it later if the rounds show up in profiles.
- How the round number reaches the sub-model (its own step counter, or an environment property).
- How deaths per period are counted for R (from the population before and after, or a counter).
- Plot styling, CSV float formatting (it must read back with `experiments.run._parse`), and README wording.
- Every FLAME GPU API used must be checked against the rc.5 documentation (Context7) before it is
  written; where an API differs from what this document assumes, keep the behaviour above and adapt.
