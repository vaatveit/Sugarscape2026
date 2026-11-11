# xxl Viewer — Design

Date: 2026-11-10. Follows the combat studies of 11-08 to 11-10 (VI-1-combat through VI-1-assim-k4). The Python viewer
(`viewer/`, [its design](2026-10-24-viewer-design.md)) shows book and xl runs of the Python model; nothing shows a run
of the Julia port in today's xxl world, where those studies ran.

## Intent

Start a fresh xxl run of a combat-study experiment and watch it live: the two tribes spreading over the 500 × 500
world, fighting where they meet, and assimilating. Alongside, the rest of what a VI-1 run does: trade, credit,
inequality and disease. The user sets the experiment, the raw seed, combat hostility h and the combat curve k.

**Goals**
- A browser page showing today's xxl world with every living agent drawn in its cell, a period at a time, as the Julia
  model computes it.
- The map's default look (the user chose option A of three mockups): agents blue or red by tribe; black crosses where
  kills happened in the last 10 periods and gold rings on agents that changed tribe in the last 10 periods, both fading
  with age; the landscape faint underneath.
- A colour menu for the agents: **tribe** (default), **culture shade** (the user asked for mockup B's shading as an
  option), **wealth**, **disease** and **credit** (definitions below). The kill and tribe-change marks stay on in every
  colour mode.
- Charts under or beside the map, each over all periods computed so far, with a line at the period shown and a marker
  at period 500 (where the study stops): population by tribe; kills per period; tribe changes per period; Gini of
  wealth; trades per period and mean price; loans outstanding and total debt; share of agents sick. Plus a Lorenz curve
  of wealth for the period shown.
- Before Start, the user sets: the experiment, the **raw seed** (the number the model's random generator gets, not the
  run index; the user's choice), **h** (`combat_hostility`) and **k** (`combat_curve`). h and k start at the chosen
  experiment's own values.
- Play, pause, step, a speed limit, and a time slider to scrub back through the newest periods kept.

**Non-goals (this version)**
- Pollution in v1. None of the eight experiments has the pollution rule, so the layer would always be blank. It comes
  with the pollution experiment planned next (below).
- Trade on the map (lines between partners): today's runs make roughly 50,000–100,000 trades a period, too many to
  draw. Trade is shown in the charts.
- Replaying saved runs; setting any parameter beyond experiment, seed, h and k; the book and xl worlds; experiments
  other than the eight VI-1 ones; exporting video or images; changes to the Python viewer; serving anyone but the local
  user.

**Next, after v1 (the user, 11-10):** a new VI experiment with pollution and every other rule on, to be watched in this
viewer. v1 does not build it, but its structure must leave room for it: the experiment list, the colour menu and the
charts are lists that a later experiment can extend (for example a pollution layer on the landscape and a pollution
chart) without reworking the page or the frames.

**Anti-goal (the user's one wince): the viewer must not show anything the model didn't do.** Concretely:
- What the page shows at period t is the Julia model's actual state at t, produced by the model's own code (the same
  `step!` the studies run, no reimplemented rule), and every chart counts exactly what the model counted.
- Every visual encoding is a fixed, documented function of model values, with a legend to read it back, and none
  rescales from frame to frame: the same look means the same amount at every period.
- Tests check this (see Verification).

## How it gets made (the user's choices)

- **All Julia** (the user chose it over feeding the Python viewer from a Julia process): a small web server inside the
  Julia package runs the model and serves the page and its frames. One command starts it, for example
  `julia --project=julia julia/xxl_viewer.jl`, then the user opens the printed `http://127.0.0.1:<port>/` address.
- **HTTP.jl** is added to `julia/Project.toml` as the first package outside the standard library. *(The user accepted
  this with the all-Julia choice.)* Look up its current documentation (Context7) before writing code against it.
- The page is plain HTML, CSS and ES-module JavaScript with no build step, adapted from the Python viewer's
  `viewer/static/` (canvas board, hover, slider, legend, pace control). It talks only to the Julia server.
- The server binds to 127.0.0.1 only.

## What the user sees

### Starting a run
- **Experiment:** the eight VI-1 experiments of the combat study (`JULIA_COMBAT_EXPS`), in this order: VI-1-combat,
  VI-1-distance, VI-1-near, VI-1-far, VI-1-far-speed, VI-1-assim, VI-1-assim-random, VI-1-assim-k4. Default:
  VI-1-assim-k4. *(My call: the study's Chapter III experiments, `COMBAT_EXPS`, also have two tribes but no trade,
  credit or disease, so they are left out.)*
- **Raw seed:** any non-negative integer. Default: the experiment's base seed. When it equals base seed + k for a k in
  the experiment's registered runs, the page says "= run index k". *(My call: helps match a saved `seed<k>-combat.csv`.)*
- **h and k:** number fields, defaulting to the experiment's today-world values. The model's own config checks decide
  what is allowed (for example, the assimilation rules refuse h outside (0, 1)); a refused setting shows the model's
  error message and starts nothing.
- The settings in force (experiment, raw seed, h, k) stay on screen for the whole run.
- Starting a run discards the previous one.

### Running
- The model steps in the background as fast as it can (about 1 s a period at 60,000+ agents for stepping and the
  standard metrics, from the 11-10 timings; the viewer's own readings add to that, and must not stall the server),
  until the user stops it or the population reaches 0. There is no fixed end; period 500 is only marked.
- The page plays periods at the chosen speed limit, never ahead of what is computed. When it catches up with the newest
  period it shows each new one as it arrives. Pause, step forward and back, and the slider work over the periods kept.
- Periods kept for the map: the newest 100 *(my call, as the Python viewer's xl runs)*. Older periods remain in the
  charts, shaded as no longer on the map.

### The map
- 500 × 500, one cell per site, y increasing upward (as the Python viewer).
- **Landscape:** faint, so the agents read first. Sugar and spice levels by a fixed, one-to-one blend, scaled by the
  landscape's fixed maximum capacity, never the frame's maximum (the Python viewer's rule, paler).
- **Agents**, by the colour menu:
  - *Tribe* (default): blue or red, by the model's own tribe label (the one the combat readings count as `n_blue` /
    `n_red`).
  - *Culture shade:* 12 fixed steps from blue (no 1-tags) to red (all 11 tags 1), by the count of 1s in the agent's
    tags.
  - *Wealth:* sugar + spice, in fixed logarithmic bands chosen once for all runs (wealth has no upper bound, so the
    bands cannot stretch with the frame). The last band is open-ended.
  - *Disease:* the number of diseases the agent carries, in fixed steps, 0 drawn neutral.
  - *Credit:* lender, borrower, both, or neither, read from the model's loan book.
- **Event marks**, on top of any colouring:
  - Kills: a black cross at the cell where the victim died, for each kill in the last 10 periods, its opacity falling
    linearly with age (fixed schedule).
  - Tribe changes: a gold ring on each agent whose tribe label differs from its label one period earlier (the agents
    the combat readings count in `tribe_changes`), for changes in the last 10 periods, fading the same way.
- **Hover:** over an agent, its id, tribe, 11 tags, sugar, spice, age, diseases and loans; over an empty cell, its sugar
  and spice. Exact values.
- A legend for the active colouring and for the marks.

### The charts
Each is a line over periods 0 to newest, with a vertical line at the period on the map and a marker at 500:
- Population: blue and red.
- Kills per period (blue victims, red victims).
- Tribe changes per period.
- Gini of wealth.
- Trades per period, and mean price.
- Loans outstanding, and total debt: the sum of `Loan.due` over `m.loans` (principal plus interest, what borrowers
  owe), labelled so. *(My call.)*
- Share of agents sick.
- Lorenz curve of wealth at the period on the map (from the same values as the Gini).

Clicking a chart jumps the map to that period if it is still kept.

## Faithfulness rules
- The run is built exactly as the combat study builds seed k of the experiment in the today world (`world_config(exp,
  "today")`, `XXL_DEFAULTS`), except that the seed is the raw seed and h and k are the user's. With the experiment's
  own h and k and raw seed = base seed + k, the run is the study's seed k.
- Each chart value is the value the study's own readings produce for that period: the combat readings
  (`CombatReadings` / `combat_period!`) for population, kills and tribe changes, and the standard metrics
  (`collect_metrics` / `xxl_metrics!`, the `seed<k>.csv` columns `gini`, `trades`, `mean_price`, `n_loans`,
  `fraction_sick`) for the rest. Total debt, the Lorenz curve and the event positions are new readings, taken from the
  model's state in the same pass.
- The marks count what the charts count: the crosses of period t number `killed_blue + killed_red` of t; the rings
  number `tribe_changes` of t.
- The map draws exactly the living agents the population chart counts.
- A value the model leaves undefined (`NaN`, for example `mean_price` in a period with no trades) is carried as
  undefined and drawn as a gap, never as 0. The frame format must carry it (plain JSON cannot).
- Kill positions are the victims' cells, read from `m.dead_this_step` filtered by `m.killed`; `m.kill_log` has none.
- Tribe is the model's `tribe(a)`: blue when 0-tags outnumber 1-tags, so culture-shade steps 0–5 ones are the blue
  tribe and 6–11 the red.

## Verification
- **Matches the study:** for a short run (for example 30 periods) of a combat experiment with its own h and k and raw
  seed = base seed + k, every charted series equals the corresponding columns of that experiment's `seed<k>-combat.csv`
  and `seed<k>.csv` from `run_combat_world("today", …)` over the same periods.
- **Settings reach the model:** a run started with h and k shows them in the model's config, and a refused setting
  starts nothing.
- **Marks and map agree with the counts:** at each period, crosses = kills, rings = tribe changes, agents drawn =
  population.
- **Encodings are fixed:** the colour of a given value is the same in every frame; the culture shade has 12 distinct
  steps; the wealth bands are constants.
- The full suite stays green, and the new tests keep its time reasonable (a few short runs, not 500-period ones).

## Left to the builder
- Page layout beyond "map first, charts and controls around it"; colours other than those named above; the wealth
  bands' edges and the disease steps (fixed, documented in the legend).
- How frames travel (binary or JSON) and how the server and the stepping share the model (a background task, a lock,
  a queue).
- Exact file names and where the viewer's code sits in the package (under `julia/src/`, with the page's static files
  alongside or in a new top-level folder).
- How the JavaScript is tested, if beyond the Julia tests.
