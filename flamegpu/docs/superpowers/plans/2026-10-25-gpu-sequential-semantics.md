# Python's Agent Order on the GPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GPU movement and neighbour counts reach Python's one-agent-at-a-time outcome:
- deferred-acceptance movement over the period's order;
- in-order neighbour counts.

This removes the II-6 and II-8 disagreements.

**Architecture:**
- Each citizen draws a 32-bit `priority` and a `dir_order` once per period.
- **Movement:** the movement sub-model runs propose/bid rounds whose claims hold across rounds, keyed by
  `priority << 32 | id`, until a round makes no bid. A new `commit_move` layer then moves everyone at once.
- **Neighbour counts:** they move after metabolism and read per-site `left`/`arrived` order keys.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), pytest, the Python bridge in `flamegpu/bridge/`.

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-sequential-semantics-design.md`

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`, seatbelts on, used by pytest) and `scripts\build.cmd build-fast OFF`
  (timings). Run all commands from `flamegpu/`.
- **Context7:** look up the FLAME GPU API (`/websites/flamegpu`) before writing FLAME GPU code. Each task names its
  lookups.
- **Macro-property rule:** within a layer, a macro property is only read or only atomically written. Every write in
  `commit_move` and `cell_commit` uses `exchange` or `min`/`max`.
- **Goldens fail in Tasks 1–3 by design.** Every GPU output changes from Task 1 on, so the four `test_matches_golden`
  cases are expected to fail until Task 4 regenerates them, once. Each task's suite run deselects them and says so in
  the ledger. Any other failure is a bug.
- **Nothing may assume 500×500.** New site-sized properties are `uint64_t` of `MAX_CELLS`. No host function touches
  them.
- **The suite** is `.venv\Scripts\python -m pytest tests -q`.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Replacement runs.** Newcomers are placed after `count_neighbors`. They must not appear in this period's
   `left`/`arrived`, and they move normally next period. Pinned by the existing `test_replacement.py` and
   `test_invariants.py` runs with `--check` (Tasks 2 and 3).
2. **Look stride above 1.** A rescan must see the same hashed looks and `dir_order`. Pinned by
   `test_movement_is_serial_dictatorship_with_stride` (Task 2).
3. **A world where nobody can move** (full lattice). The sub-model must exit after one round with `bids` = 0. Pinned by
   the existing `test_full_lattice_everyone_stays` (Task 2).
4. **Seatbelts.** `propose` reads `claim`, `bid` writes it, and `commit_move` writes five site properties. Each may
   only read or only atomically write a given property. All new tests run on `build\`.
5. **Stale per-site keys.** `left`/`arrived` from period t must never be read in period t + 1, when every priority is
   new. Pinned by the exact neighbour test over several consecutive periods (Task 3).

---

### Task 1: The period's order — 32-bit priority, `dir_order`, and dump columns

**Files:**
- Modify: `src/rules.cuh` (`start_period`), `src/movement.cuh` (`claim_key` → `order_key`; `scan` uses `dir_order`)
- Modify: `src/model.cu` (citizen variable `dir_order` in the model and the movement sub-model)
- Modify: `src/checks.cu` (`CitizenRow`, `citizens()`, the agent dump header and rows)
- Create: `tests/test_sequential.py`

**Interfaces:**
- **Produces:**
  - citizen variable `priority` (`unsigned int`, all 32 bits used), drawn as
    `static_cast<unsigned int>(FLAMEGPU->random.uniform<uint64_t>(0, 0xFFFFFFFFull))`;
  - citizen variable `dir_order` (`unsigned int`): the direction scanned i-th is `(dir_order >> 2i) & 3`, a
    VON_NEUMANN index, drawn once per period as a uniform permutation;
  - `__device__ uint64_t order_key(unsigned int priority, flamegpu::id_t id)` = `priority << 32 | id`, where larger
    means earlier;
  - agents.csv gains, after `neighbors`, the columns `id,priority,dir_order,look_seed` (`look_seed` is 0 at stride 1).
- **Consumes:** `scan` keeps its claim/resolve rounds until Task 2, but with the claim key `order_key` (no round field)
  and the direction order from `dir_order`.

- [ ] **Step 1: Context7 lookups.** Query `/websites/flamegpu` for `DeviceAPI::getID` (the `id_t` width) and
  `AgentRandom::uniform<uint64_t>`.

- [ ] **Step 2: Write the failing test** in `tests/test_sequential.py`:

```python
BLOCK = {"placement": "block", "block": "0,0,20,20", "initial_population": "400", "vision": "1,6"}

def test_period_order_in_dump(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, BLOCK, steps=3)
    assert dump.returncode == 0, dump.stderr
    orders = [[(a["dir_order"] >> (2 * i)) & 3 for i in range(4)] for a in dump.agents]
    assert all(sorted(o) == [0, 1, 2, 3] for o in orders)
    assert len({tuple(o) for o in orders}) == 24  # 400 draws reach every permutation
    assert len({a["priority"] for a in dump.agents}) == 400  # 32 bits: no ties at 400
    assert max(a["priority"] for a in dump.agents) > 2 ** 20  # not today's 20 bits
    assert len({a["id"] for a in dump.agents}) == 400
```

- [ ] **Step 3: Run it.** Run `pytest tests/test_sequential.py -q`. Expected: FAIL with `KeyError: 'dir_order'`.

- [ ] **Step 4: Implement.** `start_period` draws `priority` and `dir_order`. The look seed stays as now, drawn only
  when the stride is above 1. Draw the permutation as a Fisher–Yates over 4 with clamped `uniform<int>`, as `scan`
  does today. Then `scan` stops shuffling and reads `dir_order`, and the `claim_key` uses become `order_key`. Finally
  the dump writes `id,priority,dir_order,look_seed`.

- [ ] **Step 5: Build and test.**
  - Run `cmd /c scripts\build.cmd`, then the suite with
    `--deselect tests/test_golden.py::test_matches_golden`.
  - Expected: all pass. The goldens fail as expected; check that only those fail.

- [ ] **Step 6: Commit.**

```bash
git add src tests/test_sequential.py
git commit -m "flamegpu: draw the period's order once — 32-bit priority, dir_order; dump id, priority, dir_order"
```

### Task 2: Deferred-acceptance movement and `commit_move`

**Files:**
- Modify: `src/movement.cuh` (`scan`/`resolve` → `propose`/`bid`; exit condition; new `commit_move`)
- Modify: `src/model.cu` (sub-model layers, the `bids` scalar macro, the `commit_move` layer after the sub-model)
- Test: `tests/test_sequential.py`

**Interfaces:**
- **Consumes:** Task 1's `order_key`, `priority` and `dir_order`.
- **Produces:**
  - movement state `settled`: 0 = must scan, 1 = holding a bid, 2 = staying;
  - the scalar macro `bids` (`unsigned int`) in the model and the sub-model environment;
  - `MAX_ROUNDS = 65535`;
  - `commit_move` (citizen) as spec section 3: move or harvest own site, set `moved`, add production pollution.
    Task 3 adds the `left`/`arrived` writes.

- [ ] **Step 1: Context7 lookups.** Query `/websites/flamegpu` for exit conditions reading and writing a scalar
  macro property (`HostMacroProperty` assignment), and for sub-model macro-property auto-mapping.

- [ ] **Step 2: Write the failing tests** in `tests/test_sequential.py`:
  - **`serial_dictatorship(prev, cur, width, height, stride=1) -> dict[int, tuple[int, int]]`**, a test helper. It
    takes, from the t − 1 dump, each agent's start site and vision, the landscape sugar, and the occupancy. From the t
    dump it takes `priority`, `dir_order` and `look_seed` by `id`. It processes agents in descending `(priority, id)`:
    - the baseline is the agent's own site's sugar at distance 0;
    - it scans the directions in `dir_order`, wrapping the torus. The distances are 1..vision, or with a stride s > 1
      `look_distance(look_seed, d, k, s)` for k in `range(vision // s)`. That is a Python copy of `movement.cuh`'s
      `mix32`/`look_distance` on 32-bit unsigned arithmetic (mask with `0xFFFFFFFF` after each multiply);
    - it skips sites occupied at t − 1 or taken by an earlier agent;
    - a site replaces the best if its sugar is higher, or equal at a shorter distance;
    - it returns each `id`'s final site.
  - **The first test:**

```python
DEATHLESS = {**BLOCK, "endowment": "25,50", "max_age": ""}  # immortal, no starvation by t = 6

@pytest.mark.parametrize("t", [2, 3, 4, 5, 6])
def test_movement_is_serial_dictatorship(exe, tmp_path, t):
    prev = run_gpu(exe, tmp_path / "a", DEATHLESS, steps=t, dump_at=t - 1)
    cur = run_gpu(exe, tmp_path / "b", DEATHLESS, steps=t, dump_at=t)
    assert prev.returncode == cur.returncode == 0
    got = {a["id"]: (a["x"], a["y"]) for a in cur.agents}
    assert serial_dictatorship(prev, cur, 50, 50) == got
```

  (Create `tmp_path / "a"` and `tmp_path / "b"` first, as `test_metrics` does. For the t − 1 run the steps value is t,
  so both runs share every draw up to t.)

  - **`test_movement_is_serial_dictatorship_with_stride`:** `DEATHLESS` with `look_stride = 5` and `vision = 5,20`, at
    t = 2..5. `serial_dictatorship(prev, cur, 50, 50, stride=5)` equals the GPU's sites.

- [ ] **Step 3: Run them.** Run `pytest tests/test_sequential.py -q`. Expected: both serial-dictatorship tests FAIL on
  today's rounds for at least one t, with mismatched sites.

- [ ] **Step 4: Implement** spec section 2, plus `commit_move` from section 3 minus `left`/`arrived`. `resolve` goes
  away, and harvesting moves to `commit_move`.

- [ ] **Step 5: Build and test.**
  - Run `cmd /c scripts\build.cmd`, then the suite with the goldens deselected.
  - Expected: all pass, including `test_movement_is_serial_dictatorship` for every t, the parity tests,
    `test_full_lattice_everyone_stays`, the replacement tests, and `test_crowded_world_places_everyone`.

- [ ] **Step 6: Mutant check.**
  - Make `propose` ignore `claim` (so a site held by an earlier agent stays available), rebuild, and run the serial
    test. Expected: FAIL.
  - Revert.

- [ ] **Step 7: Commit.**

```bash
git add src tests/test_sequential.py
git commit -m "flamegpu: deferred-acceptance movement — claims held across rounds by order key; commit_move"
```

### Task 3: In-order neighbour counts

**Files:**
- Modify: `src/model.cu` (`left`, `arrived` site macros; layer order: `commit_move`, `metabolize`, `count_neighbors`,
  then `place_newcomer`)
- Modify: `src/movement.cuh` (`commit_move` writes `left`/`arrived`)
- Modify: `src/rules.cuh` (`metabolize_and_age` clears `arrived` on starvation only; `count_neighbors`; `cell_commit`
  clears `left`/`arrived`)
- Test: `tests/test_sequential.py`

**Interfaces:**
- **Consumes:** Task 2's `commit_move` and `order_key`.
- **Produces:**
  - site macros `left`, `arrived` (`uint64_t`, `MAX_CELLS`);
  - the count rule: a site s counts for key k when `arrived[s] > k || (left[s] != 0 && left[s] < k)`.

- [ ] **Step 1: Write the failing tests:**
  - **`in_order_neighbours(prev, cur, width, height) -> dict[int, int]`**, a test helper. Agents come from the t dump
    with their keys; start sites come from the t − 1 dump by `id`. For agent p, each of its four neighbour sites counts
    if an earlier agent ends there, or a later agent started there.
  - **`test_neighbours_in_order`:** with `DEATHLESS`, at t = 2..6, `in_order_neighbours(...)` equals each agent's
    dumped `neighbors`. Consecutive t values pin Review Focus 5.
  - **`test_old_age_neighbour_still_counted`:** a 10×10 map at uniform capacity 3. Agent A at (5,5) has `max_age` 1;
    agent B at (6,5) is immortal; both have vision 1. After 1 step, B's `neighbors` is 1.
  - **`test_starved_neighbour_counted_half_the_time`:** the same map. A at (5,5) has sugar 0.5 and metabolism 4 and
    starves in period 1; B at (6,5) is healthy. Over 60 seeds, the fraction of runs with B's `neighbors == 1` lies in
    [0.3, 0.7]. Today's GPU gives 1.0.

- [ ] **Step 2: Run them.** Expected: `test_neighbours_in_order` and `test_starved_neighbour_counted_half_the_time`
  FAIL. `test_old_age_neighbour_still_counted` PASSES; it is a guard for the starvation-only rule.

- [ ] **Step 3: Implement** spec section 3: the writes, the layer order, the count rule, and the clearing.

- [ ] **Step 4: Build and test.**
  - Run `cmd /c scripts\build.cmd`, then the suite with the goldens deselected.
  - Expected: all pass. `test_metrics.py`'s Python-formula checks still match, since they recompute from the dumps.

- [ ] **Step 5: Mutant check.**
  - Clear `arrived` on every death (old age included), rebuild, and run `test_old_age_neighbour_still_counted`.
    Expected: FAIL.
  - Revert.

- [ ] **Step 6: Commit.**

```bash
git add src tests/test_sequential.py
git commit -m "flamegpu: count neighbours in the period's order (left/arrived order keys), after metabolism"
```

### Task 4: Goldens, fingerprint, results, report, docs

**Files:**
- Modify: `bridge/gpu_run.py` (`GPU_FINGERPRINT = "gpu-phase2\n"`), `tests/test_golden.py` (docstring)
- Regenerate: `tests/data/golden/*/*`
- Modify: `docs/validation/xl-chapter2.md` (regenerated, plus the hand-written reading), the Phase 1 design (a
  superseded-by note on movement), `README.md` if it describes movement rounds
- Regenerate (git-ignored): `results-gpu/` (all of Chapter II), `results-gpu-xl/`, `results-gpu-xl-fast/`

- [ ] **Step 1: Fingerprint.** `test_bridge.py`'s `test_replacement_fingerprint` and `test_gpu_run_xl` compare against
  `GPU_FINGERPRINT`, so they follow the change. Run them. Expected: PASS.

- [ ] **Step 2: Regenerate the goldens.**
  - Run `.venv\Scripts\python tests\make_golden.py`, then `git diff --stat tests/data/golden`.
  - Expected: all four cases change.
  - Record in `test_golden.py`'s docstring that all cases were regenerated on 2026-10-25, with the user's approval of
    this design, because movement and counting moved to Python's order.
  - Run the full suite (nothing deselected). Expected: all pass.

- [ ] **Step 3: Rebuild both builds.** Then:
  - `.venv\Scripts\python -m bridge.gpu_run II --jobs 4`
  - `.venv\Scripts\python -m bridge.gpu_report --chapter II`
  - Expected: the report's GPU column is current. Note every status change against the previous report: GPU 36 pass,
    10 near, 3 fail. In particular, II-4's mean neighbours should move toward Python's 0.797 (it was 0.855).

- [ ] **Step 4: The xl validation.**
  - Run `.venv\Scripts\python -m bridge.xl_validate`.
  - Expected: II-6 and II-8 have no disagreement, or each remaining one is explained by the residual (vacated sites)
    with its size.

- [ ] **Step 5: Timing.** Compare stepping per period (fast build) for every experiment with the previous report's.
  Report the number of movement rounds if stepping grew by more than 20%.

- [ ] **Step 6: Rewrite the report's reading.**
  - The II-6 and II-8 findings (the harness evidence, the fixes, what remains).
  - Correct the II-8 "separate effect" claim.
  - The new timings.

- [ ] **Step 7: Commit.**

```bash
git add bridge tests docs README.md
git commit -m "flamegpu: regenerate goldens and the xl report for Python-order movement and neighbour counts"
```
