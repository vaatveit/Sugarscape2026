# SugarscapeCW, run headless

Outside evidence for the Chapter III population gap: Christopher Watts' NetLogo replication of every chapter
(SugarscapeCW 1.2.0, 2015/2023). Run on Figs III-1, III-3, III-4 and III-5 on 2026-10-23.

**Source.** CoMSES codebase 4688, release 1.2.0 (`code/SugarscapeCW.nlogo`, GPL-3.0), downloaded by the project owner
through CoMSES' download form. It is written for NetLogo 5.3.1. NetLogo 6.4.0 was installed from
`downloads.netlogo.org/6.4.0/NetLogo-6.4.0-64.msi` (312 MB, unsigned; with the project owner's approval). Nothing
from either is committed here.

## What Watts' code does

Each agent, in turn: ages (and dies at its maximum age), moves, harvests and metabolizes (and starves at zero sugar),
then runs rule S. The landscape grows back after every agent has acted. Read from the code:

- **Rule S is the book's.**
  - **Mating:** an agent mates with every fertile neighbor of the other sex. A neighbor counts when it is of
    childbearing age and holds at least its initial endowment. The initiating parent's wealth is re-checked before
    each birth.
  - **The child:** it is placed on an empty site next to either parent. It takes vision and metabolism from one
    parent each, and draws its maximum age and childbearing ages fresh.
- **The gift is an integer.** Each parent gives int(initial endowment / 2), and the child's endowment, which is also
  its own fertility requirement, is the sum. It can only round down, so requirements ratchet down over the
  generations.
- **Two departures from the text:**
  - **Stacking:** the one-commodity rule M ranks every visible site, occupied ones included, so agents can share a
    site. This is rare: one to five sites at a time hold two agents.
  - **No wrap:** the world doesn't wrap.
- **The map** is identical to ours, cell for cell.
- **Founders** start at age 0 in its presets (optionally U[0, 80]). Its Chapter III preset is Fig III-5's setting.

## Our harness

- **[convert.py](convert.py)** rewrites a copy in NetLogo 6 syntax. NetLogo 6's headless opener refuses 5.x models,
  so each task placeholder (`?`, `?1`, `?2`) becomes a named argument of an anonymous procedure, and the version
  line changes. Every edit must match exactly; the model's logic is unchanged. With `--nostack`, it also confines
  rule M to unoccupied sites and the agent's own (an ablation).
- **[CWRun.java](CWRun.java)** starts from the model's Chapter III preset. It sets only each figure's stated
  endowment (p.57, p.65) and fertility ends (p.64), the founders' ages, the seed and the run length.
  - It prints rows in the MASON harness's format.
  - Optional words: `wrap` makes the world a torus (an ablation); `probe` prints births, fertile-age agents, those
    holding their endowment, completed family size and the mean endowment each period.
  - Runs are deterministic.
- **[build_and_run.sh](build_and_run.sh)** runs four figures × two founder settings × 10 seeds.
  **[ablate.sh](ablate.sh)** runs the stacking and wrap ablations on III-1 and III-4.

```bash
sh diagnostics/sugarscapecw/build_and_run.sh <SugarscapeCW.nlogo> <work folder> 10 12
```

```bash
python diagnostics/sugarscapecw_compare.py <work folder>/runs
```

```bash
sh diagnostics/sugarscapecw/ablate.sh <SugarscapeCW.nlogo> <work folder> 10 8
```

```bash
python diagnostics/ablation_summary.py <work folder>/ablate "fig3-{fig}_{v}_seed*.csv" base,nostack,wrap,nostack+wrap
```

## Results (2026-10-23; 10 seeds)

Full output: [sugarscapecw_compare.txt](../output/sugarscapecw_compare.txt),
[sugarscapecw_ablate.txt](../output/sugarscapecw_ablate.txt).

| Target | Book | SugarscapeCW, founders age 0 | SugarscapeCW, spread ages | Ours, p.55 (VAR-book) | Ours, default (θ=0.83) |
|---|---|---|---|---|---|
| III-1 steady population | ≈500 | 473 pass | 465 pass | 360 near | 478 pass |
| III-3 population floor | ≈250 | 106 fail | 51 fail | 18 fail | 33 fail |
| III-3 oscillation period | ≈200 | 426 fail | 557 fail | 495 fail | 412 fail |
| III-4 oscillation range | ≈1,000 | 929 pass | 883 pass | 120 fail | 106 fail |
| III-4 oscillation period | ≈125 | 117 pass | 118 pass | 136 pass | 132 pass |
| III-5 extinction | yes | 0 of 10 | 0 of 10 | 0 of 10 | 0 of 10 |

**Ablations** (III-1 and III-4, founders at age 0):

| Setting | III-1 level | III-4 range |
|---|---|---|
| Watts' model | 476 | 910 |
| no stacking | 475 | 590 |
| torus | 475 | 938 |
| no stacking, torus | 479 | 678 |

- **Neither departure explains the level.** With the text's movement on a torus, his model still settles at 479
  under p.55's threshold.
- **Stacking accounts for part of III-4's swings** (910 to 590), but the swings stay within the band without it
  (678, on a torus).
- **The integer gift explains the level.** Probed on III-1 (no stacking, torus, 3 seeds), births per woman match
  ours (1.99 children per completed life against 2.01; 44% of fertile-age agents hold their endowment against 43%).
  But his population's mean endowment, and with it the fertility requirement, falls from 74 to 63 by t≈500 and stays
  there; ours falls only to 71. The same truncation in our model
  ([probe_integer_gift.py](../probe_integer_gift.py)) lifts III-1 to ≈450 and III-4's range to ≈500.
