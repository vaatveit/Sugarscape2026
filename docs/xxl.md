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
[docs/superpowers/specs/2026-10-28-xxl-design.md](superpowers/specs/2026-10-28-xxl-design.md) (the first rules,
rules 1–7) and
[docs/superpowers/specs/2026-10-29-xxl-revised-design.md](superpowers/specs/2026-10-29-xxl-revised-design.md) (the
scorecard and the stage-1 survival switches, rules 8–11).

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
  The one exception is viable placement (rule 9), which draws a new agent's site after its traits instead of
  before. A "uniform draw" is one number uniform on [0, 1) from the model's generator.

## The settings

An xxl run is an xl configuration plus these settings. The book column turns each rule off. The first-rules column
is `XXL_V1`, the rules of the first design, which the `XXL-…` experiments and the results of "Results of the first
rules" use. The default column is `XXL_DEFAULTS`, what `--xxl` and the scorecard start from: the first rules with
the changes stage 1 chose ("Stage 1: the scorecard and survival").

| Setting | Book setting | First rules (`XXL_V1`) | Default | Rule |
|---|---|---|---|---|
| `vision_shape` | `"lattice"` | `"disc"` | `"disc"` | 1 |
| `speed` | none | (1, 6) | (1, 6) | 2 |
| `travel_cost` c | 0 | 0.1 sugar per site | **0.2** sugar per site | 2 |
| `memory` M | 0 | 8 | 8 | 3 |
| `memory_span` | 50 | 50 | 50 | 3 |
| `word_of_mouth` | false | true | true | 3 |
| `interaction_radius` R | 1 | 1.5 | 1.5 | 4 |
| `season_gradient` | false | true | true | 5 |
| `landscape` | `"xl"` | `"xl"` | **`"generated"`** | 6 |
| `max_metabolism` | none | none | none | 8 |
| `founder_placement` | `"random"` | `"random"` | **`"viable"`** | 9 |
| `free_step` | 0 | 0 | **1.5** sites | 10 |
| `founder_ages` | `"book"` | `"book"` | `"book"` | 11 |

The last four are the stage-1 survival switches. Each was tried at a candidate setting, and the scorecard decided
which to keep:

| Setting | Candidate | What the candidate does | Chosen by stage 1 |
|---|---|---|---|
| `max_metabolism` | 4 | Caps the sugar and spice metabolism drawn for a new agent | No |
| `founder_placement` | `"viable"` | Places founders and newcomers on land that feeds them | Yes |
| `free_step` | 1.5 | Charges no travel cost for a move whose target is within 1.5 sites | Yes |
| `founder_ages` | `"young"` | Starts founders no older than the start of their fertile years | No |
| `landscape` | `"generated"` | Makes the generated map the default | Yes |

The xxl version of a regular experiment is its xl version (docs/xl.md) with these set to the default column. For a
base experiment without seasons the season gradient is set to false, and for one without sex or without finite lives
`founder_ages` is set to `"book"`, so a fingerprint never names a rule that can't apply.

**Refused combinations.** A configuration xxl doesn't define is refused, not run under book rules:
- `vision_shape` other than `"lattice"` or `"disc"`; `landscape` other than `"xl"` or `"generated"`;
  `founder_placement` other than `"random"` or `"viable"`; `founder_ages` other than `"book"` or `"young"`;
- speed that isn't a range lo ≤ hi with lo ≥ 1; travel cost below 0; R below 1; memory below 0; span below 1;
  a free step below 0; a metabolism cap below 1, below the lowest sugar metabolism, or (with spice) below the
  lowest spice metabolism;
- memory without speed; travel cost above 0 without speed; a free step above 0 without speed; word of mouth without
  memory (> 0);
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
   distance it actually moved (torus distance between old and new site), in sugar, unless its target was within the
   free step (rule 10). This counts as burn for the income credit reads and for consumption pollution. The death
   check is unchanged.

`travel_cost` was 0.1 sugar per site in the first rules and is 0.2 in the defaults; `XXL-speed` sweeps it. With
S = V and c = 0, every target is reached in one period and nothing is charged, which is rule M again.

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

**xxl** (`landscape = "generated"`, the default since stage 1; among the `XXL-…` experiments only `XXL-terrain` uses
it): two committed files in `sugarscape/maps/`, in the xl map's format (500 lines of 500 whitespace-separated
integers 0–4, northernmost row first, LF endings):

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
  its walk has a landing site that is empty and not vulnerable: rule 2's step, k = min(S, ⌊d⌋), …, 1, takes the first
  site that is empty and safe, with that site's sugar as the reward. The far target itself isn't checked, since the
  agent won't be there this period. A candidate with no safe landing site is passed over.
- **Choice.** The best safe candidate wins: highest value, then nearest, then at random (a reservoir over the safe
  ties, as in rule 2). A strictly better candidate is checked for safety only when it would replace the best so far;
  a candidate tied in value and distance is always checked, and only safe ties count in the draw. The own site is
  checked first; if it is unsafe and nothing else is safe, the agent still stays and harvests.
- **Attack and harvest.** A defeated occupant loses min(α, its sugar) to the attacker and is killed, before the
  attacker moves onto the site and harvests its sugar: no production pollution and no income recorded, as in the
  book. Travel cost is charged by metabolism as in rule 2. With memory, the agent then updates its memory.

## Rule 8: a cap on metabolism

**Book setting:** none (`max_metabolism = nothing`): metabolisms are drawn from the experiment's ranges.

**xxl** (`max_metabolism = M`, candidate 4): a new random agent's sugar metabolism is drawn uniformly from
lo … min(hi, M) instead of lo … hi, and with spice its spice metabolism likewise. This applies wherever the
experiment draws a metabolism: founders and rule R's replacements. Children inherit their parents' metabolisms
(rule S), so the cap holds for them without a change. It is the same number of draws over a narrower range. The cap
may not be below the lowest metabolism of either range. M = 4 is the highest capacity on both maps, so with it no
agent is drawn that no single site can feed.

**Stage 1:** not chosen. The other changes pass every survival check without it (below), so the default stays at the
book setting.

## Rule 9: viable founder placement

**Book setting:** `founder_placement = "random"`: a founder goes to a uniformly random empty site of its placement
area, and then its traits are drawn. The area is the experiment's: the whole grid, the placement block, or with
tribal blocks its tribe's block; for a rule-R replacement it is the whole grid.

**xxl** (`"viable"`): a founder or a rule-R replacement draws all its traits first, exactly as random placement draws
them (the Chapter II–V draws, then speed), and only then its site: a uniformly random empty site of its area whose
sugar capacity is at least its sugar metabolism and, with spice, whose spice capacity is at least its spice
metabolism. Such a site feeds the agent on its own. If none of those is empty, the agent goes to a
uniformly random empty site of the area, and the run counts it as a fallback (the scorecard's `viable_fallbacks`
column, a running total). Births are untouched: a child is born next to its parents, as in rule 4.

A founder whose metabolism exceeds every capacity always falls back. In IV-A3 and VI-1, where both metabolisms are
drawn from 1–5 and no site has a capacity above 4, that is the 36% of founders with a metabolism of 5, sugar or spice
(7,044–7,313 of 20,000 per seed under the defaults, seeds 20–39); II-4 draws metabolisms 1–4 and has none.

**Stage 1:** chosen. It has the largest effect on II-4 of any change, and II-4 fails without it.

## Rule 10: the free step

**Book setting:** `free_step = 0`: every move pays the travel cost of rule 2.

**xxl** (`free_step = f`, candidate 1.5; it needs speed): a move whose *target* is within f of the agent (d ≤ f)
costs nothing. A move toward a farther target costs c × the distance moved, as in rule 2. The agent's valuation agrees
with what it pays: wherever rule 2 charges c·d for a candidate at distance d (its value and its starve-on-the-way
cutoff), and in memory's ranking (rule 3) and combat's valuation (rule 7), that term is 0 when d ≤ f.

With f = 1.5, a step to any of the eight Moore neighbours (d ≤ √2) is free, while a trip to a site 2 or more away pays
for every site moved, each period. The target is chosen afresh each period, so the last step of a longer trip, once
the target is within f, is free too. It removes the travel-cost trap of the first rules (see "Who dies in the second
die-off"): an agent that steps to a full neighbouring site each period to eat no longer runs a deficit, while long
trips still cost at every speed. (Discounting each period's step instead would make every move of a speed-1 agent
free.)

**Stage 1:** chosen. II-4 fails without it.

## Rule 11: young founders

**Book setting:** `founder_ages = "book"`: founders start at the experiment's own ages (VI-1: uniform on
0 … max age − 1; under the first rules 26–39% of VI-1's founders died of old age by t = 50).

**xxl** (`"young"`): each founder's age is drawn uniformly from the whole numbers 0 … its fertility start, in the same
position as the book's draw, so founders start before or at the start of their fertile years. It applies only to
experiments with sex and finite lives whose founders start at uniform ages; for an experiment without sex or without
finite lives the transform sets it back to `"book"`. Newcomers and children are untouched.

**Stage 1:** not chosen. It does the most for VI-1's trough of any change, but the survival checks pass without it,
and with it the share sick ends above the scorecard's bound (below). It stays available for stage 2.

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
  A result folder is named by the id with `/` replaced by `_`. They are defined from the first rules, `XXL_V1`, not
  from the defaults, so their settings, fingerprints and recorded results did not change with stage 1.

  | Id | Base | Settings away from the book |
  |---|---|---|
  | `XXL-vision` | II-4 | disc vision |
  | `XXL-speed/c0`, `/c0.05`, `/c0.1`, `/c0.2` | II-4 | disc vision, speed (1, 6), travel cost c |
  | `XXL-memory/solo`, `/shared` | II-4 | the above at c = 0.1, memory 8, without and with word of mouth |
  | `XXL-radius/R1`, `/R1.5`, `/R3` | IV-A3 | the first rules, interaction radius R |
  | `XXL-seasons/halves`, `/gradient` | II-7 | the first rules, without and with the season gradient |
  | `XXL-terrain/II-4`, `/IV-A3` | II-4, IV-A3 | the first rules on the generated landscape |
  | `XXL-society/VI-1` | VI-1 | the first rules (every Chapter VI rule at once) |
  | `XXL-combat/III-9` | III-9 | the first rules, with combat |

- **Fingerprint** (`fingerprint.txt`): the line `julia`; a line `xxl ` followed by the first nine settings as
  `name=value`, in the table's order, then each of the four stage-1 settings only when it is off its book setting
  (so a first-rules fingerprint is as it was before they existed), space separated (strings in double quotes,
  `speed=nothing` or `speed=(1, 6)`). For the first rules it is
  `xxl vision_shape="disc" speed=(1, 6) travel_cost=0.1 memory=8 memory_span=50 word_of_mouth=true
  interaction_radius=1.5 season_gradient=true landscape="xl"` on one line, and for the defaults
  `xxl vision_shape="disc" speed=(1, 6) travel_cost=0.2 memory=8 memory_span=50 word_of_mouth=true
  interaction_radius=1.5 season_gradient=true landscape="generated" founder_placement="viable" free_step=1.5`;
  then the base experiment's xl fingerprint (docs/xl.md); then, for the generated landscape, one line `xxl map <file> sha256=<hex>` per map in use (the spice
  map only if the experiment has spice). A change to the settings, the base experiment or the maps makes saved
  xxl results stale.
- **CSVs.** `seed{k}.csv` has the 45 standard metric columns of the Julia port (after `t`), then the nine above. A
  scorecard run adds 14 more (next section); ordinary `--xxl` runs never write them.
- **Report.** `julia --project=julia julia/xxl_report.jl [prefix]` reads the result folders and prints, per XXL
  experiment, the mean and the seed standard deviation at t = 50, 100, 200 and over the last 100 periods, xxl above
  its base's Julia xl run, for population, mean sugar, Gini, trades and price sd (with trade) and every added
  column, with the stepping seconds per period of both.
- **Agreement is statistical.** An xxl run's random stream differs from every other run's, in any language.

## Stage 1: the scorecard and survival

The first rules (`XXL_V1`) nearly killed VI-1's society: on the baseline scorecard below, its 20,000 founders fell to
2–6% of their number before the population recovered, II-4 and IV-A3 kept only about 60% of xl's survivors, and
disease died out in every seed ("Results of the first rules" has the analysis behind the first two). The goal is now
a well-functioning simulation: the population rarely goes extinct, and sex, culture, trade, credit and disease each
work. The work goes in stages, each scored by the same scorecard: stage 1 survival, stage 2 contact and demography,
stage 3 trade and credit, stage 4 disease. This section is stage 1's record.

**Outcome.** The defaults are now the first rules with three changes and a higher travel cost: the generated map
(rule 6), viable founder placement (rule 9), a free step of 1.5 (rule 10), and c = 0.2. On 20 seeds that were not
used to choose them (seeds 20–39) they pass 13 of the 15 checks, every survival check among them, against 7 of 15 for
the first rules. The two that still fail, mates in reach (X2) and loans voided by death (X8), failed in every setting
tried; with the other X checks they are the baseline for stages 2–4.

### The scorecard

```bat
julia --project=julia julia/xxl_scorecard.jl [--rules v1|defaults] [--set field=value]... [--label NAME]
    [--seeds N] [--first-seed K] [--jobs J] [--out DIR]
```

It runs II-4 (500 periods; sugar only, no births), IV-A3 (300; sugar, spice and trade, no births) and VI-1 (500;
sex, culture, trade, credit and disease at once) under one rule set, by default the defaults, on 20 seeds starting
at seed index 0. `--rules v1` starts from the first rules instead, and each `--set` changes one field
(`--set free_step=1.5`). It also runs the xl version of each experiment on the same seeds as the reference level,
once per seed range: a later scorecard on the same seeds reuses it. Results go to
`results-julia-xxl/scorecard-<label>-s<first>-<seeds>/` (the per-seed CSVs, so a scorecard can be re-scored without
re-running) and its report to the `.md` file of the same name, with each check's value, threshold, result and
per-seed detail. The label is the base and the `--set`s joined by `+` unless `--label` names it.

The scorecard's runs write 14 more columns, which ordinary `--xxl` runs don't: deaths by cause (`deaths_sugar`,
`deaths_spice`, `deaths_old_age`, `deaths_killed`; starving of both goods counts as sugar), `births`, `n_fertile` and
`n_fertile_with_mate` (a fertile agent of the other sex within the interaction radius), `tag_flips_per_agent`,
`share_traded_10` (the share of agents who traded in the last 10 periods), the loan flows `loans_started`,
`loans_rolled`, `loans_repaid` and `loans_voided` (ended by the borrower's or lender's death), and
`viable_fallbacks` (rule 9).

**The checks.** Every threshold is provisional. "End" is the mean over the last 100 periods; a "value" is what the
tables below report.

| Check | Aspect | Value | Passes when |
|---|---|---|---|
| S1 No extinction | Survival | VI-1 seeds that reach population 0 | = 0 |
| S2 No near-extinction | Survival | The lowest VI-1 seed's minimum population ÷ its 20,000 founders | ≥ 0.1 |
| S3 Recovery | Survival | VI-1's end population ÷ xl's, means over seeds | ≥ 0.5 |
| S4 Survivors, one good | Survival | II-4's end population ÷ xl's, means over seeds | ≥ 0.9 |
| S5 Survivors, two goods | Survival | IV-A3's end population ÷ xl's, means over seeds | ≥ 0.9 |
| X1 Births keep up | Sex | Births ÷ deaths over VI-1's last 200 periods, mean over seeds | 0.9–1.1 |
| X2 Mates in reach | Sex | At VI-1's trough, the share of fertile agents with a mate in reach, mean over seeds | ≥ 0.5 |
| X3 Both cultures live | Culture | The share of VI-1 seeds where both tribes hold ≥ 5% at t = 200 | ≥ 0.8 |
| X4 Culture moves | Culture | The fewest tag flips per agent in any period of any VI-1 seed | > 0 |
| X5 Agents trade | Trade | VI-1's end share of agents who traded in the last 10 periods, mean over seeds | ≥ 0.5 |
| X6 Prices agree | Trade | VI-1's end price sd ÷ xl's, means over seeds | ≤ 1.5 |
| X7 Credit persists | Credit | The fewest loans outstanding in any period after t = 100 of any VI-1 seed | ≥ 1 |
| X8 Loans are repaid | Credit | The share of VI-1's loans voided by a death (of those voided or repaid), mean over seeds | ≤ 0.2 |
| X9 Disease is endemic | Disease | The share of VI-1 seeds with a disease circulating at t = 500 | ≥ 0.9 |
| X10 Disease is bounded | Disease | VI-1's end share of agents sick, mean over seeds | 0.01–0.2 |

S4 and S5 compare with xl because an experiment without births has no extinction to avoid: its population can only
fall, and xl's free movement, as far as the agent sees, is the level reached when no agent dies of a model artifact.
Only the S checks gate stage 1; the X checks are reported from the start so each later stage knows its baseline.

### The tuning

All tuning scorecards ran on seeds 0–19, and the choice was then confirmed on seeds 20–39.
1. **Baseline:** the first rules.
2. **One at a time:** the first rules plus each change alone, at their candidate settings (the four switches of
   rules 8–11 and the generated map).
3. **Together:** all five, at travel costs 0.05, 0.1 and 0.2, with book or young founder ages: six settings.
4. **Trim:** no single change passed S1–S5, so the trim started from the passing setting of step 3 with the fewest
   changes, then the higher travel cost. It dropped each change in turn, kept any drop that still passed S1–S5, and
   repeated until no change could be dropped.
5. **Choose and confirm:** the trim's result, confirmed on the 20 further seeds.

The switches and the landscape count as changes; the travel cost does not. Every scorecard below passed S1: no seed
of any setting went extinct (the lowest population of any VI-1 seed was 410 under the first rules and 3,578 under the
defaults). Failing values are in bold.

| Setting (seeds 0–19) | Changes | S2 | S3 | S4 | S5 | Checks passed | X checks failing |
|---|---|---|---|---|---|---|---|
| First rules | 0 | **0.021** | 0.683 | **0.617** | **0.586** | 7 | X1, X2, X8, X9, X10 |
| + metabolism cap 4 | 1 | **0.051** | 0.720 | **0.617** | **0.893** | 9 | X2, X8, X9 |
| + viable placement | 1 | **0.062** | 0.752 | **0.874** | 1.363 | 9 | X2, X8, X9, X10 |
| + free step 1.5 | 1 | **0.037** | 0.767 | **0.799** | **0.641** | 8 | X2, X8, X9, X10 |
| + generated map | 1 | 0.105 | 0.687 | **0.640** | **0.879** | 10 | X2, X8, X9 |
| + young founders | 1 | 0.158 | 0.692 | **0.617** | **0.586** | 10 | X2, X8, X9 |
| All, c = 0.05, book ages | 4 | 0.263 | 0.676 | 1.181 | 2.660 | 12 | X2, X8, X10 |
| All, c = 0.05, young | 5 | 0.778 | 0.632 | 1.181 | 2.660 | 12 | X2, X8, X10 |
| All, c = 0.1, book ages | 4 | 0.263 | 0.687 | 1.180 | 2.687 | 13 | X2, X8 |
| All, c = 0.1, young | 5 | 0.783 | 0.625 | 1.180 | 2.687 | 12 | X2, X8, X10 |
| All, c = 0.2, book ages | 4 | 0.258 | 0.660 | 1.179 | 2.694 | 13 | X2, X8 |
| All, c = 0.2, young | 5 | 0.780 | 0.622 | 1.179 | 2.694 | 12 | X2, X8, X10 |

The one-at-a-time rows are at the first rules' travel cost, 0.1. "All" is the cap, viable placement, the free step
and the generated map, with founder ages as named.

**What each change does alone.**
- **The metabolism cap** removes the founders of IV-A3 and VI-1 with a metabolism of 5, sugar or spice, whom no
  single site can feed (36% of them). IV-A3 rises to 89% of xl's population, just short of the bar, and VI-1's
  trough is 2.5 times as high, still half the bar. II-4 already draws metabolisms 1–4, so it does not move at all.
- **Viable placement** does the most for II-4 (S4 from 0.617 to 0.874) and lifts IV-A3 past xl (S5 1.363): a founder
  that starts on land that feeds it does not starve looking for it. VI-1's trough rises only to 0.062, and disease
  still dies out in every seed.
- **The free step** removes II-4's travel-cost trap (S4 0.799) and gives the best VI-1 recovery (S3 0.767), but
  helps IV-A3 little (S5 0.641) and VI-1's trough less (0.037).
- **The generated map**, the only change to the land itself, passes S2 alone, just (0.105). IV-A3 rises to 88%
  of xl, II-4 barely (0.640). It also keeps disease alive: one circulates at t = 500 in 17 of 20 seeds, against none
  under the first rules.
- **Young founders** pass S2 alone (0.158), presumably because fewer founders die of old age in the early famine
  (not traced). II-4 and
  IV-A3 have no aging, so the switch does nothing there and S4 and S5 are the first rules'. Disease survives in 8 of
  20 seeds.

No single change passes S1–S5. S4 is the hardest: only viable placement and the free step move it much.

**Together.** All five pass S1–S5 at every travel cost and with either founder ages. The travel cost barely changes
survival (S4 1.179–1.181, S5 2.660–2.694). Young founders raise VI-1's trough from about 0.26 to about 0.78 of the
founders, but cost recovery (S3 0.622–0.632 against 0.660–0.687), and with them the share sick ends above 20% at
every travel cost (X10 0.224–0.259). With book ages X10 passes at c = 0.1 and 0.2 (0.167, 0.148) and fails at 0.05
(0.204). The fewest changes (four, book ages), then the higher travel cost, put the trim's start at c = 0.2 with book
ages.

**The trim.** From that start, at c = 0.2, each change was dropped in turn, the one with the least effect on S4 alone
first: the cap, the generated map, the free step, then viable placement.

| Setting (seeds 0–19, c = 0.2, book ages) | S2 | S3 | S4 | S5 | Checks passed | X checks failing | Drop |
|---|---|---|---|---|---|---|---|
| Start: all four | 0.258 | 0.660 | 1.179 | 2.694 | 13 | X2, X8 | |
| Without the cap | 0.179 | 0.682 | 1.179 | 1.967 | 13 | X2, X8 | accepted |
| Without the cap and the generated map | **0.072** | 0.756 | 1.205 | 1.593 | 10 | X2, X8, X9, X10 | refused |
| Without the cap and the free step | 0.127 | 0.616 | **0.807** | 1.210 | 11 | X2, X8, X9 | refused |
| Without the cap and viable placement | 0.112 | 0.685 | **0.796** | 0.914 | 12 | X2, X8 | refused |

- **Without the cap** every survival check still passes. Its 36% of founders with a metabolism of 5 now go to a
  random site (rule 9's fallback), so IV-A3 keeps fewer (S5 from 2.69 to 1.97 of xl) and VI-1's trough is lower
  (0.258 to 0.179), with room to spare on both.
- **Without the generated map** VI-1's trough fails (0.072; 5 seeds of 20 below 0.1), and disease dies out in every
  seed.
- **Without the free step**, or **without viable placement**, II-4 fails (0.807, 0.796).

Each of the three remaining changes was dropped from the final set and each drop failed, so nothing more can be
dropped: the trim ends at three changes. The trim is greedy, so another order could in principle reach a different
smallest set. At c = 0.2, II-4 passed only with viable placement and the free step together, and those two alone fail
S2, which suggests that no two changes suffice, but not every pair was scored.

### The choice and its confirmation

The trim's result is the new default: `landscape = "generated"`, `founder_placement = "viable"`, `free_step = 1.5`
and `travel_cost = 0.2`, with `max_metabolism` and `founder_ages` at their book settings and every other field as in
the first rules. On seeds 20–39 it passes the same 13 checks as on seeds 0–19, with nearly the same values:

| Check | Threshold | First rules, seeds 0–19 | Defaults, seeds 0–19 | Defaults, seeds 20–39 |
|---|---|---|---|---|
| S1 No extinction | = 0 | 0 | 0 | 0 |
| S2 No near-extinction | ≥ 0.1 | **0.021** | 0.179 | 0.198 |
| S3 Recovery | ≥ 0.5 | 0.683 | 0.682 | 0.684 |
| S4 Survivors, one good | ≥ 0.9 | **0.617** | 1.179 | 1.178 |
| S5 Survivors, two goods | ≥ 0.9 | **0.586** | 1.967 | 1.972 |
| X1 Births keep up | 0.9–1.1 | **1.131** | 1.051 | 1.044 |
| X2 Mates in reach | ≥ 0.5 | **0.015** | **0.024** | **0.023** |
| X3 Both cultures live | ≥ 0.8 | 1 | 1 | 1 |
| X4 Culture moves | > 0 | 0.012 | 0.167 | 0.187 |
| X5 Agents trade | ≥ 0.5 | 0.920 | 0.979 | 0.981 |
| X6 Prices agree | ≤ 1.5 | 1.297 | 1.223 | 1.202 |
| X7 Credit persists | ≥ 1 | 14 | 990 | 1,134 |
| X8 Loans are repaid | ≤ 0.2 | **0.276** | **0.253** | **0.249** |
| X9 Disease is endemic | ≥ 0.9 | **0** | 0.95 | 0.95 |
| X10 Disease is bounded | 0.01–0.2 | **0** | 0.112 | 0.107 |
| Checks passed | | 7 | 13 | 13 |

The per-seed detail, on seeds 20–39: VI-1's lowest population is 3,956–8,476 (S2 0.198–0.424 of the founders), and
it ends at 47,990–71,020 against xl's 67,670–103,800. II-4 ends at 27,940–28,280 against xl's 23,760–24,000, and
IV-A3 at 7,231–7,412 against 3,621–3,825.

- **II-4 and IV-A3 now keep more agents than xl.** The checks ask for 90% of xl, and xl is a reference, not a
  ceiling. xl places founders at random, where viable placement starts every II-4 founder, and every IV-A3 founder
  it can, on land that feeds it; that is presumably the difference (not traced).
- **VI-1's trough is now 18–42% of the founders**, against 2–6% under the first rules, and its recovery is unchanged
  at about 68% of xl.

### The baseline for stages 2–4

Under the defaults, on seeds 20–39:
- **X2 fails badly: mates are rarely in reach.** At VI-1's trough only 2.3% of fertile agents (1.2–3.6% per seed)
  have a fertile agent of the other sex within the interaction radius, against the 50% asked. It failed in every
  setting tried (0.011–0.026), so stage 1's changes don't touch it. This is stage 2's problem: contact and
  demography.
- **X8 fails narrowly: a quarter of loans end voided by a death** (0.249; 0.236–0.276 per seed) against the 20%
  allowed. It also failed in every setting (0.235–0.313). Stage 3 covers credit.
- **Births now keep up with deaths** (X1 1.044; under the first rules 1.131, births far ahead of deaths as the
  population refilled after its deep trough).
- **Disease is now endemic but near its bounds.** A disease circulates at t = 500 in 19 of 20 seeds in both seed sets
  (X9 0.95 against 0.9, so two more seeds without disease would fail it). The mean share sick passes (0.107), but per
  seed it runs from 0 to 0.25, so some seeds lie outside the 1–20% bounds.
- **Culture, trade and credit pass:** both tribes live in every seed, culture moves throughout (fewest tag flips per
  agent 0.187, against 0.012 under the first rules), 98% of agents trade, the price spread is 1.2 times xl's, and at
  least 1,134 loans are outstanding in every period after t = 100.

**Run time.** VI-1 dominates. With `--jobs 10` on the 24 threads of an i7-13700K (machine load not recorded), the
confirmation scorecard took 2,196 s, of which the xl reference runs for the new seed range took 583 s (VI-1 512 s).
Scorecards that reused an existing xl reference took 1,373–2,209 s (the defaults on seeds 0–19: 1,753 s).

## Results of the first rules (`XXL_V1`)

This section is the record of the first rules, `XXL_V1`, as the 16 `XXL-…` experiments still run them. Where it says
"the defaults" or "the xxl defaults", it means those rules (the first-rules column of "The settings"), not today's
defaults.

First runs of the 16 `XXL-…` experiments (2026-10-28), 5 seeds each, against fresh Julia xl runs of the five base
experiments (10 seeds for II-4, IV-A3 and III-9; 5 for II-7 and VI-1; all fingerprints current). These are findings,
not pass/fail thresholds: xxl is a different model, and a difference from xl says what a change does, not that
something is wrong. Everything below is read from `julia --project=julia julia/xxl_report.jl`; figures are the
mean across seeds ± the standard deviation across seeds (n − 1), at t = 50, 100, 200 and over the last 100 periods
("final" below). "xl" means the base experiment's Julia xl run.

**How to read the spreads.** Seed spreads are small next to most differences below (population sd is 0.2–0.7% of the
mean at the four checkpoints in the II-4 and II-7 families, and 0.7–2.1% in IV-A3's), but five seeds is few, and VI-1 and III-9 at the end are far
noisier (their final population sds are 8% and 6.5% of the mean). Each experiment was run once.

**Timings.** One job (`--jobs 1`), one thread, an i7-13700K, Julia 1.13.2, stepping only (docs/xl.md, "Timing").
The machine was not recorded as quiet. It is noisy in absolute terms: this batch's xl II-4 stepped at 0.037 s per
period, against 0.014 s in [julia/README.md](../julia/README.md)'s earlier measurement of the same run, so compare
only the ratios inside this table, and treat even those as indicative. Seconds per period are the mean over seeds
and periods; agents are the mean at the start and end of a run.

| Experiment | Base | xxl s/period | xl s/period | Ratio | Agents, xxl start → end | xl end |
|---|---|---|---|---|---|---|
| `XXL-vision` | II-4 | 0.050 | 0.037 | 1.4 | 40,000 → 22,948 | 23,828 |
| `XXL-speed/c0` | II-4 | 0.094 | 0.037 | 2.6 | 40,000 → 19,075 | 23,828 |
| `XXL-speed/c0.05` | II-4 | 0.088 | 0.037 | 2.4 | 40,000 → 18,491 | 23,828 |
| `XXL-speed/c0.1` | II-4 | 0.080 | 0.037 | 2.2 | 40,000 → 13,997 | 23,828 |
| `XXL-speed/c0.2` | II-4 | 0.072 | 0.037 | 2.0 | 40,000 → 13,461 | 23,828 |
| `XXL-memory/solo` | II-4 | 0.146 | 0.037 | 4.0 | 40,000 → 13,993 | 23,828 |
| `XXL-memory/shared` | II-4 | 0.155 | 0.037 | 4.2 | 40,000 → 13,999 | 23,828 |
| `XXL-radius/R1` | IV-A3 | 0.071 | 0.033 | 2.2 | 20,000 → 2,069 | 3,253 |
| `XXL-radius/R1.5` | IV-A3 | 0.071 | 0.033 | 2.2 | 20,000 → 2,096 | 3,253 |
| `XXL-radius/R3` | IV-A3 | 0.078 | 0.033 | 2.4 | 20,000 → 2,139 | 3,253 |
| `XXL-seasons/halves` | II-7 | 0.120 | 0.030 | 4.0 | 40,000 → 11,196 | 17,621 |
| `XXL-seasons/gradient` | II-7 | 0.135 | 0.030 | 4.5 | 40,000 → 12,293 | 17,621 |
| `XXL-terrain/II-4` | II-4 | 0.165 | 0.037 | 4.5 | 40,000 → 14,653 | 23,828 |
| `XXL-terrain/IV-A3` | IV-A3 | 0.094 | 0.033 | 2.9 | 20,000 → 3,100 | 3,253 |
| `XXL-combat/III-9` | III-9 | 0.346 | 0.035 | 10.0 | 54,000 → 19,081 | 303 |
| `XXL-society/VI-1` | VI-1 | 0.934 | 0.515 | 1.8 | 20,000 → 64,279 | 89,367 |

Wall clock for the batch (from the run log, one job): the five xl bases took 39 minutes (VI-1 26 of them); the xxl
families took 2 h 20 min: `XXL-vision` 4 min, `XXL-speed` 18, `XXL-memory` 15, `XXL-radius` 6, `XXL-seasons` 13,
`XXL-terrain` 11, `XXL-combat` 32 and `XXL-society` 42. The ratios per period mix the cost per agent with the
population, which is usually lower in xxl. Per agent and period (stepping seconds over the sum of the population at
t = 0 … T − 1, mean over seeds), xxl costs: vision 2.1 µs, speed 4.3–4.7, memory 7.8–8.3, `XXL-terrain/II-4` 8.7,
seasons 8.7–9.0, combat 14.7, `XXL-terrain/IV-A3` 18.5, radius 18.8–20.1 and society 31.2; against xl's 1.5 (II-4 and
II-7), 4.9 (IV-A3), 3.4 (III-9) and 9.2 (VI-1). The memory runs cost about 1.8× the same speed run without memory
(below).

The xxl code leaves the xl hot path as fast as before: xl II-4 measured at base 8ae9319 and at this branch,
interleaved in one session (12 pairs of separate processes pinned to one P-core, each the best of eight 10-period
runs), had medians of 0.0201 s per period (base) and 0.0202 s (branch).

### Round vision (`XXL-vision`, II-4)

Disc vision alone, with no speed: agents jump to the best site they see, as in the book.
- **Population is 2–4% below xl** at every checkpoint: 24,832 ± 91 against 25,834 ± 123 at t = 50, and 23,076 ± 89
  against 23,894 ± 88 final. Mean sugar is 3% above xl at t = 50 (78.7 against 76.2) and 4% below it final (490 against
  509).
- **Inequality is higher later:** Gini 0.397 against 0.382 at t = 200 and 0.412 ± 0.001 against 0.390 ± 0.002 final.
- **Agents move far:** 5.1–6.0 sites per period on average, with 5% staying put.
- **They cluster.** The pair correlation is 1.7–2.2 at distance 1, 1.9–2.3 at 10 and 1.6–1.8 at 50, rising over the
  run: long jumps pile agents onto the same peaks. (The speed runs below are at 1.0–1.5.)
- Stepping costs 1.4× xl's per period.

### Speed and travel cost (`XXL-speed`, II-4)

Disc vision, speed (1, 6), and travel cost c = 0, 0.05, 0.1, 0.2.
- **Speed alone removes about a quarter of the early population.** At t = 50 all four are at 19.3–19.5k (sd 65–80),
  against 25.8k for xl (the cause was not examined: presumably agents that can no longer jump to a distant site
  crowd and starve). This does not depend on c.
- **Without a travel cost the population then holds:** c = 0 is at 19,459, 19,396, 19,273 and 19,110 ± 66 (final), and
  c = 0.05 slides slowly to 18,698 ± 63 final.
- **c = 0.1 and c = 0.2 add a second die-off.** For c = 0.2 it begins just after t = 100 and is well under way by
  t = 150: 19,069 (t = 100), 17,584 (150), 15,411 (200), 13,587 (250), then it levels off at about 13,460 ± 92 from
  t ≈ 300. For c = 0.1 it begins at about t = 200–250 and runs for the rest of the run: 19,026 (200), 18,665 (250),
  17,576 (300), 16,577 (350), 15,583 (400), 14,715 (450), 13,997 (500), still falling at t = 500 (final-window
  mean 14,703 ± 93). The travel cost per period is small (mean distance moved is under 1 site, so about 0.09 sugar
  for c = 0.1, against metabolisms of 1–4), and it kills the agents who were exactly breaking even: see "Who dies in
  the second die-off" below.
- **Survivors are richer and the Gini is not monotone in c.** Final mean sugar is 453 (c = 0), 442, 542 (c = 0.1), 546
  (c = 0.2), against xl's 509. The Gini at t = 200 is 0.459, 0.475, 0.491, 0.415, against 0.382 for xl, and final 0.493,
  0.502, 0.386, 0.355 against 0.390: it rises while the population is stable, and falls once the die-off has run
  (the die-off removes the poor: those who die after t = 100 had a median 16–26 sugar at t = 100, the survivors
  121–130; see below).
- **Agents barely move.** Mean distance moved is 0.89–1.0 site per period at every c, with 10–15% settled, although
  the mean speed is 3.5. Presumably, with growback of 1 per period and vision of 10 or more, the best site is usually
  the nearest one that has regrown, one site away (not tested). The pair correlation is 1.0–1.5, much less clustered than round vision without
  speed (1.7–2.3).
- Stepping is 2.0–2.6× xl's, less at high c because there are fewer agents.

**Who dies in the second die-off.** It kills the agents whose metabolism equals the capacity of the land they live
on. This comes from tracing every founder in seeds 0–2 of c = 0, 0.1 and 0.2 (120,000 founders per c), recording
each one's traits, harvest, distance moved and time of death. The traced runs reproduce the recorded populations
exactly. II-4 has no aging, births or replacement, so every death is starvation.
1. **Harvest is capped by capacity.** A site holds at most its capacity, so an agent that steps to a full
   neighbouring site each period harvests that capacity. At t = 100 the mean harvest per period over periods 81–100
   is 1.00, 2.00, 2.99 and 3.93–3.98 on capacity 1, 2, 3 and 4 land (seed 0, at each c), whatever the agent's
   metabolism.
2. **Many agents live at a zero margin.** After the first die-off the richer land is full, and about 6,000 agents
   per seed live on land whose capacity equals their metabolism (2 on 2, 3 on 3, 4 on 4). Their harvest less their
   metabolism over periods 1–100 is 0.000 at the median.
3. **They can't avoid the travel cost.** Staying put yields only the growback of 1, so an agent with metabolism 2 or
   more must keep stepping to a full site, about one site per period, at a cost of about c. The margin becomes −c.
4. **They starve when their savings run out.** For the agents dying after t = 100 whose income over periods 1–100 was
   negative, their sugar at t = 100 divided by that loss predicts when they die. The median predicted and actual
   death times are 343 and 346 for c = 0.1 (correlation 0.90), and 178.5 and 180 for c = 0.2 (0.74). Halving the
   loss doubles the time, which is why c = 0.1's die-off comes later and lasts longer. Those who die were also the
   poor: their median sugar at t = 100 was 16–26, against 121–130 for the survivors.

Share of the agents alive at t = 100 that die by t = 500 (three seeds pooled):

| Metabolism | c = 0 | c = 0.1 | c = 0.2 |
|---|---|---|---|
| 1 | 0% | 0% | 0% |
| 2 | 0% | 38% | 42% |
| 3 | 1% | 55% | 61% |
| 4 | 27% | 100% | 100% |

- **Metabolism 1 is safe.** Staying put and living on the growback already covers it.
- **Metabolism 4 always dies under a cost.** There is no richer land to move up to. Even at c = 0 a capacity-4 site
  is sometimes not full when it is reached, so these agents harvest about 3.95 and slowly starve. This is c = 0's
  slow decline: 971 of the 58,172 alive at t = 100 die by t = 500, 19,211 at t = 200 against 18,613 at t = 1000 in
  seed 0.
- **Metabolism 2 and 3 die in part.** As others die, room opens on richer land, and some agents move up before their
  savings run out.
- **Vision, speed and place make no difference.** The death rate is 26–31% across every band of vision and every
  speed, and those who die stood on land of the same mean capacity at t = 100 as the survivors (2.64–2.68 against
  2.70–2.71 in an 11 × 11 box). Every agent moves about one site per period, whatever its speed.
- **How the die-off ends.** Run on to t = 1000 (seed 0), c = 0.1 levels off just after t = 500 at about 13,840, and
  c = 0.2 at about 13,370. The slower drain leaves more time to find room on richer land, so c = 0.1 does not fall as
  far as c = 0.2.

### Memory and word of mouth (`XXL-memory`, II-4)

**Memory has no aggregate effect beyond the seed spread, though it changes every individual run.** `solo` and
`shared` match `XXL-speed/c0.1` within the seed spread at every checkpoint (final population 14,703 ± 89 and
14,704 ± 92 against 14,703 ± 93; final Gini 0.386 in all three; mean sugar 542 in all three). Only the three 5-seed means
agree this closely: seed by seed the runs part from t ≈ 8–12 (the first period at which a population differs from
the speed run's same seed is 8–12 in all ten memory runs), and the populations at t = 500 differ by up to 88 agents in
a seed (seed 2: 14,020 against 13,932; seed 4: 14,082 against 14,156 in `solo`), in both directions, with a mean
difference of −5 (`solo`) and +2 (`shared`) agents.

The share of agents whose target is a remembered site *beyond vision*, `share_remembered_target`, is exactly 0 in every
period of all five seeds of `solo` and `shared`, so that is not how memory acts here. The ranking is why, and it follows
from the spec's rule 3, not from a bug. `rank_pool!` keeps the M = 8 entries of highest rule-2 net value from the
agent's current position, and that value charges the waiting cost m₁(T − 1): a site beyond the agent's speed takes
T ≥ 2 periods, so it loses at least m₁ (1–4 sugar here) on top of the travel cost, and ranks below any site within
speed that has nearly as much sugar. Memory therefore fills with the near disc, which rule 1 looks at every period
anyway, and almost never holds far food. A diagnostic on one run (`solo`, seed 0, at t = 5, 30, 60 and 200, measured
on a copy of the model so that the run itself was not disturbed) found 89–91% of the entries within the agent's speed,
9–11% beyond its speed but within its vision, and at most 9 of the 150,000–320,000 entries beyond vision, none of them
a target; 3–20% of the entries held no sugar (20% at t = 5, 3% from t = 60). With nothing to pick beyond vision,
memory's only input to a move is rule 1, step 4: `look!` appends the remembered sites within vision that the period's
ring draws missed, 0.74–0.89 per agent per period in that run. Each is an extra candidate, or changes a tie count and
so shifts the reservoir draws that follow, which is enough to part every run from the speed run's same seed by
t ≈ 8–12. They lie beyond the agent's speed and carry the same waiting cost, so presumably they seldom beat the near
sites, and the aggregates do not move. Word of mouth is not what starts the divergence, since `solo` also departs at
t ≈ 8–12. For memory to matter the ranking would have to change, for example to the resources less the travel cost,
without the waiting term, so that far food can be remembered. That is a possible change, not one tested or
recommended here.

Beyond-vision remembered targets are rare everywhere: over all five seeds, the share is nonzero in none of the periods
of `XXL-radius/R1` and `XXL-terrain/II-4`, in 1 period of one seed of `XXL-radius/R1.5` and 3 periods of one seed of
`XXL-radius/R3`, in 1–2 periods of three seeds of `XXL-terrain/IV-A3`, in 0–7 periods per seed of `XXL-seasons`, 0–19
of `XXL-society/VI-1` and 0–1 of `XXL-combat/III-9`, at most 4.1 × 10⁻⁴ of the agents in any period (in `XXL-radius/R3`
seed 0). All of these runs have memory, speed and a travel cost, so they rank memory the same way, and the cause is
presumably the same; the diagnostic above was run on `solo` only. Whether other settings (slower growback, smaller
vision, patchier food, a larger speed) would change this was not tried.

Memory has a cost: 0.146 and 0.155 s per period against 0.080 for the same run without it (1.8–1.9×); per agent and
period, 7.8 and 8.3 µs against 4.3.

### Interaction radius (`XXL-radius`, IV-A3)

Full xxl defaults on IV-A3 (trade), R = 1, 1.5 and 3.
- **xxl is far from xl in this experiment, at any R.** Final population is 2,181 ± 23 (R = 1), 2,199 ± 39 (1.5) and
  2,251 ± 29 (3), against 3,739 ± 72 for xl; at t = 50 it is 3.9–4.1k against 8.7k. Final mean sugar is 198–199
  against 120.
- **R makes a small difference to survival** (R = 3 is 3% above R = 1 final, 2,251 against 2,181, seed sds 23–29),
  and a large one to trade: trades per period rise with R, final 1,034 ± 60, 1,198 ± 46 and 1,508 ± 46, as the
  number of neighbours grows; xl has 3,894 ± 139 with about 1.7× the population.
- **Prices spread more than in xl, whatever R.** Final price sd is 0.78, 0.78 and 0.82 against 0.56 for xl.
  Regional price sd (between the hundred 50 × 50 regions) is 1.13, 1.14 and 1.17, and the slope of |Δ log price| on
  distance is about 0.0012–0.0013 per site in all three: a trade 100 sites away differs in log price by about 0.12
  more than a neighbouring one. R barely moves these.
- **Agents clump hard.** The pair correlation at distance 1 is 11.4–12.0 final (from 1.5 at t = 50) at all three R, at 10 it
  is 2.9–3.0, and at 50 it is about 1.1: small, dense groups on the best sites. The R = 3 run is slightly less
  clustered at distance 1 (11.4 against 12.0, about two sds).
- Stepping is 2.2–2.4× xl's. R barely changes the cost.

### Seasons by latitude (`XXL-seasons`, II-7)

Full xxl defaults on II-7, without and with the gradient.
- **The gradient makes a difference.** Final population is 12,605 ± 57 with it against 11,282 ± 36 without (+12%), and
  at t = 50, 17,443 ± 29 against 15,916 ± 28 (+10%). xl has 17,650 ± 81 final and 22,667 at t = 50.
- **Final mean sugar is 445 against 398** (xl 441). At t = 100 and 200 it is 96 and 176 with the gradient against 89 and
  175.
- **Inequality differs in the middle:** Gini 0.389 and 0.425 at t = 100 and 200 with the gradient against 0.364 and 0.359,
  and the same at the end (0.355 against 0.349). Both are above xl's 0.30.
- **Migration toward the equators is modest.** The mean winter weight λ is 0.62–0.66 with halves, close to the 2/π ≈ 0.64
  of agents spread evenly over latitude; with the gradient it is 0.57–0.62, lower at every checkpoint: 0.575, 0.572 and 0.599
  at t = 100, 200 and final. That is a drift of 0.02–0.07 in λ, not a mass move; the t checkpoints sit at fixed phases
  of the season cycle, so those figures are not season-averaged (the final column averages the last 100 periods).
- Stepping is 4.0× (halves) and 4.5× (gradient) xl's per period.

### Generated landscape (`XXL-terrain`, II-4 and IV-A3)

Full xxl defaults on the generated maps (400 Gaussian bumps, radii 5–80, the xl map's capacity counts). The
control for II-4 is `XXL-memory/shared`, and for IV-A3 `XXL-radius/R1.5`: the same rules on the xl map. The II-4
control is not exact: it has R = 1, the terrain run R = 1.5. II-4 has no trade, culture or mating, but word of mouth
copies from the agent's neighbours, which the radius sets (4 neighbours at R = 1, up to 8 at 1.5), so the radius can
change who an agent hears from.
- **II-4:** population is 4% above the control final (15,272 ± 37 against 14,704 ± 92), 1.7% above at t = 50 and 1.2%
  at t = 100.
  Mean sugar and Gini are close (537 and 0.387 against 542 and 0.386). The pair correlation final is 1.47 against
  1.25 at distance 1, 1.51 against 1.50 at 10 and 1.25 against 1.35 at 50.
- **IV-A3:** the population is 49% above the control final: 3,286 ± 49 against 2,199 ± 39, and 41% above it at t = 50
  (5,545 against 3,933). It is 12% below xl (3,739). Trades per period double (2,591 ± 94 against 1,198 ± 46), price sd
  is lower (0.58 against 0.78), regional price sd is lower (0.73 against 1.14), and clustering at distance 1 is 8.5
  against 11.8, and 0.86 at distance 50, below the random 1: agents are spread out at long range. Mean sugar is
  224 against 199.
- The same rules cost IV-A3's agents far more on the xl map than on the generated map, and II-4's agents hardly
  differ. IV-A3 needs sugar and spice, and the xl map puts them in opposite places. II-4 eats only sugar, and gains
  only from shorter climbs to richer land: see "Why the map matters" below.
- Stepping is 4.5× xl's per period in II-4 and 2.9× in IV-A3.

**Why the map matters.** This comes from tracing every founder of IV-A3 and II-4 under the full xxl defaults on each
map, so the map is the only difference (seeds 0–2 each, 12 runs that reproduce the recorded populations exactly), and
from measuring the maps. The two map pairs have the same number of sites at each capacity; only the layout differs.

| | xl map | generated map |
|---|---|---|
| Correlation of sugar and spice capacity per site | −0.57 | −0.12 |
| Sites with sugar ≥ 3 and spice ≥ 3 | 1,796 | 21,437 |
| Sites with sugar ≥ 4 and spice ≥ 4 | 0 | 1,951 |

- **IV-A3: where a founder starts decides whether it lives.**
  - *The land near the start is the best predictor.* Score each founder by the best min(sugar, spice) capacity
    within 20 sites of where it starts. Survival to t = 300 by that score is about the same on both maps: 0% at 0,
    4–8% at 1, 15–19% at 2, 31–32% at 3 and 60% at 4 (the xl map has no land scoring 4).
  - *The generated map starts far more founders near good land.* 13,319 of 60,000 score 3 or 4, against 1,789 on
    the xl map, and 6,609 score 0, against 15,560.
  - *That more than explains the gain.* The xl map's survival rates applied to the generated map's founders predict
    10,900 survivors, against 9,344 actual and 6,290 on the xl map. The weaker scores survive a little less on the
    generated map (4% against 8% at 1, 15% against 19% at 2), presumably from competition with the extra survivors
    (not tested).
  - *Survivors mostly feed themselves.* About 80% of the agents alive at t = 100 stand on a site that covers both
    their metabolisms by itself (84% on the xl map, 79% on the generated one).
  - *Metabolism matters; vision and speed barely do.* Survival rises for every pair of metabolisms, most for the
    harder ones: sugar 1 with spice 3 goes from 16% to 31%, and sugar 2 with spice 2 from 24% to 36%. Across vision
    and speed it varies by a few points at most.
- **II-4: a gain of 4.5%, almost all from metabolism 2.** On the same rules, the generated map keeps 43,879 of
  120,000 founders against 41,983 (so the inexact control above was not hiding a larger effect).
  - *Who gains:* metabolism-2 survival rises from 40% to 46%, 1,930 of the 1,896 extra survivors. Metabolism 1
    barely changes (+92), and metabolism 3 is slightly worse off (−126).
  - *Why metabolism 2 gains:* under the travel-cost die-off (`XXL-speed` above), an agent on land whose capacity
    equals its metabolism survives only by moving up to richer land as room opens. On the generated map,
    capacity-2 land is about twice as close to capacity-3 land (a median of 12 steps against 23). So 75% of the
    metabolism-2 agents on capacity-2 land at t = 100 die later, against 86% on the xl map.
  - *Why metabolism 3 doesn't:* capacity-3 land is farther from capacity-4 land on the generated map (a mean of 38
    steps against 24), so 86% of the metabolism-3 agents on capacity-3 land die later, against 84%.
  - *The net is small* because these partly cancel, and II-4 never uses spice, where the maps differ most.
- **Caveat.** This rests on one generated map pair. Its −0.12 correlation is that draw's chance, not a property of
  the generator, so another pair would shift the numbers but not the mechanism.

### Combat (`XXL-combat`, III-9)

Full xxl defaults on III-9, which is combat (rule C with α = ∞, the reward being the victim's wealth) between tribes
placed in blocks.
- **Combat is far less lethal under xxl.** xl III-9 falls from 54,000 to 435 ± 422 by the last 100 periods (Gini 0.80 ±
  0.10, mean sugar 40,011 ± 17,900 among a few rich survivors). xxl keeps 19,373 ± 1,260 (Gini 0.37 ± 0.03, mean sugar
  1,365 ± 48). At t = 100 xxl has 27,813 against xl's 27,060, and at t = 200 26,298 against 18,311: the paths diverge
  after about t = 100.
- **Agents never rest:** 1% settled, 1.3 sites moved per period.
- **Agents cluster** at 1.9–2.5 at distances 1, 10 and 50, a flat profile, not the sharp short-range clumps of IV-A3.
- Stepping is 10× xl's per period (0.346 against 0.035 s), the largest ratio of all. The population over the run
  is 2.3× xl's on average (about 23,560 against 10,290 agents, because xl's collapses), so per agent and period it
  is 4.4× (14.7 against 3.4 µs).
- This experiment runs rule 7 together with the other xxl rules. The controls below separate combat's own effect and
  find which rule tames it.

**What combat itself does.** III-9 has no aging, so every death is either a kill or a starvation. The source is a run
of III-9 with combat on and off (`combat_alpha = nothing`) under four rule sets, seeds 0–2 each, 1000 periods, with
starvations told from kills by recording the deaths inside `metabolize!` (a copy of the method that draws nothing; the
xl and xxl runs reproduce the recorded populations exactly). The four rule sets are xl, round vision alone, round
vision with speed (1, 6) and travel cost 0.1, and the full xxl defaults. Means over the three seeds:

| Rules | Population at t = 100, on / off | t = 300 | t = 1000 | Gini at t = 1000, on / off | Kills by t = 1000 |
|---|---|---|---|---|---|
| xl | 27,113 / 30,672 | 11,147 / 28,288 | 383 / 27,747 | 0.82 / 0.26 | 31,000 |
| round vision | 4,881 / 30,173 | 953 / 28,519 | 705 / 27,695 | 0.48 / 0.27 | 38,011 |
| round vision + speed | 27,809 / 28,276 | 24,502 / 25,974 | 19,081 / 24,428 | 0.38 / 0.25 | 5,504 |
| full xxl | 27,797 / 28,283 | 24,471 / 25,969 | 19,037 / 24,424 | 0.38 / 0.25 | 5,536 |

- **Speed is what tames combat.** With speed an occupied site can be attacked only within the attacker's speed (1–6
  sites), where without it any occupied site in sight (10–60 sites) can be taken in one jump. Adding speed cuts the
  kills from 38,011 to 5,504, and the other xxl rules then change almost nothing (19,037 against 19,081 at
  t = 1000).
- **Round vision alone makes combat deadlier than xl.** It has 33,836 kills by t = 100, against xl's 4,836, and the
  population falls to 4,881. Presumably a disc finds more targets than four lines of sight do (not tested). It then
  settles at about 350 agents per tribe.
- **Under xxl, combat costs 22% of the population by t = 1000** (19,037 against 24,424), and the gap is still
  widening: 486 agents at t = 100, 1,498 at t = 300, 5,387 at t = 1000. Kills run at a steady 4–6 per period
  throughout (5.2 over t = 51–100, 5.7 over t = 501–1000), so the gap grows as they accumulate; the run is not at
  equilibrium at t = 1000.
- **Kills add to starvation, not replace it.** Under xxl, 29,427 starve with combat against 29,576 without, so the
  victims are not mostly agents who would have starved anyway. Kills are about 16% of all deaths, and both tribes
  survive (8,083–11,240 agents each at t = 1000). Combat raises the Gini by 0.13, against 0.56 in xl.
- **xl collapses in two phases,** the same in all three seeds. Up to t = 300 blue destroys red: about 15,000 red
  victims against 4,000–6,000 blue. Over t = 301–1000 the 170–910 reds left fall to about 20, yet kill about 10,000
  blues. With α = ∞ each kill takes the victim's whole wealth, so the last reds grow too rich for any blue to
  retaliate against: mean wealth at t = 1000 is 17,000–55,000 sugar. Why blue wins the first phase was not examined;
  it is not the land, since the red block is the richer (mean capacity 3.15 against 2.76).
- **First contact.** The two blocks touch only at a corner, across the torus seam. The first kill is at t = 1 under
  the xxl rules and at t = 12–14 under xl, presumably because xl's lines of sight do not cover the diagonal (not
  tested).

### Society (`XXL-society`, VI-1)

Full xxl defaults on VI-1, which has the Chapter VI rules at once: sex, culture, trade, credit and disease on the
sugar and spice landscape (no combat).
- **Deeper early trough, then growth.** Population is 1,677 ± 74 at t = 50 and 1,040 ± 153 at t = 100 (xl 4,210 and
  5,075), 13,144 ± 2,320 at t = 200 (xl 50,613 ± 8,910), and 61,596 ± 4,800 final (xl 89,507 ± 8,880). No seed went
  extinct: the five end at 58,131–66,507.
- **Mean sugar and Gini end near xl's:** 28.4 ± 0.7 against 29.2 ± 0.3, and 0.206 in both. At t = 100 mean sugar is 61.6
  against 43.8.
- **Trades are fewer** (17,552 ± 1,640 final against 101,940 ± 36,300; about 0.28 per agent against 1.1) and price sd is
  higher (0.51 against 0.40).
- **Clustering is extreme at t = 100:** 20.8 ± 10.2 at distance 1 and 15.2 ± 7.2 at 10, with a wide spread across
  seeds, and falls to 1.9–2.0 by the end (1.8 at 50).
- Stepping is 1.8× xl's per period (0.93 against 0.52 s) with 28% fewer agents at the end. A full run of five seeds took
  42 minutes, far less than the several hours expected from the xl timings.

### What the first runs show

- In II-4, speed alone costs about a quarter of the early population, and a travel cost of 0.1 or more adds a second
  die-off. The second die-off kills the agents whose metabolism equals the capacity of their land: they must step
  about one site per period to eat, the travel cost turns their zero margin negative, and they starve when their
  savings run out.
- Round vision without speed changes xl little (2–4% less population) but clusters agents.
- Memory and word of mouth change every individual run from about t = 10 but have no aggregate effect beyond the seed
  spread at these settings. Memory ranks sites by rule 2's value with its waiting cost, so it keeps the sites within
  the agent's speed, which it looks at anyway, and beyond-vision targets are almost never chosen (a diagnostic on one
  run). They cost about 1.8× the stepping time.
- The interaction radius raises trade volume strongly and survival barely (R = 3 is 3% above R = 1, about 3 seed
  sds); price levels hardly change.
- The latitude gradient raises population by about 10% and moves agents toward the equators in a small way.
- On the generated landscape IV-A3's population is half as large again as on the xl map, and II-4's differs by
  4%; each rests on one map pair. The xl map puts sugar and spice in opposite places, so few IV-A3 founders start
  near land that feeds both metabolisms. II-4 gains only from shorter climbs to richer land.
- Combat survives the xxl rules, and the population does not collapse as in xl. Against the same rules without
  combat, it costs 22% of the population by t = 1000, against 99% in xl. Speed is what makes the difference: it
  limits attacks to within 1–6 sites. Round vision alone makes combat deadlier than xl.
- Everything in this section comes from one run per experiment, 5 seeds, on a machine whose load was not recorded.
