# Reproducing *Growing Artificial Societies*: a retrospective

This is a review of our attempt to rebuild Epstein and Axtell's Sugarscape (1996) from the book and
reproduce its results. The work ran from 2026-10-21 to 2026-10-22. The detailed evidence is in the
chapter records ([II](docs/replication/chapter-2.md), [III](docs/replication/chapter-3.md), [IV](docs/replication/chapter-4.md), [V](docs/replication/chapter-5.md),
[VI](docs/replication/chapter-6.md)), our reading of the book is in [book-notes.md](docs/book-notes.md), and the
design is in [the spec](docs/superpowers/specs/2026-10-21-sugarscape-design.md). Every number below is
taken from those records as of commit `7556424`.

## The short version

- **Every rule in the book is implemented**, with 96 registered experiments and 141 measured
  targets. Across the targets, **68 pass, 30 are near and 43 fail**.
- **Results driven by movement, the landscape, markets and local imitation reproduce well.** These
  include carrying capacity and selection on the plain sugarscape, wealth inequality, price
  formation and market thickness, credit networks, combat patterns, Schelling segregation, and Ring
  World's travelling groups.
- **Results driven by births do not.** Under the sex rule S as written, the population is too low
  and too damped. Fig III-1's steady population of ≈500 comes out at ≈360. Fig III-3's floor,
  Fig III-4's large swings and Fig III-5's extinction are missing, and so are Chapter VI's
  extinction (VI-2) and waves (VI-3). Inheritance doesn't raise inequality (III-7). One fitted
  departure, a fertility test at 0.83 of the birth endowment, fixes the level but not the
  dynamics.
- **Four other families fail**:
  - long-run carrying capacity (Figs II-5, IV-6), which matches at t≈50 but not at t=500;
  - migration waves (II-6, III-12);
  - endemic disease (V-2, VI-1);
  - full cultural absorption (III-8).
- **The population failures share one cause.** Our births respond to density less steeply than
  the original's: too few births when the society is sparse, too many when it is crowded. We
  located where this matters (the founding boom, thinned mountains, the falls after each peak).
  We ruled out more than twenty single causes within the text. What produces the original's
  behavior is still unknown.
- **Some of the book's results look fragile or internally inconsistent.** The strongest case: the
  book shows two runs of Fig III-1's rules that disagree, one booming to ≈570 and the other
  crashing to ≤172. And no implementation we know of gets the book's population figures from the
  published rule S alone: Kehoe's collapses, while MASON and Ascape match only by departing from
  the text (see [below](#book-results-that-may-not-be-robust-or-correct)).

## Scoreboard

| Chapter | Targets | Pass | Near | Fail | Strongest results | Weakest results |
|---|---|---|---|---|---|---|
| II Life and death | 31 | 19 | 12 | 0 | carrying capacity (II-4), Gini, selection, neighbors, metabolism-1 curve, seasons, pollution | Fig II-5 metabolism 2–3 at t=500, waves (II-6) |
| III Sex, culture, conflict | 25 | 11 | 4 | 10 | III-1 level (with the 0.83 departure), evolution, combat, friendship, proto-history dominance | III-3 to III-5 dynamics, inheritance (III-7), cultural absorption (III-8), waves |
| IV Trade | 41 | 19 | 8 | 14 | price formation, market thickness, lifespan effect, high-vision Gini, credit | carrying capacity with and without trade (IV-6), trade volume, reproduction runs IV-17/IV-18 |
| V Disease | 6 | 2 | 1 | 3 | V-1 clears | V-2's endemic level |
| VI Conclusions | 38 | 17 | 5 | 16 | Schelling, Ring World, VI-1 prices | VI-1's society, disease and credit; VI-2 extinction; VI-3 waves |
| **Total** | **141** | **68** | **30** | **43** | | |

**How to read the score.**
- **Bands are ours, not the book's.** The book reports single runs, usually as pictures, so each
  band is a tolerance we set before running. We never widened a band to make a target pass.
- **"Near" is generous for wide bands.** Near means the mean lies within the band widened by half
  its width on each side. For a proxy band that starts at or near zero, almost any value is near.
  So several near rows are plain failures: II-6's waves (×2), III-12 and III-13, V-2's sick share,
  IV-15's trade volume.
- **Some passes depend on a departure from the book.** III-1's level, IV-14 and III-15's rare
  extinctions pass only because the default fertility threshold is the fitted 0.83, not p.55's 1.0. Under the book's rule (the
  `VAR-book` experiments) III-1 settles at 360, a near.
- **Some proxies are weak.** Ring World's "size bounded by the most nearsighted" passes trivially:
  groups never grow large enough to test the bound.

## How the work was done

**Sources.**
- Our reading of the book is in book-notes.md, rule by rule, with page and footnote citations.
- The full scan supplied Appendices B and C.
- Kehoe's formal specification (2016) served only as a tie-breaker where the book is silent; where
  it contradicts the book, we followed the book.
- The 50×50 capacity map is the widely circulated `sugar-map.txt`, checked against Fig II-1. It is
  identical, up to rotation, to MASON's. The spice map is that map mirrored east–west (Fig IV-1).

**Anti-goals, fixed in the spec before any code:**
- no silently chosen values: every choice the book leaves open is a named, documented setting;
- no following Kehoe against the book;
- no tuning stated parameters to match a number.

**Build order.** Each chapter followed the same steps: a written plan, then rules implemented
test-first, then an experiment per figure or animation, then a multi-seed replication report,
then a whole-branch review and a fix pass, then the chapter record.

**Tests.**
- 282 fast tests cover two things:
  - rules checked against the book's worked examples: Appendix C's welfare example, Table V-1's
    immune response, Fig IV-2's trade, the growback, seasonal and diffusion formulas;
  - invariants: one agent per site, no negative sugar, trade conserves goods and raises both
    welfares, loans balance, births minus deaths match the population.
- 141 slow tests, one per target.

**Determinism.**
- One seeded generator drives each run.
- Results are cached by a fingerprint of the configuration.
- Stream-pin tests catch any change to the random sequence.
- After every change to a default, earlier chapters were re-run, and their records say which rows
  stayed identical.

**Diagnostics.**
- Once the population gap appeared, we spent most of 2026-10-22 on diagnostics. Probes patched the
  model from outside, and none changed it.
- Book curves were digitized from the page images (Figs III-1, III-3, III-4, III-5, VI-2, VI-3).
  Agents and age bins were counted in animation frames.
- We inverted the book's curves to infer its births.

**Decisions made with the user:**

| Date | Decision | Effect |
|---|---|---|
| 2026-10-21 | Carrying capacity is measured at t=500, the asymptote | Fig II-5's metabolism-2 and -3 points and Fig IV-6 stay near or fail; both match at t≈50 |
| 2026-10-21 | Fertility tests sugar only (p.55), not sugar and spice | Requiring both had wiped out 4 of 5 seeds in IV-14, IV-17 and IV-18 |
| 2026-10-22 | Founders with finite lives start at ages U[0, max age) | Matches Animation III-1's first histogram, VI-2's early births and Ascape's code. It also lowered III-1's early curve and killed IV-14, IV-17 and IV-18 |
| 2026-10-22 | Default fertility threshold 0.83 of the birth endowment, fitted to III-1's level alone; the book's 1.0 runs as `VAR-book` | III-1 and IV-14 pass. III-15's extinctions fall to the book's rare level. The dynamics rows don't change |

## What reproduced

**Chapter II: the landscape.**
- **Carrying capacity (II-4):** 233 against 224.
- **Wealth inequality (II-4 Gini):** initial Gini 0.230, exactly the book's figure, then 0.477
  late against 0.503.
- **Selection:** metabolism falls to 1.85 (book 1.8).
- **Neighbors:** 0.80 per agent (book 0.9).
- **Fig II-5's metabolism-1 curve:** all five points within 4%.
- **Seasonal migration (II-7):** high-vision agents migrate, and low-vision agents hibernate.
- **Pollution (II-8):** agents abandon the polluted peaks and return after diffusion.
- **Initial endowment:** the book never states it for these runs. Only 25–50 reproduces Fig II-4's
  curve: RMS error 11 agents, against 49 and 57 for the other ranges the book uses.

**Chapter III: evolution, culture and combat.**
- **Evolution under S:** mean vision 5.6 at t≈900 (book 5.3), and metabolism falls to 1.0 (book
  1.0).
- **III-1:** fluctuations of 6.5% (book under 10%). The level is 478 with the 0.83 threshold.
- **III-4:** its damped cycle has the book's period, 116 against ≈125.
- **Combat (III-9, III-11, III-14):** every run ends in one of the book's three patterns.
  Same-tribe war persists, and assimilation prevents hegemony in about half the runs.
- **Friendship:** best-friend closeness 0.98 (book 0.91).
- **Proto-history (III-15):** Red dominates both mountains in 20% of runs (book ≈25%), and
  extinction is rare (10%).

**Chapter IV: trade and credit.**
- **Price formation:** mean price ≈1.0, and ln-price dispersion falls to 0.047 by t=1000 (book
  ≈0.05).
- **Market thickness:** vision 1–15 gives a dispersion of 0.014 (book ≈0.03).
- **Lifespan:** dispersion falls with lifespan, 0.45 / 0.30 / 0.22 / 0.11 against the book's
  ≈0.5 / 0.3 / 0.2 / 0.15.
- **Gini at mean vision 10–14.5:** with and without trade.
- **Trade with reproduction (IV-14):** dispersion 0.39 (book ≈0.37).
- **Pollution:** a sugar-price spike follows pollution (2.3, book ≈3.5).
- **Credit networks (IV-A5):** 150 active loans and 29 agents both lending and borrowing (book
  frame: 187 and 21). Hierarchies run 6–7 levels deep (book "as many as five").

**Chapter V: disease.**
- **V-1:** the society rids itself of disease, with a sick share of 0.6% at t=450–500.
- **Starting load:** 4.4 active diseases per agent (book 3.41).

**Chapter VI: the wider models.**
- **Schelling (VI-4 to VI-7):** 5 of 6 rows pass. The book's point is reproduced: a small change in
  individual preference makes a large change in segregation.
- **Ring World (VI-8, VI-9):** all 9 rows pass. Agents form ≈5–6 travelling groups that move ≈6×
  faster than loners, and they leapfrog. A megagroup breaks up within ≈10 periods.
- **VI-1 prices:** mean ≈1 and dispersion 0.33 (book 0.3–0.4).
- **VI-3 against VI-2:** over the first 75 periods the trading society tracks the non-trading one
  (ratio 1.11), as the book says.

## What did not reproduce

### 1. Population dynamics under the sex rule (the largest family)

| Result | Book | Ours (defaults) | Under the book's threshold (`VAR-book`) |
|---|---|---|---|
| III-1 steady population | ≈500 | 478 (fitted) | 360 |
| III-1 early boom, t=20 / 85 | 470 / 570 | 398 / 208 | 356 / 136 |
| III-3 floor / period / agents ever lived | ≈250 / ≈200 / ≈12,500 | 33 / 438 (3 of 5 seeds) / 3,690 | 18 / 493 / 1,613 |
| III-4 oscillation range | ≈1,000 | 106 | 120 |
| III-5 extinction | yes, t≈610 | 0 of 10 seeds | 0 of 10 |
| III-7 Gini with inheritance / vision | 0.743 / 4.3 | 0.31 / 5.19 | 0.35 / 5.13 |
| IV-17, IV-18 (trade or foresight with S) | run 1,000 periods | 4 of 5 and 5 of 5 seeds extinct | — |
| VI-1 population at t≈50 | ≈155 | 41; extinct in 5 of 5 seeds | — |
| VI-2 crash at t≈20 / extinction | ≈130 / yes | 213 / 1 of 10 seeds | — |
| VI-3 minimum / first peak / waves | ≈65 / ≈1,190 / 700–1,200 | 36 / 308 / 204–534 | 272 first peak |

**What we established, in the order we found it** (details in the [Chapter III record](docs/replication/chapter-3.md)):

1. **Births limit the population; food doesn't.** In III-1 nobody starves after t≈300. About 60% of
   all harvest is destroyed when agents die of old age. Only 43% of fertile-age agents pass the
   wealth test.
2. **The early boom is wealth-limited.**
   - The founders are unselected (mean metabolism 2.5), so they burn more than they harvest. Only
     their first child is "free".
   - Fig III-1 needs ≈6.5 births per period to reach 570 by t=85. We get ≈2.5. Free contact
     everywhere reaches only 3.2.
3. **The long-run level is set by women's wealth cycle.**
   - Nearly every woman stops at two children (81% have exactly two). Re-earning half her
     endowment takes ≈12.5 years, including the wait for a partner.
   - The population therefore settles where net income is ≈1.45 per year. That happens at N≈350
     on our map.
4. **No movement detail the text allows raises income at high density enough.** Greedy movement
   grazes the peaks bare and leaves the lowlands unharvested. Ignoring "nearest" in M lifts III-1 to
   452, but p.25 forbids it and it breaks Fig II-5 at t≈50.
5. **Partners are met by near-random mixing.** A fertile agent waits ≈8 periods. Spacing and kin
   don't change that. Moore neighbors add 2–6%, and a radius of 2 gives 417.
6. **III-3's floor is a lost mountain.**
   - The founding crash takes each mountain down to 10–50 agents.
   - Below ≈30–40 agents, births fall short of deaths. This is an Allee effect: partners stop
     meeting.
   - An emptied mountain is never re-founded. One mountain holds half of what two hold.
7. **III-4's swings are an old-age echo.**
   - Inverting the book's curve shows that it needs no starvation: births per agent are ≈3.6×
     higher on the rise than on the fall at the same density.
   - The memory behind this is the delay to fertility, and our rules have it too. Our births
     respond to density as the book's do, except in the lowest band (23 against 32 per period).
   - Our model is **bistable**, with a quiet equilibrium near 1,170 and the book's large cycle. A
     slow, smeared founding boom puts our runs on the quiet side: 0 of 20 ordinary runs lock into
     the cycle.
8. **III-5's extinction needs births shut off for ≈40 periods after each peak.** That is long
   enough for a boom's women to age out of fertility. Our agents leave each peak with income in
   hand: net income stays positive up to N≈1,700. A brake on current density alone clamps the
   population instead of crashing it.

**Ruled out as single causes, within the text:**
- **Founders:** founder ages (age 0, spread); founders' sugar drawn apart from their recorded
  endowment; a fertility margin for founders only; founders' metabolism 1–2.
- **Child endowment and threshold:** the child's endowment set to one parent's gift (the lattice
  fills); a child's threshold redrawn at random; Ascape's cheap children; a cheaper child at the
  book's threshold; p.65's 10–40 read as a fertility threshold rather than an endowment range
  (close to MASON's reading); inherited fertility ages.
- **Mating:** mating before metabolism; Moore mating neighbors; fertility end inclusive; the
  agent's own fertility tested once per turn; the child placed at the nearest empty site.
- **Lifespan:** every maximum age set to 80; lifespan drift.
- **Food and movement:** higher regrowth (G1.5, G2); the current site never a destination;
  "must move"; spacing and kin; a lowered food ceiling (every capacity-1 site set to 0).
- **Density brakes:** births blocked above a population cap; lack of room for the baby.

**Levers that work, all departures from the text:**
- a fertility threshold below the endowment: 0.83 fits the level, 0.5 fits the boom;
- unrestricted contact: 509 in III-1, and it locks III-4 into the cycle in 4 of 10 culled runs;
- ignoring "nearest" in M: 452 in III-1;
- removing the parents' cost: the lattice fills.

None of them reproduces the boom, the level, the swings and the extinction together.

### 2. Long-run carrying capacity (Figs II-5 and IV-6)

- **Fig II-5:** the metabolism-2 points run 10–20% low at t=500. So do three metabolism-3 points:
  8 of Chapter II's 12 near rows.
- **Fig IV-6:** with and without trade, it runs ≈25% low (9 fails, 1 near). Trade's ≈20–30% lift
  is reproduced.
- **At t≈45–60 both figures match.** All 18 Fig II-5 points are within ±5%. Of the ten Fig IV-6
  points, all but one are within ±5%, and that one is +19%.
- **In the two-commodity model the long-run number is a survival fraction, not a capacity.**
  Survivors at t=500 scale with the starting population (≈0.25–0.32 of it), which the book doesn't
  state for Fig IV-6. This also explains IV-3's low trade volume: 34 trades per period against
  ≈150, from 66 agents.

### 3. Migration waves (II-6, III-12, III-13)

- **No coherent diagonal waves form.** Neither the text's 400-agent block nor the 284-agent block
  counted from the animation produces them. The NE share at t=200 is 0.05, against a band of
  0.15–1.
- **III-12's blocks settle on their own peaks**, so III-13 has no wave to suppress.
- **Ruled out:** the block layout, the endowment, and "must move".
- **Reviewer's mechanism note:** behind the front, regrown sites tie with fresh sites ahead. With a
  random scan order (fn 8), front agents step back as often as forward.

### 4. Endemic disease (V-2, VI-1)

- **The book's V-2 stays endemic** at ≈0.86 active diseases per agent. **Ours clears like V-1**:
  0.02 per agent by t=500.
- **Each disease starts only 1–3 bits from its nearest window** in a 50-bit immune string. So it is
  learned in a few periods, and each infection passes to only ≈0.17 others.
- **No reading of E sustains V-2 while V-1 still clears.** We tested immune carriers, a one-period
  lag, one flip per period in total, lifelong disease sets, more contacts, and no fee.
- **VI-1** inherits the same failure: its disease clears within ≈5 periods.

### 5. Cultural absorption (III-8, III-15)

- **III-8:** at t=6,000 each side sits at 91–98% one color, but a few holdouts never convert. No
  run becomes all one color (book: all Blue after ≈2,700). The tag dynamics behave like a voter
  model, which fits the book's process, but they finish more slowly.
- **III-15:** Red and Blue end on opposite mountains in 0 of 20 runs (book: somewhat under half).
  Our society never spills into the lowlands, as the book's does.

### 6. Thin markets and small societies

- **These all follow from small, sparse populations:**
  - dispersion at vision 1: 0.16 against ≈0.3 (IV-7);
  - with cultural preferences: 0.18 against ≈0.45, and 267 trades per period against ≈1,000
    (IV-15);
  - Gini without trade at low vision: 0.30 against 0.43 (IV-13);
  - slow price recovery after pollution, resting on 5–29 trades per period (IV-A3).
- **VI-1's credit is nearly absent:** 0.25 active loans against ≈215. 83% of credit requests find
  no potential lender next door. Our creditworthiness test counts sugar income only, and many
  agents gather mostly spice.

### 7. Smaller misses

- **Vision under selection:** mean vision at t=500 is 3.79 against the book's single run of 4.1
  (II-4). Metabolism selection matches.
- **Hibernation:** the low-vision hibernation proxy is 0.22 against a band up to 0.15 (II-7).
- **VI-5 against VI-4:** VI-5 is 1.20× as segregated as VI-4, where the book says "comparable".
- **V-1:** one distinct disease still circulates in a few seeds at t=500.

## What worked

- **Reading the book before writing code.** Book-notes.md, with citations, settled most questions
  before they became bugs. Later disputes went back to the page, as when p.28's ridge passage
  decided that the agent's own site wins ties.
- **Writing the anti-goals down.** "Don't tune to the target" kept the records honest:
  - the only fitted value (0.83) was fitted to a single number, frozen, and validated out of
    sample;
  - it was adopted only by explicit decision;
  - the book's rule still runs beside it.
- **Unit tests built from the book's own worked examples.** They pinned the rules where the book is
  exact, so later failures could be blamed on readings, not on arithmetic.
- **Determinism and regression re-runs.** Seeded streams, fingerprint caching and stream pins made
  "every row identical" a checkable claim after each default change. They also made `VAR-book`
  reproduce the old default exactly.
- **Whole-branch reviews.** They caught real defects:
  - the order of transmission and immune response within E;
  - pollution swamping the two-commodity welfare;
  - the "carrying capacity" that is really a survival fraction;
  - spice in the fertility test.
- **Treating the book's figures as data.** Digitizing curves and counting animation frames turned
  headline numbers into trajectories. That is how we found that Fig III-1 and Animation III-2 are
  different runs, that III-4's swings need no starvation, and that III-5's troughs cap births at
  ≈1 per period.
- **Inverting the book's curves.** Births equal the population's change plus old-age deaths, which
  gave the book's implied births, its lag structure and its response curve. That let us compare
  mechanisms, not just outcomes.
- **Counterfactual bounds.** Global contact, doubled regrowth and θ sweeps put limits on what any
  detail in a given category could achieve. Whole categories could then be ruled out at once.
- **Paired seeds for comparative claims.** VI-3 against VI-2, and the Schelling ratios, compare
  identical starting societies.

## What didn't work

- **Reading single-run figures as targets for multi-seed means.** The book's figures are single
  runs of a model that, in our hands, is knife-edged (III-3: whether both mountains survive) and
  bistable (III-4). A band around one run's value can't tell "wrong model" from "different
  realization".
- **Some statistics weren't reliable:**
  - **Period:** the first autocorrelation peak gives 201–1,701 on irregular series. Peak spacing
    from smoothed turning points was more informative.
  - **Status rule:** near means little for wide proxy bands.
  - **Measurement time:** we never settled when "carrying capacity" was read.
- **Faithful changes that hurt the overall fit.** Spread founder ages are better supported by the
  book's frames. Yet they lowered III-1's early curve, extinguished IV-14, IV-17 and IV-18, and
  undid the calibrated threshold's out-of-sample gains, which had been measured with age-0
  founders. The rules are tightly coupled, so one-at-a-time changes moved rows in chapters far from
  the one under study.
- **Searching for a single cause.** Over a day of probes ruled out more than twenty single causes
  of the population gap. Each was cheap, but the yield fell steadily, and an interaction between
  readings can't be found this way.
- **Diagnostics that live outside the repository.** The probe scripts behind the diagnostic tables
  sit in a session scratchpad, not in git. The tables are recorded, but most can't be regenerated
  from the repo.
- **Proxies for qualitative claims.** Some proxies are sharp (Ring World's groups), but others are
  weak or permissive (the nearsighted bound, II-7's hibernation band). Each one is our own
  construct.

## How the model could be changed to reproduce more

These are grouped by how far they move from the book. None has been adopted, except where noted.

### A. Measurement, no model change

1. **Read carrying capacity at t≈50 as well as t=500.** This would turn 8 of Chapter II's near rows
   and most of Fig IV-6's fails into passes. The evidence that the book read its sweeps early is
   strong (18 of 18 Fig II-5 points within ±5%). It is a user decision to revisit, not a fix.
2. **State Fig IV-6 relative to the starting population**, since the long-run number scales with
   it.
3. **Report the book's single runs as frequencies.** For example: the share of seeds that keep both
   mountains (III-3), lock into the large cycle (III-4) or die out (III-5). This separates "never
   happens" from "happens in some runs".

### B. Departures already shown to help (each at a cost)

| Change | Helps | Costs |
|---|---|---|
| Fertility threshold 0.83 (**adopted**) | III-1 level, IV-14 survival, III-15 extinction | Contradicts p.55; no help with the dynamics |
| Age-0 founders with θ=0.83 | III-3 floor 174, agents ever lived 8,739, III-4 range 304, VI-3 floor 705 and first peak 848 | Contradicts Animation III-1's ages and VI-2's early births |
| Wider or unrestricted mating contact | Low-density births reach the book's: the III-4 response curve and the first peak (≈1,560 at t≈90); 4 of 10 culled III-4 runs lock into the book's cycle | Contradicts von Neumann mating (p.56); raises III-1's level, so θ would need re-fitting |
| Ignoring "nearest" in M | III-1 452; spacing 0.97 (book 0.9) | Contradicts p.25; Fig II-5 +12–14% at t≈50 |
| Lifelong disease sets | V-2 endemic (2.05 per agent) | V-1 becomes chronic; V-2's population crashes to 13 |

### C. Untested candidates, most promising first

1. **Mate search within vision**, between radius 2 (tested: 417) and global contact (tested: 509).
   It targets the low-density Allee effect directly. That effect sits behind III-3's lost
   mountains, the low first band of III-4's response curve, and the slow founding boom.
2. **A gift that depends on wealth, with a threshold that doesn't.** For example, parents give half
   their *current* sugar (Kehoe's prose reading), while the child's threshold is drawn from the
   founders' range. Children born in poor, crowded times would then come of age below threshold.
   That gives exactly the lasting post-peak deficit III-5 needs. We redrew thresholds only with
   fixed gifts, and never tied the gift to current wealth. p.55 states the gift plainly, so this is
   a departure.
3. **Ascape's departures as one package:** random founder ages, children costing at most 5 sugar,
   and fresh thresholds. We probed each alone, never together. Ascape was built at Brookings, where
   the book's authors worked, so its choices are weak evidence of what the original code did.
4. **Rule-by-rule sweeps** (all agents move, then all mate), as Kehoe orders them. The text implies
   per-agent turns, and we tested only mating before metabolism. This is worth one diagnostic run.
5. **For waves:** growback before the agents move instead of after; the map's corridor capacities
   checked against Fig II-1 cell by cell; integer sugar on regrown sites.
6. **For disease:** passing every active disease to each neighbor instead of one at random. This
   departs from p.145, but spread is the measured bottleneck: each infection reaches ≈0.17 others,
   and endemic disease needs above 1.
7. **For VI-1's credit:** count sugar and spice income in the creditworthiness test.

### D. Outside evidence

- **Run the Ascape and MASON Sugarscapes** on our map and compare III-1 and III-4 curves directly.
  MASON reports general matches for III-1, III-3 and III-5, but only with child placement that
  ignores occupancy. We don't have the original code (about 20,000 lines, Macintosh, Appendix A).
- **Ask the authors.** Kehoe reached the same impasse and concluded the rule must be clarified by
  the original developers.

## Book results that may not be robust or correct

These are the claims our evidence casts doubt on, with how strong that evidence is.

| Claim | Why we doubt it | Evidence |
|---|---|---|
| Fig III-1's early boom to ≈570 | The book's other run of the same rules (Animations III-2/III-3, the source of Fig III-2) crashes to ≤172 agents on the peaks. The boom is one realization, not a property of the rules | Strong (internal) |
| Fig III-1's level of ≈500 | That same animation run settles at ≈670–1,020 | Strong (internal) |
| The population figures follow from rule S as published | No implementation we know of gets them from the text alone. Ours and Kehoe's (collapse before t=2,500) don't. MASON matches only with child placement that ignores occupancy. Ascape departs from the text on cost, ages and thresholds. The figures probably depend on unstated details of the original code | Strong that the text is incomplete |
| One founder setup underlies the figures | Animation III-1's ages and VI-2's first-period births need spread ages. Fig III-3's opening (rise to ≈450, crash to ≈250) fits age-0 founders | Medium |
| Fig III-4's large cycle is the typical outcome | In our model the cycle is one of two stable states, reached only after a fast, compact boom (0 of 20 ordinary runs). Whether the original lands there reliably is unknown; the book shows one run | Medium (depends on our model) |
| Fig III-3's floor of ≈250 | It needs both mountains to survive the founding crash, a knife-edge in our runs | Medium (depends on our model) |
| Fig III-5's extinction at t≈610 | It needs births near zero for ≈40 periods after each peak. It may well be one realization, and its frequency is unstated | Weak to medium |
| Fig II-5 values are asymptotic "carrying capacities" | Our populations match all 18 points at t≈45–60 and fall 10–20% below at t=500 on the metabolism-2 and -3 curves | Medium: either the book read early, or our long-run decline is wrong |
| Fig IV-6's carrying capacities | In the two-commodity model the long-run population scales with the unstated starting population | Strong in our model |
| Animation V-3's first-frame statistics | A spread of 0.62 at a mean of 3.41 is impossible for 10-disease draws, which give 1.2–1.5 | Strong (arithmetic) |
| V-2's endemic state under the stated parameters | Diseases 1–3 bits from a window of a 50-bit string are learned faster than they spread. No reading sustains V-2 while V-1 clears | Medium |
| Animation II-6's set-up | The text says 400 agents "exactly as in II-2"; frame 1 shows a 20×19 block of ≈284 | Strong (internal) |
| III-8's "all Blue after ≈2,700" | One typical run of a voter-like process, whose absorption times are widely spread | Weak to medium |
| VI-4 and VI-5 are "comparable" | The book's own pictures of the two differ | Weak |
| III-7's Gini of 0.743, fn 32's frequencies | Single figures or rough shares, with no count of runs | Weak |

## Recommended next steps

1. **Check the diagnostic probe scripts into the repository** (for example under `diagnostics/`),
   so every table in the records can be regenerated.
2. **Fix the statistics:** a near rule that doesn't reward wide proxy bands; peak spacing from
   turning points in place of autocorrelation for periods.
3. **Report carrying capacity at both t≈50 and t=500**, if the user reopens that decision.
4. **Turn single-run claims into frequencies over 20 or more seeds** (III-3, III-4, III-5, VI-2).
5. **Test candidates C1–C3 first**, together and as labelled departures. They aim at the one
   mechanism behind most remaining failures: births that respond steeply to density.
6. **Get outside evidence:** run Ascape or MASON on our map, or ask the authors.

## Where things are

| What | Where |
|---|---|
| Book reading, by rule and page | [docs/book-notes.md](docs/book-notes.md) |
| Design and anti-goals | [docs/superpowers/specs/2026-10-21-sugarscape-design.md](docs/superpowers/specs/2026-10-21-sugarscape-design.md) |
| Chapter plans | [docs/superpowers/plans/](docs/superpowers/plans/) |
| Chapter records (results, choices, diagnostics) | [chapter-2.md](docs/replication/chapter-2.md), [chapter-3.md](docs/replication/chapter-3.md), [chapter-4.md](docs/replication/chapter-4.md), [chapter-5.md](docs/replication/chapter-5.md), [chapter-6.md](docs/replication/chapter-6.md) |
| Rules | `sugarscape/rules/`; Schelling and Ring World in `sugarscape/variants/` |
| Experiments and targets | `experiments/registry.py`, `replication/targets.py` |

```bash
python -m pytest -q
```

```bash
python -m replication.report --chapter III --jobs 8
```

```bash
python -m experiments.run III-4 --seeds 5 --jobs 8
```

The first command runs the fast suite. The second writes the replication table for one chapter;
add `--rerun` to ignore cached results, and use `--chapter VAR` for the book-rule variants. The
third runs one experiment, saving CSV and PNG output under `results/`.
