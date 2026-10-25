# Replacement on the Device and Fast Metrics Gathering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the two host-side per-agent costs that dominate xl periods: metrics gathering (about 9.5 ms) and
replacement (about 4.7 ms). Metrics stay byte-identical; replacement keeps Python's distribution.

**Architecture:**
- `main` steps the simulation itself, and gathers each metrics row between steps with
  `CUDASimulation::getPopulationData` into one host `AgentVector`, read through its column pointers.
- Dying citizens output their own newcomers in `metabolize_and_age`.
- A new citizen layer, `place_newcomer`, claims a uniformly random empty site for each newcomer with
  `occupied[site].CAS(0, 1)`.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), pytest, the Python bridge in `flamegpu/bridge/`.

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-replacement-metrics-design.md`

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080 (compute capability 89), telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`, seatbelts on, used by pytest) and `scripts\build.cmd build-fast OFF`
  (timings). Run all commands from `flamegpu/`.
- **Context7:** look up the FLAME GPU API (`/websites/flamegpu`) before writing FLAME GPU code. Each task names the
  lookups it needs.
- **Macro-property rule:** within a layer, a macro property is only read or only atomically written.
- **No run without replacement changes.** Its outputs stay byte-identical. The replacement birth output and the
  `place_newcomer` layer are added only when `cfg.replacement`.
- **Golden runs** (`tests/data/golden/`):
  - `block_seasons`, `diffusion`, and `gini_t0`'s `agents.csv` and `landscape.csv` never change.
  - `gini_t0/metrics.csv` and `gini_t30/*` are regenerated exactly once, in Task 2, with `tests\make_golden.py`.
- **Nothing may assume 500×500.**
- **The suite** is `.venv\Scripts\python -m pytest tests -q`. Redirect long output to a file and read its tail.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A population that dies out (no replacement).** Metrics rows must keep coming, with population 0 and nan means,
   when `getPopulationData` returns an empty vector, whose column pointers may be null. Pinned by
   `test_metrics_after_extinction` (Task 1).
2. **A tiled world (`--tile 2`) with replacement.** Newcomers must land anywhere in the tiled world, not only in the
   first tile; `place_newcomer` must use the tiled width and height. Pinned by `test_newcomers_use_tiled_world`
   (Task 2).
3. **`--metrics-every` above 1 with replacement, together with `--dump-at`.** The rows and the dump of the same
   period must both appear. Pinned by `test_metrics_every_with_replacement_and_dump` (Task 2).
4. **Seatbelts.** The `build\` binary checks macro-property access. `CAS` in `place_newcomer` must not trip the
   read-after-write check. All replacement tests run on `build\` (seatbelts on).
5. **The t = 0 row with `--init`.** The row is made from the `--init` agents' `AgentVector`, in file order. Pinned by
   the existing parity tests that compare t = 0 metrics with Python. Task 1 runs them, unchanged.

---

### Task 1: Gather metrics in bulk between steps

**Files:**
- Modify: `src/main.cu` (the `simulation.simulate()` call and the lines around it)
- Modify: `src/host_state.cu`, `src/host_state.h` (`write_metrics`, `finish_init`, `end_period`)
- Test: `tests/test_sources.py`, `tests/test_metrics.py`

**Interfaces:**
- Produces: `void write_metrics(flamegpu::CUDASimulation* simulation, flamegpu::AgentVector& citizens, unsigned int t)`
  in `host_state.cu`.
  - With a simulation, it first refreshes `citizens` with `simulation->getPopulationData(citizens)`.
  - With `nullptr`, it reads `citizens` as given; this is the t = 0 row from the founders.
  - It is a no-op without `--out`, or when `t % metrics_every != 0`.
  - It adds the copy, the column fill and `compute_metrics` to `s.metrics_seconds`, but not the CSV write.
- Produces: `main` runs `for (unsigned int t = 1; t <= cfg.steps; ++t) { simulation.step(); write_metrics(&simulation, metrics_pop, t); }`
  - `metrics_pop` is one `flamegpu::AgentVector(model.Agent("citizen"))`, reused across periods.
  - The t = 0 row is `write_metrics(nullptr, citizens, 0)`, made before the loop.

- [ ] **Step 1: Context7 lookups.** Query `/websites/flamegpu` for `CUDASimulation::step` and
  `CUDASimulation::getPopulationData(AgentVector&)`. Confirm that `step()` alone is enough when there are no init
  or exit functions; the source of `simulate()` in `build-fast\_deps\flamegpu2-src` shows what it adds. Also confirm
  that `AgentVector::data<T>(name) const` is public.

- [ ] **Step 2: Write the failing tests**

In `tests/test_sources.py`:

```python
POPULATION_READ = re.compile(r"\.getPopulationData\(\)")  # HostAgentAPI's per-agent DeviceAgentVector


def _between(text, start, end_pattern):
    i = text.index(start)
    m = re.compile(end_pattern).search(text, i + len(start))
    return text[i:m.start() if m else len(text)]


def test_metrics_not_read_per_agent():
    # Metrics are gathered in bulk between steps (spec 2026-10-25, section 4); only replace_dead may still read
    # agents through DeviceAgentVector in timed host code (until Task 2), and the diagnostics in checks.cu.
    text = (SRC / "host_state.cu").read_text(encoding="utf-8")
    outside = text.replace(_between(text, "FLAMEGPU_HOST_FUNCTION(replace_dead)", r"\nFLAMEGPU_|\Z"), "")
    assert not POPULATION_READ.search(outside)
    for name in ("main.cu", "metrics.cu", "model.cu"):
        assert not POPULATION_READ.search((SRC / name).read_text(encoding="utf-8")), name
```

In `tests/test_metrics.py`:

```python
def test_csv_same_with_and_without_timing(exe, tmp_path):
    (tmp_path / "a").mkdir(); (tmp_path / "b").mkdir()
    _, plain = _run(exe, tmp_path / "a", steps=15)
    _, timed = _run(exe, tmp_path / "b", steps=15, extra=("--timing", tmp_path / "b" / "t.json"))
    assert plain.read_bytes() == timed.read_bytes()


def test_metrics_after_extinction(exe, tmp_path):
    # A sugarless world: everyone starves in period 1 (endowment 1, metabolism 1, no replacement); rows continue
    # with population 0.
    _, out = _run(exe, tmp_path, {"endowment": "1,1", "metabolism": "1,1"}, steps=4,
                  capacity=np.zeros((50, 50), dtype=int))
    rows = read_rows(out)
    assert [r["t"] for r in rows] == list(range(5))
    assert rows[-1]["population"] == 0 and math.isnan(rows[-1]["mean_vision"]) and math.isnan(rows[-1]["gini"])
```

- [ ] **Step 3: Run them.**
  Run: `.venv\Scripts\python -m pytest tests/test_sources.py tests/test_metrics.py -q`
  Expected:
  - `test_metrics_not_read_per_agent` FAILS on `write_metrics`' `getPopulationData()`.
  - The two metrics tests PASS. They characterise today's behaviour, and the change must keep them.

- [ ] **Step 4: Implement `write_metrics(CUDASimulation*, AgentVector&, unsigned)`.**
  - Fill `AgentColumns` from `const flamegpu::AgentVector&`'s `data<int>/data<float>/data<unsigned int>` pointers.
  - Guard size 0 before dereferencing.
  - Remove the metrics calls from `finish_init` and `end_period`.
  - In `main`, replace `simulation.simulate()` with the t = 0 row and the step loop. `simulate_seconds` times
    the loop. Keep `SimulationConfig().steps` set.
  - Update the `metrics_seconds` and `finish_init` comments in `host_state.h`.

- [ ] **Step 5: Build and run the tests.**
  - Run: `cmd /c scripts\build.cmd`
  - Then: `.venv\Scripts\python -m pytest tests -q > %TEMP%\suite.txt` (read the tail).
  - Expected: all pass, the 4 golden cases included, byte for byte.

- [ ] **Step 6: Measure.**
  - Build: `cmd /c "scripts\build.cmd build-fast OFF"`.
  - Run 200 periods of the II-4 xl config, with `--out` and `--timing`. Make the config with `bridge.config_cfg` from
    `experiment_config("II-4", True)`, as `gpu_run` does.
  - Expected: `metrics_s / 201` under 1 ms. It was about 10 ms. Record the number in the commit message.

- [ ] **Step 7: Commit.**

```bash
git add src/main.cu src/host_state.cu src/host_state.h tests/test_sources.py tests/test_metrics.py
git commit -m "flamegpu: gather metrics in bulk between steps (byte-identical rows; xl metrics <N> ms/period, was ~10)"
```

### Task 2: Replacement on the device

**Files:**
- Modify: `src/rules.cuh` (`metabolize_and_age`; new `place_newcomer`)
- Modify: `src/model.cu` (`describe_model`: output, layer, environment properties)
- Modify: `src/host_state.cu`, `src/host_state.h` (remove `replace_dead`; births in `end_period`; `rng` comment)
- Modify: `bridge/gpu_run.py`, `bridge/gpu_report.py` (fingerprint)
- Create: `tests/test_replacement.py`
- Modify: `tests/test_sources.py`, `tests/test_bridge.py`, `tests/test_golden.py` (docstring), `tests/test_invariants.py` (comment)
- Regenerate: `tests/data/golden/gini_t0/metrics.csv`, `tests/data/golden/gini_t30/{agents,landscape,metrics}.csv`

**Interfaces:**
- Consumes: Task 1's `write_metrics`; `end_period` still reads and resets the `deaths` macro property.
- Produces:
  - **Environment properties** (main model): `replacement` (`unsigned int`, 0 or 1), and the `int` ranges
    `vision_lo`, `vision_hi`, `metabolism_lo`, `metabolism_hi`, `endowment_lo`, `endowment_hi`, `max_age_lo` and
    `max_age_hi`.
  - **Constant** `PLACE_TRIES = 4096` in `rules.cuh`.
  - **Fingerprint:** `def gpu_fingerprint(exp_id: str, xl: bool = False) -> str` in `bridge/gpu_run.py`. It returns
    `GPU_FINGERPRINT + REPLACEMENT_FINGERPRINT + fingerprint(id, xl)` when `experiment_config(id, xl).replacement`,
    and `GPU_FINGERPRINT + fingerprint(id, xl)` otherwise, with `REPLACEMENT_FINGERPRINT = "replacement: device\n"`.
    `gpu_run` writes it, and `gpu_report.gpu_current` compares with `gpu_fingerprint(exp_id)`.

- [ ] **Step 1: Context7 lookups.** Query `/websites/flamegpu` for:
  - `setAgentOutput` with `setAllowAgentDeath` in one function, and `agent_out.setVariable`;
  - `DeviceMacroProperty::CAS`;
  - `random.uniform<int>(min, max)`, to confirm both bounds are inclusive.

- [ ] **Step 2: Write the failing tests.** `tests/test_replacement.py` uses `run_gpu` and `read_rows` from
  `tests/gpu.py`.

```python
EVERYONE_DIES = {"initial_population": "250", "max_age": "1,1", "replacement": "true", "founder_ages": "zero"}

def test_newcomers_land_uniformly(exe, tmp_path):
    # Everyone dies every period, so each dump holds 250 newcomers placed on an empty 50x50 world.
    counts = np.zeros(25)
    for seed in range(8):
        for t in (3, 7, 11):
            d = tmp_path / f"{seed}_{t}"; d.mkdir()
            dump = run_gpu(exe, d, {**EVERYONE_DIES, "seed": str(seed)}, steps=t)
            assert dump.returncode == 0, dump.stderr
            sites = {(a["x"], a["y"]) for a in dump.agents}
            assert len(sites) == 250 and all(a["age"] == 0 for a in dump.agents)
            for x, y in sites:
                counts[(x // 10) + 5 * (y // 10)] += 1
    expected = counts.sum() / 25
    chi2 = ((counts - expected) ** 2 / expected).sum()
    assert chi2 < 60  # 24 degrees of freedom: p ~ 1e-4 at 60; a half-world bias gives chi2 in the thousands

@pytest.mark.parametrize("population", [2490, 2500])
def test_crowded_world_places_everyone(exe, tmp_path, population):
    cfg = {"initial_population": str(population), "max_age": "5,10", "replacement": "true", "endowment": "25,50"}
    dump = run_gpu(exe, tmp_path, cfg, steps=40, extra_args=("--check",))
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == population

def test_newcomer_attributes(exe, tmp_path):
    cfg = {"initial_population": "400", "max_age": "3,8", "replacement": "true", "founder_ages": "zero",
           "look_stride": "5", "vision": "5,20", "endowment": "5,25", "metabolism": "1,4"}
    dump = run_gpu(exe, tmp_path, cfg, steps=12)
    assert dump.returncode == 0, dump.stderr
    born = [a for a in dump.agents if a["age"] == 0]
    assert len(born) > 20
    for a in born:
        assert a["vision"] % 5 == 0 and 5 <= a["vision"] <= 20
        assert 1 <= a["metabolism"] <= 4 and 5 <= a["sugar"] <= 25 and a["sugar"] == int(a["sugar"])
        assert 3 <= a["max_age"] <= 8 and 0 <= a["x"] < 50 and 0 <= a["y"] < 50

def test_newcomers_use_tiled_world(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, EVERYONE_DIES, steps=5, extra_args=("--tile", "2"))  # 100x100, 1000 agents
    assert dump.returncode == 0, dump.stderr
    outside = sum(1 for a in dump.agents if a["x"] >= 50 or a["y"] >= 50)
    assert 0.65 < outside / len(dump.agents) < 0.85  # three tiles in four

def test_metrics_every_with_replacement_and_dump(exe, tmp_path):
    out = tmp_path / "m.csv"
    dump = run_gpu(exe, tmp_path, {**EVERYONE_DIES, "max_age": "2,4"}, steps=9, dump_at=6,
                   extra_args=("--out", out, "--metrics-every", "3"))
    assert dump.returncode == 0, dump.stderr
    assert [r["t"] for r in read_rows(out)] == [0, 3, 6, 9] and len(dump.agents) == 250
```

  In `tests/test_sources.py`, replace Task 1's `test_metrics_not_read_per_agent` with
  `test_agent_data_read_only_in_diagnostics`:
  - `POPULATION_READ` must not appear anywhere in `TIMED_HOST_SOURCES`;
  - `host_state.cu` must not contain `newAgent(`.

  In `tests/test_bridge.py`, add `test_replacement_fingerprint`:
  - `gpu_fingerprint("II-4-gini")` contains `"replacement: device\n"`;
  - `gpu_fingerprint("II-4") == GPU_FINGERPRINT + fingerprint("II-4")`.

- [ ] **Step 3: Run them.**
  Run: `.venv\Scripts\python -m pytest tests/test_replacement.py tests/test_sources.py tests/test_bridge.py -q`
  Expected:
  - The source guard and `test_replacement_fingerprint` FAIL (`ImportError: gpu_fingerprint`).
  - The five `test_replacement.py` tests PASS on today's host replacement. They pin the rule's distribution, and the
    device version must keep it.

- [ ] **Step 4: Implement.**
  - **`metabolize_and_age`:** when `replacement`, a dying citizen sets the newcomer's variables through `agent_out`
    as spec section 1 says: `x` and `y` are −1, `age` is 0, and vision is `stride * U[lo/stride, hi/stride]`.
  - **`place_newcomer`:** as spec section 2, using the env `width` and `height`. The scan fallback after
    `PLACE_TRIES` misses starts from the last draw and wraps.
  - **`describe_model`:** `setAgentOutput(citizen)` and the `place_newcomer` layer in place of `replace_dead` and
    the `occupy_site` layer after it, both only when `cfg.replacement`. Add the env properties.
  - **Host bookkeeping:** remove `replace_dead` (and its declaration). `end_period` passes
    `births = cfg.replacement ? deaths : 0` to `check_invariants`; drop `RunState::births` if nothing else uses it.
  - **Bridge:** add `gpu_fingerprint`, and use it in `gpu_run` and `gpu_report`.

- [ ] **Step 5: Build and run the tests.**
  - Run: `cmd /c scripts\build.cmd`
  - Then: `.venv\Scripts\python -m pytest tests -q > %TEMP%\suite.txt`
  - Expected: everything passes except `test_matches_golden[gini_t0]` (metrics.csv only) and
    `test_matches_golden[gini_t30]`. Any other failure is a bug, not a golden to regenerate.

- [ ] **Step 6: Mutant check.**
  - Temporarily make `place_newcomer` draw from `[0, cells / 2)`, rebuild, and run
    `pytest tests/test_replacement.py::test_newcomers_land_uniformly`.
  - Expected: FAIL (χ² far above 60).
  - Revert, rebuild, and confirm it passes.

- [ ] **Step 7: Regenerate the goldens.**
  - Run: `.venv\Scripts\python tests\make_golden.py`, then `git diff --stat tests/data/golden`.
  - Expected: exactly `gini_t0/metrics.csv`, `gini_t30/agents.csv`, `gini_t30/landscape.csv` and
    `gini_t30/metrics.csv` changed. Anything else means stop and debug.
  - Add to `test_golden.py`'s docstring: the replacement cases were regenerated on 2026-10-25, with the user's
    approval, when replacement moved to the device (spec 2026-10-25); its random stream changed by design.
  - Then run the whole suite. Expected: all pass.

- [ ] **Step 8: Measure.**
  - Build: `cmd /c "scripts\build.cmd build-fast OFF"`.
  - Run 200 xl periods of II-4-gini and of II-4 with `--timing`.
  - Expected: II-4-gini `stepping_s / 200` within about 20% of II-4's (spike: 0.84 ms against 0.73).

- [ ] **Step 9: Commit.**

```bash
git add src tests bridge
git commit -m "flamegpu: replacement on the device (newcomers born in metabolize_and_age, placed by CAS); regenerate the gini goldens"
```

### Task 3: Refresh results, report and docs

**Files:**
- Modify: `docs/validation/xl-chapter2.md` (regenerated, plus its hand-written "Reading these results")
- Modify: `docs/superpowers/specs/2026-10-24-xl-gpu-design.md` (section 3's `replace_dead` bullet: a note that it is
  superseded by the 2026-10-25 design)
- Modify: `README.md`, if it describes replacement or metrics gathering on the host
- Regenerate (git-ignored): `results-gpu/II-4-gini/`, `results-gpu/REPORT.md`, `results-gpu-xl/`, `results-gpu-xl-fast/`

**Interfaces:** Consumes Tasks 1–2 and both builds.

- [ ] **Step 1: Rebuild both builds** (`scripts\build.cmd`; `scripts\build.cmd build-fast OFF`).

- [ ] **Step 2: Rerun the 50×50 replacement experiment and the GPU report.**
  - Run: `.venv\Scripts\python -m bridge.gpu_run II-4-gini`
  - Then: `.venv\Scripts\python -m bridge.gpu_report --chapter II`
  - Expected: II-4-gini is no longer reported stale; its two targets keep their status (pass, pass).

- [ ] **Step 3: Rerun the xl validation.**
  - Run: `.venv\Scripts\python -m bridge.xl_validate > %TEMP%\xlv.txt`
  - Expected:
    - it uses `<root>/results-xl/` (Python, unchanged) and rewrites the report;
    - II-4-gini agrees on every judged comparison;
    - the other experiments' verdicts are unchanged, since their runs are byte-identical.

- [ ] **Step 4: Update the report's reading.**
  - Rewrite the timing paragraphs from the new `timing.csv` files: II-4-gini against II-4, and `metrics_s` per period
    for every experiment.
  - State that the Python II-4-gini timing in `results-xl/` predates main's commit 77ffcb6, and quote `docs/xl.md`'s
    1.13 s per period.
  - Keep every disagreement listed.

- [ ] **Step 5: Run the whole suite** (`pytest tests -q`). Expected: all pass.

- [ ] **Step 6: Commit.**

```bash
git add docs README.md
git commit -m "flamegpu: refresh the xl report for device replacement and bulk metrics"
```
