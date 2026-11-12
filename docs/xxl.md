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
the changes stage 1 chose ("Stage 1: the scorecard and survival") and the disease list stage 4 chose ("Stage 4: the
disease list"). Stages 1–4 were run before list D became the default, so where they say `XXL_DEFAULTS` they mean these
settings with the experiment's own disease list.

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
| `disease_count` | none | none | **3** | 12 |
| `founder_diseases` | none | none | **1** | 12 |
| `disease_lengths` | none | none | **(9, 10)** | 12 |
| `trade_move` (expected price: `"own"` or `"local"`) | none | none | none | 13 |
| `trade_blend` λ (score W^(1−λ)·V^λ) | 1 | 1 | 1 | 13 |
| `trade_guard` k (periods of sugar or spice) | none | none | none | 13 |
| `trade_price` (`"meeting"`: one price per meeting) | none | none | none | 14 |
| `trade_step` (share of the book's unit a step trades) | 1 | 1 | 1 | 15 |

`max_metabolism`, `founder_placement`, `free_step` and `founder_ages` are the stage-1 survival switches. Each was tried
at a candidate setting, and the scorecard decided which to keep:

| Setting | Candidate | What the candidate does | Chosen by stage 1 |
|---|---|---|---|
| `max_metabolism` | 4 | Caps the sugar and spice metabolism drawn for a new agent | No |
| `founder_placement` | `"viable"` | Places founders and newcomers on land that feeds them | Yes |
| `free_step` | 1.5 | Charges no travel cost for a move whose target is within 1.5 sites | Yes |
| `founder_ages` | `"young"` | Starts founders no older than the start of their fertile years | No |
| `landscape` | `"generated"` | Makes the generated map the default | Yes |

The xxl version of a regular experiment is its xl version (docs/xl.md) with these set to the default column. For a
base experiment without seasons the season gradient is set to false, for one without sex or without finite lives
`founder_ages` is set to `"book"`, for one without disease the three list settings are set to none, and for one without
trade the three trade move settings are set to none (`trade_blend` to 1), so a fingerprint never names a rule that can't
apply.

**Refused combinations.** A configuration xxl doesn't define is refused, not run under book rules:
- `vision_shape` other than `"lattice"` or `"disc"`; `landscape` other than `"xl"` or `"generated"`;
  `founder_placement` other than `"random"` or `"viable"`; `founder_ages` other than `"book"` or `"young"`;
- speed that isn't a range lo ≤ hi with lo ≥ 1; travel cost below 0; R below 1; memory below 0; span below 1;
  a free step below 0; a metabolism cap below 1, below the lowest sugar metabolism, or (with spice) below the
  lowest spice metabolism;
- a disease count below 1; founder diseases below 0 or above the count; a disease length range that isn't lo ≤ hi with
  lo ≥ 1, or whose hi reaches `immune_length`; any of the three on an experiment without disease, or disagreeing with
  the configuration;
- a trade move other than none, `"own"` or `"local"`; a trade blend outside 0–1; a trade guard below 0; a trade blend
  other than 1 or a trade guard without a trade move; a trade move on an experiment without trade;
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
at equal distance, in the order looked at. An agent that isn't fertile doesn't look at all, since nothing could come
of its search; it makes no draws either. (With the lattice look it is the book's.)

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

## Rule 12: the disease list

**Book setting:** `disease_count`, `founder_diseases` and `disease_lengths` are none: the experiment's own list stands
(VI-1: 25 diseases of lengths 1–10, with 10 offered to each founder).

**xxl:** each one set replaces its configuration field: `disease_count` the diseases on the master list (`disease_list`),
`founder_diseases` the diseases offered to each founder (`diseases_per_agent`), and `disease_lengths` the lowest and highest
length, inclusive (`disease_length`). Only the configuration changes. The rules and their draw order don't, and a founder
is still skipped for a disease it's immune to. For an experiment without disease the transform sets them back to none.

**Stage 4:** studied in "Stage 4: the disease list" below, which recommends 3 diseases of length 9–10 with 1 offered to each
founder. The user adopted it, so the defaults use that list. Under `--xxl` it reaches every experiment with disease: VI-1,
which stage 4 measured, and V-1, V-2 and `VAR-inttrade/VI-1`, which it didn't.

## Rule 13: movement that counts on trade

**Book setting:** `trade_move` is none, `trade_blend` is 1 and `trade_guard` is none: an agent scores a site by the
welfare of the sugar and spice it would hold after eating there, as in the book, whatever trade lets it do.

**xxl** (`trade_move` set; it needs trade): an agent under trade scores a site by the value of the bundle it would hold
there at the price it expects to trade at, instead of by the welfare of that bundle alone. Three settings shape it:

| Setting | Values | What it does |
|---|---|---|
| `trade_move` | none / `"own"` / `"local"` | Which price p the agent expects, in spice per sugar. `"own"`: its last trade price, which never ages, falling back to its MRS when it has not traded. `"local"`: the geometric mean (the mean log) of the latest exchange price at its own site and at each site it looked at this move, counting only sites with an exchange in the last 10 periods, falling back to its MRS when there are none. None leaves the rule off |
| `trade_blend` λ | 0 to 1 | How far the score moves from the book's welfare W toward the value V at p: the score is W^(1−λ)·V^λ, so 1 is the full rule and 0 the book's |
| `trade_guard` k | periods, or none | An agent whose sugar or spice would last fewer than k periods at its burn (`sugar_burn`, the disease fees included, for sugar; its spice metabolism for spice) scores by the book's rule, so it doesn't gamble on a trade it may not find |

**The score.** For a site, (A, B) is the bundle the agent would hold after the trip: its holdings as the book's score
counts them (the foresight clamp; with speed, less the travel cost and what it burns on the way), plus the site's sugar
and spice, devalued by pollution. W is the book's welfare of (A, B), A^e₁·B^e₂, and V = A + B/p is what the bundle is
worth in sugar at the expected price p. The score is W^(1−λ)·V^λ: both W and V grow in proportion with the bundle, so
the blend needs no units (*my call*). A site where the agent would starve on the way is still worth nothing. When there
is no valid price (no trade price and no MRS, as when it holds no spice) or the guard holds, the move uses the book's
score as it stands.

**Where it applies.** The site score of all three moves. `speed_move!` and `xxl_move!` read the local price from the
sites of their look; the book's lattice loop (`move!` without round vision or speed) keeps no list of what it looks at,
so its local price reads the agent's own site only (*my call*). Under memory the remembered sites are valued at the
move's price, both when the move picks its target and when it updates the memory after, and word of mouth ranks the
agent's memory and its neighbours' best at the same move's price, so the memory stays ranked as the move would rank it
(*my call*). Combat's move uses the book's score.

`trade_blend` and `trade_guard` change nothing unless `trade_move` is set. Speed and travel cost don't change. For an
experiment without trade the transform sets all three back to their book values.

**Refused:** an unknown `trade_move`; a `trade_blend` outside 0–1; a `trade_guard` below 0; `trade_blend` other than 1 or
`trade_guard` set without a `trade_move`; `trade_move` on an experiment without trade, if it reaches `Config` directly.

**Fingerprint:** the `xxl` line names a trade move setting only when it is off its book value, after the disease list:
`trade_move="local" trade_guard=5`, with `trade_blend=0.5` between them when it isn't 1. A run with the rule off has the
fingerprint it always had.

**Stage 5:** measured in "Stage 5: trade": no version passed screening, and the rule changed almost nothing.

## Rule 14: the meeting's price

**Book setting:** `trade_price` is none: in rule T the two neighbours trade one unit at a time, and the price is the geometric mean
of their two current MRSs, worked out again before every unit.

**xxl** (`trade_price` set; it needs trade): the price is set once, when the meeting starts, and every unit of the meeting trades at it.

| Value | What a meeting does |
|---|---|
| none | The book's rule T: the price is recomputed before every unit, so it follows the two MRSs as each unit moves them together |
| `"meeting"` | The price is the geometric mean of the two MRSs when the meeting starts, worked out once. Which agent buys sugar (the one with the higher MRS then) is fixed for the meeting too. The meeting ends at the first unit that fails a test |

**What stays.** Only the price changes. The unit sizes are the book's (price p above 1: 1 sugar for p spice; p below 1: 1/p sugar
for 1 spice; whole units with `trade_rounding = "down"`), and so are the tests on each unit: holdings stay positive, the buyer's MRS
stays at or above the seller's, and both welfares strictly rise. A meeting whose starting MRSs aren't both valid, or are equal, doesn't
trade, as now. Each accepted unit still goes to the trade log with its price, so `last_price` and every metric read it as before.
Trading once with each neighbour, in random order, is unchanged.

**Why.** *The user's reasoning:* it isn't realistic for the MRS to set a new price during a single bargaining session. The price
should be set when the session starts and apply to every unit exchanged. *My call:* with a price fixed per meeting, prices differ
between meetings by who meets whom, so an agent can sell dearly to a neighbour in need and buy cheaply from one with a good to spare,
which the moving price squeezes out. Measured in "Stage 5b: the meeting's price": it didn't make healthy traders richer, while a
meeting moved only 1.68 units on average.

**Rule 13:** the code allows both rules at once, but the study doesn't combine them. For an experiment without trade the transform sets `trade_price` back to none.

**Refused:** a `trade_price` other than `"meeting"` (or none); `trade_price` on an experiment without trade, if it reaches `Config`
directly.

**Fingerprint:** the `xxl` line names it only when it is on, after the disease list and Rule 13's settings: `trade_price="meeting"`.
A run with the rule off has the fingerprint it always had. `--set trade_price=meeting` reads it in the extinction, scorecard and
trade study commands.

## Rule 15: the trade step

**Book setting:** `trade_step` is 1: in rule T each step of a meeting trades the book's unit (price p above 1: 1 sugar for p spice;
p below 1: 1/p sugar for 1 spice).

**xxl** (`trade_step` below 1; it needs trade): each step trades that share of the book's unit, so a step of 0.1 trades a tenth of
the sugar and a tenth of the spice the book would. The meeting goes on step by step until a step fails a test, so a smaller step means
more steps in a meeting and a meeting that stops closer to where the two MRSs meet.

| Value | What a step does |
|---|---|
| 1 (the book) | The book's unit: the sugar and spice of a step are what price and rounding give |
| above 0, below 1 | The step's sugar and spice are both multiplied by it, in either price rule (the book's price recomputed before every step, or Rule 14's price for the meeting). With Rule 14 every step trades at the meeting's price |

**What stays.** Only the step's size changes. Both price rules, the tests on each step (holdings stay positive, the buyer's MRS stays at
or above the seller's, both welfares strictly rise) and trading once with each neighbour, in random order, are as they are. Each
accepted step still goes to the trade log with its price. Volume is read in goods moved, not in exchanges counted, since a smaller step
makes more exchanges for the same goods.

**Why.** *The user's idea:* trade in smaller units. *My call:* the name and type (`trade_step`, a `Float64`). The study's step of 0.1
was my proposal, which **the user** approved. The step's behaviour in `bargain!` is described in the design
(`docs/superpowers/specs/2026-11-05-xxl-trade-step-design.md`). Measured in "Stage 5c: smaller trade steps": with no disease, agents moved
more than twice as much sugar, but traders ended no richer than similar non-traders.

**Rule 13:** the code allows it with Rule 13, but the study doesn't combine them. For an experiment without trade the transform sets
`trade_step` back to 1.

**Refused:** a `trade_step` at or below 0, above 1, or not finite; a `trade_step` other than 1 with `trade_rounding = "down"` (whole
units would round a tenth to nothing; *my call*); a `trade_step` other than 1 on an experiment without trade, if it reaches `Config`
directly.

**Fingerprint:** the `xxl` line names it only when it isn't 1, after Rule 14's setting: `trade_step=0.1`. A run with the step at 1 has
the fingerprint it always had. `--set trade_step=0.1` reads it in the extinction, scorecard and trade study commands.

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
  `name=value`, in the table's order, then each later setting only when it is off its book setting
  (so a first-rules fingerprint is as it was before they existed), space separated (strings in double quotes,
  `speed=nothing` or `speed=(1, 6)`). The base experiment's `Config` line below keeps its own `disease_list`, as it
  keeps its own map, so the `xxl` line is what names a list. For the first rules it is
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
- **Trying a setting.** `julia/xxl_scorecard.jl` and `julia/xxl_extinction.jl` both take a repeated `--set field=value`,
  so a candidate can be scored or tested for extinction without becoming a default. It goes in the fingerprint, so give
  each candidate its own `--label`. `julia --project=julia julia/xxl_disease_list.jl --base FOLDER --arms NAME=FOLDER,…
  [--label NAME]` reads finished extinction runs against a baseline and the disease list's reading table (stage 4). It
  runs nothing, so it can be used while a run is going.
- **Agreement is statistical.** An xxl run's random stream differs from every other run's, in any language.

## VI-1 with pollution

Two experiments ask whether pollution makes a population migrate: whether agents leave polluted land, and come back
once diffusion has cleaned it. Both are `VI-1-assim-k4` (the combat study's passing arm) with the book's pollution
added and nothing else changed: the seeds, combat, culture rule, curve, `h`, sex, trade, credit, inheritance, disease
and the xxl defaults that today's world applies. In `VI-1-pollution` pollution starts at t = 350 and diffusion at
t = 450, so it meets a society that has settled. In `VI-1-pollution-t0` both start at t = 0, so the society grows
up with pollution.

| Setting (book config) | `VI-1-pollution` | `VI-1-pollution-t0` |
|---|---|---|
| `pollution` (α, β) | (1.0, 1.0), the book's P₁,₁ | (1.0, 1.0) |
| `pollution_start` | 350 | 0 |
| `pollution_stop` | none (pollution keeps being made after diffusion starts, as in II-8) | none |
| `diffusion_period` | 1 (D₁) | 1 |
| `diffusion_start` | 450 | 0 |
| `diffusion_passes` | 1 in the book's world; the xl transform makes it 100 in xl and today's world (docs/xl.md) | same |
| steps | 600 | 600 |

The rates are the book's: production pollution is α × the sugar harvested, at the harvest site; consumption pollution
is β × the sugar burned (metabolism, disease fees and the travel cost), at the agent's site. Spice is clean. Sugar
taken in combat makes no production pollution (rule 7). Agents already score sites by resources ÷ (1 + pollution)
(rules 1–3 and combat's site welfare), so no choice they make changes.

- **Running them.** Through the combat study, as for the other VI-1 experiments:
  `julia --project=julia julia/xxl_combat_study.jl --world today --exp VI-1-pollution …` (or `VI-1-pollution-t0`). The
  worlds `book` and `xl` can be asked for too; only today's world is in the viewer. An experiment without pollution
  writes exactly the files it wrote before.
- **Timing.** The step taken from t = 350 to t = 351 is the first to pollute, so row t = 351 is the first polluted
  reading; likewise the first diffused reading is t = 451. The charts' dotted lines sit at 350 and 450 in
  VI-1-pollution (none in VI-1-pollution-t0, where both start at 0).
- **Checkerboard.** Rule D averages a cell's four neighbours without the cell itself, so each pass moves pollution to
  the opposite colour of the checkerboard. An even number of passes per period (100 in xl and today's world) brings
  it back to the colour it was made on. So pollution stays on the colour it was made on, and the banded map can show a
  checkerboard texture. That is the model's behaviour, not a viewer fault; no rule changes here.
- **`seed<k>-pollution.csv`.** Written only for experiments with pollution, next to `seed<k>-combat.csv`, with the
  columns below after `t` (`periods + 1` rows). A seed counts as done only when this file exists too. All are read at
  the end of the period, where the combat readings are read. The last four came with the decay rule (below) and are
  written for every pollution experiment; files saved before then have only the first three.

  | Column | Meaning |
  |---|---|
  | `mean_pollution` | The mean pollution over all cells of the world. |
  | `agent_pollution` | The mean pollution of the cells the agents stand on. `nan` with no agents. |
  | `share_rich` | The share of agents standing on rich land. `nan` with no agents. |
  | `agents_rich` | The number of agents standing on rich land. |
  | `agents_other` | The number of agents standing on the other cells; with `agents_rich`, the population. |
  | `pollution_rich` | The mean pollution over the rich cells. |
  | `pollution_other` | The mean pollution over the other cells (`nan` if every cell is rich). |

  Rich land is the cells whose sugar capacity plus spice capacity is at or above the 75th percentile of that sum over
  all cells, worked out once per run from the fixed capacities. Ties at the cut are included, so the share of cells
  that counts as rich can exceed a quarter. In today's world the cut is a capacity of 5, which covers 32% of cells.

### Results (2026-11-11)

**The short answer.** Pollution barely moves agents off the rich land; it brings the poor land into use. When it
starts, the number of agents on rich land dips by about 5% and is back above its old level by the time diffusion
starts, much as in the book's II-8, where (in docs/book-notes.md's summary of pp.48–50) agents return to high-sugar
regions after diffusion. Meanwhile the number on
poorer land nearly triples, so the society ends about 45% bigger and the *share* on rich land falls from 0.71 to
0.48. (A first reading of these runs took that falling share for an exodus; the counts below correct it.) Pollution
also shrank the minority culture: it was lost in every seed when pollution started at t = 0, and fell to a tenth of
the agents when it started at t = 350. A control without pollution shows the growth and the minority's fall are
pollution's doing.

**The runs.** Today's world, seeds 0–19, 600 periods, 5 workers, all run with the user's go-ahead
(`results-julia-xxl/combat-today-<exp>-s0-20-p600/`):

| Run | Experiment | Pollution, diffusion from |
|---|---|---|
| Late | `VI-1-pollution` | t = 350, t = 450 |
| Control | `VI-1-assim-k4` with `--periods 600` | none |
| From the start | `VI-1-pollution-t0` | t = 0, t = 0 |

`VI-1-assim-k4` had only been run to t = 500, so the control repeats it to 600. Its first 500 periods match the saved
runs (median population 65,192 at t = 500 in both). Every late seed's main and combat tables for t = 0–350 are
byte-identical to its control seed (20 of 20), so all differences come from pollution. Every seed of all three runs is
alive at t = 600.

**Readings** (medians over seeds; "where agents stand" is `agent_pollution` ÷ `mean_pollution`):

| Reading | Late | Control | From the start |
|---|---|---|---|
| Share on rich land, t = 350 | 0.71 | 0.71 ¹ | 0.54 |
| Share on rich land, t = 450 / 600 | 0.54 / 0.48 | – | 0.49 / 0.48 |
| Agents on rich land, t = 350 / 400 / 500 / 600 | 43.6k / 41.9k / 45.1k / 46.2k | – | 41.7k / 43.0k / 44.9k / 45.4k |
| Agents off rich land, t = 350 / 600 | 17.6k / 51.1k | – | 35.4k / 49.5k |
| Agents on / off sugar capacity ≥ 3, t = 600 ² | 43.2k / 53.7k | 39.6k / 27.4k | 42.0k / 52.9k |
| World mean pollution, t = 450 / 600 | 74 / 217 | 0 | 171 / 310 |
| Where agents stand, t = 450 / 600 | 1.59 / 1.15 | – | 1.18 / 1.11 |
| Population, t = 600 | 97,282 | 67,381 | 95,230 |
| Minority share, t = 500 / 600 | 0.36 / 0.10 | 0.36 / 0.36 | 0.010 / 0.000 |
| Seeds with the minority ≥ 5% at t = 600 | 13 of 20 | 19 of 20 | 0 of 20 |
| Kills per period, t = 600 | 168 | 254 | 0 |

¹ The control writes no pollution table. Its share is the late run's, which is identical to it up to t = 350.
² The main table's `on_peak_fraction` (sugar capacity ≥ 3), the one land reading the control has. Counts are
population × share, medians over seeds.

- **A small, short retreat.** In the late run the agents on rich land (about 80,500 cells, 54% occupied at t = 350) fall
  to a low of 92–97% of their t = 350 number in each seed (median 95%); the median count is lowest around t = 400. The
  count is rising again by t = 425 (42.4k), is back above its old level when diffusion starts (43.9k at t = 450) and
  keeps climbing (45.1k at t = 500, 48.1k at t = 550). At t = 375 agents stand on land twice as polluted as the world's
  mean (1.98 times it); diffusion brings that down to 1.15 by t = 600 while the mean keeps rising.
- **The poor land fills.** The agents off rich land go from 17.6k at t = 350 to 51.1k at t = 600. Without pollution
  the poorer land stays thinly settled: on the sugar-capacity reading the control has 27.4k off the good land at
  t = 600 against the late run's 53.7k, and 39.6k on it against 43.2k. So the share on rich land falls because the
  society grows on the poor land, not because agents leave the rich land. With pollution from the start, agents never
  crowd onto the rich land: its share is about 0.72 from t = 25 to 250, against near 0.98 without pollution (¹).
- **A bigger society.** The control levels off near 67,000. The late run passes 82,000 by t = 450 and peaks near
  100,000 at t = 550. The run from the start falls twice as far at first: a median of 2,500 agents at t = 100,
  against the control's 4,900, and 2,168 in its smallest seed. It then catches the control at t = 300 and grows past
  it. *My reading* of why: a site's goods are scored divided by 1 + pollution, so a polluted rich site can score no
  better than a clean poor one, and agents settle land the control leaves empty. The runs don't record births or
  site choices, so this isn't tested.
- **One culture.** In the late run the minority follows the control until t = 500, then falls to 0.10 by t = 600, still
  falling. From the start it falls away from the control's from about t = 250 and is gone by t = 600 in every seed
  (10 of 20 at exactly zero, the largest 0.02); kills fall with it to none, since one culture has no one to fight.
  In the late run kills fall less, to 168 a period. The control keeps both cultures (0.36) and its war (254 kills a
  period).

### Why the minority loses

From the saved tables only (`seed<k>.csv`, `-combat.csv`, `-kills.csv`); no run was made for this.

- **Not more contact.** With pollution the tribes mix *less*: the share of neighbour pairs across tribes over
  t = 451–600 is 0.028 in the late run against 0.049 in the control, and tribe changes per agent are lower (52 against
  87 per 1,000 agents a period).
- **Mostly not deaths.** Over t = 451–600 the late run's minority shrinks 0.67% a period while the majority grows 0.25%.
  Kills, starvation and old age per head differ between the tribes by about 0.1% a period, a tenth of that gap. With
  pollution from the start deaths count for more: over t = 251–450 the minority is killed at 2.2 times the majority's
  rate per head (8.3 against 3.7 per 1,000): kills are 40% of its gap in growth, and kills and starvation together 46%.
- **One converging culture.** A tribe is only which side of 5½ an agent's 11 tags fall on, and in the late run and the
  control 5–11% of agents change tribe every period, so the label is fluid. What pollution changes is how fast the whole
  society's tags converge: the mean closeness of tags between friends reaches 0.980 at t = 600 in the late run against
  the control's 0.947, and 1.000 (identical tags) with pollution from the start. The minority disappears because nearly
  everyone ends up with nearly the same tags, on one side of the line.
- **Why faster.** *My reading*, not tested: agents move more under pollution (79–87% of them a period after t = 400,
  briefly 92% as diffusion starts, against 68–70% in the control), so each meets a changing set of neighbours and tags
  spread across the whole society instead of staying in regional pockets. A possible amplifier with pollution from the
  start: combat's loot isn't devalued by pollution while a site's goods are (`score` in julia/src/rules/welfare.jl), so
  where pollution is high, combat moves are chosen mostly by whom an agent can rob, and the chance of hostility rises
  with tag distance. A diagnostic run recording the tag-count distribution and tribe changes by direction would test
  both.

### How pollution could fall

Nothing in the model or the book removes pollution: rule P only adds (p.47), and rule D averages over neighbours on
the torus, so the total is conserved (`diffuse!` in julia/src/landscape.jl; the sum check in
test_landscape.jl's diffusion test). The book's only remedy is to stop making it: in IV-3 (pp.126–129) generation stops
at t = 150
and diffusion starts. Here that is `pollution_stop`, which the model and the Python original already have.

- **With `pollution_stop` only.** The total freezes, and with 100 diffusion passes a period the field flattens towards
  the world's mean. The mean stops rising but never falls. Flat pollution devalues every site by about the same
  factor, so rich land regains its lead over poor land, but the world never gets cleaner.
- **With a removal rule** (none in the book, so an xxl extension): the smallest is a decay of a fixed share δ of each
  site's pollution every period, applied after diffusion in `step!`. Then the mean falls as (1 − δ)^t once generation
  stops, and settles where making and decay balance while it doesn't. That rule now exists as `pollution_decay`
  ("Decay", below). Alternatives are decay only on empty sites, or absorption tied to sugar regrowth; both are further
  from anything in the book.

### What this doesn't show

- **Births and site choices.** The runs record neither, so why the poor land fills and why the minority converges
  away are readings, not measurements.
- **A fall in pollution.** Pollution never decays and never stops in these three runs, so the world's total only
  grows. The decay run below is the one where it doesn't.
- One map, 20 seeds, one setting of α, β and the diffusion period.

### Run time

Same machine, 5 workers: 63 min for the late run, 51 min for the control and 57 min for the run from the start. A first
try of the late run with 10 workers was stopped after 4 minutes, before any seed was done, because other work was
holding about 7 GB and free memory fell to 2 GB.

### Decay: `pollution_decay` and `VI-1-pollution-decay`

The user wants to see agents leave polluted land and come back as it decays
([docs/superpowers/specs/2026-11-11-pollution-decay-design.md](superpowers/specs/2026-11-11-pollution-decay-design.md)).
Nothing above removes pollution, so this adds a rule the book doesn't have.

- **The rule.** `pollution_decay` (δ, default 0) is a config field of the Julia port only, like `culture_rule`; the
  Python original has no such field. At the end of every period, after growback and after diffusion, every site keeps
  1 − δ of its pollution. It acts whether or not pollution is being made and whether or not diffusion runs that period,
  so after a `pollution_stop` the world gets cleaner. At 0 nothing is touched, so every existing run is byte-identical.
  It needs no scaling between worlds: the xl transform scales space (diffusion passes × 100), not time. `validate`
  accepts 0 ≤ δ < 1. The combat study's fingerprints don't change (they take the Python registry's config text); the
  extinction study's checkpoint headers list every Julia field, so they gained `pollution_decay=0.0`.
- **The rate.** The user asked for a fouled patch to be livable again about 50 periods after it is left, with "nearly
  all" of its pollution gone; taken as nine-tenths, that is δ = 0.045 (0.955^50 = 0.100; half gone in about 15
  periods). Agents make about 2.5 units a period each, so P ≈ 1 per cell a period at today's population; since a
  period's pollution is made before that period's decay, the world's mean should settle near P (1 − δ) ÷ δ ≈ 21
  within about 50 periods of the start, against 217 and rising at t = 600 without decay. With 100 diffusion passes a
  period, pollution mostly stays within about 25 cells of where it is made. These were estimates from the runs above.
  The study below bears out the mean (21.1 at t = 1000), but it takes about 350 periods to get there, not 50, because
  the population keeps growing from 61,000 to 100,000.
- **The experiment.** `VI-1-pollution-decay` is `VI-1-pollution` with the decay added and the run lengthened; nothing
  else changes. Pollution keeps being made while it decays (the user's choice), so the land settles into a balance;
  what the user expects to see is a rotation, agents fouling a patch, leaving it, and coming back once it recovers.

  | Setting (book config) | `VI-1-pollution` | `VI-1-pollution-decay` |
  |---|---|---|
  | `pollution` (α, β) | (1.0, 1.0) | (1.0, 1.0) |
  | `pollution_start` | 350 | 350 |
  | `pollution_stop` | none | none |
  | `pollution_decay` | 0 | 0.045 |
  | `diffusion_period`, `diffusion_start` | 1, 450 | 1, 450 |
  | steps | 600 | 1000 |

- **Running it.** `julia --project=julia julia/xxl_combat_study.jl --world today --exp VI-1-pollution-decay …`, or
  in the viewer. The 20-seed study below took 1 h 53 min with 5 workers.

### Decay results (2026-11-12)

**The short answer.** Decay works as designed: the world's mean pollution settles at 21, as estimated, against 217 and
rising at t = 600 without it. But it changes almost nothing about where agents live. They step back from rich land by
about 4% when pollution starts (5% without decay), are back above their old number before diffusion starts, and then
stay between about 47,000 and 49,000 for the rest of the run. The totals show no cycle of leaving and returning. The
minority culture is mostly lost, as without decay: it is under 1% of agents at t = 1000, though 8 of 20 seeds keep 5%
or more.

**The run.** Today's world, seeds 0–19, 1000 periods, 5 workers, with the user's go-ahead
(`results-julia-xxl/combat-today-VI-1-pollution-decay-s0-20-p1000/`). Every seed's main and combat tables for
t = 0–350 are byte-identical to its `VI-1-pollution` seed (20 of 20), so all differences come from decay. Every seed is
alive at t = 1000.

**Readings** (medians over seeds; "No decay" is `VI-1-pollution`, "Control" is `VI-1-assim-k4`, both run only to
t = 600, from "Results" above; counts on rich land in the no-decay run are population × share, since its pollution
tables predate the count columns):

| Reading | Decay | No decay | Control |
|---|---|---|---|
| World mean pollution, t = 450 / 600 / 1000 | 16.8 / 20.7 / 21.1 | 74 / 217 / – | 0 |
| Pollution on rich land / elsewhere, t = 450 / 1000 | 30.9 / 10.1, 30.0 / 16.8 | – | – |
| Where agents stand, t = 450 / 600 / 1000 | 1.68 / 1.27 / 1.25 | 1.59 / 1.15 / – | – |
| Lowest count on rich land after t = 350, as share of t = 350 ³ | 0.96 (0.93–0.98), t ≈ 375 | 0.95 (0.92–0.97), t ≈ 395 | – |
| Agents on rich land, t = 350 / 450 / 600 / 1000 | 43.6k / 46.6k / 47.7k / 48.7k | 43.6k / 43.9k / 46.2k / – | – |
| Agents off rich land, t = 600 / 1000 | 50.5k / 51.9k | 51.1k / – | – |
| Share on rich land, t = 600 / 1000 | 0.49 / 0.48 | 0.48 / – | – |
| Population, t = 600 / 1000 | 98,409 / 100,836 | 97,282 / – | 67,381 / – |
| Minority share, t = 500 / 600 / 1000 | 0.32 / 0.12 / 0.008 | 0.36 / 0.10 / – | 0.36 / 0.36 / – |
| Seeds with the minority ≥ 5%, t = 600 / 1000 | 14 / 8 of 20 | 13 of 20 | 19 of 20 |
| Kills per period, t = 600 / 1000 | 177 / 58 | 168 / – | 254 / – |
| Share of agents moving a period, t = 600 / 1000 | 0.80 / 0.80 | 0.82 / – | 0.69 / – |

³ Each seed's lowest count over the whole run after t = 350 (to t = 1000, or 600 without decay): the median, the
range over seeds in brackets, and the median period of the low.

- **Pollution settles.** The mean reaches 17 when diffusion starts and 21 by about t = 700, then stays within 20.9–21.2
  to the end. Rich land stays about 1.8 times as polluted as the rest (30 against 17), and agents stand on land 1.25
  times as polluted as the world's mean.
- **A slightly smaller, shorter retreat.** In each seed the count on rich land falls to 93–98% of its t = 350 number,
  lowest around t = 375; the median count is back above its t = 350 number from about t = 415, against about t = 450
  without decay, where the low is 92–97% around t = 395. Pollution also builds more slowly with decay (the world's mean
  is 9.9 at t = 375 against 17.1).
- **No cycle in the totals.** From t = 600 to 1000 the count on rich land in a typical seed stays between 46.7k and 48.9k
  (median of each seed's lowest and highest), and the share between 0.477 and 0.489. A rotation of agents fouling a
  patch, leaving it and coming back once it recovers could still be happening patch by patch: the readings are totals
  over all rich land, so they can't show it. The viewer can; a per-patch reading would measure it.
- **The same society.** At t = 600 the population, the split between rich and poor land, and the land-capacity
  reading are within a few percent of the no-decay run's, with a tenth of its pollution. So the growth on poor land
  doesn't need much pollution: *my reading* is that a site's goods are scored divided by 1 + pollution, so even at 30
  a rich site is devalued enough for clean poor sites to compete, and above that level more pollution changes little.
- **The minority is mostly lost.** It falls from about t = 450, about 50 periods earlier than without decay (0.32 at
  t = 500 against 0.36), and is 0.12 at t = 600 against the no-decay run's 0.10. It is about 1% by t = 800 and 0.008
  at t = 1000, with 8 of 20 seeds keeping 5% or more. Friends' tag closeness reaches 0.997, and kills fall from about 480 a period at t = 350 to 58. Agents
  move about as much as without decay (80% a period against the control's 69%). That is consistent with the untested
  reading in "Why the minority loses" above, that tags converge faster because agents keep moving; it also suggests
  that the amount of pollution, which decay cuts tenfold, matters less than its presence. The runs don't record what
  moves agents, so this too is a reading.

**What this doesn't show.** Whether agents rotate between patches (see above); how the no-decay run and the control
would compare after t = 600, since neither was run that far; and any other rate of decay.

## Viewer

A live browser view of one xxl VI-1 run, in today's world, stepped as the page asks for it:

```bat
julia --project=julia --threads=2,1 julia/xxl_viewer.jl [--port 8766]
```

It serves `http://127.0.0.1:8766/` (the Python viewer keeps 8765) until Ctrl+C. The server answers requests on an
interactive thread and a background task steps the run on a default one, so the command refuses, with a one-line
message and a non-zero exit, unless there is at least one default and at least one interactive thread
(`Threads.nthreads(:default) >= 1` and `Threads.nthreads(:interactive) >= 1`); `--threads=1,1` is enough. On this Julia
plain `--threads=2` already gives 2 default and 1 interactive threads, but `--threads=2,1` says so. `.claude/launch.json`
has the same command as `xxl-viewer`. It answers only requests addressed to `127.0.0.1:<port>` or `localhost:<port>`
(any other Host header is 403), and refuses a POST whose Origin header names any other page (403), so another website
open in the browser can neither start or stop a run nor read the viewer's frames.

- **What it shows.** The landscape with the agents coloured by tribe, culture, wealth, disease or credit (a menu
  switches between them); marks that each fill exactly one cell, black where an agent was killed and gold where one
  changed tribe; the charts of the run's series; and, hovering an agent, its readings (also under a mark, which hides
  the agent on its cell). Two menus pick the marks: "Marks from" this period (the default), the last 10 periods fading,
  or none; and "Show" kills and switches, kills only or switches only. The user chose these cell-size marks after the
  live check of 11-10, where crosses and rings several cells wide hid the agents. A cell with both a kill and a switch
  shows the kill. A cell can hold several events, and in the fading mode marks on one cell blend in order, oldest
  first; a line under the map then says how many events fall on how many cells.
- **Pollution runs.** The experiment menu includes `VI-1-pollution`, `VI-1-pollution-t0` and `VI-1-pollution-decay`
  (previous section). For
  those runs only, a "Ground shows" menu (resources, the default, or pollution) says what the empty cells show;
  it is independent of the agent colours and the marks. On pollution, each empty cell takes the colour of its pollution
  band: 0, below 1, 1–3, 3–10, 10–30, 30–100, 100–300, 300–1000, and 1000 or more (nine bands, spaced by powers of
  about three because without decay pollution grows without bound). The server works the bands out from the model
  and sends one per cell; the page only maps a band to a colour. Hovering a cell shows its band, and the legend lists
  the bands. Two charts appear only for these runs: "Pollution" (the world's mean against the mean where agents stand,
  so agents leaving fouled land shows as the second line falling below the first) and "On the richest land" (the share
  of agents on rich land, on an axis from 0 to 1, with a caption giving the cut and the share of cells it covers),
  then "Agents on rich land" (the counts on rich land and elsewhere, which show whether the share moves because agents
  leave or because the society grows elsewhere) and "Pollution on rich land and elsewhere" (the two means). Every chart
  marks the start of pollution and of diffusion with dotted lines ("pollution on", "diffusion on") when the experiment
  has them; with decay the first reads "pollution on, decays 4.5%", and the legend for the pollution ground states the
  rate. The dashed study-end line sits at the experiment's own steps: 600 or 1000 for the pollution experiments, 500
  for the others.
- **What you set.** The experiment (the VI-1 combat-study experiments), the raw seed, and the combat study's `h` and
  `k`. Start begins a run, and shows the model's own message if it refuses the settings (`h = 1` on `VI-1-assim`,
  say). The stepper runs at most 50 periods ahead of the period the page shows: the page reports the period on its
  map with every status request (each second, and at once whenever it shows another period), whether that frame came
  from the server or from the page's own cache. So a paused page keeps its frame, the status reads "waiting", and Play
  moves the model on again. A new run is drawn only with its own legend: the page asks for the legend by run id, and
  the server answers 409 for a run that is no longer current, so switching between a pollution experiment and another
  never mixes legends.
- **Faithfulness.** The viewer steps the same model the study does. Its series equal the combat study's CSVs for the
  same experiment, seed, `h` and `k` (`julia/test/test_xxl_viewer_run.jl`); its frame counts (agents, kills, tribe
  changes) equal the readings of the same period; for a pollution run its pollution series equal the study's
  `seed<k>-pollution.csv` (`julia/test/test_xxl_viewer_run.jl`, "pollution run matches the study") and each cell's band
  equals the model's (`julia/test/test_xxl_viewer_frame.jl`); the study's `seed<k>-pollution.csv` itself equals the
  model's readings (`julia/test/test_xxl_pollution_readings.jl`); and the encodings (colour modes, marks, legend) are
  fixed and tested (`julia/test/test_xxl_viewer_*.jl`, `julia/test/js/`).

## Stage 1: the scorecard and survival

The first rules (`XXL_V1`) nearly killed VI-1's society: on the baseline scorecard below, its 20,000 founders fell to
2–6% of their number before the population recovered, II-4 and IV-A3 kept only about 60% of xl's survivors, and
disease died out in every seed ("Results of the first rules" has the analysis behind the first two). The goal is now
a well-functioning simulation: the population rarely goes extinct, and sex, culture, trade, credit, disease and combat
each work (combat joined the goal in stage 8). The work goes in stages, each scored by the same scorecard: stage 1
survival, stage 2 extinction risk, stage 3 trade and credit, stage 4 disease. This section is stage 1's record.

**Outcome.** The defaults are now the first rules with three changes and a higher travel cost: the generated map
(rule 6), viable founder placement (rule 9), a free step of 1.5 (rule 10), and c = 0.2. On 20 seeds that were not
used to choose them (seeds 20–39) they pass 13 of the 15 checks, every survival check among them, against 7 of 15 for
the first rules. The two that still fail, mates in reach (X2) and loans voided by death (X8), failed in every setting
tried. Both have since become reported values with no threshold: X2 under stage 2's spec ("X2 stops being a target"),
X8 under the credit study's design (`docs/superpowers/specs/2026-10-31-xxl-credit-study-design.md`, "Part 1: retire
X8"). X1 and X3–X7, X9 and X10 are the baseline for stages 3 and 4, and X2 and X8 are read beside them. Past reports
aren't re-run, and their counts of checks passed stay as recorded, out of 15 or 14; 13 now apply. The scorecard rows in
the tables below keep their figures.

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
`n_fertile_with_mate` (a fertile agent of the other sex in mating reach, as `mate_contact` sets it; see X2 below),
`tag_flips_per_agent`,
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
| X2 Mates in reach | Sex | At VI-1's trough, the share of fertile agents with a mate in reach, mean over seeds | none, reported only |
| X3 Both cultures live | Culture | The share of VI-1 seeds where both tribes hold ≥ 5% at t = 200 | ≥ 0.8 |
| X4 Culture moves | Culture | The fewest tag flips per agent in any period of any VI-1 seed | > 0 |
| X5 Agents trade | Trade | VI-1's end share of agents who traded in the last 10 periods, mean over seeds | ≥ 0.5 |
| X6 Prices agree | Trade | VI-1's end price sd ÷ xl's, means over seeds | ≤ 1.5 |
| X7 Credit persists | Credit | The fewest loans outstanding in any period after t = 100 of any VI-1 seed | ≥ 1 |
| X8 Loans voided by a death | Credit | The share of VI-1's loans voided by a death (of those voided or repaid), mean over seeds | none, reported only |
| X9 Disease is endemic | Disease | The share of VI-1 seeds with a disease circulating at t = 500 | ≥ 0.9 |
| X10 Disease is bounded | Disease | VI-1's end share of agents sick, mean over seeds | 0.01–0.2 |

S4 and S5 compare with xl because an experiment without births has no extinction to avoid: its population can only
fall, and xl's free movement, as far as the agent sees, is the level reached when no agent dies of a model artifact.
Under the stage-1 defaults the two sides run on different landscapes (the defaults on the generated map, the xl
reference on the xl map), so S4 and S5 compare across maps there.
Only the S checks gate stage 1; the X checks are reported from the start so each later stage knows its baseline.
X2 had a threshold of 0.5 in stage 1 and has none from stage 2 on: the scorecard still reports its value and per-seed
detail, with "reported only" as its result, and it no longer counts among the checks passed. The counts of checks
passed in the tables below are out of 15; from stage 2 on 14 apply. The counts don't change, because X2 failed in
every setting scored. The past scorecards were not re-run.

X2 counts partners in mating reach, the reach `mate_contact` sets: VI-1 mates within vision (`mate_contact =
"vision"`), which under xxl is a round look, so X2 takes a fresh look from each fertile agent. The look draws its own
random numbers (the scorecard tracker's copy of the RNG), so scoring leaves the run unchanged. Until 2026-10-30 X2
counted only partners within the interaction radius, 1.5; the tables below say where a value is from that count.

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
and the generated map, with founder ages as named. The X checks failing are from the earlier X2 count (within the
interaction radius); re-scored with mating reach, X2 still reads far below the old 0.5 under the first rules and the
defaults (below). The "X checks failing" column lists X2 as it failed its old threshold.

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
| X2 Mates in reach | — | 0.108 | 0.160 | 0.163 |
| X3 Both cultures live | ≥ 0.8 | 1 | 1 | 1 |
| X4 Culture moves | > 0 | 0.012 | 0.167 | 0.187 |
| X5 Agents trade | ≥ 0.5 | 0.920 | 0.979 | 0.981 |
| X6 Prices agree | ≤ 1.5 | 1.297 | 1.223 | 1.202 |
| X7 Credit persists | ≥ 1 | 14 | 990 | 1,134 |
| X8 Loans voided by a death | — | 0.276 | 0.253 | 0.249 |
| X9 Disease is endemic | ≥ 0.9 | **0** | 0.95 | 0.95 |
| X10 Disease is bounded | 0.01–0.2 | **0** | 0.112 | 0.107 |
| Checks passed | | 7 | 13 | 13 |

The per-seed detail, on seeds 20–39: VI-1's lowest population is 3,956–8,476 (S2 0.198–0.424 of the founders), and
it ends at 47,990–71,020 against xl's 67,670–103,800. II-4 ends at 27,940–28,280 against xl's 23,760–24,000, and
IV-A3 at 7,231–7,412 against 3,621–3,825.

- **II-4 and IV-A3 now keep more agents than xl.** The checks ask for 90% of xl, and xl is a reference, not a
  ceiling. xl places founders at random, where viable placement starts every II-4 founder, and every IV-A3 founder
  it can, on land that feeds it. For IV-A3 the generated map counts too: it alone lifts S5 from 0.586 to 0.879, and
  dropping it in the trim takes S5 from 1.967 to 1.593. Placement and map are presumably the difference (not
  traced). The xl reference stays on the xl map, so these ratios compare across maps.
- **VI-1's trough is now 18–42% of the founders**, against 2–6% under the first rules, and its recovery is unchanged
  at about 68% of xl.

### The baseline for stages 2–4

Under the defaults, on seeds 20–39:
- **X2 is low: at the trough few fertile agents can see a mate.** At VI-1's trough 16.3% of fertile agents
  (12.3–19.3% per seed) have a fertile agent of the other sex in sight; under the first rules 10.8% (5.0–17.1%).
  Stage 1's changes raised it by half. The 50% it was once asked to reach is gone: X2 is reported only, with no
  threshold. Counted within the interaction radius, as X2 was until 2026-10-30, the share is 2.3% (0.011–0.026 in
  every setting tried). Births still keep up with deaths (X1 1.044). Stage 2 (extinction risk) reads X2 as a
  measure, not a target.
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

## Stage 2: the chance of extinction

**The bar is the user's:** a healthy society is one that doesn't go extinct, so the chance of extinction over 2,000
periods must be below 5%. The design is in
[docs/superpowers/specs/2026-10-30-xxl-extinction-risk-design.md](superpowers/specs/2026-10-30-xxl-extinction-risk-design.md).

**The test:** VI-1 under `XXL_DEFAULTS`, seeds 20–79, 2,000 periods each. A seed is extinct if its population reaches 0
at any period from 1 to 2,000. The test passes if the one-sided 95% exact (Clopper–Pearson) upper limit on the chance
of extinction is below 5%.

**The verdict: pass.** 0 of 60 seeds went extinct, which puts the upper limit at 4.87%. The report is
`results-julia-xxl/extinction-defaults-s20-60-p2000.md` (git-ignored); `julia/xxl_extinction.jl` runs the test.

| Across the 60 seeds | Lowest | Median | Highest |
|---|---|---|---|
| Lowest population in the run | 3,441 (seed 53) | 5,866 | 8,476 (seed 26) |
| Population at t = 2,000 | 51,151 (seed 78) | 72,323 | 85,317 (seed 66) |

- **The trough is the only close call.** Every seed reaches its lowest population at t = 62–78, and no seed comes
  back down to it later. The deepest, seed 53, falls to 17% of the 20,000 founders. At t = 500, 1,000, 1,500 and 2,000
  no seed is below 48,282.
- **No seed is in slow decline.** 0 of 60 fell by more than 10% from t = 1,001–1,500 to t = 1,501–2,000, the report's
  warning line. The closest is seed 78, down 9.1% (55,497 to 50,438); next is seed 38, down 6.9%. Over the last 200
  periods births reach deaths in 38 of 60 seeds, and the two counts differ by at most 2.3% in any seed.
- **X2 reads 0.16, and the society survives anyway.** On seeds 20–39 16.3% of fertile agents have a mate in reach at
  VI-1's trough, by the scorecard's count; seeds 40–79 weren't scored. X2 stays a reported value with no threshold.

**What the pass does not show.**
- It clears the bar with no room: one extinct seed among the 60 would have failed it.
- All 60 seeds share one generated map pair (rule 6). The 4.87% is for those maps; other maps weren't tried.
- The limit says nothing past 2,000 periods.
- Survival is the only thing it tests. The scorecard still fails X8, loans voided by death (0.249 against 0.2).

**Run time.** On the 24 threads of an i7-13700K with 31.8 GB, shared with other work, the run took 14 h 40 min by the
clock, from 14:40 to 05:20. It was stopped three times and resumed each time: for low memory at 16:39 and 00:32, and
at 17:17 by a false alarm, when the memory watcher's limit was set too tight. It ran with 10 workers, then 5 from
16:40, then 4 from 00:34. The report gives `--jobs 4` and 47,766 s of wall time, but the first is only the last
resume's setting and the second leaves out work lost in the stops. Each stop kept the finished seeds and lost those in
progress, 20 in all and roughly 13 CPU-hours; they reran in full, and none was chosen by its outcome. The finished
seeds took 2,337–5,535 s each, 228,304 s in all, depending on the load.

**Next:** stage 3, the economy, starting from X8.

## Stage 3: what X8 measures

X8 is the one scorecard check still failing under `XXL_DEFAULTS`: the share of VI-1's loans voided by a death, against a
limit of 0.2. That limit was my provisional pick in stage 1, not a measurement, and X8 had never been read under xl or
the book's world. So this step asks what X8 measures and whether credit works; it changes no rule. The design is in
[docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md](superpowers/specs/2026-10-31-xxl-x8-investigation-design.md).

**The short answer.** X8 mostly reads how long lenders live, so it's a poor guide to whether credit works: term 5 passes
X8 and lowers the trough, term 20 reads more than twice the limit and lifts it, and inheritance lowers X8 and lifts it.
The bigger finding is about credit itself. It lifts the trough by 18%, and by about t = 300 these 5 seeds can't detect any
difference it makes to births or population. They could only detect a difference of about 10%.

**The runs.** `julia/xxl_loan_trace.jl` follows every loan and, every 50 periods, a census of all agents. The main run is
`XXL_DEFAULTS`, VI-1, seeds 20–29, 2,000 periods. Its reports and the probes' are in `results-julia-xxl/loans-*.md`
(git-ignored). The run is the same run with the tracer on: all 10 CSVs are byte-identical to the extinction run's, and
the tracer's counts equal the scorecard's for all 10 seeds. Figures below are t = 1–500, the check's own window, then
t = 501–2,000 where it adds something.

**1. Who dies?** Mostly old lenders.

| | t = 1–500 | t = 501–2,000 |
|---|---|---|
| X8, mean over seeds | 0.2466 (seeds 0.2363–0.26) | 0.259 |
| Voids in which only the lender died | 0.8053 | 0.7529 |
| Voids in which a party was certain to die of old age by the due date | 0.6713 | 0.6463 |
| Dead lenders: old age, sugar, spice | 0.775, 0.093, 0.131 | 0.793, 0.053, 0.154 |
| Dead lenders aged 60 or more | 0.811 | 0.806 |
| Dead borrowers: old age, sugar, spice | 0.048, 0.006, 0.946 | 0.040, 0.006, 0.954 |
| Loans ended by the borrower's death, alone or with the lender's | 0.0480 | 0.0640 |

The typical dead lender is 70–74 and the typical dead borrower 20–24. Median time to a void is 4 periods for a lender and
2 for a borrower. Rollovers are 0.75% of loans started and about 1% of those reaching their due date, so a borrower who
lives can nearly always pay.

**2. Is a loan riskier than its parties' ages explain?** A little by age, not against similar agents.

- **Against age alone,** borrowers' voids run 1.10 times what mortality at those ages predicts, and 1.20 later; lenders'
  run 1.11, and 1.06 later. Old age is on the mark (borrowers 0.94, 0.92; lenders 1.02, 1.00). The borrowers' excess is
  spice (1.17, 1.26), which fits the design's other lead: a loan is in sugar, and a borrower can starve of spice.
- **Against similar agents,** borrowers die less, not more: 0.70 times the rate of could-borrow agents of the same age,
  and 0.60 for spice. So the excess over age comes from who borrows. Lenders are level at 0.96.
- **Starving of sugar is the exception on both sides.** It fired the report's lines, and it differs by side:
  - **Borrowers** read 3.18 (905 deaths against 285 expected), but that is 0.09% of borrowers per follow-up and 2.8% of
    their deaths, so the report's wording, "a real credit defect", overstates it. Their old-age ratio of 1.19 also shows
    how unlike the groups are, since a loan can't make anyone die of old age. And could-borrow agents can take a loan
    during the follow-up, so they aren't a clean baseline.
  - **Lenders** deserve more attention. They read 1.51 (3,370 against 2,234) with an old-age ratio of 1.015, so that
    discount doesn't apply. It is 0.38% of lenders and 1.7% of their deaths, but 9.3% of the voids where a lender died,
    since a dead lender voids all its loans, and by age the voids run 6.46 times the prediction (5.29 later). A
    lender past childbearing age may lend half its current wealth at each request, with no limit on requests. That could be
    the cause; I didn't test it.

**3. What does it cost, in sugar?** Voided loans are larger than average, but most of that cost falls on no living lender.

- 28.6% of principal is voided (29.1% later), against 24.7% of loans. Of that, 78% (74%) is where only the lender died.
  There, no living lender loses anything, because without inheritance the claim dies with them. The borrower keeps 0.96
  of the principal, as the book intends (p.133).
- Principal lost to a borrower's death is 6.3% of all principal (7.5% later).
- Lenders get back 1.445 per unit lent (1.433 later), against 2.0 due on a loan that runs its term.

**4. Does credit do its job?** In the trough, yes. After that the runs can't show that it does.

- **It reaches the right people.** Every loan's borrower is of childbearing age when it starts, and 53% of loans come from
  lenders past it. 52% of loans have a borrower who has a child during the term.
- **Comparing individuals flatters it.** Agents who took a loan had a child 3.12 times as often as could-borrow agents
  who didn't (3.60 later).
- **Turning credit off shows little else.** With credit off, seeds 20–24 against the same seeds with credit on, as means
  of the per-seed ratios:

  | With credit off | Ratio to credit on | By seed | Below credit on in |
  |---|---|---|---|
  | Births, t ≤ 100 | 0.749 | 0.688–0.801 | 5 of 5 |
  | Trough | 0.848 (5,116 against 6,011) | 0.801–0.884 | 5 of 5 |
  | Births, t = 101–300 | 0.956 | 0.867–1.023 | 3 of 5 |
  | Births, t = 301–500 | 1.019 | 0.875–1.113 | 2 of 5 |
  | Births, all of t ≤ 500 | 0.982 | 0.867–1.058 | 2 of 5 |
  | Population at t = 500 | 0.989 | 0.879–1.082 | 2 of 5 |

  That is about 726,000 loans per seed for 6,700 more births. The difference has a paired 95% interval of about 10% either
  way, so these seeds can't tell it from nothing, and they can't resolve an effect of 5% either.
- **The 3.12 doesn't carry to society.** These checks weren't planned; I added them after seeing the no-credit result.
  They compare credit on with credit off, standardized by window and age band, and none is randomized:

  | Children, credit on against credit off | Ratio | Children against expected |
  |---|---|---|
  | All agents | 0.979 | 613,413 against 626,449 |
  | Took a loan, against could-borrow agents with credit off | 1.30 | 52,705 against 40,530 |
  | Could borrow and took none, against the same | 0.38 | 6,217 against 16,382 |
  | Lending, against could-lend agents with credit off | 0.82 | 94,043 against 114,248 |

  So those who take a loan do better, those who don't do worse, and lenders have fewer children. Selection and displacement
  can't be separated here, but society's total barely moves.
- **Why the effect fades is open.** I can point to three things, and no run tested any of them.
  - **The loan is small.** To be creditworthy, a borrower's present income over the term must cover everything due, and on
    `L10,10` the due amount is twice the principal. So a new loan is at most 5 periods of present income. The sampled loans
    show that: never above 5.00, median 2.00 (at term 5, never above 3.33; at term 20, never above 6.67). The borrower might
    have saved the same sugar in that time, though a median loan also costs 2 more to repay than saving would. Income here
    is one period's reading, and the rule is our reading of p.132.
  - **Births follow deaths once the population flattens.** At t = 401–500 births and deaths per seed are 95,192 and 91,233
    with credit, 94,773 and 93,320 without. Any boost confined to the trough would fade this way, whatever the loan's size.
  - **The trough gain may not be about saving time at all.** 36% of loans ended in t ≤ 100 end by the lender's death, with
    the borrower keeping 0.95 of the principal. That moves wealth from the dying to the young, as inheritance does, and
    inheritance has the largest lift in early births (1.347).

**The probes.** Seeds 20–24, 500 periods, one change at a time. Each is a measurement, not a proposal. Ratios are to the
defaults on the same seeds, as means of the per-seed ratios. The repaid, lender-only and doomed figures for the defaults
are from the 10-seed report.

| Run | X8 | Repaid, of ended | Lender-only, of voids | Doomed, of voids | Births | Births, t ≤ 100 | Trough | Population at t = 500 |
|---|---|---|---|---|---|---|---|---|
| Defaults | 0.2444 | 0.7535 | 0.8053 | 0.6713 | 338,410 | 13,074 | 6,011 | 61,181 |
| Term 5 | 0.1506 | 0.8494 | 0.772 | 0.5812 | 0.948 | 0.878 | 0.927 | 0.956 |
| Term 20 | 0.5284 | 0.4726 | 0.8438 | 0.7705 | 0.994 | 1.169 | 1.095 | 0.989 |
| Inheritance | 0.0825 | 0.918 | 0.6035 | 0.5262 | 1.232 | 1.347 | 1.144 | 1.221 |
| No credit | — | — | — | — | 0.982 | 0.749 | 0.848 | 0.989 |

- **Term.** X8 follows the design's crude mortality estimate, 1 − (1 − h)^(2d) with h = 0.0155: 0.145, 0.268 and 0.465
  for terms 5, 10 and 20, against 0.151, 0.244 and 0.528 read. Term 5 passes X8, and the trough is lower in all 5 seeds;
  term 20 reads more than twice the limit, and the trough is higher in all 5, though births and final population stay
  level. Getting under 0.2 this way is the failure the design warned of. Changing the term also changes the amount due
  (1.5, 2 and 3 times the principal) and who is creditworthy, so it changes who borrows, not only how long they are exposed.
- **End-of-run effect.** X8 counts voids from a run's last d periods but not those loans' repayments, which come later.
  Among the sampled loans, keeping only those started at least d + 1 periods before the end lowers X8 by 0.001 at term 5,
  0.004 at term 10 and 0.009 at term 20. So it doesn't change any of this.
- **Inheritance,** the book's own answer to a lender's death, takes X8 to 0.08, with more births and people. But it also
  passes on wealth, so that probe changes more than loans: the Gini at t = 500 is 0.387 against 0.241. Its figures are the
  tracer's, since the scorecard's `loans_voided` miscounts under inheritance.

**The reference worlds.** Neither reaches 0.2, though past the trough neither is far above it. xl is near the defaults.
The book's mean of 0.38 comes from seeds that went extinct: 11 of its 20 seeds died out at t = 117–201, having made fewer
than 70 loans each, and read 0.38–0.65. By stage 2's bar the book's world isn't healthy, so its reading says little about
a healthy X8. Pooling all its loans gives 0.241.

| World | Seeds | X8, mean over seeds | X8, pooled, 1–500 | X8, pooled, 101–500 | Ended by the borrower's death | Lenders get per unit lent | Lender-only, of voids | Doomed, of voids |
|---|---|---|---|---|---|---|---|---|
| xxl defaults | 10 | 0.2466 | 0.2465 | 0.2437 | 0.0480 | 1.445 | 0.8053 | 0.6713 |
| xl | 5 | 0.2326 | 0.2326 | 0.2303 | 0.0417 | 1.483 | 0.8206 | 0.7499 |
| Book, 50 × 50 | 20 | 0.3821 | 0.241 | 0.235 | 0.0426 | 1.456 | 0.8235 | 0.7701 |

So 0.2 didn't describe the reference worlds either, and in all three X8 is about the same once pooled.

**My guess, written before measuring, held in the main.** I guessed that X8 is mostly a reading of how long agents live,
and that most voids come from old lenders. Both held, but age alone doesn't explain everything: borrowers' voids run
10–20% over age, from spice, and lenders starve of sugar more than I expected. The guess also missed the larger point,
since I didn't expect credit's effect to be so hard to find after the trough.

**The reading table, set before the long runs.**

| Row | t = 1–500 | t = 501–2,000 |
|---|---|---|
| Age ratio within 0.9–1.1 on both sides | No: 1.102, 1.114 | No: 1.20, 1.055 |
| Lender-only voids over half, or doomed over a quarter | **Fired:** 0.8053, 0.6713 | **Fired:** 0.7529, 0.6463 |
| Borrowers' matched ratio over 1.1, sugar or spice | **Fired on sugar:** 3.18; spice 0.60 | **Fired on sugar:** 3.36; spice 0.62 |
| Lenders' matched ratio over 1.1, sugar or spice | **Fired on sugar:** 1.51; spice 0.54 | **Fired on sugar:** 1.51; spice 0.57 |
| Took a loan against took none, a child, at most 1.1 | No: 3.12 | No: 3.60 |
| With credit off, births and end population within 5% | **Fired:** 0.980, 0.986 | No run past t = 500 |
| Age ratio over 1.1 with matched ratio within 0.9–1.1 | No: matched 0.70 | No: matched 0.70 |

The last-but-one row is the one the design called the bigger finding, and it fired as written: 0.980 and 0.986 are the
report's ratios of means, where the table above gives means of ratios. But 5 seeds can't resolve a 5% line, so read it as
no effect these seeds could detect, not as no effect. The table's rows changed once before any long run, after a
reviewer saw up to 260 periods of seed 20: the child comparison and the age ratio were redefined and a row for lenders
was added, because the first two as written couldn't work. The lines themselves, 0.9–1.1, 1.1 and 5%, didn't move. No
reading changed after the gate run or the main run.

**What this doesn't show.**
- All runs share one generated map pair, as in stage 2.
- The matched and credit-on-against-off group comparisons aren't randomized, so they are evidence, not proof.
- The no-credit probe has 5 seeds and stops at t = 500, so credit's effect at 2,000 periods and on the chance of extinction
  is unmeasured. The population is still growing at t = 500. Its seeds stay paired through the trough, where the result is
  clear, and not by t = 500.
- The probes say nothing about combinations, such as inheritance without credit.
- The term probes change who borrows, so they aren't a clean test of exposure.

**Run time.** Same machine, shared with other work, including a program holding about 12 GB. The main run took 4 h 11 min
by the clock, 14:21 to 18:32, with 4 workers rather than the planned 5 for lack of free memory, and no stops; seeds took
3,930–5,946 s. The probes ran from 18:34 to 20:56, 2 h 22 min, also with 4 workers and no stops: term 5 1,655 s, term 20
2,040 s, inheritance 2,111 s, no credit 1,671 s, xl 795 s and the book 28 s.

**My recommendation, not a decision.**
1. **Stop treating X8 as pass or fail, without setting a new limit yet.** Keep it as a reported value, like X2. I'm not
   proposing 0.25: X8 reads about the same in all three worlds, but that says what it measures, not that any value of it is
   healthy. The simple replacements have problems of their own. The share of loans ended by the borrower's death rises with
   the term (0.034, 0.048, 0.082) and over time (0.064 later). What lenders get back per unit lent mostly reflects lenders'
   own deaths; among loans whose lender lived, it is about 1.85 in the defaults and in xl, from the sampled loans, and it
   rises with the term as the amount due does. The direct test of credit is what it did here: the trough and births with
   credit on against off.
2. **Don't shorten the term.** It passes X8 and lowers the trough.
3. **Make credit's job the real stage 3 question.** It helps in the trough, the one close call in stage 2, so it shouldn't
   go. A new spec should first run credit off for 2,000 periods, with enough seeds to resolve 5% and to read the chance of
   extinction, and then look at why the effect fades.
4. **Look at how much lenders may lend,** as part of that spec. Lenders' starving is a small share of their deaths but
   voids many loans, and the rule has no limit per period.
5. **Test inheritance on its own, later.** It looks strong, but wealth concentrates, and it would need its own extinction
   test before anyone relied on it.

**What to change is the user's decision,** under a new spec. Nothing here changes X8 or the rules.

## Stage 3: what credit adds

The user read the findings above and chose to retire X8 and study credit. X8 is now reported only, so the scorecard reads
13 of 13 under the defaults. That says X8 no longer counts. It doesn't say credit works: the one credit check left, X7, only
tests that loans exist. This step changes no rule in `XXL_DEFAULTS`. The design is in
[docs/superpowers/specs/2026-10-31-xxl-credit-study-design.md](superpowers/specs/2026-10-31-xxl-credit-study-design.md).

**The short answer.** Without credit the society passes the user's bar on these maps: 0 of 60 seeds went extinct in 2,000
periods. For population, credit acts like a head start. It lifts the trough by 15% and early births by 28%, and by
t = 1,501–2,000 it changes population by no more than 5%. But other things last: with credit on there is more inequality,
far more trade and about twice the sickness, and without it a disease is more likely to die out, enough to fail X9. Those
readings weren't planned, and I didn't test why. Repayable loans keep about 0.45 of the lift, and these runs can't say how
much of the rest is dying lenders' sugar. Bigger loans about double the lift and bring many more rollovers, and more
starving in place of other deaths. A limit per period shows no effect in the trough, but seems barely to have bound.
Inheritance moves later population far more than anything else here, and it concentrates wealth.

**Read with the next section,** which came after this. With no disease, credit's gain in population lasts, so "a head start" holds only for population in the world with disease, where more disease roughly offsets it. And the lasting mark on wealth and inequality is mostly credit's own, not left by the trough.

**The main run.** `XXL_DEFAULTS` with credit off, VI-1, seeds 20–79, 2,000 periods, paired with stage 2's credit-on run on
the same seeds. Reports are in `results-julia-xxl/` (git-ignored): `extinction-nocredit-s20-60-p2000.md` and
`credit-compare-main.md`. With credit off the verdict is **PASS, 0 of 60 extinct, limit 4.87%**, and no seed was falling at
the end. The closest call was seed 53, which fell to 2,838 from 20,000 founders at t = 83. Its lowest with credit on was
3,441, the lowest of that run too. Both runs read 0 of 60, so this test can't compare their risk, but credit off comes
closer to the edge: 12 seeds under 4,000 against 4, and 1 under 3,000 against none.

Credit off against credit on, ratios of means over the 60 seeds, each with a 95% bootstrap interval over seed pairs:

| Window | Population | Births | Births per head | Interval against 0.95–1.05, population |
|---|---|---|---|---|
| Trough | 0.8675 [0.8591, 0.8756] (5,020 against 5,787) | | | below |
| t = 1–100 | 0.9336 [0.9297, 0.9376] | 0.7813 [0.7687, 0.7938] | 0.8353 [0.8245, 0.8457] | below |
| t = 101–200 | 0.8838 [0.8684, 0.9000] | 0.9147 [0.8944, 0.9359] | 1.036 [1.026, 1.046] | below |
| t = 201–300 | 0.9622 [0.9374, 0.9889] | 0.9828 [0.9549, 1.012] | 1.020 [1.010, 1.029] | straddles 0.95 |
| t = 301–500 | 0.9925 [0.9703, 1.016] | 1.002 [0.9754, 1.030] | 1.011 [1.004, 1.017] | inside |
| t = 501–1,000 | 0.9884 [0.9626, 1.015] | 0.9792 [0.9469, 1.013] | 0.9911 [0.9830, 0.9993] | inside |
| t = 1,001–1,500 | 0.9979 [0.9692, 1.027] | 0.9886 [0.9522, 1.026] | 0.9913 [0.9821, 1.001] | inside |
| t = 1,501–2,000 | 1.011 [0.9813, 1.042] | 1.013 [0.9759, 1.051] | 1.002 [0.9936, 1.011] | inside |

- **The trough** is lower without credit in all 60 seeds (0.79–0.93), and births at t ≤ 100 are too (9,696 against 12,409).
- **The head start:** with credit off, population runs 11.4 periods behind at t = 100 (4–21 by seed), 9.4 at t = 150 (−5–18)
  and 6.8 at t = 200 (−78–33). Past that the curve is too flat for this reading to mean much. For a while after the trough
  births per head run a little higher without credit, 3.6% at t = 101–200 and 1.1% by t = 301–500.
- **The end:** at t = 1,501–2,000 the reading is that credit lowers population by 1.1%, and the interval allows it to raise
  population by up to about 1.9% or lower it by up to about 4.0%. That rules out a lasting effect on population above 5%. It
  doesn't show there is none.
- **Births and deaths late on** don't quite settle the 5% line. Births at t = 501–1,000 reach 0.9469, under 0.95, and births
  at t = 1,501–2,000 reach 1.051, over 1.05. Deaths do the same, at 0.9484 and 1.051.
- **These aren't the earlier figures.** The section above gives 0.749 and 0.848 for 5 seeds, as means of per-seed ratios, and
  says credit lifts the trough by 18%. As ratios of means those 5 seeds read 0.7523 and 0.8511. Sixty seeds read the early
  effect a little smaller, so 15% (1 / 0.8675) replaces 18%.

**Did the seeds stay paired?** Partly. The correlation between a seed's credit-on and credit-off mean population is 0.99 at
t = 1–100, 0.81 at t = 101–200, 0.59 at t = 301–500, and 0.44 at t = 1,501–2,000. The design feared ±4.7% if pairing was
lost. The late interval came out about ±3%, so 60 seeds did settle the 5% line, for the population's ratio of means.

**What does last.** None of this was in the design's reading table. The reviewer of this section found it by looking across
about 50 CSV columns after the fact, and I recomputed it, so treat these as leads with strong numbers. Credit off against
credit on, t = 1,501–2,000, 60 seeds:

| | Credit on | Credit off | Off against on | Off below on, seeds |
|---|---|---|---|---|
| Gini | 0.239 | 0.213 | 0.8895 [0.879, 0.900] | 60 |
| Mean sugar | 25.0 | 27.9 | 1.113 [1.097, 1.130] | 2 |
| Trades per period | 101,345 | 56,964 | 0.562 [0.485, 0.644] | 56 |
| Mean price | 1.386 | 1.149 | 0.829 [0.788, 0.870] | 49 |
| Share of agents sick | 0.113 | 0.052 | 0.458 [0.356, 0.567] | 50 |
| Diseases circulating | 3.32 | 1.84 | 0.555 [0.462, 0.653] | 44 |

- **These all lie wholly outside 0.95–1.05.** Each is already well off 1 at t = 101–200, except the Gini at 0.96, which reaches
  0.90 by t = 301–500, and they hold through every later window.
- **Without credit, these seeds would fail X9.** A disease circulates at t = 500 in 57 of 60 seeds with credit, 0.95, and in
  48 of 60 without, 0.80, against X9's 0.9. In the pairs, 10 seeds have one only with credit and 1 only without.
- **The mark looks like it's left by the trough.** With credit on, a seed's diseases at t = 101–200 correlate 0.998 with its
  diseases at t = 1,501–2,000. So my lead, which I didn't test, is that a shallower trough lets more diseases survive, and they
  stay. (Tested in the next section: a seed's trough doesn't predict it, but neither does any other measure, so that doesn't separate them. The gap opens after the trough.)
- **The level population may be two effects cancelling.** (Tested in the next section: they roughly offset, on average.) Late on, population within a run is mostly disease: its correlation
  with the share sick is −0.98 with credit and −0.90 without. Taking each run's fit on the share sick out of the population
  takes the pairs' correlation from 0.44 to 0.03. A fit over both runs reads about 5,300 more people with credit at the same
  share sick, about 7.6%, and about 6,100 fewer from credit's extra sickness. Grouped by diseases circulating at t = 2,000,
  population is higher with credit at every count that both runs have, from 83,621 against 76,013 at no diseases to 59,324
  against 58,211 at five. Credit also widens the spread between seeds, 13.0% of the mean against 8.4%. The share sick is itself
  a result of the change, so none of this is causal, and I wouldn't lean on it without testing it.

**The probes.** Seeds 20–29 to about t = 500, and 20–39 for the claims probe. One change at a time, each a measurement and
not a proposal. Reports: `credit-compare-study.md` and `credit-compare-inherit2x2.md`. None went extinct. Each probe's
ratios are against credit on over its own seeds. Lift kept is (probe − off) ÷ (on − off): 1 keeps all of credit's lift, 0
keeps none.

| Probe | Seeds | Trough | Births, t ≤ 100 | Population, t = 301–500 | Lift kept, trough |
|---|---|---|---|---|---|
| Inheritance, credit on | 10 | 1.150 [1.137, 1.165] | 1.372 [1.346, 1.400] | 1.342 [1.220, 1.465] | 2.195 [1.984, 2.446] |
| Inheritance, credit off | 10 | 1.040 [1.020, 1.057] | 1.137 [1.103, 1.168] | 1.407 [1.266, 1.557] | 1.316 [1.138, 1.538] |
| Claims outlive the lender | 20 | 0.9297 [0.9123, 0.9466] | 0.8753 [0.8458, 0.9035] | 1.044 [0.9925, 1.104] | 0.4465 [0.3349, 0.565] |
| Bigger loans | 10 | 1.137 [1.121, 1.155] | 1.262 [1.222, 1.300] | 1.066 [1.002, 1.125] | 2.092 [1.888, 2.309] |
| Lender limit | 10 | 1.007 [0.9981, 1.016] | 1.016 [0.9946, 1.035] | 0.973 [0.9126, 1.028] | 1.059 [0.9856, 1.136] |

- **Where the lift comes from: repayable loans keep some of it, and the rest can't be split.** With a dead lender's loans
  standing, the trough keeps 0.45 of credit's lift, [0.33, 0.57], and births at t ≤ 100 keep 0.41, [0.28, 0.54]. Both straddle
  0.5, so these seeds couldn't settle the row's question. The probe's confound decides what else can be said: the repayment
  leaves the world, which the book's rules never do, and borrowers end poorer than under either the book's rule or
  inheritance. Total sugar at t = 70 reads 232,171 against 250,887, 7.5% lower. So it tests where the lift comes from, and
  isn't a sensible rule. Excluding 0 means loans do some of the work even with that drain, though a loan from a lender who
  later dies still hands the young that lender's sugar for part of its term. Excluding 1 doesn't show the gift matters, since
  the 0.55 lost can't be split between the lost gift and the drain. Its later population, 1.044 at t = 301–500, doesn't show
  the drain is harmless: that run has far less disease (share sick 0.055 against 0.109, and disease at t = 500 in 13 of 20
  seeds against 19). Its CSV's lender columns also still count dead lenders.
- **Credit still lifts the trough with inheritance on, but that doesn't separate the loans from the gift.** There a dead
  lender's claims pass to its living children if it has any, and otherwise the loan is void. Inheritance passes on wealth, not
  only loans, so this is another world, with richer agents. Credit off against on is 0.9041 for the trough, [0.8811, 0.9234],
  and 0.8289 for births at t ≤ 100, [0.7967, 0.8539], against 0.874 and 0.788 on these same 10 seeds without inheritance. In
  absolute terms the trough lift is 685 against 780, and the births lift 3,144 against 2,841. Over t = 1–500 inheritance removes
  about 80% of what borrowers keep when a lender dies (67,880 per seed against 348,980, on seeds 20–24), but only about a third
  by t = 100 (9,654 against 15,160), which is when this lift is measured. From t = 201 no window can tell credit on from off,
  and with 10 seeds those intervals are wide, up to 13.6% at t = 301–500.
- **Inheritance alone does more for the trough than credit alone,** by 4.0%, [2.0%, 5.7%], and far more after that:
  population at t = 301–500 runs 41% above credit on, [27%, 56%], and at t = 500 it's 90,251 against 61,166. That is well
  above the 71,095 these seeds reach with credit on at t = 1,501–2,000. Births rise 51% and deaths 46% at t = 301–500, so deaths
  per head rise about 3.6%. In the trough it isn't ahead of everything: inheritance with credit is about level with bigger
  loans (7,143 against 7,063), and inheritance alone is below them. Two things weigh on the other side. The Gini at t = 500 is
  0.371 alone and 0.386 with credit, against 0.239. And the share sick at t = 301–500 is 0.178 alone and 0.222 with credit,
  against 0.106, on the far side of X10's ceiling of 0.2 with credit, if that lasted to the end. These runs stop at t = 500, so
  they say nothing about where it settles or about extinction, and I didn't test why it does this.
- **Bigger loans lift the trough a further 13.7%, so the income limit does hold credit back there.** Its costs are many more
  rollovers and more starving, not more deaths overall. "Bigger" undersells the change: there are 2.05 times the loans, 1.5
  times the mean size and 3.06 times the principal. Figures are seeds 20–29 at t = 1–500 against the same seeds' loan trace,
  with no intervals:

  | | Defaults | Bigger loans |
  |---|---|---|
  | Loans started | 7,284,839 | 14,912,805 |
  | Rollovers, of loans started | 0.75% | 7.2% |
  | Repaid, of ended | 0.7535 | 0.6819 |
  | Dead borrowers starving of sugar | 0.64% | 6.2% |
  | Borrowers' sugar deaths, census (matched ratio) | 905 (3.18) | 11,460 (2.91) |
  | Lenders' sugar deaths, census (matched ratio) | 3,370 (1.51) | 15,580 (1.43) |
  | All agents: sugar deaths per agent, census | 0.0026 | 0.0074 |
  | All agents: all deaths per agent, census | 0.1646 | 0.1635 |
  | Gini at t = 500 | 0.239 | 0.285 |
  | Share of loans voided by a death (X8) | 0.2466 | 0.3188 |

  Counts per borrower aren't like for like, since borrowers go from about a quarter of the census to over a third and now
  include agents with lower incomes, so the table compares all agents. Deaths per head by window are level, 0.95, 1.04, 0.99 and
  1.00, so starving replaces other deaths and population runs higher. Population at t = 301–500 reads 1.066, [1.002, 1.125], above
  1 and straddling 1.05. The run stops at t = 511, so it can't speak to t = 1,501–2,000.
- **The lender limit shows no gain or cost in the trough, and it doesn't test what I meant it to.** The trough interval rules out
  a cost above 0.2% and a gain above 1.6%. Later population can't be settled: at t = 301–500, [0.9126, 1.028] allows a cost of up
  to 8.7%. The lenders' matched sugar ratio is 1.49 (3,582 against 2,400), against 1.51 (3,370 against 2,234), so the row doesn't
  fire. But the cap seems barely to have bound: total principal lent didn't fall (about 1.006 times the defaults), though loans
  started did (0.961). A lender can also still give half its wealth every period. And the matched ratio is a blunt measure here,
  since it hardly moved under bigger loans, with 3.06 times the principal. One reading did move a little: at t ≤ 100, 0.195 of
  dead lenders' voids came from a lender starving of sugar, against 0.209. So my lead in the section above, that the lack of a
  limit starves lenders, is untested, not shown wrong. The limit also changes the first lender a borrower meets, and so who
  lends.

**My guess, written before measuring.**

| Guess | Result |
|---|---|
| 0 of 60 extinct with credit off | Held |
| Population at t = 1,501–2,000 within 5% | Held: [0.9813, 1.042] |
| A head start | Held for population: all 60 seeds lower in the trough, about 11 periods behind at t = 100, and within 5% by the end. Missed that other things last |
| At least half the trough's lift comes from dying lenders' sugar | Not shown. The 0.55 lost fits, but the interval allows 0.43–0.67, and the drain can't be separated from the gift |
| Bigger loans lift the trough further | Held: 1.137 |
| Bigger loans don't change later population | Not tested: the probe stops at t = 511. What exists leans against it: t = 301–500 reads 1.066, [1.002, 1.125] |

The guess missed the two largest results. I didn't expect credit's trough to leave a lasting mark on disease, trade and wealth,
or inheritance to move population at t = 301–500 by so much more than credit does.

**The reading table, set before the runs.** A result can fall under more than one row. A row that fires is a reading, not a
finding by itself.

| Row | Result |
|---|---|
| Credit off: limit under 5% | **Fired:** 4.87%. Survival doesn't depend on credit, by the user's bar |
| Credit off: limit at or over 5% | No |
| Population, t = 1,501–2,000, inside 0.95–1.05 | **Fired:** [0.9813, 1.042]. No lasting effect on the society's size above 5%; this row doesn't speak to the rest |
| That interval wholly outside 0.95–1.05 | No |
| That interval straddles 0.95 or 1.05 | No |
| Claims, lift kept in the trough, wholly under 0.5 | No: [0.3349, 0.565] |
| Claims, wholly over 0.5 | No |
| Claims, straddles 0.5 | **Fired.** Couldn't say which matters more. The interval excludes 0 and 1, but excluding 1 may only reflect the drain |
| Inheritance, credit off, trough against credit on, wholly above 1 | **Fired:** 1.040, [1.020, 1.057]. Inheritance alone does more than credit for the trough |
| That interval straddles 1 | No |
| That interval wholly below 1 | No |
| Bigger loans, trough wholly above 1 | **Fired:** 1.137, [1.121, 1.155]. The income limit holds credit back in the trough |
| Bigger loans, trough straddles 1 | No |
| Bigger loans, trough wholly below 1 | No |
| Lender limit: matched ratio at or under 1.1, and trough doesn't fall wholly below 1 | No: the ratio is 1.49, though the trough doesn't fall |
| Lender limit: otherwise | **Fired.** It doesn't help by the row's measure; no cost detected in the trough |

No reading changed after the runs. "What does last" sits outside this table and was found afterwards. Windows that straddle a
line other than these rows' are in the tables, and read as "the seeds couldn't settle it".

**What this doesn't show.**
- All runs share one generated map pair, as in stage 2. The 4.87% is for those maps.
- The extinction test reads 0 of 60 on both sides, so it can't show that credit leaves the risk unchanged.
- The probes have 10 or 20 seeds and stop at about t = 500, so none of them has an extinction verdict or a late reading. A
  ratio over those seeds is against the same seeds of the main runs, whose own effect reads a little smaller than over all
  60 (trough 0.874 at 10 seeds, 0.873 at 20, 0.867 at 60).
- Who borrows or lends isn't assigned at random, so group comparisons within a run are evidence and not proof. That covers this
  section's matched ratios and the census figures in the bigger-loans table, and the section above's readings, including the
  5-seed credit-off comparison of who has children. The comparisons with credit on and off are direct changes on the same seeds,
  on one map pair.
- "What does last" was found by searching after the runs, and why it happens wasn't tested.

**Run time.** Same machine, shared with other work. The main run took 44,399 s by its own count, 12 h 20 min, with 5 workers
and no stops; its log reads 00:04 to 11:24 because the clock went back an hour that night. Its seeds took 2,770–4,421 s. The
probes ran from 11:25 to 14:18, 2 h 53 min, with 4 workers and no stops: 33, 28, 42, 39 and 31 minutes in the order of the
table. The main run came in at the low end of the design's 12–17 hours, and the probes under its 5 hours or so.

**My recommendation, not a decision.**
1. **Keep credit as it is.** It lifts the one close call, and the society passes the user's bar without it. Whether that counts as
   working as intended is the user's question, and I'd say yes for now: it does something real in the period that matters most,
   and the one change here that makes credit itself do more, bigger loans, has real costs.
2. **Before stage 4, find out why the trough leaves a lasting mark.** It costs no new runs at first, since the CSVs can test how
   trough depth and disease survival go together. It matters because X9 depends on it, and stage 4's disease work would start
   from a baseline that credit is partly holding up.
3. **Don't adopt the lender limit, and don't rely on this probe to clear lending.** It seems barely to have bound. A real test
   of whether lending starves lenders would need a tighter cap, over several periods.
4. **Don't adopt bigger loans without their own spec.** The lift is real, and so are 9.6 times the rollovers' share and about 2.9
   times the starving per agent. They'd need an extinction test and a run to 2,000 periods.
5. **If a rule gets its own spec next, make it inheritance.** It's the book's own rule and it moves later population far more
   than anything else here. It needs a 2,000-period extinction run, and a decision on whether a Gini of 0.37–0.39 and that much
   more sickness are acceptable.
6. **Don't add a new credit check yet.** The direct test is the trough with credit on against off, which takes a paired run. It's
   worth writing down once the question above is settled, not before.

**What to change is the user's decision,** under a new spec. Nothing here changes the rules.

## Stage 3: why credit's mark lasts

The user chose to trace the lasting mark, recommendation 2 above. This step changes no rule and no code under `julia/`. I had
said it might need no new runs. It needed two sets, and that was my call: a trace of every disease, and credit on and off with no
disease. No reading table was set before them, so apart from the two leads named below, all of this is reading after the fact.

**The short answer.** Credit has two lasting results, and as far as I can see they start from one early lift: its effects read the
same with disease and without up to about t = 60.
- **At the same disease, credit means more people, less sugar each and more inequality.** With no disease at all, credit off has
  11.0% fewer people, [10.0%, 12.0%], in all 20 seeds, about the same total sugar, more sugar per head and a lower Gini.
- **More diseases last.** Long diseases must pass from founders to children at about t = 80–150, on few carriers. With credit more of
  them make it, and they stay.
- **In the world actually run, those two roughly offset for population.** So what credit leaves there is the same number of
  people, 8.5–11% less total sugar, more inequality, more sickness and more trade. "A head start" is still a fair
  description of population in that world, but it isn't all credit does: the level population hides a gain at equal disease.
- **Why more diseases last isn't settled.** More hosts near the sick is the lead the evidence fits best, on averages and timing, but no
  measure I tried sorts seeds within a run. That includes the trough, my earlier lead.
- **Trade is mostly disease.** Where diseases circulate, disease count accounts for nearly all of credit's gap in trades per head.

**The lead on the trough.** A seed's trough doesn't predict how many diseases it keeps. But that test doesn't separate the trough from
anything else, because the other measures fail it too. Diseases at t = 200, 60 seeds, where the raw effect of credit on the count is 1.42:

| Measure | Credit's effect, holding it | Correlation of the pairs' gaps | Correlation within a run, on and off |
|---|---|---|---|
| Trough | 1.52 | 0.20 | −0.08, −0.10 |
| Population at t = 90 | 1.49 | 0.20 | −0.03, −0.07 |
| Births at t = 61–90 | 1.44 | 0.22 | 0.01, −0.05 |
| Neighbours per sick agent at t = 61–80 | 1.09 | 0.05 | 0.27, 0.17 |

So trough depth as such doesn't sort seeds, and neither does population or births, and neighbours only weakly. This is evidence
about the seeds within an arm. It can't rule out what credit does to the average, which is what the rest of this section reads. The timing
is against the trough having a direct role: the two runs have about the same number of diseases until after it, which comes at about
t = 68 with credit and t = 73 without, and the gap opens later:

| t | 50 | 80 | 90 | 100 | 125 | 200 | 2,000 |
|---|---|---|---|---|---|---|---|
| Diseases circulating, credit on | 8.55 | 5.87 | 4.62 | 3.63 | 3.37 | 3.32 | 3.32 |
| Diseases circulating, credit off | 8.55 | 5.70 | 4.00 | 2.63 | 2.15 | 1.90 | 1.83 |

No disease ever returned in either run, so a disease that's gone stays gone.

**The trace.** A tracer read each run period by period to t = 200 through the runner's `period_done` hook: each disease's carriers,
who catches what, and the neighbours of the sick. It covered credit on and off on 60 seeds, claims on 20 and the other probes on 10,
180 runs in all. Population, new infections and diseases circulating match the runs' CSVs in every period of t = 1–200 in all 120 on and
off runs, so it reads a run without changing it. Credit on against off, 60 seeds:

- **Short diseases go first, with or without credit.** Of the 668 diseases of length 7 or less that any founder carries, 603 with
  credit and 605 without are gone by t = 50. Few founders can carry them, since a short string is likely to match somewhere in an immune
  string: the share of founders not immune is 0.006 at length 3, 0.23 at length 5 and 0.96 at length 10.
- **What lasts is long, and so is credit's gap.** Lengths 9 and 10 are 95–96% of what's left at t = 200, and they hold 1.32 of the
  1.42 gap. Length 8 gives 10 survivors against 3:

  | Length | Listed | Survive to t = 200, credit on | Credit off |
  |---|---|---|---|
  | 7 | 149 | 0.000 | 0.007 |
  | 8 | 146 | 0.068 | 0.021 |
  | 9 | 156 | 0.449 | 0.205 |
  | 10 | 157 | 0.758 | 0.497 |

- **They all reach t = 60, on few carriers, and must change hosts.** Of 313 long diseases 313 and 311 are alive at t = 60, with a median
  of 16 and 14 carriers. By then the share of new infections in people born during the run is rising fast, from about 0.5 at t = 41–50 to
  0.98 at t = 81–90, in both runs.
- **The sick have more neighbours with credit, more so than population alone would give.** Neighbours per sick agent read 1.20 against
  1.04 at t = 51–60, 1.45 against 1.16 at t = 61–70 and 1.87 against 1.45 at t = 71–80, higher with credit in 48 of 60, 50 of 59 and 50 of
  58 seeds. That ratio is about 1.25–1.29 at t = 61–80, against about 1.17–1.21 for all agents' neighbours. The gap builds gradually
  from about t = 41. The share of the living who could catch a long disease is about level, 0.80 and 0.79 at t = 70, as are infections per contact
  at t = 61–80, 0.34 and 0.33. So there are more vulnerable people close by, in about the same proportion: 4,438 against 3,777 per long disease.
- **Carriers turn upward sooner.** Total carriers over ten periods, as a ratio, per seed and by median: 0.75 with credit and 0.62 without
  from t = 65, 1.10 and 0.60 from t = 70, 1.59 and 0.82 from t = 75. A seed's carriers bottom out 13.6 periods sooner with credit,
  [9.8, 17.5], and that low is 51.5 carriers against 20.4. In 15 of those lows carriers reach 0, 3 with credit and 12 without, so that's partly
  when diseases die out. Without those seeds it's 12.7 periods, [9.4, 16.1], sooner in 40 of 47.
- **Most of the gap opens at about t = 80–125, and credit off keeps losing a few afterwards.** Credit's lead in long diseases is 6 at t = 80, 57 at
  t = 100, 70 at t = 125, 76 at t = 150 and 79 at t = 200. In t = 125–200 credit off loses 12 long diseases and credit on 3. Not all of those
  are thin: credit off's include diseases with 209, 106, 61 and 32 carriers at t = 125. After t = 200 credit off loses 4 more, and credit on none.

**The fit can't say how much hosts explain.** I fitted each living disease's survival to t = 200 on credit, its carriers at t = 60 and
its length, and credit's coefficient is 1.18 [0.81, 1.62]. Adding one more reading lowers it, whatever the reading is about:

| Added | Credit's coefficient |
|---|---|
| Noise | 1.17 |
| Trough | 0.80 |
| Mean sugar, t = 70 | 0.74 |
| Neighbours per sick, t = 61–80 | 0.68 |
| Population, t = 90 | 0.61 |
| Mean sugar, t = 90 | 0.41 |
| Trades per head, t = 41–60 | −0.30 |
| Population at t = 70 and t = 90, and neighbours | −0.03 |

Anything credit moves takes credit's coefficient with it, because it largely says which run a seed is in. So this doesn't favour hosts
over the trough or wealth, and I withdraw the reading of it I first drafted.

**What does point to hosts.** Two things, neither decisive. Inheritance without credit has more people and no loans, and it has more
diseases than credit off, +1.1 [0.0, 2.2]. And over the six 10-seed worlds, more people at t = 80 goes with more diseases at t = 200, and it seems
to level off:

| | Off | On | Limit | Inheritance, off | Bigger loans | Inheritance, on |
|---|---|---|---|---|---|---|
| Population at t = 80 | 5,667 | 6,863 | 6,941 | 7,594 | 8,418 | 8,978 |
| Diseases at t = 200 | 1.9 | 3.3 | 3.4 | 3.0 | 3.5 | 4.2 |

Inheritance also adds wealth, so these aren't clean tests of hosts, and the intervals are wide.

**Claims doesn't fit simply.** With claims the mean of carriers at t = 100 is 2.4 times credit off's (226 against 93, and 444 with credit on; medians
82, 53 and 408), but there are no more diseases, −0.15 against off, [−1.0, 0.6], and clearly fewer than credit on, −1.3, [−2.1, −0.55]. It has 1.19 neighbours
per sick at t = 61–70, against 1.13 off and 1.44 on. So one lead, untested, is that only hosts arriving before about t = 75 matter.
Its interval still allows a modest gain.

**Which diseases cross.** Credit raises the odds at every size, and a disease's early carriers predict much of which ones make it. Among
long diseases, by quartile of carriers at t = 60, survival to t = 200 runs 0.23, 0.51, 0.68 and 0.96 with credit, and 0.09, 0.23, 0.41 and 0.65
without. Carriers at t = 60 sort survivors well (area under the curve 0.84 and 0.78). Even the other run's carriers at t = 20 do, 0.79 and
0.76, so much of that is settled when the runs are still alike. A disease survives with credit 0.82 of the time when it survives without, and 0.49 when
it doesn't. The on and off counts at t = 200 correlate 0.526 by seed, list lengths alone leave that at 0.525, and each disease's carriers at
t = 60 with its length leave 0.319. There are no repeat runs of a seed, so I can't say how much of the rest is chance.

**The test with no disease.** The defaults with `disease_list` and `diseases_per_agent` set to 0, credit on and off, seeds 20–39, 1,000
periods, through `run_extinction` with a custom experiment. Reports: `extinction-nodisease-s20-20-p1000.md` and
`extinction-nodisease-nocredit-s20-20-p1000.md`. None of the 40 went extinct. Its on and off pair by seed, but they don't pair
with the runs with disease, whose random draws differ. Credit off against on, t = 501–1,000, ratios of means with 95% intervals over
seed pairs:

| | No disease, on | Off | Off against on | With disease, on | Off | Off against on |
|---|---|---|---|---|---|---|
| Population | 77,527 | 69,028 | 0.890 [0.880, 0.900] | 64,146 | 63,404 | 0.988 [0.962, 1.014] |
| Gini | 0.227 | 0.201 | 0.886 [0.880, 0.892] | 0.240 | 0.215 | 0.892 [0.880, 0.906] |
| Mean sugar | 26.14 | 29.60 | 1.132 [1.117, 1.149] | 25.87 | 28.59 | 1.105 [1.094, 1.115] |
| Total sugar | 2,024,844 | 2,040,836 | 1.008 [1.000, 1.016] | 1,659,272 | 1,813,897 | 1.093 [1.066, 1.123] |
| Trades per period | 24,268 | 14,228 | 0.586 [0.579, 0.595] | 92,095 | 55,417 | 0.602 [0.507, 0.696] |
| Trades per head | 0.313 | 0.206 | 0.658 [0.652, 0.664] | 1.513 | 0.932 | 0.616 [0.517, 0.720] |
| Mean price | 1.047 | 0.965 | 0.921 [0.915, 0.926] | 1.464 | 1.221 | 0.834 [0.793, 0.875] |

Ratios that match don't show the same cause, as trades show below. So I split the pairs with disease: each pair's gap in t = 501–1,000 against its gap in
diseases at t = 200, which comes before that window. The intercept reads credit's gap at equal counts. This is a fit on a result of the change,
across 60 pairs:

| Credit on minus off | Whole gap | At equal counts | Per extra disease | r |
|---|---|---|---|---|
| Population | 741 [−1,013, 2,386] | 5,958 [4,498, 7,319] | −3,682 [−4,387, −2,996] | −0.80 |
| Gini | 0.026 | 0.018 [0.014, 0.022] | 0.005 [0.004, 0.007] | 0.63 |
| Mean sugar | −2.72 | −2.59 [−3.05, −2.15] | −0.09 [−0.29, 0.09] | −0.13 |
| Trades per head | 0.581 | 0.018 [−0.132, 0.139] | 0.397 [0.346, 0.473] | 0.86 |
| Mean price | 0.243 | 0.032 [−0.029, 0.079] | 0.149 [0.112, 0.190] | 0.80 |

- **Population: the two roughly offset, on average, on this map pair.** The gain at equal counts, 5,958, against 3,682 times the 1.42 extra diseases, about 5,216, leaves
  about 740, the net actually read. With no disease credit's gain is larger in people, 8,499, though close in ratio, 0.89 against 0.90 at equal counts. It doesn't
  offset pair by pair: the gaps vary widely, and they correlate −0.80 with the disease gap.
- **Mean sugar is credit's own, and most of the Gini is.** About 70% of the Gini gap remains at equal counts. Mean sugar doesn't depend on the count.
- **Trade and price are mostly through disease.** See below.
- **With disease, population's gap closes as the extra diseases spread.** Population, off against on:

  | t | 60 | 100 | 125 | 150 | 200 | 300 | 500 | 1,000 |
  |---|---|---|---|---|---|---|---|---|
  | No disease | 0.922 | 0.826 | 0.827 | 0.832 | 0.850 | 0.908 | 0.897 | 0.891 |
  | With disease | 0.912 | 0.774 | 0.809 | 0.870 | 0.944 | 0.979 | 0.995 | 0.984 |

  To t = 60 they're about the same, and so are the other measures: at t = 41–60 trades read 0.828 and 0.829, mean sugar 1.016 and 1.016. With no disease the gap
  doesn't close by t = 1,000: 0.894 at t = 501–750 and 0.887 at t = 751–1,000, lower in all 20 seeds both times. Nothing tests t = 2,000.
- **The trough isn't only disease.** With none, population still falls from 20,000 to 9,922 with credit and 9,183 without, at t = 54 and
  t = 65. Disease takes it to 5,787 and 5,020. Credit's lift is 8.0% with no disease, [7.2%, 8.9%], and 15.3% with it.

**Grouping seeds by disease count.** Means over t = 501–1,000, by diseases circulating at t = 1,000, with the runs with no disease at the
top. Seeds in a group aren't assigned at random, and several groups are tiny, so read the pattern, not a row:

| Diseases | Seeds, on / off | Population, on / off | Trades per head, on / off | Mean price, on / off | Gini, on / off |
|---|---|---|---|---|---|
| None, by rule | 20 / 20 | 77,527 / 69,028 | 0.313 / 0.206 | 1.047 / 0.965 | 0.227 / 0.201 |
| 0 | 3 / 14 | 76,924 / 68,570 | 0.310 / 0.206 | 1.06 / 0.967 | 0.230 / 0.202 |
| 1 | 1 / 11 | 75,572 / 67,145 | 0.468 / 0.388 | 1.098 / 1.048 | 0.228 / 0.205 |
| 2 | 20 / 16 | 70,763 / 63,143 | 0.890 / 0.919 | 1.174 / 1.188 | 0.230 / 0.214 |
| 3 | 7 / 10 | 63,504 / 60,006 | 1.584 / 1.479 | 1.409 / 1.376 | 0.241 / 0.225 |
| 4 | 13 / 7 | 60,557 / 55,694 | 1.846 / 2.092 | 1.512 / 1.660 | 0.242 / 0.235 |
| 5 | 11 / 1 | 56,764 / 51,089 | 2.203 / 2.435 | 1.833 / 1.951 | 0.253 / 0.243 |
| 6 | 5 / 1 | 54,196 / 54,398 | 2.449 / 2.187 | 2.078 / 1.832 | 0.258 / 0.244 |

- **The seeds that lost every disease read like the runs with none.** That shows the no-disease runs are a fair baseline for seeds whose disease died out,
  and says nothing about counts of 1 or more, where the offset operates. Credit on's three such seeds are few and spread, from 73,895 to 80,474, and credit
  off's include seeds 73 and 75, whose last disease lasted to t = 635 and t = 511.
- **Each disease goes with about 3,200–4,300 fewer people on average** (slopes −4,276 with credit, −3,179 without, r −0.91 and −0.87, against the count at t = 200). The first
  seems to cost less, on thin groups. Credit's gap is about 8,000 at counts up to 2 and 3,500–4,900 at 3 and 4, the groups that have enough seeds on both sides, so the two effects
  don't simply add.

**Trade is mostly disease.** Trades per head go from 0.2–0.3 with none to about 2.4 with six, and the price about doubles. The evidence, none of it a randomised test:
- Within each arm trades per head correlate 0.91 and 0.90 with the count at t = 200, which comes before the window they're read over.
- It doesn't go through population: holding the share sick, their partial correlation with population is −0.22 and 0.01. Holding population, it's 0.50 and 0.75 with the share sick.
- Two seeds lose their last disease well inside the run, both with credit off. In seed 73 (t = 635) trades per head go from 0.304 to 0.208, and in seed 75 (t = 511) from 0.322 to
  0.201, comparing the 100 periods before with t + 100 to t + 200. Price falls with them, 1.045 to 0.980 and 1.060 to 0.971, near the runs with none.
- Credit also has its own lift with no disease, 0.107 per head, [0.105, 0.109]. At equal counts with disease the fit reads 0.018, [−0.132, 0.139], whose interval
  contains that, so the lift can't be seen there, against disease's far larger gap. I said earlier in this work that trade and price were marks of disease and not of credit.
  That was too strong: with no disease credit off has 41% fewer trades.
- Why is a lead. The fee is in the marginal rate of substitution directly (`sugar_burn` in `mrs`, `julia/src/rules/welfare.jl:37`), so a sick agent values sugar more at the same holdings. That's from the
  code, not tested.

**What this doesn't show.**
- All of it is on one map pair, as before. The runs with no disease have 20 seeds and stop at t = 1,000, and population is still
  rising slowly in every run there, about 6% from t = 501–750 to t = 751–1,000 with credit.
- The no-disease world has about 20% more people than the runs with disease with credit on, and 9% more with it off, so credit's own effect there
  needn't be the same size as in a world with disease. The fits at equal counts are the only reading in that world, and they condition on a result of the change.
- What makes more diseases last with credit isn't established. The readings of neighbours, carriers and births describe what differs between the arms on average, not what causes survival.
- Lengths of 8 or less don't last, but they are 54% of founders' disease load at t = 0. Their effect on the trough isn't tested.
- The trace stops at t = 200, and the scripts aren't in the repository. Copies are in `results-julia-xxl/lasting-mark-scripts/` with the traces in
  `results-julia-xxl/disease-trace/`, all git-ignored, so they don't travel with the repo.

**Run time.** Same machine, 5 workers, no memory stops. The trace took about 62 minutes. The runs with no disease took 6,760 s and
5,895 s, 3 h 31 min in all.

**My recommendation, not a decision.**
1. **Keep credit, and describe it as more than a head start.** In the world actually run it leaves about the same people, with 8.5–11% less total sugar, more inequality and
   more sickness. At equal disease or none it adds about 9–12% to population. This changes the question I left with the user: helping through the worst period isn't
   all it does, and not all of what else it does is welcome. Whether that's working as intended is still the user's call. I'd still say yes.
   (The user has since ruled that it is: see stage 4.)
2. **Make stage 4's first question the disease list.** The count of diseases moves population a long way, and trade and price more than anything else here, and it's set by
   a crossing on few carriers. What lasts is almost entirely lengths 9 and 10, about 5.2 per seed. X9 reads 0.95 with credit and 0.80 without, so its pass depends on that
   crossing. A spec could test lists with more long diseases. That's a rule change, so it's for the user to decide.
3. **Judge trade after disease, not before.** Changing disease will move every trade reading, so a trade check set now would be largely measuring disease.
4. **Don't run more of this first.** The unknowns left (what makes diseases last with credit, why disease drives trade, and what the seeds share) matter mostly if stage 4 keeps this
   disease list. A test of hosts would be replicate runs of a seed with hosts added by hand at about t = 60–80, and that's worth doing only if the crossing stays.

## Stage 4: the disease list

The user read stage 3 and ruled that **credit is working as intended**, so credit stays on throughout this stage. They chose to design the disease list,
recommendation 2 above. This step adds Rule 12, a switch for the list, and measures six candidate lists against a reading table set before the runs.
The design is `docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md`. Nothing here changes `XXL_DEFAULTS`: whether to adopt a list is the user's decision.
(The user adopted list D afterwards: see "Adopting list D" at the end of this section.)

**The short answer.**
- **A short list of long diseases does what the idea said.** List D, 3 diseases of length 9–10 with 1 offered to each founder, passed every bar set before the runs, in screening
  and in confirmation: none of 60 seeds extinct to t = 2,000, 13 of 13 on both scorecards, and 58 of 60 seeds inside X10's band at the end, against 47 of 60 today.
- **The trough rises by about half.** Mean 8,533 against 5,787, [1.41, 1.55] as a ratio, and the lowest seed is 7,427 against 3,441. Births to t = 100 rise a little more, 1.56 times.
- **The lottery in the count is mostly gone, and in population about half of it.** Diseases at t = 2,000 are 3 in 49 of 60 seeds and 2 in 9, against anything from 0 to 6 today.
  The spread of population over seeds falls from 0.110 to 0.064 at t = 301–500 and from 0.13 to 0.054 at t = 1,501–2,000. With no disease at all it's 0.018 at t = 301–500
  (stage 3's runs, seeds 20–39), so some of what's left is still disease.
- **On average, disease no longer depends on credit.** On seeds 20–39 credit off keeps 2.6 diseases at t = 500 against 2.75 with it, and X9 reads 19 of 20 both ways. Today the
  same seeds read 1.95 against 3.1, and 16 against 19. Seed by seed it's chance: seed 32 loses all disease with credit and keeps 1 without, and seed 27 loses it without
  and keeps 3 with. Without credit the band is weaker, 16 of 20, which would fail screening's bar. Credit still lifts the trough, 8,483 against 7,755.
- **What it costs.** One seed in 60 still loses all its disease, by t = 77. That's no worse than today: X9 reads 59 of 60 against today's 57, and today's scorecards read 0.95
  on both seed sets too. Trade falls by about a quarter by t = 1,501–2,000, as stage 3 predicted, since disease drives trade. Trade isn't judged here.

**The arms.** VI-1 under `XXL_DEFAULTS` plus the list, credit on, seeds 80–99, 500 periods. Today's list is the baseline, over its existing seeds 20–79.

| Arm | Diseases | Offered to each founder | Lengths | Why |
|---|---|---|---|---|
| Today | 25 | 10 | 1–10 | Baseline |
| A | 6 | 2 | 9–10 | Today's long diseases, without the rest |
| B | 4 | 2 | 9–10 | My guess |
| C | 4 | 2 | 10 | Same, at better odds |
| D | 3 | 1 | 9–10 | The lightest load |
| E | 10 | 4 | 9–10 | Today's load, all long: the ceiling check |
| F | 4 | 2 | 12 | Beyond the book's lengths |

**The reading table, set before the runs.** An arm passed screening if X9 held in at least 18 of 20 seeds, the mean share sick over t = 451–500 was inside 0.01–0.2,
at least 18 of 20 seeds were inside that band, the trough's mean was at least today's 5,787 with no seed below 3,441, and no seed went extinct. All 120 runs finished
and none went extinct.

| Arm | X9 | Share sick, mean | Seeds in band (under, over) | Trough, mean / lowest | Diseases at t = 500 | Result |
|---|---|---|---|---|---|---|
| Today, 60 seeds | 57 of 60 | 0.119 | 42 of 60 (4, 14) | 5,787 / 3,441 | 3.32, sd 1.58 | |
| A | 20 | 0.205 | 10 (0, 10) | 6,838 / 5,805 | 4.95, sd 1.43 | Fails both X10 rows |
| B | 20 | 0.134 | 18 (0, 2) | 7,522 / 6,637 | 3.6, sd 0.5 | Passes |
| C | 20 | 0.186 | 14 (0, 6) | 6,849 / 6,083 | 4.0, sd 0 | Fails per seed |
| D | 19 | 0.095 | 19 (1, 0) | 8,533 / 7,771 | 2.7, sd 0.73 | **Passes, chosen** |
| E | 19 | 0.192 | 8 (1, 11) | 4,596 / 3,813 | 4.6, sd 2.09 | Fails per seed and on the trough |
| F | 20 | 0.439 | 0 (0, 20) | 3,698 / 2,094 | 4.0, sd 0 | Fails three rows |

B and D passed. The choice went to the most seeds in band, 19 against 18, so under the rule set before the runs it rests on one seed. The misses differ: D's one is
seed 96, which lost all disease, and B's two are just over the band, 0.209 and 0.218. D's lead on the trough doesn't rest on a seed: B's best trough, 8,388, is below D's
mean. D also has the lower share sick, and about the same spread of population, 0.066 against 0.062. Neither of the spec's conditional readings fired as worded: A didn't
pass while B–D failed, and E passed X10's mean, 0.192, only just under the bar, while failing it per seed with 11 of 20 over. E's mean passing is the scorecard's
reading, so by that bar alone the ceiling isn't where I thought. Per seed it is.

**My guess against what happened.** Written before the runs: 4 diseases of length 9–10 with 2 offered to each founder (B) lifts the trough by a quarter or more, ends with about
3 diseases per seed, passes X9 at 0.95 or better and puts at least 18 of 20 seeds in band. A list of 10 long diseases fails X10. Beyond length 10 isn't needed.
- **The trough:** right. B's is 30% above today's.
- **About 3 diseases:** a little low. B kept 3.6, since 12 of 20 seeds kept all 4.
- **X9 and the band:** right, but the band only just: 18 of 20, exactly the bar.
- **A list of 10 fails X10:** right per seed, wrong on the mean. See above.
- **Length 10 is enough:** right, and more than that: length 12 is harmful. F keeps all 4 diseases in every seed, the share sick is 0.44 and its trough is lower than today's.
- **The idea holds.** The list's size sets a ceiling: C and F keep every disease they list, and B nearly does. Longer diseases last better and make more people sick, so
  4 at length 10 already fails. What I didn't guess is that the lightest arm would do best.

**Confirmation.** List D, on the same terms as stages 2 and 3. Reports: `disease-list-confirmation.md`, `disease-list-credit-off.md`, `scorecard-list-d-s0-20.md` and
`scorecard-list-d-s20-20.md`, all in `results-julia-xxl/`.

| Bar | Reading | Result |
|---|---|---|
| Extinction, seeds 20–79 to t = 2,000: none | 0 of 60 | Pass |
| Scorecard, seeds 0–19 and 20–39: 13 of 13 | 13 of 13 and 13 of 13 | Pass |
| Seeds in X10's band at the end, t = 1,951–2,000: at least 0.9 | 58 of 60 (2 under, 0 over) | Pass |

The table set before the runs reads this as **recommend adopting it**. Over the 60 seeds at t ≤ 500 it also passes every screening row: X9 59 of 60, share sick 0.081,
58 of 60 in band, trough 8,533 / 7,427. D against today, ratios of means with 95% intervals:

| Reading | Today | D | Ratio |
|---|---|---|---|
| Trough | 5,787 | 8,533 | 1.474 [1.407, 1.550] |
| Births to t = 100 | 12,409 | 19,297 | 1.555 [1.467, 1.655] |
| Share sick, t = 451–500 | 0.119 | 0.081 | 0.680 [0.546, 0.852] |
| Population, t = 301–500 | 57,346 | 60,972 | 1.063 [1.030, 1.098] |
| Population, t = 501–1,000 | 64,146 | 67,365 | 1.050 [1.016, 1.087] |
| Population, t = 1,501–2,000 | 69,827 | 74,659 | 1.069 [1.033, 1.108] |
| Mean sugar, t = 1,501–2,000 | 25.03 | 25.41 | 1.015 [0.998, 1.032] |
| Gini, t = 1,501–2,000 | 0.239 | 0.234 | 0.976 [0.964, 0.989] |
| Trades per head, t = 1,501–2,000 | 1.556 | 1.153 | 0.741 [0.640, 0.868] |
| Mean price, t = 1,501–2,000 | 1.386 | 1.198 | 0.865 [0.812, 0.920] |

At t = 501–1,000 trades per head and price read about as they do at t = 301–500, 0.839 and 0.874 as ratios, and mean sugar is about 1.5% higher in every window. The trough comes a
little sooner, at t = 62 against 68 on average. Diseases circulating are 2.8 at t = 100 and 2.78 at t = 200, against 3.63 and 3.32. The share sick still follows the
count, but the count hardly varies. At t = 1,951–2,000 it is 0.035 with 2 diseases and 0.070 with 3.

**What moved on the scorecard.** Against today's scorecards on the same seeds, 0–19 and then 20–39:
- **Up:** S2, the margin over near-extinction, about doubles, 0.18 to 0.38 and 0.20 to 0.37. X4, culture's movement, about doubles, 0.17 to 0.32 and 0.19 to 0.31. X7, credit
  persisting, rises from 990 to 2,991 and from 1,134 to 2,795. S3 rises a little.
- **Down, inside their bars:** X10 falls, 0.112 to 0.086 and 0.107 to 0.076, and X6, the gap in price, narrows, 1.22 to 1.13 and 1.20 to 1.16. X1 dips, 1.051 to 1.042 and 1.044 to 1.037.
- **The same:** S1, S4, S5, X3, X5, and X2 and X8, which are reported only. X9 reads 1 and 0.95, against today's 0.95 and 0.95: the second scorecard fails it in seed 32, which also loses all disease in the extinction run.

**Credit off.** Seeds 20–39, 500 periods, a reading and not a bar. Credit on and off pair by seed. D's disease barely depends on credit any more, so on this reading the lasting
mark of stage 3 on disease belongs mostly to today's list:

| Seeds 20–39 | Today, on | Today, off | D, on | D, off |
|---|---|---|---|---|
| Diseases at t = 500 | 3.1 | 1.95 | 2.75 | 2.6 |
| X9 | 19 of 20 | 16 of 20 | 19 of 20 | 19 of 20 |
| Seeds in band, t = 451–500 | | | 19 of 20 | 16 of 20 |
| Trough, mean / lowest | | | 8,483 / 7,429 | 7,755 / 6,651 |

Without credit, D's count is higher or lower than with it in only 5 of 20 seeds. Its band is weaker: 2 seeds are under and 2 over.

**Found after the runs.**
- In arms A, B and D of screening, and today's 60 seeds with credit, no seed's count changed after t = 145. Without credit today's seeds change as late as t = 1,674. It
  doesn't hold for D's 60 seeds either: seed 69 loses a disease at t = 804. The other ten seeds that end under 3 lose theirs by t = 140. Seed 32 loses all three, one at
  t = 69 and the last two at t = 77, and seed 57 loses two, by t = 70.
- A list can draw the same disease twice: two diseases match only at the same length and the same bits. Per seed that's about 3.3% for E, 1.1% for A, 0.6% for C,
  0.4% for B, 0.2% for D and 0.15% for F, worked out from `init_disease_list!`. It never happened: every seed of this stage's runs starts with as many diseases as its list. (Today's list, with its short diseases, starts with 14–24 of 25.)
- The memory watcher in screening matched no process, so it couldn't have stopped a run. Nothing ran short of memory then, so no result is affected. Confirmation's watcher
  did work, and it stopped one scorecard once, when another program took the memory. That scorecard was started over from the beginning.

**What this doesn't show.**
- All of it is on one map pair, as before.
- B wasn't confirmed, and the choice of D over B rests on one seed in 20. B keeps disease better. D is lighter on the trough and the share sick.
- How often a seed loses all disease isn't pinned down. D's runs with credit have 2 such seeds in 80, so the chance per seed could be anywhere from about 0.3% to 8.7%.
  X9's bar is 0.9, so a scorecard of 20 seeds fails with 3 such seeds: about a 1% chance at 2 in 80, and 27% at 9%.
- Trade falls by about a quarter, and nothing here says whether that's right. That was a non-goal: trade is judged after disease.
- Population is still rising at t = 2,000 in both worlds, so the end readings aren't a steady state.

**Run time.** Same machine, 5 workers. Screening took about 3 h 46 min for the six arms, from 21 min for F to 52 for B. Confirmation took 54 and 61 min for the two
scorecards, plus 13 min lost to the memory stop, 40 min for credit off, and 13 h 43 min for the 60-seed extinction run, against 13 h 16 min for today's with fewer people.

**My recommendation, not a decision.**
1. **Adopt list D in `XXL_DEFAULTS`:** `disease_count = 3`, `founder_diseases = 1`, `disease_lengths = (9, 10)`. It passed every bar set before the runs, lifts the trough by about half
   and takes most of the lottery out of disease. Adopting it changes the defaults' fingerprint, so every saved result under the defaults goes stale, and the defaults need
   their own run list. That's a separate step.
2. **If a margin on X9 matters more than the trough, B is the alternative.** It kept disease in all 20 seeds, but it has more sickness, its band passed at the bar exactly, and it
   wasn't confirmed.
3. **Then judge trade.** With disease settled, trade per head is about 1.15 instead of 1.56, and that's now the reading to judge.

**Adopting list D.** The user adopted recommendation 1: `XXL_DEFAULTS` now has `disease_count = 3`, `founder_diseases = 1` and
`disease_lengths = (9, 10)`. The same change brought in a speedup that alters the random draws: under round vision, an infertile
agent's mate search no longer looks or draws, since nothing could come of it ("Mate search within vision"). The rules don't change,
but every xxl run with sex, round vision and mate search within vision now draws differently, the first rules' runs included. The
xxl fingerprint says so with a line of its own. A folder saved before the change is refused by the extinction test and the loan
trace, and read as stale by `xxl_report`; a plain `--xxl` or scorecard run doesn't check an old folder's fingerprint, so give those a
new `--out`. Book and xl runs are unchanged.

What this means for the record:
- The findings above stand: they compare lists under the rules, and the skip changes no rule. But no run of today's code
  reproduces the confirmation runs, which were made before the skip.
- Every saved result under the old defaults is stale: the extinction, scorecard and loan runs of stages 1–4.
- The extinction-risk test ("Stage 2: the chance of extinction") is to be rerun whenever the defaults change. The list D confirmation run is that test for
  list D, but on the draws before the skip, so a reference rerun under today's code is the record to keep. The old defaults'
  folders (`extinction-defaults-s20-60-p2000`, `loans-defaults-s20-10-p2000`) hold the default label, so a rerun needs a new
  `--label` or those folders moved. The rerun is below.
- V-1, V-2 and `VAR-inttrade/VI-1` take the list too under `--xxl`, and nothing here measured them.

**The reference rerun.** Run on 2026-11-03 at b6a6d66, the commit that adopted list D, with label `list-d-default`: both scorecards and the
60-seed extinction test, then `xxl_disease_list.jl --base extinction-list-d-s20-60-p2000 --arms rerun=extinction-list-d-default-s20-60-p2000
--label reference` to read it against the confirmation. It is the record of today's defaults.
- **Extinction test: pass.** 0 of 60 seeds (20–79) extinct over 2,000 periods, so the chance of extinction is under 4.87% at 95% confidence,
  against a bar of 5%. No living seed is falling at the end. The trough averages 8,552, at about t = 61, and its lowest is 7,341, in seed 46.
- **Scorecards: 13 of 13 on both,** seeds 0–19 and 20–39. Against the confirmation's scorecards, S2 reads 0.388 and 0.375 against 0.383 and
  0.371, X10 0.081 and 0.074 against 0.086 and 0.076, X7 3,237 and 2,846 against 2,991 and 2,795, and X9 1 and 1 against 1 and 0.95.
  S4 and S5 come from II-4 and IV-A3, which have no sex, and read the same, as they must. X1 reads the same to the digits shown.
- **The same world as the confirmation, within noise.** Every ratio of the rerun's mean to the confirmation's has 1 inside its 95% range, at
  t ≤ 500 and in both later windows:

| Reading | Confirmation | Rerun | Ratio [95%] |
|---|---|---|---|
| Trough, mean | 8,532.5 | 8,552.2 | 1.002 [0.986, 1.018] |
| Births to t = 100 | 19,297 | 19,362 | 1.003 [0.983, 1.024] |
| Share sick, t = 451–500 | 0.081 | 0.076 | 0.932 [0.761, 1.141] |
| Population, t = 1,501–2,000 | 74,659 | 75,046 | 1.005 [0.987, 1.024] |
| Gini, t = 1,501–2,000 | 0.234 | 0.234 | 1.001 [0.993, 1.009] |
| Mean sugar, t = 1,501–2,000 | 25.41 | 25.29 | 0.995 [0.979, 1.012] |
| Trades per head, t = 1,501–2,000 | 1.153 | 1.125 | 0.975 [0.882, 1.076] |
| Mean price, t = 1,501–2,000 | 1.198 | 1.194 | 0.997 [0.973, 1.021] |

- **The band and the trough bar.** The share sick is inside 0.01–0.2 at the end in 59 of 60 seeds, against 58. The report's one "near" row
  is screening's trough bar: the rerun's lowest seed, 7,341, is 1.2% under the confirmation's 7,427. That bar asks a new list to be no worse
  than the baseline, not two runs to match, and the means match, so I don't read it as a difference.
- **Losing disease.** At t = 2,000 the rerun has 3 diseases in 45 seeds, 2 in 14 and none in 1, against 49, 9, 1 and 1 with 1 disease. 15
  seeds end under 3 diseases, against 11, and 8 seeds are in both. Seed 32 loses all three again, but slowly, at t = 59, 305 and 1,198 instead
  of by t = 77, so X9 at t ≤ 500 reads 60 of 60 against 59. Seed 69 again loses one late, at t = 823 against 804. Seed 57, which lost two,
  keeps all three. A seed's founders and their diseases are drawn before any mate search, so they are the same in both runs; the overlap
  suggests a seed's start matters to whether it loses disease, but the draws after matter too.
- **Run time.** Same machine, 5 workers: 29 and 31 min for the scorecards, and 6 h 41 min for the extinction test, against 54 and 61 min and
  13 h 43 min for the confirmation. That's the eight speedups merged before list D together with the skip.

## Stage 5: trade

Stage 4 recommended judging trade once disease was settled, and the user went on with it. Under list D trade passes its checks (X5,
X6), but it follows sickness: stage 3 found trades per head of 0.2–0.3 in seeds with no disease against about 2.4 with six. The user
ruled that this isn't trade working as intended: **some healthy agents should trade in order to get rich**, and a healthy agent who
trades should end up with more resources than one who doesn't (both **the user's**). The way to get there that the user accepted was my
proposal: gather what is plentiful where you stand and trade it for the other good instead of walking for it. That needs movement that
counts on trade, so this stage built Rule 13 and screened five versions of it. The design is
[docs/superpowers/specs/2026-11-03-xxl-trade-design.md](superpowers/specs/2026-11-03-xxl-trade-design.md), with the changes made after
Part 1 at its end. Nothing here changes `XXL_DEFAULTS`.

**The short answer.** Rule 13 changed almost nothing. No version passed screening and none came near, so by the design the stage stops
here, with no confirmation run. No arm's reading is clearly above or below today's except for small rises in trade (about 1% with no
disease, 2–4% in IV-A3), and distance walked is within 1.5% in every arm. Healthy traders
already hold about 9% more than similar healthy agents who trade least, and no arm raised that. With no disease, trades per head stayed
at 0.31, where the bar asked for twice that. What to try next is the user's call.

**What was built** (on branch `xxl-trade`): Rule 13 (above); an observer that records, each period, who trades with whom by health and,
for a window, every agent's holdings at its start and end; `julia/xxl_trade_study.jl`, which runs an arm with it; and
`julia/xxl_trade_report.jl`, which applies the bars. With Rule 13 off and no observer, runs give the same bytes as on `main`: the pinned
same-run digests and `XXL_V1` goldens, recorded on `main`'s code, pass unchanged.

**The comparison the bar reads** (**the user's**: similar traders against similar non-traders in the same world, not the world with trade
against the world without it, which credit showed can turn a gain into more agents rather than richer ones). Agents alive throughout a
window and strictly healthy in it are put in cells of the same metabolisms, vision, age band and fifth of resources at the window's
start. In each cell of at least 6, the third with the most exchanges is set against the third with the fewest, and the reading is their
mean resources at the window's end, sugar + spice ÷ the window's mean price, pooled over cells. Matching makes this fairer, not a
randomised test.

### Part 1: who trades, and does it pay

**The first run measured nothing on its main question.** The window was t = 401–500, and VI-1's agents live 60–100 periods, so almost
none were alive at both ends: every VI-1 snapshot was empty. The report then read the missing figure as "not richer" and picked a row of
the design's table on it. That was a bug, now fixed: a missing figure decides nothing. The user then made three decisions (all **the
user's**):
- the window is the last 20 periods (t = 481–500), which keeps about a third of agents;
- the healthy-trade bar is dropped: 92% of strictly healthy agents traded with a strictly healthy partner within 10 periods (98% with
  recovering agents counted as healthy), against a bar of 25%. The reason I gave when asking: trades are one unit at a time, so nearly
  everyone trades a little;
- the bars count only **strictly healthy** agents, with no disease for 10 periods. The design counted recovering agents as healthy, but
  they were 32% of agents. The reason I gave when asking: their holdings are still skewed by the fee, so their trade is largely
  disease-driven. The design's wider reading is shown beside each figure.

**The rerun, seeds 80–99, 500 periods** (`results-julia-xxl/trade-part1b.md`):

| Reading, t = 301–500 unless marked | Strictly healthy | Recovering counted as healthy |
|---|---|---|
| Traders ÷ similar non-traders, resources at the mean price, t = 481–500 | 1.09 [1.051, 1.133] | 1.089 [1.05, 1.133] |
| Agents matched, 20 seeds | 331,595 (815 in cells too small) | 442,651 |
| Healthy agents' exchanges with a partner who isn't healthy | 0.534 (random pairing 0.275) | 0.195 (random 0.084) |
| Healthy ÷ sick median gap in log MRS to neighbours | 0.225 | 0.266 |
| Trades per head with both healthy / with one | 0.259 / 0.612 | 1.039 / 0.531 |

With no disease, trades per head are 0.308. Sick agents make 7.5 exchanges each per period, and recovering agents 3.3. The design's
table picked "healthy trade is mostly with sick partners, and healthy MRS gaps are small": **the diagnosis holds**, go on to screening.
Trade on against trade off moves nothing measurable: strictly healthy agents' resources 1.017 [0.976, 1.062], population 0.989, total
resources 1.008, all straddling 1.

Today already sits at 1.09 against the Richer bar of 1.10, so a version that only matched today would sit at the bar. The user changed
the bar (**the user's**): an arm must reach 1.10 with its interval above 1, **and** at least 1.05 × today's (1.145), **and** the interval
of its ratio ÷ today's must be above 1.

### Screening

VI-1 under `XXL_DEFAULTS` plus each arm, seeds 80–99, 500 periods, with the same arm in the no-disease world and in IV-A3
(`results-julia-xxl/trade-screen.md`). The arms were the design's, all *my call*:

| Arm | Expected price | Blend | Guard | Traders ÷ non-traders | ÷ today's | Trades per head, no disease | Trades per head |
|---|---|---|---|---|---|---|---|
| Today | — | — | — | 1.09 [1.051, 1.133] | — | 0.308 | 1.687 |
| A | local | 1 | 5 | 1.083 [1.049, 1.122] | 0.993 [0.946, 1.043] | 0.311 | 1.728 |
| B | own | 1 | 5 | 1.095 [1.055, 1.139] | 1.004 [0.953, 1.059] | 0.310 | 1.698 |
| C | local | 0.5 | 5 | 1.087 [1.052, 1.125] | 0.997 [0.948, 1.048] | 0.310 | 1.586 |
| D | local | 1 | none | 1.08 [1.044, 1.121] | 0.991 [0.942, 1.042] | 0.311 | 1.636 |
| E | local | 1 | 15 | 1.083 [1.045, 1.125] | 0.993 [0.943, 1.047] | 0.312 | 1.504 |

- **Fails, every arm:** Richer with trade (B's row alone is near), and trade without disease (0.310–0.312 against a bar of 0.617). One
  failed bar is enough, so no arm is near and there's no further round.
- **Passes, every arm:** sick agents still trade (7.42–7.58 per head against 7.53), the trough (means 8,485–8,555 against 8,544, lowest
  7,768 against a floor of 7,224), X9 and X10 per seed (at least 18 of 20), X6 (1.15–1.17), and no extinction.
- **Nothing else moved clearly.** Against today's, every ratio's interval straddles 1 except trades per head with no disease, up about 1%
  in A, D and E, and IV-A3's trades per head, up 2–4% in A, C and D. Trades per head over all agents fell in C and E (0.94 and 0.89 of
  today's), but their intervals are wide and straddle 1; E's mean price is 1.35 against 1.39. Distance walked is 1.19–1.21 against 1.21.
  Population, Gini, mean sugar and mean spice are within about 2%.

### What happened against my guess

I guessed, before measuring, that healthy traders today would end within 5% of similar non-traders, and that Rule 13 at a local price
with a guard would double trade with no disease and leave healthy traders at least 10% richer. Healthy traders today are already 9%
richer, and Rule 13 changed neither figure.

**Why, as I read it** (*my call*, not tested). Valuing a site at the expected price p ranks sites by sugar + spice ÷ p. To first order
the book's welfare does the same at the agent's own MRS (its marginal rate at the agent's holdings is the MRS). Trade evens MRSs out:
healthy neighbours' log MRSs differ by a median of 0.07. If an agent's own MRS likewise sits close to the market's p, and a site's goods
are small next to what an agent holds so the book's diminishing returns barely bite, the two scores pick almost the same site and Rule 13
seldom changes where an agent goes. Two things this doesn't settle: the 0.07 is between neighbours, not between an agent and p; and sick
agents' gap is 0.29, so the argument predicts Rule 13 moves sick agents more, which screening didn't measure. A check would count how
often a move's target differs between the two scores, on one seed. It needs a small counting script and about 7 minutes of running, and
it hasn't been run: the user asked to hold it until they say.

### What this doesn't show

- All of it is on one map pair. Where sugar and spice sit decides how much specialising could pay, so this limit matters more here than
  in earlier stages.
- Matching traders with non-traders isn't a randomised test: who trades most may differ in ways the cells don't hold.
- The window is 20 periods, so the comparison reads a short stretch of a life.
- Screening ran on 20 seeds, 500 periods. An effect too small to see there isn't ruled out, but it would be too small to meet the user's bar.
- The explanation above is untested.

### Run time

Same machine, 5 workers, no memory stops: the first Part 1 took 1 h 23 min, 12 of them for VI-1's xl reference, which its rerun reused;
the rerun took 1 h 8 min, and screening 8 h 47 min. With Rule 13 on a run takes about 1.45 times as long. Screening's VI-1 runs slowed
from arm B on (25 min for A, 43–59 for the others); when I looked at 20:47, three processes of another project, started at 19:18, were
using about 18 of the machine's 24 threads.

### My recommendation, not a decision

1. **Don't adopt any version of Rule 13.** None changed anything the user asked for.
2. **Run the check first**, if the user agrees: one seed of arm A, about 7 minutes, counting how often Rule 13 changes a move's target.
   If it seldom does, the next design needs a stronger lever than the movement score; if it often does, the reason is elsewhere.
3. **The next design is the user's call.** Candidates I'd consider: trades of more than one unit, so that an agent far from its partner's
   MRS can move a lot at once; a map whose sugar and spice sit further apart, so a site's goods are less balanced; or accepting trade as
   it is. Each is a new rule change, with its own design.
4. **The branch keeps Rule 13 off by default**, and with it off every run is unchanged, so merging it costs nothing but code. Whether to
   merge, keep it on its branch, or drop it is the user's call.

**The user's ruling** (2026-11-05): no version of Rule 13 is adopted, and the next step investigates trades larger than one unit. The
check above wasn't run: stage 5b made it moot.

## Stage 5b: the meeting's price

The user asked to investigate trades larger than one unit, with this reasoning (**the user's**): it isn't realistic for the MRS to set a
new price during a single bargaining session; the price should be set when the session starts and apply to every unit, and there has to
be a way for the seller to profit, not just break even. I pointed out that a meeting already trades until the MRSs would cross, so the
change is to the price, not to how much a step holds. I proposed, and the user agreed, Rule 14 (above): the book's geometric-mean price,
computed once when the meeting starts. The design is
[docs/superpowers/specs/2026-11-05-xxl-meeting-price-design.md](superpowers/specs/2026-11-05-xxl-meeting-price-design.md). Nothing here
changes `XXL_DEFAULTS`.

**The short answer.** Rule 14 fails screening, so by the design this step stops with no confirmation run. Healthy traders end slightly
richer than today's against similar non-traders, 1.103 against 1.09, but not by the bar and not clearly; trade with no disease doesn't
move at all. The reason is in the new reading: **a meeting moves 1.68 units on average.** With one or two units a meeting, a price fixed
for the meeting can hardly differ from one recomputed each unit.

**The run.** One arm, M (`trade_price = "meeting"`), under `XXL_DEFAULTS`, seeds 80–99, 500 periods, in VI-1, the no-disease world and
IV-A3 (`results-julia-xxl/trade-screen-meeting.md`). The baseline is stage 5's Part 1 rerun, made at commit 9bf328c on `xxl-trade`;
with Rule 14 off the code makes the same runs, so the comparison isolates the rule. The bars are stage 5's as the user left them.

| Row | M | Bar | Result |
|---|---|---|---|
| Richer with trade | 1.103 [1.07, 1.139]; ÷ today's 1.012 [0.964, 1.062] | at least 1.10, interval above 1; at least 1.145; ÷ today's interval above 1 | near |
| Without disease | 0.3077 trades per head | at least 0.6166 (×2 today's 0.3083) | fail |
| Sick agents still trade | 7.357 | at least 3.767 | pass |
| Trough | mean 8,590, lowest 8,018 | mean at least 8,117, none below 7,224 | pass |
| X9 / X10 per seed / X6 / extinction | 20 / 19 of 20 / 1.153 / 0 of 20 | 18 / 18 / at most 1.5 / none | pass |

The report's own verdict text follows stage 5's results table, so I applied stage 5b's by hand (*my call*, from the design): an arm is
near only if every failing row misses by no more than 5% of its bar. The no-disease row misses by half, so M is neither a pass nor near:
it fails, and the second version (a price leaning towards the agent who needs the trade less) is the user's call. The report's own text
reaches the same "stop".

**Readings, against today's:** trades per head 1.64 against 1.69, sick agents' 7.36 against 7.53, and IV-A3's trades per head 0.945 of
today's, the one ratio clearly below 1 (interval [0.924, 0.966]). Population, Gini, distance walked and the trough match today's. Units
per meeting are 1.68, and the price spread across a period's meetings is 0.47 in log price: prices do differ from meeting to meeting, but
each meeting is too small for that to make anyone rich. Today's units per meeting weren't recorded (the baseline's readings predate the
column). Back-to-back meetings of one pair count as one, so units per meeting read about 0.3% high.

**Against my guess.** I guessed each meeting would move fewer units than today's, trade per head would fall, the no-disease bar would
fail, and the matched ratio would rise to about 1.12. Trade fell a little (within noise), the no-disease bar failed, and the ratio rose to
1.103, also within noise. The guess got the direction of everything, but it didn't foresee that meetings average only 1.68 units.

**Why meetings are so short, as I read it** (*my call*, not tested). One unit changes the buying agent's log MRS by about 1/sugar +
p/spice, and the selling agent's by about as much the other way. With mean holdings of about 28 sugar and 37 spice and a price near 1.4,
that is about 0.07 each, so one unit narrows the pair's gap by about 0.15. The median gap between strictly healthy neighbours' log MRSs is
0.068 (over all neighbour pairs, not only those that trade), so for a typical healthy pair one whole unit overshoots about twofold, and
the book's tests refuse it. The meetings that do happen are presumably between pairs with wider gaps, or poorer agents, whose steps are
larger still. The unit isn't too small for healthy agents to profit; it is too large. Trades of a fraction of a unit would let two
neighbours with a small gap take several steps.

### What this doesn't show

- One map pair, 20 seeds, 500 periods, one arm.
- Units per meeting under today's rule weren't measured, so how much shorter Rule 14's meetings are is not known.
- The reasoning about unit size is arithmetic on means, not a measurement; holdings and gaps vary widely between agents, and 1/sugar
  grows fast for poorer agents, so the step a unit takes is far from uniform.

### Run time

Same machine, 5 workers, no memory stops: 44 minutes for the three runs and the report, 16 for VI-1 and 21 for the no-disease world.

### My recommendation, not a decision

1. **Don't adopt Rule 14.** It changed nothing the user asked for.
2. **Next, smaller units** (the user's choice of next step, after this result): let a step trade a fraction of a unit, so that healthy
   neighbours with a small gap can trade further before their MRSs cross. It is a new rule with its own design.
3. **The branch keeps Rule 14 off by default** and changes no run with it off. Whether to merge it is the user's call.

## Stage 5c: smaller trade steps

The user chose smaller units next (**the user's**), after stage 5b found one whole unit narrows a healthy pair's gap in log MRS by about
0.15 against a typical gap of 0.068. Rule 15 (above) makes a step a share of the book's unit; the study used a tenth, my proposal, which
the user approved. The user also decided to test it alone and with Rule 14's meeting price, to measure every volume bar in goods moved
rather than exchanges counted, and to rank traders in the matched comparison by the goods they moved rather than by their exchanges (all
**the user's**). The design is
[docs/superpowers/specs/2026-11-05-xxl-trade-step-design.md](superpowers/specs/2026-11-05-xxl-trade-step-design.md). Nothing here changes
`XXL_DEFAULTS`.

**The short answer.** Smaller steps did what was hoped for the amount of trade and nothing for who gets rich. Healthy agents trade far
more: sugar moved per head with no disease more than doubles, so the no-disease bar passes, where every earlier arm of stage 5 failed it
(measured then in trades counted). But traders end no richer than similar non-traders, about 1.00–1.02 times, against today's 1.052, so
both arms fail the Richer bar, by 9% and 8%, and the step stops with no confirmation run.

**The runs.** Seeds 80–99, 500 periods, under `XXL_DEFAULTS`: a new run of today's rule in VI-1 with the new readings (its 20 seed CSVs
are byte-identical with stage 5's Part 1 run, so the comparison isolates the step), then arm S (`trade_step = 0.1`) and arm SM (also
`trade_price = "meeting"`), each in VI-1, the no-disease world and IV-A3 (`results-julia-xxl/trade-screen-step.md`). Every fingerprint was
checked at launch.

**Today's ratio under the new ranking.** Ranked by sugar moved, today's healthy traders hold 1.052 times what similar non-traders hold,
against 1.09 when stage 5 ranked them by exchanges. So the Richer bar here was at least 1.105 (1.05 × 1.052), with its interval above 1
and the arm ÷ today interval above 1.

| Row | Today | S | SM | Bar | Result |
|---|---|---|---|---|---|
| Richer with trade | 1.052 | 1.004 [0.963, 1.05]; ÷ today 0.954 [0.900, 1.013] | 1.02 [0.983, 1.06]; ÷ today 0.969 [0.918, 1.023] | see above | fail, fail |
| Without disease, sugar moved per head | 0.387 | 0.914 | 0.854 | at least 0.775 | pass, pass |
| Sick agents' sugar moved per head | 8.2 | 10.66 | 9.69 | at least 4.1 | pass, pass |
| Trough, mean / lowest | 8,544 / 8,027 | 8,306 / 7,726 | 8,375 / 7,708 | at least 8,117 / 7,224 | pass, pass |
| X9 / X10 per seed / X6 / extinction | — | 20 / 20 / 1.128 / 0 of 20 | 20 / 20 / 1.121 / 0 of 20 | 18 / 18 / at most 1.5 / none | pass, pass |

By stage 5c's results table, applied by hand as before (*my call*): each arm fails one row, and misses it by more than 5% (S by 9.1%, SM by
7.7%), so neither is near. The report's own text reaches the same "stop". X6 weights each exchange equally, so smaller steps tilt it towards long meetings;
it is kept as the scorecard defines it.

**Readings.** Sugar moved per head between healthy agents rises from 1.17 to 1.86 (S) and 1.67 (SM), about 1.6 and 1.4 times; total spice moved per
head from 2.81 to 4.09 and 3.57. Exchanges per head rise about 13 to 15 times, from 1.69 to 24.8 and 22.2, since each step is a tenth. Sugar per meeting falls
from 1.93 to 0.88 and 0.80. Population (59,082 and 59,101 against 59,399), Gini (0.230 and 0.235 against 0.232), mean sugar and spice, and
distance walked hardly move. IV-A3's sugar moved per head rises from 1.33 to 1.76 and 1.52; its end population is 1% higher in S (7,400 against 7,326, interval
above 1) and unchanged in SM.

**Against my guess.** I guessed sugar moved with no disease would at least double, which it did, and that the matched ratio would rise,
past 1.145 with Rule 14 too. It fell instead, slightly, within noise.

**Why more trade doesn't make traders richer, as I read it** (*my call*, not tested). In the book's trade both sides gain by their own
welfare, at a price between their MRSs, and goods only change hands. When healthy agents trade a lot, trading evens holdings out
between neighbours rather than setting traders apart from non-traders, so the agents who moved the most end where similar agents who
moved less do.

### What this doesn't show

- One map pair, 20 seeds, 500 periods, one step size.
- The matched comparison isn't randomised; ranking by goods moved changes who counts as a trader, which is why today's figure was
  recomputed.
- Spice moved by pair type and per agent wasn't recorded (*my call*, to avoid another code change before the runs); only total spice is.
- The explanation above is untested.

### Run time

Same machine, 5 workers, no memory stops: 2 h 26 min for the seven runs and the report: 18 min for today's run, 28 and 33 min for the two
arms in VI-1, 27 min for each no-disease run, and about 3 min for each IV-A3 run.

### My recommendation, not a decision

1. **Don't adopt Rule 15 for its own sake.** It raises healthy trade a lot, which the user wanted, but not what the user's bar asks for:
   traders ending richer.
2. **Across stages 5–5c, no version of the book's trade made traders richer than similar non-traders.** Rules 13, 14 and 15 changed
   where agents go, how a meeting is priced and how much a step moves. In each, both sides gain by their own welfare and goods only change
   hands. Traders profiting at others' expense, like a merchant buying low from one agent and selling high to another, is a different
   kind of rule, and the next design, if any, is the user's call.
3. **Each branch keeps its rule off by default** and changes no run with it off. Whether to merge them is the user's call.

**The user's ruling** (2026-11-06): merge and move on from trade. The three branches were merged into main (c0b0312) with Rules 13, 14
and 15 off by default, none adopted. Trade in xxl stays as the book has it.

## Stage 6: sex

The user chose sex as the next stage and asked me to skip the questions, so the bars below are my calls, which the user approved. The
design is [docs/superpowers/specs/2026-11-07-xxl-sex-design.md](superpowers/specs/2026-11-07-xxl-sex-design.md). Nothing here changes
`XXL_DEFAULTS`, and no rule was added.

**What "works as intended" meant** (*my call*): rule S works in xxl as it does in the book. Births sustain the population (the
scorecard's X1 already passed, 1.04); births are limited by what the book's rules limit them by, age, the wealth test and an empty
site, not by xxl's world size or sparse look; and inheritance and selection still act. The question was whether xxl's look, which
checks the sites within an agent's speed plus a few random points out to its vision (about 30–130 sites against a vision disc of up to
about 7,850), leaves fertile agents without mates more often than the book's rules do.

**The short answer.** Sex works as intended in xxl, and the stage stops with no rule change. Fertile agents in today's xxl find a mate
more often than in the book's own world, not less, nearly all of them have a child before their fertile years end, and selection on
metabolism is at least as strong as the book's.

**The runs.** VI-1 in three worlds, 500 periods each, with an observer that records mating without changing a run (each seed's CSV is
byte-identical with it on and off, tested): the book's 50 × 50 world under the book's rules, xl's VI-1, and today's xxl
(`XXL_DEFAULTS`), on seeds 80–99 (`results-julia-xxl/sex-part1.md`). Every fingerprint was checked at launch. The book's 200-agent
VI-1 died out in 12 of the 20 seeds, leaving 8, under the design's minimum of 15, so M1, M2 and S all read missing. With the user's
go-ahead the book world was rerun on seeds 80–139. Its first 20 seeds matched the first run byte for byte, and 28 of the 60 survived.
No xl or today seed died out.

**Bars**, decided at t = 301–500. Ratios are today ÷ book of the means over seeds, with 95% intervals from 10,000 bootstrap resamples of
each world's seeds:

| Bar | Today ÷ book | Bar | Result |
|---|---|---|---|
| M1: fertile agent-periods with no mate in reach | 0.778 [0.767, 0.789] | at least 1.5, interval above 1 | doesn't hold |
| M2: agents fertile at least 5 periods who had no child | 0.917 [0.76, 1.11] | at least 1.5, interval above 1 | doesn't hold |
| S: relative drop in mean metabolism, t = 0 → 500 | 1.116 [1.039, 1.223] | at least 0.5 | holds |

M ("mate finding limits births in xxl") would need both M1 and M2 to hold. Neither does, so by the design's outcome rules sex works as
intended.

**Readings** (t = 301–500, means over seeds):

| Reading | Book | xl | Today |
|---|---|---|---|
| Fertile agent-periods with no mate in reach | 0.888 | 0.839 | 0.691 |
| ... with no fertile mate anywhere within vision | 0.888 | 0.246 | 0.055 |
| Fertile agents (≥ 5 periods) who had no child | 0.029 | 0.022 | 0.027 |
| Fertile share of the population | 0.126 | 0.109 | 0.096 |
| Agents of childbearing age blocked by the wealth test | 0.698 | 0.736 | 0.767 |
| Births per fertile agent-period | 0.121 | 0.133 | 0.165 |
| Mating attempts with no empty site, per birth | 0.014 | 0.015 | 0.0001 |
| Median distance between parents (sites) | 2.8 | 27.3 | 4.0 |
| Mean metabolism, start → end | 2.98 → 1.20 | 3.00 → 1.00 | 3.00 → 1.00 |
| Mean vision, start → end (sd at end) | 3.0 → 4.6 (0.36) | 30.0 → 47.1 (5.7) | 30.0 → 32.4 (13.9) |
| Mean speed, start → end (sd at end) | — | — | 3.5 → 5.0 (1.1) |

- **The limit on births is the wealth test, as in the book.** About 70–77% of agents of childbearing age fail it in all three worlds;
  only about a tenth of agents are fertile.
- **xxl's look is sparse, but mates are nearby.** 69% of today's fertile agent-periods have no mate in reach, yet only 5.5% have no
  fertile mate anywhere within vision. That gap is the look's sampling. It doesn't cost children: today has the most births per fertile
  agent-period of the three worlds, and a fertile life ends childless about as rarely as in the book (2.7% against 2.9%). The book's
  look covers every site it can see, so in the book the two shares are equal.
- **A child almost always finds a site** in xxl (one failed attempt per 14,000 births, against one per 70 in the book), probably because
  the world is sparse (a guess).
- **Selection acts.** Metabolism falls from 3 to 1 in xl and today, a little further than the book's 1.20. Vision barely moves in today
  and keeps its spread, while speed, the trait xxl agents move by, rises from 3.5 to 5.0. That fits xxl moving agents by speed (a guess),
  but it wasn't judged (*my call* in the design).

**Against my guess.** The stage began from the worry that the sparse look might make mate finding the limit. It doesn't: today's
no-mate share is lower than the book's and xl's, and almost every fertile life produces a child.

### What this doesn't show

- **The book's world compares unlike worlds.** It has its own density and its own look, so "1.5× the book's" compares unlike worlds; xl
  is shown beside it for that reason, and today ÷ xl gives the same answer for M1 (0.82).
- **Only the book's surviving seeds are read** (28 of 60), which may not be typical seeds. M1's interval is narrow and
  wholly below 1; M2's is wide and spans 1, but its point value is far from 1.5.
- One xxl map, VI-1 only, 20 seeds and 500 periods for xl and today.
- Vision, spice metabolism and speed are reported, not judged.

### Run time

Same machine, 5 workers: 48 s for the book's 20 seeds and 56 s for its 60, 19 min for xl and 30 min for today.

## Stage 7: culture

The user said to continue with culture and to skip the questions, so the bars below are my calls; the user approved them with the design. The design
is [docs/superpowers/specs/2026-11-07-xxl-culture-design.md](superpowers/specs/2026-11-07-xxl-culture-design.md). Nothing here changes
`XXL_DEFAULTS`, and no rule was added.

**What "works as intended" meant** (*my call*): rule K works in xxl as it does in the book. In the book, tag flipping between
neighbours makes agents culturally like the agents around them (pp.73–80). So: agents come to live among culturally like agents; an
area the size of the book's world tends toward one tribe; and culture keeps moving with both tribes alive across the whole world.
xxl's world holds 100 times the book's agents, so the whole world turning one colour, as the book's often does, wasn't asked for. The
scorecard's X3 and X4 already passed, but neither asks whether tags cluster.

**The short answer.** Culture works as intended in xxl, and the stage stops with no rule change. Today's neighbours are more alike than
chance and far more so than xl's, areas the size of the book's world lean toward one tribe, and both tribes live in every seed
with tags still flipping.

**The runs.** VI-1 in three worlds, 500 periods each, with an observer that records culture without changing a run: the book's 50 × 50
world under the book's rules (seeds 80–139, as stage 6's rerun), xl's VI-1 and today's xxl (`XXL_DEFAULTS`), both on seeds 80–99
(`results-julia-xxl/culture-part1.md`). Every seed's standard CSV is byte-identical to stage 6's for the same world and seed (100 of
100), so these are the same runs as stage 6's, observed again. 28 of the book's 60 seeds survived, as in stage 6; no xl or today seed
died out.

**Bars**, decided at t = 301–500. Ratios are today ÷ book of the means over seeds, with 95% intervals from 10,000 bootstrap resamples
of each world's seeds:

| Bar | Today ÷ book | Bar | Result |
|---|---|---|---|
| W1: neighbour closeness − 0.5 | 0.640 [0.586, 0.703] | under 0.5, interval under 1 | doesn't hold |
| W2: patch polarization (50 × 50 patches) | 0.458 [0.378, 0.577] | under 0.5, interval under 1 | holds |
| F: both tribes ≥ 5% at t = 500; tags flip every period of t = 301–500 | 20 of 20; 20 of 20 | ≥ 80% of seeds; every seed | holds |

W ("culture is weak in xxl") would need both W1 and W2 to hold. W1 doesn't, and F passes, so by the design's outcome rules culture works
as intended. W2 holds on its point value (0.458, under 0.5); its interval reaches past 0.5, but the bar asks only that it stay under 1.

**Readings** (t = 301–500, means over seeds):

| Reading | Book | xl | Today |
|---|---|---|---|
| Neighbour closeness | 0.842 | 0.563 | 0.719 |
| Chance closeness (all pairs, from the tag counts) | 0.797 | 0.505 | 0.505 |
| Neighbour closeness above chance closeness | 0.044 | 0.058 | 0.213 |
| Patch polarization | 0.542 | 0.074 | 0.249 |
| Blue share | 0.574 | 0.499 | 0.496 |
| Tag flips per agent per period | 0.30 | 0.89 | 1.03 |
| Neighbours per agent | 1.73 | 2.03 | 4.10 |
| Neighbour pairs still together next period | 0.18 | 0.08 | 0.37 |
| Distance moved per period (sites) | 1.7 | 16.9 | 1.2 |
| Friend closeness | 0.831 | 0.543 | 0.680 |
| Per-position polarization at t = 500, mean \|2zᵢ − 1\| | 0.70 | 0.08 | 0.09 |

- **The book's clustering is mostly its whole world converging.** In the book's surviving seeds, tags across the whole world are
  almost as alike as neighbours' (chance closeness 0.80 against neighbour closeness 0.84). Five of the 28 end with one tribe under
  5%. The mean per-position polarization at t = 500 is 0.70. W1 and W2 measure against 0.5 on purpose, so that convergence counts as the rule
  working. But it means much of the book's value, which the 0.5 bars halve, comes from its world being small enough to turn one colour.
- **Today's clustering is local, and the strongest of the three.** Today's neighbours are 0.21 more alike than two agents picked at
  random from the whole world, against 0.04 in the book and 0.06 in xl. The whole world stays mixed (blue share 0.50, per-position
  polarization 0.09) while neighbourhoods and 50 × 50 patches lean to a colour. That is the book's "segregated subpopulations"
  picture at a scale where the whole world can't converge.
- **xl shows how much is xxl's rules rather than world size.** At the same world size, today's neighbour closeness above 0.5 is 3.5 times xl's, and its patch
  polarization 3.4 times. xl agents move about 17 sites a period, and few neighbour pairs last to the next period (0.08). Today's
  move about 1, have twice as many neighbours, and keep them (0.37). My reading, not tested: neighbours that stay put give flips time to
  add up. The today ÷ xl patch ratio's interval is wide, [2.56, 4.53].
- **Still rising slowly.** Today's neighbour closeness above 0.5 goes 0.17, 0.19, 0.21, 0.22 over t = 51–100, 101–200, 201–300 and
  301–500, and patch polarization 0.16, 0.19, 0.23, 0.25. The book's flattens after t = 200 (0.30, 0.33, 0.34).

**Against my guess.** The stage began from the stage-6 numbers showing today's friend closeness (0.68) well below the book's (0.84),
which I read as possibly weak culture. Measured against what the whole world looks like, today's neighbours are more alike, not less. The book's
higher number is mostly global convergence.

### What this doesn't show

- **The book's world compares unlike worlds.** It has its own density and neighbourhood (4 sites against xxl's 8 within 1.5), so
  "half the book's" compares unlike worlds; xl is shown beside it to say how much is world size and how much is xxl's rules.
- **A 50 × 50 patch of a bigger world isn't closed** as the book's world is: agents come and go across its edges, which is part of what
  W2 measures.
- **Only the book's surviving seeds are read** (28 of 60), which may not be typical seeds.
- One xxl map, VI-1 only (culture changes nothing else there: no cultural preferences, no combat), 20 seeds and 500 periods for xl and
  today. Whether today's patches would keep sharpening past t = 500 isn't known.

### Run time

Same machine, 5 workers: 62 s for the book's 60 seeds, 19 min for xl and 32 min for today. The observer adds little over stage 6's
times.

## Stage 8: combat

The user added combat to the goal, asked for the book's combat variants to be run in xxl and analyzed, and said to skip the questions,
so the bars below are my calls; the user approved them with the design. The design is
[docs/superpowers/specs/2026-11-08-xxl-combat-design.md](superpowers/specs/2026-11-08-xxl-combat-design.md). Nothing here changes
`XXL_DEFAULTS`, and no rule was added: every variant was already an experiment, and xxl already ran combat with its own move (rule 7).

**What "works as intended" meant** (*my call*): rule C works in xxl as it does in the book (pp.82–92). In the book combat is war
between tribes. It kills across tribal lines; it keeps the tribes apart, so that they meet at a front instead of mixing; the war can
last; and with culture on, tag flipping keeps either tribe from taking everything. In xxl that has to happen without the population
dying out. The book's exact endings (one tribe wiped out, tribes swapping mountains) weren't asked for: xxl's world holds 100 times
the book's agents, and the generated map has no twin peaks.

**The short answer.** Combat works as intended in xxl, and the stage stops with no rule change. It is gentler than the book's: under
C_∞ it kills about 0.4 times as many agents per founder, and neither tribe is wiped out in any seed. But it keeps the tribes apart more
completely than the book's does (at t = 901–1000, once they have met), the war with replacement lasts with a front, and with culture on
both tribes survive. No seed of any variant died out.

**The runs.** Five experiments in three worlds, seeds 0–19, each over its own steps, with an observer that records kills, contact,
territory and wealth without changing a run (`results-julia-xxl/combat-part1.md`):

| Variant | Experiment | Steps |
|---|---|---|
| C_∞ | III-9 | 1000 |
| C_2 with same-tribe replacement | III-11 | 1000 |
| No combat (the waves) | III-12 | 200 |
| C_2 | III-13 | 200 |
| C_∞ with culture K | III-14 | 1000 |

The worlds are the book's 50 × 50 world under the book's rules, xl, and today's xxl (`XXL_DEFAULTS`; the tribal blocks at xl's
corners on the generated map, with viable placement inside each block). Every book and xl seed that has a saved run with a current
fingerprint is byte-identical to it (50 of 50; xl's saved III-12, III-13 and III-14 predate xl's centred look and weren't compared).

**A second run of III-12 and III-13 for today.** Read as planned, the report said "works as intended", but its separation bar was
empty, so I set that verdict aside (W2 read honestly as missing, so W missing and no outcome): in 200 periods today's tribes, starting
far apart, barely met. Without combat only 0.003% of neighbour pairs were cross-tribe over t = 101–200 (the book's world: 8%), and with
combat no one was killed in that window. So the cut in mixing (0.993) measured distance, not combat, and the design's anti-goal says a
bar can't pass because no one fights. With the user's go-ahead, today's III-12 and III-13 were run again for 1000 periods, and before
the results I fixed how W2 would read them: today's cut over t = 901–1000 against the book's over t = 101–200, and W2 missing if
today's no-combat mixing over t = 901–1000 stayed under a tenth of the book's (0.008). The long runs' figures below come from
`results-julia-xxl/combat-scripts/w2-long.jl` (output `w2-long.txt`); `combat-part1.md` still shows the 200-period W2.

**Bars.** Ratios are today ÷ book of the means over seeds, with 95% intervals from 10,000 bootstrap resamples of each set of seeds:

| Bar | Today ÷ book | Bar | Result |
|---|---|---|---|
| W1: III-9 kills per founder by t = 1000 | 0.391 [0.318, 0.495] | under 0.5, interval under 1 | holds |
| W2: cut in mixing, 1 − mixing(III-13) ÷ mixing(III-12) | 1.279 [1.219, 1.351] | under 0.5, interval under 1 | doesn't hold |
| F1: III-11 kills in every 100-period block of t = 501–1000; both tribes' home share above 0.5 | 20 of 20; 20 of 20 | every seed; ≥ 80% of seeds | holds |
| F2: III-9 and III-14 alive at t = 1000 | 40 of 40 | every seed | holds |
| F3: III-14 both tribes ≥ 5% at t = 1000 | 20 of 20 | ≥ 50% of seeds | holds |

W ("combat is weak in xxl") would need both W1 and W2 to hold. W2 doesn't, and F passes, so by the design's outcome rules combat
works as intended. The cuts behind W2: the book's 0.767 [0.726, 0.804] over t = 101–200, today's 0.981 [0.980, 0.982] over
t = 901–1000 (today's no-combat mixing there is 0.012, above the 0.008 floor); xl's is 0.172 [0.156, 0.187].

**Readings** (means over seeds):

| Reading | Book | xl | Today |
|---|---|---|---|
| III-9: kills per period, t = 101–200 / 501–1000 | 0.71 / 0.017 | 80.8 / 10.9 | 0.60 / 10.6 |
| III-9: population at t = 501–1000 (from 540 / 54,000 / 54,000) | 130 | 2,018 | 22,250 |
| III-9: seeds with both tribes ≥ 5% at the end | 7 of 20 | 17 of 20 | 20 of 20 |
| III-11: kills per period, t = 501–1000 | 9.3 | 1,169 | 723 |
| III-11: home share blue / red, t = 501–1000 | 0.79 / 0.77 | 0.89 / 0.89 | 0.64 / 0.88 |
| III-11: front share, t = 501–1000 | 0.050 | 0.061 | 0.084 |
| III-12 mixing (no combat): book and xl t = 101–200, today t = 901–1000 | 0.080 | 0.080 | 0.012 |
| III-13 mixing (C_2): same windows | 0.019 | 0.066 | 0.00023 |
| III-14: population at t = 501–1000 | 7.5 | 4,716 | 1,441 |
| III-14: tribe changes per period, t = 1–100 / 501–1000 | 1.4 / 0.0001 | 195 / 0.63 | 111 / 0.078 |

- **Today's wars start late and never end.** Under C_∞ (III-9) no one is killed in the first 100 periods, while the tribes are still
  apart; kills rise to about 10 a period by t = 501–1000, when the book's war is long over. Each tribe stays on its own side (home
  shares above 0.99 throughout), and neither is wiped out in any seed, against 13 of 20 seeds in the book's world ending with one tribe
  under 5%. Speed is what tames it: an agent can attack only within its speed (1–6), so war is fought at a front, not across the map
  (rule 7). xl, which can attack anywhere within its vision (10–60), kills 1.7 times the book's per founder, and its population falls
  to about 2,000. - **Combat keeps the tribes apart, with few kills.** Without combat, today's tribes meet after about t = 200 and
  mixing rises steadily to 0.012 by t = 1000, still climbing. With C_2 it stays about 50–130 times lower in every window from t = 201
  on, while III-13 kills only 0.02–0.5 agents a period. The book's world cuts mixing by three quarters; xl's by a sixth. - **The war of
  attrition lasts.** With same-tribe replacement (III-11) today kills 700–900 agents a period throughout, and both tribes hold more
  than half their side in every seed. Blue holds its side less firmly than red (0.64 against 0.88), and red starves five times as
  often; one generated map, so this may be the map's. - **With culture, no tribe takes everything.** In III-14 both tribes live in
  every seed. Tag flips run at about half xl's rate early and an eighth of it late; the book's world is down to 7 or 8 agents by then.
  Today's survivors are very unequal (Gini about 0.9).

### What this doesn't show

- **Kills by attacker are read from the victim.** The observer counts victims by tribe; with two tribes the attacker is the other
  one, so kills by attacker tribe aren't recorded separately.
- **The book's world compares unlike worlds.** It has its own density and neighbourhood (4 sites against xxl's 8 within 1.5) and
  twin peaks the generated map doesn't have; xl is shown beside it to say how much is world size and how much is xxl's rules.
- **W2 measures mixing, not waves.** The book recreation doesn't reproduce the waves (Blue advances about 8 sites by t = 50), and
  today's W2 compares a late window, after the tribes have met, with the book's early one. Today's no-combat mixing is still rising at
  t = 1000, so the size of the cut at a settled front isn't known.
- One xxl map, 20 seeds, no combat in VI-1 or the scorecard (combat is barred with credit and spice). A combat check in the
  scorecard isn't proposed: nothing here calls for one.

### Run time

Same machine, 5 workers: about 3 min for the book's 100 seeds and 24 min for xl's. Today: III-9 29 min, III-11 66 min (it holds
40,000 agents), III-12 and III-13 at 200 periods 24 min, III-14 7 min; the 1000-period III-12 and III-13 39 and 48 min.

## Results of the first rules (`XXL_V1`)

This section is the record of the first rules, `XXL_V1`, as the 16 `XXL-…` experiments still run them. Where it says
"the defaults" or "the xxl defaults", it means those rules (the first-rules column of "The settings"), not today's
defaults. The results were made before an infertile agent's mate search stopped looking ("Adopting list D", above), so
today's code doesn't reproduce their seeds where an experiment has sex. The rules are the same.

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
