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
- **VI-3 near-extinction minimum** (and its VAR- copies): Julia higher (66 → 87, p = 0.15). Same kind: VI-3's
  minimum follows the early die-off, which 5 seeds measure loosely.

**Untimed:** every Python result is still from 2026-10-23, before the runner recorded timing, so the speed tables
are Julia only until the user's timed re-run lands.
