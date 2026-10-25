# Replacement on the device and fast metrics gathering — Design

Date: 2026-10-25. Builds on the [xl design](2026-10-24-xl-gpu-design.md) and replaces its section 3 bullet on
`replace_dead`. Requested by the user after the investigation summarised under Intent: move replacement (rule R,
p.32) onto the GPU to close II-4-gini's timing gap, regenerate the `gini_t30` golden it changes, and fix
`write_metrics`' gathering in the same work.

## Intent

The GPU port is one entry in a performance comparison with Python and Julia (xl design, Intent). Two host-side
costs make it look slower than it is, and both grow with the world:

- **Replacement.** At xl, II-4-gini steps in 6.3 ms per period on `build-fast\` against II-4's 0.73 ms. The two
  differ only in finite lives and replacement. An Nsight Systems trace (200 periods) shows the GPU almost idle: the
  kernels take 0.17 ms per period. Of the 6.3 ms, 4.7 ms is spent in the host function `replace_dead`:
  - 3.9 ms reading every citizen's `x` and `y` one agent at a time through `DeviceAgentVector`. Each read costs a
    string map lookup and checks, and grows with the agents.
  - 0.8 ms scanning all 250,000 sites for empty ones. This grows with the sites.
  - 0.07 ms creating about 570 newcomers. Creating them while the population vector is open also makes FLAME GPU
    copy all 14 citizen variables back to the host to merge them in.
- **Metrics.** `write_metrics` takes about 10 ms per period at xl: 9.5 ms gathering seven columns per agent through
  the same per-agent reads, and 0.8 ms computing the row. It is in every experiment's `metrics_s`, and it is more
  than all of the stepping.

A throwaway spike (since reverted) moved replacement onto the device as described below. II-4-gini stepping fell to
0.84 ms per period. Over 5 xl seeds × 200 periods, every metric agreed with the host version within 0.2%
(|Welch t| ≤ 1.2) at t = 1, 40–60 and 150–200. `--check` passed.

## Goals

1. **Replacement runs on the device.** No host function in a period reads agent data or creates agents for
   replacement. The rule keeps Python's distribution: each death is replaced by a newcomer with fresh random
   attributes, on a site drawn uniformly from the empty sites, one after another without repeats
   (`Model.spawn_random_agent`).
2. **Metrics are gathered in bulk.** Gathering a metrics row doesn't read agents one at a time. The row's bytes are
   unchanged for every run, because the same columns reach `compute_metrics` in the same agent order.
3. **The golden runs change only where replacement changes them** (user):
   - `block_seasons` and `diffusion` stay byte for byte.
   - `gini_t0`'s agent and landscape dumps (t = 0) stay byte for byte.
   - `gini_t0/metrics.csv` (30 periods with replacement) and all of `gini_t30` are regenerated, once, with
     `make_golden.py`, after the new tests pass.
4. **The xl validation report is refreshed.** The GPU xl runs are redone, and the report is regenerated, with its
   hand-written reading updated for the new timings.

## Non-goals

- Speeding up `--dump-*` and `--check`. They run only in tests and are never timed (xl design, section 3).
- Computing metrics on the device. The 0.8 ms compute stays on the host, which is what keeps the rows byte-identical
  (Goal 2).
- Rerunning Python's xl results. The II-4-gini Python timings in `results-xl/` predate main's commit 77ffcb6, which
  made Python's replacement fast (`docs/xl.md`: 1.13 s per period). Its seed CSVs are byte-identical, so the
  fidelity comparison stands. The report says the Python timing is stale and quotes `docs/xl.md`'s figure (*my
  call*: a rerun costs hours of CPU for a number already recorded).
- Same-tribe replacement and every rule outside Chapter II.
- Other GPU speed-ups.

## Anti-goals

- **No run without replacement changes.** Its outputs stay byte-identical. The replacement machinery is added to the
  model only when `replacement = true` (*my call*), so other runs execute exactly the kernels they do today.
- **No silent change of distribution.** Replacement is checked statistically: placement uniformity, newcomer
  attributes, and the xl comparison with Python (Verification).
- **No hang.** Placement always terminates, however full the world is.
- **No stale result scored as current.** Saved GPU results made with host-side replacement must read as stale.

## Constraints

As the xl design: FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, `scripts\build.cmd`, telemetry off, Context7
lookups before FLAME GPU code is written. Each layer obeys the macro-property rule: within a layer, a macro property
is only read or only atomically written. The world may grow later, so nothing may assume 500×500.

## Design

### 1. Newcomers are born on the device

- **Birth with death.** When replacement is on, `metabolize_and_age` is given the citizen as its agent output
  (`setAgentOutput`). A citizen that dies there also outputs one newcomer. FLAME GPU supports output from a dying
  agent of its own type: its own tests include `Optional_Output_SameState_WithDeath`.
- **The newcomer's attributes**, drawn with the dying agent's device random stream, each uniform on its inclusive
  range as the host draws are now:
  - vision: `look_stride × U[lo / stride, hi / stride]` (xl design, section 2a);
  - metabolism and endowment (its sugar);
  - `max_age`. Validation already requires `max_age` with replacement.
  - `age` is 0, and `x` and `y` are −1, meaning unplaced. Every other variable keeps its default, as with
    `newAgent` today.
- The ranges reach the device as environment properties (names: the builder's).
- Newcomers join the population when the layer ends, as FLAME GPU births do.

### 2. Placement: one kernel of atomic claims

- **New citizen function `place_newcomer`**, in the layer after `metabolize_and_age`. It replaces both the
  `replace_dead` host layer and the `occupy_site` layer after it. Citizens that are already placed return at once.
  The layer exists only when replacement is on (Anti-goals). `occupy_site` stays in the initialise layer for the
  founders.
- **An unplaced newcomer**:
  1. draws a site uniformly from all sites, `[0, width × height)`;
  2. claims it with `occupied[site].CAS(0, 1)`;
  3. on failure (the site is occupied, or another newcomer claimed it first), draws again.
  - On success it sets `x` and `y`.
- **The layer only atomically writes `occupied`.** It reads `occupied` only through `CAS`.
- **Why it has Python's distribution.** Every draw is uniform, and the claims treat all empty sites alike. So the set
  of sites the newcomers end up on is a uniformly random set of that many empty sites. That is what Python's
  one-after-another uniform draws give. Which newcomer gets which site doesn't matter, since their attributes are
  independent draws.
- **Termination.** There are always at least as many empty sites as newcomers: each death freed its own site in
  `metabolize_and_age`, and nothing occupies a site between that layer and this one. So a site can always be found.
  - To bound the time in a nearly full world, after `PLACE_TRIES` random draws (*my call*: 4096) a newcomer scans
    sites in order from its last draw, wrapping around, claiming the first empty one by `CAS`. That scan is certain
    to succeed.
  - The scan slightly favours sites after long occupied runs. It is reached only when 4096 uniform draws all missed:
    with a fraction q of sites taken, that happens with probability q^4096. That is below 10⁻⁹ unless the world is
    more than about 99.5% full.
  - The host's "lattice is full" error becomes unreachable and is removed.
- **Newcomers don't harvest on arrival**, as now. Placement runs after movement and after metabolism.

### 3. Host bookkeeping

- `replace_dead` is removed. `end_period` already reads and resets `deaths`. Births equal deaths when replacement is
  on, and are 0 otherwise. That is what `check_invariants` needs.
- `RunState::rng` is now used only for the founders, and its comment says so.
- **Random streams.** Replacement runs now draw their newcomers on the device, and the dying agents' draws advance
  the device streams. So every replacement run's random stream changes, the 50×50 ones included. Runs without
  replacement draw nothing new.
- **Fingerprint.** A replacement run's `fingerprint.txt` gains a line saying replacement runs on the device (wording:
  the builder's). Saved II-4-gini results, the only Chapter II experiment with replacement, then read as stale in
  `bridge.gpu_report`, while every other saved result stays current. II-4-gini's 50×50 results are rerun, and
  `results-gpu/REPORT.md` is regenerated.

### 4. Metrics gathered between steps

- **`main` steps the simulation itself.** It calls `simulation.step()` `cfg.steps` times instead of `simulate()`.
  This model has no init or exit functions and no FLAME GPU logging, which is all `simulate()` adds around its loop
  of `step()`.
- **After each step `t`**, when there is a CSV and `t % metrics_every == 0`:
  - `CUDASimulation::getPopulationData` copies the citizens into one reused host `AgentVector`;
  - the `AgentColumns` are filled from its `data<T>()` column pointers, in agent order;
  - `compute_metrics` makes the row, as now.
  - The copy brings all 14 variables (about 1.4 MB at 25,000 agents), with no per-agent lookups.
- **The t = 0 row** is made before the first step from the founders' `AgentVector`, the one passed to
  `setPopulationData`, in the same order. Nothing changes the citizens' variables before `finish_init` today, so the
  row is identical. `finish_init` keeps the t = 0 dumps, checks and timing, and stops writing metrics.
- **Order of outputs.** `end_period` keeps the dumps and `--check`, which still read through `DeviceAgentVector`.
  If a check fails, the step throws before that period's metrics row, as now.
- **`metrics_s`** keeps its definition: the copy, filling the columns and computing the row, t = 0 included, with the
  CSV write left out.
- **Timing keys.** `stepping_s` is unchanged: `begin_period` to `end_period`, synchronised. `simulate_seconds` now
  times the step loop, metrics included as before, so `bridge.bench` reads the same quantity.

## Verification (pytest, in `flamegpu/tests/`)

1. **Goldens** (Goal 3).
   - The metrics change (section 4) comes first, and every golden must still match byte for byte.
   - After the replacement change, exactly `gini_t0/metrics.csv` and the three `gini_t30` files differ.
   - `make_golden.py` is run once. `git diff --stat` must show only those four files.
   - `test_golden.py`'s docstring records that regeneration and why.
2. **Uniform placement.**
   - The run: 50×50, `max_age = 1,1` (everyone dies every period), 250 citizens, replacement on. Every agent dumped
     at the end of a period is then a newcomer placed on a world that was empty.
   - Across several seeds and dump periods:
     - the sites are distinct;
     - counts over 25 blocks of 10×10 pass a χ² test at a generous threshold.
   - A mutant that favours low site indices must fail it.
3. **A nearly full and a full world.**
   - The runs: 50×50 with 2,490 citizens, and with 2,500, replacement on, `max_age = 5,10`, so a few agents die each
     period and the newcomers must find the few empty sites. Both use `--check`.
   - Each run ends, its invariants hold, and the population stays constant. This exercises the scan of section 2.
   - If validation refuses a population equal to the site count, the full case is 2,499 citizens.
4. **Newcomer attributes.** `founder_ages = zero`, so agents younger than t are newcomers. Agents of age 0 at a dump
   were born that period and hold their exact draws:
   - vision is in range and a whole number of strides, with `look_stride = 5` and `vision = 5,20` (legal on 50×50);
   - metabolism, endowment (sugar) and `max_age` are in range;
   - `x` and `y` are in the world.
5. **No replacement, no change.** The existing goldens and parity tests cover this.
6. **Existing replacement tests stay**: `test_replacement_keeps_population` and
   `test_replacement_keeps_occupancy_consistent`.
7. **Metrics.** The goldens prove byte identity, and the existing `test_metrics_every` covers `--metrics-every`. A
   new test checks that the metrics CSV is byte-identical with and without `--timing`, since the timed path is the one
   the bridge uses.
8. **Source guards** (`test_sources.py`):
   - `host_state.cu` has no `newAgent(`;
   - `HostAgentAPI::getPopulationData()` is called only from `checks.cu`, the diagnostics.
9. **Performance and fidelity, measured once and not asserted in pytest** (*my call*: timing assertions are flaky):
   - `xl_validate` is rerun. II-4-gini must still agree with Python on every judged comparison.
   - The report records the new stepping and metrics timings. The expectation is II-4-gini stepping within about
     20% of II-4's, and metrics gathering under 1 ms per period at xl.

## Left to the builder

- Names: the environment properties for the newcomer ranges, the fingerprint line, the new functions.
- Where the bulk gathering lives (`host_state.cu` or `main.cu`), and the exact test thresholds within the
  constraints above.
- Whether `place_newcomer` early-exits by `x < 0` or by an agent-function condition. Prefer the simplest that
  measures well.
