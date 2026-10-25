# Reproducing *Growing Artificial Societies*: a retrospective

This is a review of our attempt to rebuild Epstein and Axtell's Sugarscape (1996) from the book and
reproduce its results. The work ran from 2026-10-21 to 2026-10-22, with four follow-ups on 2026-10-23.
The [first](#follow-up-2026-10-23) carried out this review's recommendations, and each later one
([second](#second-follow-up-2026-10-23), [third](#third-follow-up-2026-10-23),
[fourth](#fourth-follow-up-2026-10-23)) took the next steps the one before left. The detailed evidence is in the
chapter records ([II](docs/replication/chapter-2.md), [III](docs/replication/chapter-3.md), [IV](docs/replication/chapter-4.md), [V](docs/replication/chapter-5.md),
[VI](docs/replication/chapter-6.md)), our reading of the book is in [book-notes.md](docs/book-notes.md), the
design is in [the spec](docs/superpowers/specs/2026-10-21-sugarscape-design.md), and the probe scripts are in
[diagnostics/](diagnostics/README.md). Every number below is taken from those records as of the follow-up.

## The short version

- **Every rule in the book is implemented**, with 96 registered experiments and 169 measured
  targets. Across the targets, **99 pass, 27 are near and 43 fail**, under the default rule S since
  2026-10-23 (integer gifts and partners in sight; below). Under the previous default, a fitted
  threshold of 0.83, they scored 95 / 22 / 52. (Before the follow-up added 28 early
  carrying-capacity rows and tightened "near", 141 targets scored 68 / 30 / 43.)
- **Results driven by movement, the landscape, markets and local imitation reproduce well.** These
  include carrying capacity and selection on the plain sugarscape, wealth inequality, price
  formation and market thickness, credit networks, combat patterns, Schelling segregation, and Ring
  World's travelling groups.
- **Results driven by births do not.** Under the sex rule S as written, the population is too low
  and too damped. Fig III-1's steady population of ≈500 comes out at ≈360. Fig III-3's floor,
  Fig III-4's large swings and Fig III-5's extinction are missing, and so are Chapter VI's
  extinction (VI-2) and waves (VI-3). Inheritance doesn't raise inequality (III-7). A fitted
  fertility test at 0.83 of the birth endowment fixed the level but not the dynamics.
- **The default rule S now keeps p.55's threshold, with two changes** (user decision, 2026-10-23):
  each parent's gift rounds down to a whole unit, and partners are the agents in sight, not only the
  four neighbors (C1). Nothing is fitted. III-1's level, III-3's floor and VI-3's minimum, floor
  and ceiling pass; III-4's swings and IV-17's and IV-18's survival come near. III-5's and VI-2's
  extinctions, VI-2's crash, the periods of III-3 and VI-3, and III-7 are still missing. Integer
  gifts may be the original's own arithmetic; partners in sight depart from p.56.
- **Four other families fail**:
  - long-run carrying capacity (Figs II-5, IV-6), which matches at t≈50 (27 of 28 points pass) but
    not at t=500;
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
  published rule S. Kehoe's collapses. MASON's own code, run on its own configs, misses III-1, III-3
  and III-5 as ours does. Ascape's code, which departs from the text, reproduces Fig III-4's cycle
  but misses the other three by more than we do (see
  [below](#book-results-that-may-not-be-robust-or-correct)).
- **One outside implementation points to a cause.** Watts' SugarscapeCW reaches Fig III-1's level and
  most of Fig III-4's swings at p.55's threshold, because it halves endowments in integers. The same
  truncation in our model, registered as `VAR-intgift`, lifts III-1 to 454 (pass) and III-4's range
  from 120 to 526, with nothing fitted. If the original kept sugar as integers, this is a reading of
  p.55, not a departure. Combined with C1 (mate search within vision), it passes 9 of the 18
  population targets, more than any variant, fitted or not. III-5's extinction is still missing
  ([fifth](#fifth-follow-up-2026-10-23) and [sixth](#sixth-follow-up-2026-10-23) follow-ups).

## Scoreboard

| Chapter | Targets | Pass | Near | Fail | Strongest results | Weakest results |
|---|---|---|---|---|---|---|
| II Life and death | 49 | 37 | 9 | 3 | carrying capacity (II-4), Gini, selection, neighbors, Fig II-5 at t≈50 (18 of 18), seasons, pollution | Fig II-5 metabolism 2–3 at t=500, waves (II-6), hibernation (II-7) |
| III Sex, culture, conflict | 25 | 11 | 5 | 9 | III-1 level, III-3's floor, evolution, III-4's period, combat, friendship, proto-history dominance | III-3's period, III-4's range (near), III-5's extinction, inheritance (III-7), cultural absorption (III-8), waves |
| IV Trade | 51 | 28 | 9 | 14 | price formation, market thickness, lifespan effect, high-vision Gini, credit, Fig IV-6 at t≈50 (9 of 10) | Fig IV-6 at t=500, trade volume, reproduction runs IV-17/IV-18 (near) |
| V Disease | 6 | 2 | 0 | 4 | V-1 clears | V-2's endemic level |
| VI Conclusions | 38 | 21 | 4 | 13 | Schelling, Ring World, VI-1 prices, VI-3's minimum, floor and ceiling | VI-1's society, disease and credit; VI-2's crash and extinction; VI-3's period |
| **Total** | **169** | **99** | **27** | **43** | | |

**How to read the score.**
- **Bands are ours, not the book's.** The book reports single runs, usually as pictures, so each
  band is a tolerance we set before running. We never widened a band to make a target pass.
- **"Near" was generous for wide bands until 2026-10-23.** It meant within the band widened by half
  its width on each side, so for a band starting near zero almost any value was near. The margin on
  each side is now the smaller of half the width and a quarter of that bound's magnitude. Nine rows
  that were plain failures now say so: II-6's waves (×2), II-7, III-12, III-13, IV-15 (×2), V-2's
  sick share and VI-1's lenders-and-borrowers.
- **Carrying capacity is scored twice.** Each Fig II-5 and IV-6 point is read at t=500 (the
  asymptote, the user's 2026-10-21 decision) and at t≈50 (where the book's sweeps match ours), and
  both count.
- **Some passes depend on a departure from the book.** III-3's floor, VI-3's minimum, floor and
  ceiling, IV-14 and III-15's rare extinctions pass only with partners in sight (C1), which departs
  from p.56. III-1's level needs integer gifts or C1. Under rule S as written (the `VAR-book`
  experiments) III-1 settles at 360, a near. The former default, a fitted threshold of 0.83, runs as
  `VAR-fit83`.
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
- 287 fast tests cover three things:
  - rules checked against the book's worked examples: Appendix C's welfare example, Table V-1's
    immune response, Fig IV-2's trade, the growback, seasonal and diffusion formulas;
  - invariants: one agent per site, no negative sugar, trade conserves goods and raises both
    welfares, loans balance, births minus deaths match the population;
  - the replication statistics and status rule themselves.
- 169 slow tests, one per target.

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
| 2026-10-22 | Default fertility threshold 0.83 of the birth endowment, fitted to III-1's level alone; the book's 1.0 runs as `VAR-book` (replaced 2026-10-23) | III-1 and IV-14 pass. III-15's extinctions fall to the book's rare level. The dynamics rows don't change |
| 2026-10-23 | "Near" capped at a quarter of the nearer bound | Nine near rows become fails; no status improves |
| 2026-10-23 | Carrying capacity also read at t≈50, counted in the totals | 27 of the 28 new rows pass; the t=500 rows are unchanged |
| 2026-10-23 | Run MASON's own Sugarscape | Built from its project archive; see [Follow-up](#follow-up-2026-10-23) |
| 2026-10-23 | Register C1+C3fit as the labelled variant `VAR-c1c3fit` | Rule S gains three options, off by default (`mate_contact`, `child_gift`, `child_threshold`); the report scores the variant on every population target. Defaults and totals unchanged |
| 2026-10-23 | Register integer gifts as the labelled variant `VAR-intgift` | Rule S gains a fourth option, off by default (`gift_rounding`); p.55's threshold, nothing fitted. Defaults and totals unchanged; see [sixth follow-up](#sixth-follow-up-2026-10-23) |
| 2026-10-23 | Register integer gifts + C1 as `VAR-intgiftc1` | 9 of 18 population targets pass, nothing fitted. Defaults and totals unchanged; see [seventh follow-up](#seventh-follow-up-2026-10-23) |
| 2026-10-23 | Default rule S: p.55's threshold with integer gifts and partners in sight (C1); the fitted 0.83 runs as `VAR-fit83` | 99 / 27 / 43 of 169 (was 95 / 22 / 52). III-3's floor and VI-3's minimum, floor and ceiling pass; III-4's swings and IV-17/IV-18 come near; III-1's fluctuations and III-15's Red dominance slip to near. Every experiment re-run |

## What reproduced

**Chapter II: the landscape.**
- **Carrying capacity (II-4):** 233 against 224.
- **Wealth inequality (II-4 Gini):** initial Gini 0.230, exactly the book's figure, then 0.477
  late against 0.503.
- **Selection:** metabolism falls to 1.85 (book 1.8).
- **Neighbors:** 0.80 per agent (book 0.9).
- **Fig II-5's metabolism-1 curve:** all five points within 4%. Read at t≈50, all 18 points of the
  sweep pass.
- **Seasonal migration (II-7):** high-vision agents migrate, and low-vision agents hibernate.
- **Pollution (II-8):** agents abandon the polluted peaks and return after diffusion.
- **Initial endowment:** the book never states it for these runs. Only 25–50 reproduces Fig II-4's
  curve: RMS error 11 agents, against 49 and 57 for the other ranges the book uses.

**Chapter III: evolution, culture and combat.**
- **Evolution under S:** mean vision 5.6 at t≈900 (book 5.3), and metabolism falls to 1.0 (book
  1.0).
- **III-1:** the level is 555 (book ≈500) with nothing fitted. Fluctuations are 11%, just over the
  book's 10% (near; 6.5% under the former 0.83 default).
- **III-3's floor:** 201 (book ≈250), the first setting to reach it.
- **III-4:** its cycle has the book's period, 104 against ≈125 (peak spacing).
- **Combat (III-9, III-11, III-14):** every run ends in one of the book's three patterns.
  Same-tribe war persists, and assimilation prevents hegemony in about half the runs.
- **Friendship:** best-friend closeness 0.98 (book 0.91).
- **Proto-history (III-15):** Blue dominates both mountains in 40% of runs and Red in 45% (book
  ≈25% each; Red's is near), and extinction is rare (5%).

**Chapter IV: trade and credit.**
- **Price formation:** mean price ≈1.0, and ln-price dispersion falls to 0.047 by t=1000 (book
  ≈0.05).
- **Market thickness:** vision 1–15 gives a dispersion of 0.014 (book ≈0.03).
- **Lifespan:** dispersion falls with lifespan, 0.45 / 0.30 / 0.22 / 0.11 against the book's
  ≈0.5 / 0.3 / 0.2 / 0.15.
- **Gini at mean vision 10–14.5:** with and without trade.
- **Fig IV-6 at t≈50:** 9 of 10 points pass, with trade's lift; the tenth is near (119 against 100).
- **Trade with reproduction (IV-14):** dispersion 0.38 (book ≈0.37).
- **Pollution:** a sugar-price spike follows pollution (2.3, book ≈3.5).
- **Credit networks (IV-A5):** 137 active loans and 22 agents both lending and borrowing (book
  frame: 187 and 21). Hierarchies run 6–8 levels deep (book "as many as five").

**Chapter V: disease.**
- **V-1:** the society rids itself of disease, with a sick share of 0.6% at t=450–500.
- **Starting load:** 4.4 active diseases per agent (book 3.41).

**Chapter VI: the wider models.**
- **Schelling (VI-4 to VI-7):** 5 of 6 rows pass. The book's point is reproduced: a small change in
  individual preference makes a large change in segregation.
- **Ring World (VI-8, VI-9):** all 9 rows pass. Agents form ≈5–6 travelling groups that move ≈6×
  faster than loners, and they leapfrog. A megagroup breaks up within ≈10 periods.
- **VI-1 prices:** mean ≈1 and dispersion 0.35 (book 0.3–0.4).
- **VI-3 against VI-2:** over the first 75 periods the trading society tracks the non-trading one
  (ratio 1.11), as the book says.
- **VI-3's waves:** after the crash the population sinks to 66 (book ≈65), then swings between a
  floor of 678 and a ceiling of 960 (book 700–1,200). The first peak (831) and the period (221
  against ≈115) still miss.

## What did not reproduce

### 1. Population dynamics under the sex rule (the largest family)

| Result | Book | Ours (default since 2026-10-23: integer gifts + C1) | Former default (θ=0.83, `VAR-fit83`) | Rule S as written (`VAR-book`) |
|---|---|---|---|---|
| III-1 steady population | ≈500 | 555 | 478 (fitted) | 360 |
| III-1 early boom, t=20 / 85 | 470 / 570 | 377 / 220 | 398 / 208 | 356 / 136 |
| III-3 floor / period / agents ever lived | ≈250 / ≈200 / ≈12,500 | 201 / 393 / 9,934 | 33 / 412 (3 of 5 seeds) / 3,690 | 18 / 495 / 1,613 |
| III-4 oscillation range | ≈1,000 | 598 | 106 | 120 |
| III-5 extinction | yes, t≈610 | 0 of 10 seeds | 0 of 10 seeds | 0 of 10 |
| III-7 Gini with inheritance / vision | 0.743 / 4.3 | 0.31 / 5.37 | 0.31 / 5.19 | 0.35 / 5.13 |
| IV-17, IV-18 (trade or foresight with S) | run 1,000 periods | 3 of 5 and 1 of 5 seeds extinct | 4 of 5 and 5 of 5 | — |
| VI-1 population at t≈50 | ≈155 | 40; extinct in 3 of 5 seeds | 41; extinct in 5 of 5 | — |
| VI-2 crash at t≈20 / extinction | ≈130 / yes | 217 / 0 of 10 seeds | 213 / 1 of 10 | — |
| VI-3 minimum / first peak / waves | ≈65 / ≈1,190 / 700–1,200 | 66 / 831 / 678–960 | 36 / 308 / 204–534 | 272 first peak |

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

None of them reproduces the boom, the level, the swings and the extinction together. The
follow-up's candidates and frequencies sharpen this ([below](#follow-up-2026-10-23)).

### 2. Long-run carrying capacity (Figs II-5 and IV-6)

- **Fig II-5:** the metabolism-2 points run 10–20% low at t=500. So do three metabolism-3 points:
  8 of Chapter II's 9 near rows.
- **Fig IV-6:** with and without trade, it runs ≈25% low (9 fails, 1 near). Trade's ≈20–30% lift
  is reproduced.
- **At t≈45–60 both figures match.** All 18 Fig II-5 points are within ±5%. Of the ten Fig IV-6
  points, all but one are within ±5%, and that one is +19%. Scored as targets since 2026-10-23,
  27 of the 28 pass.
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
  - the only fitted value (0.83, the default until 2026-10-23) was fitted to a single number,
    frozen, and validated out of sample;
  - it was adopted, and later replaced by a setting with nothing fitted, only by explicit decision;
  - the book's rule still runs beside the default, and so does the former default.
- **Unit tests built from the book's own worked examples.** They pinned the rules where the book is
  exact, so later failures could be blamed on readings, not on arithmetic.
- **Determinism and regression re-runs.** Seeded streams, fingerprint caching and stream pins made
  "every row identical" a checkable claim after each default change. They also made `VAR-book`,
  and later `VAR-fit83`, reproduce the old default exactly.
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
- **Some statistics weren't reliable** (all three fixed on 2026-10-23):
  - **Period:** the first autocorrelation peak gives 201–1,701 on irregular series. Peak spacing
    from smoothed turning points was more informative, and the targets now use it.
  - **Status rule:** near meant little for wide proxy bands; its margin is now capped.
  - **Measurement time:** we never settled when "carrying capacity" was read; both readings are
    now scored.
- **Faithful changes that hurt the overall fit.** Spread founder ages are better supported by the
  book's frames. Yet they lowered III-1's early curve, extinguished IV-14, IV-17 and IV-18, and
  undid the calibrated threshold's out-of-sample gains, which had been measured with age-0
  founders. The rules are tightly coupled, so one-at-a-time changes moved rows in chapters far from
  the one under study.
- **Searching for a single cause.** Over a day of probes ruled out more than twenty single causes
  of the population gap. Each was cheap, but the yield fell steadily, and an interaction between
  readings can't be found this way.
- **Diagnostics that lived outside the repository.** The probe scripts behind the diagnostic tables
  sat in a session scratchpad, not in git. Fixed on 2026-10-23: they are in
  [diagnostics/](diagnostics/README.md), pinned to the defaults they were written under, and spot
  checks in every epoch reproduce their saved outputs exactly.
- **Proxies for qualitative claims.** Some proxies are sharp (Ring World's groups), but others are
  weak or permissive (the nearsighted bound, II-7's hibernation band). Each one is our own
  construct.

## How the model could be changed to reproduce more

These are grouped by how far they move from the book. None has been adopted, except where noted.

### A. Measurement, no model change

1. **Read carrying capacity at t≈50 as well as t=500.** Done on 2026-10-23 (user decision): 27 of
   the 28 early rows pass, while the t=500 rows keep their statuses.
2. **State Fig IV-6 relative to the starting population**, since the long-run number scales with
   it. Not done.
3. **Report the book's single runs as frequencies.** Done on 2026-10-23 over 30 seeds; see
   [Follow-up](#follow-up-2026-10-23), and the [eighth follow-up](#eighth-follow-up-2026-10-23) for the new default.

### B. Departures already shown to help (each at a cost)

| Change | Helps | Costs |
|---|---|---|
| Fertility threshold 0.83 (adopted 2026-10-22, **replaced** 2026-10-23) | III-1 level, IV-14 survival, III-15 extinction | Contradicts p.55; no help with the dynamics |
| Integer gifts with partners in sight (**adopted** 2026-10-23) | III-1 level, III-3 floor, VI-3 minimum, floor and ceiling, III-4 swings and IV-17/IV-18 survival (near) | Partners in sight contradict p.56; III-1 sits at 555 and fluctuates 11% |
| Age-0 founders with θ=0.83 | III-3 floor 174, agents ever lived 8,739, III-4 range 304, VI-3 floor 705 and first peak 848 | Contradicts Animation III-1's ages and VI-2's early births |
| Wider or unrestricted mating contact | Low-density births reach the book's: the III-4 response curve and the first peak (≈1,560 at t≈90); 4 of 10 culled III-4 runs lock into the book's cycle | Contradicts von Neumann mating (p.56); raises III-1's level, so θ would need re-fitting |
| Ignoring "nearest" in M | III-1 452; spacing 0.97 (book 0.9) | Contradicts p.25; Fig II-5 +12–14% at t≈50 |
| Lifelong disease sets | V-2 endemic (2.05 per agent) | V-1 becomes chronic; V-2's population crashes to 13 |

### C. Candidates, most promising first

All seven were tested on 2026-10-23: C1–C3 with p.55's threshold on every population figure
([Chapter III record](docs/replication/chapter-3.md#candidate-departures-from-rule-s-2026-10-23)), C4–C7 under the
defaults on the figures each bears on ([candidates2.py](diagnostics/candidates2.py)). C1 and C3 help most;
C4–C7 change little.

1. **Mate search within vision**, between radius 2 (tested: 417) and global contact (tested: 509).
   It targets the low-density Allee effect directly. That effect sits behind III-3's lost
   mountains, the low first band of III-4's response curve, and the slow founding boom.
   *Result:* the broadest improvement of any candidate, with no fitted value: III-1 420 (pass),
   III-3's floor 163 (near; 33 today), VI-3's minimum 64 (pass), VI-3's floor and ceiling near. It
   leaves III-4's swings small and III-5 and VI-2 alive.
2. **A gift that depends on wealth, with a threshold that doesn't.** Parents give half their
   *current* sugar (Kehoe's prose reading), and the child's threshold is drawn from the founders'
   range, so children born in poor, crowded times come of age below threshold. p.55 states the
   gift plainly, so this is a departure. *Result:* VI-2 dies out like the book (4 of 5), but III-3
   and VI-3 die too, and III-5 survives.
3. **Ascape's departures as one package:** random founder ages, children costing at most 5 sugar,
   and fresh thresholds. Ascape was built at Brookings, where the book's authors worked, so its
   choices are weak evidence of what the original code did. *Result:* the only candidate that gives
   III-4 the book's swings (range 969, period 124) and the only one in which III-5 dies out (1 of 5),
   but III-1 falls to 220 and III-3 and VI-3 die out. With C1 added, III-4 keeps its swings (615)
   and III-1 recovers to 314. *Fitted* (θ=0.74, fitted to III-1's level alone): III-4's range 866
   and VI-3's floor 731 pass, and five more rows come near, but nothing dies out
   ([Chapter III record](docs/replication/chapter-3.md#c1-with-cheap-children-at-a-fitted-threshold-2026-10-23)).
   Registered as `VAR-c1c3fit` (user decision, 2026-10-23).
4. **Rule-by-rule sweeps** (all agents move, then all mate), as Kehoe orders them. The text implies
   per-agent turns. *Result:* III-4's range rises from 106 to 282, while VI-3 gets worse (first
   peak 89) and nothing else moves, the waves included.
5. **For waves:** growback before the agents move instead of after; the map's corridor capacities
   checked against Fig II-1 cell by cell; integer sugar on regrown sites. *Result:* none is a cause.
   - Growback first is the same model relabelled: II-6's series are identical.
   - The map reads as Fig II-1 at 86% of sites exactly and at 99.4% within one level (94% exactly
     on the saddle between the mountains).
   - Regrown sugar is already integer under G1.
6. **For disease:** passing every active disease to each neighbor instead of one at random. This
   departs from p.145, but spread is the measured bottleneck: each infection reaches ≈0.17 others,
   and endemic disease needs above 1. *Result:* V-2's endemic level rises only from 0.02 to 0.05
   diseases per agent (book 0.86). There are too few contacts for more diseases per contact to
   matter.
7. **For VI-1's credit:** count sugar and spice income in the creditworthiness test. *Result:* about
   1 active loan instead of 0.25 (book ≈215). The society is too sparse for credit either way.
8. **Integer gifts** (found 2026-10-23 in Watts' SugarscapeCW). Each parent gives int(endowment / 2), so a
   child's endowment, and with it its fertility requirement, rounds down. If the original kept sugar as
   integers, this is p.55's rule. *Result*, at p.55's threshold with nothing fitted: III-1 454 (pass), III-4's
   range 526 (near), and VI-2 dies out in 5 of 10. With C1 it scores best of any variant: 9 of 18 population
   targets pass, including III-3's floor and VI-3's floor and ceiling. Registered as `VAR-intgift` (user
   decision, 2026-10-23); see [sixth follow-up](#sixth-follow-up-2026-10-23).

### D. Outside evidence

- **Run the Ascape and MASON Sugarscapes** and compare III-1 and III-4 curves directly. Both were
  run on 2026-10-23 ([diagnostics/mason/](diagnostics/mason/README.md),
  [diagnostics/ascape/](diagnostics/ascape/README.md)). We don't have the original code (about
  20,000 lines, Macintosh, Appendix A).
- **Six more implementations** were examined on 2026-10-23: Think Complexity's, Agents.jl's, Mesa's,
  SugarscapeCW, nkremerh's and langerv's ([fifth follow-up](#fifth-follow-up-2026-10-23)). SugarscapeCW's integer
  gifts are the one lead; the others' successes come from departures from the text.
- **Ask the authors.** Kehoe reached the same impasse and concluded the rule must be clarified by
  the original developers. We could not reach them; the questions are in
  [Questions for the authors](#questions-for-the-authors).

## Book results that may not be robust or correct

These are the claims our evidence casts doubt on, with how strong that evidence is.

| Claim | Why we doubt it | Evidence |
|---|---|---|
| Fig III-1's early boom to ≈570 | The book's other run of the same rules (Animations III-2/III-3, the source of Fig III-2) crashes to ≤172 agents on the peaks. The boom is one realization, not a property of the rules | Strong (internal) |
| Fig III-1's level of ≈500 | That same animation run settles at ≈670–1,020 | Strong (internal) |
| The population figures follow from rule S as published | No implementation we know of gets them from the text. Ours and Kehoe's (collapse before t=2,500) don't. MASON's own code on its own configs, scored with our targets, settles III-1 at 348, loses III-3 and never extinguishes III-5. Ascape departs from the text on cost, ages and thresholds; with the book's parameters, even on the book's map, it settles III-1 near 230, loses III-3 in every run and never extinguishes III-5. The figures probably depend on unstated details of the original code | Strong that the text is incomplete |
| One founder setup underlies the figures | Animation III-1's ages and VI-2's first-period births need spread ages. Fig III-3's opening (rise to ≈450, crash to ≈250) fits age-0 founders | Medium |
| Fig III-4's large cycle is the typical outcome | In our model the cycle is one of two stable states, reached only after a fast, compact boom: 2 of 30 ordinary runs under p.55's rule, 0 of 30 under the default. Whether the original lands there reliably is unknown; the book shows one run. Cheaper reproduction makes the swings routine: Ascape's code cycles at the book's period in 10 of 10 runs (range 444–807), and MASON's flat threshold at twice the period | Medium (depends on the reproduction rule) |
| VI-2's society dies out | Under p.55's rule ours dies out in 15 of 30 seeds: a coin flip, not a property of the rules | Medium (depends on our model) |
| Fig III-3's floor of ≈250 | It needs both mountains to survive the founding crash, a knife-edge in our runs | Medium (depends on our model) |
| Fig III-5's extinction at t≈610 | It needs births near zero for ≈40 periods after each peak. Its frequency is unstated. It never happens in 60 runs under the default or p.55's rule, nor in 10 of MASON's. Under `VAR-c1c3fit` it happens in 2 of 30 | Weak |
| Fig II-5 values are asymptotic "carrying capacities" | Our populations match all 18 points at t≈45–60 and fall 10–20% below at t=500 on the metabolism-2 and -3 curves | Medium: either the book read early, or our long-run decline is wrong |
| Fig IV-6's carrying capacities | In the two-commodity model the long-run population scales with the unstated starting population | Strong in our model |
| Animation V-3's first-frame statistics | A spread of 0.62 at a mean of 3.41 is impossible for 10-disease draws, which give 1.2–1.5 | Strong (arithmetic) |
| V-2's endemic state under the stated parameters | Diseases 1–3 bits from a window of a 50-bit string are learned faster than they spread. No reading sustains V-2 while V-1 clears | Medium |
| Animation II-6's set-up | The text says 400 agents "exactly as in II-2"; frame 1 shows a 20×19 block of ≈284 | Strong (internal) |
| III-8's "all Blue after ≈2,700" | One typical run of a voter-like process, whose absorption times are widely spread | Weak to medium |
| VI-4 and VI-5 are "comparable" | The book's own pictures of the two differ | Weak |
| III-7's Gini of 0.743, fn 32's frequencies | Single figures or rough shares, with no count of runs | Weak |

## Questions for the authors

These are the details of the original code that the text leaves open and that would settle more than further
probes. We could not reach the authors, so they stand as the project's open questions. Each names the result it
bears on and the page whose wording leaves it open; the evidence is in the sections above and the chapter records.

1. **The fertility wealth test (p.55).** Did an agent need current sugar at least equal to its own birth endowment,
   or something else (a fixed amount, a fraction of the endowment, sugar plus spice)?
2. **The child's endowment and threshold (p.55).** Was the child's endowment half of each parent's *initial*
   endowment, and was that endowment also the child's own fertility threshold?
3. **Partner contact (p.56).** Did agents mate only with their four lattice neighbors after moving, and was the
   child placed on an empty site next to a parent?
4. **Founders' ages (Figs III-1 to III-5, VI-2).** Did the first generation start at age 0 or at random ages?
   Animation III-1's first histogram and VI-2's first-period births suggest random ages; Fig III-3's opening
   suggests age 0.
5. **Fig III-1 and Animations III-2/III-3.** Were these the same parameters? The animation run falls to about 170
   agents and later exceeds 1,000; Fig III-1 rises to about 570 and settles near 500.
6. **Fig II-5 and Fig IV-6.** At what time were the carrying capacities read? Ours match the figures at t≈50 but
   fall 10–25% below them by t=500 for metabolisms 2–3. And how many agents started the Fig IV-6 sweep?
7. **Animations V-2 and V-3.** What disease and immune-string lengths did the endemic run use, and is V-3's
   "average diseases per agent" the count of active (unmatched) diseases?
8. **Integer sugar (p.55).** Did the program store sugar as integers, so that "one half of whatever his initial
   endowment had been" rounded down? Rounding down lowers every later generation's fertility requirement, and in
   our model it supplies most of the gap in Figs III-1 and III-4 (fifth follow-up).

## Follow-up (2026-10-23)

The six steps this review recommended, and what each found:

1. **Diagnostics checked in.** 71 probe scripts are in [diagnostics/](diagnostics/README.md), each
   pinned to the defaults it was written under and indexed with its commit and saved output. Spot
   checks in all three defaults epochs reproduce their saved outputs exactly.
2. **Statistics fixed.**
   - **Near:** the margin is now the smaller of half the band and a quarter of the bound, which
     turns nine near rows into fails and improves none.
   - **Period:** targets use the median peak spacing of a 41-period moving average, in place of the
     first autocorrelation peak. III-4 132 (pass), III-3 412, VI-3 241.
3. **Carrying capacity at t≈50 counted** (user decision): 27 of 28 rows pass.
   - **Re-runs:** Chapters IV–VI and the VAR runs, whose saved results here predated the 0.83
     default, were re-run. Every chapter's observed values match its record, apart from the three
     periods.
4. **Single runs as frequencies** over 30 seeds
   ([Chapter III record](docs/replication/chapter-3.md#the-books-single-runs-as-frequencies-2026-10-23)):
   - **VI-2 under p.55's rule:** dies out in 15 of 30 runs.
   - **III-4 under p.55's rule:** locks into the large cycle in 2 of 30.
   - **VI-3 under the default:** reaches the book's waves in 4 of 30.
   - **Never:** III-5 dies out, or III-3's floor reaches the book's band.
5. **Candidates C1–C3 tested** (above, section C):
   - **Within-vision mating (C1)** is the best single remedy for the low-density shortfall.
   - **Cheap children (C3)** produce III-4's swings and III-5's only extinction.
   - **None** reproduces every figure, and combining them works only partly.
   - **Reading:** the book's figures behave as if births were both easy to arrange when sparse and
     cheap enough to boom and bust.
6. **Outside evidence.**
   - **MASON:** built and run headless from its project archive
     ([diagnostics/mason/](diagnostics/mason/README.md)). Its own model misses the book's III-1 (348),
     III-3 and III-5 as ours does. Its large III-4 swings come from a flat fertility threshold of
     25, at about twice the book's period.
   - **MASON's own statistics are unreliable:** children are counted but left out of its averages.
   - **Questions for the authors:** drafted; see
     [Questions for the authors](#questions-for-the-authors). The authors could not be reached.

It left four next steps: send the authors' questions, run Ascape, try C1 with cheaper children at a
fitted threshold, and test candidates C4–C7.

## Second follow-up (2026-10-23)

1. **Questions for the authors.** The authors could not be reached, so the questions now have their
   own section ([above](#questions-for-the-authors)) as the project's open questions.
2. **Ascape run** headless from its 5.6.1 release jar
   ([diagnostics/ascape/](diagnostics/ascape/README.md)), with the book's parameters on its own
   landscape and on the book's map:
   - **III-4:** every run cycles at the book's period (124–128) with ranges of 444–807, the only
     implementation with both.
   - **III-1, III-3, III-5:** missed by more than ours. III-1 settles at 230–270, III-3 dies out in
     every run, and III-5 never does.
   - **Its code departs from the text:** children cost at most 5 sugar, with a bug that keeps only
     the second parent's gift; thresholds are fresh draws; there is no preference for the nearest
     site.
3. **C1 with cheap children at a fitted threshold** (C1+C3fit; θ=0.74, fitted to III-1's level alone,
   frozen, then validated). It has the best out-of-sample record of any setting:
   - **Pass:** III-4's range (866) and period (107), VI-3's floor (731).
   - **Near:** III-3's period (144) and agent count (9,060), VI-3's first peak (879) and ceiling (904).
   - **Missing:** every extinction and near-extinction (III-3's floor, III-5, VI-2, VI-3's minimum).
     The society booms and busts like the book's but never comes close to dying.
4. **Candidates C4–C7** (section C): none is a remedy.
   - **Ruled out for the waves:** the order of growback (a relabelling), the map (it matches Fig II-1
     to within one level at 99.4% of sites) and rule-by-rule sweeps.
   - **Disease and credit:** more diseases per contact and two-good credit income barely move V-2
     and VI-1, whose societies are too sparse.

No default changed and no target moved, so the scoreboard stands.

It left three next steps: register C1+C3fit as a labelled variant, count its extinctions over 30 seeds,
and look for what drives the book's societies to near-extinction.

## Third follow-up (2026-10-23)

1. **`VAR-c1c3fit` registered** (user decision). Rule S gained three options, off by default:
   partners in sight, a gift of at most 5, and a redrawn threshold. The report scores the variant on
   every population target. It reproduces the diagnostic's runs exactly. Defaults, the saved runs'
   fingerprints and the totals are unchanged.
2. **Its extinctions as frequencies** over 30 seeds
   ([Chapter III record](docs/replication/chapter-3.md#var-c1c3fits-single-runs-as-frequencies-2026-10-23)):
   - **III-5:** dies out in 2 of 30 (the first extinctions of any setting), with a trough below 100
     in 9.
   - **III-4:** holds the large cycle in 18 of 30.
   - **III-3:** keeps both mountains in 9 of 30.
   - **VI-2:** never dies out (0 of 30). The variant's easier births work against it.
3. **What stops the near-extinctions**
   ([Chapter III record](docs/replication/chapter-3.md#what-keeps-the-variants-societies-alive-after-a-peak-2026-10-23)):
   - **Peak cohorts are short:** they come of age at 0.72 of their requirement, and only 27% qualify.
     This is the deficit the default lacked.
   - **Falls are short and never starve.** They last ≈65 periods with ≈4 births per period before
     the trough, where the book's last ≈110 with ≲1 birth per period and 52–91 starvations.
   - **Why no one starves:** metabolism is 1.00 at every peak, so each site's regrowth feeds its
     holder.
   - **Three mechanisms, each fitted to III-1, don't change this:** Ascape's lost gift (deeper
     deficit, still no extinction), Ascape's movement (higher troughs), and children with a fresh
     metabolism (steady starvation, no cycle).
   - **Reading:** the book's peaks must outgrow their food while the peak cohorts can't breed, and
     ours never outgrow it.

It left two next steps: find what would let a peak outgrow its food, and score `VAR-c1c3fit` on VI-1.

## Fourth follow-up (2026-10-23)

1. **Can a peak outgrow its food?** Four departures, each on top of `VAR-c1c3fit` and fitted to
   III-1's level ([Chapter III record](docs/replication/chapter-3.md#can-a-peak-outgrow-its-food-2026-10-23)):
   - **Zeroing the capacity-1 sites, or making agents leave their own site:** they move the fitted
     threshold by less than 0.01, so the level is limited by births, not food. Neither produces
     extinctions or starving falls.
   - **Growback of 0.75 per period:** troughs reach 50, but there is still no starvation in the
     falls and no extinction.
   - **Growback of 0.5 per period:** the only setting whose falls starve (51 per fall; the book's
     need 52–91). But its fitted threshold is 0.28, so 84% of even the peak cohort can breed, and
     the troughs stop near 570.
   - **Chapter II:** halving growback lowers Fig II-5's m2 and m3 points by 14–16% at t≈50, and
     zeroing the capacity-1 sites lowers m1 by 15%. Both contradict results that match today.
   - **Reading:** with the level fitted, starvation and the peak cohort's fertility deficit pull
     against each other, and the book's falls need both. No mechanism of this kind is left
     untested.
2. **`VAR-c1c3fit` on VI-1**
   ([Chapter VI record](docs/replication/chapter-6.md#var-c1c3fit-on-vi-1-2026-10-23)):
   - **The society nearly doubles** at t≈50 (73; the default gives 41, the book 155).
   - **Now pass:** family size (1.09) and best-friend closeness.
   - **Credit rises** from almost nothing to 41 active loans (book ≈215).
   - **Still short:** the society is half the book's, so trade and credit stay low. Wealth is more
     unequal (Gini 0.36), and the disease still clears.

**Next steps now.** The probes within reach are exhausted: every reading of the text, every
candidate departure and both outside implementations have been tried against the population
figures. What remains needs new evidence rather than more probes:
1. Look for the original program (Appendix A: about 20,000 lines for the Macintosh) or the book's
   companion CD-ROM, in Brookings' or the authors' archives.
2. Otherwise, treat the replication as complete and tag the current state (for example `v1.1`).

## Fifth follow-up (2026-10-23)

The project owner found six more implementations, plus Downey's *Think Complexity* (2nd ed.). We read each one's
code, ran the three that cover our misses, and tested their departures one at a time.

| Implementation | Covers | Run | Result |
|---|---|---|---|
| *Think Complexity*, ch. 9 (Downey, Python) | Ch. II: carrying capacity, wealth, waves | II-6 under each departure ([Chapter II record](docs/replication/chapter-2.md#think-complexitys-waves-2026-10-23)) | Its waves need its own map (peaks 20 sites apart; the book's are 24) or vision up to 16 (p.42: at most 10); either alone puts the wave proxy in band (0.16 against 0.05). They are the first crossing, at t≈5–20, not repeated waves. |
| Agents.jl v4.0 example (Julia) | Ch. II, 20 periods | — | Not the text's movement (agents head only for the grid's richest sites); targets none of our misses. |
| Mesa G1MT and the SFI tutorial (Python) | Ch. IV: trade | IV-3 and Fig IV-6 ([Chapter IV record](docs/replication/chapter-4.md#mesas-sugarscape-g1mt-2026-10-23)) | Trading with everyone in sight and moving over a diamond: trades per period 32 to 42 (book ≈150); Fig IV-6 at t=500 moves by at most 8 agents. |
| SugarscapeCW (Watts, NetLogo) | every chapter | III-1 to III-5, headless in NetLogo 6.4 ([harness](diagnostics/sugarscapecw/README.md)) | **III-1 473 and III-4's swings (range 929, period 117) at p.55's threshold.** III-3's floor (106) and III-5's extinction are missing. |
| nkremerh/sugarscape (Python) | every chapter | III-1 to III-5, on its landscape and the book's map ([harness](diagnostics/nkremerh/README.md)) | III-1 564 and III-3's floor 279, but only because daughters can inherit a father's end of fertility; without that, 383 and 56, and with its other departures removed, 376 and 25, as ours. No III-4 swings, no III-5 extinction. |
| langerv/sugarscape (Python 2, Pygame) | Chs. II–III | — (read only) | Its own map (capacities up to 10) and children paid for with sugar the parents may not have; its saved population plot (near 800) isn't comparable. |
| "Creating Intelligent Agents" (Brearcliffe and Crooks, NetLogo) | learning in combat | — | Not a replication; not examined further. |

**SugarscapeCW's lead: integer gifts.**
- **Its rule S is ours,** except that each parent gives int(initial endowment / 2). The child's endowment, which is
  also its fertility requirement, can only round down.
- **Its two departures from the text are not the cause.** With stacking removed and the world wrapped, it still
  gives III-1 479 and III-4 678
  ([ablations](diagnostics/output/sugarscapecw_ablate.txt)).
- **Births per woman match ours** (2.0), but at a lower requirement. Its population's mean endowment falls from 74
  to 63 and holds; ours falls only to 71.
- **The same truncation in our model**
  ([probe](diagnostics/output/probe_integer_gift.txt); [Chapter III record](docs/replication/chapter-3.md#two-more-implementations-and-integer-gifts-2026-10-23)):
  - **III-1:** 360 to 451, which passes with nothing fitted (our fitted 0.83 threshold gives 478).
  - **III-4:** the range rises from 120 to 476 (562 with founders at age 0), near the band.
  - **Still failing:** III-3's floor and III-5's extinction.
- **Its status is open.** If the original stored sugar as integers, it is the book's rule; nothing in the book says
  either way. Question 8 for the authors asks.

**Other things learned:**
- **Founders at age 0** give both outside models, and ours, the book's t=20 boom (≈460 against 470). Spread ages
  don't.
- **Two implementations ship our map file, cell for cell:** Mesa's and SugarscapeCW's.
- **Errors found in outside code:**
  - nkremerh's map loader swaps sugar and spice.
  - langerv's agents see one site farther east and north than west and south.
  - SugarscapeCW's sight procedure, which skips occupied sites, is never called.

It left a decision: whether integer gifts become a registered variant, tested with C1 and C3.

## Sixth follow-up (2026-10-23)

1. **`VAR-intgift` registered** (user decision). Rule S gained a fourth option, off by default:
   `gift_rounding="down"` rounds each parent's gift down to a whole unit. It applies to sugar and spice, and to
   the whole-endowment gift or C3's capped one. The variant is p.55 otherwise: threshold 1.0, nothing fitted.
   Defaults, saved runs and totals are unchanged.
2. **Scored on all six population figures** (18 targets; up to 10 seeds;
   [Chapter III record](docs/replication/chapter-3.md#var-intgift-and-its-combinations-2026-10-23)):

| Variant | Fitted | Pass / near / fail | What changes |
|---|---|---|---|
| `VAR-book` (p.55 as written) | — | 5 / 1 / 12 | — |
| `VAR-intgift` | — | 7 / 1 / 10 | III-1 454 (pass); III-4's range 526 (near); VI-2 dies out in 5 of 10 (pass) |
| integer gifts + C1 | — | **9 / 4 / 5** | III-1 555; **III-3's floor 201** and VI-3's minimum (66), floor (678) and ceiling (960) pass; III-4's range 598 (near) |
| integer gifts + C3 | — | 5 / 1 / 10 | III-4's swings (969), but III-1 falls to 220 and III-3 and VI-3 collapse |
| integer gifts + C1 + C3 | — | 5 / 2 / 11 | III-1 314; C3's redrawn thresholds cut the link the rounding acts through |
| `VAR-c1c3fit` | θ=0.74 | 7 / 5 / 6 | — |
| default | θ=0.83 | 6 / 0 / 12 | — |

   - **Integer gifts with C1 is the best of any variant, with nothing fitted.** It is the first to pass III-3's
     floor, which no variant had reached (33 by default, 95 under `VAR-c1c3fit`).
   - **What no variant reproduces:** III-5's extinction (1 run in 10 under integer gifts + C3, none under the
     others), VI-2's crash at t≈20 (212–241 against ≈130), and the periods of III-3 and VI-3.
   - **C1 is a departure from p.56** (partners are the four neighbors), where integer gifts may be the book's
     own arithmetic. The two have different standing.

It left two decisions: whether to register integer gifts + C1, and whether integer gifts should replace the
fitted 0.83 in the defaults.

## Seventh follow-up (2026-10-23)

1. **`VAR-intgiftc1` registered** (user decision): integer gifts and C1 at p.55's threshold, nothing fitted. In the
   report it scores 9 pass, 4 near, 5 fail on the population figures, as in the diagnostic.
2. **Integer gifts as the default, tested on every target**
   ([Chapter III record](docs/replication/chapter-3.md#var-intgiftc1-and-integer-gifts-as-the-default-2026-10-23)).
   The 13 experiments the threshold touches were rerun under p.55's threshold: with exact gifts, with integer gifts,
   and with integer gifts and C1 (at the project owner's request):

| Default | All 169 targets (pass / near / fail) |
|---|---|
| fitted 0.83 (today) | 95 / 22 / 52 |
| p.55, exact gifts | 93 / 22 / 54 |
| p.55, integer gifts | 95 / 22 / 52 |
| p.55, integer gifts + C1 | **99 / 27 / 43** |

   - **Integer gifts tie the fitted default,** without a fitted value.
   - **Gains:** III-4's swings reach near (106 to 526), VI-2 dies out like the book's run (5 of 10), and III-15's
     Blue dominance passes.
   - **Losses:** IV-14 dies out in 3 of 5 runs (its dispersion fails), and III-15's extinctions rise from 2 to 6 of
     20 runs, where the book calls them rare.
   - **Integer gifts + C1 is better on every total:** four more passes, five more nears, nine fewer fails. Of 13
     status changes, 11 improve: III-3's floor, VI-3's minimum, floor and ceiling pass, and IV-17 and IV-18
     survive (near). Two slip from pass to near (III-1's fluctuations, III-15's Red dominance); none falls to
     fail. IV-14 and III-15's rare extinctions pass again. VI-2 no longer dies out.
   - **Why integer gifts tie 0.83 on III-1:** the fitted value lowers every agent's requirement to 0.83 at once. Integer gifts
     lower children's requirements by up to a unit a generation, to ≈0.85 of the founders' level. Only the
     gradual route moves the dynamics.

**Recommendation.** If the default is to score best, integer gifts + C1 wins outright, with nothing fitted. But C1
departs from p.56, which names the four neighbors as partners, so it trades a fitted number for a departure in the
rule. Integer gifts alone tie 0.83 with neither a fitted number nor a departure (if the original stored sugar as
integers). The choice of default is the project owner's.

3. **Decision (user, 2026-10-23): the default is integer gifts + C1.**
   - **What changed:** `Config` now defaults to threshold 1.0, `gift_rounding="down"` and `mate_contact="vision"`.
     Every experiment was re-run. The full report reproduces the candidate test: 99 / 27 / 43 of 169. Chapters II
     and V are unchanged row for row.
   - **The variants keep their meaning.** Each now names its threshold, gift rounding and contact. `VAR-fit83` is
     the former default, and reproduces its saved III-1 runs exactly. `VAR-intgiftc1` now equals the default.
   - **Older diagnostics still regenerate:** epochs A–C in `diagnostics/_pin.py` pin exact gifts and the four
     neighbors, and a new epoch D holds the current defaults.

**Next steps now.**
1. **Measure frequencies over 30 seeds** under the new default, as for `VAR-c1c3fit`. The book's single runs may sit
   in their tails. Done; see the [eighth follow-up](#eighth-follow-up-2026-10-23).
2. **The earlier two still stand:** look for the original program, or tag the current state.

## Eighth follow-up (2026-10-23)

**The book's single runs as frequencies under the new default**, over 30 seeds
([Chapter III record](docs/replication/chapter-3.md#the-new-defaults-single-runs-as-frequencies-2026-10-23)). Integer
gifts alone are counted too, for comparison. Nothing in the model changed.

| Figure | Book's behavior | θ=0.83 | p.55 | `VAR-c1c3fit` | Integer gifts | **Default** |
|---|---|---|---|---|---|---|
| III-3 | both mountains | 3 | 0 | 9 | 2 | **23** |
| III-3 | floor ≥200 | 0 | 0 | 1 | 0 | **21** |
| III-4 | large cycle | 0 | 2 | 18 | 13 | **16** |
| III-5 | extinct | 0 | 0 | 2 | 0 | 0 |
| III-5 | trough <100 | 0 | 0 | 9 | 2 | 0 |
| VI-2 | extinct | 1 | 15 | 0 | 15 | 0 |
| VI-2 | crash ≤156 | 0 | 0 | 0 | 0 | 0 |
| VI-3 | survives | 23 | 12 | 30 | 18 | **30** |
| VI-3 | waves in band | 4 | 0 | 1 | 0 | **14** |

1. **III-3, III-4 and VI-3 are now typical runs:** the book's behavior appears in about half to three quarters of
   the seeds, so those figures are no longer tail draws.
2. **The gift rules split the work.** Integer gifts carry III-4's cycle; partners in sight carry III-3's two
   mountains and VI-3's waves.
3. **The extinctions remain out of reach.** III-5 and VI-2 never die out under the default: partners in sight keep
   alive the societies the book's runs lose. Integer gifts alone let VI-2 die out in 15 of 30, but III-5 still
   never does. Only `VAR-c1c3fit`'s cheap children have produced III-5's extinction.

**Next steps now.** Look for the original program, or tag the current state. The one open question in
rule S is what lets the book's III-5 and VI-2 die out while its III-3 and VI-3 survive.

## Ninth follow-up (2026-10-23)

**Integer trade registered as `VAR-inttrade`** (user request)
([Chapter IV record](docs/replication/chapter-4.md#integer-trade-var-inttrade-2026-10-23)). If the original stored
sugar as integers (question 8), rule T's exchanges were whole units too. With `trade_rounding="down"`, each
exchange rounds p or 1/p down to a whole unit, as Mesa truncates them and Kehoe's specification divides them; the
price stays p. The variant runs all 23 experiments that trade, with their 53 targets; the default is unchanged.

1. **It scores worse.** Chapter IV's trade targets go from 17 / 6 / 9 to 12 / 11 / 9, and Chapter VI's from 7 / 3 / 11
   to 5 / 5 / 11. Of 10 status changes, 8 are for the worse.
2. **Whole units keep prices apart.** For 1 < p < 2 every exchange is one for one, so trades stop before the
   MRSs meet. IV-3's dispersion at t≈1000 rises from 0.047 to 0.118 (book 0.05), and IV-12's lifespan rows overshoot.
3. **Trade volume falls by half to three quarters,** away from the book's (IV-3 34 → 12 per period; IV-15 267 → 69).
4. **What it helps:** the high-dispersion rows (IV-15 0.18 → 0.23, IV-17 0.27 → 0.46 against 0.45), by keeping
   prices apart rather than by thickening the market.
5. **Reading:** Fig IV-3's convergence argues that the original traded real amounts. Whatever it did with gifts,
   rounding doesn't explain the thin markets.

**Next steps now.** The other integer reading still open is winter growback (II-7): Kehoe's `1 div 8 = 0`, no growth
in winter, is untested (pulse growth is). Beyond that, look for the original program, or tag the current state.

## Where things are

| What | Where |
|---|---|
| Book reading, by rule and page | [docs/book-notes.md](docs/book-notes.md) |
| Design and anti-goals | [docs/superpowers/specs/2026-10-21-sugarscape-design.md](docs/superpowers/specs/2026-10-21-sugarscape-design.md) |
| Chapter plans | [docs/superpowers/plans/](docs/superpowers/plans/) |
| Chapter records (results, choices, diagnostics) | [chapter-2.md](docs/replication/chapter-2.md), [chapter-3.md](docs/replication/chapter-3.md), [chapter-4.md](docs/replication/chapter-4.md), [chapter-5.md](docs/replication/chapter-5.md), [chapter-6.md](docs/replication/chapter-6.md) |
| Rules | `sugarscape/rules/`; Schelling and Ring World in `sugarscape/variants/` |
| Experiments and targets | `experiments/registry.py`, `replication/targets.py` |
| Viewer (watch one run in the browser) | `viewer/`; [design](docs/superpowers/specs/2026-10-24-viewer-design.md) |
| xl, the 500×500 workload for comparing implementations | [docs/xl.md](docs/xl.md); `sugarscape/xl.py`, `sugarscape/maps/xl.py`; [design](docs/superpowers/specs/2026-10-24-xl-design.md) |
| Probe scripts behind the records; MASON, Ascape, SugarscapeCW and nkremerh harnesses | [diagnostics/](diagnostics/README.md), [diagnostics/mason/](diagnostics/mason/README.md), [diagnostics/ascape/](diagnostics/ascape/README.md), [diagnostics/sugarscapecw/](diagnostics/sugarscapecw/README.md), [diagnostics/nkremerh/](diagnostics/nkremerh/README.md) |

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

## Viewer

```bash
python -m viewer
```

This starts a local server on 127.0.0.1 and opens a browser tab. Pick any experiment on the sugar and spice
grid (Schelling and Ring World are not included) and a seed, then press Start. The page shows:
- **The board.** Cells blend sugar yellow and spice rust by their current levels, and agents are dots colored and
  sized by the attributes chosen in the menus (tribe and wealth = sugar + spice).
- **Population over time.** A chart of the number of living agents; click it to jump to a period.
- **Controls.** Play, pause, speed, step, and a slider back through the newest 500 periods (older ones are
  dropped to bound memory; the chart still shows the whole run).

What the page shows, and how to read it:
- **Exact values on hover.** Hovering over a cell shows its levels and capacities, and over an agent shows its
  attributes.
- **Fixed encodings.** The legend maps every color and dot size back to numbers, and nothing rescales from one
  period to the next. Wealth bands are < 10, 10–30, 30–100, 100–300 and ≥ 300.
- **Which moment.** The board at period t is the state after period t's rules have all run; t = 0 is the starting
  placement.
- **Seeds.** The seed is the run index used everywhere else, so seed k is the run saved as `seed{k}.csv` under
  `results/`.
- **When it computes.** Periods are computed only while playing, or one at a time when you step forward from
  the newest.

Keyboard: space plays and pauses, and the arrow keys step one period. `--port N` picks the port and
`--no-browser` skips opening a tab. The page's encoding tests run with `node --test "tests/js/*.test.mjs"`, and the
suite runs them too when Node is installed.

## xl

xl is the sugarscape at 10× the resolution: 500 × 500 sites, 100× the agents, vision, starting blocks and pollution
diffusion scaled to match, and agents looking at one random site in every 10 along their lines of sight, so a run
looks like a regular one, only more detailed. It is the shared workload for comparing this model with the FLAME GPU
port and the Julia version in `julia/`. [docs/xl.md](docs/xl.md) is the contract for other implementations: the map file
and its checksum, the configuration table, and the timing measures.

```bash
python -m experiments.run II-4 --xl --seeds 1
```

This writes the xl run to `results-xl/`. Every run, regular or xl, also writes `timing.csv` (setup, stepping and
metrics seconds per seed) and `machine.txt`. In the viewer, tick **xl** before Start. In Python an xl period takes
seconds rather than milliseconds (about 2.4 s for II-4's rules, 6.5 s for VI-1's).

## Julia

[julia/](julia/README.md) is a Julia port of the sugarscape model, every rule of Chapters II–VI, that runs every
sugarscape experiment of the registry at regular and xl size and writes results in this runner's layout. Its
comparison report (`python -m bridge.report`, from `julia/`) tests agreement with this model's saved results metric
by metric, scores both against the book's targets, and puts their timings side by side. Across all 134 experiments
Julia agrees with Python (no flagged difference in 8,165 tested windows), and II-4 at xl agrees too, about 84× faster
per period. The method and every follow-up are in [julia/docs/validation.md](julia/docs/validation.md).
