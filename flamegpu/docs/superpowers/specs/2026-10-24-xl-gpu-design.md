# Sugarscape xl on FLAME GPU 2 — Design

Date: 2026-10-24. Implements the contract in [`docs/xl.md`](../../../../docs/xl.md) (the repository root's) for the
Chapter II rules, on top of [Phase 1](2026-10-23-phase1-chapter2-gpu-design.md). The Python xl design is
[`docs/superpowers/specs/2026-10-24-xl-design.md`](../../../../docs/superpowers/specs/2026-10-24-xl-design.md) in the
repository root; its non-goal "FLAME GPU support for xl" is what this work now takes up.

## Intent

xl is the shared workload for comparing three implementations of Sugarscape (Python, this FLAME GPU port, and a
Julia one not yet written) on **performance and fidelity** (user). This work makes the GPU port a fair entry in that
comparison:
- it runs the xl version of the Chapter II experiments;
- it reports the same timing measures as Python;
- it is not slowed by costs that belong to the 2500×2500 maximum rather than to the world actually being run;
- it shows, by its own statistical check, that its xl results agree with Python's xl results.

**For now everything is tested at 500×500** (user). The 50×50 exact tests stay, since they are the exact match
against Python. Every new check runs at 500×500. The 2500×2500 tiling benchmark (`bridge.bench`) stays in the code
but is not re-run. **The world may grow later** (user), so nothing here may assume 500×500.

## Goals

1. `python -m bridge.gpu_run <id> --xl` runs an experiment's xl version on the GPU, using the Python project's own
   transform, so the GPU never re-implements the xl table.
2. Rule D runs `diffusion_passes` passes per diffusion period, as the Python model does. Movement looks with
   `look_stride`, and vision is drawn in whole strides (section 2a, an amendment).
3. No host-side work that runs in the timed parts of a run copies an array sized for the compiled maximum
   (`SUGARSCAPE_MAX_CELLS`, 6.25M sites) when the world is smaller (user).
4. Every GPU run reports `docs/xl.md`'s timing measures (setup, stepping and metrics, plus periods and the agent
   count at the start and at the end). The bridge writes them to `timing.csv` and `machine.txt`, with the same
   columns as the Python runner.
5. A one-off validation run (user) compares the GPU's xl results with Python's, statistically, and writes a report
   to `docs/validation/`.

## Non-goals

- Rules beyond Chapter II (spice, tribes, sex, culture, trade, credit, disease, combat). An xl config that turns any
  of them on is still refused, as now.
- Scoring xl runs against the book's targets. They are absolute numbers for a 50×50 world (as in the Python xl
  design).
- The three-way comparison itself (Python, GPU and Julia side by side). That is separate work. This work's report
  compares the GPU with Python only, and it records timings without ranking the implementations.
- Making the GPU faster in general. Only the copies sized for the maximum are in scope (Goal 3).
- Re-running or re-validating the 2500×2500 benchmark.

## Anti-goals

- **No 50×50 result changes.** Every existing GPU run gives the same output as today, so the saved `results-gpu/`
  stay current and the Phase 1 fingerprint (`gpu-phase1`) stays.
- **No Python project change.** The bridge calls `experiments.run.experiment_config(id, xl=True)` and
  `fingerprint(id, xl=True)` as they are. Python's xl results come from its own unmodified `--xl` runner.
- **Never drop a setting silently.** A Config field the GPU cannot honour is refused, never ignored. This stays the
  rule for every field this work doesn't add.
- **No disagreement hidden.** The report lists every comparison, not only the ones that agree.

## Constraints

As Phase 1:
- FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080 (compute capability 89);
- built by `scripts\build.cmd`: `build\` with seatbelts on, and `build-fast\` with them off;
- telemetry off;
- Context7 lookups before any FLAME GPU code is written.

## Design

### 1. The bridge: `gpu_run --xl`

- **Config.** `--xl` builds each experiment's config with `experiment_config(id, xl=True)`, Python's `to_xl`.
  Experiments that aren't sugarscape configs are refused, as Python refuses them. An xl config that still uses
  non-Chapter II rules is skipped, as such configs are now.
- **Three fields stop being refused.**
  - `sugar_map` becomes a field the GPU reads. `run.cfg`'s `map` line already names the configured map file, and
    `load_map` checks the file against the configured width and height.
  - `diffusion_passes` is written to `run.cfg` (section 2).
  - `look_stride` is written to `run.cfg` (section 2a; amendment of 2026-10-24).
  - Every other field outside Chapter II is still refused when it isn't at its default.
- **Output folder.** xl results go to `results-gpu-xl/`, which is git-ignored like `results-gpu/`. `--out` still
  overrides it.
- **Fingerprint.** `gpu-phase1` plus `fingerprint(id, xl=True)`, which includes the map's SHA-256. A changed map or
  transform therefore makes GPU xl results stale, as it does Python's.
- **Timing files** (*my call*: for every GPU run, regular or xl, as the Python runner does):
  - `timing.csv`, with Python's columns `seed, periods, setup_s, stepping_s, metrics_s, agents_start, agents_end`,
    one row per seed, built from each seed's `--timing` JSON;
  - `machine.txt`, recording:
    - the GPU name and driver version, CUDA runtime version, FLAME GPU version, and `SUGARSCAPE_MAX_CELLS`;
    - which build ran (seatbelts on or off);
    - CPU and platform, and `--jobs`;
    - that runs with `--jobs` above 1 shared the GPU;
    - that every seed is a fresh process, so every seed's setup includes starting CUDA.
- **Build choice** (*my call*): `gpu_run` gains `--exe`, defaulting to `build\` as now. Timing runs use
  `build-fast\` (seatbelts off), the build that measures the model rather than FLAME GPU's checks.

### 2. Diffusion passes (rule D)

- **New `run.cfg` key `diffusion_passes`**: an integer ≥ 1, default 1. It is parsed, validated and printed by
  `--print-config` like the other keys.
- **Behaviour.** In a diffusion period, after growback, pollution is diffused `diffusion_passes` times. Each pass
  replaces every site's pollution with the mean of its four von Neumann neighbours from the previous pass, exactly
  as Python's loop of `Landscape.diffuse()`. With 1 pass, results are unchanged (anti-goal).
- **Mechanism: the builder's.** The constraints on it:
  - the pass count is a run setting, never compiled in;
  - each layer obeys the macro-property rule (within a layer, a property is only read or only atomically written);
  - a period without diffusion costs about nothing extra.

  The movement sub-model, which repeats layers until an exit condition holds, is the precedent.

### 2a. Look stride (amendment, 2026-10-24; user-approved)

`docs/xl.md` gained a look stride after this design was approved (main, commit 0b6b937). At xl, `look_stride = 10`:
along each lattice line, an agent looks at one site drawn uniformly from each stretch of 10 (one of the sites 1–10
away, one of 11–20, and so on out to its vision), and vision is drawn in whole strides (10, 20, … 60). Python's
reference is `look_distances` in `sugarscape/rules/movement.py` and the vision draw in `Model._spawn_at`.

- **New `run.cfg` key `look_stride`**: an integer ≥ 1, default 1, parsed, validated and printed like the other keys.
  Validation refuses a vision range whose bounds aren't whole multiples of the stride, as Python's `Config` does.
- **Vision draws.** Founders and newcomers draw `stride × U[lo / stride, hi / stride]`. With stride 1 that is the
  current draw, so the host random stream is unchanged.
- **Movement's scan.** In each direction, for each stretch k = 0, 1, … (vision / stride − 1), the agent looks only at
  distance `stride · k + offset`, with offset uniform on 1 … stride. It still takes the nearest of the best sites it
  saw, by that site's actual distance.
- **One look per period** (*my call*, approved by the user). Python's agents look once per period. The GPU resolves
  conflicts in rounds, and an agent that loses its site scans again. That rescan must see the same sites, less any
  taken since, not a fresh sample, or losers would get extra looks. So each citizen draws one look seed per period
  (in `start_period`), and each offset is a hash of (look seed, direction, stretch). There are no per-agent arrays.
- **Stride 1 draws nothing extra.** The look seed is drawn only when the stride is above 1, so 50×50 results stay
  byte-identical (the golden runs prove it).
- Combat and mate search use the stride in Python too. The GPU has neither yet (Chapter II only); whoever ports
  them must use the same looks.

### 3. No copies sized for the maximum

FLAME GPU copies a whole macro property whenever a host function touches it (`HostMacroProperty` downloads all of
its elements). Here that means 6.25M entries, whatever the world's size. Agent data is different: a host function
that reads agent variables through `getPopulationData()` copies only the variables it reads, and only for the agents
that exist.

The rule is that **no host function in setup or in a period touches a site-sized macro property.** The only
exceptions are the diagnostics (`--check` and the dumps), which run only in tests and are never timed. Today two
places break the rule:

- **Replacing dead agents, `replace_dead`, every period with deaths.** Today it reads and writes back the whole
  `occupied` array (25 MB each way).
  - Instead, it finds the empty sites from the living citizens' `x` and `y`, read as agent data.
  - The empty sites are listed in ascending site order, as now. The host random draws are therefore identical, and
    every existing 50×50 result is unchanged (anti-goal).
  - Newcomers mark their own sites in `occupied` in a citizen layer right after `replace_dead`. That layer only
    writes `occupied`. How a newcomer is recognised is the builder's: today a newcomer is the only citizen with age
    0 at that point.
- **Initialisation, `init_landscape`, once in setup.** Today it writes `capacity`, `sugar` and `occupied` from the
  host. These writes move to the GPU instead, for example by carrying each site's capacity as a cell-agent variable
  and setting the macro properties in a device layer.
  - The mechanism is the builder's, but the t = 0 state that metrics, dumps and `--check` see must be unchanged.
    The parity tests compare t = 0 dumps with Python's.

**Growing the world later.** The macro properties stay sized by `SUGARSCAPE_MAX_CELLS`. After this change, raising
it costs device memory (4 bytes per site per property), not time per period. A world beyond 2500×2500 needs only
that one build setting.

### 4. Timing (`docs/xl.md`, "Timing")

`--timing FILE` writes the measures below into its JSON. The existing keys stay, because `bridge.bench` reads them.

| Key | Measures |
|---|---|
| `setup_s` | From the start of model building in `main`, after the config is parsed, to the state at t = 0. Covers loading the map, describing the model, creating the simulation (which starts CUDA), creating the populations, and initialisation. The t = 0 metrics are left out. |
| `stepping_s` | The sum over periods of each period's time, measured as now with the GPU synchronised at both ends, so metrics and dumps are left out. |
| `metrics_s` | The sum over every metrics collection, t = 0 included: the time to gather the period's metrics. Writing the CSV row is left out, as Python's runner writes its CSV after timing. |
| `periods`, `agents_start`, `agents_end` | The period count, and the citizen count at t = 0 and after the last period. |

- Timed runs use neither `--check` nor the dumps.
- `--metrics-every` above 1 would make `metrics_s` incomparable, so the bridge always uses 1.

### 5. The fidelity check (one-off; user)

**Experiments** (*my call*): five, which together exercise every Chapter II rule the GPU implements.

| Experiment | Rule it exercises | Seeds × periods |
|---|---|---|
| II-4 | basic movement and harvest | 10 × 500 |
| II-4-gini | replacement (the path section 3 changes) | 10 × 500 |
| II-6 | block placement | 5 × 300 |
| II-7 | seasons | 5 × 500 |
| II-8 | pollution, and 100-pass diffusion | 5 × 200 |

The largest vision in the II-5 sweep, II-5/m3/v10.5 (vision 10–200 at xl), runs on the GPU only, as a smoke test of
long scans.

**Runs.**
- Python: `python -m experiments.run <id> --xl --jobs J` from the repository root, into its `results-xl/`. That is
  about 20 CPU-hours, about 2–3 hours of wall time across 24 threads (user: acceptable once).
- GPU: the same seeds, two ways:
  - once with `build\` (seatbelts on), as the results compared;
  - once with `build-fast\`, for the timing table.

  The GPU part takes minutes.

**Comparison** (*my call*; user: a gap that is large in seed-spread units but small in size is close enough):
- Every metric column the two sides share is compared at four checkpoints: 10%, 25%, 50% and 100% of the run's
  periods.
- At each checkpoint the report gives:
  - the GPU mean and the Python mean over seeds;
  - the **size of the gap**: |GPU − Python| as a percentage of the metric's scale, which is the largest |Python
    mean| over the whole run. That keeps metrics that start near zero, such as pollution, from looking huge;
  - the **gap in spread units**: Welch's t.
- A comparison **disagrees** only when the size of the gap is over **1%** *and* |t| > 3. Anything else is close
  enough. The report states these thresholds as the ones it used.
- **No spread.** Where both sides have no seed-to-seed spread, t is undefined. The comparison then disagrees only
  if the gap is over 1%. A metric whose scale is 0 on the Python side is reported but not judged.

**Report**, `flamegpu/docs/validation/xl-chapter2.md` (committed, like `phase1-chapter2.md`):
- every comparison, with the disagreements listed first;
- the smoke test's result;
- a timing table for each experiment: setup and stepping per period for the GPU (fast build) and Python, with
  Python's `--jobs` stated, since shared-processor timings flatter neither side;
- the machine notes;
- any disagreement either explained or listed as open. A disagreement does not block the work.

**The script** that runs the comparison and writes the report lives in `bridge/` (*my call*). Its name is the
builder's. It reads both result folders. It runs the GPU side itself, but it does not launch the hours-long Python
runs: if Python's xl results are missing or stale, it prints the exact commands to run instead.

## Verification (pytest, in `flamegpu/tests/`)

- **Bridge**
  - `--xl` writes to `results-gpu-xl/` with the xl fingerprint.
  - It refuses Schelling and Ring World ids.
  - `sugar_map`, `diffusion_passes` and `look_stride` reach `run.cfg`.
  - Any other non-Chapter II field off its default is still refused (the existing tests stay as they are).
- **Diffusion**: exact parity with Python at 50×50 for `diffusion_passes` = 3, over a few diffusion periods, using
  the existing `--init` and dump harness.
- **Look stride** (section 2a). Exact parity with Python is impossible at stride > 1, since the draws differ, so
  the tests check the rule's properties:
  - vision values are whole strides, and every one of them occurs;
  - a vision range not in whole strides is refused;
  - an agent looks once per stretch, at a uniform offset: with equal food on every site of one stretch and none
    elsewhere, agents move exactly as far as their one look in that stretch reached. Every distance 1 … stride
    occurs about equally often; looking at every site would always move them 1;
  - stride 1 leaves the golden runs byte-identical.
  - A rescan seeing the same sites holds by construction: each offset is a pure function of the period's look seed,
    direction and stretch, and the scan draws no offsets itself. No test can see it from outside the program, so the
    review checks it instead.
- **Replacement and initialisation**: every existing parity, invariant and metrics test passes unchanged. That
  proves the empty-site order, and therefore the random draws, are unchanged.
- **500×500**: an xl run of each of II-4-gini and II-8 for a few periods with `--check`. Invariants hold, the map
  loads at 500×500, and the visions 10, 20, … 60 are drawn (and nothing between them).
- **Timing**
  - The JSON has the new keys, with non-negative times and the right period and agent counts.
  - `timing.csv` and `machine.txt` are written with Python's columns.
- **No copies sized for the maximum**: how to pin this is the builder's. One way is a test-only counter of host
  macro-property accesses during periods. As further evidence, the validation report's stepping time per period for
  II-4-gini (replacement) should be close to II-4's.

## Left to the builder

- The diffusion-pass mechanism and the device initialisation mechanism, within sections 2 and 3's constraints.
- How newcomers are recognised.
- The validation script's name and its command-line options.
- How the regression test for maximum-sized copies works.
- Small refactors needed to pass xl through the bridge.
