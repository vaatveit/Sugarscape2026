# Assimilation by cultural distance — design

Branch `vi1-assim` (worktree `.claude/worktrees/vi1-assim`), from `c13c83e` on `vi1-curve` (`combat_curve`), kept apart
from `vi1-curve` while its sweep runs there.
Everything below that isn't the user's is **my call**, marked as such, for the user to accept or change when approving.

## Intent

In VI-1-distance and its variants, combat depends on cultural distance but culture (rule K) does not. Rule K copies one
random tag position onto each neighbour, so a contact changes something with probability d / 11: the most different
pairs assimilate fastest. Culture only converges, and every surviving population so far ended culturally uniform, with
combat dying with the difference. The user's goals for the society: most seeds survive, neither tribe dies out, and
combat doesn't die out. The user asked to "investigate making assimilation itself depend on distance".

## What the user decided

- **All pairs influence each other.** "yes, all pairs of agents influence each other": distance makes influence rarer,
  never impossible.
- **Very different pairs assimilate less often** than close pairs ("less often").
- **Same curve as combat.** "same as combat": p(copy) = 1 − p(fight) = 1 − h × (d / L)^k, with combat's
  `combat_hostility` h and `combat_curve` k.
- **Test both ways of copying** ("test both"): when a contact copies, it changes (A) a tag where the two differ, or (B)
  a random tag, as today's rule K does.

## The rule: K by distance

When an agent a meets another agent b in rule K (the agents rule K reaches now: its neighbours, or with `culture_reach`
combat's sight or attack reach):
- d = the number of tags where they differ, L = the tag length.
- If d = 0, nothing happens and nothing is drawn (my call: there is nothing to copy).
- Otherwise, with probability p(copy) = 1 − h (d / L)^k, b copies one of a's tags. Which one is the setting:
  - **A, `"distance"`:** a position where they differ, chosen uniformly among the d differing positions, so every
    copy changes a tag. A contact changes something with probability 1 − h (d / L)^k: close pairs change far more
    often than today (one tag apart, h = 0.5, k = 1: 95% against 9%), very different pairs less often.
  - **B, `"distance-random"`:** a random position, as today; if they already agree there nothing changes. A contact
    changes something with probability (d / L)(1 − h (d / L)^k): below today's d / L at every distance.

Draws come from `m.rng` (my call: the copy draw first, then the position, in both forms). The order of contacts is shuffled as now.

**h must be below 1** (my call): at h = 1, agents that differ everywhere would never copy, which the user ruled out. So
assimilation by distance needs 0 < h < 1.

## How it's switched on (my calls)

A config value `culture_rule`: `"random"` (default: today's rule K), `"distance"` (A) or `"distance-random"` (B). Either distance form needs
culture, tags and combat by distance (`combat_hostility` in (0, 1)), since it reads combat's h and k. Julia only.
Vertical transmission at birth (`cross_tags`) and everything else in rule K's neighbourhood, friends and the readings
stay as they are.

## The experiment (my calls)

- `VI-1-assim` (A) and `VI-1-assim-random` (B): VI-1-distance with `culture_rule` set, defined next to VI-1-distance
  and run through the combat study, each with a fingerprint line naming the change.
- **Runs, after the user's go-ahead**: for each form the same sweep as combat's curve, in today's xxl, seeds 0–9, 500
  periods: k in 1, 2, 3, 4 and h in 0.25, 0.5, 0.9 (0.9 in place of 1, which this rule refuses). 2 × 12 settings,
  about 100 minutes.
- **Read against the same bars as the combat sweep**, fixed before the runs: at least 80% of seeds alive at t = 500;
  both tag majorities at least 5% in at least 80% of survivors; kills in t = 401–500 in at least 80% of survivors.
  Shown beside the combat sweep's settings (k, h) so the effect of the culture rule is visible setting by setting
  (h = 0.9 has no combat-sweep twin; h = 1.0 has no assimilation twin).
- The book's world and xl are left out until today's xxl has a setting that works, as for the combat sweep.

## Goals

1. Rule K in which the chance of a change falls with cultural distance as 1 − h (d / L)^k, never to zero.
2. VI-1-assim and VI-1-assim-random run through the combat study in today's xxl.
3. Nothing that ran before changes.

## Non-goals

- No change to vertical transmission, friends, tribe definitions or the readings.
- No separate culture settings (the user chose combat's curve).
- No run before the go-ahead; no write-up.

## Anti-goals

- Any existing run changing. With `culture_rule = "random"`, every experiment the guard fixtures cover (III-9, III-11,
  III-12, III-13, III-14, VI-1, VI-1-combat, VI-1-distance) gives byte-identical CSVs.
- A pair that can never influence each other (h = 1 is refused).

## How it's built (left to the builder, within these)

- Tests: p(copy) at d = 1, 5, 11 for given h and k; d = 0 draws nothing; in A a successful copy changes exactly one
  differing tag and never an agreeing one; over many seeds the change rate matches 1 − h (d/L)^k in A and
  (d/L)(1 − h (d/L)^k) in B; the "random" path is
  draw-for-draw today's; config checks (`"distance"` without combat by distance, h = 1, unknown values refused).
- The sweeps reuse the combat sweep's script, with `culture_rule` set and h = 0.9 for 1.0.
- Build after the combat sweep finishes or on this branch only: the sweep's workers load `julia/src` from
  `vi1-curve`'s worktree, so nothing there may change while it runs.
