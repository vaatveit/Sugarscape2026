# Sugarscape xxl, stage 3: what credit adds — Design

The second step of stage 3 of the revised xxl rules, after "Stage 3: what X8 measures" in `docs/xxl.md`. The user read
those findings and chose: **retire X8 and study credit** (the user's). So this has two parts: a small change to the
scorecard, and an investigation that changes no rule in `XXL_DEFAULTS`.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of mine.

## Intent

The overall goal is a society where credit, like sex, culture, trade and disease, works as intended. The last step found
that X8 can't tell us whether it does, and left this picture (seeds 20–24 to t = 500, credit off against credit on):

| | Ratio | By seed |
|---|---|---|
| Births, t ≤ 100 | 0.749 | 0.688–0.801, lower in all 5 |
| Trough | 0.848 | 0.801–0.884, lower in all 5 |
| Births, t ≤ 500 | 0.982 | 0.867–1.058 |
| Population at t = 500 | 0.989 | 0.879–1.082 |

Credit lifts the trough, the one close call in stage 2. After that, 5 seeds can't detect what it does, at about 726,000
loans per seed. Four things are unknown:

1. **Does survival depend on credit?** The trough is 15% lower without it, but nobody has run credit off past t = 500. The
   user's bar for a healthy society is under a 5% chance of extinction in 2,000 periods.
2. **Is the effect a head start, or does anything last?** Population with credit off runs about 11–14 periods behind
   credit on at t = 100–200 (a rough reading from the same 5 seeds, nearly all positive). Past t = 300 that reading is
   noise, because the curve has flattened.
3. **Why does credit lift the trough?** There are two candidates. Loans may bring children forward. Or dead lenders may be
   handing sugar to young borrowers: 36% of loans that end by t = 100 end with the lender's death, and the borrower keeps
   0.95 of the principal, much as inheritance would, and inheritance has the largest lift in early births (1.347).
4. **What limits credit?** A new loan can't exceed 5 periods of the borrower's present income, by the creditworthiness rule
   (our reading of p.132). Is that why it adds so little? Separately, a lender past childbearing age may lend half its
   current wealth at each request, with no limit per period. Lenders starve of sugar 1.51 times as often as similar agents
   (3,370 deaths against 2,234 expected), and those deaths void 9.3% of the loans a dead lender voids.

**My guess, written before measuring** (*my call*), so the study can show it wrong: with credit off, 0 of 60 seeds go
extinct and the population at t = 1,501–2,000 stays within 5%, so survival doesn't depend on credit and its effect is a
head start. At least half the trough's lift comes from dying lenders' sugar. Bigger loans lift the trough further, and
don't change the later population.

## Goals

1. **Retire X8:** it stays on the scorecard as a reported value with no threshold, as X2 did (the user's).
2. Answer the four questions above for `XXL_DEFAULTS` on VI-1.
3. The findings and a recommendation in `docs/xxl.md`, with the question of what to change put to the user.

## Non-goals

- Any change to `XXL_DEFAULTS` or to what a default run does. The probes below are measurements, not candidates being
  adopted. Adopting any of them is the user's decision and its own spec.
- A new credit check on the scorecard. What it should test depends on this study's answer, so it waits.
- Re-running stage 2 or stage 3's runs. They are the credit-on side of every comparison here.
- Trade, disease (stage 4) and X2. Python, the viewer and FLAME GPU: Julia only, as in stages 1–3.

## Anti-goals

- **Reading a pass as a result.** With X8 gone, the scorecard's only credit check is X7, that loans exist. It will read 13
  of 13 under the defaults. That says X8 no longer counts. It doesn't say credit works, and the docs have to say so.
- **Calling a gap in the data "no effect".** Every comparison prints its interval. A difference the seeds can't resolve is
  reported as that.
- **Changing the run by adding options.** With the new options at their defaults, a run's CSV must stay byte-identical.

## Part 1: retire X8

The same change as X2 (commit `9da7954`, and "X2 stops being a target" in
`docs/superpowers/specs/2026-10-30-xxl-extinction-risk-design.md`):

- `score` in `julia/src/xxl/scorecard.jl`: X8 keeps its value and per-seed detail, with no threshold and no pass or fail.
  Reports say "reported only" and leave it out of the total: "Passing: 13 of 13 checks" under the defaults.
- Its title changes from "Loans are repaid" to "Loans voided by a death" (*my call*), since it no longer tests that loans
  are repaid.
- `julia/test/test_xxl_scorecard.jl`: X8's pass-and-fail pair goes, as X2's did, and a test that it is reported only takes
  its place. Retiring X8 also breaks three assertions that assume X2 is the only reported check: `"Passing: 14 of 14
  checks"`, `count(c -> c.reported_only, checks) == 1`, and the "every check passes or names seed 1" line, which X8 doesn't
  meet because it isn't gated on extinction. They change to match (*my call*: the user's choice to retire X8 authorizes
  these changes and no other tests).
- The stage-1 spec's X8 row and `docs/xxl.md`'s table say so. Past reports aren't re-run, and the counts of checks passed
  stay as recorded; the docs note that those were out of 15 or 14, and that 13 now apply. `docs/xxl.md`'s sentence saying
  X8 is part of the baseline for stages 3 and 4 is corrected.

## Part 2: the study

### The main run: credit off, to the user's bar

**`XXL_DEFAULTS` with credit off, VI-1, seeds 20–79, 2,000 periods** (*my call*):

- These are stage 2's seeds, so each pairs with a credit-on run already on disk
  (`results-julia-xxl/extinction-defaults-s20-60-p2000/`), and no credit-on seed needs running again.
- The verdict uses the same test as stage 2: extinct at any period from 1 to 2,000, and the same one-sided 95% exact limit.
  Stage 2 needed all 60: at 0 extinct the limit is 4.87%, and fewer seeds can't get under 5%.
- **What 60 seeds can resolve depends on whether seeds stay paired, which nobody knows yet** (*my call to accept this*).
  Over the 60 credit-on seeds, the population at t = 1,501–2,000 varies by 13% from seed to seed, and a seed's level
  persists (correlation 0.94 with its own t = 301–500). The 5 no-credit seeds stayed tightly paired through the trough
  (0.80–0.88) but not by t = 500 (0.88–1.08). If a credit-off seed doesn't share its partner's later level, the comparison
  at t = 1,501–2,000 reads about ±4.7%. That can rule out an effect much above 5%, and can't show one is below 5%. Settling
  that would take about 280 seeds per side, several days of runs, including new credit-on seeds, and I don't think it's
  worth it: the extinction verdict needs only these 60, and "credit changes later population by no more than about 7%" is
  already a useful answer. The findings say which it was.

It runs on `julia/xxl_extinction.jl`, which gains `--no-credit`. That tool already resumes from checkpoints and stops
cleanly on its stop file, which suits a long run on a machine shared with other work.

### The probes: why, and what limits it

**Seeds 20–29, 500 periods, one change at a time from `XXL_DEFAULTS`; the claims probe uses seeds 20–39** (*my call*). Each
answers one question and none is a proposal. Credit on and credit off are the same seeds from the runs above, and t ≤ 500
of a 2,000-period run is the same run.

| Probe | Change | Question |
|---|---|---|
| Inheritance, credit on | `inheritance = true` | With the next one, the 2 × 2 of credit and inheritance |
| Inheritance, credit off | `inheritance = true`, `credit = nothing` | What passing on wealth does with no loans at all. Does credit add anything once it's there? |
| Claims outlive the lender | A dead lender's loans aren't voided: the borrower still pays when due, and that sugar leaves the world | Takes away the gift from a dying lender and keeps the loan. How much of the trough's lift is left? |
| Bigger loans | The creditworthiness test doubles what income can carry: `income × d × 2 − owed ≥ due` | Does the income limit hold credit back? |
| Lender limit | A lender may lend at most half its wealth in a period, in all, as measured at its first loan of that period | Does the lack of a limit starve lenders, and does a limit cost children? |

**Why these seeds** (*my call*). So far the trough stays paired, with a spread of about 0.033 per seed, so 10 seeds should
read it to about ±2.4%. Total births may read only to about ±12% at 10 seeds if unpaired. So these probes can answer questions about the
trough and early births, and can't answer whether births move by 5%. The claims probe's question turns on lift kept, whose
interval is wider: about ±0.2–0.25 at 10 seeds, which couldn't tell the 0.5 line from most results, so it gets 20 seeds,
for about ±0.15. A probe that looks promising gets more seeds later, under its own decision.

**Confounds the findings have to state:**

- Inheritance passes on wealth, not only loans, and concentrates it (Gini 0.387 against 0.241 at t = 500).
- In the claims probe, sugar leaves the world, which the book's rules never do, and borrowers end up poorer than under
  either the book's rule or inheritance. It tests where the lift comes from. It isn't a sensible rule.
- Bigger loans also raise what a borrower owes against its income, so more should roll over and more may starve. The
  report prints rollovers and deaths with the trough.
- The lender limit changes the first lender a borrower meets, and so who lends.

### What gets built

- **Three options on `Config`, off by default** (*my call*): `claims_outlive_lender` (false), `credit_reach` (1.0) and
  `lender_limit` (false), with validation in the style of `config.jl`'s, needing `credit`. Their rule code goes in
  `julia/src/rules/credit.jl` and the death path in `model.jl`. They aren't `XxlRules` fields, so `--set` doesn't reach
  them, as with `credit` and `inheritance` in the last step.
- **`julia/xxl_extinction.jl`** gains `--no-credit`, `--inheritance`, `--claims-outlive-lender`, `--credit-reach K` and
  `--lender-limit`. All of it is in the run's fingerprint and the folder is named by `--label`. Every run above goes
  through this tool, for its checkpoints (*my call*).
- **`julia/xxl_loan_trace.jl`** gains `--credit-reach` and `--lender-limit`, for the bigger-loans and lender-limit probes:
  their reading needs the tracer's census and cause of death, and rollovers. Those two probes run on it and not on the
  extinction tool. The claims probe stays off the tracer, whose chains assume a dead lender ends the loan (*my call*).
- **A comparison: `julia/xxl_credit_compare.jl`** (*my call*), reading only finished CSVs, so it runs nothing and can be
  rerun freely. It pairs seeds between two folders and prints, for each probe against a base:
  - For population means and births, by window (t ≤ 100, 101–200, 201–300, 301–500, 501–1,000, 1,001–1,500, 1,501–2,000,
    where the run reaches them), and for the trough: the ratio of means, a 95% bootstrap interval, the per-seed range, and
    how many seeds are below the base. The bootstrap resamples seed pairs, 10,000 times from a fixed random seed, so a rerun
    prints the same figures and it holds whether or not seeds stay paired. A mean of per-seed ratios reads about 1.7% high
    when they don't, so it isn't used. `docs/xxl.md`'s earlier figures are means of ratios, and the findings say so where
    they set the two side by side.
  - Births per head by window.
  - The lag at t = 100, 150, 200: how many periods behind the base the probe's population is, each smoothed over 11 periods.
  - Each folder's extinction count and the shared seeds' count. It says so if the folders aren't the same length, and it
    compares only what both reach.
  - For the 2 × 2 and the claims probe, the lift kept: (probe − credit off) ÷ (credit on − credit off), for the trough and
    for births at t ≤ 100, from means over seeds, with the same bootstrap over seed triples.
  Deaths come from births and the change in population, as `extinction.jl` does. These CSVs have no cause-of-death columns.

## How the findings are read

Set out now so the result can't pick its own reading (*my call*). These are reporting lines, not thresholds.

**Every interval reads one of three ways against its line:** wholly on one side, wholly on the other, or straddling it. A
straddle reads "the seeds couldn't settle it", and the findings give the largest effect the interval rules out. It is never
read as "no effect" or as the guess holding.

| What the runs show | Reading | Likely recommendation to the user |
|---|---|---|
| Credit off: limit under 5% | Survival doesn't depend on credit, by the user's bar | Credit can be judged on what else it does; say how close the lowest seed comes |
| Credit off: limit at or over 5% | Credit is part of why the society survives | Credit stays; its job is at least this, and stage 3 protects it |
| Population ratio's interval, t = 1,501–2,000, is inside 0.95–1.05 | No lasting effect on the society's size above 5% | Credit is a head start, if the early rows hold |
| That interval is wholly above 1.05 or wholly below 0.95 | A lasting effect, of that size | The fade seen so far was only a lack of seeds, and this finding replaces it |
| That interval straddles 0.95 or 1.05 | Couldn't settle the 5% line | Say what it rules out. This is the likely result if seeds don't stay paired |
| Claims probe: lift kept in the trough, interval wholly under 0.5 | The lift comes mostly from dying lenders' sugar, not from timing | Credit is working as a wealth transfer; inheritance may do that job better, so test it on its own |
| Claims probe: interval wholly over 0.5 | Loans themselves lift the trough more than the transfer does | The transfer isn't the main reason |
| Claims probe: interval straddles 0.5 | Couldn't say which matters more | Say whether either alone is ruled out: an interval that excludes 0 or 1 still tells us something |
| Inheritance, credit off: trough against credit on with no inheritance, interval wholly above 1 | Inheritance alone does more than credit for the trough | Weigh that against what it does to wealth |
| That interval straddles 1 | About the same, to within the interval | The same weighing, more cautiously |
| That interval wholly below 1 | Credit does more for the trough than inheritance alone | Inheritance is no substitute |
| Bigger loans: trough interval wholly above 1 | The income limit holds credit back in the trough | Consider it, under a new spec, with rollovers and deaths |
| Bigger loans: interval straddles 1 | No lift the seeds could detect; give the largest it rules out | The limit doesn't look like the lever, within that size |
| Bigger loans: interval wholly below 1 | Bigger loans hurt: the debts cost more than the sugar helps | Say so, with rollovers and deaths |
| Lender limit: lenders' matched sugar ratio at or under 1.1 (with its counts), and trough interval doesn't fall wholly below 1 | The missing limit was starving lenders, and no cost to the trough can be detected | Consider it, under a new spec |
| Lender limit: otherwise | Either it doesn't help or it costs too much | Say which |

A result can fall under more than one row. The report says which, with numbers.

**The question this leaves to the user** (the user's, when the findings arrive): if credit turns out to be a head start and
survival doesn't need it, does helping the society through its worst period count as "working as intended", or should
credit do more? The study supplies the figures. It doesn't settle that.

## The runs and their cost

Everything is checkpointed or quick, and heavy runs go one at a time. Memory is watched as in stages 2 and 3: stop only
this run's Julia tree, on free memory under 1 GB for two polls in a row, or commit headroom under 0.5 GB.

- **Main run:** the last step's no-credit seeds took 796–945 s per 500 periods with 4 workers, and later periods are slower
  as the population grows. Stage 2's credit-on seeds took 2,337–5,535 s for 2,000. So I estimate 12–17 hours for 60 seeds
  with 4 or 5 workers. A stop loses at most 100 periods per running seed.
- **Probes:** about 40–50 minutes each at 10 seeds and about 90 for the claims probe, about 5 hours in all.
- **No edit under `julia/src` while runs are unfinished:** the fingerprint holds the source's hash. So all code is finished,
  tested and reviewed before the main run starts.

## Testing

**The default run is unchanged** (the check that matters most). With the new code and options off, seed 20 over 500 periods
is byte-identical to `results-julia-xxl/extinction-defaults-s20-60-p2000/seed20.csv` over its first 502 lines. A failure
stops here and no long run starts. Default-off checkpoints still resume.

**Small worlds with known answers:**

- `claims_outlive_lender`: a lender dies mid-term and the loan stands; at the due date the borrower pays the amount due, no
  living agent receives it, and total sugar falls by it. A borrower's death still voids. An unpaid loan rolls over as usual.
  Lender and borrower dying together still voids. `inheritance` with it is rejected at validation (*my call*: they answer
  the same death two ways).
- `credit_reach`: at 1.0 a loan at the limit passes and one just over doesn't, as now; at 2.0 the limit doubles.
- `lender_limit`: a lender past childbearing age lends at most half its wealth over several requests in a period; the next
  period it may lend again. Off, today's behaviour holds. A childbearing lender's "beyond what children need" still applies,
  within the same limit.
- `--no-credit` and the other flags reach both configs, and a change of flag refuses an existing folder under the same label.

**The comparison, on hand-made CSVs:** a pair with a known ratio; the bootstrap prints the same interval on a rerun and
narrows as seeds are added; an interval reads the right one of its three states at each side of a line; lift kept with its
interval on a known triple; folders of different lengths; seeds that don't all match; an extinct seed, which has no ratio
for later windows, is counted and said so; the lift kept when credit on equals credit off, which prints a dash, not a number.

**Part 1:** the scorecard's total leaves X8 out and its row prints "reported only".

The existing suite stays green, with only the X8 changes in Part 1 touching existing tests.

## Deliverables and order

1. A new branch `xxl-credit-study`, from `xxl-x8-investigation` (*my call*), because the tracer and findings aren't on `main`
   yet. Merging either branch is the user's decision.
2. Part 1, then the options, flags and comparison, with tests and a whole-branch review.
3. The gate above, then the main run, then the probes.
4. The findings and a recommendation in `docs/xxl.md`, a new section "Stage 3: what credit adds", stating: the guess and
   whether it held; which rows fired; whether seeds stayed paired, and so what the 60 seeds could resolve; the limits (one
   map pair, 10 or 20 seeds on the probes, not randomized); that the census readings are from the 5-seed no-credit run; the
   real run time with any stops, from logs.

Commits follow the user's standing rule, which needs approval. Nothing is merged or pushed without it.

## Left to the builder

- How the three options are carried in the rule code, as long as nothing moves when they're off.
- How `claims_outlive_lender` keeps a dead lender's loan on the book: `Loan` holds the lender, so a dead one can stay, but
  `m.lent` and the settle path must cope, and the sugar paid must leave the world rather than reach a dead agent.
- The comparison's table layouts and function names, and whether the `--no-credit` plumbing shares `trace_experiment`.
- Whether the extinction report's verdict prints for a probe's 10 seeds at 500 periods. It means little there, so it may say so.
