# Python's agent order on the GPU: deferred-acceptance movement and in-order neighbour counts — Design

Date: 2026-10-25. Builds on the [Phase 1 design](2026-10-23-phase1-chapter2-gpu-design.md), whose movement rounds it
replaces, and on the [xl design](2026-10-24-xl-gpu-design.md). Requested by the user after the investigation summarised
under Intent: one design for both fixes, then the plan.

## Intent

The xl validation (`docs/validation/xl-chapter2.md`) has 14 disagreements with Python: 13 in II-6, 1 in II-8. A Python
harness that keeps Python's model but swaps parts of a period (scratch, not in the repository) found that both come
from the GPU doing at once what Python does one agent at a time.

- **II-6: how contested sites are resolved.** On the GPU every agent picks from the round's start state. The earliest
  agent in the period's order wins a contested site, and losers pick again next round. By then agents later in the
  order have taken sites the loser would have reached first in Python's order. In II-6's packed 200×200 block the
  wave front keeps losing, so it advances more slowly and fewer agents reach the north-east peak.
  - Python with the GPU's rounds reproduces the GPU: `moved` 21,860 / 24,070 / 28,580 at t = 4, 5, 10 (GPU 21,880 /
    24,100 / 28,600), and the north-east fraction −18% from t = 15 (GPU −14 to −16%).
  - Python with **deferred acceptance** (below) reproduces Python exactly: 5 xl seeds × 40 periods, every metric 0.0%.
  - Not the cause: sight of sites vacated during the period. A GPU spike that let agents see them changed no choice
    in 5 seeds × 300 periods at xl. A vacated site was harvested on arrival and is never anyone's best.
- **II-8 (and II-4's +7% at 50×50): when neighbours are counted.** The GPU counts after everyone has moved; Python counts
  each agent right after its own move and metabolism.
  - Python's own moves with the GPU's counting reproduce the GPU's mean neighbours: the spikes (+31% at t = 1, +46% at
    t = 102) and the steady −4 to −6% after diffusion starts (GPU −5 to −8%). Its moves, population and on-peak
    fraction stay identical to Python's.
  - Counting in order instead brings mean neighbours within 0–2% of Python at every period checked (5 xl seeds × 200
    periods). Fixing movement alone leaves it at −5 to −8%.
  - The report's claim that the shortfall is "a separate effect", because its sign is opposite to the spikes', is
    wrong: both come from counting after everyone has moved.

## Goals

1. **Movement reaches Python's outcome.** Each agent ends on the best site it sees among those free at the period's
   start and not taken by an agent earlier in the order, as Python's one-at-a-time rule M gives.
2. **Neighbour counts are Python's.** Each agent's count is the occupied von Neumann sites as they stand at its turn:
   earlier agents at their new sites if they survived metabolism, later agents still at their old sites.
3. **The xl validation agrees** for II-6 and II-8, apart from what the residual below explains. The 50×50 replication
   report keeps its statuses or explains each change.
4. **An exact test** proves Goals 1 and 2 period by period, not only statistically.

## Non-goals

- **Offering sites vacated during the period.** Python lets a later agent take a site an earlier agent left. Deferred
  acceptance offers only sites free at the start. In II-6 this never matters. At 50×50 with random starts it changes
  about 1 move in 180 in period 1 and under 1% after (harness, II-1 and II-4). The current GPU has the same gap. Left
  for later; Verification measures it.
- Rules outside Chapter II, and the 2500×2500 benchmark.
- Matching Python's random stream. Agreement stays statistical, except in the exact test, which reads the GPU's own
  draws.

## Anti-goals

- **No silent fidelity regression.** Every experiment's 50×50 and xl results are rerun and every status change is
  explained.
- **No hang.** Movement always ends, and a round limit still reports an error (exit 4).
- **No order bias from ties.** Two agents must almost never share a priority. Today's 20-bit priority ties about 760
  times a period at 40,000 agents.

## Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, `scripts\build.cmd`, telemetry off.
- **Context7** lookups before FLAME GPU code is written.
- **Macro-property rule:** within a layer, a macro property is only read or only atomically written.
- **World size:** nothing may assume 500×500.
- **Every GPU output changes.** All four golden cases are regenerated once, and every saved GPU result becomes stale.
  Approving this design approves that regeneration.

## Design

### 1. The period's order

- `start_period` draws two per-agent values:
  - **`priority`:** a 32-bit uniform draw through the 64-bit path, `uniform<uint64_t>(0, 2^32 − 1)`. Today it is 20
    bits through a float.
  - **`dir_order`:** one of the 24 permutations of the four directions, drawn once per period. Python draws its
    direction order once per period (`candidate_sites`). Today's scan reshuffles at every rescan.
    - Packed in 8 bits: the direction scanned i-th is `(dir_order >> 2i) & 3`, a VON_NEUMANN index (east, west,
      north, south).
- **The order key** is `priority << 32 | id`: larger means earlier in the order. It replaces `claim_key`, and has no
  round field.
- With both drawn once per period, a rescan of the same agent sees the same sites in the same order. Together with the
  look seed (xl design 2a), the rescan differs only in which sites are still available.

### 2. Deferred-acceptance movement (the movement sub-model)

Each agent has a movement state (`settled`): 0 = must scan, 1 = holding a bid, 2 = staying.

- **`propose`** (reads `occupied`, `sugar`, `pollution`, `claim`; writes nothing shared):
  - Staying agents return.
  - A holder whose bid still stands, `claim[target] == key`, returns.
  - Everyone else scans as today, with `dir_order` fixing the direction order. A site is available only if it was free
    at the start of the period (`occupied` is not changed during the sub-model) and `claim[site] < key`, meaning no
    earlier agent holds it.
  - The best available site, with own site as the baseline (score, then distance; ties keep the first in scan order),
    becomes `target`. If it is the agent's own site, the state becomes 2; otherwise 1, with a bid pending.
- **`bid`** (writes `claim`, `bids`; atomic only):
  - An agent with a pending bid does `claim[target].max(key)` and `++bids`.
  - Two bids on one site in the same round: the larger key, the earlier agent, holds it. The other notices next round.
- **Exit condition:**
  - If `bids` is 0, no claim changed, so nobody was displaced: exit.
  - Otherwise reset `bids` and run another round. Above `MAX_ROUNDS` (*my call*: 65,535), throw `RoundLimitError`
    (exit 4).
- **Why it ends and why it is Python's outcome.**
  - Every bid strictly raises a site's claim, so the rounds end.
  - Every site prefers earlier agents, so this is deferred acceptance with a common priority. Its unique stable outcome
    is serial dictatorship in priority order: Python's one-at-a-time rule over the start-free sites.
  - An agent's options only shrink over rounds, so a staying agent's choice is final.
- **No moves happen inside the sub-model.**

### 3. After movement: commit, metabolism, counts

New main-model layer order:
1. start_period
2. movement sub-model
3. `commit_move`
4. metabolize
5. `count_neighbors`
6. place_newcomer (replacement only)
7. cell_grow
8. cell_commit
9. diffusion

- **`commit_move`** (citizen; writes `occupied`, `sugar`, `pollution`, `left`, `arrived`):
  - Holders move to `target`: `occupied[own] = 0`, `occupied[target] = 1`, set `moved`, harvest the target, and add
    production pollution.
  - Stayers harvest their own site.
  - Everyone records `left[start] = key` and `arrived[final] = key`.
  - Targets were free at the start and are distinct, and starts are distinct, so no two agents write the same site.
- **`metabolize_and_age`:** as now. A citizen that starves also clears `arrived[its site]` (exchange 0).
  - A citizen dying of old age does not clear it. Python removes starved agents at their turn, but old-age deaths
    only at the end of the period, so later agents still count those as neighbours.
- **`count_neighbors`** (reads `arrived`, `left`): a neighbour site s counts for the agent with key k when
  `arrived[s] > k` (an earlier agent ended there and survived) or `0 < left[s] < k` (a later agent started there and
  has not moved yet).
  - The agent's own site is not a neighbour.
  - Newcomers (placed afterwards) are not counted, as in Python, and keep 0.
- **`cell_commit`** also clears `left` and `arrived`, as it clears `claim`, so every period starts empty.
- **New site-sized `uint64_t` macro properties:** `left` and `arrived`. Device memory grows by 2 × 8 bytes per site.
  No host function touches them (xl design 3).

### 4. Outputs, results and docs

- **`--dump-agents` gains `id`, `priority`, `dir_order` and `look_seed` columns** (*my call*): the period's order and
  looks, for the exact test. Existing readers key on named columns.
- **`GPU_FINGERPRINT` becomes `gpu-phase2`**, so every saved GPU result reads as stale. The replacement line from
  2026-10-25 stays.
- **The goldens:** `make_golden.py` is run once, and all four cases change. `test_golden.py`'s docstring records why.
- **Rerun** every Chapter II experiment at 50×50 (`gpu_run II`, `gpu_report --chapter II`) and the xl validation, and
  regenerate `docs/validation/xl-chapter2.md` with a rewritten reading. The II-8 paragraph's "separate effect" claim is
  corrected.
- **The Phase 1 design's movement section** gets a superseded-by note.

## Verification (pytest, in `flamegpu/tests/`)

1. **Exact movement test** (Goal 4):
   - Run a scenario twice with one seed (runs are deterministic), dumping at t − 1 and at t. Use 50×50, 400 agents in a
     20×20 block, look stride 1, no replacement, a few periods with many conflicts.
   - No pollution. The GPU scores sites in float32 and the reference in float64, so ties could break differently with
     fractional scores. Without pollution, scores are whole sugar amounts.
   - No deaths. An agent that dies in period t is missing from the t dump with its order values, so it can't be
     replayed. Use immortal agents with a large endowment and early periods.
   - A Python reference in the test recomputes period t by serial dictatorship from the t − 1 dumps (positions,
     landscape, occupancy) and the t dump's `priority` and `dir_order`.
   - Every agent's final site must equal the GPU's.
   - It must fail on today's movement rounds (watched RED).
   - A second scenario uses look stride 5 (vision 5–20). The reference recomputes the hashed looks from the dumped
     `look_seed` with the same `mix32`/`look_distance` formulas, so this case is exact too.
2. **Exact neighbour test:** from the same dumps, recompute each surviving agent's in-order count and require equality.
   It must fail on today's counting.
   - **Deaths, which the exact tests can't replay:**
     - Old age: an agent dying of old age is still counted by its neighbour, in every order. A deterministic test.
     - Starvation: across many seeds, an agent next to a starving one counts it about half the time, when the starving
       agent comes later in the order. Today's GPU counts it every time. A statistical test.
3. **Unchanged guards:**
   - Parity tests (order-independent scenarios) still match Python.
   - `--check` invariants and the replacement tests still hold.
   - A full lattice still ends with everyone staying.
4. **Round limit:** a crowded 50×50 world (2,490 agents, vision 6) ends in far fewer than `MAX_ROUNDS` rounds.
5. **Statistical, measured once:**
   - The xl validation: II-6 and II-8 should agree. Any disagreement left is reported with the residual's size.
   - At 50×50: II-4's mean neighbours against Python (+7% in Phase 1) should fall to about 0.
   - Timing: stepping per period for every experiment against today's, reported, not asserted.

## Left to the builder

- Variable and function names beyond those fixed above, and how `dir_order` is packed.
- The exact-test scenario's size and periods, within the constraints above.
- Whether `count_neighbors` reads `left` and `arrived` as two properties or one packed one. Prefer the simplest that
  passes the exact test.
