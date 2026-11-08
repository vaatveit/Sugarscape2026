# Sugarscape xxl, stage 7: culture — design

Status: draft, 2026-11-07. The user chose culture as the next stage and asked to skip the questions, so every choice
below that isn't quoted from the user is **my call**, marked as such, for the user to accept or change when approving.

## Intent

The xxl goal is a well-functioning simulation: the population rarely goes extinct, and sex, culture, trade, credit and
disease each work as intended (docs/xxl.md, stage 1). Survival, credit, disease, trade and sex have had their stages;
culture is the last. It passes both scorecard checks: both tribes hold at least 5% at t = 200 in every VI-1 seed (X3),
and tags flip in every period (X4, fewest flips per agent 0.19 under the stage-1 defaults, about 0.3 under list D).
Neither check asks whether culture does what the book's rule K does.

In VI-1, culture changes nothing else: cultural preferences and combat are off, so tags matter only to themselves and
to children (vertical transmission, p.78). The question is therefore about tags alone.

**What "works as intended" means here (my call):** rule K works in xxl as it does in the book. In the book
(pp.73–80, Animation III-6, III-8 and III-15), tag flipping between neighbours makes agents culturally like the agents
around them: "each spatially segregated subpopulation converges to pure Blue or pure Red", friends grow alike
(closeness of all friends 0.52 → 0.89), and with sex on, separate groups keep their own colours and meet in the
lowlands. So:
1. **Agents come to live among culturally like agents.** Neighbours are more alike than chance, and more so over time.
2. **Areas take on a colour.** A patch the size of the book's world tends toward one tribe, as the book's world does.
3. **Culture keeps moving and both tribes live** across the whole world. X3 and X4 say so already.

xxl's world holds 100 times the book's agents, so the whole world converging to one colour, as the book's does, isn't
expected and isn't asked for (my call). The book's own 50 × 50 VI-1 is the reference for 1 and 2, as the book's rules at
the book's scale. xl's VI-1 is a second reference: the same world size, without xxl's rules.

## What we already know (read 2026-11-07, no new runs)

From the standard CSVs of stage 6's runs (VI-1, seeds 80–139 for the book, 28 of which survive; seeds 80–99 for xl
and today, all surviving):

| t | Book: blue share, range over seeds | Book: friend closeness | xl: friend closeness | Today: blue share, range | Today: friend closeness |
|---|---|---|---|---|---|
| 50 | 0.23–0.68 | 0.62 | 0.55 | 0.47–0.53 | 0.65 |
| 100 | 0.03–1.00 | 0.74 | 0.56 | 0.46–0.53 | 0.66 |
| 200 | 0.00–1.00 | 0.82 | 0.55 | 0.43–0.58 | 0.67 |
| 500 | 0.00–1.00 | 0.84 | 0.54 | 0.42–0.60 | 0.68 |

- **The book's world converges, as the book says.** By t = 100 some seeds are all one tribe; at t = 500 the mean
  distance of the blue share from one half is 0.28. Friend closeness reaches 0.84, near the book's 0.89.
- **Today's friends are less alike than the book's, xl's barely alike at all.** Today's friend closeness rises slowly,
  0.65 to 0.68 over 450 periods, against the book's 0.62 to 0.84. Above chance (0.5), today's is about half the
  book's. xl's stays at chance.
- **Friend closeness is only a hint.** It is taken when a friend is met and never updated (p.80), and an agent who meets
  more agents keeps closer friends by choice alone. xxl's neighbours are everyone within 1.5 (up to 8 sites), the
  book's the four lattice neighbours. So Part 1 measures closeness afresh.
- **The global blue share says little in the big worlds.** 20,000 founders keep it near one half by sheer numbers.
  That's why reading 2 below counts book-sized patches.

My guess at the cause, to be tested, not assumed: xxl's agents travel further over their lives than the book's (they
see 10–60 and walk toward what they see), so their neighbours keep changing and K never gets long enough with the same
neighbours to make them alike. xl's agents jump up to their vision every period, the extreme of the same thing.

## Goals

1. **Part 1, a diagnosis.** Readings that say whether xxl agents live among culturally like agents, and whether areas
   take on a colour, as much as the book's rules do at the book's scale. Part 1 can end the stage: if culture works as
   intended by the bars below, that's written up and the stage stops with no rule change.
2. **Only if Part 1 finds a problem:** a rule change, designed in its own spec after Part 1, with the user. Picking a
   rule waits for Part 1's readings; the mixing readings below are there to point at one.

## Non-goals and anti-goals

- **No change to rule K itself**, its tag length (11), group membership or vertical transmission. They're the book's.
- **No cultural preferences, combat or Schelling-style moving toward one's own tribe** in this stage. They'd make tags
  matter in other ways, which isn't the question.
- **Whole-world convergence is not the goal**, and neither is more flipping. A rule that makes neighbours alike only by
  making one tribe win everywhere would fail X3 and the intent.
- **No change to `XXL_DEFAULTS` or `XXL_V1` in Part 1**, and none of the other stages' rules change.
- **Python, the runner and the viewer don't change.**
- **No study run without the user's go-ahead** (the user's standing rule). The test suite and scratch dry runs of a few
  periods are fine.

## Part 1: the readings

Three worlds, VI-1, 500 periods each, as in stage 6 (my call):
- **book:** the Julia port's VI-1, 50 × 50, the book's rules, seeds 80–139 (60 seeds, because the book loses about
  half its seeds by t = 500 and a bar needs 15 survivors; 28 survived in stage 6);
- **xl:** the xl reference VI-1, seeds 80–99;
- **today:** VI-1 under `XXL_DEFAULTS`, seeds 80–99.

Rule K draws its random numbers in the run, so these runs repeat stage 6's draw for draw; the new observer must keep
that true. Stage 6's folders don't hold the readings below, so the runs are needed again (my call: rerun rather than
add the readings to stage 6's study).

An observer, like stage 6's `SexReadings`, writes per-seed tables beside the standard CSV. It must change nothing in
a run: each seed's standard CSV stays byte-identical with the observer on and off (tested). It draws no random numbers.
Readings are taken at the end of each period (after every agent's turn), every period unless noted.

**Per period:**
- population; blue share; tag flips per agent (as X4);
- **neighbour closeness:** over every pair of living agents who are neighbours by the rule's own reach (the book's and
  xl's four lattice sites, xxl's radius 1.5), the mean of 1 − Hamming distance ÷ 11. Each unordered pair counts once;
- **chance closeness:** the same mean over every pair of living agents in the world, worked out exactly from the count
  of zeros at each tag position (no sampling);
- neighbours per agent (mean), and the share of agents with none;
- **neighbour persistence:** of the neighbour pairs at the end of the last period whose two agents are both still
  alive, the share that are still neighbours now;
- distance moved this period (mean, in sites, on the torus), and in xxl, mean speed;
- per tag position, the share of zeros (11 columns), so positions locking in, as in Animation III-7, show.

**Every 10 periods, the patches (my call):** the world is cut into patches of the book's size, 50 × 50 sites (the book's
world is one patch; xl's and today's are 100). For each patch holding at least 20 agents: its agent count and blue share.
From them, **patch polarization**: the mean over those patches of |2 × blue share − 1|, weighted by agent count. 0 is
half and half in every patch, 1 is every patch one colour. The count of patches left out is recorded.

**Friend closeness** (best and all friends) is in the standard CSV already and is reported beside the rest.

## Part 1's bars (my call)

**Intervals.** As stage 6: seeds aren't paired across worlds. Each reading is a per-seed value, the mean over the
window of its per-period (or per-tenth-period) values. A ratio of two worlds is the ratio of their means over seeds, and
its 95% interval comes from a bootstrap that resamples seeds within each world separately: 10,000 resamples, percentile
interval, bootstrap seed 20261031, so the report repeats. A seed that went extinct before t = 500 is left out and
counted in the report. A world left with fewer than 15 seeds reads the bar as missing, and a missing bar decides
nothing.

**Small populations (my call).** A period in which a reading is undefined (no neighbour pairs; no pairs still alive for
persistence; no patch of 20 agents) is skipped in that seed's window mean. A seed with no defined period in the window
for a reading is missing for that reading only, and doesn't count toward that reading's 15. The book's world is its one
patch, so the 20-agent floor applies to it too. The report gives, per world and reading, the seeds used and the share of
seed-periods skipped, so a W2 resting on a few large surviving book seeds is visible.

**W, culture is weak in xxl.** Decided at t = 301–500, by both of these:
- W1: today's neighbour closeness above chance tags (neighbour closeness − 0.5) is less than half the book's, with
  the interval of the ratio below 1. (0.5 is the closeness of independent random tags. Chance closeness isn't the
  baseline: in a book seed that has converged, every pair is alike, near and far, and that is the rule working.)
- W2: today's patch polarization is less than half the book's, with the interval below 1.

W holds only when both hold. W fails when either fails, even if the other reads missing; it reads missing only when
neither fails and at least one is missing (as stage 6's M).

**F, culture keeps moving and both tribes live across today's world.** In at least 80% of today's seeds both tribes
hold at least 5% of the population at t = 500, and in every seed the fewest tag flips per agent in any period of
t = 301–500 is above 0. (X3 and X4, read at the end instead of t = 200, my call.) F counts all 20 of today's seeds
run: a seed that went extinct fails both parts, rather than being left out.

**Outcome:**
- **F fails or reads missing:** reported to the user with the readings. No rule is proposed until we've talked.
- **W holds and F passes:** culture is weak in xxl. The mixing readings (persistence, distance moved, neighbours per
  agent, beside xl's and the book's) go to the user with what they point to, and any rule gets its own spec with the
  user.
- **W doesn't hold and F passes:** culture works as intended in xxl. Written up in docs/xxl.md as "Stage 7: culture"
  and the stage stops.
- **W reads missing:** reported to the user; no outcome is drawn.

**Reported, deciding nothing:** each reading at t = 51–100, 101–200 and 201–300 too, to show whether today is catching
up or has levelled off; xl beside both; chance closeness; friend closeness; per-position zero shares at t = 500.

**Caveats, to state in the write-up:** the book's world has its own density and neighbourhood (4 sites against xxl's 8
within 1.5), so "half the book's" compares unlike worlds; xl is shown to say how much is world size and how much
xxl's rules. A 50 × 50 patch of a bigger world isn't closed as the book's world is: agents come and go across its
edges, which is part of what W2 measures.

## How it's built (left to the builder, within these)

- In the Julia port only: `julia/src/xxl/` for the observer and the study's run and report, with command lines
  `julia/xxl_culture_study.jl --world book|xl|today [--seeds N --first-seed K --jobs J]` and
  `julia/xxl_culture_report.jl --book DIR --xl DIR --today DIR --md PATH`, like stage 6's. Reusing stage 6's run,
  resume, fingerprint and bootstrap pieces is expected.
- A folder per world, named and fingerprinted like stage 6's. A stopped seed is rerun from period 0.
- The report writes `results-julia-xxl/culture-part1.md`: the readings per world and window, each bar with its value,
  interval and result, and the outcome by the rules above. The results folder is git-ignored.
- Neighbour pairs: the observer needs every agent's neighbours at the period's end, which `a.neighbors` doesn't give
  (it's set before the agent's rules run, and others move after). The observer finds them itself from the grid with the
  rule's own neighbourhood, without touching the model's scratch lists in a way that changes the run.
- Tests: the observer changes nothing (byte-identical CSVs in all three worlds on a short run); hand-made worlds where
  every reading has a known value (two neighbour pairs with known tags, a pair that stops being neighbours, an agent
  moving a known distance across the torus edge, patches with known colours, a patch under 20 agents left out); chance
  closeness against a brute-force count over all pairs; the report on hand-written folders, including a bar that reads
  missing and W failing on one part while the other is missing.
- Drift check (my call): each new seed's standard CSV must be byte-identical to stage 6's for the same world and seed
  (`.claude/worktrees/xxl-sex/results-julia-xxl/sex-{book-VI-1-s80-60,xl-VI-1-s80-20,today-VI-1-s80-20}-p500/`, kept
  until this check has run). The dry run before asking checks its rows against the same rows of stage 6's CSVs; the
  report checks the full files after the runs and says so. A mismatch stops the stage and goes to the user.
- Suite before each commit to `julia/src`, in the background; files LF; the pinned same-run digests and xxl-v1 goldens
  pass unchanged.
- Run time: stage 6's runs took 48 s (book, 20 seeds), 19 min (xl) and 30 min (today) with `--jobs 5`; the observer adds
  some. My guess is under an hour in all. The dry run before asking says how long.

## Branch and approvals

Branch `xxl-culture` (worktree `.claude/worktrees/xxl-culture`), from main `5e5f69d`. Commits on the branch, merging,
pushing and every study run need the user's approval.
