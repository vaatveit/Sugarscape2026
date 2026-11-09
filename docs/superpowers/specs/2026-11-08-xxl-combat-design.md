# Stage 8: combat in xxl — design

The user asked to add combat to the xxl goal, run the book's combat variants in xxl and analyze their behaviour, and to
skip the questions. Everything below that isn't quoted from the user is **my call**, marked as such, for the user to
accept or change when approving.

## Intent

The xxl goal is a well-functioning simulation: the population rarely goes extinct, and sex, culture, trade, credit and
disease each work as intended (docs/xxl.md, stage 1). All five are settled (stages 3–7). The user's words: "let's add
combat to the xxl goal. implement the different variants of combat above and analyze their behavior." The variants
"above" are the book's (pp.82–92):

| Variant | Experiment | Rules | What the book shows |
|---|---|---|---|
| C_∞ | III-9 (Animations III-9, III-10) | ({G1}, {C_∞}), no aging | one tribe wipes out the other, or small colonies of each survive on their own peak; tribes often swap mountains |
| C_2 with same-tribe replacement | III-11 | ({G1}, {C_2, R[60,100]}) | a lasting front: a "war of attrition" |
| No combat | III-12 | ({G1}, {M}) | the two tribes spread as waves that collide and interpenetrate |
| C_2 | III-13 | ({G1}, {C_2}) | combat stops the interpenetration |
| C_∞ with culture | III-14 | ({G1}, {C_∞, K}) | invaders are assimilated; no runaway hegemony |

**What "works as intended" means here (my call):** rule C works in xxl as it does in the book. In the book combat is
war between tribes. It kills across tribal lines and changes how a run turns out; it keeps tribes apart, so that they
meet at a front instead of mixing; the war can last; and with culture on, tag flipping keeps either tribe from taking
everything. In xxl that has to happen without the population dying out (the goal's first clause). xxl's world holds
100 times the book's agents and has no twin peaks on its generated map, so the book's exact endings (eradication,
swapped mountains) aren't asked for; they are reported.

**Adding combat to the goal (my call):** docs/xxl.md's goal sentence gains combat, written in the stage's write-up.
Adding a combat check to the scorecard (which runs VI-1, where combat is off) is not part of this stage; the write-up
proposes it if the results call for one.

## What we already know (read 2026-11-08, no new runs)

- **Every variant is already an experiment** (julia/registry.toml: III-9, III-11, III-12, III-13, III-14), each with an
  xl version (`xl_fingerprint`), and `combat_alpha`, `replacement_same_tribe` and tribal blocks are config fields. xxl
  runs combat under round vision and speed with its own move, `xxl_combat_move!` (julia/src/xxl/combat.jl, rule 7). So
  no combat rule has to be written: the stage needs xxl versions of the experiments, an observer and a report.
- **The book recreation** (docs/replication/chapter-3.md) passes III-9 (one of the three endings, 10/10), III-11 (both
  tribes persist, 5/5) and III-14 (no runaway hegemony, 0.5 of runs). It does **not** reproduce the waves: Blue
  advances about 8 sites by t = 50 against the book's 10–60, with or without combat (III-13 9.6), so III-13's
  suppression fails. Waves can't be the measure; contact between tribes can.
- **Final populations** in the saved runs (results-julia, results-julia-xl; xl's III-12, III-13 and III-14 are from
  before xl's centred look, so they are only a guide):

  | | Book world | xl |
  |---|---|---|
  | III-9, t = 1000 (from 540 / 54,000) | 133–272 | 156–739 |
  | III-11, t = 1000 (fixed by replacement) | 400 | 40,000 |
  | III-12, t = 200 (from 740 / 74,000) | 366–380 | 36,715–37,030 |
  | III-13, t = 200 | 292–320 | 18,880–19,131 |
  | III-14, t = 1000 (from 540 / 54,000) | 2–19 | 3,734–4,518 |

- **xxl III-9 under the first rules** (docs/xxl.md, "Combat (`XXL-combat`, III-9)"): xl collapses to about 400 agents,
  xxl keeps about 19,000. Speed is what tames combat: an occupied site can be attacked only within the attacker's speed
  (1–6), and kills fall from 38,011 to 5,504 by t = 1000 when speed is added. Kills are about 16% of deaths there,
  and both tribes survive. Those runs used `XXL_V1` on the xl map, not today's defaults.
- **xl III-9's war is driven by a sparse retaliation check** (docs/xl.md): xl's lattice look sees one site in 10, so
  agents miss wealthy attackers. This stage doesn't change it (non-goal).

## Goals

1. Run each variant in three worlds and record what combat does: kills, deaths, tribe sizes, contact between tribes,
   territory and wealth.
2. Decide whether combat works as intended in today's xxl by the bars below, against the book's world.
3. Write it up in docs/xxl.md as "Stage 8: combat", with combat added to the goal.

## Non-goals and anti-goals

- No change to `XXL_DEFAULTS` or to any rule in Part 1. If combat turns out weak or broken, the readings go to the user
  and any rule gets its own spec with the user (as stages 6 and 7).
- No change to xl's retaliation check, the book's combat rule or the waves' failure.
- No combat in VI-1 or the scorecard (combat is barred with credit and with spice, and VI-1 has both).
- Anti-goal: an observer that changes a run. Every standard CSV must be byte-identical with the observer on and off.
- Anti-goal: a bar that passes because combat kills nobody. A world where no one fights can't read "works".

## Part 1: the readings

**Worlds (my call), as stages 6 and 7:** the book's 50 × 50 world under the book's rules (`exp.config`), xl
(`to_xl`) and today's xxl (`to_xxl(exp.config, XXL_DEFAULTS)`), for each of the five experiments, over each
experiment's own steps (1000 for III-9, III-11 and III-14; 200 for III-12 and III-13). Today's rules put the blocks at
xl's corners on the generated map, with viable placement inside each block; the book's twin peaks don't exist there
(a caveat for the write-up).

**Seeds (my call):** 0–19 in every world and experiment, 20 seeds. Seeds 0–4 (0–9 for III-9 and III-14) already have
saved runs in the main checkout's `results-julia` (the book's world, all five current) and `results-julia-xl` (only
III-9 and III-11 current: III-12, III-13 and III-14 were saved before xl's centred look, commit `eb70704`), which gives
the drift check below where the fingerprints still match.

**Each period, per world (the observer):**
- **Deaths by cause and tribe:** kills, by the attacker's tribe and the victim's; starvations; deaths of age (III-11
  only). Both combat moves (the book's `combat_move!` and `xxl_combat_move!`) record kills; recording draws nothing.
- **Tribe sizes:** the standard CSV's `n_blue` and `n_red`.
- **Contact:** the share of neighbour pairs that are cross-tribe ("mixing"), and the share of agents with at least one
  neighbour of the other tribe ("front share"). Neighbours are the interaction set: the four lattice neighbours in the
  book's world and xl, the sites within the interaction radius (1.5) in today's.
- **Territory:** each tribe's "home share", the share of its agents nearer (on the torus) to its own block's centre
  than to the other block's.
- **Wealth:** the Gini and the largest sugar holding of each tribe.
- **Tribe changes by culture** (III-14 only): agents whose tribe changes in the period's tag flips.

## Part 1's bars (my call)

**Intervals, small populations and missing values** as stage 7: a reading per seed is the mean of its per-period
values over the window; ratios of worlds are ratios of their means over seeds, with 95% intervals from 10,000 bootstrap
resamples of each world's seeds apart (bootstrap seed 20261031); a period with an undefined value is skipped; a world
with fewer than 15 seeds in a value reads that bar as missing.

**W, combat is weak in xxl.** Both of these:
- **W1, lethality (III-9):** today's kills per founder by t = 1000 are under half the book's, the interval's upper end
  under 1. (Kills per founder rather than per agent-period, since the book's war ends once one tribe is gone.)
- **W2, separation (III-13 against III-12):** combat's cut in mixing, 1 − mixing(III-13) ÷ mixing(III-12) over
  t = 101–200 (each a mean over seeds), is under half the book's for today, the interval's upper end under 1. The
  interval comes from resampling the four sets of seeds apart. **A reference must show a cut:** the book's cut counts
  only when its own 95% interval is above 0. The book recreation doesn't reproduce the waves, so it may not; then W2
  is read against xl's cut on the same terms, and if xl's interval isn't above 0 either, W2 reads missing. The report
  says which reference W2 used.

W holds only when both hold; W fails when either fails; it reads missing when neither fails and one is missing.

**F, the wars stay wars and the population lives (today only):**
- **F1, a lasting front (III-11):** every seed has a kill in each 100-period block of t = 501–1000, and in at least
  80% of seeds both tribes hold their ground: each tribe's home share, averaged over t = 501–1000, is above 0.5.
  (III-11 replaces every dead agent with one of its own tribe, so tribe sizes never change and "both tribes alive"
  can't fail; replacements are placed anywhere, so without a front holding each tribe's side, home shares sit near
  0.5. The book's world and xl are shown beside it.)
- **F2, survival (III-9 and III-14):** the population is above 0 at t = 1000 in every seed.
- **F3, no runaway hegemony (III-14):** both tribes hold at least 5% at t = 1000 in at least half the seeds (the book
  recreation's band for III-14 starts at 0.5).

F holds when all three hold. A seed that didn't finish fails F.

**Outcome:**
- **The drift check fails:** stop and report.
- **F fails or reads missing:** reported to the user with the readings. No rule is proposed until we've talked.
- **W reads missing:** reported to the user; no outcome is drawn.
- **W holds and F passes:** combat is weak in xxl. The readings (kills by window, front share, speed's reach) go to
  the user with what they point to, and any rule gets its own spec with the user.
- **W doesn't hold and F passes:** combat works as intended in xxl. Written up in docs/xxl.md as "Stage 8: combat", the
  goal gains combat, and the stage stops.

**Reported, deciding nothing:** every reading for every variant and world, by window (t = 1–100, 101–200, 201–500,
501–1000 where the run is that long); III-9's ending per seed (one tribe under 5%, or both alive); home shares (do
tribes swap?); kills by attacker tribe; the survivors' wealth; xl beside the book's world and today throughout.

**Caveats, to state in the write-up:** the book's world has its own density and neighbourhood (4 sites against xxl's 8
within 1.5), and the generated map has no twin peaks, so "half the book's" compares unlike worlds; xl is shown to
separate world size from xxl's rules. The book recreation doesn't reproduce the waves, so W2 measures mixing, not wave
suppression.

## How it's built (left to the builder, within these)

- Follow stage 7's shape: an observer (`julia/src/xxl/combat_readings.jl`), a study
  (`julia/xxl_combat_study.jl --world book|xl|today --exp III-9|III-11|III-12|III-13|III-14 [--seeds N]
  [--first-seed K] [--jobs J] [--out DIR]`, folders `combat-<world>-<exp>-s<first>-<seeds>-p<steps>/`) and a report
  (`julia/xxl_combat_report.jl`, writing `results-julia-xxl/combat-part1.md`).
- Kill recording in the book's `combat_move!` draws nothing and changes nothing; a test shows each world's CSV
  byte-identical with the observer on and off, for each experiment.
- Drift check (my call): each new seed's standard CSV that has a saved counterpart with the same fingerprint
  (the main checkout's `C:/Projects/Sugarscape2026/results-julia` for the book's world and `results-julia-xl` for xl)
  must be byte-identical to it. A saved folder whose fingerprint differs is reported as "no reference", not as drift:
  expected for xl's III-12, III-13 and III-14 (my call: not rerun; the observer-on-and-off test covers them). Today
  has no reference (XXL-combat used `XXL_V1`).
- Tests for each reading on small hand-built worlds, the bars on hand-made seed tables, and the outcome order.

**Cost (estimate, my call to check by a dry run):** today's III-9 took about 6.5 minutes a seed for 1000 periods under
the first rules. At 5 workers the 100 today seeds come to roughly 1.5–2 hours; xl and the book's world add a few
minutes. A dry run of 5 periods per world and experiment will give the real figure before asking for the go-ahead.

## Branch and approvals

Branch `xxl-combat` (worktree `.claude/worktrees/xxl-combat`), from main `0dc0021`. Commits on the branch, merging,
pushing and every study run need the user's approval.
