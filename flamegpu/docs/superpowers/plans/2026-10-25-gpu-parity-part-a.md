# Every Rule on the GPU, Part A: The Turns and Chapter III without Combat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Python's rules S, I (old age), K and friends on the GPU in Python's turn order, with every
Chapter III configuration field, all 45 metric columns, and agreement with Python on III-1, -3, -4, -5, -7, -8, -12,
-15 and the 24 reproduction variants of III-1, -3, -4, -5.

**Architecture:**
- Movement keeps deferred acceptance, but with an interaction rule on, nothing moves at commit.
- **The turns:**
  - Citizens publish their state to device buffers (the store).
  - A `turns` sub-model runs every agent's turn in the period's order: move to the target, harvest, metabolism,
    neighbours, S, K.
  - Turns run in waves. A turn runs once every earlier turn whose fixed footprint conflicts with its own has
    finished.
  - Citizens absorb the store back, and cells create the newborn citizens.
- **Unchanged:** runs with no interaction rule keep today's path.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), CUB/Thrust (shipped with CUDA), pytest, the Python
bridge in `flamegpu/bridge/`.

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-full-parity-design.md` (Part A of "The work, in
parts").

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`, seatbelts on, used by pytest) and `scripts\build.cmd build-fast OFF`.
  Run all commands from `flamegpu/`.
- **The suite** is `.venv\Scripts\python -m pytest tests -q`.
- **Context7** before FLAME GPU (`/websites/flamegpu`), CUB or Thrust code is written. Each task names its lookups.
- **Macro-property rule:** within a layer a macro property is only read, or only atomically written. The store's
  buffers aren't macro properties: the scheduler guarantees a turn exclusive use of its footprint.
- **Without interaction rules** (none of `sex`, `culture` on; combat, trade, credit and disease are still refused):
  - today's layers run unchanged;
  - the four goldens' existing columns stay byte-identical, which Task 3 checks column by column.
- **No nondeterminism:** a seed gives the same bytes every run. No float atomics reach an output. Newborn order
  comes from turn order, never from an atomic counter's order.
- **Limits** (spec section 5): `tag_length` ≤ 63 (exit 2), the uid buffer (exit 5).
- **Still refused in Part A** (they belong to Parts B–D): `combat_alpha`, `replacement_same_tribe`, `spice` and the
  Chapter IV fields, the disease fields. `ConfigError` names them as "not on the GPU yet".
- **`--tile` with `initial_blocks`** is refused (ruling: the benchmark tiles only II-4).
- **Existing tests:** tests asserting the Chapter-II-only boundary (`test_bridge`, `test_cli`), the golden
  comparison and the fingerprint string change with that boundary, as the spec approves. No assertion about
  behaviour is weakened.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Replacement through the turns path.** Deaths in turns and at old age each make one newcomer, with tags and sex
   drawn as Python's `_spawn_at` draws them. `--check`'s population accounting counts newborns and newcomers.
   Pinned by `test_turns_replacement_check` (Task 5).
2. **A crowded world with vision contact**, where most turns conflict: waves must still progress and equal serial
   mode. Pinned by `test_serial_equivalence[block_vision]` (Task 5).
3. **Look stride above 1 with partners in sight:** sight lines come from the period's look seed, the same in both
   modes. Pinned by `test_serial_equivalence[stride5]` (Task 5) and Task 9's xl smoke run.
4. **Extinction:** a period in which everyone dies, and later periods with no citizens. The turns sub-model must exit
   at once, and the metrics must follow Python's empty-population conventions (`mean_children` 0.0, means NaN).
   Pinned by `test_turns_extinction` (Task 4).
5. **The uid buffer filling up** must stop the run with exit 5 and a message naming the limit. Pinned by
   `test_uid_capacity_exceeded` (Task 5).

---

### Task 1: Chapter III configuration fields, through `run.cfg` and the bridge

**Files:**
- Modify: `src/config.h`, `src/config.cu` (fields, parsing, `validate`, `print_config`; `UNSUPPORTED` shrinks)
- Modify: `src/main.cu` (`--version` prints `max_tag_bits = 63`)
- Modify: `bridge/config_cfg.py` (`FIELDS`, `_value` for `initial_blocks`)
- Test: `tests/test_cli.py`, `tests/test_bridge.py`, `tests/gpu.py` (`DEFAULT_CFG` gains the new keys at Python's
  defaults)

**Interfaces:**
- **Produces, `RunConfig` fields with Python's defaults:**
  - `bool sex`;
  - `IntRange fertility_start{12,15}`, `female_fertility_end{40,50}`, `male_fertility_end{50,60}`;
  - `bool inheritance`, `int tag_length = 0`, `bool culture`;
  - `std::vector<TribeBlock> initial_blocks`, where `struct TribeBlock { std::string tribe; int x0, y0, w, h, n; }`;
  - `double fertility_threshold = 1.0`, `child_share = 0.5`;
  - `std::string mate_contact = "vision"`, `child_gift = "endowment"`, `child_threshold = "endowment"`,
    `gift_rounding = "down"`.
- **Produces, `run.cfg` spelling:** the keys are Python's field names. `initial_blocks = blue,0,0,20,20,270;red,30,30,20,20,270`
  (empty for none). Booleans are `true`/`false`.
- **Produces:** `constexpr int MAX_TAG_BITS = 63` in `config.h`.

- [ ] **Step 1: Write the failing tests:**
  - `test_cli.py::test_chapter3_keys_round_trip`: every new key, set off its default, comes back the same from
    `--print-config`.
  - `test_cli.py::test_chapter3_validation`: each case exits 2 with stderr naming the field:
    - even `tag_length`;
    - `tag_length = 65`, naming 63;
    - `culture` without tags;
    - a block outside the grid, or holding more agents than its sites;
    - a tribe other than blue/red;
    - `fertility_threshold = 0`;
    - `child_share = 1.5`;
    - each bad option string;
    - `initial_blocks` with `--tile 2`.
  - `test_cli.py::test_later_parts_still_refused`: `combat_alpha`, `spice`, `disease_list` and
    `replacement_same_tribe` each exit 2 with "not on the GPU yet".
  - `test_bridge.py::test_chapter3_part_a_configs_convert`: for III-1, -3, -4, -5, -7, -8, -12, -15 and the
    `VAR-*/III-[1345]` ids, `unsupported_features` is `[]`, and `config_to_cfg` runs `--print-config` with exit 0.
  - Update `test_unsupported_lists_features` and `test_any_other_field_off_default_is_refused` to use
    `combat_alpha` and `spice` as the refused examples.

- [ ] **Step 2: Run them.** `.venv\Scripts\python -m pytest tests/test_cli.py tests/test_bridge.py -q`.
  Expected: the new tests FAIL (unknown or refused keys).

- [ ] **Step 3: Implement.** Port Python's `Config.__post_init__` checks for these fields, with the same conditions
  and the field named in each message. `print_config` writes them in the order of `FIELDS`.

- [ ] **Step 4: Run them again.** Expected: PASS. Then the suite: everything else passes.

- [ ] **Step 5: Commit** `flamegpu: Chapter III configuration fields in run.cfg and the bridge`.

### Task 2: Founders and newcomers with Chapter III state; the new variables in `--init` and dumps

**Files:**
- Modify: `src/model.cu` (citizen variables), `src/host_state.cu` (`make_citizens`, tribal blocks),
  `src/rules.cuh` (`output_newcomer` draws tags and sex), `src/landscape_io.h/.cu` (`InitAgent`, optional
  columns), `src/checks.cu` (dump columns)
- Modify: `tests/gpu.py` (`write_init` writes optional columns), `tests/reference.py` (builds Python agents with
  them)
- Test: create `tests/test_chapter3_setup.py`

**Interfaces:**
- **Produces, new citizen variables:**
  - `uid` (`unsigned int`), in Python's creation order;
  - `sex` (`unsigned int`: 0 none, 1 F, 2 M), `fertility_start`, `fertility_end` (`int`; with no sex `INT_MAX` and
    `INT_MIN`, Python's inf and −inf);
  - `initial_sugar` (`double`);
  - `tags` (`uint64_t`, bit i = tag i);
  - `n_children` (`unsigned int`);
  - `parent_a`, `parent_b` (`unsigned int`, `NO_UID = 0xFFFFFFFF` for founders and newcomers);
  - `friend_uid[5]`, `friend_dist[5]` (`unsigned int` arrays) and `n_friends`;
  - `disp_x`, `disp_y` (`int`);
  - `sugar` becomes `double`.
- **Produces, state:** `RunState::next_uid` (host), and the environment macro property `next_uid` (`unsigned
  int`), which device newcomers take uids from in Task 4. `agents_ever` = `next_uid`.
- **Produces, `--init` optional columns:** `sex` (F/M/blank), `fertility_start`, `fertility_end`,
  `initial_sugar` (default `sugar`), `tags` (a 0/1 string, tag 0 first).
- **Produces, dump columns:** the same, plus `uid,n_children,parent_a,parent_b,n_friends,disp_x,disp_y`.
- **Draw order:** each founder's draws follow `Model._spawn_at`: vision, metabolism, endowment, max age, then tags
  (resampled until the tribe matches, for a block), then sex, then the fertility start and end drawn for that sex.
  With `initial_blocks`, the blocks' sites are chosen block by block, without replacement among empty sites, before
  the draws.

- [ ] **Step 1: Context7.** `/websites/flamegpu`: array agent variables (`newVariable<T, N>`, `getVariable<T, N>`)
  and `uint64_t` / `double` agent variables in `AgentVector::data<T>`.

- [ ] **Step 2: Write the failing tests** in `test_chapter3_setup.py`, at `--dump-at 0`:
  - `test_tribal_blocks_founders`: III-12's blocks. 370 blue agents, all inside (0,0,20,20); 370 red inside
    (30,30,20,20). Each one's tag majority matches its block. Uids are `0..739`.
  - `test_sex_and_fertility_ranges`: III-1's config. Every founder has sex F or M; `fertility_start` is in 12..15;
    `fertility_end` is in 40..50 for F and 50..60 for M; `initial_sugar == sugar`. Both sexes are 40–60% of 400.
  - `test_init_columns_round_trip`: four agents with sex, tags and fertility given come back unchanged.
  - `test_newcomer_has_tags_and_sex`: tags on, sex on, replacement, `max_age = 1,1`. After step 1, every citizen has
    sex set and tags below `1 << tag_length`.

- [ ] **Step 3: Run them.** Expected: FAIL (unknown columns).

- [ ] **Step 4: Implement.** The host draws with `RunState::rng` in the order above. `output_newcomer` draws in the
  same order with the device stream, and its uid is assigned by the newcomer's own placement order in Task 4. Until
  then, newcomers take uids from `next_uid` by `atomicAdd` (ruling: the gap is closed in Task 4).

- [ ] **Step 5: Run them, then the suite.** Expected: the new tests PASS. The goldens FAIL on agents.csv's new
  columns only; Task 3 changes the comparison. Ledger this.

- [ ] **Step 6: Commit** `flamegpu: Chapter III state for founders and newcomers; --init and dump columns`.

### Task 3: The 45 metric columns, society metrics, and goldens compared column by column

**Files:**
- Modify: `src/metrics.h/.cu` (`MetricsRow` and `AgentColumns` widen; the CSV header in Python's order),
  `src/host_state.cu` (`write_metrics` gathers the new columns), `src/movement.cuh` (`commit_move` updates
  `disp_x/disp_y`)
- Modify: `tests/test_golden.py` (`comparable` compares, for `metrics.csv` and `agents.csv`, every column the golden
  file has, by name), `bridge/gpu_run.py` (`GPU_FINGERPRINT = "gpu-phase3\n"`), `tests/test_bridge.py` (expects
  it)
- Regenerate: `tests/data/golden/*` (after the test below proves the old columns unchanged)
- Test: create `tests/test_metrics_parity.py`

**Interfaces:**
- **Produces:** the CSV columns are exactly `list(sugarscape_metrics(model))` in that order.
  - Economic and disease columns take Python's values for runs without those rules: `mean_spice`, `trades`,
    `sugar_traded`, `spice_traded`, `mean_foresight`, `n_loans`, `n_lenders`, `n_borrowers`, `n_both`,
    `credit_depth`, `mean_diseases`, `sd_diseases`, `fraction_sick`, `new_infections` and `diseases_circulating`
    are 0.0, or NaN where Python's `safe_mean` / `np.std` of an empty population gives NaN. The price columns are
    NaN.
  - `mean_children` is 0.0 for an empty population.
- **Produces:** `compute_metrics` takes a uid → index map for friends' tags.
  `best_friend_closeness` and `friend_closeness` follow `society_metrics`: living tagged friends only, and
  closeness = 1 − Hamming / `tag_length`.
- **Produces:** `--out`'s `t = 0` row from the founders, as today.

- [ ] **Step 1: Write the failing tests** in `test_metrics_parity.py`:
  - `test_t0_row_matches_python`: every column of the t = 0 row equals Python's `sugarscape_metrics` (to 1e-12;
    NaN matches NaN), from the same `--init` agents. The agents:
    - tags of both tribes, on both sides of the anti-diagonal;
    - sex set;
    - two agents with `n_children` given via `--init`. Ruling: `--init` gains `n_children` for this test, and Python
      gets that many dummy dead children.
  - `test_one_step_matches_python`: the same, after one deterministic step (`test_parity`'s distinct-capacity map,
    agents far apart, tags on, culture off).
  - `test_csv_header_is_pythons`: the header equals `t` + `list(sugarscape_metrics(...))`.

- [ ] **Step 2: Run them.** Expected: FAIL (13 columns).

- [ ] **Step 3: Implement.** Gather the new columns as `AgentVector` columns, as `write_metrics` does today.

- [ ] **Step 4: Change `comparable`** to compare by column name, for every column the golden has. Run
  `test_golden`. Expected: PASS with the old golden files: the existing columns are unchanged.

- [ ] **Step 5: Regenerate** with `tests\make_golden.py`. Then check that every old column of every golden file is
  byte-identical to the committed version. Use a one-off script comparing `git show HEAD:<file>` by column, and
  ledger its output. Update `test_golden.py`'s docstring with this third regeneration (columns added only).

- [ ] **Step 6: Run the suite.** Expected: all pass.

- [ ] **Step 7: Commit** `flamegpu: Python's 45 metric columns, society metrics; goldens gain columns, old columns unchanged`.

### Task 4: The store and the turns, with Chapter II's turn body

**Files:**
- Create: `src/store.h`, `src/store.cu` (the device store: allocation sized from the world, publish/absorb kernels'
  helpers, the newborn and uid bookkeeping)
- Create: `src/turns.cuh` (footprints, the scheduler's layers and exit condition), `src/turn.cuh` (the turn body)
- Modify: `src/model.cu` (the turns layers when `cfg.sex || cfg.culture`, or `--force-turns`),
  `src/movement.cuh` (`commit_move` only records targets when the turns run), `src/main.cu` (`--force-turns`,
  `--serial-turns`, `--uid-capacity N`; exit 4 for `SchedulerError`, exit 5 for `CapacityError`; `waves_mean` in
  the timing JSON), `src/host_state.h` (`SchedulerError`, `CapacityError`), `CMakeLists.txt`
- Test: create `tests/test_turns.py`

**Interfaces:**
- **Produces, `struct Store`** (device-side, pointer struct in an environment property `store`, `uint64_t`):
  - row arrays indexed by the citizen's index this period (`getIndex()`), holding every citizen variable a turn
    touches, plus `start`, `target` (sites), `key` (`order_key`), `done`, `dead`;
  - `site_row[cells]` (−1 empty);
  - `uid_row[uid_capacity]`;
  - the newborn rows after `n_citizens`, with `(parent_key, seq)`;
  - the footprint entries.
- **Produces, footprint entry** `{site, key, write}`, one per (turn, site). Write wins when a turn both reads and
  writes a site.
- **Produces, the scheduler rule:**
  - Sort the entries by (site, key descending).
  - At each site, a maximal run of consecutive readers is one group, and each writer is a group of its own.
  - An entry waits for every member of the previous group at its site.
  - A turn's counter is the sum over its entries of the previous group's size.
  - When a turn finishes, it decrements the counter of every member of the next group after each of its entries.
  - Build with CUB or Thrust in a host function. The work is proportional to the entries.
- **Produces, layers:**
  - main model: `publish` (citizen), the `footprint` host function, the `turns` sub-model, `absorb` (citizen;
    DEAD for the dead), `spawn_newborns` (cell, agent output citizen);
  - inside `turns`: `run_turns` (a citizen with counter 0, not done, takes its turn), `release_turns`, and the
    exit condition `turns_done`.
  - In serial mode, `run_turns` runs only the turn whose rank in key order equals the wave number.
  - `turns_done` throws `SchedulerError("a wave ran no turn")` when turns are pending and none ran.
- **Produces, the turn body for Chapter II rules** (`take_turn` in `turn.cuh`): Python's `Model.step` for one agent:
  1. move to `target` (occupancy, `moved`, `disp`);
  2. harvest with production pollution;
  3. metabolism with consumption pollution; starvation marks the row dead and empties the site;
  4. `neighbors` counted from `site_row` as it stands.

  Old age stays at the end of the period, after the turns.
- **Footprint, Chapter II rules:** the turn writes its start and target sites, and reads and writes the four sites
  around the target.
- **Produces, newborn and newcomer uids:** after the turns, sort the newborns by `(parent_key` descending, `seq)`
  and give them uids in that order. Then the newcomers get uids in the order of their deaths: starved ones in turn
  order, then old-age ones in uid order.

- [ ] **Step 1: Context7.**
  - `/websites/flamegpu`: environment properties of type `uint64_t`; host functions launching custom kernels on
    `FLAMEGPU->getCUDAStream()` (or the documented stream accessor); sub-model exit conditions;
    `setAgentOutput` with another agent type.
  - Thrust or CUB: `sort_by_key` / `DeviceRadixSort::SortPairs` on 64-bit keys, and `DeviceScan`.

- [ ] **Step 2: Write the failing tests** in `test_turns.py`:
  - `test_turns_path_equals_fast_path`: on II-4 (400 random agents, 20 steps), II-8's pollution and II-7's seasons,
    `--force-turns` gives metrics.csv and both dumps byte-identical to the default path, at several dump periods.
    No replacement.
  - `test_serial_equivalence_chapter2`: `--force-turns` against `--force-turns --serial-turns`, byte-identical, on
    II-6's block (400 agents in 20×20) for 10 steps.
  - `test_waves_reported`: the timing JSON has `waves_mean ≥ 1` with `--force-turns`, and 0 without.
  - `test_dependency_chain`: a one-row 12×1 world where every agent neighbours the next. With `--serial-turns` and
    without, the dumps are identical, and `waves_mean` is above 1.
  - `test_turns_extinction`: metabolism 500 for everyone. After step 1 there are no citizens, and steps 2–5 run
    with exit 0. Rows t ≥ 1 have `population` 0, `mean_sugar` NaN and `mean_children` 0.0.
  - `test_turns_replacement_counts`: II-4-gini with `--force-turns --check` runs 30 steps with exit 0.

- [ ] **Step 3: Run them.** Expected: FAIL (unknown options).

- [ ] **Step 4: Implement** the store, publish/absorb, footprints, scheduler and turn body.
  - `run_turns` reads and writes only the store.
  - `check_invariants` counts births as newcomers + newborns.
  - Newcomers in the turns path are output in `absorb` (starved) and by the end-of-period old-age layer.

- [ ] **Step 5: Run the tests, then the suite.** Expected: all pass, the goldens included (the default path is
  untouched).

- [ ] **Step 6: Commit** `flamegpu: the device store and ordered turns (waves, serial mode), Chapter II turn body`.

### Task 5: Rule S in the turn, with every option

**Files:**
- Create: `src/sex.cuh` (Python's `is_fertile`, `in_sight`, `_empty_sites`, `mate`, `cross_tags`)
- Modify: `src/turns.cuh` (S footprints), `src/turn.cuh` (S after neighbours), `src/store.cu` (newborn rows),
  `src/model.cu` / `spawn_newborns` (children become citizens), end of period (children aged with everyone)
- Modify: `tests/reference.py` (Python scenarios with sex)
- Test: create `tests/test_sex.py`

**Interfaces:**
- **Consumes:** Task 4's `Store`, footprint entry, `take_turn` and the newborn rows.
- **Produces, S in the turn, line for line with `sex.mate`:**
  - partners = `in_sight` (vision contact) or the four neighbours, in a random permutation;
  - the empty sites around the agent, then around the partner, de-duplicated in that order, excluding the target of
    any agent whose turn isn't done;
  - the draws in Python's order: site, vision parent, metabolism parent, max-age parent, then the `redraw`
    threshold, sex, fertility ages, crossed tags;
  - gifts `floor(initial × share)` (`down`) or exact, or `min(5, max(sugar, 0))` when `capped`;
  - both parents' `n_children` += 1; the child's `parent_a/b` = the two uids; the child starts at age 0.
- **Produces, `in_sight` distances:** with stride 1, 1..vision. With stride s > 1, `look_distance(look_seed ^ SIGHT_SALT, d, k, s)`,
  where `SIGHT_SALT = 0x5EED5EEDu` keeps them apart from movement's looks.
- **Footprint, S:** for an agent of childbearing age with sex:
  - `neighbors` contact: writes the sites within Manhattan distance 2 of the target.
  - `vision` contact: writes every sight-line site from the target and the four sites around each one, and the four
    sites around the target.

- [ ] **Step 1: Context7.** `/websites/flamegpu`: `AgentRandom::uniform<uint64_t>` (permutations and choices via
  the 64-bit draw, as `place_newcomer` does).

- [ ] **Step 2: Write the failing tests** in `test_sex.py`:
  - `test_mating_matches_python[...]`, one case per option. Parity scenarios in which the result can't depend on
    order or draws: one fertile F/M pair whose parents share vision, metabolism and max age, with exactly one empty
    site next to either. Compared with Python's dump: holdings to 1e-9, the child's site, traits and `n_children`.
    The cases:
    - `book`: exact gifts, neighbours contact;
    - `intgift`: `down`;
    - `c1`: vision contact, partner 3 sites away;
    - `capped`;
    - `redraw`: the child's `initial_sugar` lies in the endowment range;
    - `threshold`: `fertility_threshold = 0.74`, the pair fertile only at that threshold.
  - `test_no_birth_without_empty_site`: a pair with every neighbouring site occupied.
  - `test_child_never_on_pending_target`: Python's rule plus difference 2. Agent C, later in the order, moves to the
    only empty site next to an F/M pair that comes earlier. Run 20 seeds: no child is ever born at C's target, and
    C always arrives there.
  - `test_serial_equivalence[block_vision|neighbors|stride5]`: III-1's config with 400 agents in a 20×20 block,
    20 steps. Also `mate_contact = neighbors`, and the `stride5` case with vision 5..20 and `look_stride = 5`.
    Waves are byte-identical to `--serial-turns`.
  - `test_turns_replacement_check`: III-1's config with replacement and `--check`, 40 steps, exit 0.
  - `test_uid_capacity_exceeded`: `--uid-capacity 450` on III-1 exits 5, with stderr naming `uid capacity`.
  - `test_children_aged_in_birth_period`: in the `book` case, the child's age is 1 at the dump after its birth period.

- [ ] **Step 3: Run them.** Expected: FAIL.

- [ ] **Step 4: Implement.**

- [ ] **Step 5: Run the tests, then the suite.** Expected: all pass.

- [ ] **Step 6: Commit** `flamegpu: rule S in the turn, every option, children in creation order`.

### Task 6: Inheritance I at old age

**Files:**
- Modify: `src/rules.cuh` (the end-of-period old-age layers: dying flag, then heirs pull), `src/model.cu`
- Test: create `tests/test_inheritance.py`

**Interfaces:**
- **Produces:** the end of the period, after the turns:
  1. `age += 1` for every citizen, newborns included;
  2. a citizen with `age >= max_age` is marked dying;
  3. each living, non-dying citizen adds `parent.sugar / k` for each dying parent with `sugar > 0`, where k is that
     parent's number of living, non-dying children. Shares are added in increasing parent uid.
  4. The dying die.
- **Produces:** the count k comes from an integer atomic count by children, in the layer before the shares are added.
- **Ruling (deferred to Part C):** inheritance at starvation moves only positive holdings. Sugar is ≤ 0 at
  starvation, and spice arrives in Part C, so Part A has nothing to move. Part C adds the starving agent's heirs to
  its footprint (spec section 2) with spice. Cost if wrong: none for Part A's experiments, whose starvations pass on
  nothing in Python either.

- [ ] **Step 1: Write the failing tests:**
  - `test_inheritance_matches_python`: a parent with `max_age` reached, three living children (one also dying),
    and `inheritance = true`. Matches Python's dump to 1e-9: each surviving child gets half.
  - `test_two_parents_die_together`: both parents of one child die in the same period. The child gets both shares,
    added in parent uid order (compared with Python to 1e-12).
  - `test_no_inheritance_flag`: the same without `inheritance`, and nothing moves.

- [ ] **Step 2: Run them.** Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: inheritance at old age, heirs in parent creation order`.

### Task 7: Culture K and friends

**Files:**
- Create: `src/culture.cuh` (Python's `transmit`, `update_friends`, `hamming`)
- Modify: `src/turn.cuh` (K after S), `src/turns.cuh` (friends in the footprint)
- Test: create `tests/test_culture.py`

**Interfaces:**
- **Produces, K in the turn:**
  - transmit to the four neighbours as they stand after mating, newborns included, in a random permutation: copy
    the agent's tag at a random position;
  - then `update_friends` with the neighbour list from before mating:
    - drop dead friends;
    - add new ones up to 5, by distance at the encounter;
    - replace the stored-farthest only when strictly closer, the first of equal maxima.
- **Footprint, culture:** reads and writes the four sites around the target. For each friend, reads its start site
  if its key is smaller, else its target (spec section 2).
- **Produces:** a friend is dead if its row is dead or its uid has no row.

- [ ] **Step 1: Write the failing tests:**
  - `test_transmit_matches_python`: `tag_length = 1`, one agent with a single neighbour that differs. After one
    step the neighbour's tag equals the agent's, as in Python (the position draw can't matter at length 1).
  - `test_friends_match_python`: a line of agents where each meets known neighbours over 3 steps, with `friend_uid`,
    `friend_dist` and `n_friends` compared with Python. Cases: the cap of 5, strictly-closer replacement, and a
    dead friend dropped.
  - `test_friend_closeness_metrics`: the two closeness columns match Python for the same state.
  - `test_serial_equivalence[culture|culture_sex]`: III-8's and III-15's configs at 400 and 100 agents. Waves equal
    serial mode byte for byte over 30 steps.

- [ ] **Step 2: Run them.** Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: culture K and friends in the turn`.

### Task 8: The semantics harness and the agreement report

**Files:**
- Create: `bridge/semantics_harness.py` (the scratch `hybrid.py` from the design investigation, cleaned:
  Python's model with deferred-acceptance targets chosen first, then every turn in order, children never on pending
  targets; writes `results-harness/`)
- Create: `bridge/agreement_report.py`
- Test: create `tests/test_agreement_report.py`, `tests/test_semantics_harness.py`

**Interfaces:**
- **Produces:** `python -m bridge.agreement_report <id-or-prefix>... [--gpu DIR] [--python DIR] [--out FILE]`.
  - It loads `julia/bridge/agreement.py` by path (`importlib.util.spec_from_file_location`, module name
    `julia_agreement`).
  - It runs `compare_experiment` and `flag` on GPU against Python seeds.
  - It writes markdown: totals; every flagged check; checks with p < 0.01; untestable windows; stale fingerprints;
    and a speed table (setup, stepping per period and metrics per period from each side's `timing.csv`, with the
    GPU/Python ratio).
  - The default output is `<gpu dir>/AGREEMENT.md`.
  - Ids match as `bridge.gpu_run.matching_ids` matches them. An experiment with no seeds on either side is listed
    as "not run" and isn't tested.
- **Produces:** `python -m bridge.semantics_harness <id-or-prefix>... [--jobs J]`, the same series layout as
  `experiments.run`, so `agreement_report --gpu results-harness` scores it.

- [ ] **Step 1: Write the failing tests:**
  - `test_identical_series_no_flags`: two folders with the same synthetic seeds give 0 flagged.
  - `test_shifted_series_flagged`: one metric shifted by 5 SD in one window is flagged, and named in the markdown.
  - `test_speed_table_ratio`: synthetic `timing.csv` files give the expected ratio.
  - `test_missing_side_not_run`: an id with Python seeds but no GPU folder is listed as "not run", and the report
    doesn't fail.
  - `test_harness_runs`: the harness on III-1 for 3 steps and 1 seed writes `seed0.csv` with Python's columns.

- [ ] **Step 2: Run them.** Expected: FAIL (no modules).

- [ ] **Step 3: Implement both.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Rerun the harness** on the 43 experiments of the design's measurement (`--jobs 22`, about 5 min) and
  score it.
  - Expected: 0 flagged among about 2,835 tested windows.
  - Write the result into a new `docs/validation/semantics-harness.md`, with the command lines.

- [ ] **Step 6: Commit** `flamegpu: semantics harness and the agreement report`.

### Task 9: Part A's experiments against Python

**Files:**
- Create: `docs/validation/chapter3-part-a.md`
- Modify: `README.md` ("How the GPU version differs": the turns, differences 1–3 and the limits; the rules now on
  the GPU)

- [ ] **Step 1: Run the experiments** on `build\` (seatbelts on):
  `.venv\Scripts\python -m bridge.gpu_run <id> --jobs 4` for III-1, -3, -4, -5, -7, -8, -12, -15 and each of
  `VAR-book`, `VAR-share`, `VAR-c1c3fit`, `VAR-intgift`, `VAR-intgiftc1` and `VAR-fit83` on `III-[1345]`.
  Expected: every run exits 0. Ledger the wall time.

- [ ] **Step 2: Agreement.** `.venv\Scripts\python -m bridge.agreement_report III VAR --out docs/validation/agreement-part-a.md`.
  - Expected: 0 flagged.
  - Each flag gets superpowers:systematic-debugging, then a fix (back to the owning task's tests) or a written
    explanation with its evidence: a harness run of the same experiment, or more seeds.

- [ ] **Step 3: Book targets.** `.venv\Scripts\python -m bridge.gpu_report --chapter III` and `--chapter VAR`. Every
  status change against Python is explained in the validation doc. The combat experiments show "not run".

- [ ] **Step 4: xl smoke run.** III-1 at xl, 1 seed, 20 steps on `build-fast\`, exits 0. Ledger the waves per
  period and the stepping per period.

- [ ] **Step 5: Write `docs/validation/chapter3-part-a.md`:**
  - what ran;
  - the agreement verdict and every flag or status change, explained;
  - waves per period and stepping ms per period per experiment, from the timing JSON;
  - the xl smoke run.

  Then update the README.

- [ ] **Step 6: Run the suite.** Expected: all pass.

- [ ] **Step 7: Commit** `flamegpu: Part A validation — Chapter III without combat against Python`.
