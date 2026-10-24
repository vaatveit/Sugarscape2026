# Sugarscape xl

xl is the sugarscape at 10× the linear resolution: 500 × 500 sites instead of 50 × 50, with every distribution of
resources and agents scaled so that an xl run looks like a regular run, only more detailed. It exists to compare
the performance of different implementations of the same model: this Python model, the FLAME GPU 2 port in
`flamegpu/`, and a Julia implementation. This document is the contract they implement. It needs no Python.

xl is defined by two things: the map file `sugarscape/maps/sugar-map-xl.txt` and the configuration table below.
The design and its reasoning are in
[docs/superpowers/specs/2026-10-24-xl-design.md](superpowers/specs/2026-10-24-xl-design.md).

## The map

**File:** `sugarscape/maps/sugar-map-xl.txt`, 500 lines of 500 whitespace-separated integers from 0 to 4 (the sugar
capacity of each site), with LF line endings.
- The first line is the northernmost row, and the first number in a line is the westernmost site.
- Indexing sites [x, y] with x east and y north (y = 0 the southern row), the site (x, y) is on line 500 − y,
  number x + 1. This is the same format and orientation as the regular `sugar-map.txt`.
- SHA-256 of the file: `014091e7bc6ade8a6887c37f94c3edc4806c470a887fdfafbc2eefa84234c43d`. The repository
  marks the map files `-text`, so no checkout rewrites their line endings.

**Spice**, when a configuration has it, is the sugar map mirrored east–west: the spice capacity at (x, y) is the
sugar capacity at (499 − x, y). That is how the regular spice map relates to the regular sugar map (Fig IV-1), and
upscaling commutes with the mirror, so there is no separate spice file.

**How the map was made.** You don't need this to implement xl; it's here so the map can be audited or rebuilt.
The reference generator is `sugarscape/maps/xl.py`.
- The regular map's five terraces (capacity 0–4) are not a formula. The top terrace is exactly two discs, but the
  others are hand-shaped, so each terrace boundary is redrawn at 10× resolution instead. All arithmetic is float64,
  and coordinates are in regular-cell units, with regular cell i centred at i + 0.5. Nothing wraps around the
  torus, because the regular map's edges don't match across it.
  1. For each level ℓ = 1, 2, 3, 4, the region is the set of regular cells with capacity ≥ ℓ.
  2. At each regular cell centre, the signed distance is the Euclidean distance between centres to the nearest
     cell on the other side of the region's boundary: positive inside the region, negative outside.
  3. That field is interpolated bilinearly to the 500 × 500 fine centres. Fine cell j lies at regular index
     (j + 0.5)/10 − 0.5; positions beyond the outermost regular centres take the edge value.
  4. It is blurred with a separable Gaussian of σ = 5 fine cells (0.5 regular cells). The kernel is truncated at
     radius 15, normalised to sum 1, and the field is padded by replicating its edges.
  5. A fine cell is inside level ℓ if its blurred value is > 0 and it is inside level ℓ − 1.
  6. Its capacity is the number of levels it is inside.
- Properties, all tested:
  - In each 10 × 10 block, both the centre cell (offset 5, 5) and the majority value equal the regular cell's
    capacity, in all 2,500 blocks.
  - Each capacity's area is 100× its regular area to within 1.1%: ratios 0.9985, 0.9992, 1.0028, 1.0024 and 0.9893
    for capacities 0–4.
  - No blurred value lies within 10⁻⁴ of the threshold (the closest is 3.4 × 10⁻⁴), so the file regenerates
    identically on any machine.

## The configuration

An xl run starts from a regular configuration on the 50 × 50 map and changes exactly these settings. Anything
measured in sites scales by 10 along each side, anything counted per area scales by 100, and anything per agent,
per site or per period is unchanged.

| Setting | Regular | xl |
|---|---|---|
| World | 50 × 50 torus | 500 × 500 torus |
| Capacity map | `sugar-map.txt` | `sugar-map-xl.txt` |
| Initial agents | N | 100 · N |
| Vision range [lo, hi] | e.g. [1, 6] | [10 · lo, 10 · hi]. Each agent draws uniformly from every whole number in the range, e.g. 10, 11, … 60. |
| Starting block (x0, y0, w, h), for block placement | e.g. (0, 0, 20, 20) | (10 · x0, 10 · y0, 10 · w, 10 · h) |
| Tribal starting blocks (tribe, x0, y0, w, h, n) | e.g. (blue, 0, 0, 20, 20, 270) | (tribe, 10 · x0, 10 · y0, 10 · w, 10 · h, 100 · n) |
| Diffusion passes per diffusion period (rule D) | 1 | 100 |
| Everything else | | unchanged |

"Everything else" covers metabolisms, endowments, lifespans, fertility ages, foresight, growback, seasons, the
pollution rates, trade, credit, culture, combat, disease, the random seed and the number of periods.

Notes:
- **Diffusion.** One pass of rule D replaces each site's pollution with the mean of its four neighbours, which
  spreads pollution about 0.7 sites (standard deviation). Spread grows as the square root of the number of passes,
  so 100 passes reach 10× as many sites: the same share of the world.
- **What vision reaches.** Everything that looks as far as vision now reaches 10× as far, as movement does. That
  includes mate search within vision (the reference model's default rule S contact) and combat (rule C replaces
  movement and looks along the lattice out to vision). Trade, culture and disease still act between the four
  adjacent agents. Crowding is the same, and agents travel as far in world terms, so each meets about as many
  others per period.
- **Seasons** split the world into northern and southern halves at y = 250.
- **The largest registered vision** is [5, 24], which becomes [50, 240]. That is still less than half of 500, so
  opposite lattice scans never reach the same site.
- **Agreement is statistical.** An xl run's random stream differs from its regular run's, so implementations
  agree statistically, never site by site.

## Timing

So that implementations report comparable numbers, each seed's run is timed in three parts, as wall-clock seconds:

| Measure | What it covers |
|---|---|
| **setup** | Building the model: loading the maps and placing the founders, up to the state at t = 0. |
| **stepping** | The model's own periods, summed over all of them. |
| **metrics** | Collecting each period's metrics (t = 0 included), summed. This is the harness's work, not the model's. |

With them, report the number of periods and the agent count at the start and at the end. Report the machine too
(language and library versions, platform, processor) and whether runs shared the processor.

The Python runner writes these to `timing.csv` (one row per seed) and `machine.txt` in each result folder. The
first seed's setup includes one-off warm-up in a fresh process: in a regular run of `TEST-tiny`, 0.056 s for
seed 0 against 0.001 s for seed 1.

*Not defined here:* which metrics must agree between implementations, over how many seeds, and to what tolerance.
That belongs to the comparison work.

## The Python reference

- `sugarscape.xl.to_xl(config)` returns the xl configuration of a regular one, and refuses anything that isn't
  50 × 50 on `sugar-map.txt`.
- `python -m experiments.run <id> --xl` runs an experiment's xl version into `results-xl/`, with its own
  fingerprint: the xl configuration plus the map's SHA-256. Schelling and Ring World have no xl.
- `python -m viewer`: tick **xl** before Start to watch an xl run. Each site is drawn as one solid colour, with no
  smoothing. The landscape is paler and agents fill their site in colours that stand out against every site (3:1
  contrast or better). Agent size is off, and the newest 100 periods are kept.
- **Speed**, measured on the design prototype: about 4–6 s per period for II-4's rules (40,000 agents), and 6–10 s
  per period early in VI-1. The viewer took 6.6 s to step and draw II-4's first xl period. The Python model is the
  baseline being measured, so it hasn't been tuned for xl.
- The rule that diffuses pollution 100 times is `Config.diffusion_passes`. It defaults to 1 and is left out of
  regular fingerprints.
