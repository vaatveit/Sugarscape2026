# Sugarscape xxl

xxl is a rule set for the 500 × 500 world that uses the room instead of hiding it. xl makes the world 10× wider and
adjusts the rules so its results match the regular run's; xxl is a different model. In Sugarscape an agent fills one
site and harvests one site, so a site is the agent's own size, and the big world is 10× wider *measured in agents*.
xxl uses that room to pull apart lengths that the 50 × 50 world forces to be about the same:

| Length, in sites | Book (50 × 50) | xl | xxl |
|---|---|---|---|
| Distance moved in a period | up to vision, 1–6 | up to vision, 10–60 | speed, 1–6 |
| Vision | 1–6 | 10–60 | 10–60 |
| Interaction (trade, culture, disease, mating, credit) | 1 | 1 | radius R, 1.5 by default |
| Landscape features (mountain radius) | about 10 | about 100 | about 100 (xl map), or 5–80 (generated) |
| World | 50 | 500 | 500 |

It is not a recreation of the book and is not scored against the book's targets. It exists in the Julia port only
(`julia/`); the Python model, runner and viewer don't change. This document is the contract: it defines the rules
without reference to any one language, as [docs/xl.md](xl.md) does for xl. It builds on xl, whose map, look
and timing definitions it uses. The design and its reasoning are in
[docs/superpowers/specs/2026-10-28-xxl-design.md](superpowers/specs/2026-10-28-xxl-design.md).

Each change is a separate switch with a *book setting* that turns it off, so its effect can be measured alone. With
every switch at its book setting, an xxl run is its Julia xl run, draw for draw.

## Conventions

- **Sites** are whole-number coordinates (x east, y north, 0-based) on the W × H torus, W = H = 500.
- **Distance** is Euclidean, the shorter way round in each direction: d = √(dx² + dy²), with dx = min(|Δx|, W − |Δx|)
  and dy likewise. The signed offset used to walk toward a site is the shortest way round in (−W/2, W/2]; a
  half-width apart goes positive.
- **Rounding.** Wherever a real coordinate becomes a site, it is rounded to the nearest whole number, **ties to
  even** (2.5 → 2, 3.5 → 4, −0.5 → 0), and then wrapped onto the torus. There is no other rounding rule.
- **Sorting by distance** compares the exact integer dx² + dy², so equal distances tie exactly.
- **Draws.** Every xxl random draw is gated by its feature and comes after every draw of the book rules in the same
  occasion: per agent (founders and newborns), after the Chapter V draws; per period, inside the rule that makes it.
  A "uniform draw" is one number uniform on [0, 1) from the model's generator.

## The nine settings

An xxl run is an xl configuration plus these settings. The book column turns each rule off; the default column is
what `--xxl` and the `XXL-…` experiments start from.

| Setting | Book setting | Default |
|---|---|---|
| `vision_shape` | `"lattice"` | `"disc"` |
| `speed` | none | (1, 6) |
| `travel_cost` c | 0 | 0.1 sugar per site |
| `memory` M | 0 | 8 |
| `memory_span` | 50 | 50 |
| `word_of_mouth` | false | true |
| `interaction_radius` R | 1 | 1.5 |
| `season_gradient` | false | true |
| `landscape` | `"xl"` | `"xl"` |

The xxl version of a regular experiment is its xl version (docs/xl.md) with these set to the default column. For a
base experiment without seasons the season gradient is set to false, so a fingerprint never names a rule that can't
apply.

**Refused combinations.** A configuration xxl doesn't define is refused, not run under book rules:
- `vision_shape` other than `"lattice"` or `"disc"`; `landscape` other than `"xl"` or `"generated"`;
- speed that isn't a range lo ≤ hi with lo ≥ 1; travel cost below 0; R below 1; memory below 0; span below 1;
- memory without speed; travel cost above 0 without speed; word of mouth without memory (> 0);
- the season gradient without seasons, or with `winter_growback = "pulse"`;
- speed above the lowest vision (an agent never reaches in one period a site it can't see);
- `landscape = "generated"` unless the sugar map is `sugar-map-xxl.txt`, and that map unless the landscape is
  generated;
- with disc vision, a vision whose limit 2V reaches the shorter side of the grid (a disc can't overlap itself across
  the torus);
- combat with spice or with credit, as the book rules refuse them.

## Rule 1: round vision

**Book setting:** `"lattice"`, the look along four lattice lines of docs/xl.md ("Looking": xl's centred look at
stride 10).

**xxl:** `"disc"`. Agent `a` with vision V and near radius n looks, from a position (x, y), at:
1. its own site (x, y), first;
2. every site with 1 ≤ d ≤ n, nearest first (equal distances by dx, then dy, both ascending), where n is the agent's
   speed S, and n = 1 without speed (the four adjacent sites), so a site next door is never missed;
3. K = ⌈4V / 10⌉ points drawn uniformly by area from the ring n < d ≤ V (a vision-60 agent draws 24). Only if V > n;
   otherwise there is no ring and nothing is drawn. Each point takes two uniform draws, u₁ then u₂:
   ρ = √(n² + u₁(V² − n²)), θ = 2π·u₂, offset (ρ cos θ, ρ sin θ), each coordinate rounded as above. A point whose
   rounded offset has dx² + dy² not in (n², V²] is dropped. A site already looked at in this step is looked at
   once. Dropped and repeated points still used their draws;
4. with memory on, last: each remembered site within V (torus distance) of (x, y) that isn't looked at yet. They
   are looked at afresh, at their current values (rule 3).

The disc removes the lattice's preference for the four axes. It also removes the reason xl needed random offsets: moves
along lattice lines in steps of 10 split the world into 100 separate worlds.

**Movement without speed** (`XXL-vision`): the agent scores its own site and each empty site it looked at with rule
M's score (sugar ÷ (1 + pollution); with spice, the welfare W of the holdings plus the site's devalued resources
under foresight, as in the book), and jumps to the best. Ties go to the nearest site by distance, then to the first
looked at; staying wins a tie with the agent's own site. No tie-break draw. It harvests there, as rule M does.

**Mate search within vision** (`mate_contact = "vision"`) takes a fresh disc look from the agent's position after
moving, without remembered sites. The agents on the looked-at sites are its partners in sight, nearest first and,
at equal distance, in the order looked at. (With the lattice look it is the book's.)

Speed (rule 2) works with either shape; with the lattice look, the near sites are the lattice's own and the other
rules below apply to them unchanged.

## Rule 2: speed and travel cost

**Book setting:** no speed. The agent jumps to the best site it sees and pays nothing for the move.

**xxl:** speed S is a genetic trait like vision. It is drawn uniformly from the `speed` range (one draw, the integer
range lo … hi) when an agent is created, after every book draw, and a child takes its speed from a random parent
(one draw choosing between the two) after every other draw of its birth, as it does vision. Each period, an agent:

1. **Chooses a target.** Candidates: its own site (d = 0), each empty site it looked at (rule M considers only empty
   sites, at every distance), and with memory its remembered sites beyond vision (torus distance > V), valued from
   what is remembered, whose occupancy it can't see. For a candidate at distance d:
   - T = max(1, ⌈d / S⌉) periods of travel;
   - the sugar burn m₁ is metabolism plus disease fees, and the spice burn m₂ the spice metabolism;
   - **Without spice:** h₁ = w₁ − c·d − m₁(T − 1) where w₁ is the sugar held. Value = h₁ + s, where s = sugar ÷
     (1 + pollution) at the site (remembered values for remembered sites).
   - **With spice:** b₁ = max(w₁ − φ·m₁, 0), b₂ = max(w₂ − φ·m₂, 0), with foresight φ (the clamp of the book's
     eq. 6); h₁ = b₁ − c·d − m₁(T − 1), h₂ = b₂ − m₂(T − 1). Value = W(h₁ + s, h₂ + q), the book's welfare function
     (exponents from the agent's metabolisms or cultural preference, as in rule M), with each term clamped at zero,
     s and q the site's sugar and spice each ÷ (1 + pollution). The travel terms come off after the clamp, so a
     poor agent still pays for distance.
   - **Dropped** (value −∞) when the agent would starve on the way, judged on what it really holds: d > 0 and
     w₁ − c·d − m₁(T − 1) ≤ 0, or with spice w₂ − m₂(T − 1) ≤ 0. The agent's own site is never dropped.

   With c = 0 and T = 1 this ranks sites exactly as rule M does. The agent targets the highest value. Ties go to the
   nearest by distance; remaining ties at random as a reservoir: the c-th candidate tied at the best value and
   distance replaces the choice with probability 1/c, one uniform draw each (no draw when not tied). Values are what
   the agent sees now; it doesn't predict growback. The target is chosen again every period.
2. **Steps.** If the target is within S and empty, the agent moves onto it. Otherwise it walks toward it in a
   straight line: with the signed offsets (Δx, Δy) to the target and d = √(Δx² + Δy²), for k = min(S, ⌊d⌋), …, 1 it
   takes the site (x + round(k·Δx/d), y + round(k·Δy/d)) wrapped, skips it if it is its own site, and moves to the
   first that is empty. If none is empty, it stays. (Hence a remembered target within S that turns out occupied is
   walked toward, not landed on.)
3. **Harvests and pays.** It harvests the site it ends on, as rule M does. In metabolism it also burns c × the
   distance it actually moved (torus distance between old and new site), in sugar. This counts as burn for the income
   credit reads and for consumption pollution. The death check is unchanged.

`travel_cost` defaults to 0.1 sugar per site; `XXL-speed` sweeps it. With S = V and c = 0, every target is reached
in one period and nothing is charged, which is rule M again.

## Rule 3: memory and word of mouth

**Book setting:** `memory = 0`. Memory needs speed (a remembered site beyond vision couldn't be reached by any other
rule).

**xxl:** each agent keeps up to M remembered sites (default 8). An entry holds the site, the sugar and spice seen
there (raw, not devalued; spice only with spice on), the pollution seen there, and the period it was seen. It stores
resources, not a score, so any agent can value it again from anywhere. Rule 2 devalues the remembered resources by
the remembered pollution; combat uses the sugar as it is.

**After moving** (and harvesting), the agent builds a pool and keeps the M best:
- the site it stands on, as it is after harvest, and each site it looked at this move, at their current resources
  and pollution, all seen this period; one entry per site;
- its remembered entries not older than `memory_span` periods (an entry seen at period t₀ is dropped when the
  current period − t₀ > span), except for sites already in the pool;
- the pool is ranked by rule 2's value from the agent's new position, with the holdings it has now: higher value
  first, then more recent sighting, then smaller (x, y). An entry the agent couldn't reach alive (value −∞) ranks
  last, so it is kept only if fewer than M are reachable. The best M are stored, best first.

A remembered site within vision is looked at afresh (rule 1, step 4). Beyond vision, the agent values the remembered
resources with travel time and cost as in rule 2.

**Word of mouth** (`word_of_mouth`): later in the same agent's turn, after metabolism and finding its neighbours
(rule 4), the agent copies each neighbour's *first* entry (the one that neighbour ranked highest), if it is within
the span, into its own pool, with the period it was seen; for a site it already has, the newer sighting stays. Its
own entries older than the span are dropped. It then keeps the M best by the same ranking.

## Rule 4: interaction radius

**Book setting:** R = 1: an agent's neighbours are its four von Neumann neighbours.

**xxl:** the neighbours are the living agents within distance R of it: those at the offsets 0 < d ≤ R, nearest
first (equal distances by dx, then dy), wrapped. R = 1.5 is the eight Moore neighbours (the default), R = 3 the 28
sites within 3. Trade, culture, disease, credit and rule S with `mate_contact = "neighbors"` all use this set, and so
does `mean_neighbors`. A child is born on a random empty site within R of either parent (a uniform draw among the
empty sites within R of the first parent, then those of the other not already listed; the book: one of the four
neighbour sites). At R = 1.0 none of this runs and the book's four sites, in the book's order, are used.

## Rule 5: seasons by latitude

**Book setting:** the world splits into a north half (y ≥ H/2) and a south half, as in rule S_{α,β,γ}. The half in
summer grows α per period; the other grows α/β (`winter_growback = "fractional"`). The north is in summer while
t mod 2γ < γ, the south in the other γ periods.

**xxl** (`season_gradient`, with seasons on). On the torus the two halves meet twice, at y = H/2 and at the seam
y = 0, both boundaries between opposite seasons. Both are treated as equators. Each site's winter weight is
**λ(y) = |sin(2π·y / H)|**: zero on both equators, one along the middle of each half (y = H/4 and 3H/4). A site in
the half in summer grows at α, and a site in the half in winter at **α · β^(−λ(y))**, from α at the equators to the
book's α/β along the middle. Sugar and spice use the same rate, capped at their capacities, as in the book. The rate
is continuous everywhere. Only the fractional winter is defined with the gradient.

## Rule 6: generated landscape

**Book setting:** the xl map `sugar-map-xl.txt`, with spice its east–west mirror (docs/xl.md).

**xxl** (`landscape = "generated"`, used only by `XXL-terrain`): two committed files in `sugarscape/maps/`, in the xl
map's format (500 lines of 500 whitespace-separated integers 0–4, northernmost row first, LF endings):

| File | Generator seed | SHA-256 |
|---|---|---|
| `sugar-map-xxl.txt` | 1 | `4891fca80ec10b70a8fdddb9e12a0e6c25851eb7493f8baaf4897e9448ef4f30` |
| `spice-map-xxl.txt` | 1001 | `e5ea6466369a62eeb1ef3a00d76bce5e9fc4dda0dd3f3c1b8e8e9f549eda800d` |

Spice is generated independently, not mirrored: the mirror is a fact of the book's map, not a law. The generated
maps wrap seamlessly across the torus. `julia/make_xxl_maps.jl` regenerates both and prints the seeds and hashes.

**SplitMix64** (Vigna), used instead of a library generator so that the maps regenerate identically on any language
version. State and outputs are unsigned 64-bit, and arithmetic wraps modulo 2⁶⁴. The state starts at the seed. To
draw:
```
state ← state + 0x9e3779b97f4a7c15
z ← state
z ← (z xor (z >> 30)) × 0xbf58476d1ce4e5b9
z ← (z xor (z >> 27)) × 0x94d049bb133111eb
output z xor (z >> 31)
```
A unit draw is `(output >> 11) × 2⁻⁵³`, uniform on [0, 1). Test vectors: seed 0 gives 0xe220a8397b1dcdaf,
0x6e789e6aa1b965f4, 0x06c45d188009454f; seed 1 gives 0x910a2dec89025cc1, 0xbeeb8da1658eec67, 0xf893a2eefb32555e, and
its first unit draw is 0.5665615751722809.

**The generator,** for a seed:
1. Draw 400 bumps from the seed's SplitMix64 stream, each with four unit draws in this order: centre x = 500·u,
   centre y = 500·u, radius r = exp(ln 5 + u·(ln 80 − ln 5)) (log-uniform on 5–80 sites), height h = 1 − u (uniform
   on (0, 1]). Seed 1's first bump is (283.2808, 372.8909), r = 73.82, h = 0.5556.
2. The field at site (x, y), 0-based integers, is the sum over the bumps, in draw order starting from 0, of
   h·exp(−(dx² + dy²) / (2r²)), where dx = min(g, 500 − g) with g = |x − centre x| mod 500, and dy likewise (the real
   centres, not rounded).
3. Cut it into capacities by rank, so that every capacity covers exactly as many sites as the xl map's: 43,036 sites
   of capacity 0, 52,156 of 1, 76,716 of 2, 55,932 of 3 and 22,160 of 4. Sort the sites by field value ascending (ties
   by site index, y·500 + x, stable); the first 43,036 get capacity 0, the next 52,156 capacity 1, and so on. Total
   sugar is then the xl map's: differences in results come from geography, not from more food.
4. Each cut lies between two neighbouring field values: the last value of one class and the first of the next. The
   generator requires each such gap to be at least 10⁻⁹, far above the rounding a different machine or language could
   introduce, so the cut is the same however the sum is evaluated. If a gap is smaller, it moves to the next seed
   (1, 2, … for sugar; 1001, 1002, … for spice). Both maps passed on their first seed, which is the seed in the table.

## Rule 7: combat

**Book setting:** with the lattice look and no speed, combat is the book's rule C_α, as xl runs it.

**xxl:** combat replaces movement, as in the book, and uses the xxl look and step (round vision or speed on). It is
sugar only: combat with spice or credit is refused.
- **Look.** One look of the attacker (rule 1) at the start of its turn, before any retaliation check.
- **Candidates.** The agent's own site, and the looked-at sites that are empty or held by an agent of another tribe
  with no more sugar than the attacker. Own-tribe and wealthier occupants are passed over. The reward of a site is
  its sugar, plus min(α, the occupant's sugar) if occupied. With memory, remembered sites beyond vision are candidates
  as empty sites, with their remembered sugar.
- **Reach.** With speed, an occupied site is a candidate only within S: the attack happens this period, and an
  occupant farther away won't stay put. Without speed every candidate is within reach and the agent jumps.
- **Value.** Rule 2's one-commodity value with the reward in place of the site's sugar: w₁ − c·d − m₁(T − 1) + reward,
  dropping candidates the agent would starve on the way to. The own site's value is w₁ + its sugar.
- **Retaliation.** A site the agent would end this period on is unsafe when an agent of another tribe, other than the
  attacker and the victim, holds more sugar than the attacker's sugar plus that site's reward. Travel cost doesn't
  count. The check is a fresh look of the attacker's vision from that site (rule 1 centred there, no remembered sites,
  its own draws), so it consumes random draws; with the lattice look it is the book's check.
- **Safe candidates.** A candidate within reach is safe when its own site is. A candidate beyond reach is safe when
  its walk has a landing site that is empty and not vulnerable: rule 2's step, k = S, S − 1, …, 1, takes the first
  site that is empty and safe, with that site's sugar as the reward. The far target itself isn't checked, since the
  agent won't be there this period. A candidate with no safe landing site is passed over.
- **Choice.** The best safe candidate wins: highest value, then nearest, then at random (a reservoir over the safe
  ties, as in rule 2). A strictly better candidate is checked for safety only when it would replace the best so far;
  a candidate tied in value and distance is always checked, and only safe ties count in the draw. The own site is
  checked first; if it is unsafe and nothing else is safe, the agent still stays and harvests.
- **Attack and harvest.** A defeated occupant loses min(α, its sugar) to the attacker and is killed, before the
  attacker moves onto the site and harvests its sugar: no production pollution and no income recorded, as in the
  book. Travel cost is charged by metabolism as in rule 2. With memory, the agent then updates its memory.

## The metrics

Added to xxl runs only, after the 45 columns every Julia result has, so regular and xl CSV layouts are unchanged.
Where a metric doesn't apply it is `nan`.

| Column | Definition |
|---|---|
| `mean_moved` | Mean distance moved this period (torus distance from where the agent started its move), per living agent at the end of the period; newborns count 0. `nan` with no agents. |
| `share_settled` | Share of living agents that didn't move this period (newborns count as not moved). |
| `clustering_1`, `clustering_10`, `clustering_50` | The pair correlation of agent positions at r = 1, 10, 50: ordered pairs of agents whose offset (dx, dy), the shorter way round, has r² − r + 1 ≤ dx² + dy² ≤ r² + r (a shell of width 1 around distance r), divided by N(N − 1)·P_r, where N is the number of living agents and P_r the share of ordered pairs of sugar-capacity ≥ 1 sites that are at a shell-r offset: what N agents placed at random on those sites would give. Above 1 is clustered. `nan` with fewer than 2 agents. |
| `regional_price_sd` | With trade: the population standard deviation of the mean log price over the 50 × 50 regions (100 of them) that hold at least one of this period's trades. A trade sits where its first agent is when the period ends; its region is (x ÷ 50, y ÷ 50). `nan` without trades; 0 with one region. |
| `price_distance_slope` | With trade: the least-squares slope of \|Δ log price\| on the distance between two trades' first agents, over every unordered pair of the period's first 2,000 trades in log order. `nan` with fewer than 2 trades, or no spread in distance. |
| `share_remembered_target` | With memory: the share of living agents whose target this period was a remembered site beyond vision. `nan` without memory. |
| `mean_winter_weight` | With seasons: the mean of λ(y) (rule 5) over living agents. It tracks migration toward the equators in winter. `nan` without seasons. |

## Running

- **The run.** `julia --project=julia julia/run.jl <id> --xxl` runs the xxl version (the default column) of each
  matching registered sugarscape experiment, with the same seeds and steps, into `results-julia-xxl/`; `--out` still
  overrides. It refuses Schelling and Ring World, and can't be combined with `--xl`. Timing, `machine.txt` and `--note`
  work as for xl (docs/xl.md, "Timing"). The `XXL-…` ids and prefixes run without the flag.
- **The `XXL-…` experiments** have no Python counterpart and are defined in Julia (`julia/src/xxl/experiments.jl`),
  not in the exported registry. Each is a base registry experiment passed through the xxl transform with its own
  settings, 5 seeds each (the base's steps). A family prefix runs its members (`XXL-speed`), and `XXL` runs all of them.
  A result folder is named by the id with `/` replaced by `_`.

  | Id | Base | Settings away from the book |
  |---|---|---|
  | `XXL-vision` | II-4 | disc vision |
  | `XXL-speed/c0`, `/c0.05`, `/c0.1`, `/c0.2` | II-4 | disc vision, speed (1, 6), travel cost c |
  | `XXL-memory/solo`, `/shared` | II-4 | the above at c = 0.1, memory 8, without and with word of mouth |
  | `XXL-radius/R1`, `/R1.5`, `/R3` | IV-A3 | the defaults, interaction radius R |
  | `XXL-seasons/halves`, `/gradient` | II-7 | the defaults, without and with the season gradient |
  | `XXL-terrain/II-4`, `/IV-A3` | II-4, IV-A3 | the defaults on the generated landscape |
  | `XXL-society/VI-1` | VI-1 | the defaults (every Chapter VI rule at once) |
  | `XXL-combat/III-9` | III-9 | the defaults, with combat |

- **Fingerprint** (`fingerprint.txt`): the line `julia`; a line `xxl ` followed by every setting as `name=value`, in
  the table's order, space separated (strings in double quotes, `speed=nothing` or `speed=(1, 6)`), e.g.
  `xxl vision_shape="disc" speed=(1, 6) travel_cost=0.1 memory=8 memory_span=50 word_of_mouth=true
  interaction_radius=1.5 season_gradient=true landscape="xl"` on one line; then the base experiment's xl fingerprint
  (docs/xl.md); then, for the generated landscape, one line `xxl map <file> sha256=<hex>` per map in use (the spice
  map only if the experiment has spice). A change to the settings, the base experiment or the maps makes saved
  xxl results stale.
- **CSVs.** `seed{k}.csv` has the 45 standard metric columns of the Julia port (after `t`), then the nine above.
- **Report.** `julia --project=julia julia/xxl_report.jl [prefix]` reads the result folders and prints, per XXL
  experiment, the mean and the seed standard deviation at t = 50, 100, 200 and over the last 100 periods, xxl above
  its base's Julia xl run, for population, mean sugar, Gini, trades and price sd (with trade) and every added
  column, with the stepping seconds per period of both.
- **Agreement is statistical.** An xxl run's random stream differs from every other run's, in any language.

## Results

Results follow.
