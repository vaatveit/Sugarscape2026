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
