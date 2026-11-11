# VI-1 with pollution: design

Date: 2026-11-11. Builds on `VI-1-assim-k4` (docs/xxl.md; julia/src/xxl/vi1_combat.jl) and the xxl viewer
(docs/superpowers/specs/2026-11-10-xxl-viewer-design.md; julia/viewer/).

## Intent

The user wants to see whether **pollution makes populations migrate** in today's xxl society with every other rule on.
The evidence they asked for is visual: agents **leave polluted areas, then come back after diffusion** spreads the
pollution out. This is the book's Animation II-8 story (pp. 48–50: pollution on, agents abandon the fouled peaks for the
hinterland, diffusion on, they return), asked of the 500 × 500 world with combat, culture by distance, sex, trade,
credit, inheritance and disease all running.

Two experiments, both in the viewer's menu:

1. **`VI-1-pollution`** (staged): pollution from t = 350, diffusion from t = 450, run to t = 600. In saved runs of
   `VI-1-assim-k4` (today's world, seeds 0–3) the population crashes from 20,000 to about 4,000 by t = 50, regrows from
   about t = 100 and levels off at 62,000–66,000 from about t = 350. Pollution therefore hits a settled society, so a move
   can be put down to pollution rather than to the crash or the regrowth. The user picked 350 and 450 "for now", to see
   the effect and make sure it is behaving correctly.
2. **`VI-1-pollution-t0`**: pollution and diffusion both from t = 0, run to t = 600. The user wants it to watch after the
   staged run, once the staged run has shown the rules behave.

## Goals

- The two experiments, defined in the Julia port like the other VI-1 combat-study experiments, runnable by the combat
  study (`julia/xxl_combat_study.jl`) and offered by the viewer.
- The viewer shows pollution on the map (option A, the user's choice) and charts it (both charts, the user's choice).
- The viewer's rule holds for everything new: it never shows anything the model didn't do. The new series equal the
  study's numbers, the new frame data equal the model, and tests prove both.
- The deferred viewer bug is fixed: `adoptRun` (julia/viewer/static/app.mjs) draws a new run's first frames with the
  previous run's legend until `/api/legend` answers. This now matters, because pollution runs have a different legend.

## Non-goals

- No study runs (20-seed or otherwise) as part of this work; the user is asked before any. Checks are the test suite and
  a live run in the viewer.
- No change to the pollution rules themselves (P and D as the model has them), or to any other rule.
- No new pass/fail bars: this is an experiment to watch, not a tuning study.
- No change to the existing experiments' outputs: a study of any existing experiment writes exactly what it writes today.

## Anti-goals

- A pollution picture or chart that is drawn, smoothed, rescaled or inferred in the browser rather than read from the
  model's own state.
- Pollution drawn so that it hides agents or can be mistaken for an agent or a mark.
- A run of one experiment shown, even briefly, with another experiment's legend.

## The experiments

Both are `VI-1-assim-k4` with pollution added, everything else unchanged (seeds, combat, culture rule, curve, h, sex,
trade, credit, inheritance, disease, and the xxl defaults today's world applies).

| Setting (book config) | `VI-1-pollution` | `VI-1-pollution-t0` |
|---|---|---|
| `pollution` (α, β) | (1.0, 1.0): the book's P₁,₁ | (1.0, 1.0) |
| `pollution_start` | 350 | 0 |
| `pollution_stop` | none (pollution keeps being made after diffusion starts, as in II-8) | none |
| `diffusion_period` | 1 (D₁) | 1 |
| `diffusion_start` | 450 | 0 |
| `diffusion_passes` | 1 in the book's world; the xl transform makes it 100 in xl and today's world (docs/xl.md) | same |
| steps | 600 | 600 |

- Rates are the book's: production pollution α × sugar harvested, at the harvest site; consumption pollution β × sugar
  burned (metabolism, disease fees and xxl travel cost), at the agent's site. Spice is clean (p.127). Sugar taken in
  combat makes no production pollution (docs/xxl.md, rule 7), as in the book.
- Movement already scores sites by resources ÷ (1 + pollution) (rule M, xxl rules 1–3, combat's site welfare), so
  nothing in the agents' choices changes.
- Each builder follows the file's pattern: `vi1_reach_experiment`-style construction from `VI-1-assim-k4`, a variant
  line appended to both fingerprints, the id added to `JULIA_COMBAT_EXPS`, the study's usage text and the viewer's
  `VIEWER_EXPS`. The variant lines name the settings, for example
  `variant: VI-1-pollution pollution=(1,1) pollution_start=350 diffusion=1 diffusion_start=450 steps=600 (...)`.
  The exact wording is the builder's.
- **Timing** (how the model counts): `step!` runs with the period count before it is incremented, so the step from
  t = 350 to 351 is the first to pollute and row t = 351 is the first polluted reading; likewise the first diffused
  reading is t = 451. The charts' dotted lines sit at 350 and 450 (labelled "pollution on" and "diffusion on" after that
  period), and tests expect the first changes at rows 351 and 451.
- **Checkerboard** (a model property, not a viewer bug): rule D averages a cell's four neighbours without the cell itself,
  so each pass moves pollution to the opposite colour of the checkerboard, and an even number of passes per period
  (100 in xl and today's world) brings it back. Pollution made on one colour stays on it, and the banded map may show a
  checkerboard texture. That is the model's own behaviour; the rules don't change here (non-goal), and docs/xxl.md
  says so next to the experiments.
- Both worlds `book` and `xl` stay buildable as for the other VI-1 experiments (the study may be asked for them); only
  today's world is in the viewer.

## The pollution readings (the study's numbers)

Three numbers per period, read at the end of the period exactly where the combat readings and metrics are read:

| Column | Meaning |
|---|---|
| `mean_pollution` | mean pollution over all cells of the world |
| `agent_pollution` | mean pollution of the cells agents stand on (NaN when there are no agents) |
| `share_rich` | share of agents standing on rich land (NaN when there are no agents) |

**Rich land** (my call, from the user's "top quarter of the land by sugar" in the mockup): the cells whose sugar
capacity + spice capacity is at or above the 75th percentile of that sum over all cells. It is computed once per run
from the fixed capacities. Ties at the cut are included, so the share of cells that counts as rich can be above a
quarter; the viewer states the share it actually covers. Sugar + spice rather than sugar alone because pollution devalues
both in the agents' welfare.

- The combat study writes them for an experiment with pollution, as `seed<k>-pollution.csv` (`t` plus the three
  columns, `periods + 1` rows), next to `seed<k>-combat.csv`. That file is required for a seed to count as done only when
  the experiment has pollution. An experiment without pollution writes nothing new, and its fingerprint and files are
  unchanged.
- The viewer's run takes its three new series from the same reading function, at the same point in the period, never
  recomputing.

## The viewer

### Map (option A)

- A new menu, **"Ground shows"**: *resources* (today's sugar and spice colours, the default) or *pollution*. Only
  offered when the run's experiment has pollution. It is independent of "Colour agents by" and of the marks.
- With *pollution*, each empty cell is coloured by its pollution band, from white (clean) to darkest (most polluted).
  Agents and marks are drawn on top exactly as now.
- **Bands** (my call, mirroring the wealth bands): band 0 is exactly 0; then (0, 1), [1, 3), [3, 10), [10, 30),
  [30, 100), [100, 300), [300, 1000), and 1000 or more: nine bands. Pollution has no sink in the model, so it grows
  without bound; at the rates above the world mean may reach the hundreds by t = 600, and fixed log-spaced bands keep
  early and late periods comparable. The frame carries one band byte per cell, computed in Julia from the model's
  pollution; the browser only maps a band to its colour.
- **Colours** (my call): a ramp from white through a muted tan to a dark olive-brown (the tight spots are the credit
  mode's grey `#9ca3af` mid-ramp and the wealth mode's dark purple (60, 10, 60) at the dark end), adjusted as needed so that every
  agent colour of every mode stays at least 60 (RGB distance) from every ground colour, and the kill (black) and switch
  (gold) marks stay distinct from the ground, as the existing landscape palette is tested (julia/test/js/map.test.mjs).
  The mockup's dark brown is close to the disease mode's darkest reds, so the exact colours are the builder's, under
  that test.
- **Hover** shows the cell's pollution band (its range) under "Under the pointer", next to sugar and spice.
- The legend lists the bands with their colours when the ground shows pollution.

### Charts (both)

- **"Pollution"**: `mean_pollution` (whole world, neutral grey) and `agent_pollution` (where agents stand, brown) on one
  panel. Agents leaving fouled land shows as the brown line falling below the grey; coming back, the brown rejoining it.
- **"On the richest land"**: `share_rich`, fixed axis 0 to 1, with the caption stating the cut and the share of cells
  it covers.
- Both are shown only for a run whose experiment has pollution.
- Every chart marks the start of pollution and of diffusion as dotted vertical lines when the experiment has them.
- The dashed "where the study stops" line (today the constant `STUDY_END = 500` in charts.mjs) becomes the
  experiment's own steps, so it sits at 600 for the pollution experiments and stays at 500 for the others.

### The legend bug

`adoptRun` must not draw a new run's frames with the old run's legend. The builder chooses the fix, for example
clearing `state.legend` on adoption and drawing nothing new until the new run's legend has arrived, or fetching the
legend by run id and checking it. A test or the live check shows that switching between a pollution experiment and a
non-pollution one never mixes legends.

## Checks

- **Experiments:** both builders give `VI-1-assim-k4`'s config with exactly the pollution settings above changed, in
  all three worlds (`diffusion_passes` 1 in the book's, 100 in xl and today's), with the variant lines.
- **Pollution behaves correctly in today's world with every rule on:** a short run of `VI-1-pollution-t0`
  (or a test config with early starts) checks that pollution is 0 everywhere before its start; that from its start each
  period's increase equals α × harvest + β × burn summed over the agents, before diffusion; that diffusion conserves
  the world total and starts at its start period; and that nothing changes when the starts lie beyond the run.
- **Study:** a pollution experiment's seed writes `seed<k>-pollution.csv` equal to the readings; a non-pollution
  experiment's seed writes the same files as before (no new file, no new fingerprint line; the fingerprint's checksum of
  `julia/src` changes with any code change, as always).
- The harvest-and-burn arithmetic is already unit-tested (julia/test/test_movement.jl: formation and no pollution before
  the start; julia/test/test_xxl_speed.jl: travel cost counts as consumption pollution; julia/test/test_xxl_combat.jl:
  combat's harvest). An exact whole-world count would need a tally in the model, so the new tests check the
  combination instead (planning call): identical to `VI-1-assim-k4` before the start, onset at the start, diffusion
  starting at its period, and 100 passes conserving the total (with a floating-point tolerance).
- **Viewer series = study:** for a short run of a pollution experiment, the viewer's three new series equal the
  study's `seed<k>-pollution.csv` (as the existing series equal the combat CSV in julia/test/test_xxl_viewer_run.jl).
- **Viewer frames = model:** each cell's band in the frame is the band of the model's pollution at that period.
- **JS:** band colours, the colour-distance rule, legend contents, the hover line, chart entries and the start
  markers, in julia/test/js/.
- **Full suite** green (about 17 minutes).
- **Live check** in the browser pane: a `VI-1-pollution` run viewed past t = 350 with the ground on pollution, and
  switching to `VI-1-assim-k4` and back to see the legend fix. No viewer server left running afterwards.
- Review subagents on the finished branch.

## Existing tests that change

Adding the experiments and charts breaks tests that list every experiment or chart exactly. They get the new entries,
and nothing else in them changes (the user approves this with the document): `julia/test/test_vi1_reach.jl` (the id
list and the error-message list), `julia/test/test_xxl_viewer_run.jl` (`VIEWER_EXPS`), `julia/test/js/charts.test.mjs`
(the chart count), and the frame fixture in `julia/test/js/` if the frame layout changes (regenerated, not edited by
hand).

## Left to the builder

- The variant lines' wording; the reading function's name and file; frame layout details (a band byte per cell appended
  to the frame, with the layout's version bumped if the format requires it).
- The ground colours, under the colour-distance test.
- The adoptRun fix's mechanism.
- Docs: docs/xxl.md gets the two experiments (with the settings table) and the viewer's new ground menu and charts in its
  "Viewer" section; the "Pollution comes with a later experiment" line goes.

## Process

- Branch `vi1-pollution` from main (34afbc1). Nothing merged or pushed without the user's approval.
- Never start a study run without asking the user. Use Context7 for any dependency's docs before coding against it.
  Never leave a viewer server running after a check.
