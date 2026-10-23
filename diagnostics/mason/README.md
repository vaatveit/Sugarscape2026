# MASON's Sugarscape, run headless

Outside evidence for the Chapter III population gap: the MASON implementation (Bigbee, Cioffi-Revilla and Luke 2007,
"Replication of Sugarscape using MASON"), run on its own configs for Figs III-1, III-3, III-4 and III-5.

**Source.** The project's archive, `https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/mason-sugarscape/source-archive.zip`
(37 MB, downloaded with the user's approval on 2026-10-22). The checkout leaves `lib/` and `sim/app/sugarscape/util/`
empty, but the `.svn` pristine copies hold both: the project's own `mason.jar`, JFreeChart 1.0.13 and JCommon 1.0.16, and
the util sources. Nothing from the archive is committed here; [build_and_run.sh](build_and_run.sh) assembles a build
folder from it.

**Our driver.** [RunSeeded.java](RunSeeded.java) runs one config for a given seed (MASON's own `main` seeds from the clock)
and prints its own rows: MASON's population count, the agents actually on the grid, and on-grid mean vision and
metabolism. Two quirks of MASON's code make its own statistics unusable as they stand:
- **Children are counted but never added to `active_agents`,** so MASON's printed vision and metabolism average over
  founders only, and fall to 0 as the founders die.
- **Child placement ignores occupancy:** a child can overwrite an agent, which keeps acting off the grid. The counted
  population includes these agents: 2–12 of them on average in these runs.

Runs are deterministic: the same seed gives byte-identical output.

```bash
sh diagnostics/mason/build_and_run.sh <unzipped archive> <work folder> 10 8
```

```bash
python diagnostics/mason_compare.py <work folder>/runs
```

## Results (2026-10-23; 10 seeds; our columns as registered, 5 or 10 seeds)

| Target | Book | MASON | Ours, default (θ=0.83) |
|---|---|---|---|
| III-1 steady population | ≈500 | 348 near | 478 pass |
| III-1 small fluctuations | ≤0.10 | 0.063 pass | 0.065 pass |
| III-1 mean vision at t≈900 / metabolism | 5.3 / 1.0 | 5.47 / 1.00 pass | 5.64 / 1.00 pass |
| III-3 floor | ≈250 | 32 fail (5 of 10 seeds extinct) | 33 fail |
| III-3 period | ≈200 | 752 fail (6/10 seeds oscillate) | 412 fail (3/5) |
| III-4 range | ≈1,000 | 657 pass | 106 fail |
| III-4 period | ≈125 | 239 fail | 132 pass |
| III-5 extinct by t=1500 | yes | 0 of 10 seeds | 0 of 10 |

Trajectories (means over seeds; book digitized):

| | t=20 | t=85 | Lowest before t=300 | Mean t≥500 |
|---|---|---|---|---|
| Book, Fig III-1 | 470 | 570 | — | ≈500 |
| MASON III-1 | 472 | 362 | 238 | 348 |
| MASON III-4 | 519 | 643 | 400 | 955 (range 670 late) |

**Reading.**
- **MASON doesn't reproduce the book's population figures either.** Its III-1 crashes after the founding boom and
  settles near 350 (ours under p.55's rule: ≈360), III-3 loses most of its population, and III-5 never dies out.
- **Its III-4 swings come from a cheaper reproduction rule.** MASON reads p.65 as a flat fertility threshold of 25
  sugar with endowments of 50–100. The large swings then appear, but at about twice the book's period. Our candidate C3
  (Ascape's cheap children) also gives III-4 its swings, at the book's period ([candidates.py](../candidates.py)).
- **So the 2007 claim of "general" matches for III-1, III-3 and III-5 doesn't hold up when MASON's own configs are
  scored quantitatively,** and two independent implementations of the text land in the same place.
