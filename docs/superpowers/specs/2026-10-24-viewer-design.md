# Sugarscape Viewer — Design

Date: 2026-10-24. Follows [the project design](2026-10-21-sugarscape-design.md), whose non-goals deferred "a viewer
[until] after the core is verified". The core is now verified (tags `v1.0`, `v1.1`).

## Intent

Watch a run of the simulation unfold: the landscape, the agents on it, and the population over time. Start from a
registered experiment, choose a seed, press play, and scrub back to any period already seen. The viewer exists to
*look at* the model, so it must never show anything the model didn't do.

**Goals**
- A browser tab showing the 50×50 world grid with cells colored by their current sugar and spice, and every agent
  drawn in its cell.
- Agent color and size driven by attributes the user picks from menus. First attributes: **tribe** and **wealth**
  (wealth = sugar + spice; on sugar-only runs spice is 0, so wealth is sugar).
- A population-over-time chart beside the board.
- Play, pause, speed, and a time slider to scrub back and forth through the periods already computed.
- Runs use a registered experiment's settings exactly; the user chooses only the seed.

**Non-goals (this version)**
- Editing parameters other than the seed (a later step, by the user's wish).
- The Schelling and Ring World experiments (`SchellingConfig`, `RingConfig`): their worlds aren't the sugar/spice
  grid. The picker lists only experiments whose config is a `sugarscape.config.Config`.
- Pollution, loans, friendship or trade networks, disease maps, other charts. Any of these can be added later.
- Exporting video or images.
- Serving anyone but the local user: the server binds to 127.0.0.1.

**Anti-goal (the user's one wince).** The visualization must faithfully represent the underlying data. Concretely:
- Every visual encoding is a fixed, documented function of model values, and a legend lets the viewer read it back.
- No encoding rescales from frame to frame, so the same look means the same amount at every period.
- What the board shows at period t is the model's actual state at t, produced by the model's own code (not a
  reimplementation), and the chart counts exactly the agents the board draws.
- Tests check all of this (see Verification).

## What the user sees

One page, laid out board-first: the board, with the population chart beside or under it, a control bar, the
attribute menus, and the legend. Exact layout is the builder's.

### Starting a run
- **Experiment picker:** every registered experiment with a `Config`, by id and title, the book's experiments first
  and the `VAR-` variants after them.
- **Seed:** the run index k, as everywhere else in the project (run k uses `config.seed + k`; k = 0 to `seeds − 1`
  are the registered runs, whose results the report scores). Any k ≥ 0 is allowed. The page also shows the actual
  seed. *(My call: index rather than raw seed, so "seed 3" here is seed 3 in `results/`.)*
- Starting a run discards the previous one.

### The board (the user chose option A from three mockups)
- **Cells:** color blends sugar yellow and spice rust over a white background, by each cell's current level.
  - The blend must be **one-to-one**: two cells with different (sugar, spice) pairs never get the same color. The
    mockup's rescaling (shrinking s and p when s + p > 1) broke this and must not be used. One way that works: color
    = white + a·s·(yellow − white) + b·p·(rust − white), with a, b chosen so no channel ever clips.
  - "One-to-one" applies to the colors **as drawn** (integer RGB, 0–255 per channel), at the model's own
    resolution. On the registered runs, cell levels are multiples of 1/8: growback adds 1 or refills to capacity,
    seasonal winter growback adds 1/8, and harvesting sets a cell to 0. So 0 to 4 in steps of 1/8 gives 33 levels
    per resource. All 33 × 33 (sugar, spice) pairs must draw as distinct colors. Hover gives exact values at any
    resolution. *(My call, after the review.)*
  - Levels are scaled by a fixed maximum for the run (the landscape's highest capacity, which is 4 on the book's
    maps), never by the current frame's maximum.
  - On sugar-only experiments, spice is 0 everywhere and the cells are shades of yellow alone.
- **Agents:** a dot centered in its cell.
- **Orientation:** y increases upward, as the book draws the landscape (the existing diagnostics use
  `origin="lower"`).
- **Which moment:** the board at period t shows the state after period t's rules have all run (after
  `Model.step()` has returned t times); t = 0 is the initial placement. This matches `Model.run`'s observer.

### Attribute menus
- **Color by:** tribe | wealth | none.
  - Tribe: red and blue, as the book colors them (`Agent.tribe`).
  - Wealth: one color per wealth band, from a sequential ramp.
  - None: one neutral color.
- **Size by:** wealth | none. Wealth uses one size per band; none uses a single size.
- **Defaults:** color by tribe and size by wealth.
- **Runs without tribes:** when `Agent.tribe` is `None` (no cultural tags), the tribe option is disabled and color
  falls back to none.
- **Wealth bands (user-approved):** < 10, 10–30, 30–100, 100–300, ≥ 300. They are the same for every run and every
  period, with lower bounds inclusive.
- Other attributes (vision, metabolism, age, sex, disease) are out of scope now, but the menus must be easy to
  extend.

### Legend
- **Cells:** a small 2-D swatch grid, sugar along one axis and spice along the other (0 to the run's maximum), so any
  cell color can be read back to its two amounts.
- **Agents:** the tribe colors, or the five wealth bands with their color or size, whichever the menus have chosen.

### Hover
- **Over a cell:** its coordinates, sugar and spice levels, and capacities.
- **Over an agent:** its id, wealth, sugar, spice, tribe, vision, metabolism, age and sex.
- Values are shown as the model holds them, rounded only for display (e.g. two decimals).

### Population chart
- Population (the number of living agents) against t for every period computed so far.
- A vertical marker sits at the period on the board, and clicking the chart jumps there.
- The y-axis may grow as the run goes on (an axis with labeled ticks is readable at any scale; this is not an
  encoding that misleads).

### Time controls
- Play/pause, a speed control, and step forward and back by one period.
- The slider spans t = 0 to the latest computed period.
- Playing past the last computed period computes new ones; the run continues until paused, with no cap at the
  experiment's registered `steps`. The registered length is shown for reference.
- Computation happens only while playing, at most a short way ahead of the board, and stops on pause, so a paused
  run never grows. "How far ahead" is that short lead. *(My call, after the review.)*
- Dragging the slider or clicking the chart shows that period at once.
- **Responsiveness target:** scrubbing within a computed run feels immediate (well under a second to show a
  period). Playback speed is limited by how fast the model computes. The page shows the current t, the
  population, and how far ahead the computation has got.

## How it's made (my calls, not the user's)

- **Server:** a small local Python server using only the standard library (`http.server` or `asyncio`; no new
  dependencies), in a new top-level package `viewer/`. It's started with `python -m viewer`, picks a free port,
  binds 127.0.0.1, prints the URL and opens the default browser.
- **Model:** the server builds the model exactly as `experiments/run.py` does
  (`replace(exp.config, seed=exp.config.seed + k)`, then `Model(...)`) and steps it with `Model.step()`. The viewer
  never changes model code.
- **Page:** plain HTML, CSS and JavaScript drawing on a `<canvas>`, served by the same server. No build step and no
  front-end libraries. The population chart is drawn on a canvas too.
- **Encoding module:** the cell blend, wealth bands, band colors and sizes, and tribe colors live in one small
  JavaScript ES module. It is tested with Node's built-in test runner (`node --test`; Node 25 is installed here),
  with no npm packages.
- **Packaging:** add `viewer*` to `[tool.setuptools.packages.find]` and the static files to package-data.

## Verification

- **Frame fidelity (pytest).** For a few experiments (one sugar-only, one with spice and tribes, e.g. II-4 and
  VI-1) and several periods, each frame the server serves matches a model stepped independently to the same t:
  - every agent's id, position, sugar, spice, tribe, vision, metabolism, age and sex;
  - every cell's sugar and spice level;
  - the population count.
- **Scrubbing (pytest).** Requesting period t after the run has gone past it returns the same frame as when t was
  first computed.
- **Encoding (node --test):**
  - the cell blend never clips, and its drawn (rounded) colors are distinct for all 33 × 33 (s, p) pairs on the
    1/8 grid from 0 to 4;
  - band boundaries (9.99, 10, 30, 100, 300) land in the right bands;
  - the legend's swatches and bands come from the same functions the board uses.
- **Browser check.** Open the page, run II-4 and VI-1, scrub, switch menus, hover. Before calling the viewer done,
  confirm that the board, legend and chart agree with the frame data.

## Left to the builder

- Page layout, styling and the exact color values: rust and yellow close to the mockup, tribe red and blue
  distinguishable, and a wealth ramp ordered light to dark.
- How periods are stored for scrubbing (every frame kept, checkpoints with replay, or something else), as long as
  values are exact and a long run (III-8 registers 6,000 periods) stays within reasonable memory.
- The transport (polling or streaming) and the frame format.
- The speed control's range.
- Error handling for a bad seed or a model exception: show it on the page and leave the server running.
