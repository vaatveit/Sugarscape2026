# Sugarscape xxl — Design

Date: 2026-10-28. Builds on [the xl design](2026-10-24-xl-design.md) and its contract, [docs/xl.md](../../xl.md),
and on [the Julia port's design](2026-10-24-julia-design.md): xxl is built in the Julia port only.

## Intent

xl is the book's model at 10× the linear size, adjusted so that its results match the regular run's. **xxl is a
different model:** a separate rule set (user decision: named "xxl") that uses the bigger world instead of hiding it.
It is not a recreation of the book and is not scored against the book's targets.

**Julia only** (user decision, 2026-10-28: Python is too slow at this scale). xxl is built in the Julia port,
`julia/`, which steps xl's II-4 in 0.014 s per period against Python's 1.33 s (julia/docs/validation.md). The
Python model, runner, registry and viewer don't change.

**What the bigger world offers.** In Sugarscape an agent fills one site and harvests one site, so a site is the
agent's own size, not a free choice of grid resolution. The 500 × 500 world is therefore 10× wider *measured in
agents*, and what it adds is room: room to pull apart lengths that the 50 × 50 world forces to be about the same.

| Length, in sites | Book (50 × 50) | xl | xxl |
|---|---|---|---|
| Distance moved in a period | up to vision, 1–6 | up to vision, 10–60 | speed, 1–6 |
| Vision | 1–6 | 10–60 | 10–60 |
| Interaction (trade, culture, disease, mating, credit) | 1 | 1 | radius R, 1.5 by default (the 8 Moore neighbours) |
| Landscape features (mountain radius) | about 10 | about 100 | about 100 (xl map), or 5–80 (generated) |
| World | 50 | 500 | 500 |

In the book every agent can reach anything it can see in one period, for free, and what it can see is a sizeable
share of the world. xxl keeps xl's far sight but makes moving slow and costly, so distance matters: crossing a
valley takes many periods, and agents have reasons to settle, migrate in waves, remember places and tell each other
about them. Each change below is a separate switch with a *book setting* that turns it off, so its effect can be
measured alone.

**Goals**
- Six rule changes, each switchable: round vision, speed with travel cost, memory and word of mouth, an interaction
  radius, seasons that vary with latitude, and a generated landscape with features at many scales. Combat (rule C)
  works under them.
- `julia --project=julia julia/run.jl <id> --xxl`, parallel to `--xl`: any registered sugarscape experiment, run on
  the xl world under the xxl rules, into `results-julia-xxl/`.
- Registered `XXL-…` experiments that add the changes one at a time, so each one's effect is measured.
- New metrics for what the changes are about: distance moved, regional prices, clustering, migration.
- A contract, `docs/xxl.md`, defining the rules without reference to any one language (as `docs/xl.md` does for
  xl), and reporting the `XXL-…` results.

**Non-goals**
- Matching the book or xl, apart from the exact reduction check (Verification).
- A Python implementation (user decision), or xxl in the Python viewer, which runs the Python model.
- A FLAME GPU version (*my call*: not until the Julia rules settle).
- Schelling and Ring World.
- Multi-threading a single run. It stays the Julia port's separate follow-up. xxl will cost several times xl's
  stepping; the builder measures and reports it, as for xl.

**Anti-goals**
- **No regular or xl run changes, on either side.** Python is untouched. In Julia, every registered experiment
  keeps its random stream and its fingerprints, so `results-julia/` and `results-julia-xl/` stay current and still
  agree with Python's. `julia/registry.toml` is still exported from Python, unchanged, and the existing Julia
  tests, the scenarios and lockstep fixtures included, pass unchanged.
- **The book rule modules keep their behaviour.** xxl hooks in at the few points named below; it doesn't edit the
  book rules into something else.
- **No silent fallback.** A combination xxl doesn't define is refused by `validate`, not run under book rules.

## Distances

Sites are at whole-number coordinates on the torus. The distance between two sites is Euclidean, the shorter way
round in each direction: d = √(dx² + dy²), where dx = min(|x₁ − x₂|, W − |x₁ − x₂|), and dy likewise.

## The rules

### 1. Round vision

**Book setting:** `vision_shape = "lattice"`, the existing look along four lattice lines (xl's centred look at
stride 10).

**xxl:** `"disc"`. An agent looks at:
- its own site;
- every site within its near radius n (1 ≤ d ≤ n), where n is its speed S, everywhere it could be at the end of
  this period; without speed (`XXL-vision`), n = 1, the four adjacent sites (*my call*), so a site next door is
  never missed;
- K sites drawn uniformly *by area* from the ring n < d ≤ V, each rounded to the nearest site. K = ⌈4·V/10⌉ (*my
  call*), as many as xl's look checks, so a vision-60 agent draws 24. Duplicates are looked at once; sites outside
  the ring after rounding are dropped.
- With memory on (rule 3), also its remembered sites.

This removes the lattice's preference for the four axes. It also removes the reason xl needed random offsets in the
first place: moves along lattice lines in steps of 10 split the world into 100 separate worlds.

Mate search within vision (`mate_contact = "vision"`) takes a fresh disc look from the agent's position after
moving, as the lattice version takes a fresh look today (*my call*): the agents on those sites are its partners in
sight, nearest first.

Speed (rule 2) works with either vision shape; with the lattice look, the near sites are the lattice's own.

### 2. Speed and travel cost

**Book setting:** `speed = None`. The agent jumps to the best site it sees and pays nothing for the move.

**xxl:** speed S is a genetic trait like vision: drawn uniformly from `speed` = (lo, hi) at birth, by default (1, 6)
(*my call*: the book's vision range), and passed to children as rule S passes vision. Each period:
1. **Choose a target.** The candidates are the agent's own site (d = 0), the empty sites it looked at (rule M
   considers only empty sites, at every distance), and, with memory on, its remembered sites beyond vision, whose
   occupancy it can't see (*my call*). For a candidate at distance d, travel takes T = max(1, ⌈d / S⌉) periods,
   and the agent would arrive holding
   - h₁ = b₁ − c·d − m₁·(T − 1) sugar, where c is the travel cost per site and m₁ the sugar burn (metabolism plus
     disease fees),
   - h₂ = b₂ − m₂·(T − 1) spice, with spice on,

   where b is what the agent's holding counts for now: max(w − φ·m, 0) with foresight φ (eq. 6, the clamp as now),
   and w itself without foresight. The travel terms are subtracted after the clamp (*my call*), so a poor agent
   still pays for distance; welfare counts a holding below zero as zero, as it does now. Whether the agent would
   starve on the way is judged on what it really holds: a candidate other than its own site is dropped when
   w₁ − c·d − m₁·(T − 1) ≤ 0, or w₂ − m₂·(T − 1) ≤ 0 with spice (*my call*, after the plan review: judged on the
   clamped holdings, an agent with foresight holding less than φ·m could never move). The net value is h₁ + s
   with one commodity, where s is the site's sugar devalued by pollution as now (s / (1 + p)), and the welfare
   W(h₁ + s, h₂ + q) with two, where q is its spice devalued the same way.
   With c = 0 and T = 1 this ranks sites exactly as rule M does.

   The agent targets the highest net value. Ties go to the nearest; remaining ties at random. Its own site is a
   candidate at d = 0. Values are what the agent sees now. It doesn't predict growback.
2. **Step.** If the target is within S, the agent moves onto it. Otherwise it walks toward it in a straight line.
   For k = S, S − 1, …, 1 it takes the site nearest its position plus k sites along that line (rounding to the
   nearest site, the same rounding everywhere), and moves to the first that is empty. If none is empty, it stays.
3. **Harvest and pay.** It harvests the site it ends on, as rule M does. In metabolism it also burns c × the
   distance it actually moved, in sugar. This counts as burn for the income credit reads, and for consumption
   pollution. The death check is unchanged.

The target is chosen again every period (*my call*: no commitment to a destination). An agent drawn off course by a
better site nearer by is the behaviour being studied.

`travel_cost` c defaults to 0.1 sugar per site (*my call*; `XXL-speed` sweeps it). Speed may not exceed vision
(*my call*): an agent never reaches, in one period, a site it can't see. With S = V and c = 0, every target is
reached in one period and nothing is charged, which is rule M again.

### 3. Memory and word of mouth

**Book setting:** `memory = 0`.

**xxl:** each agent keeps up to `memory` = M remembered sites (default 8, *my call*). An entry holds the site, the
resources seen there (sugar, and spice with spice on), the pollution seen there, and the period it was seen. Rule 2
devalues the remembered resources by the remembered pollution; combat (rule 7) uses the sugar as it is. It stores
resources, not a score, so it can be valued again from anywhere, by anyone (*my call*).
- After moving, the agent pools its memory with the sites it looked at this period and keeps the M with the highest
  net value (rule 2) from its new position, with its holdings now (ties to the more recent). The site it harvested
  is stored as it is after harvest, so the agent doesn't return to it expecting food. Entries older than
  `memory_span` periods (default 50) are dropped first.
- A remembered site still within vision is looked at afresh. Beyond vision, the agent values the remembered
  resources, with travel time and cost as in rule 2.
- **Word of mouth** (`word_of_mouth`, default on when memory is on): after moving, an agent copies each neighbour's
  first entry (the one that neighbour ranked highest) into its own memory, with the period it was seen, then keeps
  the M best by its own ranking.

Memory needs speed. Without it, a remembered site beyond vision couldn't be reached by any rule, so `validate` refuses
memory without speed.

### 4. Interaction radius

**Book setting:** R = 1.

**xxl:** an agent's neighbours are the living agents within distance R of it. R = 1 is exactly the book's four von
Neumann neighbours, R = 1.5 the eight Moore neighbours, and R = 3 the 28 sites within 3. Trade, culture, disease,
credit and rule S with `mate_contact = "neighbors"` all use this set, and so does `mean_neighbors`. A child is born on
a random empty site within R of either parent (the book: one of the parents' four neighbour sites). It takes its
speed from a random parent, as it does vision.

The default is R = 1.5, the eight Moore neighbours (user decision, 2026-10-28): a round neighbourhood to match round
vision, where the four von Neumann neighbours keep the lattice's axes. `XXL-radius` sweeps R over 1, 1.5 and 3, so
the book's R = 1 is still measured.

### 5. Seasons by latitude

**Book setting:** the world splits into north and south halves at y = H/2, as now.

**xxl** (`season_gradient`, on when seasons are on). On the torus the two halves meet twice: at y = H/2 and at the
seam, y = 0. Both are boundaries between opposite seasons, so both are treated as equators (*my call*): a taper only
at y = H/2 would leave the rate jumping from α to α/β across the seam. Each site's winter weight is
λ(y) = |sin(2π·y / H)|: zero on both equators, one along the middle of each half (y = H/4 and 3H/4). Each period, a
site in the half that is in summer grows at the rate α. A site in the half in winter grows at α · β^(−λ(y)), so the
winter rate runs smoothly from α at the equators to the book's α/β along the middle. Summer and winter alternate
every γ periods, with the halves opposite, as in the book. The rate is continuous everywhere.

Only `winter_growback = "fractional"` is defined with the gradient; `validate` refuses `"pulse"`.

### 6. Generated landscape

**Book setting:** the xl map, with spice its east–west mirror.

**xxl** (`landscape = "generated"`, used only by `XXL-terrain`; the other xxl runs keep the xl map so that the rule
changes are measured on familiar ground). Two committed 500 × 500 files, `sugar-map-xxl.txt` and
`spice-map-xxl.txt`, in `sugarscape/maps/` (where Julia already reads maps) and in the xl map's format, each with its
SHA-256 in the contract. The generator is committed in `julia/` (standard library only, runnable as a script) and
builds each map as follows:
- a field that is the sum of 400 Gaussian bumps on the torus, each h·exp(−d²/(2r²)) at the wrapped distance d from
  its centre to a site's 0-based integer coordinates, with centres uniform, radii r log-uniform on 5–80 sites and
  heights h uniform on (0, 1], drawn from a fixed seed per map;
- capacities 0–4 cut from the field by rank: the lowest-valued sites get capacity 0, as many of them as the xl map
  has capacity-0 sites, and so on up, so each capacity covers exactly the xl map's number of sites. Total sugar is
  then the xl map's, and differences in results come from geography, not from more food.
- each cut lies midway between the two neighbouring field values it separates. The generator requires each such gap
  to be at least 10⁻⁹, far above the rounding a different machine or language could introduce. If one isn't, it
  moves to the next seed, and the contract records the seed used (*my call*: the xl map's 10⁻⁴ margin can't hold at
  exact counts, where neighbouring values of 250,000 lie about 10⁻⁵ apart).

The generator draws from its own small generator, SplitMix64, written out in the contract, rather than from Julia's
`Random` (*my call*). Julia doesn't promise that its random streams stay the same across versions, and the maps
must regenerate identically on any version, or in another language.

Spice is generated independently with its own seed, rather than as a mirror: the mirror is a fact of the book's
map, not a law. The generated maps wrap seamlessly across the torus, unlike the book's.

### 7. Combat (rule C)

**Book setting:** with the lattice look and no speed, combat is the book's rule C, as xl runs it.

**xxl** (user decision, 2026-10-28: combat is supported). Combat replaces movement, as in the book, and uses the xxl
look and step:
- **Candidates.** The agent's own site, and the looked-at sites (rule 1) that are empty or held by an agent of
  another tribe with no more sugar than the attacker. Own-tribe and wealthier occupants are passed over, as in the
  book. The reward is the site's sugar, plus min(α, the occupant's sugar) if occupied. With memory, remembered sites
  beyond vision are candidates as empty sites, with their remembered sugar.
- **Reach.** With speed, an occupied site is a candidate only within S: an attack happens this period, and an
  occupant farther away won't stay put (*my call*). Each candidate's value is rule 2's net value with the reward in
  place of the site's sugar, in the one-commodity form, since combat is sugar only. That includes travel cost and
  dropping sites the agent would starve on the way to.
- **Retaliation.** A site the agent would end this period on is unsafe when an agent of another tribe, other than
  the attacker and the victim, holds more sugar than the attacker's sugar plus that site's reward. Travel cost
  doesn't count, as in the book's threshold. The check uses a fresh look of the attacker's vision from that site:
  rule 1's look centred there, with no remembered sites.
- **Safe candidates.** A candidate within reach is safe when its own site is. A candidate beyond reach is safe when
  its walk has a safe landing site: rule 2's step, k = S, S − 1, …, 1, takes the first site that is empty and safe,
  with that site's sugar as the reward. The far target itself isn't checked, since the agent won't be there this
  period. A candidate with no safe landing site is passed over like any unsafe one (*my call*: an agent never walks
  into retaliation). Nobody is attacked on the way, and occupied steps are skipped, as in rule 2.
- **Choice.** The best safe candidate wins: highest value, then nearest, then at random. With no safe candidate the
  agent stays and harvests, as in the book. A strictly better candidate is checked for safety only when it would
  replace the best so far, as the book's code does. A candidate tied in value and distance is always checked first,
  and only safe ties count in the random draw, so each safe tie is equally likely.
- **Attack and harvest.** A defeated occupant loses min(α, its sugar) to the attacker and is killed, in the book's
  order. The attacker then moves onto the site and harvests its sugar as the book's rule C does: no production
  pollution, no income recorded.

Without speed (round vision alone) every candidate is within reach, and the agent jumps, as rule C does. Combat with
spice and combat with credit stay refused, as the book rules refuse them.

## Configuration and code

All of it is in `julia/`. Python is untouched.

- **`Config.xxl`:** an immutable `XxlRules` struct, or `nothing` for every existing config. It is the one field of
  the Julia `Config` with no Python counterpart, and the comment says so. The registry loader never sets it, so
  every exported experiment loads as before.
- **`XxlRules` fields and the values `to_xxl` gives them:**

  | Field | Book setting | `to_xxl` default |
  |---|---|---|
  | `vision_shape` | `"lattice"` | `"disc"` |
  | `speed` | `nothing` | `(1, 6)` |
  | `travel_cost` | 0 | 0.1 |
  | `memory` | 0 | 8 |
  | `memory_span` | 50 | 50 |
  | `word_of_mouth` | `false` | `true` |
  | `interaction_radius` | 1 | 1.5 |
  | `season_gradient` | `false` | `true` |
  | `landscape` | `"xl"` | `"xl"` |

- **`to_xxl(cfg)`** is `to_xl(cfg)` with `xxl` set to the defaults. It refuses anything `to_xl` refuses. For a base
  experiment without seasons, it turns the season gradient off, so a fingerprint never names a rule that can't apply.
- **Validation in `validate`:**
  - memory needs speed;
  - travel cost above 0 needs speed, word of mouth needs memory, and the season gradient needs seasons, rather than
    being ignored;
  - speed at most the lowest vision;
  - a generated landscape exactly when `sugar_map` is `sugar-map-xxl.txt`;
  - `"pulse"` winter refused with the gradient;
  - speed ≥ 1, travel cost ≥ 0, R ≥ 1, memory ≥ 0, span ≥ 1;
  - with disc vision, the vision limit becomes V < W/2: a disc can't overlap itself across the torus.
- **Random stream.** Every xxl draw is gated by its feature and comes after all existing draws: per agent, after the
  Chapter V draws; per period, inside the xxl hook. With every feature at its book setting, an xxl run makes exactly
  the draws its Julia xl run makes (Verification).
- **Hook points** in the Julia model, each dispatching to xxl code (file and names are the builder's) when the
  feature is on:
  - `move!` (rules 1–3), and `combat_move!` and `vulnerable` (rule 7);
  - `metabolize!` (travel cost);
  - `set_neighbors!`, `neighbors_of` and `mate!`'s birth sites (rule 4);
  - `in_sight` (rule 1);
  - `seasonal_growback!` (rule 5);
  - map loading and the spice map in the `Model` constructor (rule 6);
  - `spawn_at!` and `mate!`'s inheritance (the speed trait).

  `Agent` gains the speed trait and the memory. Book rule code is otherwise unchanged, and its hot paths must not
  slow down when `xxl` is `nothing` (the existing `test_hot_paths` still passes).

## Runner and experiments

- **`--xxl`** in `julia/run.jl`: runs the xxl version of each matching registered sugarscape experiment, with the
  same seeds and steps, into `results-julia-xxl/` (`--out` still overrides). It refuses Schelling and Ring World ids
  with the reason, and can't be combined with `--xl`. Timing, `machine.txt` and `--note` work as for xl.
- **Fingerprint:** `julia`, then an `xxl` line giving every `XxlRules` field, then the base experiment's xl
  fingerprint from the registry, then the SHA-256 of each generated map in use. A change to the xxl rules, the base
  experiment or the maps makes saved xxl results stale.
- **`XXL-…` experiments** (5 seeds each, *my call*, given the cost) have no Python counterpart, so they are defined
  in Julia, not in the exported `registry.toml`. Each is a base registry experiment, passed through `to_xxl` with
  overrides. `julia/run.jl XXL-speed` runs them like any id or prefix, into `results-julia-xxl/`.

  | Id | Base | What changes from the book settings |
  |---|---|---|
  | `XXL-vision` | II-4 | disc vision only |
  | `XXL-speed/c0`, `/c0.05`, `/c0.1`, `/c0.2` | II-4 | disc vision, speed (1, 6), travel cost c |
  | `XXL-memory/solo`, `/shared` | II-4 | the above at c = 0.1, plus memory, without and with word of mouth |
  | `XXL-radius/R1`, `/R1.5`, `/R3` | IV-A3 | full xxl defaults, interaction radius R |
  | `XXL-seasons/halves`, `/gradient` | II-7 | full xxl defaults, with and without the gradient |
  | `XXL-terrain/II-4`, `/IV-A3` | II-4, IV-A3 | full xxl defaults on the generated landscape |
  | `XXL-society/VI-1` | VI-1 | full xxl defaults (user decision: every Chapter VI rule at once) |
  | `XXL-combat/III-9` | III-9 | full xxl defaults, with combat (*my call*: one experiment to exercise rule 7) |

- **Report:** each `XXL-…` experiment's metrics against its base experiment's Julia xl run (`results-julia-xl/`), with
  the seed spread. It reads only result folders, like `bridge.report`, in whichever language the builder picks.

## Metrics

Added to xxl runs only, after the 46 columns every Julia result has, so regular and xl CSV layouts are unchanged:
- **`mean_moved`:** mean distance moved this period, per living agent.
- **`share_settled`:** share of agents that didn't move.
- **`clustering_1`, `clustering_10`, `clustering_50`:** the pair correlation of agent positions at distances 1, 10
  and 50, relative to the same number of agents placed at random on sites of capacity 1 or more. Above 1 means
  clustered.
- **With trade:** `regional_price_sd`, the standard deviation of mean log price across the 100 50 × 50 regions with
  trades this period, and `price_distance_slope`, the slope of |log price difference| against the distance between
  trades.
- **With memory:** `share_remembered_target`, the share of agents whose target was a remembered site beyond vision.
- **With seasons:** `mean_winter_weight`, the mean of λ(y) over agents, which tracks migration toward the equators
  in winter.

## Verification

- **No regular or xl change:** the existing Julia suite passes unchanged, the scenarios, lockstep and hot-path
  tests included, and so does the Python side's `pytest` in `julia/`, which checks that `registry.toml` and the
  fixtures are current. Python's own suite is untouched.
- **Exact reduction:** with every `XxlRules` field at its book setting, an xxl run's seed CSVs, in the columns the
  xl run has, are byte-for-byte its Julia xl run's, for II-4, IV-A3, III-1, III-9 and VI-1, over 50 periods. This
  pins the hooks and the random-stream gating.
- **Rule 1:** the drawn sites' distances follow the uniform-by-area law (radial CDF of (d² − n²) / (V² − n²),
  Kolmogorov–Smirnov test). Every site within the near radius n is looked at, n = 1 without speed. Partners in
  sight come from a fresh look after moving.
- **Isotropy:** on a landscape of independent random capacities 0–4 (statistically the same in every direction),
  the directions of disc-vision moves longer than one site are uniform over the 8 octants (chi-square; a move along
  an axis or a diagonal counts half to each side). Integer offsets share only the lattice's 8 symmetries, so finer
  sectors would fail even for a correct look (*my call*, after the plan review). Under the lattice look every move
  lies along an axis.
- **Rule 2:**
  - the net-value formula and its tie order on hand-built cases;
  - the step's straight-line walk and its fallbacks;
  - travel cost charged by distance actually moved;
  - candidates seen occupied are never targets; remembered sites beyond vision are, occupied or not;
  - a candidate the agent would starve on the way to is dropped, with and without spice;
  - speed = vision with c = 0 picks the same site as rule M on a hand-built landscape.
- **Rule 3:** trimming to the M best by net value from the new position, the span, a fresh look within vision,
  entries valued by two different agents with spice, and word of mouth copying the neighbour's first entry with
  its period.
- **Rule 4:** R = 1 gives the four von Neumann neighbours and R = 1.5 the eight Moore neighbours. Births land
  within R.
- **Rule 7:**
  - a weaker enemy within reach is attacked, loses min(α, its sugar) and dies;
  - with speed, one beyond reach is not attacked;
  - own-tribe and wealthier occupants are never attacked;
  - a candidate with a stronger enemy in a fresh look from it is passed over, a walk lands on the farthest safe
    step, and a far target with no safe step is passed over for the next best;
  - with round vision and no speed, combat jumps as rule C does;
  - lattice look, speed = vision and c = 0 pick the same site as the book's rule C on a hand-built landscape.
- **Rule 5:** the rate is continuous across y = H/2 and the seam, equals α at both equators and α/β at y = H/4 and
  3H/4, and is the book's when the gradient is off.
- **Rule 6:** the generator reproduces both committed files exactly; every cut's gap is at least 10⁻⁹; each
  capacity's site count equals the xl map's.
- **Validation:** each refusal listed above, and `--xxl` with `--xl`.
- **Results:** `docs/xxl.md` reports each `XXL-…` experiment from the report above, with the seed spread, and the
  Julia stepping time per period against the base experiment's xl run. These are findings, not pass/fail
  thresholds.

## Left to the builder

File layout and names in `julia/`; how the disc look and the step are made fast; the rounding rule, as long as it is
one rule, stated in the contract; where the generator lives in `julia/`; the report's language; small refactors
needed to thread `Config.xxl` through the runner.
