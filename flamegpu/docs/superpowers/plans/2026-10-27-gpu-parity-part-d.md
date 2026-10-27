# Every Rule on the GPU, Part D: Chapter V (Disease), and Part C's Deferred Minors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Python's Chapter V on the GPU: immune systems, the master disease list, rule E (transmission, then the
immune response), the disease fee, and `disease_metrics`. The target is agreement with Python on V-1, V-2, VI-1 and
VAR-inttrade/VI-1. After this part every field of Python's `Config` runs on the GPU. The part also fixes the four
minors Part C deferred.

**Architecture:**
- **Disease puts a run on the turns path.** `turns_on()` adds `disease_list > 0` (spec section 1). E's partners are the
  four sites around the agent, which every footprint already holds, so the scheduler is unchanged.
- **The state is bits and ids.**
  - Immune genotype and phenotype are `uint64_t`, bit i holding Python's list element i.
  - The master list lives in environment arrays: each disease's bits and length.
  - An agent's active diseases are an ordered list of canonical ids: the lowest master index with the same bits and
    length. "Already carrying it" and `diseases_circulating` then compare strings, as Python's tuples do.
- **One implementation of the string rules.** `disease.h` holds `nearest_substring`, `is_immune` and `immune_step`,
  `__host__ __device__`, for the founders' infections on the host and rule E on the device.
- **The fee** (`sugar_burn = metabolism + disease_fee · diseases`) is used wherever Python uses `sugar_burn`:
  - metabolism and consumption pollution;
  - credit's income;
  - the welfare score in movement, from the start-of-period count (difference 3);
  - the welfare and MRS in trade, from the current count.
- **New infections** are counted per period by an integer atomic, which is deterministic, and reported like the trade
  totals.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), CUB (shipped with CUDA), pytest, the Python bridge in
`flamegpu/bridge/`.

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-full-parity-design.md`: Part D of "The work, in parts", and
sections 1, 2, 4 ("Disease E"), 5 and 7. The Part C plan (`2026-10-26-gpu-parity-part-c.md`) describes the spice,
trade and credit code this part extends, and its ledger's final review lists the four minors. The Python rules are in
`sugarscape/rules/disease.py`, `sugarscape/model.py` (`__init__`, `_spawn_at`, `step`), `sugarscape/rules/sex.py`
(the child's genotype), `sugarscape/agent.py` (`sugar_burn`) and `sugarscape/stats.py` (`disease_metrics`). Julia's
`julia/src/rules/disease.jl` is the same bit-field port, and a useful cross-check. Each GPU function names the Python
function it follows line for line.

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`, seatbelts on, used by pytest) and `scripts\build.cmd build-fast OFF`. Run
  every command from `flamegpu/`. After each build, grep the build log for `#2001` (host-only functions called from
  device code; Part C's `std::isinf` lesson).
- **The suite** is `.venv\Scripts\python -m pytest tests -q`. It needs the GPU to itself: timings taken while another
  program uses the GPU are not comparable.
- **Context7** before FLAME GPU (`/websites/flamegpu`) or CUB code is written. Each task names its lookups.
- **No change to Chapter II or Parts A–C outputs:**
  - every new draw is gated by `disease_list > 0`, as in Python;
  - without disease, `sugar_burn` is the metabolism exactly, so sugar, pollution and income are unchanged;
  - the disease columns keep today's values (0 or NaN for nobody, then 0, 0);
  - the goldens and every existing test pass. `GPU_FINGERPRINT` stays `gpu-phase3`.
- **No nondeterminism:** a seed gives the same bytes every run, in waves and under `--serial-turns`. The new-infection
  count is an integer atomic, which is deterministic.
- **Limits** (spec section 5), each checked at setup with exit 2 and a message naming it:
  - `immune_length` at most `MAX_IMMUNE_BITS = 64`;
  - `disease_list` at most `MAX_DISEASES = 64`;
  - `--version` prints `max_immune_bits = 64` and `max_diseases = 64`.
  - An agent carries each canonical disease at most once, so its list never exceeds `MAX_DISEASES`. No further limit.
- **Nothing refused after Part D.** `bridge.config_cfg.unsupported_features` stays as the guard for any field Python
  adds later (spec section 7).
- **Existing tests:** this plan changes these existing tests and helpers:
  - the refusal-boundary tests, which can no longer name a disease field: `test_cli.py`
    (`test_unsupported_feature_key_is_rejected`; `test_later_parts_still_refused` is removed) and `test_bridge.py`
    (`test_unsupported_lists_features`, `test_any_other_field_off_default_is_refused`);
  - `tests/gpu.py` and `tests/reference.py`, which gain the disease columns and the test master list;
  - `test_cli.py::test_version`, which gains the two limits.

  No assertion about behaviour is weakened. Approving this plan approves these changes.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings this plan makes against the spec

Each is recorded in the ledger when its task is reached.

- **D1: Two test-only options for the master list.**
  - `--disease-list PATH` replaces the drawn master list with the file's bit strings.
  - `--dump-diseases PATH` writes the list in use.
  - Why: Python and the GPU draw different lists from their own streams. A test that compares holdings must give
    both the same list, and a test of the draws must see the GPU's.
  - Cost if wrong: two test-only command-line options, like Part C's `--dump-order`.
- **D2: `--init` with disease on needs every agent's immune string.**
  - An `--init` agent without `immune` is refused (exit 2). So are disease columns with `disease_list = 0`, and an
    agent given two indices of one string, which Python's `infect` could never produce.
  - `diseases_per_agent` doesn't infect `--init` agents. Their diseases are the column's, as the test harness's
    Python model holds them.
  - Cost if wrong: none to experiments, which never use `--init`.
- **D3: A test-only `--loan-capacity N`** sets the loan book's capacity (default 2 × cells), so the book's real
  capacity can be tested on a small world.
  - Cost if wrong: one test-only option, like `--uid-capacity`.
- **D4: The owed loop's guard has no failing test.**
  - `seek_credit` skips a start-of-period loan whose lender row isn't found, as `lender_sites` does.
  - No run can reach that state: `rebuild_loans` and the ledger drop every loan with a dead party. So no test can
    fail before the fix. It is verified by the suite and the final review.
  - Cost if wrong: none.
- **D5: The bridge guard is tested with a made-up field.** No `Config` field is left unread, so the tests derive a
  `Config` subclass with a `future_rule` field.
  - Cost if wrong: none.

## Review Focus

1. **Equal disease strings under different master indices.**
   - A neighbour already carrying the same string under another index is not infected.
   - `diseases_circulating` counts the string once.

   Pinned by `test_transmission_matches_python[duplicate]` (Task 3) and `test_disease_metrics_t0_match_python`
   (Task 2).
2. **The fee wherever Python burns sugar:**
   - metabolism, consumption pollution and starvation;
   - credit's income;
   - welfare in movement (start of period) and in trade (now).

   Pinned by `test_disease_fee_matches_python[plain|polluted|welfare]`, `test_fee_starvation_matches_python`,
   `test_credit_income_counts_fee` and `test_trade_pairs_match_python[diseased]` (Task 3).
3. **A newborn infected in its birth period.** It keeps the disease through `spawn_newborns`, and has no immune
   response until its first turn. Pinned by `test_newborn_infected_in_birth_period` (Task 3).
4. **Training several diseases in one period**, in infection order:
   - one cleared mid-list;
   - the leftmost of tied windows;
   - training on a later disease changing the window an earlier one uses next period.

   Pinned by `test_immune_response_matches_python` (Task 3).
5. **Reaching the true limits.** A book of exactly its capacity settles and re-originates; a lender with more than 32
   heirs still exits 5, while a non-lender with 33 children dies cleanly. Pinned by Task 4's tests.

---

### Task 1: Chapter V configuration fields

**Files:**
- Modify: `src/config.h`, `src/config.cu`:
  - the fields;
  - parsing, `validate`, `print_config`;
  - `UNSUPPORTED` keeps only `sugar_map`;
  - `KNOWN` gains the keys.
- Modify: `src/main.cu` (the interim refusal of runs), `bridge/config_cfg.py` (`FIELDS`), `tests/gpu.py`
  (`DEFAULT_CFG`), `tests/reference.py` (`config_from_cfg`)
- Test: `tests/test_cli.py`, `tests/test_bridge.py`

**Interfaces:**
- **Produces, `RunConfig` fields**, at Python's defaults:
  ```cpp
  int disease_list = 0;          // master list size (p.147); 0 = no disease
  int diseases_per_agent = 0;    // distinct diseases offered to each founder
  IntRange disease_length{1, 10};
  int immune_length = 50;
  double disease_fee = 1.0;      // extra sugar burned per active disease (p.143)
  ```
  - `bool disease() const { return disease_list > 0; }`.
  - `turns_on()` adds `|| disease()`.
  - `constexpr int MAX_IMMUNE_BITS = 64; constexpr int MAX_DISEASES = 64;`.
- **Produces, run.cfg:** `disease_list = n`, `diseases_per_agent = n`, `disease_length = lo,hi`, `immune_length = n`,
  `disease_fee = x`. `print_config` prints them in that order, after `credit`.
- **Produces, `validate`,** with Python's `Config.__post_init__` messages:
  - `disease_list and diseases_per_agent must be >= 0`;
  - `cannot offer K distinct diseases from a list of N`;
  - `disease_length lo,hi must be a range starting at >= 1`;
  - `diseases must be shorter than immune systems (p.141)` (when `disease_length.hi >= immune_length`);
  - `disease_fee must be >= 0, not X`.
  - The GPU's limits, checked only with disease on (Python accepts any `immune_length` without disease):
    `immune_length N: the GPU holds at most 64 immune bits` and `disease_list N: the GPU holds at most 64 diseases`.
- **Produces, for the interim** (Part C's Task 1 ruling places it the same way): `main` refuses a run with disease
  on, after `--print-config`, with `disease: not on the GPU yet` (exit 2). Task 2 removes it.
- **Produces:** `config_cfg.FIELDS` gains the five names after `credit`. `config_from_cfg` maps them to `int`, a tuple
  and a `float`.

- [ ] **Step 1: Write the failing tests.**
  - **`test_cli.py`:**
    - `test_chapter5_fields_round_trip`: every new key, set away from its default, comes back from
      `--print-config` as given.
    - `test_chapter5_validated[negative|too-many|length0|too-long|fee|immune65|list65]`: exit 2, with the message's
      distinctive words. For example, `too-long` is `disease_length = 1,50` with `immune_length = 50`.
    - `test_unsupported_feature_key_is_rejected` uses `sugar_map = sugar-map.txt` and expects `sugar_map`.
    - Delete `test_later_parts_still_refused`.
    - `test_disease_run_refused_for_now`: `disease_list = 1` with steps 1 exits 2 with `not on the GPU yet`. Task 2
      deletes this test.
  - **`test_bridge.py`:**
    - **`test_unsupported_lists_features`** (D5):
      ```python
      Future = make_dataclass("Future", [("future_rule", bool, field(default=False))], bases=(Config,), frozen=True)
      ```
      `unsupported_features(Future(future_rule=True)) == ["future_rule"]`, and `config_to_cfg` raises
      `UnsupportedFeature` naming it.
    - **`test_any_other_field_off_default_is_refused`:** the same `Future` on II-4's fields. Only `future_rule` is
      listed; `Future()` lists nothing.
    - **`test_part_d_configs_convert`:**
      - V-2's run.cfg holds `disease_list = 25` and `diseases_per_agent = 10`;
      - `unsupported_features` is empty for every `PART_D_IDS` id (`V-1`, `V-2`, `VI-1`, `VAR-inttrade/VI-1`).
    - **`test_every_config_experiment_converts`:** every registered experiment whose config is a `Config` has no
      unsupported feature.

- [ ] **Step 2: Run them.** Expected: FAIL (unknown keys; `disease_list` unsupported in the bridge).

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: Chapter V config fields through run.cfg and the bridge`.

### Task 2: Disease state: the master list, immune systems, founders' infections

**Files:**
- Create: `src/disease.h`: `__host__ __device__`, line for line with Python's `nearest_substring`, `is_immune` and
  `immune_step`, using the same `WELFARE_FN`-style macro as `welfare.h`.
- Modify: `src/model.cu`:
  - citizen variables `immune_genotype`, `immune` (`uint64_t`), `n_diseases` (`unsigned int`) and `diseases`, an
    array of `MAX_DISEASES` (`uint8_t` if FLAME GPU supports it for array variables, else `unsigned int`);
  - environment `disease` (0/1), `immune_length`, `disease_fee` (double), and arrays `disease_bits`
    (`uint64_t[MAX_DISEASES]`) and `disease_len` (`unsigned int[MAX_DISEASES]`), in the main, movement and turns
    models.
- Modify: `src/host_state.h`, `src/host_state.cu`:
  - `RunState` gains `disease_bits`, `disease_len`, `disease_canon`;
  - the master list, the founders' draws and infections;
  - `--init`'s disease columns.
- Modify: `src/rules.cuh` (`output_newcomer` draws the immune genotype; `init_citizen_out` covers the new variables),
  `src/sex.cuh` (the child's genotype), `src/store.h`, `src/store.cu` (rows `immune_genotype`, `immune`, `n_diseases`,
  `diseases`), `src/turns.cuh` (`publish`, `absorb`, `spawn_newborns` copy them)
- Modify: `src/landscape_io.h`, `src/landscape_io.cu` (`InitAgent` gains `immune_genotype`, `immune` and `diseases`;
  `check_init_agents` applies D2)
- Modify: `src/main.cu` (`--disease-list`, `--dump-diseases`, `--version`'s limits; remove the interim refusal),
  `src/checks.cu` (dump columns; invariants), `src/metrics.h`, `src/metrics.cu` (four state columns)
- Modify: `tests/gpu.py`, `tests/reference.py`
- Test: create `tests/test_disease.py`; `tests/test_cli.py` (`test_version`; delete `test_disease_run_refused_for_now`)

**Interfaces:**
- **Produces, `disease.h`:**
  - `struct Nearest { int start, distance; };`
  - `Nearest nearest_substring(uint64_t immune, int immune_length, uint64_t bits, int len)`: the leftmost window of
    least Hamming distance, stopping at distance 0, as Python.
  - `bool is_immune(uint64_t immune, int immune_length, uint64_t bits, int len)`.
  - `bool immune_step(uint64_t& immune, int immune_length, uint64_t bits, int len)`: flips the lowest differing bit of
    the nearest window, and returns whether the disease now matches (distance was 0 or 1).
- **Produces, the master list, on the host, in Python's order:** drawn before the founders' sites.
  - For each of the `disease_list` entries: its length from `disease_length`, then its bits, as `random_tags(rng, len,
    "")` draws them.
  - `disease_canon[i]` is the lowest j with equal bits and length.
  - `--disease-list PATH` replaces the draws: one 0/1 string per line, bit 0 first.
    - Exit 2 if the line count isn't `disease_list`, or if a string's length is below 1 or at least
      `immune_length`.
- **Produces, draws in Python's `_spawn_at` order**, after Chapter IV's, only with disease on:
  - **Founders (host) and newcomers (`output_newcomer`, `random_bits`):** `immune_genotype` = `immune_length` random
    bits; `immune = immune_genotype`; no diseases.
  - **The child (`mate`), after the spice draws:** the genotype crosses the parents' genotypes as the tags are
    crossed; the phenotype copies it; no diseases.
- **Produces, founders' infections, on the host:**
  - after every founder is placed, and before the founder ages are drawn;
  - founders in placement order, each offered `diseases_per_agent` distinct master indices by partial Fisher–Yates
    (Python's `rng.choice(..., replace=False)`), in pick order;
  - each is infected with the canonical id unless it carries it or `is_immune` (Python's `infect`).
- **Produces, `--init`** (D2): optional columns:
  - `immune_genotype` and `immune`: 0/1 strings of `immune_length`; the genotype defaults to the immune string;
  - `diseases`: master indices joined by `|`, in infection order, stored as canonical ids.
- **Produces, dumps:**
  - `--dump-agents` appends `immune_genotype,immune,diseases`: the two strings, empty without disease, and the
    canonical ids joined by `|`.
  - `--dump-diseases PATH` writes `index,canonical,bits` per master entry at setup.
- **Produces, test helpers:**
  - `run_gpu(..., diseases: list[str] | None = None)` writes and passes `--disease-list`.
  - `reference.build_python`, `run_python`, `run_python_in_order` and `python_metric_rows` take the same
    `diseases`. They set `model.disease_list` to those tuples, and each agent's `immune_genotype`, `immune`,
    `disease_fee = config.disease_fee` and `diseases`.
  - `python_dump` writes the three columns. Python's diseases are written as `model.disease_list.index(d)`, the
    lowest equal index, so they are canonical too.
  - `INIT_OPTIONAL` and `TEXT_COLUMNS` gain the three columns.
  - `compare_dumps` compares `immune` and `diseases` exactly wherever both dumps carry them.
- **Produces, `--check`:** with disease on, every agent:
  - has `n_diseases <= disease_list`;
  - carries distinct ids;
  - carries ids that are canonical (`disease_canon[id] == id`).
- **Produces, metrics:**
  - `AgentColumns` gains `n_diseases` and `diseases`.
  - `mean_diseases` is the mean of the counts, `sd_diseases` `np.std` (population), `fraction_sick` the share with
    a count above 0; all three are NaN for nobody.
  - `diseases_circulating` is the number of distinct canonical ids carried.
  - Without disease these give today's values exactly.
- **Produces, `--version`:** `max_immune_bits = 64`, `max_diseases = 64`.
- **Not yet:** the turn ignores disease until Task 3: no fee, no E. Ledger it.

- [ ] **Step 1: Context7.** `/websites/flamegpu`:
  - array agent variables, and whether `uint8_t` is a supported variable type;
  - environment property arrays of `uint64_t`, read in an agent function by index.

- [ ] **Step 2: Write the failing tests** in `test_disease.py`, on `test_parity.py`'s `CAPACITY` unless stated.
  - **`test_master_list_draws`:** `disease_list = 20`, `disease_length = 1,2`, `immune_length = 10`, steps 0, with
    `--dump-diseases`. Twenty entries; every length is 1 or 2; every `canonical` is the lowest index with equal bits;
    at least one entry is a duplicate. The 2 + 4 strings make one certain.
  - **`test_founders_infected[none|four]`:** 400 founders, `disease_list = 10`, `immune_length = 50`, dumps at t = 0
    with `--dump-diseases`. Every agent:
    - has a 50-bit `immune` equal to its genotype;
    - carries at most `diseases_per_agent` distinct canonical ids, none of them one it is immune to (checked with
      Python's `disease.is_immune` on the dumped list);
    - **none:** with `diseases_per_agent = 0`, no agent carries a disease;
    - **four:** with `diseases_per_agent = 4`, some agent carries one.
  - **`test_newcomers_draw_immune`:** `replacement = true`, `max_age = 1,1`, `disease_list = 10`,
    `diseases_per_agent = 4`. At t = 3 every agent is a newcomer with a 50-bit immune string equal to its genotype and
    no diseases. The strings aren't all equal.
  - **`test_child_genotype_crossed`:** `test_sex.py`'s `PAIR` with `BOOK`, `disease_list = 1`, `immune_length = 10`
    and `--disease-list` `["11"]`. Nobody carries the disease. The blockers' genotypes and immune strings are all 0.
    - F's genotype is `0000011111` and its immune string `1111111111`.
    - M's genotype is `0000000000` and its immune string `1111100000`.
    - After 1 step the child's genotype has `00000` in bits 0–4, where the genotypes agree; crossing the immune
      strings would give `11111` there.
    - Its immune string equals its genotype, and it carries nothing.
  - **`test_disease_dump_round_trip`:**
    - **agents:** four far-apart agents with all-0 immune strings (`immune_length = 12`), carrying `"0|3"`, `""`,
      `"2"` and `"3|1"`;
    - **master list:** `["101", "0110", "101", "1"]`, so index 2 is index 0's duplicate;
    - **assert,** dumped at t = 0:
      - the GPU's and Python's (`run_python`, 0 steps) `immune_genotype`, `immune` and `diseases` columns are equal;
      - the third agent's diseases read `0`, the canonical id, on both sides.
  - **`test_init_disease_refused[columns-without-disease|no-immune|duplicate|list-count|list-too-long]`:** exit 2,
    naming the line or the file. `duplicate` gives one agent `"0|2"`: two ids of one string.
  - **`test_disease_metrics_t0_match_python`:** `test_disease_dump_round_trip`'s agents. The t = 0 row's four state
    columns match `python_metric_rows`. `diseases_circulating` is 3: indices 0 and 2 are one string.
  - **`test_disease_check`:** V-2 from the registry (`test_spice._registry`), 5 steps with `--check`. Exit 0.
  - **`test_disease_runs_on_turns`:** V-1, 1 step with `--timing`. `waves_mean > 0`.
  - **`test_cli.py`:** `test_version` asserts `max_immune_bits = 64` and `max_diseases = 64`.

- [ ] **Step 3: Run them.** Expected: FAIL (`disease: not on the GPU yet`; unknown options).

- [ ] **Step 4: Implement.**

- [ ] **Step 5: Run them, then the suite.** Expected: all pass, the goldens included.

- [ ] **Step 6: Commit** `flamegpu: disease state - the master list, immune systems, founders' infections`.

### Task 3: Rule E in the turn, the disease fee, new infections

**Files:**
- Create: `src/disease.cuh`:
  - `sugar_burn(const Store&, unsigned int row, double fee) -> double`;
  - Python's `infect`, `transmit` and `immune_response`.
- Modify: `src/turn.cuh`:
  - burn `sugar_burn` (sugar, consumption pollution, and credit's `harvest − burn`);
  - E after L.
- Modify: `src/trade.cuh` (welfare and MRS with `sugar_burn`), `src/movement.cuh` (`propose`'s welfare with the
  start-of-period `n_diseases`), `src/model.cu` (the movement sub-model's citizen gains `n_diseases`),
  `src/footprint.cuh` (touch point 14 in the comment)
- Modify: `src/store.h`, `src/store.cu` (counter `infections`; `StoreHost::take_infections()`), `src/turns.cuh` (host
  function `total_infections` after `total_trades`), `src/host_state.h` (`RunState::new_infections`),
  `src/metrics.cu` (`new_infections`)
- Test: `tests/test_disease.py`, `tests/test_trade.py`, `tests/test_credit.py`

**Interfaces:**
- **Consumes:** Task 2's rows, environment and `disease.h`.
- **Produces, `sugar_burn`:** `metabolism + fee · n_diseases`, in double. With no diseases it is the metabolism
  exactly.
- **Produces, the turn:**
  - metabolism takes `sugar_burn` off the sugar;
  - consumption pollution is `pollution_beta · (float) burn`;
  - starvation is unchanged in form;
  - `seek_credit` gets `harvest − burn`.
- **Produces, E after L** (Python's `transmit`, then `immune_response`), only when the agent carries a disease:
  - **the neighbours:** the occupants of the four sites around it now, in VON_NEUMANN order, newborns included (touch
    point 14), shuffled by Fisher–Yates with `draw_between` as `trade_with_neighbors` shuffles them;
  - **for each neighbour:** a disease is drawn from the agent's list with `draw_between(0, n − 1)`, even if the
    neighbour can't take it. `infect` appends the canonical id unless the neighbour carries it or `is_immune`. Each
    infection adds 1 to the store's `infections`.
  - **the immune response:** the agent's own diseases in list order, each `immune_step`-ped. Those now matched leave
    the list, which keeps its order.
- **Produces, the welfare score:**
  - in movement, `welfare(metabolism + fee · n_diseases, ...)` with the citizen's start-of-period count;
  - in trade, `welfare` and `mrs` with `sugar_burn` of each row now.
- **Produces, `new_infections`:**
  - `StoreHost::take_infections()` returns the period's count and clears it;
  - `total_infections` stores it in `RunState::new_infections` for the metrics row;
  - 0 at t = 0, as Python's empty `infection_log`.

- [ ] **Step 1: Write the failing tests.** "Agrees with Python" means `compare_dumps(gpu, py, pollution=True) == []`,
  with the immune strings and the diseases included.
  - **`test_disease.py`:**
    - **`test_disease_fee_matches_python[plain|polluted|welfare]`:**
      - **the agents:** `test_spice._movers(sugar=40.0)`, four far-apart agents, `immune_length = 12`, carrying 0, 1,
        2 and 3 diseases from `["111", "0110", "1", "10101"]`, with immune strings all 0. Nobody meets, so the order
        can't matter. `"1"` is cleared in period 1, the others later.
      - **run:** 4 steps, against `run_python`.
      - **polluted:** `pollution = 1,1` and `diffusion_period = 1`.
      - **welfare:** `spice = true`, every agent with spice 30 and spice metabolism 2. Its movement is scored with the
        fee.
    - **`test_fee_starvation_matches_python`:** 1 step over 10 seeds, with Python stepped in the GPU's order
      (`run_python_in_order`). A 7×7 zero-capacity world, vision 0, `immune_length = 12`, master list
      `["111", "0110"]`:
      - agent S at (3,3) has sugar 3, metabolism 1, both diseases (burn 3) and an all-0 immune string, so it dies in
        its turn;
      - agent N at (3,4) has sugar 50, metabolism 0, no disease, and immune `111011000000`, immune to both;
      - for each seed: the dumps agree, N's `neighbors` matches Python's, and the population matches;
      - both orders occur over the seeds.
    - **`test_immune_response_matches_python`:**
      - one agent, `immune_length = 12`, immune `000000000000`, carrying `["111", "1", "0110"]` in that order;
      - after each of steps 1–4 (`run_gpu` with `dump_at`), the dump agrees with `run_python` for the same steps;
      - by step 4 the list is shorter than at step 1.
    - **`test_transmission_matches_python[susceptible|immune|duplicate]`:** 1 step over 5 seeds, Python stepped in
      the GPU's order. Both orders occur among each run's pairs.
      - **layout:** 15 pairs at `(4·(i % 5), 4·(i // 5))` and the site east of it, on a zero-capacity 20×20 map,
        vision 0, metabolism 0, sugar 50, `immune_length = 12`. The master list is `["0110", "0110", "111"]`.
      - **the source** carries one disease, index 0, so the choice is forced. Its partner carries nothing, except
        under `duplicate`.
      - **susceptible:** the partner's immune string is all 0.
      - **immune:** the partner's immune string contains `0110`.
      - **duplicate:** the partner carries index 1, the same string.
      - **assert:** the dumps agree, and the t = 1 row's `new_infections` and the four state columns match Python's.
        `new_infections` is 15, 0 and 0 per case: the source's turn always infects a susceptible partner, whichever
        turn comes first.
    - **`test_newborn_infected_in_birth_period`:** 1 step over 10 seeds, Python stepped in the GPU's order.
      - **layout:** `test_sex.py`'s `PAIR` with `BOOK`, `disease_list = 1`, `--disease-list ["11"]`,
        `immune_length = 10`.
      - **the parents:** genotypes `0000000000`, immune strings `1100000000`, so they are immune and the child isn't.
      - **the carrier:** the blocker at (6,6), next to the child's only site (5,6), carries the disease with immune
        `0000000000`. The other blockers' immune strings contain `11`.
      - **assert:** the dumps agree; the child carries the disease in exactly the seeds where the blocker's turn
        follows the mating; and both outcomes occur.
    - **`test_serial_equivalence_disease[V-2|VI-1]`:** 20 steps, waves byte-identical to `--serial-turns`
      (`test_sex._files`; VI-1's loans dump included). Also `--check` exits 0 for each.
    - **`test_disease_metrics_match_python`:** `test_transmission_matches_python[susceptible]`'s seed 0, rows t = 0
      and 1, all five disease columns.
  - **`test_trade.py`:** `test_trade_pairs_match_python[diseased]`: the `exact` case with `disease_list = 1`,
    `--disease-list ["111"]` and `immune_length = 10`.
    - Every agent carries it, so none is infected and the draws don't matter. Every immune string is all 0, at
      distance 3, so the disease stays for both steps.
    - The prices differ from `exact`'s because the burn is 1 higher.
  - **`test_credit.py`:** `test_credit_income_counts_fee`: `test_loan_and_repayment_matches_python` at t = 1, with
    `disease_list = 1`, `--disease-list ["111"]`, `immune_length = 10`.
    - The borrower carries the disease with an all-0 immune string. Its income is 1 lower, so its due limit is 10
      lower.
    - The lender is immune (`1110000000`), so nothing is transmitted.
    - Sugar and the book agree with Python.

- [ ] **Step 2: Run them.** Expected: FAIL. No fee is burned, nobody is infected, and immune strings never change.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them, then the suite.** Expected: all pass. Part C's trade and credit tests are the guard that
  `sugar_burn` without disease is the metabolism.

- [ ] **Step 5: Commit** `flamegpu: rule E in the turn, the disease fee, new infections`.

### Task 4: Part C's deferred minors

**Files:**
- Modify: `src/loans.h`, `src/loans.cu`, `src/book.cuh`:
  - a staging area of `capacity` entries, apart from the book;
  - `book_on_death` and the ledger's re-originations build there;
  - `LoanBook(cells, rows, capacity)`.
- Modify: `src/main.cu` (`--loan-capacity N`, D3), `src/model.cu` or `src/host_state.cu` (wherever `LoanBook` is
  made)
- Modify: `src/credit.cuh`:
  - the owed loop skips `lr < 0` (D4);
  - `credit_on_death` returns at once unless the dying uid lends in the book.
- Modify: `src/store.cu` (`k_fix_loans` uses `PROVISIONAL_PARENT` and its complement)
- Test: `tests/test_credit.py`

**Interfaces:**
- **Produces:** the book holds `capacity` loans, as `--version`'s `loans_per_cell = 2` says.
  - `book_put` on the book checks against `capacity`; staging has its own `capacity`.
  - The message stays `loan book capacity N exceeded`, with N the capacity in use.
- **Produces:** `credit_on_death(s, row)` calls `heirs_in_order` only if some book entry's lender is the row's uid.
- **Produces:** `--loan-capacity N` (N ≥ 1; default 2 × cells), listed in `--help` as a test option.

- [ ] **Step 1: Write the failing tests** in `test_credit.py`.
  - **`test_full_book_reoriginates`:** `test_partial_repayment_reoriginates`, with `--loan-capacity 1`. Exit 0, and
    agreement with Python at t = 11. Today the re-origination is staged at index 1 and exits 5.
  - **`test_book_over_capacity_exits_5`:**
    - two lenders, `_lender(sugar=30.0)` and `_lender(x=2, y=4, sugar=30.0)`, beside `_borrower()`;
    - Python makes 2 loans in period 1 (assert it);
    - with `--loan-capacity 1` the GPU exits 5, and stderr contains `loan book capacity 1 exceeded`;
    - without the option it exits 0 and agrees with Python.
  - **`test_many_children_non_lender_starves`:**
    - `sex = true`, `inheritance = true`, `credit = 10,10.0`, a 24×24 zero-capacity world, 1 step;
    - parent P at (3,3): male, age 30, fertility 12–50, sugar 1, metabolism 2;
    - 33 children at `(2·(i % 11), 12 + 2·(i // 11))`: female, age 0, fertility 12–40, sugar 10, metabolism 0,
      `parent_a` = P's index.
    - Exit 0, and 33 agents remain. Today `heirs_in_order` exits 5.
  - **`test_many_children_lender_exits_5`:**
    - the same children, with P age 70, fertility 12–50, sugar 100 and metabolism 60;
    - borrower `_borrower()` at (3,4), on a site of capacity 10;
    - 2 steps. P lends to B in period 1 and starves by period 2 in either order.
    - Exit 5, and stderr contains `more than 32 heirs`.

- [ ] **Step 2: Run them.** Expected:
  - FAIL: `test_full_book_reoriginates` (exit 5), `test_book_over_capacity_exits_5` (unknown option),
    `test_many_children_non_lender_starves` (exit 5);
  - PASS: `test_many_children_lender_exits_5`, which pins the limit where it still applies.

- [ ] **Step 3: Implement** the staging area, `--loan-capacity`, and the `credit_on_death` check. Also add the owed
  loop's guard (D4, no test) and the `k_fix_loans` constants. The latter is a refactor, which
  `test_newborn_lender_uids` covers.

- [ ] **Step 4: Run them, then the suite.** Expected: all pass.

- [ ] **Step 5: Commit** `flamegpu: Part C's minors - the book's full capacity, heirs only for lenders, guards`.

### Task 5: Part D's experiments against Python

**Files:**
- Create: `docs/validation/chapter5-part-d.md`, `docs/validation/agreement-part-d.md`
- Modify: `README.md`:
  - Chapter V is on the GPU, so every `Config` rule now is;
  - the immune and disease-list limits;
  - the test options `--disease-list`, `--dump-diseases` and `--loan-capacity`.

- [ ] **Step 1: Run the experiments** on `build\`: `.venv\Scripts\python -m bridge.gpu_run <id> --jobs 4` for `V-1`,
  `V-2`, `VI-1` and `VAR-inttrade/VI-1`. Expected: every run exits 0. Ledger the wall time.

- [ ] **Step 2: Agreement.** `.venv\Scripts\python -m bridge.agreement_report V-1 V-2 VI-1 VAR-inttrade/VI-1 --python C:\Projects\Sugarscape2026\results --out docs/validation/agreement-part-d.md`.
  - Expected: 0 flagged. VI-1 spice runs carry difference 3, which Part C's harness found shifts nothing at q = 0.01.
  - Each flag gets superpowers:systematic-debugging, then a fix (back to the owning task's tests) or a written
    explanation with its evidence: a harness run of the same experiment, or more seeds.

- [ ] **Step 3: Book targets.** `.venv\Scripts\python -m bridge.gpu_report --chapter V`, then `--chapter VI`. Every
  status change against Python is explained in the validation doc, with its seed-level p.

- [ ] **Step 4: xl smoke runs** on `build-fast\`, as Part C ran them: V-2 and VI-1, 1 seed, 5 steps each.
  - Ledger the waves and the stepping per period.
  - If a buffer can't be allocated, record the exit and the message as Part F's work.

- [ ] **Step 5: Write `docs/validation/chapter5-part-d.md`:**
  - what ran;
  - the agreement verdict, and every flag or status change explained;
  - waves and stepping ms per period per experiment, from the timing JSON;
  - the xl smoke runs.

  Then update the README.

- [ ] **Step 6: Run the suite.** Expected: all pass.

- [ ] **Step 7: Commit** `flamegpu: Part D validation - Chapter V against Python`.
