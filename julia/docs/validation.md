# Julia port: validation log

A running record of each comparison with the Python model: what ran, the verdict of `python -m bridge.report`, and
every flag or book-target status change with its fix or explanation. The rule is in
[the design](../../docs/superpowers/specs/2026-10-24-julia-design.md) ("Statistical agreement"). Python results
are the saved ones in the main checkout's `results/`. Until the user's timed re-run lands, they have no `timing.csv`,
so the speed tables are Julia only.

## Chapter II (2026-10-24)

**Ran:** the 25 Chapter II experiments (II-1, II-4, II-4-gini, the 18 points of II-5, II-6, II-6-measured, II-7,
II-8), registered seeds, `--jobs 8`, while the machine was shared with a Python xl run.

**Agreement: 0 flags** among 1,043 tested windows and 25 extinction tests.

**Book targets:** Python 37 pass, 9 near, 3 fail; Julia 35 pass, 9 near, 5 fail. Four statuses changed, all of
them carrying capacity, the mean population over t = 450–500 (Fig II-5):

| Experiment | Band | Python (10 seeds) | Julia (10 seeds) | Status |
|---|---|---|---|---|
| II-5/m2/v5.5 | 351–429 | 313.5 | 311.0 | near → fail |
| II-5/m2/v10.5 | 360–440 | 322.5 | 319.5 | near → fail |
| II-5/m3/v3 | 229.5–280.5 | 230.7 | 229.3 | pass → near |
| II-5/m3/v8 | 252–308 | 252.3 | 251.6 | pass → near |

**Explanation: band-edge noise, not a rule difference.** Each Python mean sits within 1.3% of a band edge (the
near band's lower edge for the first two), so a difference of a fraction of a seed SD flips the status.
- The differences are 0.7–3.0 agents, at most z = −0.75 against the two sides' standard error.
- With 40 Julia seeds of the four (left out of `results-julia/`): Julia 310.0, 319.9, 227.7 and 250.2, z between
  −0.78 and −1.53. These four were picked because Julia came out lower, so they lean low by selection; Python's 10
  seeds set most of the error.
- Across all 19 carrying-capacity points (II-4 and the II-5 sweep), Julia − Python has z from −0.75 to +1.24 and
  mean z −0.15 (13 of 19 negative). The mean of 19 independent z values has SD 0.23 under no difference, so −0.15
  is not significant.
- The GPU port's only Chapter II status change was the same II-5/m3/v8 edge (Python 252.3, GPU 251.5).

Worth re-checking when more Python seeds exist: a real bias of about −1% at high vision would show as a growing z.

## Chapter III (2026-10-24)

**Ran:** the 12 Chapter III experiments, and the reproduction variants (VAR-book, VAR-share, VAR-c1c3fit,
VAR-intgift, VAR-intgiftc1, VAR-fit83) of III-1, III-3, III-4 and III-5. Registered seeds, `--jobs 8`, shared machine.

**Agreement: 0 flags.** The untestable windows (III-1, III-3, III-4, III-5, III-15) are all `north_frac_low_vision`:
sexual reproduction selects out every agent of vision 2 or less, so there is nothing to measure. That is expected,
not an extinction.

**Book targets:** five statuses changed. Three are noise at the seed level (Welch p on the per-seed statistic):
III-1 small fluctuations (p = 0.32), III-4 oscillation range (p = 0.62), III-15 Red dominates both (p = 0.76). The
other two needed work:

- **III-9, one of the three patterns** (Python 10/10 seeds, Julia 7/10). Julia's war was also less lethal over the
  first 500 periods (mean population at t = 200: Python 162, Julia 219, p ≈ 0.04 at each time). Investigated:
  - All of Julia's late deaths are combat kills, none starvation.
  - **Decision parity:** a Python III-9 state at t = 60 (284 agents), every agent's combat move replayed in both
    implementations with directions fixed: all 284 decisions identical (destination, victim, sugar).
  - **Lockstep:** Python's recorded agent orders and direction draws fed to Julia for 300 periods: identical end
    state, every draw consumed. (This became the committed `test_lockstep.jl`.)
  - **50 seeds each:** population agrees at every time (t = 50 to 1000, p = 0.59–0.88); the pattern target is
    49/50 against 44/50 (Fisher p = 0.11). Python's registered 10 seeds happen to sit low (230 at t = 100 against
    251 over 50 seeds) and Julia's high. **Sampling noise.**
- **III-8, each side culturally pure** (Python 2/5, Julia 5/5). With 50 seeds each: 31/50 on both sides (Fisher
  p = 1.0), and the minority remnant agrees at every time from t = 100 to 6000 (p ≥ 0.20). **Sampling noise.**

The VAR- variants of III-1 to III-5 add their own changes (listed under "Variants" below), all of the same kinds.

## Chapters IV, V and VI, and the full regular comparison (2026-10-24)

**Ran:** every remaining sugarscape experiment: Chapters IV, V and VI, the reproduction variants of VI-2 and VI-3,
and VAR-inttrade on every trading experiment. With Chapters II and III that is all 134 experiments of the registry
(TEST-tiny aside), registered seeds.

**Agreement (one report, one correction): 0 flags among 8,165 tested windows and 134 extinction tests.**
Chapter V alone: 0 flags and no target status changes.

**Book targets:** Python 139 pass, 56 near, 120 fail; Julia 138 pass, 60 near, 117 fail. 38 statuses changed. The
report now gives each one's seed-level p (the target's per-seed values, Julia against Python; Fisher's exact test
for outcomes, Welch otherwise). All 38 are above 0.05 but one, where p could not be computed (IV-18, below). Under
no difference about 2 of 38 would fall below 0.05 by chance. Status changes come from means sitting near band
edges, and from experiments with few seeds and two-way outcomes.

Three groups were followed up because they pointed one way or looked qualitative:

- **IV-6 carrying capacity.** Julia was higher at 9 of 10 points (+2 to +6% with trade, about +2% without), with
  mean z 0.76. The points are not independent (seed k of every experiment starts from the same stream), so that is
  weaker than it looks.
  - **Lockstep with trade:** the event stream now carries trade's neighbour orders as well. Python's recorded
    draws reproduce a full 500-period IV-6/trade/v6 run (400 agents, 150,003 draws) exactly in Julia, and the
    committed cases cover IV-6 with and without trade, and IV-A3. So spice movement, welfare, foresight and rule T
    match Python period by period.
  - **Founders** agree at t = 0 (vision, metabolism, sugar, spice; p ≥ 0.27, 50 seeds).
  - **More seeds**, IV-6/trade/v6: 10 seeds +4.9%; 50 seeds +2.6% (p = 0.04); 200 seeds +1.3% (p = 0.04), and on
    the 150 seeds never looked at before, +0.9% (p = 0.22). Julia's mean is steady (139.7, 141.5, 141.5, 141.6)
    while Python's rises with more seeds (133.2, 137.9, 139.7, 140.3): its low-numbered seeds came out low. With
    the dynamics shown identical, what remains is sampling noise.
- **IV-18 long-run mean foresight.** 4 of 5 Julia seeds went extinct against 1 of 5 Python seeds, so the target
  had one Julia seed to measure. With 50 seeds each: 26/50 extinct on both sides (Fisher p = 1.0), population
  agreeing at every time (p ≥ 0.58). Sampling noise.
- **VI-3 near-extinction minimum** (and its VAR- copies): Julia higher on the registered seeds, in VI-3 (66 → 87,
  p = 0.15; 66.2 → 76.2, p = 0.57, once the old-age fix was in the results) and in VAR-inttrade, VAR-fit83 and
  VAR-c1c3fit. The minimum follows the early die-off, which 5 seeds measure loosely. With 50 seeds each, on the 45
  seeds never looked at before: VI-3 77.9 against 77.2 (p = 0.91), VAR-inttrade 68.1 against 74.4 (p = 0.29),
  VAR-fit83 55.6 against 45.6 (p = 0.08), VAR-c1c3fit 211.2 against 214.4 (p = 0.65). Julia is lower in two and
  higher in two, so the one-way pattern was the registered seeds; every VI-3 target in the four has p ≥ 0.15 over
  all 50 seeds. Sampling noise.

**Untimed:** every Python result is still from 2026-10-23, before the runner recorded timing, so the speed tables
are Julia only until the user's timed re-run lands.

## xl: profile (2026-10-24)

One seed each, single process, 10 periods after the first, on the shared machine (`Profile`, flat by count):

| Experiment | Agents | Step ms/period | Metrics ms | Where the time goes |
|---|---|---|---|---|
| II-4 | 40,000 → 38,957 | 56 | 6 | `move!`: the lattice scan out to vision (10–60) and `site_score` |
| IV-A3 | 20,000 → 18,606 | 134 | 2 | `move!` → welfare: two `^` per scanned site, about 80% |
| VI-1 | 19,910 → 14,400 | 169 | 6 | welfare as IV-A3 (about 85%); `mate!`'s scan of partners in sight |

What changed for speed, none of it changing a result:
- `SiteWelfare` computes the agent's part of `welfare_score` (preference fraction, exponents, holdings phi periods
  ahead) once per move instead of at every site, and scores a site with no sugar and no spice from a cached value.
  A test checks it against `welfare_score` bit for bit at every site of 400 random states. Gain about 3–6%, because
  at xl nearly every scanned site holds some regrown resource.
- Not done: replacing the two `^` per site with `exp(e1 log w1 + e2 log w2)`, or skipping sites dominated in both
  goods. Both would change scores in the last bit (or rest on `^` being monotone), so ties could break differently
  from Python. The welfare evaluation is the rule's own cost, and Python pays it too.

The hot paths stay type-stable (`test_hot_paths.jl`: `@inferred` on `step!`, `move!`, `collect_metrics`; diffusion
and growback allocate nothing).

## xl comparison (2026-10-24)

**The workload changed mid-port.** Commit 0b6b937 on main (user decision, 2026-10-24) made xl agents look at one
random site in each stretch of 10 along each lattice line (`Config.look_stride`, docs/xl.md "Looking"), and draw
vision as 10, 20, … 60. The first Julia xl runs used the earlier definition and differed from Python's II-4 xl from
t = 1 (Julia moved 18,919 agents in the first period against Python's 16,318). `main` was merged into `feat/julia`
and `look_stride` ported to movement, combat (target search and retaliation) and partners in sight, with Python's
`tests/test_look_stride.py` as the checklist. Stride 1 draws nothing, so regular results stay current.

**II-4 at xl (10 seeds each): Julia agrees with Python, 0 flags.** Julia ends with 23,238 agents on average,
Python 23,262.

**IV-A3 and VI-1 at xl:** Julia's runs are done; Python's are not yet, so the report lists them as missing.
VI-1 is worth a note before Python's arrive. Per 50 × 50 tile, the xl run follows the regular run until about t = 50
(Julia xl 33 agents per tile, Python regular 37). At t = 100 the regular society is down to about 13 and goes extinct
in 3 of 5 seeds; xl, with 100× the agents, holds about 36 per tile, never goes extinct, and grows to about 845 per
tile (84,500 agents) by t = 500. That is near the regular runs that survive (two seeds, about 744 at t = 500), so it
looks like a property of the larger world rather than of the port, but only Python's xl VI-1 can say.

## Final review fixes, timing refresh, and the full xl registry (2026-10-25)

**Regular results re-run** on the commit with the review fixes, to replace setup times that had included ~35 ms of
compilation. One fix changes trajectories (not distributions): the old-age death batch is now processed in creation
order, as Python's list keeps it. That changes the order of `m.agents`, so every experiment with old-age deaths or
replacement follows a different, equally valid random path. The report on the new results:

- **0 flags among 8,146 tested windows and 134 extinction tests** (eligibility moved slightly with the new paths).
- **Book targets:** Python 139 pass, 56 near, 120 fail; Julia 136 pass, 65 near, 114 fail; 37 statuses changed.
  One new change had a seed-level p below 0.05: **VI-1 Gini of total wealth** (Python pass, Julia near, p = 0.032).
  With 50 seeds each, Python 0.313 against Julia 0.322, p = 0.22, and every VI-1 target has p ≥ 0.10 (extinction
  29/50 against 22/50, p = 0.23). **Sampling noise**, as expected about 2 times in 37 by chance.

**The full registry at xl, in Julia:** all 135 experiments ran at their registered seeds without a failure (51 hours
of stepping summed over seeds; median experiment 72 ms per period). Python has xl results for II-4 only, which
agrees (0 flags).

**Speed, as of today's timed Python results** (II-4 only so far, all on a shared machine):

| Workload | Python s/period | Julia s/period | Speedup |
|---|---|---|---|
| II-4 regular (400 → 236 agents) | 0.0131 (4 jobs) | 0.000091 (10 jobs) | about 144× |
| II-4 xl (40,000 → about 23,230) | 1.89 (10 jobs) | 0.022 (5 jobs) | about 86× |

## Single-thread speed-ups, results unchanged (2026-10-25)

Profiling the slowest xl experiments for a threads investigation found three costs that grow faster than the
population, all in Chapter III–VI rules. Each is fixed without changing a draw or an arithmetic order:

- **Credit worthiness** summed a borrower's debts by scanning the whole loan book for every loan considered. Each
  borrower's loans are now indexed (`Model.debts`), in the book's order, so the sum is the same additions in the same
  order. (A running total would round differently once loans are repaid.)
- **Deaths** rebuilt the loan book once per death. Agents with no loans now skip rule L (`Model.lent` counts each
  lender's loans), and the end-of-period old-age batch settles its loans in one pass, which gives the same book as
  one death at a time: heirs are never in the batch, and nothing in between reads loans.
- **Partners in sight** (rule S) built six new lists per agent per period; `in_sight` and `mate!` now reuse
  buffers on the model and draw their looks in the same order.

**Identical results:** all 1,047 regular seed files of the registry and the 15 xl seed files of VI-1 and III-5 are
byte-identical to runs of the code before the change. A test checks the loan indexes against the book every period
of a VI-1 run.

**Timing, xl** (VI-1 with `--jobs 5` and III-5 with `--jobs 10`, run together, shared machine):

| Code | VI-1 s/period | III-5 s/period |
|---|---|---|
| Before | 1.435 | 0.559 |
| Credit index and rule S buffers | 0.709 | 0.373 |
| Plus the death path | 0.503 | 0.451 |

III-5 has no credit, so the last change runs none of its new code there: its 0.373 → 0.451 is the machine's load,
about 20%. Profiling VI-1 per phase at t = 400 (86,000 agents, about 20,500 loans, 1,200 deaths a period), before
and after: credit went from 1,111 to 10 ms a period, the aging phase from 233 to 125 ms, and the period from 1,945
to 613 ms.

**Stale xl results:** `results-julia-xl/` VI-1 and III-5 predate the old-age ordering fix (479b911) and diverge
from today's code at the first old-age deaths; other experiments with finite lives may too. They are statistically
the same model; a re-run would make them reproducible from the code.

## Python re-run with timings: the full comparison (2026-10-25)

The user re-ran every Python experiment with timings: all 135 regular ones (including TEST-tiny, compared for the
first time) and, at xl, II-4, II-4-gini, II-6, II-7 and II-8.

**Regular: 2 flags among 8,185 tested windows and 135 extinction tests, both in TEST-tiny**, the runner's 5-period
smoke test (20 agents, 2 seeds). Both Python seeds kept all 20 agents through t = 3, so Python's side had no
variance and any Julia death counts as `constant-differs`. With 400 seeds each, population agrees at every t
(p ≥ 0.22; at t = 3, 230/400 Python seeds still at 20 against 226/400 Julia). An artefact of 2 seeds; the 134 book
experiments have 0 flags. Book targets: 37 status changes, as before.

**xl: Julia agrees with Python on all five experiments, 0 flags.**

**Speed** (shared machine; not the quiet-machine numbers):

- Regular, 135 experiments, both sides with `--jobs 1` (Julia re-run on e838979, after the single-thread
  speed-ups; all 1,047 seed files byte-identical to the earlier run): median speedup 36× (quartiles 27× and 47×;
  10× to 135×). Summed over experiments, Python takes 1.52 s per period against Julia's 0.044 s, 34×. The lowest
  ratios are the full societies (VI-1 10×, IV-17 12×); II-4 is 46×. The first timing, before the re-run, with Julia
  sharing the processor (`--jobs 10`) and without the speed-ups, gave a median of 28×.
- xl, five Chapter II experiments: 53× (II-8) to 86× (II-4), and 666× for II-4-gini. Python's xl runs predate its
  replacement speed-up (77ffcb6), so II-4-gini's 22.6 s per period is the old scan of every site; `docs/xl.md`
  gives about 1.13 s after it. Python's streams didn't change, so agreement stands; that timing doesn't.
