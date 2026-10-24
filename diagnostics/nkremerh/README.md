# nkremerh/sugarscape, run headless

Outside evidence for the Chapter III population gap: Nathan Kremer-Herman's Python Sugarscape
(github.com/nkremerh/sugarscape, Unlicense; commit `e6559be`, 2026-10-09). It extends Hervé Lange's earlier version
(github.com/langerv/sugarscape), and its examples are meant to show "adherence to or deviation from" the book. Run on
Figs III-1, III-3, III-4 and III-5 on 2026-10-23, cloned with the project owner's approval. Nothing from it is
committed here.

## What its code does

Each agent, in turn: moves, harvests, metabolizes, runs rules T, S and the others, then ages. Read from the code:

- **Rule S is the book's.**
  - **Mating:** an agent mates with every neighbor of the other sex that is of childbearing age and holds its
    starting sugar, re-checking its own fertility before each birth.
  - **The child:** it is placed on an empty site next to either parent. Each parent pays half its starting sugar, and
    the child starts with the sum.
- **The child's other attributes** each come from a random parent. That includes its sex, its maximum age and its
  childbearing ages. So a daughter can carry her father's end of fertility (50–60 in Fig III-1, against women's
  40–50).
- **Three other departures from the text:**
  - **Must move:** rule M considers the agent's own site only when no other site in sight is open.
  - **Birth harvest:** a newborn harvests its birth site at once.
  - **Founders' values** are spread evenly over each range rather than drawn at random. Founders start at age 0.
- **Its own landscape** has generated peaks, not Fig II-1's terraces.
- **A bug in its map loader:** `configureEnvironment` passes a cell's spice where `Cell` expects its sugar, and vice
  versa. We put the book's capacities in the file's "spice" field so they land on the sugar layer.
- **Its own III-4 and III-5 examples** set starting sugar 20–80 where p.65 says 10–40. Both are run.

## Our harness

- **[run.py](run.py)** writes each run's configuration from the repository's own Chapter III example. It sets only
  the figure's stated endowment and fertility ends, the seed and the length. It runs `sugarscape.py` in its own
  process from the clone (`python -E -s`) and converts its CSV log to rows in the MASON harness's format.
- **[ablate.py](ablate.py)** runs patched copies of the clone, with exact edits required to match once:
  - `ownsite`: rule M may choose the agent's own site.
  - `nobirth`: no harvest at birth.
  - `sexages`: a child's childbearing ages are drawn for its own sex.
  - `both` and `all`: the combinations.

```bash
python diagnostics/nkremerh/run.py <clone> <work folder> 10 20
```

```bash
python diagnostics/nkremerh_compare.py <work folder>/runs
```

```bash
python diagnostics/nkremerh/ablate.py <clone> <work folder> 10 16
```

```bash
python diagnostics/ablation_summary.py <work folder> "{v}/runs/fig3-{fig}_book_seed*.csv" base,ownsite,nobirth,sexages,both,all
```

## Results (2026-10-23; 10 seeds)

Full output: [nkremerh_compare.txt](../output/nkremerh_compare.txt), [nkremerh_ablate.txt](../output/nkremerh_ablate.txt).

| Target | Book | nkremerh, own landscape | nkremerh, book map | Ours, p.55 (VAR-book) | Ours, default (θ=0.83) |
|---|---|---|---|---|---|
| III-1 steady population | ≈500 | 541 pass | 564 pass | 360 near | 478 pass |
| III-3 population floor | ≈250 | 256 pass | 279 pass | 18 fail | 33 fail |
| III-4 oscillation range | ≈1,000 | 89 fail | 97 fail | 120 fail | 106 fail |
| III-4 range, its 20–80 example | ≈1,000 | 78 fail | 83 fail | — | — |
| III-5 extinction | yes | 0 of 10 | 0 of 10 | 0 of 10 | 0 of 10 |

**Ablations** (book map):

| Setting | III-1 level | III-3 floor |
|---|---|---|
| its code | 564 | 279 |
| own site allowed | 551 | 222 |
| no harvest at birth | 544 | 240 |
| childbearing ages drawn for the child's sex | 383 | 56 |
| all three | 376 | 25 |

- **The level and the floor come from inherited childbearing ages.** Daughters who inherit a father's later end
  of fertility have more children.
- **With all three departures removed, it agrees with ours** (376 and 25, against 360 and 18–33). That is an
  independent check of our model under the text's rules.
- **It never shows III-4's swings** (range below 100) and never dies out in III-5.
