# Sugarscape xxl, stage 6: sex — design

Status: draft, 2026-11-07. The user chose sex as the next stage and asked to skip the questions, so every choice below
that isn't quoted from the user is **my call**, marked as such, for the user to accept or change when approving.

## Intent

The xxl goal is a well-functioning simulation: the population rarely goes extinct, and sex, culture, trade, credit and
disease each work as intended (docs/xxl.md, stage 1). Survival, credit, disease and trade have had their stages. Sex
passes its one scorecard check (X1, births ÷ deaths 0.9–1.1, today 1.04), and nothing else about it has been examined.

**What "works as intended" means here (my call):** rule S works in xxl as it does in the book. That means:
1. **Births sustain the population.** X1 already says so.
2. **Births are limited by what the book's rules limit them by.** Those limits are age, the wealth test (sugar at least
   the agent's endowment, sugar only, the user's decision 2026-10-21) and an empty site for the child. The size of the
   world, and xxl's sparse look, should not be the limit.
3. **Inheritance and selection still act.** Children take their traits from their parents, and traits that help
   survival spread, as in the book's Chapter III.

The book's own 50 × 50 VI-1 is the reference for 2 and 3, as the book's rules at the book's scale. xl's VI-1 is a second
reference: the same world size, without xxl's rules.

## What we already know (from the stage-4 confirmation scorecard, seeds 20–39, read 2026-11-07)

| Periods | Population | Fertile share | Fertile with a mate in reach | Births per fertile agent per period |
|---|---|---|---|---|
| 1–25 | 15,897 | 0.081 | 0.225 | 0.093 |
| 26–50 | 9,601 | 0.107 | 0.109 | 0.110 |
| 51–75 | 8,688 | 0.132 | 0.169 | 0.164 |
| 101–150 | 21,971 | 0.102 | 0.312 | 0.241 |
| 401–500 | 62,227 | 0.102 | 0.325 | 0.158 |

- **Only about 10% of agents are fertile.** VI-1's endowments are 25–50, so a child's threshold averages about 37.5, while
  mean sugar is 27–37. Most agents of fertile age are too poor. That's the book's own wealth test, not an xxl effect.
- **Most fertile agents have no mate in reach:** about 70% late on, and 83–89% around the trough (t = 26–75). A fertile
  agent with a mate in reach has a child in about half of all periods late on, and in about every period near the
  trough.
- **The mate search looks at few sites.** Under round vision (rule 1) it checks the sites within the agent's speed
  (1–6), plus 4–20 random points out to its vision (10–50): about 30–130 sites against a vision disc of up to about
  7,850. So "no mate in reach" is partly the look's sampling, a look built for finding sugar. The book's look is sparse
  too (every site on four lines out to vision 1–5), and xl's samples one site per 10 along the same four lines, so
  whether xxl is worse than the book is open.
- **Selection:** mean metabolism falls from 3.0 to 1.00 by t = 500, as in xl. Mean vision rises only from 30.0 to 32.0,
  against xl's 30.1 to 47.2. xxl moves by speed, not vision, so weaker selection on vision may be intended. Speed, xxl's
  own inherited trait, isn't recorded.
- **Deaths late on are mostly old age** (731 of about 970 per period at t = 401–500), so the society isn't starving.

## Goals

1. **Part 1, a diagnosis.** Readings that say whether mate finding limits births in xxl more than the book's rules do
   at the book's scale, and whether selection acts. Part 1 can end the stage: if sex works as intended by the bars below,
   that's written up and the stage stops with no rule change.
2. **Only if Part 1 finds a problem:** a rule change, designed in its own spec after Part 1, with the user. Candidates
   (not built now): the mate search sees every agent in the vision disc, not just the sampled sites; fertile agents with
   no mate in reach move toward the nearest agent of the other sex they have seen. Picking among them waits for Part 1's
   readings.

## Non-goals and anti-goals

- **No change to the fertility test, endowments, childbearing ages or gifts.** These are the book's, and the
  sugar-only test is the user's decision.
- **More agents is not the goal.** Credit showed that a rule can raise population without working better (stage 3).
  A rule that adds births only by breeding agents who aren't fertile by the book's test would be a failure, even if
  population and X1 look better.
- **No change to `XXL_DEFAULTS` or `XXL_V1` in this stage's Part 1**, and none of the other stages' rules change.
- **Python, the runner and the viewer don't change.**
- **No study run without the user's go-ahead** (the user's standing rule). The test suite and scratch dry runs of a few
  periods are fine.

## Part 1: the readings

Three worlds, VI-1, seeds 80–99 (the seeds stage 5 screened on, unused for choosing any rule), 500 periods each (my
call):
- **book:** the Julia port's VI-1, 50 × 50, the book's rules;
- **xl:** the xl reference VI-1 the scorecard uses, run again with the observer (the scorecard's own xl folders have
  none);
- **today:** VI-1 under `XXL_DEFAULTS`.

An observer, like stage 5's `TradeReadings`, writes per-seed tables beside the standard CSV. It must change nothing in
a run: each seed's standard CSV stays byte-identical with the observer on and off (tested, as stage 5's was). Any random
draws it needs come from its own copy of the RNG, as the scorecard's X2 count does.

**Per period:**
- population; agents of childbearing age; of those, the share that pass the wealth test (fertile);
- fertile agents with a mate in reach, counted with the rule's own reach (the scorecard's X2 count, every period);
- **fertile agents with a fertile agent of the other sex anywhere within their vision**, on every site of the shape
  the world's own look is drawn from, not the look's sample (my call): the four lattice lines out to the agent's
  vision in the book and xl, the disc of radius vision in xxl. In the book the look already covers every site on the
  four lines, so there this count equals the one above. In xl and xxl it separates the look's sampling from true
  scarcity. The method is the builder's (a bucket grid is fine); it must be exact, not an approximation;
- births; mating attempts by outcome: a partner found and both fertile but no empty site, and a child born;
- distance between the two parents at each birth (mean and median, in sites and as a share of the seeker's vision);
- mean vision, mean metabolism, mean spice metabolism, and in xxl mean speed. Also their spread (sd), so a trait that
  has fixed is visible.

**Per agent, a snapshot:** every agent whose fertile age ends (or who dies) in t = 301–500 after reaching childbearing
age. For each: periods of childbearing age, periods fertile, periods fertile with a mate in reach, periods fertile with
a mate within vision, children, and its vision, metabolism and speed. (my call: a 200-period window is long enough to
hold many whole fertile lives of 25–45 periods. Stage 5's 20-period window was for a snapshot of living agents, a
different thing.)

## Part 1's bars (my call)

**Intervals (my call).** Seeds aren't paired across worlds. Each reading is a per-seed value (for a share, the seed's
total of the numerator over its total of the denominator in the window). A ratio of two worlds is the ratio of their
means over seeds. Its 95% interval comes from a bootstrap that resamples seeds within each world separately: 10,000
resamples, percentile interval, a fixed seed for the bootstrap so the report repeats. A seed that went extinct, or
that has no fertile agent-periods (or, for M2, no snapshot agent) in the window, is left out of that reading and
counted in the report. A world left with fewer than 15 of its 20 seeds reads the bar as missing, and a missing bar
decides nothing.

**M, mate finding limits births in xxl.** Decided at t = 301–500, by both of these:
- M1: the share of fertile agent-periods with no mate in reach is at least 1.5× the book's, with the interval of the
  ratio above 1;
- M2: among snapshot agents fertile for at least 5 periods, the share with no child is at least 1.5× the book's, with
  the interval above 1.

M1 is also read at the trough (each seed's lowest population, ± 25 periods) and reported beside it, deciding nothing.
A trough snapshot for M2 isn't kept (my call): fertile lives last 25–45 periods, longer than the trough window.

**S, selection acts.** Mean sugar metabolism's relative drop from t = 0 to t = 500, (start − end) ÷ start, is at least
half the book's. If the book's own drop is under 0.1, S reads "not judged" and decides nothing. Spice metabolism, vision
and (in xxl) speed are reported against the book and xl, not judged. Vision isn't judged because xxl moves by speed.

**Outcome:**
- **S fails or reads missing (with or without M):** reported to the user with the readings. No rule is proposed until
  we've talked.
- **M holds and S doesn't fail:** mate finding is a problem in xxl. The readings with a mate within vision say whether a
  search of the whole shape would be enough, or whether agents need to move toward mates. That choice goes to the user
  with a rule spec.
- **M doesn't hold and S doesn't fail:** sex works as intended in xxl. Written up in docs/xxl.md as "Stage 6: sex" and
  the stage stops.
- **M reads missing:** reported to the user; no outcome is drawn. M fails when either M1 or M2 fails, even if the other reads missing, because M holds only when both hold and a missing bar decides nothing; M reads missing only when neither fails and at least one is missing (my call, 2026-11-07).

**Book-scale caveat, to state in the write-up:** the book's world has its own density and look, so "1.5× the book's"
compares unlike worlds. xl is shown beside it to say how much is world size and how much is xxl's rules.

## How it's built (left to the builder, within these)

- In the Julia port only: `julia/src/xxl/` for the observer and the study's run and report, with a command line in
  `julia/` like `xxl_trade_study.jl`. Reusing stage 5's run, resume and fingerprint pieces is expected.
- The book run is a plain Julia VI-1 run (no xxl transform) with the observer. A folder per world, named and
  fingerprinted like stage 5's. A stopped seed is rerun from period 0.
- The report writes `results-julia-xxl/sex-part1.md`: the tables above per world, each bar with its value, interval and
  result, and the outcome by the rules above. The results folder is git-ignored.
- Tests: the observer changes nothing (byte-identical CSVs in all three worlds on a short run); hand-made worlds where
  every count above has a known value (a fertile pair out of the look's sample but within vision, a pair with no empty
  site, a birth at a known distance); the report on hand-written folders, including a bar that reads missing.
- Suite before each commit to `julia/src`, in the background; files LF; the pinned same-run digests and xxl-v1 goldens
  pass unchanged.
- Rule S keeps no log, so counting attempts with no empty site, and knowing which parent was the seeker, needs a hook
  in `mate!` (`julia/src/rules/sex.jl`). That's allowed, provided it costs nothing and draws nothing when no observer
  is attached, and the pinned digests show it.
- Run time: my guess is an hour or a little more for the three worlds, most of it today's and xl's VI-1; the book's
  takes minutes. The dry run before asking says how long.

## Branch and approvals

Branch `xxl-sex` (worktree `.claude/worktrees/xxl-sex`), from main `c0b0312`. Commits on the branch, merging,
pushing and every study run need the user's approval.
