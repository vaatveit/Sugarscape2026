# Sugarscape xxl, stage 2: the chance of extinction — Design

Stage 2 of the revised xxl rules (`docs/superpowers/specs/2026-10-29-xxl-revised-design.md`). That spec named this
stage "contact and demography: meeting, mating, births" and left its spec for later. This is that spec, with its
goal changed by the user.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of
mine.

## Intent

The user's goal for xxl: a well-functioning simulation in which the population rarely goes extinct. Asked what a
healthy society looks like at its lowest point, the user answered that it is **one that doesn't go extinct**, and
set the bar: **less than a 5% chance of extinction, over 2,000 periods** (the user's).

So stage 2 does not set out to raise contact between agents. It finds out whether the society is already safe by
that bar. Rules change only if the test shows they must, and then in a later spec.

### What is known already

Under `XXL_DEFAULTS`, on VI-1, over seeds 0–39 and 500 periods (`docs/xxl.md`, "Stage 1"):

- No seed goes extinct. On seeds 20–39 the lowest population is 3,956–8,476 of 20,000 founders (S2 0.198–0.424).
- The end population is 47,990–71,020, and births keep up with deaths (X1 1.044).
- At the lowest point about 1 fertile agent in 6 can see a fertile mate (X2 0.16), far below the 0.5 the check asked
  for. The society survives this.

This leaves two gaps against the bar:

- **Too few seeds.** No extinctions in 40 seeds bounds the chance only below 7.2%, at 95% confidence.
- **Too short.** Nothing has run past 500 periods, so a slow decline, or a late collapse, would not have shown.

## Goals

1. A test of the bar: 60 VI-1 runs of 2,000 periods under `XXL_DEFAULTS`, and a report with the verdict.
2. X2 stops being a target; the scorecard still reports it (the user's).
3. The result recorded in `docs/xxl.md`.

## Non-goals

- Any change to the rules or to `XXL_DEFAULTS`. If the test fails, the next step is the user's decision and its own
  spec. This includes contact rules, whatever X2 reads.
- Other experiments. "The society" is VI-1, the one scorecard experiment with births (*my call*). II-4 and IV-A3 stay
  under S4 and S5.
- Other thresholds. X1, S1–S5 and the rest of the X checks stay as they are.
- Stages 3 and 4 (economy, disease).
- Python, the viewer, FLAME GPU. Julia only, as in stage 1.

## The test

**The claim:** the chance that a VI-1 run under `XXL_DEFAULTS` goes extinct within 2,000 periods is below 5%.

**Extinct** means the population reaches 0 at any period from 1 to 2,000. This is how the scorecard already defines
it (S1).

**The passing rule:** the one-sided 95% upper confidence limit (exact binomial, Clopper–Pearson) on the chance of
extinction is below 5% (*my call*: the user said "less than 5%", and a finite sample can only show that up to a
confidence level; 95% is the usual one). With no extinctions the limit is 1 − 0.05^(1/n):

| Seeds, no extinctions | Limit |
|---|---|
| 40 | 7.2% |
| 58 | 5.03% |
| 59 | 4.95% |
| 60 | 4.87% |

**Seeds: 20–79, all new runs** (*my call*).

- 60 rather than the minimum of 59, so the batches come out even at 6 × 10.
- Seeds 0–19 are left out because they chose the defaults, so their surviving is not independent evidence. Seeds
  20–39 only confirmed the choice, so they stay in.
- Seeds 20–39 must be run again: they stopped at 500 periods and the runner cannot continue a finished run.

**Workers: 10** (the user's), so the machine stays usable.

**Any extinction means the test fails.** With 60 seeds a single extinction already puts the limit above 5%: at 1
extinction the bar takes at least 93 seeds. So:

- The run continues after an extinction, because the number of extinctions matters to what happens next (*my call*).
- A failing test is not re-run with more seeds until it passes. It is reported, with what the extinct seeds did
  (when they fell, and how low the others went), and the user decides (*my call*).

### What the report says

The verdict, and for each seed: lowest population and its period; population at t = 500, 1,000, 1,500 and 2,000;
extinct or not, and when; births and deaths over the last 200 periods.

Over all seeds: the number extinct, the upper limit, wall time, and the rules and seed range.

**A warning for slow decline, which does not change the verdict** (*my call*). A seed can be alive at t = 2,000 and
still be on its way out, so the bar alone would miss it. For each seed the report gives mean population over
t = 1,001–1,500 against t = 1,501–2,000, and it states plainly how many seeds fell by more than 10%. If most did, the
2,000-period answer is passing but says little about longer runs, and the summary must say so. The 10% is a
reporting line, not a threshold.

## How it runs

A separate script, `julia/xxl_extinction.jl` (*my call*, and the user was told): it needs one experiment and whether
the population hits zero, not the scorecard's reference runs or checks.

```
julia --project=julia julia/xxl_extinction.jl --rules defaults --seeds 60 --first-seed 20 --periods 2000 --jobs 10
```

- **No scorecard columns.** The standard columns give the population, and births through `agents_ever`. Leaving the
  scorecard columns off also skips X2's looks, which is most of what the run can save.
- **Outputs** go in `results-julia-xxl/` (git-ignored): a folder of per-seed CSVs, and a `.md` report of the same name,
  named with the rules, seed range and periods, so it never overwrites a scorecard.
- **A long run must survive being stopped** (*my call*). The estimate is 4–8 hours, so a reboot or crash must not lose
  finished seeds. Each seed's result is written when it finishes, and a re-run skips seeds already done with the same
  rules, periods and code fingerprint. How this reuses the runner's existing fingerprint is left to the builder.
- **The report can be rebuilt from the CSVs** without running anything.

**Run time.** About 4.2 hours at the measured pace (1.25 s per period per seed with 10 workers, seeds 20–39 over 500
periods). Possibly up to about 8, if the later periods, at 50,000–70,000 agents, cost up to twice the 500-period
average. This is an estimate. The first finished batch gives a real figure, and the script prints it.

## X2 stops being a target

The check stays and keeps its value and per-seed detail, but it has no threshold and no pass or fail (the user's).

- `score` in `julia/src/xxl/scorecard.jl`: X2 reports a value with "reported only" as its result, and does not count
  in the total. Reports say "Passing: 13 of 14 checks".
- The stage-1 spec's X2 row and `docs/xxl.md` say so. Past reports aren't re-run. X2 failed in every setting scored,
  so the counts of checks passed stay as recorded; the docs note that they were out of 15 and that 14 now apply.
- The stage-1 spec's stage table gets stage 2's new name and a pointer here.
- **Existing tests change:** `test_xxl_scorecard.jl` pins X2's threshold and the total of 15. Those assertions are
  rewritten to pin the new behaviour. Approving this design approves that change.

## Testing

- **The limit:** 0 of 59 is below 5% and 0 of 58 is not; 1 of 93 is below 5% and 1 of 92 is not; and 0 of 0 does not
  pass.
- **Extinction detected:** a small world that cannot feed anyone reports the seed as extinct, with the right period,
  and the verdict fails. A small world that feeds everyone passes it if the sample is large enough, and otherwise
  says too few seeds.
- **Resume:** a stopped run picks up without re-running finished seeds, and ends with the same report as an unbroken
  one. A change of rules or periods doesn't reuse them.
- **The rules are the defaults:** a seed's population over its first 500 periods matches the same seed in the
  `defaults-x2sight` scorecard run. Check this on seed 20 before the long run starts; the runs are deterministic, so
  a mismatch means the test is running something else.
- **Short smoke run:** 2 seeds × 20 periods end to end, through the script.
- The existing suite stays green, with X2's assertions changed as above.

## When the test has to be repeated

Any later stage that changes `XXL_DEFAULTS` re-runs this test before it is called done, because the claim is about
the rules as they stand (*my call*). At 4–8 hours per run, the test isn't repeated while tuning, only on a final
choice.

## Who runs it

The same session that builds the script launches the long run (*my call*), in this order:

1. Build and test everything, including X2's change and its wording in the docs.
2. Pass the short smoke run and the seed-20 check. A failure stops here; the long run does not start.
3. Launch the long run in the background, with the machine kept awake.
4. Write the verdict and evidence into `docs/xxl.md` from the finished report.

Commits follow the user's standing rule, which needs approval for each. The user approved the plan's commit steps on
this branch on 2026-10-30, by telling the session to start executing once the plan was reviewed. Nothing is merged or
pushed without further approval.

## What happens after the run

- **Passes:** stage 2 is done with no rule changes, and the evidence goes in `docs/xxl.md`. Stage 3 (economy: X8) is
  next.
- **Fails:** the report and a short account of the extinct seeds go to the user, who decides whether to change rules,
  and which, under a new spec.

## Left to the builder

- The script's internal structure, and how much it shares with `run_scorecard` and the runner.
- Names of the report's columns and the CSV details, as long as the report carries what's listed above.
- How the exact limit is computed. No new dependency: a few lines of bisection are enough.
