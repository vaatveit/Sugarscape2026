# VI-1 with combat by cultural distance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Julia-only experiment `VI-1-distance`: VI-1-combat in which whether an agent fights another, and whether it
fears another, is a weighted draw on cultural distance, p = 0.5 × (tags that differ ÷ tag length), with no part played by
the tribe label.

**Architecture:** One function, `hostile!(m, a, other)`, replaces the four tribe tests (the occupant test in
`combat_move!` and `xxl_combat_move!`, the watcher test in `vulnerable` and `disc_vulnerable`). With
`combat_hostility == 0` it is the old label test and draws nothing, so every existing run is byte-identical. Above 0 it
draws once per pair per move, cached in the model and emptied at the start of each combat move. Kills are logged in
`take_loot!`; the combat observer collects them and the combat study writes `seed<k>-kills.csv` for distance runs.

**Tech Stack:** Julia, module `Sugarscape` in `julia/`, Test stdlib.

**Spec:** `docs/superpowers/specs/2026-11-09-vi1-distance-design.md`

## Global Constraints

- **Nothing that ran before changes.** With `combat_hostility = 0` (the default), III-9, III-11, III-12, III-13, III-14,
  VI-1 and VI-1-combat give byte-identical CSV contents in the book's world, xl and today's xxl. Fingerprint files carry a
  code hash and may change.
- **The rule:** p(a, b) = h × d(a, b) / L, d the number of differing tags (`count_ones(a.tags ⊻ b.tags)`), L =
  `a.ntags`, h = `m.config.combat_hostility`. A draw comes up when `rand(m.rng) < p`.
- **No tribe test anywhere in the distance path** (h > 0). The label stays in the readings, tribal blocks and same-tribe
  replacement.
- **Fight:** an occupant is a candidate only if no wealthier than the attacker (`combat_wealth`) **and** `hostile!`; the
  draw is made only after the wealth test passes.
- **Fear:** a watcher makes a site vulnerable only if wealthier than the attacker would be after taking it **and**
  `hostile!` (the draw after the wealth test).
- **One draw per pair per move:** the first `hostile!(m, a, other)` in a move draws; later calls in the same move return
  the same answer. The cache is emptied at the start of every `combat_move!` call (which dispatches to the xxl move).
- **`combat_hostility::Float64 = 0.0`** in `Config`; valid in [0, 1]; above 0 it needs `combat_alpha !== nothing`
  (combat already needs tags).
- **Experiment id `VI-1-distance`:** VI-1-combat with `combat_hostility = 0.5` in both configs; its fingerprints are
  VI-1-combat's plus the line `variant: VI-1-distance combat_hostility=0.5 (fight and fear drawn on cultural distance)\n`.
- **Kills file** `seed<k>-kills.csv`, header `t,distance,same_label`, one row per kill, `t` the period whose combat row
  counts the death; written only when the world's config has `combat_hostility > 0`, header only if no kills; written
  before `seed<k>.csv`; the seed-completeness check is unchanged.
- **No study run.** Suite runs and the dry run in Task 5 (a few periods, two seeds per world) are fine.
- **No change** to VI-1-combat's or VI-1's definitions, `XXL_DEFAULTS`, the scorecard, culture, the combat readings'
  columns, the combat report, the Python model or `julia/registry.toml`.
- **Suite:** `julia --project=julia -e 'using Pkg; Pkg.test()'` (about 36 min). One file:
  `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["<substring>"])'`; runtests.jl filters by substring.

## Review Focus

1. **A watcher seen from several candidate sites in one move** gets one answer: feared at all of them or at none. (An
   agent can't be both a possible victim and a feared watcher in one move: a victim is no wealthier than the attacker, a
   feared watcher is wealthier than the attacker after the gain.) Test in Task 2.
2. **Boundaries of h:** h = 0 is the label rule exactly; h = 1 with every tag different always fights and fears; h < 0,
   h > 1, and h > 0 without combat are rejected. Tests in Task 2.
3. **The cache must not leak between agents or periods:** a draw made in one agent's move must not answer another
   agent's move. Test in Task 2.
4. **The same seed gives the same run** under VI-1-distance (draws come only from `m.rng`). Test in Task 4.
5. **A kill row's distance and label are read before the victim dies** (tags at the moment of the kill), and the
   killer's tags are the attacker's. Test in Task 3.

---

### Task 1: Guard VI-1-combat before any rule change

**Files:**
- Modify: `julia/test/fixtures/vi1-combat-refs/make_refs.jl`
- Modify: `julia/test/test_vi1_combat_unchanged.jl`
- Create: `julia/test/fixtures/vi1-combat-refs/{book,xl,today}-VI-1-combat.csv`

**Interfaces:**
- Consumes: `run_combat_world(world, "VI-1-combat"; seeds=1, first_seed=0, periods=10, out, io)` (exists).
- Produces: 21 guard fixtures; the test loops over `(COMBAT_EXPS..., "VI-1", VI1_COMBAT_ID)`.

- [ ] **Step 1:** In `make_refs.jl` and `test_vi1_combat_unchanged.jl`, loop over `(COMBAT_EXPS..., "VI-1", VI1_COMBAT_ID)`
  (import `VI1_COMBAT_ID`); `ref_csv` already sends every id but VI-1 to `run_combat_world`. Update both header comments.
- [ ] **Step 2:** Write the three new fixtures from the current code (main `11633d1`, unchanged so far):
  `julia --project=julia julia/test/fixtures/vi1-combat-refs/make_refs.jl`. Expected: `git status` shows only the three
  new CSVs under fixtures (the 18 old ones unchanged — `git diff --stat` empty for them).
- [ ] **Step 3:** Run `Pkg.test(test_args=["vi1_combat_unchanged"])`. Expected: 42 passed (21 × 2). This guard has no red
  phase: it pins current behaviour.
- [ ] **Step 4: Commit** `julia: guard fixtures cover VI-1-combat before combat by distance`.

### Task 2: The distance draw in the book's move and retaliation check

**Files:**
- Modify: `julia/src/config.jl` (field after `combat_alpha`; checks next to the `combat_alpha` checks)
- Modify: `julia/src/model.jl` (`Model` field and its constructor)
- Modify: `julia/src/rules/combat.jl`
- Modify: `julia/src/Sugarscape.jl` (export `fight_chance`, `hostile!`)
- Test: `julia/test/test_combat_distance.jl`

**Interfaces:**
- Produces:
  - `Config.combat_hostility::Float64 = 0.0`.
  - `Model.hostile::Dict{Int,Bool}` — this move's answers by the other agent's id.
  - `fight_chance(h::Float64, a::Agent, b::Agent)::Float64` = `h * count_ones(a.tags ⊻ b.tags) / a.ntags`.
  - `hostile!(m::Model, a::Agent, other::Agent)::Bool`: with h == 0, `tribe(other) !== tribe(a)` (no draw, no cache);
    else the cached answer for `other.id`, or a fresh `rand(m.rng) < fight_chance(h, a, other)` stored in the cache.
  - `combat_move!` empties `m.hostile` first thing (before the xxl dispatch).

- [ ] **Step 1: Write the failing tests** in `test_combat_distance.jl`, on `tiny_model` worlds (as in
  `test_combat_spice.jl`: `tiny_model(zeros(Int, 12, 12); tag_length=5, combat_alpha=Inf, vision=(1, 4), kw...)`,
  `put_agent`, `tag!`):
  - `test_fight_chance`: tags 00000 vs 00000 → 0.0; 00000 vs 11111 with h = 0.5 → 0.5; 00000 vs 00111 with h = 0.5 → 0.3.
  - `test_same_label_far_apart_fights`: h = 1, attacker 00000, poorer occupant 00011 (both blue, d = 2, p = 0.4); over
    fresh models with seeds 1:500 the share attacked is within 0.4 ± 0.07. And a certain case: h = 1, occupant 11111
    (d = 5, p = 1) is always attacked.
  - `test_identical_tags_never_attacked`: h = 1, attacker and occupant 01010 (same tags), occupant poorer, 200 seeds:
    never attacked.
  - `test_identical_watcher_not_feared`: h = 1; a richer watcher with the attacker's tags in sight of the only target;
    the attack goes ahead. `test_distant_watcher_feared`: same with watcher tags all different from the attacker's; the
    target is spared.
  - `test_one_watcher_one_answer` (Review Focus 1): attacker at (1, 1), vision 4, h = 0.5; empty site (3, 1) with sugar 4
    and empty site (1, 3) with sugar 3; the only other agent, W, at (3, 3), all tags different from the attacker's and
    richer than the attacker plus 4, so it sees both sites (two steps up from (3, 1), two steps right from (1, 3)). Over
    seeds 1:300 the attacker ends at (3, 1) or stays at (1, 1), never at (1, 3): with one answer for W, if W is feared at
    (3, 1) it is feared at (1, 3) too. Both outcomes occur.
  - `test_cache_cleared_between_moves` (Review Focus 3): after one agent's move, `m.hostile` is emptied at the start of
    the next `combat_move!` (call it on a second agent and check the first agent's entries are gone).
  - `test_label_rule_at_zero`: h = 0; same-label occupant never attacked, other-label always (over a few seeds), and
    `m.hostile` stays empty.
  - `test_hostility_config` (Review Focus 2): `combat_hostility = -0.1` and `1.1` rejected; `0.5` without `combat_alpha`
    rejected; `1.0` with combat accepted.
- [ ] **Step 2:** Run `Pkg.test(test_args=["combat_distance"])`. Expected: FAIL (`combat_hostility` unknown).
- [ ] **Step 3:** Add the config field and checks, the model field, `fight_chance`, `hostile!`, and in `combat_move!`
  replace `tribe(occupant) !== mine && combat_wealth(occupant, spice) <= wealth` with the wealth test first, then
  `hostile!(m, a, occupant)`; in `vulnerable` replace `tribe(other) !== mine && combat_wealth(other, spice) > after` with
  `combat_wealth(other, spice) > after && hostile!(m, a, other)`. Drop the now-unused `mine`. Update the docstrings.
- [ ] **Step 4:** Run `["combat_distance"]`, then `["combat"]` and `["vi1_combat_unchanged"]`. Expected: all pass.
- [ ] **Step 5: Commit** `julia: combat by cultural distance in the book's move: fight and fear drawn on p = h d / L`.

### Task 3: The xxl move, and the kill log

**Files:**
- Modify: `julia/src/xxl/combat.jl`
- Modify: `julia/src/rules/combat.jl` (`take_loot!`), `julia/src/model.jl` (field, constructor, reset in `step!`)
- Modify: `julia/src/xxl/combat_readings.jl`
- Test: `julia/test/test_xxl_combat_distance.jl`

**Interfaces:**
- Consumes: `hostile!` (Task 2).
- Produces:
  - `Model.kill_log::Vector{NTuple{2,Int}}` — this period's kills as `(distance, same_label)`, emptied where
    `m.killed` is emptied in `step!`; `take_loot!` pushes `(count_ones(a.tags ⊻ victim.tags), tribe(a) === tribe(victim) ? 1 : 0)`
    before `die!` (both are 0-tag-safe: agents in combat always have tags).
  - `CombatReadings.kills::Vector{NTuple{3,Int}}` — `(t, distance, same_label)`, appended by `combat_period!` from
    `m.kill_log` with the period it is reading.
  - `kill_rows(r::CombatReadings) -> (header::Vector{String}, rows::Vector{Vector{Int}})`, header
    `["t", "distance", "same_label"]`.

- [ ] **Step 1: Write the failing tests** in `test_xxl_combat_distance.jl`, on a small world with xxl round vision and
  speed (as `test_xxl_combat_spice.jl` builds its worlds):
  - `test_xxl_identical_tags_never_attacked` and `test_xxl_distant_occupant_attacked` (h = 1, d = L, certain).
  - `test_xxl_distant_watcher_feared` and `test_xxl_identical_watcher_not_feared`.
  - `test_xxl_watcher_one_answer`: the xxl form of Task 2's `test_one_watcher_one_answer`, with two empty candidate
    sites within reach both inside one distant richer watcher's round vision: over seeds 1:300 the agent never takes the
    less valuable site.
  - `test_kill_log_row` (Review Focus 5): in the book's move with h = 1, attacker 00000 kills occupant 11111 (p = 1):
    `m.kill_log == [(5, 0)]`. With occupant 00011 (same label, p = 0.4), over seeds 1:50 every kill logged is `(2, 1)`
    and there is at least one.
  - `test_readings_collect_kills`: run `combat_period!` after a step with a kill; `kill_rows` has one row with that `t`.
- [ ] **Step 2:** Run `["xxl_combat_distance"]`. Expected: FAIL.
- [ ] **Step 3:** In `xxl_combat_move!` and `disc_vulnerable`, the same two replacements as Task 2 Step 3; add the kill
  log and the readings' collection.
- [ ] **Step 4:** Run `["xxl_combat_distance"]`, `["combat"]`, `["vi1_combat_unchanged"]`. Expected: all pass.
- [ ] **Step 5: Commit** `julia xxl: combat by cultural distance in the xxl move; kills logged with killer-victim distance`.

### Task 4: The VI-1-distance experiment and its kills file

**Files:**
- Modify: `julia/src/xxl/vi1_combat.jl` (or create `julia/src/xxl/vi1_distance.jl`, included after it)
- Modify: `julia/src/xxl/combat_study.jl`
- Test: `julia/test/test_vi1_distance.jl`

**Interfaces:**
- Consumes: `vi1_combat_experiment()`, `kill_rows`, `write_table_csv`.
- Produces: `VI1_DISTANCE_ID = "VI-1-distance"`, `vi1_distance_experiment(reg=load_registry())::Experiment`;
  `combat_plan` and `combat_study_args` accept the id; `COMBAT_USAGE` and the `combat_study_args` docstring list it;
  `combat_seed!` writes `seed<k>-kills.csv` (through a temporary name) when `world_config(exp, world).combat_hostility > 0`.

- [ ] **Step 1: Write the failing tests** in `test_vi1_distance.jl`:
  - `test_vi1_distance_config`: id, rules and steps as VI-1-combat's; `combat_hostility == 0.5` and `combat_alpha == Inf`
    in `config` and `xl_config`; each fingerprint ends with the variant line from Global Constraints and starts with
    VI-1-combat's fingerprint.
  - `test_vi1_distance_study_args`: `combat_study_args(["--world", "today", "--exp", "VI-1-distance"])` is accepted.
  - `test_vi1_distance_runs` (Review Focus 4): `run_combat_world("book", "VI-1-distance"; seeds=1, periods=4, out=tmp,
    io=devnull)` twice into two folders; `seed0.csv`, `seed0-combat.csv` and `seed0-kills.csv` are byte-identical
    between them; the kills file's header is `t,distance,same_label` and every row's `t` is in 1:4, `distance` in 0:11,
    `same_label` in 0:1.
  - `test_no_kills_file_without_hostility`: a 4-period VI-1-combat book run leaves no `seed0-kills.csv`.
- [ ] **Step 2:** Run `["vi1_distance"]`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `["vi1_distance"]`, `["vi1_combat"]`. Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: VI-1-distance, VI-1-combat with fight and fear drawn on cultural distance`.

### Task 5: Full suite and dry run (controller)

- [ ] **Step 1:** Full suite. Expected: all pass (65,332 before this plan plus the new tests).
- [ ] **Step 2:** Dry run into a scratch folder (not `results-julia-xxl`): for each world,
  `julia --project=julia julia/xxl_combat_study.jl --world <w> --exp VI-1-distance --seeds 2 --periods 30 --jobs 2 --out <scratch>`.
  Expected: kills in at least one world (sum `killed_blue + killed_red` over the combat CSVs > 0, and the kills files have
  rows). If no world has kills, stop and report to the user.
- [ ] **Step 3:** Record the dry run's kills, kills within a label, and population at t = 30 per world in the ledger.
