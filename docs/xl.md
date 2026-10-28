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
| Vision range [lo, hi] | e.g. [1, 6] | [10 · lo, 10 · hi], in steps of 10: each agent draws 10 · v, with v uniform on lo … hi, e.g. 10, 20, … 60. |
| Look stride k: along each lattice line, agents look at one random site for each k of vision, centred k, 2k, … sites away | 1 | 10 |
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
- **Looking.** Every rule that looks along the lattice out to vision looks, in each of the four directions, at one
  site for each 10 of vision. For k = 1, 2, … vision / 10, the k-th site is 10k + a − b sites away, with a and b
  each drawn uniformly from 0 … 9: that is how far a random site of the regular cell k cells away lies from a random
  site of one's own regular cell. The distance runs from 10k − 9 to 10k + 9, peaked at 10k (a triangular
  distribution). Neighbouring sites' ranges overlap, so the same distance can come up twice. It is looked at once,
  and the distances are taken nearest first. The farthest look is vision + 9 sites away. Each direction and look
  gets its own draws.
  These rules are movement (rule M), combat (rule C: its target search, and its check for retaliation from the site
  it would take) and mate search within vision (the reference model's default rule S contact). Partners in sight
  are taken nearest first across all four directions, east, west, north, south at equal distances. So an agent
  checks as many sites as in the regular run, as far away on average, and can land on any site. Everything else
  about the rules is unchanged: the nearest of the best sites wins, by its actual distance.
- **Why the stride.** Looking at every site gave each agent 10× as many sites to choose from, with crowding
  unchanged, so an agent almost always found a site that had regrown enough. In II-4, agents with metabolism 3 and
  low vision then broke even instead of running at a loss, nobody starved after t ≈ 80, and the regular run's slow
  die-off (about 4% of the population between t = 100 and 500, all of them metabolism 3 and vision 1–4)
  disappeared. With the stride, II-4's population at each of t = 60, 100, 200, 300 and 500 is 2.5–3.4% above 100 ×
  the regular run's. Its mean sugar, mean metabolism, Gini and share of agents on capacity-3 or -4 sites are within
  1.1% (10 seeds; t = 401–500 for the last four).
- **Why centred.** An earlier version drew each site uniformly from its stretch: one of the sites 1–10 away, one of
  11–20, and so on. Those average 5.5, 15.5, … sites, 4.5 sites nearer than the 10, 20, … of the regular cells they
  stand for, so xl agents saw about half a regular site less far. That cost little in II-4 (population within 1.2%
  of regular), but IV-A3's population fell 13–23% below regular from t = 25 to 300. It fell 25% below at t = 100
  with trade switched off at both scales too, so trade wasn't the cause. With centred sites, IV-A3's population is
  within 6% of regular at every checkpoint from t = 10 to 300: 124.6, 87.1, 69.0, 42.3 and 32.1 against 126.0,
  90.4, 73.2, 44.0 and 33.7 at t = 25, 50, 100, 200 and 300. Regular seeds differ from each other by a standard
  deviation of 5.7–9.5 agents there (10 seeds each).
- **Why random sites, not every 10th site.** Looking exactly 10, 20, … sites away matched II-4 as
  well, but an agent moving in steps of 10 never changes its x mod 10 or y mod 10. The world split into 100
  interleaved 50 × 50 worlds that never competed for food: 100 regular runs side by side, not one finer world.
- **Neighbours.** Agents have more adjacent neighbours than in the regular run: 1.07 per agent against 0.79 in II-4
  (t = 401–500), and 0.58 against 0.26 in IV-A3 (t = 201–300). The cause is adjacency itself, which is one site at
  both scales even though one regular site stands for a 10 × 10 block of xl sites:
  - In a regular run, 72% of moves are one site long, so the site an agent just left is usually next to it, eaten
    and empty: 77% of agents have one of their own last two sites adjacent. In xl, moves are many sites long, and
    only 15% of agents do.
  - The terrain-corrected chance of finding another agent one site away, relative to chance, is 0.85 in regular II-4
    against 0.99 in xl. Leaving each agent's own trail out, it is 1.06–1.09 against 1.02.
  - These figures were measured with the earlier uniform look. Finer peak edges account for only a little of the
    gap: a capacity-3 or -4 site has 0.994 of its four neighbours on such sites on the xl map, against 0.944 on the
    regular map.

  II-4 doesn't use neighbours, but trade, culture, disease and rule S with the four-neighbour contact do. In IV-A3,
  xl agents trade twice as often each (37.9 trades a period, divided by 100, against 18.0, with about as many
  agents), and prices spread more (standard deviation 0.56 against 0.36). Mean sugar is 14% lower, and the Gini
  0.38 against 0.35. Making the neighbourhood scale with the map would be a change to the rules, not yet decided.
- **Seasons** split the world into northern and southern halves at y = 250.
- **The largest registered vision** is [5, 24], which becomes [50, 240]. Its farthest look, 249 sites, is still
  less than half of 500, so opposite lattice scans never reach the same site. `Config` refuses any vision whose
  farthest look (vision + look stride − 1) reaches half the grid.
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
first seed each process runs includes one-off warm-up in its setup: in a regular run of `TEST-tiny`, 0.056 s for
seed 0 against 0.001 s for seed 1. With `--jobs J`, each of the J worker processes pays it on its first seed (with
`--jobs 2`, seeds 0 and 1 both took about 0.06 s and the rest about 0.001 s).

*Not defined here:* which metrics must agree between implementations, over how many seeds, and to what tolerance.
That belongs to the comparison work.

## The Python reference

- `sugarscape.xl.to_xl(config)` returns the xl configuration of a regular one, and refuses anything that isn't
  50 × 50 on `sugar-map.txt`.
- `python -m experiments.run <id> --xl` runs an experiment's xl version into `results-xl/`, with its own
  fingerprint: the look rule (`look: centred`), the xl configuration and the map's SHA-256. Schelling and Ring
  World have no xl.
- `python -m viewer`: tick **xl** before Start to watch an xl run. Each site is drawn as one solid colour, with no
  smoothing. The landscape is paler and agents fill their site in colours that stand out against every site (3:1
  contrast or better). Agent size is off, and the newest 100 periods are kept.
- **Speed**, one process (`--jobs 1`), one seed at a time, stepping only, over each experiment's full run
  (centred look; `results-xl/*/timing.csv`):

  | Experiment | Periods × seeds | Agents, start → end | s per period, mean (seed range) | Total stepping |
  |---|---|---|---|---|
  | II-4 | 500 × 10 | 40,000 → about 23,800 | 1.33 (1.08–2.09) | 111 min |
  | II-4-gini | 500 × 10 | 25,000 throughout | 1.67 (1.26–2.52) | 139 min |
  | II-6 | 300 × 5 | 40,000 → about 20,100 | 2.07 (1.73–2.41) | 52 min |
  | II-7 | 500 × 5 | 40,000 → about 17,600 | 1.04 (0.83–1.36) | 44 min |
  | II-8 | 200 × 5 | 40,000 → about 19,100 | 1.35 (1.22–1.70) | 23 min |
  | IV-A3 | 300 × 10 | 20,000 → about 3,200 | 1.11 (1.07–1.17) | 56 min |
  | VI-1 | 500 × 5 | 20,000 → 59,600–100,000 | 16.4 (9.6–25.2) | 685 min |

  - Other programs were running on the machine at times, which accounts for part of the spread between seeds.
    VI-1's spread is mostly its population: its seeds end with very different numbers of agents.
  - Early in II-4 (40,000 agents), a period takes about 2.4 s. The centred look's extra draws and sorting account
    for about a quarter of that: 2.43 s against 1.89 s with the earlier uniform look, timed together over t = 3–10.
  - Ten II-4 seeds sharing the processor (`--jobs 10`) averaged 3.2 s per period, with other programs also
    running.
  - Replacement (rule R) replaces about 900 agents a period in II-4-gini. Finding each newcomer's site by
    scanning all 250,000 sites had taken 12.95 s per period, against 1.13 s with the occupancy mask (t = 3–7,
    uniform look).

  The Python model is the baseline being measured, so it hasn't been tuned for xl.
- The rule that diffuses pollution 100 times is `Config.diffusion_passes`, and the look stride is
  `Config.look_stride`. Both default to 1 and are left out of regular fingerprints.
