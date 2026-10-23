# Ascape's Sugarscape, run headless

Outside evidence for the Chapter III population gap: the Sugarscape models in Ascape 5.6.1 (Brookings Institution,
Miles Parker and others), the one implementation built where the book's authors worked. We ran its sex model on Figs
III-1, III-3, III-4 and III-5.

**Source.** The release jar, `https://sourceforge.net/projects/ascape/files/Ascape/5.6.1/release/Ascape_5.6.1.jar`
(6.0 MB). It carries the compiled framework and the `edu.brook.sugarscape` models. We read the model code in
`Ascape_SDK_5.6.1.zip` (7.7 MB, same folder). Both were downloaded with the user's approval on 2026-10-23. Nothing
from them is committed here.

## What Ascape's code does

The sex model is `GAS_SexBase`. Each agent, in turn, moves, harvests, metabolizes, runs `PromiscuousReprod`, and dies
of starvation or old age. Read from the source, it departs from the book in these places:

- **Landscape:** two generated Gaussian mounds (`SugarCell`: peaks at (40, 10) and (15, 35), capacity
  round(4·min(1, Σ exp(−0.004 d²)))), not Fig II-1's terraces. The grid wraps.
- **Founders:** 300, at random ages up to their death age. Endowments default to 0–30 (`GAS_Base`).
  `SexualAgent`'s 50–100 fields are never read.
- **Movement:** the most sugar within vision along the four lattice lines (a vision-3 search covers 12 cells), random
  among ties, with no preference for the nearest. Occupied sites take part in the search, and an agent whose best site
  is occupied stays put.
- **The child's sugar:** each parent gives min(5, its sugar). But the child's stock is *set* twice, so it keeps only
  the second parent's gift, at most 5 sugar; the first parent's gift is lost. Our candidate C3 gave the child both
  gifts (up to 10).
- **The child's fertility threshold:** a fresh draw from the founders' endowment range, made when the child is
  initialized, not the sugar it was born with.
- **As in the book:** partners are the four lattice neighbors in random order, a birth needs an empty site next to
  either parent, and fertility needs current sugar at least the threshold, at ages 12–15 to 40–50 (women) or 50–60
  (men).

## Our driver

[AscapeRun.java](AscapeRun.java) subclasses `GAS_SexBase` and runs Ascape's rules and agent code unchanged. It sets only
the figures' stated parameters: endowments of 50–100 (p.57) or 10–40 (p.65), and fertility ending 10 years earlier for
III-3 and III-5 (p.64). It runs two setups:
- **ascape:** Ascape's landscape and its 300 founders.
- **book:** the book's map (`sugarscape/maps/sugar-map.txt`) and our 400 founders. This setup differs from ours only in
  Ascape's rule code.

It prints rows in the MASON harness's format, one per period. Runs are deterministic: the same seed gives the same
rows (only the "Finished in" timing line differs).

```bash
sh diagnostics/ascape/build_and_run.sh <Ascape_5.6.1.jar> <work folder> 10 8
```

```bash
python diagnostics/ascape_compare.py <work folder>/runs
```

## Results (2026-10-23; 10 seeds; our columns as registered, 5 or 10 seeds)

Full output: [ascape_compare.txt](../output/ascape_compare.txt).

| Target | Book | Ascape, own landscape | Ascape, book map | Ours, p.55 (VAR-book) | Ours, default (θ=0.83) |
|---|---|---|---|---|---|
| III-1 steady population | ≈500 | 268 fail | 227 fail | 360 near | 478 pass |
| III-1 small fluctuations | ≤0.10 | 0.134 fail | 0.151 fail (1 seed extinct) | 0.059 pass | 0.065 pass |
| III-1 mean vision at t≈900 / metabolism | 5.3 / 1.0 | 5.7 / 1.0 pass | 5.6 / 1.0 near | 5.68 / 1.0 pass | 5.64 / 1.0 pass |
| III-3 floor | ≈250 | 0 fail (10 of 10 extinct) | 0 fail (10 of 10 extinct) | 18 fail | 33 fail |
| III-4 period | ≈125 | 126 pass | 127 pass | 136 pass | 132 pass |
| III-4 range | ≈1,000 | 556 near | 672 pass | 120 fail | 106 fail |
| III-5 extinct by t=1500 | yes | 0 of 10 | 0 of 10 | 0 of 10 | 0 of 10 |

Trajectories (means over seeds):

| | t=20 | t=85 | Lowest before t=300 | Mean t≥500 | Late range |
|---|---|---|---|---|---|
| Book, Fig III-1 | 470 | 570 | — | ≈500 | small |
| Ascape III-1, book map | 416 | 164 | 56 | 227 | 160 |
| Ascape III-4, book map | 365 | 1,140 | 357 | 993 | 701 |
| Ascape III-5, book map | 330 | 785 | 310 | 705 | 1,073 |

**Reading.**
- **Ascape reproduces Fig III-4, and only III-4.** Its cycle has the book's period and about two-thirds of its swing.
  No other implementation gets both: MASON's swings come at twice the period, and ours have the period without the
  swings.
- **It misses the rest further than we do.** III-1 crashes after the founding generation and settles near 230–270.
  III-3 dies out in every run, and III-5 swings by ≈1,050 but never dies out.
- **The landscape and the founder count barely matter:** both setups give the same pattern. So the difference from
  our runs is in the rule code: children cost at most 5 sugar, and they come of age with an unrelated threshold.
- **So cheap children explain the large cycle, and nothing explains every figure.** Three independent codes
  (ours, MASON and Ascape) fail on III-1's level with III-3's floor and III-5's extinction. Ascape's code also has a
  plain bug (the lost first gift), so it can't stand in for the original's.
