# Assimilation by cultural distance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rule K in which a contact copies with probability 1 − h (d / L)^k (combat's curve), in two forms: copying a
differing tag (A, `"distance"`) or a random tag (B, `"distance-random"`); experiments VI-1-assim and VI-1-assim-random.

**Architecture:** A config value `culture_rule` selects the copy step inside `culture_transmit!`; the reached agents and
their shuffled order are unchanged. The copy chance reuses `fight_chance` (p(copy) = 1 − fight_chance). The default
`"random"` path is today's code, so old runs are byte-identical.

**Tech Stack:** Julia, module `Sugarscape` in `julia/`, Test stdlib.

**Spec:** `docs/superpowers/specs/2026-11-09-assimilation-distance-design.md`

## Global Constraints

- **Nothing that ran before changes.** With `culture_rule = "random"` (the default), the 24 guard fixtures (III-9,
  III-11, III-12, III-13, III-14, VI-1, VI-1-combat, VI-1-distance; book, xl, today) stay byte-identical.
- **`Config.culture_rule::String = "random"`**, one of `"random"`, `"distance"`, `"distance-random"`. Either distance form
  needs `culture` and `0 < combat_hostility < 1` (combat by distance, h below 1).
- **Per contact (b reached by a):** d = `count_ones(a.tags ⊻ b.tags)`. If d = 0: no draw, nothing changes. Else draw
  `rand(m.rng) < 1 - fight_chance(h, a, b, k)` with h = `combat_hostility`, k = `combat_curve`; on success:
  - `"distance"`: b takes a's value at one differing position, chosen as the j-th differing bit with
    j = `rand(m.rng, 1:d)` (lowest bit first);
  - `"distance-random"`: position `rand(m.rng, 0:(a.ntags - 1))`, copied as today (no change if they agree there).
- **Experiments:** `VI-1-assim` = VI-1-distance + `culture_rule="distance"`; `VI-1-assim-random` = VI-1-distance +
  `culture_rule="distance-random"`; fingerprint lines
  `variant: VI-1-assim culture_rule=distance (copy a differing tag with p = 1 - fight chance)\n` and
  `variant: VI-1-assim-random culture_rule=distance-random (copy a random tag with p = 1 - fight chance)\n`;
  both in `JULIA_COMBAT_EXPS`.
- **No study run** without the user's go-ahead; tests and the sweep script only.
- **Suite:** `julia --project=julia -e 'using Pkg; Pkg.test()'`. One file: `Pkg.test(test_args=["<substring>"])`.

## Review Focus

1. **A copy in form A never touches an agreeing tag and always changes exactly one tag.** Test in Task 1.
2. **d = 0 makes no draw** (so identical neighbours don't shift the random stream). Test in Task 1.
3. **The default path is today's draw for draw** (guard fixtures). Run in Task 1.
4. **h = 1 is refused** for either distance form (no pair cut off). Test in Task 1.
5. **The sweep's settings carry `culture_rule` into today's world** (`to_xxl` keeps it). Test in Task 2.

---

### Task 1: The rule and its setting

**Files:** Modify `julia/src/config.jl`, `julia/src/rules/culture.jl`. Test: `julia/test/test_culture_distance.jl`.

**Interfaces:** Produces `Config.culture_rule`; `copy_chance(h::Float64, a::Agent, b::Agent, k::Float64)::Float64 =
1 - fight_chance(h, a, b, k)` in culture.jl (exported).

- [ ] **Step 1: Failing tests** (`tiny_model` with `tag_length=5`, `culture=true`, `combat_alpha=Inf`,
  `combat_hostility=h`, `combat_curve=k`, `culture_rule=…`; agent a with tags 00000 next to b; one `culture_transmit!`):
  - `test_copy_chance`: `copy_chance(0.5, 00000, 00111, 1.0) ≈ 0.7`; d = 5, h = 0.5 → 0.5; k = 2, d = 3 → 1 − 0.5·0.36.
  - `test_distance_changes_one_differing_tag` (RF 1): form A, b = 01110, over seeds 1:200: after a contact b either is
    unchanged or differs from its old tags in exactly one bit, that bit was a differing one (now equal to a's).
  - `test_distance_rate`: form A, h = 0.5, k = 1, b = 00111 (d = 3): changed share over seeds 1:600 within
    0.7 ± 0.06.
  - `test_distance_random_rate`: form B, same pair: changed share within (3/5)·0.7 = 0.42 ± 0.06.
  - `test_identical_no_draw` (RF 2): form A, b = a's tags: `m.rng` state equals a copy of the state taken just after
    the shuffle would be — practically: two models with the same seed, one with b identical and one with no b at all,
    leave `rand(m.rng)` equal after `culture_transmit!` (the shuffle of a 1-element list draws nothing; check that and
    adjust if `shuffle!` draws).
  - `test_culture_rule_config` (RF 4): default "random"; "near" refused; "distance" without culture refused; with
    `combat_hostility=0` refused; with `combat_hostility=1.0` refused; with 0.5 accepted; same for "distance-random".
- [ ] **Step 2:** Run `["culture_distance"]`: FAIL. Implement; the "random" branch is the existing loop body untouched.
- [ ] **Step 3:** Run `["culture_distance"]`, `["culture"]`, `["vi1_combat_unchanged"]` (48 asserts, RF 3): pass.
- [ ] **Step 4: Commit** `julia: rule K by cultural distance: copy with p = 1 - fight chance, a differing or a random tag`.

### Task 2: The experiments and the sweep script

**Files:** Modify `julia/src/xxl/vi1_combat.jl` (two builders next to the reach ones, via `vi1_reach_experiment`),
`julia/src/xxl/combat_study.jl` (table + usage). Test: `julia/test/test_vi1_assim.jl`. Create (git-ignored)
`results-julia-xxl/vi1-assim-scripts/sweep.jl`.

- [ ] **Step 1: Failing tests:** each experiment's `config` and `xl_config` carry its `culture_rule` and
  `combat_hostility == 0.5`; each fingerprint is VI-1-distance's plus its line; `world_config(e, "today").culture_rule`
  is the experiment's (RF 5); `combat_study_args(["--world", "today", "--exp", id])` accepted for both; a 4-period book
  run of each writes `seed0.csv`, `seed0-combat.csv`, `seed0-kills.csv`.
- [ ] **Step 2:** Run `["vi1_assim"]`: FAIL. Implement. Run `["vi1_assim"]`, `["vi1_reach"]`, `["vi1_distance"]`: pass.
- [ ] **Step 3: Commit** `julia xxl: VI-1-assim and VI-1-assim-random in the combat study`.
- [ ] **Step 4:** Write the sweep script as `vi1-curve`'s (`results-julia-xxl/vi1-curve-scripts/sweep.jl` in that
  worktree): ids `VI-1-assim-k<k>-h<h>` and `VI-1-assim-random-k<k>-h<h>`, built from VI-1-assim / VI-1-assim-random
  with `replace_config(…; combat_hostility=h, combat_curve=k)`, k in (1.0, 2.0, 3.0, 4.0), h in (0.25, 0.5, 0.9),
  today, seeds 0–9, 5 workers. Not run.

### Task 3: Full suite and dry run (controller)

- [ ] **Step 1:** Full suite: all pass.
- [ ] **Step 2:** Dry run, scratch folder, 30 periods, seeds 0–1, today: VI-1-assim and VI-1-assim-random finish;
  record kills, population and tribe changes at t = 30.
