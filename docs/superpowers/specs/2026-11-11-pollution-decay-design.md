# Pollution decay: design

Date: 2026-11-11. Builds on `VI-1-pollution` (docs/superpowers/specs/2026-11-11-vi1-pollution-design.md; docs/xxl.md,
"VI-1 with pollution" and its results) and the xxl viewer (julia/viewer/).

## Intent

The user wants to **see agents leave polluted areas and come back as the pollution decays**, in today's xxl society
with every other rule on.

The `VI-1-pollution` runs (docs/xxl.md, "Results (2026-11-11)") showed why that can't happen yet: nothing removes
pollution. Rule P only adds (book p.47) and rule D averages over neighbours on the torus, so the world's total only
grows (`diffuse!`, julia/src/landscape.jl). In those runs the number of agents on rich land dipped about 5% when
pollution started and then recovered, while the population grew on poor land; the world mean reached 217 by t = 600.

This work adds a **decay rule**, which the book doesn't have, and one experiment to watch it. The user's choices:

- **Pollution keeps being made while it decays**, so the land settles into a balance rather than cleaning up once.
  What the user expects to watch is a rotation: agents foul a patch, move to cleaner land, the abandoned patch
  recovers, and they come back.
- **A fouled patch is livable again about 50 periods after it is left: "nearly all" of its pollution gone** ("real
  pollution takes a while to decay").
- **Pollution and decay start at t = 350, as before; the run goes to t = 1000.**
- **Two charts:** agents on rich land over time, as a count (the user's own ask), and pollution on rich land against
  elsewhere (proposed by me, kept by the user).

## Goals

- A decay rule in the Julia model, off by default, so every existing run is unchanged.
- One experiment, `VI-1-pollution-decay`, runnable by the combat study and offered by the viewer.
- Readings, written by the study and charted by the viewer, that can tell agents really leaving rich land and
  returning from a reshuffle: counts, not only shares (the lesson of the last results).
- The viewer's rule holds for everything new: it never shows anything the model didn't do. The new series equal the
  study's numbers, and tests prove it.

## Non-goals

- No study runs as part of this work; the user is asked before any. Checks are the test suite and a live run in the
  viewer.
- No change to rule P, rule D, their rates (α = β = 1) or the diffusion schedule, and no change to any other rule.
- No decay in the Python original: the rule lives in the Julia port only, like `culture_rule` (the Python config has
  neither). The book runs and the Julia–Python agreement are untouched because the default is 0.
- No other removal rules (decay only on empty sites, absorption tied to sugar regrowth). They are further from
  anything in the book; they can come later if this one doesn't show what the user wants.
- No patch-level rotation measure (per-region occupancy over time). The map shows rotation; the charts show the
  world-wide counts. If the charts stay flat while the map shows movement, that is a finding to report, not a defect.
- No pass/fail bars: this is an experiment to watch.

## Anti-goals

- Any existing run changing: an experiment that doesn't set the decay must give byte-identical results. Its combat-study
  `fingerprint.txt` is unchanged too, because that text is the Python registry's config plus the experiment's own
  variant lines, and the Python config doesn't get the field. (*My call*, from the code: the extinction study's
  checkpoint headers, `seed_header` in julia/src/xxl/extinction.jl, list every field of the Julia `Config`, so they
  gain `pollution_decay=0.0`, as they gained `culture_rule` when it was added in 948b68d. A resumed extinction study
  from older checkpoints reruns the seeds it can't match; nothing else reads those headers.)
- A chart or picture drawn, smoothed or inferred in the browser instead of read from the model's state.
- A chart that shows a share where the user asked for a count.

## The rule: `pollution_decay`

- A new config field `pollution_decay::Float64 = 0.0` (δ), in julia/src/config.jl beside the other pollution fields.
  Validation: 0 ≤ δ < 1, with a message in the style of the neighbouring checks. With δ > 0 it needs nothing else
  (no pollution, no decay to do; a run with `pollution = nothing` simply decays an all-zero field).
- **Where it acts:** at the end of `step!` (julia/src/model.jl), after growback and after the diffusion block, before
  `m.t += 1`: every site's pollution is multiplied by (1 − δ). With δ = 0 nothing is done (no multiply, so runs stay
  bit-identical).
- **When it acts:** every period, whether or not pollution is being made (`pollution_active`) and whether or not
  diffusion runs that period. There is no decay start and no gate on `pollution_start`: before pollution starts the
  field is all zero, so decaying it changes nothing, and "decay starts at t = 350" only ever means "there is something
  to decay from t = 350". After a `pollution_stop` it keeps acting, which is what makes pollution fall.
- **Arithmetic per period:** a site's pollution at the end of period t is (its pollution at the end of t − 1, plus
  what agents made on it during t, then diffused if diffusion runs) × (1 − δ).
- **No scaling between worlds.** The xl transform (julia/src/xl.jl) scales space (diffusion passes × 100), not time,
  so δ is the same per period in the book's world, xl and today's. `to_xl` and `to_xxl` leave it as set.
- Documented in docs/xxl.md as an xxl-era extension that the book doesn't have, with its default.

### The rate

"Nearly all gone in 50 periods" taken as nine-tenths (*my conversion*): (1 − δ)^50 = 0.1 gives δ = 0.0450, and the
experiment uses **δ = 0.045** (0.955^50 = 0.100; half gone in about 15 periods).

What to expect (*my estimate*, from the `VI-1-pollution` runs: agents make about 2.5 units a period each, about 1 per
cell at today's population): the world mean settles near production ÷ δ ≈ 21, reached within about 50 periods of the
start, against 217 and rising at t = 600 without decay. With 100 diffusion passes a period, pollution mostly stays
within about 25 cells of where it is made.

## The experiment: `VI-1-pollution-decay`

`VI-1-pollution` (itself `VI-1-assim-k4` with pollution added) with the decay added and the run lengthened; nothing
else changed (seeds, combat, culture rule, curve, h, sex, trade, credit, inheritance, disease, and the xxl defaults
today's world applies).

| Setting (book config) | `VI-1-pollution` | `VI-1-pollution-decay` |
|---|---|---|
| `pollution` (α, β) | (1.0, 1.0) | (1.0, 1.0) |
| `pollution_start` | 350 | 350 |
| `pollution_stop` | none | none |
| `pollution_decay` | 0 | 0.045 |
| `diffusion_period` | 1 | 1 |
| `diffusion_start` | 450 | 450 |
| `diffusion_passes` | 1 (100 in xl and today's world) | same |
| steps | 600 | 1000 |

- Diffusion stays at t = 450 (*my call*), so the only differences from `VI-1-pollution` are the decay and the length.
- Defined in julia/src/xxl/vi1_combat.jl next to the other pollution experiments, built for all three worlds, with a
  variant line appended to both fingerprints as the others do; added to the combat study's experiment list and usage
  (julia/src/xxl/combat_study.jl) and to `VIEWER_EXPS` (julia/viewer/run.jl).

## The readings (the study's numbers)

Four new columns in `seed<k>-pollution.csv`, read at the end of the period with the existing pollution readings
(julia/src/xxl/combat_readings.jl), for **every experiment with pollution** (*my call*: the counts are what corrected
the last reading, so the earlier pollution experiments get them too):

| Column | Meaning |
|---|---|
| `agents_rich` | the number of agents standing on rich land (0 with no agents) |
| `agents_other` | the number of agents standing on the other cells (0 with no agents) |
| `pollution_rich` | the mean pollution over the rich cells |
| `pollution_other` | the mean pollution over the other cells |

`agents_rich + agents_other` is the population. Saved pollution files from the earlier runs keep their four columns:
nothing in the code reads saved pollution files (the viewer shows live runs only), so no fallback for missing columns
is needed.

Rich land is unchanged: cells with sugar + spice capacity at or above the 75th percentile of that sum, computed once
per run (`rich_cut`). The existing columns (`t`, `mean_pollution`, `agent_pollution`, `share_rich`) keep their names,
order and meaning; the new ones are appended after them. An experiment without pollution still writes no pollution
file.

## The viewer

Two new charts, shown for every run whose experiment has pollution, after the existing "Pollution" and "On the
richest land" charts:

- **"Agents on rich land"**: `agents_rich` as a count on its own axis (the user's chart). *My call*: a second line
  with `agents_other`, the agents off rich land, in the neutral grey, because the two counts side by side are what
  showed the population growing on poor land. The builder may drop it if it crowds the chart.
- **"Pollution on rich land and elsewhere"**: `pollution_rich` and `pollution_other` on one panel, with the same
  colours the "Pollution" chart uses for its two lines where they fit.

Both take their series from the new readings at the same point in the period, never recomputing. The existing
dotted start markers apply: for an experiment whose decay is above 0, the t = 350 marker names the decay with the
pollution (for example "pollution on, decays 4.5%"), and the t = 450 marker says that diffusion starts. The dashed "where the study stops" line
sits at the experiment's steps, 1000. The pollution legend entry gains the decay rate, and a chart caption or the
legend states it ("decay 4.5% a period").

The map needs nothing new: the pollution ground already shows the model's pollution in bands, and with decay the
world settles in the lower bands.

## Checks

- **Rule:** validation rejects δ < 0 and δ ≥ 1; δ = 0 leaves a run byte-identical (a short run of an existing
  experiment against its saved or freshly computed result); on a small world with a set pollution field and no agents,
  one step multiplies every site by (1 − δ), after diffusion when diffusion runs; with `pollution_stop` the world total
  falls by (1 − δ) a period; the decay acts in periods when diffusion doesn't run.
- **Experiment:** its configs equal `VI-1-pollution`'s with exactly `pollution_decay` and the steps changed, in all
  three worlds, with the variant line; identical to `VI-1-pollution` before t = 350 in today's world (a short run).
- **Readings:** hand values for the four new columns, and `agents_rich + agents_other` equal to the population, on a small world (as the existing readings test does); the
  study writes them for a pollution experiment and still writes no pollution file for one without.
- **Viewer series = study** for a short run of the new experiment, as for the existing pollution series.
- **JS:** the two chart entries, their `when`, the markers' decay wording, the caption or legend text.
- **Full suite** green. **Live check** in the browser pane: a `VI-1-pollution-decay` run viewed past t = 450 with the
  ground on pollution, the two new charts drawing, no console or server errors, and no viewer server left running.
- Review subagents on the finished branch.

## Existing tests that change

Adding an experiment, a config field, four columns and two charts breaks tests that list every one exactly. They get
the new entries and nothing else changes (the user approves this with the document):

- `julia/test/test_vi1_reach.jl`: the experiment id lists.
- `julia/test/test_xxl_viewer_run.jl`: `VIEWER_EXPS`; the pollution series list if it is listed exactly.
- `julia/test/test_vi1_pollution.jl`: `VP_FIELDS` gains `:pollution_decay` if the experiments test needs it to compare
  the new experiment's other fields.
- `julia/test/test_xxl_pollution_readings.jl`: the column list and header check gain the four columns.
- `julia/test/js/charts.test.mjs`: the chart count and key list.
- Fixtures in julia/test/js/ only if the legend or frame layout changes (regenerated, not edited by hand).

## Left to the builder

- The variant line's wording, the validation message, the names of helper functions.
- Whether the decay is a loop or a broadcast, as long as δ = 0 does nothing at all.
- Chart colours within the viewer's existing palette, and the exact caption wording.
- Docs: docs/xxl.md gets the rule (in "VI-1 with pollution" or a short section of its own), the experiment's settings
  table and the new columns; the viewer section gets the two charts.

## Process

- Branch `pollution-decay` from main (28f0962). Nothing merged or pushed without the user's approval.
- Never start a study run without asking the user (a 20-seed, 1000-period study would take about 1¾ h with 5
  workers, by the last runs' pace). Use Context7 for any dependency's docs before coding against it. Never leave a
  viewer server running after a check.
