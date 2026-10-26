# Every Rule on the GPU, Part B: Combat and Same-Tribe Replacement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Python's combat rule C_α and C_∞ (`combat_alpha`) and same-tribe replacement
(`replacement_same_tribe`) on the GPU in Python's turn order, with every rule they combine with, and agreement with
Python on III-9, -11, -13 and -14.

**Architecture:**
- With combat, there is no deferred-acceptance movement. Each turn is Python's whole `combat_move`: it scans, checks
  for retaliation, attacks, moves and harvests. Then the rest of the turn follows as in Part A.
- **Whole turns in waves.** Each combat turn's footprint covers every site it may write: its start, every site on
  its sight lines, and the neighbour-rule sites around each. It also lists, as reads, the retaliation sight lines
  from each of those sites.
- **Turns path changes:**
  - During the turns, site sugar lives in the store, so a turn can read it while others harvest.
  - A victim dies inside its attacker's turn and takes no turn of its own.
- **Combat with inheritance** runs one turn per wave (spec section 2).
- **Same-tribe replacement** redraws a newcomer's tags until its tribe matches the dead agent's. This works on every
  path that makes newcomers.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), CUB (shipped with CUDA), pytest, the Python bridge in
`flamegpu/bridge/`.

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-full-parity-design.md` (Part B of "The work, in
parts"; sections 2, 4 and 5). Part A's plan, `2026-10-25-gpu-parity-part-a.md`, describes the store, the waves and
the tests this plan extends.

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`, seatbelts on, used by pytest) and `scripts\build.cmd build-fast OFF`.
  Run all commands from `flamegpu/`.
- **The suite** is `.venv\Scripts\python -m pytest tests -q`.
- **Context7** before FLAME GPU (`/websites/flamegpu`) or CUB code is written. Each task names its lookups.
- **Macro-property rule:** within a layer a macro property is only read, or only atomically written. During the
  turns the `sugar` macro property is neither read nor written; the store's `site_sugar` stands in for it (Task 2).
- **No change to Chapter II or Part A outputs.**
  - Chapter II's goldens and every Part A test pass unchanged.
  - The newcomer death keys change scale in Task 2, but not order, so uids are unchanged.
  - `GPU_FINGERPRINT` stays `gpu-phase3`. *Ruling: no output column or value changes.*
- **No nondeterminism:** a seed gives the same bytes every run, in waves and in `--serial-turns`.
- **Combat has none of the differences from Python** (spec section 8). Every combat test may compare with Python
  exactly wherever the order and the draws cannot change the outcome.
- **Still refused after Part B:** `spice` and the Chapter IV fields, and the disease fields. `ConfigError` names
  them as "not on the GPU yet".
- **Existing tests:** the spec approves changing the tests that pin the refusal boundary (`test_bridge`, `test_cli`)
  when that boundary moves (Task 1). No assertion about behaviour is weakened.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A newborn killed in its birth period** (combat with sex). Python counts it as a death, replaces it, and has
   already given it a uid. The GPU must do the same, although a newborn is a store row and not a citizen. Pinned
   by `test_newborn_victim` (Task 4).
2. **A friend killed after its own turn, but before its friend's turn** (III-14). The friend's "is it alive?" check
   must wait for the killer's turn. Pinned by `test_serial_equivalence_combat[III-14]` and
   `test_killed_friend_dropped` (Task 4).
3. **Look stride above 1.** The retaliation scans' distances must be the same in the turn and in the footprint.
   Pinned by `test_serial_equivalence_combat[stride5]` and `test_combat_check[stride5]` (Task 3).
4. **C_∞** (`combat_alpha = inf`). `min(inf, sugar)` must stay finite, and run.cfg's `inf` must parse. Pinned by
   `test_attack_matches_python[inf]` (Task 2).
5. **Site sugar read in the turns layer.** Combat reads candidate sites' sugar while other turns harvest, so it must
   never touch the `sugar` macro property in that layer. Pinned by every `test_combat.py` test, which run on the
   seatbelts build (Task 2).

---

### Task 1: Combat configuration fields and same-tribe replacement

**Files:**
- Create: `src/tribe.h` (`is_blue`, host and device)
- Modify: `src/config.h`, `src/config.cu` (fields, parsing, `validate`, `print_config`; `UNSUPPORTED` loses
  `combat_alpha` and `replacement_same_tribe`)
- Modify: `src/rules.cuh` (`output_newcomer` takes the dead agent's tags; `metabolize_and_age` passes them)
- Modify: `src/turns.cuh` (`absorb`, `age_and_die` and `die_old` pass the dead agent's tags)
- Modify: `src/model.cu` (environment property `same_tribe`), `src/host_state.cu` (uses `tribe.h`)
- Modify: `bridge/config_cfg.py` (`FIELDS`), `tests/gpu.py` (`DEFAULT_CFG`), `tests/reference.py`
  (`config_from_cfg`)
- Test: `tests/test_bridge.py`, `tests/test_cli.py`; create `tests/test_same_tribe.py`

**Interfaces:**
- **Produces, `RunConfig` fields:**
  - `std::optional<double> combat_alpha;`, where `INFINITY` is C_∞;
  - `bool replacement_same_tribe = false;`;
  - `bool combat() const { return combat_alpha.has_value(); }`.
- **Produces, run.cfg:**
  - `combat_alpha =` is empty for none, `inf`, or a number;
  - `replacement_same_tribe = true|false`;
  - `print_config` prints both after `gift_rounding`.
- **Produces, `validate`, with Python's messages:**
  - `culture, combat, and tribal blocks need cultural tags (tag_length > 0)` replaces today's message;
  - `combat_alpha must be >= 0, not X`;
  - `replacement_same_tribe needs replacement=True`.
  - Until Task 2, a set `combat_alpha` is refused with `combat_alpha: not on the GPU yet`. Task 2 removes that
    line.
- **Produces, `src/tribe.h`:** `__host__ __device__ inline bool is_blue(uint64_t tags, int length)`. This is
  Python's `culture.tribe`: blue when `2 · popcount < length`. It uses `__popcll` on the device. `host_state.cu`'s
  copy goes.
- **Produces:** `output_newcomer(FLAMEGPU, uint64_t death_key, uint64_t dead_tags)`. With `same_tribe` set and
  `tag_length > 0`, the newcomer's tags are redrawn with `random_bits` until
  `is_blue(tags) == is_blue(dead_tags)`, as Python's `random_tags` does. Without tags, same tribe changes nothing.
- **Produces:** `bridge.config_cfg.FIELDS` gains `"combat_alpha"` and `"replacement_same_tribe"`.
  `tests/reference.py` maps them as follows: `""` → `None`, `"inf"` → `math.inf`, and a number → `float`.

- [ ] **Step 1: Write the failing tests.**
  - **`test_same_tribe.py`:**
    - `test_starved_newcomers_keep_tribe[fast-blue|fast-red|turns-blue|turns-red]`. The world is a 20×20
      zero-capacity map. Forty founders, all of one tribe (11 tag bits, all 0 for blue or all 1 for red), sit on
      every other site of rows 2–5 with sugar 1 and metabolism 5, so all starve in period 1. The config has
      `replacement = true`, `max_age = 60,100` and `replacement_same_tribe = true`.
      - `fast`: `tag_length = 11` only.
      - `turns`: also `culture = true`.
      - Assert: the dump at t = 1 holds 40 agents, all of the founders' tribe. Without the rule, the chance of this
        is 2⁻⁴⁰.
    - `test_old_age_newcomers_keep_tribe[fast|turns|turns-inheritance]`: as above, but with sugar 50 and `--init`
      `max_age = 1`, so all die of old age in period 1. Covers `metabolize_and_age`, `age_and_die` and
      `die_old`.
    - `test_same_tribe_needs_replacement`: exit 2, stderr contains `replacement_same_tribe needs replacement`.
  - **`test_cli.py`:**
    - Add `test_combat_alpha_validated[-1|no-tags]`: exit 2, with `combat_alpha must be >= 0` or
      `need cultural tags`.
    - `test_unsupported_feature_key_is_rejected` now uses `spice = true`.
    - `test_later_parts_still_refused` drops `combat_alpha` and `replacement_same_tribe`.
  - **`test_bridge.py`:**
    - `test_unsupported_lists_features` now uses `Config(spice=True)` and expects `["spice"]`.
    - Add `test_part_b_configs_convert`:
      - III-9's run.cfg holds `combat_alpha = inf`;
      - III-11's holds `combat_alpha = 2` and `replacement_same_tribe = true`;
      - `unsupported_features` is empty for III-9, -11, -13 and -14.

- [ ] **Step 2: Run them.** Expected: FAIL. The same-tribe tests fail on mixed tribes or on the
  `not on the GPU yet` refusal. The bridge test fails on `combat_alpha` being unsupported.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: combat config fields; same-tribe replacement on every newcomer path`.

### Task 2: The combat turn, one turn per wave

**Files:**
- Create: `src/combat.cuh` (Python's `combat_candidates`, `vulnerable` and `combat_move`)
- Modify: `src/store.h`, `src/store.cu` (`site_sugar`, `dir_order` and `death_key` buffers; `turn_death_key`)
- Modify: `src/looks.cuh` (`RETALIATION_SALT`, `combat_candidate_id`, `retaliation_distance`)
- Modify: `src/turns.cuh`:
  - `publish` copies `dir_order`;
  - `run_turns` skips a row that is already dead;
  - `absorb` uses the row's `death_key`;
  - new cell functions `stage_sites` and `unstage_sites`.
- Modify: `src/turn.cuh`:
  - the combat branch replaces the move;
  - every harvest uses `site_sugar`;
  - the starved death key.
- Modify: `src/model.cu`:
  - environment `combat` and `combat_alpha`, in the main and turns models;
  - no movement sub-model with combat;
  - the stage and unstage layers;
  - serial with combat (until Task 3).
- Modify: `src/config.h` (`turns_on()` includes `combat()`), `src/config.cu` (remove Task 1's refusal)
- Test: create `tests/test_combat.py`

**Interfaces:**
- **Consumes:** Task 1's `RunConfig::combat()`, `combat_alpha`, `is_blue` and `output_newcomer(..., dead_tags)`.
- **Produces, `Store`:**
  - `float* site_sugar` (`cells`). Before `publish`, `stage_sites` copies each site's sugar macro property into it,
    one cell each. After the turns, `unstage_sites` writes it back with `exchange`. Every harvest on the turns path
    goes through it, and no turns-layer code touches the `sugar` macro property.
  - `unsigned int* dir_order` (rows): the period's scan order, from `start_period`, two bits per direction.
  - `uint64_t* death_key` (rows): `turn_death_key(rank, victim)`, set when a row dies in a turn.
- **Produces:** `__host__ __device__ inline uint64_t turn_death_key(unsigned int rank, bool victim)`, which returns
  `rank << 1 | (victim ? 0 : 1)`.
  - A victim killed in a turn dies before that turn's own agent could starve, as Python appends them to
    `dead_this_step`.
  - It replaces `starved_key(rank)` on the turns path. The fast path keeps `starved_key(~key >> 1)`.
- **Produces, `looks.cuh`:**
  - `RETALIATION_SALT = 0xC0DEC0DEu`.
  - `combat_candidate_id(d, k, looks)` is `1 + d·looks + k`; 0 is the own site.
  - `retaliation_distance(look_seed, cand, d, k, stride)` is `k + 1` at stride 1. Otherwise it is
    `look_distance(mix32(look_seed ^ RETALIATION_SALT ^ (cand + 1) · 0x9E3779B9u), d, k, stride)`.
  - Each retaliation scan draws its own looks, as Python's `vulnerable` calls `look_distances` afresh. The scan of
    candidate sites uses `look_distance(look_seed, d, k, stride)`, as movement does.
- **Produces, `combat.cuh`:**
  - `struct CombatChoice { unsigned int site; int victim; };`, where `victim` is -1 when the site is empty.
  - `template <typename API> __device__ CombatChoice combat_choose(API*, const Store&, unsigned int row)`.
  - `__device__ void combat_kill(const Store&, unsigned int victim, unsigned int attacker, double alpha)`.
- **Behaviour, line for line with Python:**
  - **Candidates:**
    - First the own site, with reward = site sugar.
    - Then, for each direction in `dir_order`, each look out to vision. An empty site's reward is its sugar. An
      occupied site is a candidate only if its occupant is of another tribe and has sugar ≤ the agent's. Its
      reward is then site sugar + `min(alpha, occupant sugar)`, in double. Sight continues past an excluded site.
  - **Vulnerable:** a candidate is vulnerable if, along any of the four lines from it, an occupant other than the
    agent and that candidate's victim is of another tribe and has sugar greater than `agent sugar + reward`.
  - **Choice:**
    - The first safe candidate, replaced only by a strictly greater reward, or by an equal reward at a strictly
      smaller distance.
    - With no safe candidate, the own site.
  - **Then:**
    1. Take `min(alpha, victim sugar)` from the victim. The victim dies: `dead`, `death_key = turn_death_key(rank,
       true)`.
    2. Move, setting `moved`, `disp`, `site_row` and `occupied`.
    3. Harvest all the site's sugar, with **no** production pollution.
    4. Part A's metabolism, with consumption pollution, then neighbours, S and K.
- **Produces:** a row that is dead when its turn comes is marked `done` and `ran`, without `take_turn`.
- **Produces:** with combat, the `serial_turns` environment property is 1 (Task 3 removes this).

- [ ] **Step 1: Context7.** `/websites/flamegpu`:
  - reading a macro property and `exchange` on it from an agent function;
  - a cell (non-citizen) agent function in its own layer.

- [ ] **Step 2: Write the failing tests** in `test_combat.py`. Each case compares with Python's dump after one step
  (`compare_dumps(gpu, py) == []`, holdings to 1e-9). The world is a 20×20 map with `tag_length = 1` (`"0"` blue,
  `"1"` red). Every agent except the attacker has vision 0 and metabolism 0, and its site has capacity 0, so its own
  turn changes nothing and the order cannot matter. The attacker A is red, at (5,5), with sugar 20, vision 2 and
  metabolism 1.
  - `test_attack_matches_python[2|inf]`: victim V, blue, sugar 5, at (6,5); an empty site at (5,7) with capacity 3.
    - With alpha 2, A moves to (5,7), since 3 > 2.
    - With inf, A kills V and takes 5.
  - `test_retaliation_blocks_attack`: inf, plus R, blue, sugar 100, at (8,5). V's site is vulnerable, so A goes to
    (5,7).
  - `test_no_safe_site_stays`: no V and no (5,7); A has vision 1. Four blue agents with sugar 100 sit on all four
    sites next to A. A's site has capacity 2. A stays and ends with 20 + 2 − 1.
  - `test_same_tribe_not_attacked`: as the `inf` case, with V red. A goes to (5,7).
  - `test_richer_not_attacked`: as the `inf` case, with V's sugar at 30. A goes to (5,7).
  - `test_equal_reward_nearer_wins`: no V and no (5,7); A has vision 3. Capacity 4 at (7,5) and at (5,6). A takes (5,6) in every one of 10
    seeds.
  - `test_combat_harvest_unpolluted`: the `2` case with `pollution = 1,0`. Pollution stays 0 everywhere, as in
    Python (`compare_dumps(..., pollution=True)`).
  - `test_victim_counted_once`: the `inf` case with `--check`. Exit 0, and the t = 1 metrics row shows
    `deaths = 1` and `population = 1`, as in Python's `sugarscape_metrics`.

- [ ] **Step 3: Run them.** Expected: FAIL (`combat_alpha: not on the GPU yet`).

- [ ] **Step 4: Implement.**

- [ ] **Step 5: Run them, then the suite.** Expected: all pass, Part A's serial-equivalence and turns-equal-fast-path
  tests included. They are the guard that staging site sugar and the new death keys changed no output.

- [ ] **Step 6: Commit** `flamegpu: combat turn (C_alpha, C_inf) in Python's order, site sugar in the store`.

### Task 3: The combat footprint, and waves

**Files:**
- Modify: `src/footprint.cuh` (`FootprintEnv::combat`; the combat footprint)
- Modify: `src/store.cu` (the environment it builds)
- Modify: `src/combat.cuh` (touch points)
- Modify: `src/model.cu` (`serial_turns` is `cfg.serial_turns` again)
- Test: `tests/test_combat.py`

**Interfaces:**
- **Consumes:** Task 2's `combat_candidate_id`, `retaliation_distance`, `look_distance` and `dir_order`, and Part
  A's `footprint(s, row, env, emit)` and `around`.
- **Produces:** `FootprintEnv` gains `bool combat`. With combat, a turn's footprint replaces Part A's
  start/target/around-target entries with the following, all from the start site.
  - **Writes:**
    - the start site;
    - every candidate site P: the start, and every sight-line site at `look_distance(look_seed, d, k, stride)` for
      d < 4 and k < vision / stride;
    - the four sites around each P.
  - **Reads:** for each candidate P with id c, every site on P's retaliation lines,
    `P + dir(d') · retaliation_distance(look_seed, c, d', k', stride)`.
- **Produces, `--check` touch points:**
  - 7: every site the candidate scan reads;
  - 8: every site a retaliation scan reads;
  - 9: the chosen site, at the move.

- [ ] **Step 1: Write the failing tests** in `test_combat.py`. The configs come from the registry:
  `config_to_cfg(EXPERIMENTS[id].config, ...)` is parsed into `write_cfg` overrides, without the map, steps and
  seed.
  - `test_serial_equivalence_combat[III-9|III-11|III-13|stride5]`, 20 steps each. Waves are byte-identical to
    `--serial-turns`: metrics, agents and landscape (`test_sex._files`). `stride5` is III-9 with `vision = 5,10`
    and `look_stride = 5`.
  - `test_combat_check[III-9|III-13|stride5]`: 20 steps with `--check`, exit 0.
  - `test_combat_waves_concurrent`: III-9, 3 steps. `waves_mean` in the timing JSON is greater than 1 and less than
    half of `agents_start`.

- [ ] **Step 2: Run them.** Expected: `test_combat_waves_concurrent` FAILS, because combat still runs serially. The
  equivalence tests pass trivially.

- [ ] **Step 3: Implement** the footprint, the touch points, and `serial_turns` back to the command line's value.

- [ ] **Step 4: Run them, then the suite.** Expected: all pass. A footprint miss shows as a `--check` failure that
  names the touch point. Fix the footprint, never the test.

- [ ] **Step 5: Commit** `flamegpu: combat turns in waves, footprints over the sight and retaliation lines`.

### Task 4: Combat with culture K and sex S, and newborn victims

**Files:**
- Modify: `src/footprint.cuh` (friends and S under combat)
- Modify: `src/combat.cuh` (a newborn row as victim)
- Modify: `src/turns.cuh` (host function `bury_newborns`)
- Modify: `src/host_state.cu`, `src/host_state.h` (`draw_newcomer`, shared with founders' draws)
- Modify: `src/model.cu` (the `bury_newborns` layer after `assign_births`)
- Test: `tests/test_combat.py`

**Interfaces:**
- **Consumes:** Task 3's combat footprint, Part A's S footprint around a site, and Part A's `birth_uids`.
- **Produces, the footprint under combat:**
  - **Friends:** a friend later in the order is read at its start. A friend earlier in the order is read at its
    start and at every candidate site of its own scan. Those are all the sites where it can stand, alive or killed,
    at this agent's turn.
    - *Ruling:* the spec names "its target", and under combat its target isn't known before the turns. Cost if
      wrong: more entries per friend, not wrong results.
  - **Sex:** for an agent of childbearing age, Part A's S footprint (the radius-2 diamond, or the sight lines and
    the sites around each) around **every** candidate site, not just a fixed target.
- **Produces, newborn victims:**
  - A newborn (row ≥ `n_rows`) can be a victim, as in Python, where a child joins the grid at birth.
  - It gets `dead` and its `death_key`, and is never spawned, because its site is now the attacker's.
  - `birth_uids` still gives it a uid, as Python's `new_agent` did.
  - **The host function `bury_newborns`**, after `assign_births`:
    - reads the dead newborn rows' `(death_key, tags)`, sorted by death key;
    - adds their count to the `deaths` macro property;
    - with replacement, creates one unplaced citizen per victim through the host agent API, with `x = y = -1` and
      that `death_key`.
  - **`draw_newcomer(std::mt19937_64&, const RunConfig&, uint64_t dead_tags)`** fills those citizens. Its draws
    follow `output_newcomer`'s order and ranges, from the host's `rng`, with the same-tribe redraw.
  - *Ruling:* host draws come from a different stream than device draws, but they are deterministic per seed and
    have the same distribution. Cost if wrong: none to agreement.

- [ ] **Step 1: Context7.** `/websites/flamegpu`:
  - `HostAgentAPI::newAgent` in a host layer function, and when those agents join the population;
  - writing an environment macro property from a host function.

- [ ] **Step 2: Write the failing tests** in `test_combat.py`.
  - `test_serial_equivalence_combat[III-14|sex_neighbors|sex_vision]`, 20 steps:
    - `III-14` from the registry;
    - `sex_neighbors` and `sex_vision`: III-9 with `sex = true`, `max_age = 60,100`, `endowment = 50,100`,
      `replacement = true`, and that `mate_contact`.
    - Also `--check` exits 0 for each.
  - `test_killed_friend_dropped`: `tag_length = 1`, alpha inf, 2 steps, compared with Python's friends.
    - Red A at (5,5) has sugar 50, vision 1 and metabolism 1. Blue V at (6,5) has sugar 5. Every site has
      capacity 0.
    - Blue X at (15,15) has sugar 50, and V given as a friend (`friends = "1:0"`).
    - After step 2, X has no friends, in both.
  - `test_newborn_victim`, over 20 seeds: `mate_contact = neighbors`, `tag_length = 1`, alpha inf,
    `replacement = true`, `max_age = 60,100`, `--check`.
    - **The parents:** blue F at (5,5) and blue M at (6,5), both age 20, with sugar 60, initial sugar 50, vision 0
      and metabolism 0. F's fertility runs 12–50 and M's 12–60. After one child, each is left with 35, below its
      initial sugar, so neither mates again.
    - **The blockers:** five blue males aged 70, with sugar 120, vision 0 and metabolism 0, at (4,5), (5,4), (7,5),
      (6,6) and (6,4). That leaves (5,6) as the only possible child site.
    - **The attacker:** red A at (5,9), a male aged 70, with sugar 100, vision 3 and metabolism 0.
      - If A's turn comes before the child exists, every reward is 0, so A stays.
      - Otherwise the child (sugar 50) is the best reward. It is safe, because 120 < 100 + 50.
    - **Assert, for each seed:** exit 0, and either outcome below; both outcomes occur over the seeds.
      - **Killed:** A ended at (5,6). There is no child, and `deaths` at t = 1 is 1. `agents_ever` is 10: 8
        founders, the child, and its newcomer, which was placed.
      - **Survived:** A stayed at (5,9). The child is at (5,6), `deaths` is 0, and `agents_ever` is 9.
    - If the layout doesn't produce both outcomes, adjust positions or sugar and record a ruling. The assertions
      stay as they are.

- [ ] **Step 3: Run them.** Expected: FAIL.
  - The equivalence tests fail on a footprint miss under `--check` or on bytes.
  - `test_newborn_victim` fails on `--check`'s population accounting or on `deaths`.

- [ ] **Step 4: Implement.**

- [ ] **Step 5: Run them, then the suite.** Expected: all pass.

- [ ] **Step 6: Commit** `flamegpu: combat with culture and sex; newborn victims die, count and are replaced`.

### Task 5: Combat with inheritance

**Files:**
- Modify: `src/combat.cuh` (the victim's heirs), `src/config.h` (`serial()`), `src/model.cu`
- Test: `tests/test_combat.py`

**Interfaces:**
- **Consumes:** Task 2's `combat_kill`, Part A's `PROVISIONAL_PARENT` and the newborn rows.
- **Produces:** `bool RunConfig::serial() const { return serial_turns || (combat() && inheritance); }`. The
  `serial_turns` environment property takes it.
  - Spec section 2: a victim's heirs are found only at the turn, so combat with inheritance runs one turn per wave.
- **Produces, Python's `die` for a victim, with I on:**
  - After the take, positive sugar is split equally among the victim's living children.
  - The children are the rows (citizens and this period's newborns) that are not dead and whose `parent_a` or
    `parent_b` names the victim: its uid, or `PROVISIONAL_PARENT | row` for a victim born this period.
  - The attacker's thread scans every row. In serial mode this is safe.

- [ ] **Step 1: Write the failing tests:**
  - `test_victim_heirs_inherit[2|inf]`: Task 2's attack layout without the site at (5,7), so A attacks at either
    alpha. It has `inheritance = true`, V with sugar 10, and
    children C1 at (15,2) and C2 at (15,15). The children have `parent_a` = V's index, sugar 1, vision 0,
    metabolism 0, and capacity 0. Compared with Python's dump to 1e-9:
    - alpha 2 leaves V 8, so each child ends with 5;
    - alpha inf leaves V nothing.
  - `test_combat_inheritance_serial`: III-9 with `inheritance = true`, 1 step. `waves_mean` equals
    `agents_start`.

- [ ] **Step 2: Run them.** Expected: FAIL (the children don't inherit; waves are concurrent).

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: combat with inheritance, one turn per wave, victims' heirs paid at the kill`.

### Task 6: Part B's experiments against Python

**Files:**
- Create: `docs/validation/chapter3-part-b.md`, `docs/validation/agreement-part-b.md`
- Modify: `README.md`. "How the GPU version differs" says:
  - combat is on the GPU and has none of the three differences;
  - combat with inheritance runs one turn per wave;
  - retaliation looks at stride > 1 are drawn per scan from the period's look seed.

  It also lists combat and same-tribe replacement among the rules on the GPU.

- [ ] **Step 1: Run the experiments** on `build\`: `.venv\Scripts\python -m bridge.gpu_run <id> --jobs 4` for
  III-9, III-11, III-13 and III-14. Expected: every run exits 0. Ledger the wall time.

- [ ] **Step 2: Agreement.** `.venv\Scripts\python -m bridge.agreement_report III-9 III-11 III-13 III-14 --out docs/validation/agreement-part-b.md`.
  - Expected: 0 flagged. Combat has no difference from Python, so any flag is a bug until shown otherwise.
  - Each flag gets superpowers:systematic-debugging, then a fix (back to the owning task's tests) or a written
    explanation with its evidence.

- [ ] **Step 3: Book targets.** `.venv\Scripts\python -m bridge.gpu_report --chapter III`. Every status change
  against Python for III-9, -11, -13 and -14 is explained in the validation doc, with its seed-level p.

- [ ] **Step 4: xl smoke run.** III-9 and III-13 at xl, 1 seed, 5 steps on `build-fast\`, run as Part A ran III-1
  (`docs/validation/chapter3-part-a.md`, "xl smoke run").
  - Ledger the waves per period and the stepping per period.
  - If the footprint buffers can't be allocated, record the exit and message as Part F's work. Don't change the
    design here.

- [ ] **Step 5: Write `docs/validation/chapter3-part-b.md`:**
  - what ran;
  - the agreement verdict, and every flag or status change explained;
  - waves and stepping ms per period per experiment, from the timing JSON;
  - the xl smoke run.

  Then update the README.

- [ ] **Step 6: Run the suite.** Expected: all pass.

- [ ] **Step 7: Commit** `flamegpu: Part B validation - combat against Python`.
