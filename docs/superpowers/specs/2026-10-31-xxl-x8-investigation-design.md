# Sugarscape xxl, stage 3: what X8 measures — Design

The first step of stage 3 of the revised xxl rules (`docs/superpowers/specs/2026-10-29-xxl-revised-design.md`, "Economy:
trade and credit"). It is an investigation, not a rule change. It follows the pattern of stage 2: find out what is true,
report it, and let the user decide what changes.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of
mine.

## Intent

X8 is the one scorecard check still failing under `XXL_DEFAULTS`: 24.9% of VI-1's loans end voided by a death, against
the 20% allowed. It has failed in every setting tried (0.235–0.313, `docs/xxl.md`). The user asked for a design for
investigating it (**the user's**).

Nobody yet knows whether that number is a credit problem. Three things make it doubtful:

- **The 0.2 is not a measurement.** The stage-1 spec calls every threshold *my call* and provisional. X8 has never been
  measured under xl or the book's world, so nothing says what a healthy reading is.
- **A void is not a default.** A loan is voided if either party dies before it is due. A borrower who dies costs the
  lender. A lender who dies frees the borrower from paying, which the book intends (p.133). X8 counts both alike.
- **Lenders are often old by design.** An agent past childbearing age may lend half its wealth (p.132), and such agents
  are the ones closest to dying of old age.

So the question is not "how do we get X8 under 0.2?" It is **"what does X8 measure, and is credit working?"**

### What credit is meant to do

*My call*, from the book (pp.131–133; `docs/book-notes.md`): credit lets agents of childbearing age who are short of
sugar have children, paid for by those with sugar to spare, on terms that pay the lender. It is working if loans reach
such agents, are mostly repaid by borrowers who live, and lead to children.

### What is known already

From the existing scorecard CSVs: `XXL_DEFAULTS`, VI-1, seeds 20–39, 500 periods, mean per seed. No new runs.

| Loans | Per seed |
|---|---|
| Started | 716,512 |
| Repaid | 523,066 |
| Voided | 173,156 |
| On the book at the end | 20,290 |
| Rollovers (not an end: the chain goes on) | 5,854 |

Those reconcile exactly: repaid + voided + on the book = started.

- **Borrowers who reach the due date can almost always pay.** Only 1.1% of due loans roll over. So "the borrower can't
  pay" is not the failure here. Dying first is the only other way a loan fails.
- **Most deaths are old age:** 71.6% old age, 24.8% spice, 3.6% sugar, none killed. About 1.5% of the population dies
  per period.
- **Loans last long enough to meet those deaths.** VI-1 uses `L10,10`: 10 periods at 10% simple interest, so 2× the
  principal is due. A crude estimate from mortality alone, two parties each dying at the population's average rate
  over about 10 periods, is 1 − (1 − h)²⁰:

  | Periods | X8 in that window | Crude estimate | Deaths per agent per period (h) |
  |---|---|---|---|
  | 1–50 | 0.453 | 0.465 | 0.0308 |
  | 51–100 | 0.367 | 0.314 | 0.0187 |
  | 101–200 | 0.261 | 0.195 | 0.0108 |
  | 201–350 | 0.247 | 0.254 | 0.0145 |
  | 351–500 | 0.242 | 0.268 | 0.0155 |

- **X8 moves with mortality across settings.** Over the 20 scorecard folders on disk, X8 and the death rate correlate
  at 0.84. Those settings aren't independent, and some are the same rules scored twice, so this is a lead, not proof.

**My guess, written down before measuring:** X8 is mostly a reading of how long agents live, and most voids come from
old lenders. The estimate above ignores age and misses by up to 0.07, so this may be wrong. The design has to be able
to show that it is.

There is one lead the other way: a quarter of deaths are from spice, while loans are in sugar only (`rules/credit.jl`).
A borrower can be lent the sugar to have a child and still starve of spice.

## Goals

Answer these four questions, for `XXL_DEFAULTS` on VI-1:

1. **Who dies?** Of the voided loans: borrower, lender or both; the cause of death; the dead party's age; how far into
   the term.
2. **Is a loan riskier than its parties' ages explain?** Observed voids against what age-specific mortality predicts,
   for each side. And how many loans were doomed from the start: a party certain to die of old age before the due date
   (agents don't know their `max_age`; the investigation does).
3. **What does it cost, in sugar?** X8 counts a loan of 0.1 sugar the same as one of 50. The share of principal voided,
   by which side died; what lenders get back overall; what borrowers keep when a lender dies.
4. **Does credit do its job?** Who borrows and who lends; the share of loans whose borrower has a child during the term;
   and what happens to births, the trough and the population with credit off.

Then a recommendation to the user, and the findings in `docs/xxl.md`.

## Non-goals

- Any change to `XXL_DEFAULTS`, to the rules, or to X8's definition or threshold. Changing any of those is the user's
  decision and its own spec. The probes below are measurements, not candidates being adopted.
- A re-run of the extinction test. Nothing here changes the rules it tested.
- Trade (X5, X6 pass), disease (stage 4), and X2.
- Python, the viewer, FLAME GPU. Julia only, as in stages 1 and 2.

## Anti-goals

- **Passing X8 by making credit worse.** Shorter terms or fewer lenders would raise the check while fewer children get
  financed. A result that passes X8 and shrinks credit's job is a failure.
- **Moving the limit because it's inconvenient.** If the recommendation is to change the check, it has to say what the
  new check measures and show the evidence. It can't just report that 0.25 is fine.
- **Changing the run by measuring it.** The tracer may not draw random numbers or alter a loan.

## What gets built

### A loan tracer

An opt-in record of every loan's life, following the chain of a loan and its rollovers as one loan, the way X8 counts.
Off by default; ordinary runs and their CSVs don't change. It records:

- **At the start:** period; each party's id, age, `max_age`, sex, childbearing state and sugar; the borrower's income;
  principal and amount due; whether either party is certain to die of old age before the due date.
- **At the end:** period; how it ended (repaid; voided by the borrower, the lender or both); rollovers; sugar paid to the
  lender in all; the dead party's cause of death, with the scorecard's categories and order (`scorecard_metrics!`);
  whether the borrower had a child during the term.
- **Still on the book when the run stops:** counted as unfinished, like X8.

**Tallies, not one row per loan** (*my call*). A 2,000-period seed makes about 5 million loans, which is too much to hold
in a worker or to read back. Each seed writes fixed tables per window of periods, plus every loan whose chain number is
divisible by 100 as a raw row, for questions nobody thought of. Choosing by number draws no random numbers. Those tables
include started loans by the two parties' age bands together, which the prediction below needs.

### A census, for fair comparisons

Age alone is not a fair baseline. Borrowers are picked because they are short of sugar, so they may starve more with or
without a loan, and that would look like a credit defect. So every 50 periods the tracer takes a census of the living
agents, and follows each for d + 1 periods, d being the loan term (*my call*). A loan faces d + 1 old-age checks before
it is settled (`step!` ages and kills before `settle_loans!`), so following for d would undercount deaths by about a
tenth and move the ratios below by as much. 50 periods apart keeps the cohorts from overlapping. It draws no random
numbers.

Each agent in a census goes in a group by 5-year age band and state:

- **Borrowing:** owes on a loan.
- **Lending:** is owed on a loan.
- **Could borrow:** of childbearing age, short of sugar, income above 0, and not on a loan.
- **Could lend:** has sugar to lend (`available_to_lend` above 0), and not on a loan.
- **Everyone else.**

An agent both borrowing and lending counts in both groups. For each group the tracer records how many died within the
term, by cause (old age, sugar, spice, killed), and how many had a child.

That gives two ratios for question 2, each by side and by cause:

- **The age ratio:** observed voids ÷ what mortality at those ages predicts, using all agents in the census and the
  started loans' age bands. It says whether borrowers and lenders die more than other agents their age, for any reason.
- **The matched ratio:** the death rate of borrowing agents ÷ could-borrow agents of the same band, and of lending ÷
  could-lend. It is the nearer reading of what the loan itself does.

It also gives question 4 its comparison: the share with a child among borrowing agents against could-borrow agents.

**The groups aren't randomized.** A could-borrow agent may have no lender nearby, or income too low to qualify, so the
matched figures are evidence and not proof, and the report says so. The no-credit probe is the check on them.

### A script and a report

`julia/xxl_loan_trace.jl` (*my call*), like `xxl_extinction.jl`. Finished seeds are kept and a re-run skips them, using
the same whole-seed fingerprint. Results go in `results-julia-xxl/` (git-ignored), as a folder and a `.md` report per
run. The report can be rebuilt from the folder without running anything.

**No checkpoints in traced runs** (*my call*). A seed takes about an hour, and a resume that lost the tracer's state
would give wrong tallies with no warning. So traced runs never pass `checkpoint`, a stopped seed restarts from period 0,
and an unfinished seed's files are never read. The cost is up to an hour per running seed at each stop.

## The runs

**The main run: `XXL_DEFAULTS`, seeds 20–29, 2,000 periods.** It answers questions 1–4 (*my call*):

- These seeds already have 500-period scorecard runs and 2,000-period extinction runs to check against (see Testing).
  This is not a test of a probability, so fresh seeds buy nothing.
- X8's spread over seeds is narrow (0.236–0.276), so 10 seeds are enough.
- 2,000 periods because the stage-2 runs reach about 1.7% deaths per period by the end, against 1.5% over the first 500,
  so X8 may read higher later. The report gives t = 1–500 (the check's own window) and t = 501–2,000 separately.
- The trough (t ≤ 100) is reported apart too, since its mortality is about twice as high.

**The probes: seeds 20–24, 500 periods each, one change at a time from `XXL_DEFAULTS`** (*my call*), except the last
two, which are the reference worlds. Each answers one question, and none is a proposal:

| Probe | Change | What it tells us |
|---|---|---|
| Shorter term | `credit = (5, 10)` | Does X8 fall as mortality predicts? |
| Longer term | `credit = (20, 10)` | The same, in the other direction |
| Inheritance | `inheritance = true` | The book's own answer to a lender's death (p.133): how many voids it removes |
| No credit | `credit = nothing` | What credit does for births, the trough and the population (question 4) |
| xl | The xl VI-1 the scorecard uses as its reference, on the 500 × 500 xl map | X8's reading on the reference rules. Is 0.2 reachable there? |
| Book | The registry's 50 × 50 VI-1, with no xxl or xl layer; seeds 20–39 | The same, on the book's world. 20 seeds, since 200 founders give noisy seeds and they run quickly |

The script therefore has to run a world with no xxl rules as well, not only `XXL_DEFAULTS`. The xl probe needs a new run:
the existing xl CSVs have `n_loans` but no loan flows.

Confounds the report has to state:

- Changing the term also changes the amount due (simple interest) and who is creditworthy (income × d), so it changes
  who borrows, not only how long they are exposed.
- Inheritance also passes on wealth, so that probe changes more than loans.
- Under inheritance the scorecard's `loans_voided` miscounts (1 − k for k heirs, see `scorecard_metrics!`). The tracer
  has to count this properly: an inherited loan's copies stay part of its chain, each weighted 1/k.

**Run time.** An estimate of about 2–3 hours for the main run with `--jobs 5`, from stage 2's 2,337–5,535 s per seed
plus the tracer's cost, and about 2 hours for the probes. The first finished seed gives a real figure. Heavy runs go one
at a time, and memory is watched as in stage 2: 5 workers at about 2 GB each on 31.8 GB.

## Testing

**The run must be the same run** (the check that matters most):

- With the tracer on, seed 20's CSV over 2,000 periods is byte-identical to
  `results-julia-xxl/extinction-defaults-s20-60-p2000/seed20.csv`. Tracer on or off, the same bytes.
- The tracer's counts over t = 1–500 equal the scorecard's for seeds 20–29 **exactly**: started, repaid, voided and
  rolled, from `scorecard-defaults-x2sight-s20-20/VI-1`. So X8 computed from the tracer equals the scorecard's value.

**The accounting closes:** in every window, started = repaid + voided + still on the book, by exact count. Voids by
borrower + lender + both = voids. Sugar: lenders' receipts in the tracer equal repaid amounts plus partial payments.

**Small worlds with known answers:**

- A lender who dies mid-term: voided by the lender, sugar received 0, the right cause and age.
- A borrower who starves mid-term: voided by the borrower.
- Both dying in one period: "both".
- A loan that rolls over twice and is then repaid: one chain, two rollovers, repaid.
- A party whose `max_age` falls before the due date: doomed at the start, with the off-by-one pinned against the order
  in `step!`, where old-age death runs before `settle_loans!` in the same period.
- A lender who dies under inheritance with 2 heirs: copies weighted 1/2 each, adding up to one chain.
- A census: each agent lands in the right group, an agent both borrowing and lending in both, and a death or child one
  period past the term isn't counted.

**A report rebuilt from the folder** gives the same report. The existing suite stays green. No existing test changes.

## How the findings are read

Set out now so the result can't pick its own reading (*my call*). The lines are reporting lines, not thresholds.

| What the main run shows | Reading | Likely recommendation to the user |
|---|---|---|
| Age ratio within 0.9–1.1 on both sides | X8 measures lifespan; loans carry no extra risk | Replace or rescope X8, using question 3's sugar figures and the xl and book readings. No rule change |
| Lender-only deaths are over half of voids, or doomed loans over a quarter of voids | X8 mostly reflects the book's rule that the old lend | The same, or ask whether the old should lend at all; inheritance is the book's own answer, and the probe prices it |
| Borrowers' matched ratio above 1.1 for sugar or spice deaths | Agents starve more with a loan than similar agents without one: a real credit defect | Look at the creditworthiness test, or at sugar-only loans in a two-good world, under a new spec |
| Borrowing agents' share with a child is within 1.1× could-borrow agents', or with credit off births and end population stay within 5% | Credit isn't doing its job, whatever X8 says | The bigger finding: stage 3 is about that, not about X8 |

An age ratio above 1.1 with a matched ratio near 1 means the extra deaths come from who borrows, not from the loan. That
is not a credit defect.

If xl and the book read far above 0.2 as well, the limit never described a healthy society, and the report says so.

A result can fall under more than one row. The report says which, with its numbers.

## Deliverables and order

1. Build the tracer, script, report and tests, on a new branch from `main`.
2. Pass the byte-identical and exact-count checks on seed 20 at 500 periods. A failure stops here.
3. The main run, then the probes.
4. The findings and a recommendation in `docs/xxl.md`, a new section "Stage 3: what X8 measures", with the question of
   what to change put to the user.

Commits follow the user's standing rule, which needs approval. Nothing is merged or pushed without it.

## Left to the builder

- How the tracer hooks into `add_loan!`, `settle_loans!` and `credit_on_deaths!`, as long as nothing moves when it's off
  and the tests above hold. It must not break `checkpoint.jl`, which saves the model.
- How the probes override `credit` and `inheritance`. These are `Config` fields from the registry, not `XxlRules`
  fields, so `--set` doesn't reach them today.
- Table layouts, the window boundaries beyond those named, and the age bands' edges.
- Names of columns and files, as long as the report answers the four questions.
