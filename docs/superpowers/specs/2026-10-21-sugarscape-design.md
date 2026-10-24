# Sugarscape 2026 — Design

Date: 2026-10-21. Companion to [`docs/book-notes.md`](../../book-notes.md), which holds
the rules, parameters, and target numbers this design refers to.

## Intent

Rebuild Sugarscape as faithfully as possible to Epstein & Axtell, *Growing Artificial
Societies* (1996), and reproduce the book's results. Success means each figure and
animation in Chapters II–VI can be regenerated from a named experiment, and its
measurable outcome lands within an agreed tolerance of the book's value.

**Goals**
- Implement every rule in the book: G_α, S_αβγ, M (sugar, pollution, two-commodity),
  R[a,b], P, D_α, S, I, K (transmission + group membership), C_α, T, L_dr, E, foresight
  welfare, culturally varying preferences, plus Chapter VI's Schelling and Ring World.
- One named experiment per book figure/animation, with its exact rule set and parameters.
- An automated replication report comparing our outputs with the book's numbers.
- Deterministic, seed-reproducible runs (the book stresses this, Ch II fn 16).

**Non-goals**
- Synchronous/parallel updating (the book is explicitly sequential, Ch II fn 12).
- Speed for its own sake; runs only need to be fast enough for multi-seed sweeps.
- A polished GUI. A viewer comes after the core is verified (built 2026-10-24: [viewer design](2026-10-24-viewer-design.md)).

**Anti-goals** (would count as failure even if the code runs)
- Silently picking a value where the book is silent. Every such choice is a named,
  documented setting.
- Taking Kehoe's (2016) interpretation where it contradicts the book.
- Tuning parameters away from the book's stated values to make a number match.

## Language and tools (my call)

- **Python 3.14** in a project virtual environment (`.venv`), already installed here.
- **NumPy** for the lattice arrays and the random generator; **matplotlib** for figures
  and animation frames; **pytest** for tests.
- Rationale: rule fidelity and readability matter more than speed. The largest runs
  (~1,500 agents × 3,000 steps, up to 10 seeds per data point) are feasible in plain
  Python. If a sweep proves too slow, the hot loops (movement scan, trade loop) can be
  optimized later without changing semantics; tests pin the behavior first.
- Before writing code that uses NumPy, matplotlib, or pytest, check their current docs
  via Context7 (per the user's standing instructions).

## Architecture

```
sugarscape/
  config.py        # One frozen dataclass per run: grid, rule toggles, parameter ranges, seed
  rng.py           # Single seeded numpy Generator passed everywhere; no global random
  landscape.py     # Lattice: sugar/spice level & capacity, pollution; torus helpers
  maps/            # 50x50 capacity maps (sugar, spice) as text files + loader
  agent.py         # One Agent class (as in the original, App. A): genetics, holdings, tags,
                   #   immune string, diseases, children, loans, neighbor list
  rules/
    growback.py    # G_alpha, S_alpha_beta_gamma
    movement.py    # M: sugar, pollution (s/(1+p)), two-commodity welfare, foresight
    pollution.py   # P (formation), D_alpha (diffusion)
    replacement.py # R[a,b]
    sex.py         # S, genetic + cultural crossover
    inheritance.py # I
    culture.py     # tag flipping + group membership (K), friends network
    combat.py      # C_alpha with retaliation
    trade.py       # T, MRS, bargaining, welfare (incl. culturally varying preferences)
    credit.py      # L_dr
    disease.py     # E: immune response + transmission
  model.py         # The scheduler: one step() applying enabled rules in a fixed order
  stats.py         # Gini/Lorenz, histograms, means, price statistics, network stats
  networks.py      # Neighbor, genealogy, friends, trade, credit, disease graphs
  variants/
    schelling.py   # Ch VI Schelling variant (separate small model)
    ringworld.py   # Ch VI Ring World (separate small model)
experiments/
  registry.py      # Named experiments: "II-4", "III-3", "IV-6", "VI-3", ...
  run.py           # CLI: run an experiment for N seeds → CSV + PNG in results/<id>/
replication/
  targets.py       # Book target values with tolerance bands (from book-notes.md)
  report.py        # Runs/collects experiments, writes results/REPORT.md (pass/near/fail)
tests/             # pytest: unit, invariant, and replication tests
```

Design rules:
- **Single agent class**, rules as plain functions taking `(model, agent)`; rules read the
  config to know which variant applies. This mirrors the original's single-class design
  and keeps rule code next to its book wording.
- **Each rule cites its source** in a docstring (book page, and Kehoe only when used as a
  gap-filler).
- **Every interpretive choice is a config field** with a default and a comment naming the
  ambiguity (e.g. `disease_remove_on_immunity: bool = True`).
- Holdings and site levels are **floats** (trade moves fractional amounts; winter
  growback is fractional). Capacities and genetics are integers.

## Scheduling (the key interpretive decision)

The book never states the order, but Chapters II–IV describe agents acting one at a time
in a random order, each moving and then interacting with its new neighbors. Each period:

1. Shuffle the living agents (new random order every period).
2. For each agent still alive, in that order:
   1. **Move** by M, or by C_α when combat is on; harvest the site (pollution formation
      if P is on).
   2. **Metabolize**: subtract metabolism (+1 per active disease); consumption pollution.
      If any holding ≤ 0, the agent dies now (inheritance and loan rules apply).
   3. Record post-move neighbors (neighbor network, Ch II p.39).
   4. Interact with neighbors, each in random order: **S** (sex), **K** (culture),
      **T** (trade), **L** (credit), **E** transmission, then E immune response for self.
3. End of period: age everyone by 1; agents reaching max age die (with I, loans);
   R replaces the dead if on; process due loans; growback (G or S); diffusion every α
   periods; record statistics.

Consequences: newborns and replacements join next period's shuffle; a site's growback
happens after all agents act, so a fresh run starts with sites at capacity. The order of
the interaction sub-steps in 2.4 only matters when several rules run together (Ch VI);
it is a documented choice.

## Interpretive defaults

Taken from `book-notes.md`; each becomes a config field.

| Issue | Default | Source |
|---|---|---|
| Current site is a movement candidate | Yes, at distance 0 | Kehoe, consistent with book |
| Direction scan order / ties | Random direction order per agent; nearest wins; first encountered on ties | Book fn 8–9 |
| Death threshold | Holding ≤ 0 | Book p.25 |
| Mating wealth test | Current wealth ≥ own initial endowment | Book p.55 |
| Child endowment | Half of each parent's *initial* endowment, deducted from parents | Book p.55 |
| Child placement | Random empty von Neumann site of either parent | Not stated: our call |
| Replacement harvest on arrival | No | Kehoe |
| Retaliation check | From proposed site, attacker's vision; stay put if no safe site | Kehoe |
| Disease penalty | +1 metabolism per non-immune disease | Book "say, one"; Kehoe |
| Immune disease removed from carried set | Yes | Our reading of Ch V |
| Transmit only active (non-immune) diseases | Yes | Our call; flagged |
| Credit child requirement | Borrower's own initial endowment | Book p.55, p.132 |
| Interest | Simple: principal × (1 + r·d) | Kehoe |
| Two-commodity combat wealth | Sugar + spice | Kehoe |

## Landscape data

The capacity map exists only as Figure II-1. Plan: use the widely circulated 50×50
`sugar-map.txt` (the version used by the NetLogo Sugarscape models, derived from the
original), checked against Figure II-1 (peaks NE and SW, max 4, terraced). The
spice map for Chapter IV is the sugar map mirrored left to right (peaks NW and SE),
checked against Figure IV-1. Downloading the file needs the user's OK at that step. A
fallback is to reconstruct terraces from Figure II-1 by hand.

## Verification

Three layers, all in pytest:

1. **Rule unit tests against the book's worked examples.**
   - Appendix C: wealth (20, 50) prefers site (3, 3) over (2, 5); wealth (150, 250)
     prefers (2, 5).
   - Table V-1: immune string 1011101001 vs disease 10011 → position 1 chosen, one bit
     flip, result 1001101001.
   - Figure IV-2 trade example: A (5, 8), B (15, 2), with MRS direction and price.
   - Growback formula, seasonal formula (fn 33), diffusion averaging, Gini on known
     distributions, tag majority, vertical tag crossover.
2. **Invariant tests** run every step on random configurations: one agent per site,
   no negative site levels, trade conserves totals and raises both welfares, MRSs never
   cross, loans balance, population accounting (births − deaths).
3. **Replication tests** (marked `slow`): each registered experiment runs over several
   seeds and compares a summary statistic with the book's value, using tolerance bands:
   - Point targets: carrying capacity ≈224 (II-4), Gini 0.23→≈0.50 (II-4),
     average neighbors ≈0.9 (II-5), vision 3.5→4.1 and metabolism 2.5→1.8 at t=500,
     Gini ≈0.74 with I (III-7), σ(ln p) ≈0.05 at t=1000 (IV-5), Fig II-5 / IV-6 /
     IV-13 curves point by point.
   - Regime targets: population steady near 500 (III-1), oscillation period and
     amplitude (III-3, III-4, VI-3: period ≈115, range 700–1200), extinction (III-5, VI-2),
     disease cleared vs endemic (V-1, V-2).
   - Qualitative targets as measurable proxies: diagonal wave (population centroid
     moving NE, II-6), migration/hibernation by vision class (II-7), tribe convergence to
     all-Blue/all-Red (III-8), Schelling segregation index ordering (VI-4 < VI-6 ≈ VI-7),
     Ring World cluster count and sizes (VI-8, VI-9).
   Tolerances start loose (the book reports single runs) and tighten as we learn the
   seed-to-seed spread. The report lists every target as pass / near / fail with the
   observed mean and range, so mismatches are visible rather than hidden.

## Delivery order

Each stage ends with its replication report section green or explained.

1. Skeleton, config, RNG, landscape + maps, test harness.
2. Chapter II: G, M, R, S_αβγ, P, D; Gini/Lorenz; neighbor network.
3. Chapter III: S, I, K, friends, genealogy, C_α; proto-history.
4. Chapter IV: spice, welfare, T, price stats, culturally varying preferences,
   pollution & prices, foresight, L_dr.
5. Chapter V: E.
6. Chapter VI: all-rules run, indecomposability, Schelling, Ring World.
7. Viewer: animation frames comparable to the book's panels.

## Left to the builder

Module internals, data structures for the agent registry and occupancy grid, CSV
column names, plot styling, and CLI flags.
