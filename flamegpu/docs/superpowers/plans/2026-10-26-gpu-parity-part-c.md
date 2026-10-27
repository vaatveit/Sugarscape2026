# Every Rule on the GPU, Part C: Chapter IV (Spice, Trade, Credit) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Python's Chapter IV on the GPU: spice, welfare movement with foresight and cultural preferences, trade T
with `trade_rounding`, credit L, and `economic_metrics`. The target is agreement with Python on Chapter IV, VI-2, VI-3,
their reproduction variants, and VAR-inttrade except VI-1's: 69 experiments.

**Architecture:**
- **Spice on both paths.** Spice is a second landscape layer and four citizen variables. The fast path harvests and
  burns it. Deferred acceptance scores sites with Python's `welfare_scorer`, in double. So IV-6/notrade and
  IV-13/notrade stay on today's layers (spec section 1).
- **Trade T** is one more neighbour rule in the turn, after K. Its partners are the four sites around the target,
  which are already in every footprint. Each turn keeps its own price statistics, and the period combines them in
  rank order.
- **Credit L, without inheritance, runs in waves:**
  - **The book:** a device array in Python's list order.
  - **Owed:** a borrower adds up what it owes from its own start-of-period loans whose lender is still alive at its
    turn, plus the loans of its own turn. Each such lender's site is in the borrower's footprint.
  - **This period's loans** wait in their borrower's row. After the turns, one device thread rebuilds the book:
    loans with a dead party go, and the new loans are appended in turn order.
  - **The end of the period** runs Python's old-age `on_death` and `settle_loans`, in order, on one device thread.
- **Inheritance with credit or spice** runs one turn per wave, like combat with inheritance. In that mode the book is
  changed in the turn, exactly as Python's list is.
- **`--check` sees rows.** It now also checks the rows a turn reaches by uid: friends' and lenders' rows. This is
  Part B's deferred minor.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), CUB (shipped with CUDA), pytest, the Python bridge in
`flamegpu/bridge/`.

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-full-parity-design.md`: Part C of "The work, in parts", and
sections 1, 2, 4, 5 and 8. The Part A plan (`2026-10-25-gpu-parity-part-a.md`) and the Part B plan
(`2026-10-26-gpu-parity-part-b.md`) describe the store, the waves and the tests this plan extends. The Python rules
are in `sugarscape/rules/` (`movement.py`, `welfare.py`, `trade.py`, `credit.py`, `sex.py`), `sugarscape/model.py`
and `sugarscape/stats.py` (`economic_metrics`). Each GPU function names the Python function it follows line for line.

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`, seatbelts on, used by pytest) and `scripts\build.cmd build-fast OFF`. Run
  every command from `flamegpu/`.
- **The suite** is `.venv\Scripts\python -m pytest tests -q`.
- **Context7** before FLAME GPU (`/websites/flamegpu`) or CUB code is written. Each task names its lookups.
- **Macro-property rule:** within a layer a macro property is only read, or only atomically written. During the turns,
  the `spice` macro property is neither read nor written; the store's `site_spice` stands in for it, as `site_sugar`
  does for sugar.
- **No change to Chapter II or Part A/B outputs:**
  - Every new draw is gated by `spice`, `foresight`, `trade` or `credit`, as in Python.
  - Cell functions touch the spice layer only with spice on.
  - The goldens and every existing test pass unchanged.
  - `GPU_FINGERPRINT` stays `gpu-phase3`, and Part A's and Part B's saved results stay current. *Ruling: no
    existing output column or value changes.*
- **Holdings are double:** spice, the welfare score, the trade arithmetic and loan amounts (spec section 4). Sites
  stay float.
- **No nondeterminism:** a seed gives the same bytes every run, in waves and under `--serial-turns`. The newcomer
  placement race the user accepted stays as it is.
- **Limits** (spec section 5), each checked and named:
  - the loan book holds at most 2 × cells loans (exit 5); Python's IV-A5 peaks at 203 loans on 2,500 cells;
  - at most `MAX_HEIRS = 32` heirs per death in the serial-mode paths (exit 5);
  - `--version` prints `loans_per_cell = 2` and `max_heirs = 32`.
- **Still refused after Part C:** `disease_list`, `diseases_per_agent`, `disease_length`, `immune_length`,
  `disease_fee`. `ConfigError` names them as "not on the GPU yet".
- **Existing tests:** this plan changes a few existing tests and helpers:
  - the tests that pin the refusal boundary (`test_bridge`, `test_cli`);
  - the shared helpers `tests/gpu.py` and `tests/reference.py`, which gain the spice columns, the loans dump and
    the ordered Python step;
  - `test_sex._files`, which gains the loans dump.

  No assertion about behaviour is weakened. Approving this plan approves these changes.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings this plan makes against the spec

Each of these is recorded in the ledger when its task is reached.

- **R1: Inheritance with spice or credit runs one turn per wave.** `serial()` becomes
  `serial_turns || (inheritance && (combat() || credit || spice))`.
  - Why: a starving agent's heirs include children born earlier in the period to partners who saw it. Spec
    section 2's "around every site in sight of it" misses a partner whose vision is longer than the agent's own.
  - Credit adds heirs who take over loans, and loans that split again in later deaths. Neither can be bounded in a
    footprint.
  - No registered experiment combines inheritance with spice or credit.
  - Cost if wrong: speed only, for unregistered combinations. The results are exact.
- **R2: The lender is in the borrower's footprint, not the other way round.** Spec section 4 puts borrowers in the
  lender's footprint and corrects totals at the lender's death.
  - Here a lender's death writes only its own row, and the borrower reads the lender's `dead` flag in its own turn.
  - The shared site orders the two turns, as the spec intends.
  - Cost if wrong: none to results. The footprint is the same size.
- **R3: Trade statistics are combined with Chan's formula.** Each turn keeps its count, mean and sum of squared
  deviations (`M2`) of ln p, by Welford's update. The period combines the turns in rank order with Chan's formula.
  - Spec section 4 says "summed per turn ... then added in a fixed order".
  - This keeps `price_sd` free of cancellation, and it is still a fixed order.
  - Cost if wrong: last-digit differences from NumPy's pairwise sums, which the agreement rule can't see.
- **R4: `pollution_stop` is already on the GPU** (Chapter II, `begin_period`). Part C only tests it with spice.

## Review Focus

1. **Starving of spice with sugar left.** This must count as starvation everywhere sugar starvation does:
   - the turn's death and its key;
   - the fast path's `arrived` clearing for neighbour counts;
   - replacement.

   Pinned by `test_spice_starvation_matches_python` (Task 2), which checks a neighbour's `neighbors` column.
2. **A loan that falls due in the period its lender dies of old age.** Python runs `on_death` before
   `settle_loans`, so the loan is void and the borrower keeps its sugar. Pinned by
   `test_old_lender_dies_before_settling` (Task 6).
3. **Zero metabolism in the welfare and the MRS.** A zero exponent makes its factor 1, and the MRS is then 0, inf or
   nan, so there is no trade. A literal port divides 0 by 0. Pinned by `test_welfare_zero_metabolism_matches_python`
   (Task 3) and `test_no_trade_with_zero_spice_metabolism` (Task 5).
4. **A newborn as a lender or a trade partner in its birth period:**
   - it has no uid yet, so its loans carry a provisional reference until `birth_uids`;
   - other turns reach it through its site.

   Pinned by `test_serial_equivalence_trade[IV-14]` (Task 5), and by `test_newborn_lender_uids[waves|serial]`
   (Tasks 6 and 7): fertility from age 0, and every dumped loan names a uid below `agents_ever`.
5. **Cultural preferences after tag flips.** T reads tags after K has flipped them in the same turn, and partners'
   tags after their own turns. Pinned by `test_serial_equivalence_trade[IV-17]` and `test_trade_check[IV-17]`
   (Task 5).

---

### Task 1: Chapter IV configuration fields

**Files:**
- Modify: `src/config.h`, `src/config.cu`:
  - the fields;
  - parsing, `validate`, `print_config`;
  - `UNSUPPORTED` keeps only the disease fields;
  - `KNOWN` gains the Chapter IV keys.
- Modify: `bridge/config_cfg.py` (`FIELDS`), `tests/gpu.py` (`DEFAULT_CFG`), `tests/reference.py`
  (`config_from_cfg`)
- Test: `tests/test_cli.py`, `tests/test_bridge.py`

**Interfaces:**
- **Produces, `RunConfig` fields**, at Python's defaults:
  ```cpp
  bool spice = false;
  IntRange spice_metabolism{1, 5};
  std::optional<IntRange> spice_endowment;      // none: endowment's range
  std::optional<IntRange> foresight;            // none: myopic, phi = 0
  bool cultural_preferences = false;
  bool trade = false;
  std::string trade_rounding = "exact";         // "exact" | "down"
  std::optional<std::pair<int, double>> credit; // duration d, rate r percent
  ```
  `turns_on()` adds `|| trade || credit.has_value()`. Spice, foresight and cultural preferences alone stay on the
  fast path.
- **Produces, run.cfg** (empty means none):
  - `spice = true|false`;
  - `spice_metabolism = lo,hi`;
  - `spice_endowment =` or `lo,hi`;
  - `foresight =` or `lo,hi`;
  - `cultural_preferences = true|false`;
  - `trade = true|false`;
  - `trade_rounding = exact|down`;
  - `credit =` or `d,r` (an integer, then a number);
  - `print_config` prints them, in that order, after `replacement_same_tribe`.
- **Produces, `validate`, with Python's `Config.__post_init__` messages:**
  - `check_range` for `spice_metabolism`, `spice_endowment` and `foresight`;
  - `trade, cultural preferences, and foresight need the second commodity (spice=True)`;
  - `cultural preferences need cultural tags (tag_length > 0)`;
  - `combat is defined for sugar only (p.83); not with spice`;
  - `credit L_dr lends for childbearing; it needs sex=True`;
  - `credit needs each agent's income, which combat movement doesn't record`;
  - `credit duration must be >= 1 and rate >= 0, not d,r`;
  - `check_option("trade_rounding", ..., {"exact", "down"})`.
- **Produces, for the interim:** `validate` refuses a set `spice` with `spice: not on the GPU yet`, `trade` with
  `trade: ...` and `credit` with `credit: ...`. Task 2 removes the spice line, Task 5 the trade line and Task 6 the
  credit line.
- **Produces:** `config_cfg.FIELDS` gains the eight names after `replacement_same_tribe`. `_value` already writes
  `(10, 10.0)` as `10,10.0`. `config_from_cfg` maps an empty string to `None`, and `credit` to `(int, float)`.

- [ ] **Step 1: Write the failing tests.**
  - **`test_cli.py`:**
    - `test_chapter4_fields_round_trip`: every new key, set away from its default, comes back from
      `--print-config` as given.
    - `test_chapter4_validated[trade-no-spice|prefs-no-tags|spice-combat|credit-no-sex|credit-combat|credit-d0|bad-rounding]`:
      exit 2, with the message's distinctive words.
    - `test_unsupported_feature_key_is_rejected` uses `disease_list = 1`.
    - `test_later_parts_still_refused` keeps only the disease keys.
  - **`test_bridge.py`:**
    - `test_unsupported_lists_features` uses `Config(disease_list=1)` and expects `["disease_list"]`.
    - Add `test_part_c_configs_convert`:
      - IV-A5's run.cfg holds `credit = 10,10.0`;
      - VAR-inttrade/IV-3's holds `trade_rounding = down`;
      - `unsupported_features` is empty for all 69 Part C ids. A module-level `PART_C_IDS` lists them, built from
        the registry: Chapter IV, VI-2, VI-3, `VAR-*/VI-2|3`, and `VAR-inttrade/*` except VI-1's.

- [ ] **Step 2: Run them.** Expected: FAIL (unknown keys; `spice` unsupported in the bridge).

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: Chapter IV config fields through run.cfg and the bridge`.

### Task 2: Spice on the fast path: the landscape, the holdings, the draws

**Files:**
- Modify: `src/model.cu`:
  - cell variable `spice_capacity`;
  - macro properties `spice` and `spice_next` (main model);
  - environment `spice`, `spice_metabolism_lo/hi`, `spice_endowment_lo/hi`, `foresight_on`, `foresight_lo/hi`;
  - citizen variables `spice`, `initial_spice` (double), `spice_metabolism`, `foresight` (int).
- Modify: `src/rules.cuh`:
  - `cell_initialise`, `cell_grow` and `cell_commit` handle spice when it is on;
  - `commit_move` (in `movement.cuh`) harvests spice;
  - `metabolize_and_age` burns spice and checks death on it;
  - `output_newcomer` draws spice;
  - `init_citizen_out` covers the new variables.
- Modify: `src/host_state.h`, `src/host_state.cu`:
  - `RunState::spice_capacity`;
  - `make_cells`;
  - the founders' draws;
  - `write_metrics` columns.
- Modify: `src/landscape_io.h`, `src/landscape_io.cu`:
  - `InitAgent` gains `spice`, `initial_spice`, `spice_metabolism` and `foresight`;
  - `check_init_agents` refuses spice columns without `spice = true`.
- Modify: `src/checks.cu` (dump columns; invariants), `src/metrics.h`, `src/metrics.cu`, `src/config.cu` (remove the
  spice refusal)
- Modify: `tests/gpu.py`, `tests/reference.py`:
  - spice in `--init`, the dumps and `compare_dumps`;
  - `period_orders` and `run_python_in_order`.
- Test: create `tests/test_spice.py`

**Interfaces:**
- **Produces, the spice map:** Python's `capacity[::-1, :]`.
  - `spice_capacity[x + y·W] = capacity[(W−1−x) + y·W]`, built on the host from the loaded (or tiled) map.
  - Sites start at capacity, and growback and seasons apply the sugar rate, as in Python's `growback` and
    `seasonal_growback`.
- **Produces, draws in Python's `_spawn_at` order** (founders on the host, newcomers in `output_newcomer`), after
  sex:
  - `spice_metabolism` from its range;
  - `spice = initial_spice` from `spice_endowment`, or else `endowment`;
  - then `foresight`, only when its range is set; otherwise 0.
- **Produces, the fast path:**
  - **`commit_move`:** adds the site's spice and zeroes it. Production pollution still comes from sugar only.
  - **`metabolize_and_age`:** `spice -= spice_metabolism`. With spice on, it is starved when `sugar <= 0` or
    `spice <= 0`. "Starved" drives the `arrived` clearing, the death key (`fast_starved_key`) and replacement.
    Consumption pollution comes from the sugar burn only (Python `metabolize`).
- **Produces, dumps:**
  - `--dump-agents` appends `spice,initial_spice,spice_metabolism,foresight`.
  - `--dump-landscape` appends `spice,spice_capacity`.
  - `--init` reads the same four optional agent columns. `tests/gpu.py`'s `INIT_OPTIONAL` gains them.
  - `reference.build_python` sets them. `run_python` dumps agent spice and the landscape's spice.
  - `compare_dumps` compares spice like sugar (abs 1e-5), wherever both dumps carry it.
  - With spice on, an `--init` agent without a spice column has spice 0 and starves in its first turn, as in
    Python. Every test agent gets spice.
- **Produces, test helpers**, for tests in which the order matters:
  - **`gpu.period_orders(exe, tmp, cfg, capacity, agents, steps) -> list[list[int]]`:** each period's uids in turn
    order. It runs the program once per `--dump-at` t = 1..steps, and sorts each dump's agents by `priority << 32 | id`,
    largest first.
  - **`reference.run_python_in_order(cfg, capacity, agents, orders) -> Dump`:** steps Python with each period's
    first `rng.permutation`, the turn order, replaced by `orders[t]`. Every other draw is left alone.
- **Produces, `--check`:** site spice lies in [0, spice capacity]. With spice on, every agent's spice is > 0.
- **Produces, metrics:**
  - `AgentColumns` gains `spice` and `foresight`.
  - `gini` is over `sugar + spice`.
  - `mean_spice` is the mean of spice (NaN for nobody), and `mean_foresight` the mean of foresight. Without spice,
    both are 0, as in Python.

- [ ] **Step 1: Context7.** `/websites/flamegpu`: declaring another `float` macro property of `MAX_CELLS`, and
  reading it from a cell agent function.

- [ ] **Step 2: Write the failing tests** in `test_spice.py`. Agents have vision 0, so movement can't matter until
  Task 3. They stand at least 3 apart, so the order can't matter either.
  - `test_spice_map_mirrors_sugar`: on `sugar-map.txt` with `spice = true`, the landscape dump at t = 0 has
    `spice_capacity(x, y) == capacity(49 − x, y)` and `spice == spice_capacity` at every site.
  - `test_spice_harvest_matches_python`: `test_parity.py`'s `CAPACITY`, four agents with spice 30 and spice
    metabolisms 1–3, 5 steps. `compare_dumps(gpu, py) == []` with spice and the landscape's spice.
  - `test_spice_starvation_matches_python`, 1 step over 10 seeds, with Python stepped in the GPU's order
    (`run_python_in_order`):
    - agent S has sugar 50, spice 2 and spice metabolism 3, so it dies in its turn;
    - agent N, its neighbour, has spice 30, metabolism 0 and spice metabolism 0.
    - Assert, for each seed: Python's dump matches, N's `neighbors` matches Python's (1 if N's turn came first, else
      0), and the t = 1 metrics row's `population` matches. Both orders occur over the seeds.
  - `test_spice_starvation_replaced`: the same pair with `replacement = true` and `max_age = 60,100`, 3 steps with
    `--check`. Exit 0, and the population is 2 at every metrics row.
  - `test_spice_growback_seasonal`: `seasons = 2,4` and no agents. After 6 steps the landscape's spice matches
    Python's at every site.
  - `test_founders_draw_spice[myopic|foresight]`: 400 founders with `spice_endowment = 7,9` and
    `spice_metabolism = 2,3`:
    - every agent has spice in 7..9 with `initial_spice == spice`, and a spice metabolism in 2..3;
    - foresight is in 0..10 with `foresight = 0,10`, and 0 without.
  - `test_newcomers_draw_spice`: the same ranges, with `replacement = true` and `max_age = 1,1`. At t = 3 every agent
    is a newcomer, and the same assertions hold.
  - `test_spice_metrics_match_python`: the t = 0 and t = 1 rows of the harvest scenario match
    `python_metric_rows` (`test_metrics_parity._compare`).
  - `test_init_spice_without_spice_refused`: an `--init` agent with a spice column and `spice = false` exits 2,
    naming the line.

- [ ] **Step 3: Run them.** Expected: FAIL (`spice: not on the GPU yet`).

- [ ] **Step 4: Implement.**

- [ ] **Step 5: Run them, then the suite.** Expected: all pass. The goldens are the guard that Chapter II is
  untouched.

- [ ] **Step 6: Commit** `flamegpu: spice on the fast path - the mirrored map, holdings, draws and metrics`.

### Task 3: Welfare movement, with foresight and cultural preferences

**Files:**
- Create: `src/welfare.h` (`__host__ __device__`; Python's `welfare.py`)
- Modify: `src/movement.cuh` (`propose` scores with `welfare_score` when spice is on), `src/model.cu` (the movement
  sub-model gains the spice macro property, the environment's `spice`, `cultural_preferences` and `tag_length`, and
  the citizen variables `spice`, `metabolism`, `spice_metabolism`, `foresight` and `tags`)
- Test: `tests/test_spice.py`

**Interfaces:**
- **Produces, `welfare.h`, line for line with Python:**
  - `double preference_fraction(uint64_t tags, int tag_length, bool cultural)`: the share of 0 tags, or 0.5.
  - `double welfare(double sugar_burn, int spice_metabolism, double f, double w1, double w2)`:
    - `a1 = sugar_burn · f`, `a2 = spice_metabolism · (1 − f)` and `mu = a1 + a2`;
    - each holding is clamped at 0;
    - each factor is `w^(a/mu)`, or 1 when `a == 0`.
  - `double mrs(double sugar_burn, int spice_metabolism, double f, double w1, double w2)`: Python's `mrs`, its inf and
    nan branches included.
  - `sugar_burn` is the metabolism until Part D adds disease fees.
- **Produces, the movement score with spice on** (Python's `welfare_scorer`), in double:
  - `base1 = sugar − φ·metabolism` and `base2 = spice − φ·spice_metabolism`;
  - `devalue = 1 + pollution`;
  - the score is `welfare(..., max(base1, 0) + sugar_site/devalue, max(base2, 0) + spice_site/devalue)`.
  - It uses the holdings at the start of the period (spec section 8, difference 3).
  - The same strict comparisons as today: the first best wins, then a nearer site at an equal score.

- [ ] **Step 1: Write the failing tests** in `test_spice.py`. Each one is Julia's matching scenario
  (`julia/bridge/scenarios.py`) on `test_parity.py`'s `CAPACITY`: four far-apart agents with spice 30 and spice
  metabolism 2, 4 steps, and `compare_dumps(gpu, py, pollution=True) == []`.
  - `test_welfare_move_matches_python[myopic|foresight|polluted|stopped]`:
    - **myopic:** `spice = true`;
    - **foresight:** `foresight = 0,10`, and every agent's foresight is 5;
    - **polluted:** `pollution = 1,1` and `diffusion_period = 1`;
    - **stopped:** polluted, plus `pollution_start = 1` and `pollution_stop = 3`.
  - `test_cultural_preferences_move_matches_python`: `tag_length = 3`, `cultural_preferences = true`, 1 step.
    - The world is 21×21 with capacity 0, except capacity 4 at x = 14 on rows 5 and 15. Through the mirror, the
      sites at x = 6 on those rows have spice capacity 4.
    - Agent A at (10,5) has tags `000` (f = 1, sugar only). Agent B at (10,15) has tags `111` (f = 0, spice only).
      Both have vision 4 (`vision = 4,4`), and both metabolisms 1.
    - A moves east and B moves west, as in Python.
  - `test_welfare_zero_metabolism_matches_python`: an agent with metabolism 0 and spice metabolism 0 scores every
    site 1.0 and stays. An agent with only its spice metabolism 0 follows sugar. Both match Python.

- [ ] **Step 2: Run them.** Expected: FAIL. The GPU scores sugar only, so the agents' sites differ.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass, `test_sequential.py`'s serial-dictatorship checks
  included.

- [ ] **Step 5: Commit** `flamegpu: welfare movement with foresight and cultural preferences`.

### Task 4: Spice on the turns path: harvest, rule S's spice gifts, inheritance with spice

**Files:**
- Create: `src/heirs.cuh` (Part B's `is_child_of`, and `pay_victim_heirs` generalised as `pay_heirs`)
- Modify: `src/store.h`, `src/store.cu`:
  - row buffers `spice`, `initial_spice`, `spice_metabolism`, `foresight`;
  - the cell buffer `site_spice`.
- Modify: `src/turns.cuh`:
  - `publish`, `absorb` and `spawn_newborns` copy the spice variables;
  - `stage_sites` and `unstage_sites` copy spice;
  - `age_mark` and `heirs_take` carry spice.
- Modify: `src/turn.cuh`:
  - harvest spice;
  - burn spice, and die on it;
  - a starving agent's heirs.
- Modify: `src/sex.cuh` (the child's spice), `src/combat.cuh` (uses `heirs.cuh`)
- Modify: `src/store.h` (`Dying` gains `spice`), `src/store.cu` (`DyingTable` sorts it with the uids)
- Modify: `src/config.h` (`serial()`, ruling R1), `src/model.cu` (environment for S's spice draws)
- Test: `tests/test_spice.py`, `tests/test_inheritance.py`

**Interfaces:**
- **Consumes:** Task 2's variables and environment. Part B's `pay_victim_heirs`, `is_child_of`, `Dying` and
  `DyingTable`.
- **Produces, the turn with spice on** (Python's `move` and `metabolize`):
  - harvest takes `site_spice[target]`;
  - metabolism takes `spice_metabolism` off the spice;
  - the agent dies when `sugar <= 0 || spice <= 0`, with `turn_death_key(rank, false)`.
- **Produces, rule S with spice** (Python's `mate`). After the tags, in Python's draw order:
  - each parent's spice gift is `min(5, max(spice, 0))` when capped, else `initial_spice · share`, rounded down with
    `gift_down`;
  - both parents give theirs, and the child's `spice = initial_spice = sum`;
  - with `redraw`, `initial_spice` is drawn from `spice_endowment`, or else `endowment`;
  - then `spice_metabolism` and `foresight`, each from a random parent. Both are drawn even without foresight.
- **Produces, `heirs.cuh`:**
  - `__device__ void pay_heirs(const Store& s, unsigned int row)`: Python's `Model.die` with I on. Positive sugar,
    and positive spice, are split equally among the living children, found by scanning every row, newborns
    included.
  - It runs only in serial mode. Combat's victims, and the turn's own agent when it starves with inheritance on, call
    it.
- **Produces:** `RunConfig::serial()` is `serial_turns || (inheritance && (combat() || credit || spice))` (R1).
- **Produces, old age:**
  - `Dying` carries spice, sorted with the uids;
  - `heirs_take` adds `spice / heirs` for each dying parent with positive spice, in parent uid order, as for sugar.

- [ ] **Step 1: Write the failing tests.**
  - **`test_spice.py`:**
    - `test_turns_path_equals_fast_path_spice[IV-6-notrade-v2|IV-13-notrade-v3.5]`, `dump_at` 20:
      - `--force-turns` is byte-identical to the fast path, as `test_turns.py` checks Chapter II;
      - the configs come from the registry through `config_to_cfg`, as `test_combat.py` builds them.
    - `test_child_spice_matches_python[endowment|capped|redraw|down]`: `test_sex.py`'s `PAIR` layout with
      `spice = true`.
      - Every agent, blockers included, has spice 40 and spice metabolism 0. The parents' initial spice is 30.
      - The order still can't matter, as in Part A's test.
      - Python's dump matches, children's spice and initial spice included.
    - `test_serial_equivalence_spice[IV-18|VI-2]`: 20 steps, waves byte-identical to `--serial-turns`
      (`test_sex._files`). Also `--check` exits 0 for each.
  - **`test_inheritance.py`:**
    - `test_old_age_inheritance_spice`: `test_inheritance_matches_python`, with spice. Each surviving child also gets
      half the spice, compared with Python to 1e-9.
    - `test_starved_heirs_get_spice`: with `inheritance = true` and `spice = true`, 1 step.
      - Parent P has sugar 1, metabolism 2, spice 30 and spice metabolism 0. It starves in its turn.
      - Its two children are far away, with metabolism 0 and spice metabolism 0.
      - Each child gains 15 spice, as in Python. The timing JSON's `waves_mean` equals `agents_start` (R1).

- [ ] **Step 2: Run them.** Expected: FAIL:
  - the turns path neither harvests nor burns spice;
  - children have no spice;
  - starving parents pass nothing on.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass, Part B's combat-with-inheritance tests included.

- [ ] **Step 5: Commit** `flamegpu: spice on the turns path, rule S's spice gifts, inheritance with spice`.

### Task 5: Trade T in the turn

**Files:**
- Create: `src/trade.cuh` (Python's `bargain` and `trade_with_neighbors`)
- Modify: `src/store.h`, `src/store.cu`:
  - row buffers `trade_n`, `trade_mean`, `trade_m2`, `trade_sugar`, `trade_spice`;
  - `StoreHost::trade_totals()`.
- Modify: `src/turn.cuh` (T after K), `src/turns.cuh` (host function `total_trades` after `assign_births`),
  `src/model.cu` (environment `trade`, `trade_down`, `cultural_preferences` in the turns sub-model)
- Modify: `src/host_state.h` (`RunState::econ`), `src/metrics.h`, `src/metrics.cu` (the six trade columns),
  `src/config.cu` (remove the trade refusal)
- Test: create `tests/test_trade.py`

**Interfaces:**
- **Consumes:** Task 3's `welfare` and `mrs`; Task 4's turns-path spice; Task 2's `period_orders` and
  `run_python_in_order`.
- **Produces, the turn, after K** (Python's `trade_with_neighbors`):
  - the partners are the occupants of the four sites around the agent now, in VON_NEUMANN order, newborns included
    (touch point 10);
  - they bargain in a Fisher–Yates order drawn with `draw_between`, as `transmit` draws its order;
  - `bargain` follows Python line for line, in double: the price is `sqrt(ma · mb)`, and with `trade_down` both
    amounts are rounded down;
  - each accepted exchange updates the row's statistics: Welford on ln p, plus the sugar and spice it moved.
- **Produces:** `struct TradeTotals { double n, mean, m2, sugar, spice; }`.
  - `StoreHost::trade_totals()` combines the rows in rank order (`rank_row`) on one device thread, with Chan's
    formula (R3), and returns the totals.
  - `total_trades` stores them in `RunState::econ` for the period's metrics row.
- **Produces, metrics:**
  - `trades = n`;
  - `mean_log_price = mean`;
  - `mean_price = exp(mean)`;
  - `price_sd = sqrt(m2 / n)`, which is `np.std`;
  - all three prices are NaN when n = 0;
  - `sugar_traded` and `spice_traded`.
  - At t = 0 the totals are all zeros, as Python's empty `trade_log`.

- [ ] **Step 1: Write the failing tests** in `test_trade.py`. Python is stepped in the GPU's own turn order. Every
  agent has vision 0 on a zero-capacity 20×20 map, so a turn is metabolism, then trade.
  - `test_trade_pairs_match_python[exact|down|cultural]`, 2 steps, compared to 1e-9, plus the t = 1 and t = 2
    metrics rows' six trade columns to `rel_tol` 1e-12:
    - 15 pairs at `(4·(i % 5), 4·(i // 5))` and the site east of it;
    - holdings and metabolisms from `random.Random(11)`, as Julia's `_pairs(15, 11)` draws them;
    - **down:** `trade_rounding = down`;
    - **cultural:** `tag_length = 3` and `cultural_preferences = true`, with tags from `_pairs(15, 12, tags=3)`.
  - `test_no_trade_with_zero_spice_metabolism`: a pair where one agent's spice metabolism is 0. Its MRS is 0, so
    `trades = 0` and both keep their holdings, as in Python.
  - `test_trade_metrics_t0`: the t = 0 row has `trades = 0`, NaN prices, and 0 traded.
  - `test_serial_equivalence_trade[IV-3|IV-14|IV-17|IV-A3]`: 20 steps, waves byte-identical to `--serial-turns`.
  - `test_trade_check[IV-3|IV-17]`: 20 steps with `--check`, exit 0.

- [ ] **Step 2: Run them.** Expected: FAIL (`trade: not on the GPU yet`).

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: trade T in the turn, price statistics in rank order`.

### Task 6: Credit L in waves, and `--check` on rows

**Files:**
- Create: `src/loans.h`, `src/loans.cu` (`LoanBook`, its device view `Loans`, the after-turns rebuild, the end-of-period
  ledger)
- Create: `src/credit.cuh` (Python's `available_to_lend`, `shortfall`, `creditworthy` and `seek_credit`)
- Modify: `src/store.h`:
  - `touch_row`;
  - row buffers `new_lender`, `new_amount`, `new_due` (4 per row) and `n_new`;
  - the borrower index `loan_first`, `loan_count` and `loan_entry`.
- Modify: `src/store.cu` (the borrower index at `schedule`; provisional lender refs in `birth_uids`)
- Modify: `src/footprint.cuh` (each lender's site; `FootprintEnv::credit`), `src/culture.cuh` (`friend_alive` calls
  `touch_row`), `src/turn.cuh` (L after T)
- Modify: `src/turns.cuh` (`rebuild_loans` after `assign_births`; the layers `ledger_post`, `run_ledger` and
  `ledger_take`), `src/model.cu` (with credit, old age always goes through the `DyingTable` path; the ledger layers
  after it)
- Modify: `src/main.cu` (`--dump-loans PATH`; `--version`'s `loans_per_cell = 2`), `src/checks.cu` (the loans dump),
  `src/metrics.cu` (the five credit columns), `src/config.cu` (remove the credit refusal)
- Modify: `tests/gpu.py` (`run_gpu` passes `--dump-loans` with credit; `Dump.loans`), `tests/reference.py` (Python's
  loans), `tests/test_sex.py` (`_files` includes `loans.csv` when given credit)
- Test: create `tests/test_credit.py`; `tests/test_cli.py` (`test_version`)

**Interfaces:**
- **Consumes:** Task 5's turn, the store's `uid_row`, `rank`, `rank_row` and `dead`; Part A's `PROVISIONAL_FRIEND`
  pattern.
- **Produces, `touch_row(const Store&, unsigned int r, unsigned int rank, unsigned int where)`:** under `--check`,
  `touch()` of row r's site now (`s.x[r] + s.y[r]·w`). Touch point 12 is for friends' rows, 13 for lenders' rows.
- **Produces, `loans.h`:**
  - `struct Loans { unsigned int capacity; unsigned int* n; unsigned int *lender, *borrower; double *principal, *due; int* due_t; }`
    holds the book in Python's list order. Lender and borrower are uids, or a provisional row ref for this period's
    newborns.
  - `class LoanBook` allocates it with `capacity = 2 × cells` and throws `CapacityError("loan book capacity N
    exceeded")`. It copies the book to the host for metrics and dumps.
- **Produces, the borrower's turn, after T** (Python's `seek_credit`):
  - `need = shortfall`: `fertility_threshold · initial_sugar − sugar`, at childbearing age;
  - the lenders are the four neighbours now, in a Fisher–Yates order (touch point 11);
  - `amount = min(available_to_lend, need)`;
  - the income is `last_income`: this turn's sugar harvest minus its burn, a local of the turn;
  - `creditworthy` holds when `last_income · d − owed >= amount_due`, where `amount_due = amount · (1 + r/100 · d)`;
  - **owed** is, in list order, the dues of the borrower's start-of-period loans whose lender row is not `dead`
    (touch point 13 on each lender row), plus the dues of the loans already made in this turn;
  - a loan moves the sugar, and is kept in the borrower's row slots, at most 4, in the order made.
- **Produces, the footprint** with credit (R2): for each of the row's start-of-period loans, the lender's site. That
  is its start if the lender comes later in the order, else its target, as for friends. It is a read entry.
- **Produces, `rebuild_loans`,** one device thread after `birth_uids`. Without inheritance it builds the new book
  from:
  1. the start-of-period loans whose lender and borrower rows are both alive;
  2. then each row's new loans, rows in rank order, slots in order, dropping those whose lender died later in the
     period;
  3. with provisional lender refs resolved to uids.
- **Produces, the end of the period with credit** (Python: old-age `die`, then `settle_loans`):
  - **`ledger_post`:** every placed citizen writes `uid_row[uid] = index` and `ledger_sugar[index] = sugar`. Reusing
    `uid_row` is safe: `publish` rewrites it for every living citizen.
  - **`run_ledger`, one device thread:**
    - **old age:** for each dying uid in uid order (`DyingTable`), it removes the loans where that uid is lender or
      borrower;
    - **settling:** `settle_loans(t, d, r)` goes through the due loans in list order. Each is paid in full if the
      borrower can, else half the borrower's positive sugar is paid. The remainder is re-originated at the end of
      the list, due `t + d`.
  - **`ledger_take`:** citizens read their sugar back.
- **Produces, metrics** from the host copy, by uid:
  - `n_loans`, `n_lenders`, `n_borrowers`, `n_both`;
  - `credit_depth`, by Python's `_longest_chain` (a simple-path DFS from every lender).
- **Produces, `--dump-loans PATH`** at `--dump-at`: `lender,borrower,principal,due,due_t` (`%.17g`), in list order.
  `reference.run_python` gives `Dump.loans` from `model.loans`, with uids being the agents' ids.

- [ ] **Step 1: Context7.** `/websites/flamegpu`: a host layer function that launches a raw CUDA kernel on the
  simulation's stream, as `store.cu` does, and the order of host and agent layers within a step.

- [ ] **Step 2: Write the failing tests** in `test_credit.py`. Each comparison covers the agents' sugar (1e-9) and
  `Dump.loans` (dues and principals to 1e-9).
  - `test_loan_and_repayment_matches_python`: Julia's `credit_loan_and_repayment`, compared at t = 1, 10 and 12.
    - A 7×7 world with capacity 0 except (3,4) = 10; `sex = true`, `credit = 10,10.0`, vision 1.
    - Lender F at (3,3): age 50, sugar 100, metabolism 0, fertility 12–40, initial sugar 60.
    - Borrower F at (3,4): age 20, sugar 20, metabolism 0, fertility 12–40, initial sugar 60.
  - `test_partial_repayment_reoriginates`: the same with `credit = 2,10.0` and the site at capacity 0, so the
    borrower can't pay at t = 2. At t = 3 the loans match Python's: the remainder, re-originated.
  - `test_old_lender_dies_before_settling`: the repayment layout with `credit = 1,10.0`, 2 steps.
    - The lender's max age is 52, so it dies at the end of period 2, when the period-1 loan falls due.
    - The book is empty at t = 2, and the borrower keeps its sugar, as in Python.
  - `test_starved_lender_loan_void`: the repayment layout, but the lender has sugar 6 and metabolism 5. It runs over
    10 seeds, compared at t = 1 and t = 2, with Python stepped in the GPU's order (`run_python_in_order`).
    - If the lender's turn comes first, it lends 0.5 and lives through period 1.
    - If second, it lends 3 and then starves, so the loan is void after the turns.
    - Both orders occur over the seeds, and every seed matches Python.
  - `test_credit_metrics_match_python`: the repayment scenario's metrics rows for t = 0..12 match
    `python_metric_rows` on the five credit columns.
  - `test_credit_check[IV-A5|IV-A5-stride2]`: 20 steps with `--check`, exit 0. `IV-A5-stride2` is IV-A5 with
    `vision = 2,6` and `look_stride = 2`.
  - `test_serial_equivalence_credit[IV-A5|VI-3-credit]`: 20 steps, waves byte-identical to `--serial-turns`, the
    loans dump included. `VI-3-credit` is VI-3 with `credit = 10,10.0`.
  - `test_newborn_lender_uids[waves]`: IV-A5 with `fertility_start = 0,0`, 20 steps. Every loan dumped at t = 20
    names lender and borrower uids below that row's `agents_ever`.
  - **`test_cli.py`:** `test_version` asserts `loans_per_cell = 2`.

- [ ] **Step 3: Run them.** Expected: FAIL (`credit: not on the GPU yet`).

- [ ] **Step 4: Implement `seek_credit`, `touch_row` and the book, without the lender footprint. Run
  `test_credit_check[IV-A5]`.** Expected: FAIL. The message names touch point 13: a lender row outside the footprint.
  This is the row check's RED.

- [ ] **Step 5: Add the lender footprint.**

- [ ] **Step 6: Run them, then the suite.** Expected: all pass. The `--check` tests of Parts A and B now also check
  friends' rows (touch point 12).

- [ ] **Step 7: Commit** `flamegpu: credit L in waves; --check sees the rows a turn reaches by uid`.

### Task 7: Credit with inheritance

**Files:**
- Modify: `src/loans.h`, `src/loans.cu`:
  - `book_append`, `book_on_death`, `owed_from_book`, sequential device functions on `Loans`;
  - the ledger's old-age `on_death` with heirs.
- Modify: `src/credit.cuh`, `src/turn.cuh` (serial mode: in-turn book operations, `on_death` at starvation), `src/heirs.cuh`
  (`heirs_in_order`)
- Modify: `src/turns.cuh` (`heirs_count` also posts `(dying parent uid, child uid)` pairs; `dying_sort` sorts them),
  `src/store.h`, `src/store.cu`:
  - the pairs table in `Dying`/`DyingTable`;
  - the error bit `STORE_HEIR_CAPACITY`;
  - `birth_uids` resolves provisional refs in the book too.
- Test: `tests/test_credit.py`

**Interfaces:**
- **Consumes:** Task 6's `Loans`, `ledger_sugar` and `run_ledger`; Task 4's `pay_heirs` scan; R1's `serial()`.
- **Produces, `heirs_in_order(s, row, out, MAX_HEIRS) -> int`:** the living children of row, in Python's
  `children` order:
  - by uid first;
  - then this period's newborns by `newborn_key`;
  - more than `MAX_HEIRS = 32` sets `STORE_HEIR_CAPACITY` (exit 5, `"more than 32 heirs"`).
- **Produces, credit with inheritance**, always serial (R1). The book is Python's live list during the turns:
  - a loan is appended at once (`book_append`);
  - **owed** is the sum, in list order, of the dues of every loan in the book whose borrower is this agent
    (`owed_from_book`);
  - **a starving agent's turn** runs `book_on_death` before `pay_heirs`. Its loans as borrower go. Each of its
    loans as lender is replaced, in place, by one loan per heir (`principal/k`, `due/k`, the same `due_t`). The
    heirs are `heirs_in_order`, minus the borrower; with no heir left, the loan is void.
  - `rebuild_loans` leaves the book as it is.
- **Produces, at old age with inheritance:**
  - the ledger's `on_death` uses the same splitting;
  - the heirs are the living, non-dying children from the sorted pairs table, in uid order, minus the borrower;
  - the dying are taken in uid order, as Python's batch.
- **Produces, `--version`:** `max_heirs = 32`.

- [ ] **Step 1: Context7.** CUB `DeviceRadixSort::SortPairs` on 64-bit keys (parent uid << 32 | child uid), as
  `store.cu` already uses it.

- [ ] **Step 2: Write the failing tests** in `test_credit.py`. Python is stepped in the GPU's order where the order
  matters.
  - `test_old_lender_heirs_take_loans`, 1 step over 5 seeds, `inheritance = true`, compared with Python at t = 1:
    - Every agent is female, so nobody mates, and has metabolism 0.
    - Lender L: age 50, max age 51, sugar 100, fertility 12–40. It dies at the end of period 1.
    - Two neighbours of L borrow 10 each: they have sugar 50 and initial sugar 60, at age 20, so they are fertile.
      B is L's child (`parent_a` = L), and D isn't.
    - L's other child C is far away.
    - After L's death:
      - B's loan passes to C alone, since B would owe itself;
      - D's loan splits between B and C, half the principal and the due each, in its place in the list.
    - The book's order depends on whether B or D borrowed first, so Python is stepped in the GPU's order.
  - `test_starved_lender_heirs_take_loans`, 2 steps over 5 seeds:
    - L has sugar 12 and metabolism 5, so it lends in period 1 and starves in period 2, whichever order the turns
      take.
    - Its two children, far away, each take half of each loan.
    - Every seed matches Python's loans and sugar.
  - `test_credit_inheritance_serial`: IV-A5 with `inheritance = true`, 1 step. `waves_mean` equals `agents_start`.
  - `test_newborn_lender_uids[serial]`: as Task 6's, with `inheritance = true`.
  - `test_credit_inheritance_check`: IV-A5 with `inheritance = true`, 20 steps with `--check`, exit 0.
  - **`test_cli.py`:** `test_version` asserts `max_heirs = 32`.

- [ ] **Step 3: Run them.** Expected: FAIL. Loans are void at a lender's death instead of passing on, and waves are
  concurrent.

- [ ] **Step 4: Implement.**

- [ ] **Step 5: Run them, then the suite.** Expected: all pass.

- [ ] **Step 6: Commit** `flamegpu: credit with inheritance - loans pass to heirs, one turn per wave`.

### Task 8: Part C's experiments against Python

**Files:**
- Create: `docs/validation/chapter4-part-c.md`, `docs/validation/agreement-part-c.md`
- Modify: `README.md`:
  - spice, welfare movement, T, L and `economic_metrics` are on the GPU;
  - in "How the GPU version differs": difference 3 (movement scores with start-of-period holdings) now applies, to
    spice runs only;
  - inheritance with combat, credit or spice runs one turn per wave;
  - the loan and heir limits.

- [ ] **Step 1: Run the experiments** on `build\`, `.venv\Scripts\python -m bridge.gpu_run <id> --jobs 4`, for the 69
  ids of `test_bridge.PART_C_IDS`:
  - `IV`;
  - `VI-2` and `VI-3`;
  - `VAR-book`, `VAR-share`, `VAR-c1c3fit`, `VAR-intgift`, `VAR-intgiftc1` and `VAR-fit83`, each on `VI-2` and `VI-3`;
  - `VAR-inttrade` on each trading id except `VI-1`.

  Expected: every run exits 0. Ledger the wall time.

- [ ] **Step 2: Agreement.** `.venv\Scripts\python -m bridge.agreement_report <the 69 ids> --python C:\Projects\Sugarscape2026\results --out docs/validation/agreement-part-c.md`.
  - Expected: 0 flagged. The harness found none in 2,835 windows with all three differences (`semantics-harness.md`).
  - Each flag gets superpowers:systematic-debugging, then a fix (back to the owning task's tests) or a written
    explanation with its evidence: a harness run of the same experiment, or more seeds.

- [ ] **Step 3: Book targets.** `.venv\Scripts\python -m bridge.gpu_report --chapter IV`, then `--chapter VI` and
  `--chapter VAR`.
  - Every status change against Python for the Part C ids is explained in the validation doc, with its seed-level p.
  - VI-1 and the Chapter VI models show "not run".

- [ ] **Step 4: xl smoke runs** on `build-fast\`, as Part A ran III-1 (`chapter3-part-a.md`, "xl smoke run"): IV-3,
  IV-A3 and IV-A5, 1 seed, 5 steps each.
  - Ledger the waves and the stepping per period.
  - If a buffer can't be allocated, record the exit and the message as Part F's work. Don't change the design here.

- [ ] **Step 5: Write `docs/validation/chapter4-part-c.md`:**
  - what ran;
  - the agreement verdict, and every flag or status change explained;
  - waves and stepping ms per period per experiment, from the timing JSON;
  - the xl smoke runs.

  Then update the README.

- [ ] **Step 6: Run the suite.** Expected: all pass.

- [ ] **Step 7: Commit** `flamegpu: Part C validation - Chapter IV against Python`.
