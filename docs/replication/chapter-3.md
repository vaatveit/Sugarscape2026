# Replication report

10 pass, 4 near, 11 fail, of 25 targets.

| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |
|---|---|---|---|---|---|---|---|
| III-1 | steady population | Fig III-1, p.58 | 500 | 400–600 | 359.8 [340.6–381.7] | 5/5 | near |
| III-1 | small fluctuations | p.57 | 0.1 | 0–0.1 | 0.05902 [0.04226–0.07614] | 5/5 | pass |
| III-1 | mean vision at t≈900 | Fig III-2, p.63 | 5.3 | 4.8–5.8 | 5.685 [5.357–5.925] | 5/5 | pass |
| III-1 | mean metabolism, t=300–900 | Fig III-2, p.63 | 1 | 0.9–1.15 | 1.001 [1–1.002] | 5/5 | pass |
| III-3 | oscillation period | p.64 | 200 | 150–250 | 493 [349–637] | 2/5 | fail |
| III-3 | population floor | p.64 | 250 | 200–350 | 18.4 [0–48] | 5/5 | fail |
| III-3 | agents that ever lived | p.64 fn 10 | 1.25e+04 | 1e+04–1.5e+04 | 1613 [454–3734] | 5/5 | fail |
| III-4 | oscillation period | p.65 | 125 | 100–150 | 117.8 [114–122] | 5/5 | pass |
| III-4 | oscillation range | Fig III-4, p.65 | 1000 | 600–1400 | 119.6 [104–137] | 5/5 | fail |
| III-5 | extinction frequency (proxy) | Fig III-5, p.66 | — | 0.5–1 | 0 [0–0] | 10/10 | fail |
| III-7 | Gini with inheritance | p.67 | 0.743 | 0.65–0.85 | 0.3461 [0.318–0.3866] | 5/5 | fail |
| III-7 | mean vision at t≈900 | Fig III-7, p.68 | 4.3 | 3.9–4.7 | 5.134 [4.81–5.5] | 5/5 | fail |
| III-8 | each side culturally pure (proxy) | p.74 | — | 0.8–1 | 0.4 [0–1] | 5/5 | fail |
| III-8 | time until every side is pure | p.74 | 2700 | 1350–5400 | — [—–—] | 0/5 | fail |
| III-8 | best-friend closeness | Anim III-8, p.80 | 0.91 | 0.8–1 | 0.9819 [0.9791–0.9857] | 5/5 | pass |
| III-9 | one of the three patterns (proxy) | p.83 | — | 0.8–1 | 1 [1–1] | 10/10 | pass |
| III-11 | both tribes persist (proxy) | Anim III-11, p.86 | — | 0.8–1 | 1 [1–1] | 5/5 | pass |
| III-12 | Blue wave advances NE (proxy) | Anim III-12, p.88 | — | 10–60 | 8.122 [7.918–8.245] | 5/5 | near |
| III-12 | Red wave advances SW (proxy) | Anim III-12, p.88 | — | -60–-10 | -4.652 [-5.752–-3.575] | 5/5 | near |
| III-13 | combat suppresses Blue's wave (proxy) | Anim III-13, p.89 | — | -5–5 | 9.62 [9.024–10.73] | 5/5 | near |
| III-14 | no runaway hegemony (proxy) | p.90 | — | 0.5–1 | 0.5 [0–1] | 10/10 | pass |
| III-15 | Red and Blue on opposite mountains | p.92 fn 32 | 0.45 | 0.3–0.5 | 0.05 [0–1] | 20/20 | fail |
| III-15 | Red dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0.2 [0–1] | 20/20 | pass |
| III-15 | Blue dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0.1 [0–1] | 20/20 | pass |
| III-15 | extinction (small frequency) | p.92 fn 32 | — | 0–0.15 | 0.3 [0–1] | 20/20 | fail |

Run: `python -m replication.report --chapter III --jobs 8` on 2026-10-21 (branch feat/chapter-3, after the final-review fix pass). Seeds as registered (5, 10, or 20).
Fast suite 144 passed; `pytest -m slow tests/test_replication_ch3.py`: 11 passed, 13 failed (the near + fail rows).
Re-run 2026-10-22 (branch feat/repro-calibration) after the calibration settings changed every fingerprint: every row identical, plus the new III-3 row for footnote 10.
Re-run 2026-10-22 (branch feat/founder-ages) after founders with finite lives began at ages U[0, max age) (user decision; see the Chapter III record): the table above. Changed rows are listed under Founder ages.
Chapter II regression run on the same branch: 19 pass / 12 near / 0 fail, every row identical to docs/replication/chapter-2.md.

## Choices made from evidence or by necessity

- **Combat blocks** measured from frame 1 of Animations III-9 and III-12: Blue 20×20 at the SW corner, Red 20×20 at the NE corner, ≈270 agents each (III-9/14) and ≈370 each (III-12/13). III-11 uses 200 each ("fix the population at 400", p.86).
- **Proto-history** starts with 100 agents ("small, low density"); the book gives no number.
- **Culture runs go to absorption** (III-8, III-15 run to t=6000 and are classified there): the book describes eventual states ("ultimately converge", p.74; fn 22; fn 32's frequencies), the same principle as the t=500 carrying-capacity decision.
- **Endowments**: 50–100 for the sex runs (p.57), 10–40 where p.65 lowers "the sugar necessary for reproduction"; 25–50 (the Chapter II finding) for the culture and combat runs.

## What matches

- Evolution under S (Fig III-2): mean vision 5.6 at t≈900 (book 5.3), metabolism falls to 1.0 (book 1.0).
- Population stability under default S: relative fluctuation 5.5% (book "less than 10 percent").
- Large-oscillation period: 118 (book ≈125).
- Best-friend closeness 0.98 (book 0.91).
- Combat (III-9): every run ends in one of the book's three patterns (eradication, or frozen coexistence of small colonies); same-tribe war of attrition persists (III-11); combat with assimilation avoids runaway hegemony in half the runs (III-14).
- Proto-history (III-15): Red dominates both mountains in 30% of runs and Blue in 30% (book ≈25% each); no extinctions.

## Open discrepancies (investigated, unresolved)

1. **Population dynamics are too damped and too low under S.** Steady population ≈369 vs ≈500 (III-1); small-oscillation run nearly dies out (floor 24 vs ≈250; period ≈720 vs ≈200) (III-3); large-oscillation run swings ≈144 vs ≈1000 around a high mean (III-4); the combined run never goes extinct (III-5). Animation III-2 shows the book's population spilling into the lowlands; ours stays on the peaks.
   **State of the question (final review's flow accounting, III-1 seed 0, t=200–600):** births (4.6–4.7/period) equal old-age deaths, starvation is 0. Agents harvest ≈870 sugar/period and burn ≈350, and **≈520 (60% of all harvest) is destroyed at old-age deaths**. Only 45% of fertile-age agents meet the wealth test (mean wealth 82 vs threshold ≈75). After a birth, regaining half the endowment (≈37.5) takes ≈25 periods. **Births are wealth-cycle-limited, not partner-limited.** Founders start exactly at the threshold, so those with negative net income are sterile for life: lifetime children by metabolism m=1: 168 (98 agents), m=2: 72, m=3: 21, **m=4: 0 (113 agents)**. The book's Fig III-4 boom (400 → ≈1500 by t≈45) would need net income ≳2.5/period per agent, close to the whole map's regrowth, which the rule as written can't supply. So the gap is likely an unstated detail of the original's wealth accounting.
   Ruled out: random initial ages (worse); Moore mating neighbors (+2–6%); fertility end inclusive (no change); evolution speed (ours is as fast or faster); food supply (Chapter II metabolism-1 capacities match within 2%). Sensitivity: removing the parents' cost fills the lattice (≈2000); a threshold of half the endowment gives ≈950 (III-1). Neither is the book's rule. **III-3 sits on a knife-edge**: small changes (Moore + inclusive end) move its floor from 46 to 179, so its miss carries little diagnostic weight.
   **Probe of two wealth-accounting hypotheses (2026-10-21, user-requested; 3 seeds, 1000 periods, all 8 combinations with founder ages):**

   | Founder ages | Founders' fertility threshold | Child's recorded endowment | III-1 t20 / t85 / t240 / t330 / late (book 470 / 570 / 415 / 545 / 500) | III-4 first peak, trough, late range, period (book 1554@71, 343, ≈1000, 125–136) |
   |---|---|---|---|---|
   | all 0 | = its sugar | sum of gifts (current) | 464 / 324 / 372 / 369 / 361 | 1282@115, 925, 235, 119 |
   | all 0 | drawn independently | sum | 481 / 357 / 449 / 379 / 381 | 1302@109, 920, 253, 118 |
   | spread 0..max age | = its sugar | sum | 354 / 149 / 394 / 323 / 364 | 1343@123, 837, 349, 120 |
   | spread | independent | sum | 337 / 127 / 336 / 394 / 390 | 1380@123, 832, 373, 115 |
   | any | any | one parent's gift | runaway: 1,800–2,000 (lattice full) | ≈1,750–1,800 plateau, range ≈120, no cycle |

   - **Child's recorded endowment = one parent's gift: rejected.** The recorded endowment halves each generation, so the breeding threshold shrinks toward zero and the lattice fills.
   - **Founders' sugar independent of their recorded endowment: rejected as the explanation.** +5% on III-1 (381 vs ≈500), no change to III-4's swings.
   - **Founders with a spread of ages** (suggested by Animation III-1's first frame) help III-4 a little but make III-1's early curve much worse (149 vs 570 at t=85).
   - No combination reproduces both figures. The book's III-4 boom (≈430 → 1554 by t≈71) and crash (to 343) stay out of reach; our III-4 booms later and lower (≈1300 at t≈110) and barely crashes (≈920).
2. **Inheritance barely raises inequality** (III-7 Gini 0.33 vs 0.743) **or slows selection** (vision 5.29 vs ≈4.3). With I, recycled wealth funds births in the wealth-limited regime and the population triples (≈1,370 at t=1000) instead of dynasties keeping wealth. This is the same unknown as item 1.
3. **Culture never quite absorbs.** III-8 at t=6000: sides sit at 91–98% one color (2 of 5 runs have both sides ≥95%), and no run reaches 100% on every side (book: all agents Blue after ≈2700). A few holdout agents per side never convert. Tag positions drift like a voter model (one NE position went 83% → 95% → 34% zeros between t=1000 and 3000), consistent with the book's process but slower to finish. III-15: mountains usually end the same color (single-color dominance 60%), Red and Blue on opposite mountains only 5% (book ≈45%).
4. **Waves (III-12) are not reproduced** — the same failure as II-6. Measured as net NE-ward travel (unwrapped across the map's edges), Blue advances ≈8 and Red ≈5 by t=50, with or without combat (III-13: ≈9.6). There is no wave to suppress, so III-13 says nothing yet.

## Founder ages (2026-10-22)

**Decision (user, 2026-10-22):** in runs with finite lives, founders start at ages U[0, max age); newborns and replacements start at 0 (`Config.founder_ages`, default `"uniform"`; `"zero"` restores the old behavior). Immortal runs draw nothing and are unchanged.

**Evidence:**
- **Animation III-1's first frame** (the age histogram for Fig III-1) holds 417 agents spread across every decade: 63, 49, 45, 64, 45, 55, 49, 30, 13, 4. Ages U[0, max age) with max ages 60–100 predict ≈51 per decade to 60, then 42, 29, 16, 5. Age-0 founders would put all 400 in the first bin.
- **Fig III-1** starts near 417 and climbs at once. With spread ages our first period gives 418; with age-0 founders nobody can breed before age 12.
- **VI-2** shows births in its first three periods.
- **Ascape's code** uses `randomInRange(0, deathAge)`.

**What changed in this chapter** (5 seeds unless stated):

| Row | Age-0 founders | Spread ages |
|---|---|---|
| III-1 steady population | 369 near | 360 near |
| III-1 early curve t=20 / 85 (book 470 / 570) | 465 / 333 | 356 / 136 |
| III-3 floor / agents that ever lived | 24 / 2,593 | 18 / 1,613 |
| III-3 period | 723 (3/5) | 493 (5/5) |
| III-4 range | 144 | 120 |
| III-7 Gini / vision | 0.33 / 5.29 | 0.35 / 5.13 |
| III-15 extinction (book: rare) | 0/20 | **6/20, pass → fail** |

**Why it hurts:** with spread ages nearly every founder dies of old age within about 85 periods, and the book's society replaces them, climbing to 570 by t=85 (≈6.5 births per period). Ours manages ≈2.5 per period (diagnostic run with the 0.83 threshold, 2 seeds). The first-period baby boom (≈60 births) leaves ≈120 parents at half their endowment, so until t≈50 fertile-age agents average 51–54 sugar against a requirement near 62. And with ≈0.85 neighbors per agent, only 0–4 qualifying agents have a qualifying partner next to them at any moment. The founders' ages are now right; the birth rate is the open problem.

## Birth-rate decomposition (2026-10-22)

Diagnostic probes of III-1 under the current defaults (spread founder ages, book rule S); nothing here changes the model. 5 seeds for the counts, 3 for the counterfactuals.

**Where mating turns fail** (per period):

| Window | N | Births | Fertile-age agents | Share passing the wealth test | Fertile turns with a fertile partner adjacent | Mean wait while fertile |
|---|---|---|---|---|---|---|
| t=0–20 | 391 | 2.9 | 197 | 32% | 5% | 11 periods |
| t=20–85 | 231 | 1.6 | 99 | 42% | 4% | 13 |
| t=500–1000 | 359 | 4.6 | 169 | 43% | 6% | 8 |

- **Space never binds:** no mating attempt with a fertile partner ever failed for want of an empty site.
- **The first period matches the book:** 191 founders are fertile at t=0 and 14 children are born. Animation III-1's first frame (417 agents, about 12 more in the 0–9 bin than spread ages predict) implies about 12–17 births in the book's first period, so the starting contact rate agrees.
- **The fertile pool then collapses through wealth, not mating:** 191 → 90 → 77 → 55 by t=5, with only about 25 births. Every agent starts life exactly at its threshold, so one period of negative net income makes it sterile. Founders' net income at t=5–30 by metabolism: m=1 +1.45, m=2 +0.45, m=3 −0.57, m=4 −1.54 per period.

**Counterfactuals** (diagnostic only; "global" lets a fertile agent meet up to 4 random fertile partners anywhere, so contact is free):

| Contact | Threshold | t=20 / 85 / 240 (book 470 / 570 / 415) | Mean t=300–1000 (book ≈500) | Births per period t=20–85 |
|---|---|---|---|---|
| von Neumann (book) | 1.0 | 364 / 129 / 368 | 352 | 1.5 |
| radius 2 | 1.0 | 379 / 174 / 419 | 417 | 2.2 |
| global | 1.0 | 413 / 258 / 454 | 509 | 3.2 |
| von Neumann | 0.83 | 398 / 208 / 467 | 481 | 2.5 |
| global | 0.83 | 460 / 353 / 706 | 668 | 4.5 |

**Sugar budget** (per period, 3 seeds):

| Window | N | Harvest | Metabolism | Gifts to children | Lost at death | Mean metabolism |
|---|---|---|---|---|---|---|
| t=0–20 | 394 | 953 | 980 | 222 | 328 | 2.5 |
| t=20–85 | 233 | 665 | 481 | 114 | 342 | 2.0 |
| t=300–1000 | 352 | 875 | 352 | 346 | 519 | 1.0 |

**Findings:**
- **The steady level is limited by contact and wealth together.** Free contact alone raises it to the book's ≈500, and a 0.83 threshold alone gives 481. Either lever suffices, so the steady level alone can't say which detail the original differs in.
- **The early boom is limited by wealth alone, and no tested lever reproduces it.** The book needs about 555 births by t=85 (≈6.5 per period) to replace the dying founders and reach 570. With free contact the book's rule manages 3.2 per period; adding the 0.83 threshold still gives only 4.5, and 353 agents at t=85.
- **Why:** the unselected founders (mean metabolism 2.5) burn more than they harvest, so almost no one can re-earn the half-endowment a second birth costs. Births come from each agent's one "free" first event, at the threshold it was born with. Meanwhile ≈29,000 sugar, nearly all of the founders' 30,000 endowment, is lost at old-age deaths by t=85: it dies with post-fertile founders and never funds a birth.
- **So the book's early curve needs much cheaper births relative to early incomes,** or much higher early incomes, than rule S as read allows. The map's regrowth ceiling (2,069 sites at one unit each per period) is above what our agents harvest (953), so higher incomes aren't ruled out; but they would have to come from the same movement rule that matches Chapter II's carrying capacities. This points at the cost or threshold of reproduction, not at contact, placement, or timing, which were probed earlier. It remains unresolved.

## Income, cost and threshold (2026-10-22)

Follow-up diagnostics of the decomposition above (III-1, spread founder ages, 3 seeds unless stated). Nothing here changes the model.

**The text leaves no room on cost or threshold.** p.55: "Dad contributes an amount equal to one half of whatever his initial endowment had been, and likewise for mom"; parents "must have amassed at least the amount of sugar with which they were endowed at birth". p.65 calls the endowment range "the amount of sugar necessary for reproduction". Footnote 3 (multiple births "occasionally"; fertile agents "rarely possess enough wealth to have multiple children in a single period") doesn't discriminate: every variant below has 2+ births in at most 2% of turns with a birth.

**Higher incomes are ruled out.**
- Chapter II validates the harvest rule: all 18 Fig II-5 points match within ±5% at t≈45–60, where the book read them (Chapter II record).
- N immortal, non-breeding agents with III-1's genetics earn, per agent per period over t=1–85: N=300 +0.06 net (harvest 2.56), N=400 −0.21 (2.32), N=500 −0.44 (2.10), N=600 −0.53 (2.00). At the book's early population the unselected agents run a deficit.
- Doubling regrowth (G2, twice any income Chapter II allows) still gives only 234 agents at t=85 (book 570); G1.5 gives 177.

**Threshold θ (share of the birth endowment a parent must hold) and cost k (share each parent gives).** Child's recorded endowment = parents' mean, so cheap births don't compound:

| θ | k | t=20 / 85 / 240 (book 470 / 570 / 415) | Mean t=300–1000 (book ≈500) |
|---|---|---|---|
| 1.0 | 0.5 (book) | 364 / 129 / 368 | 352 |
| 1.0 | 0.25 / 0.1 | 366 / 141 / 291; 387 / 121 / 298 | 281; 277 |
| 0.75 | 0.5 / 0.25 / 0.1 | 408 / 265 / 603; 447 / 281 / 581; 483 / 261 / 396 | 637; 579; 435 |
| 0.5 | 0.5 / 0.25 / 0.1 | 445 / 453 / 1113; 520 / 579 / 837; 565 / 712 / 925 | 936; 918; 855 |

- **A cheaper child alone doesn't help:** the child starts further below its own threshold.
- **The threshold is the only lever, and no value fits Fig III-1's whole curve.** θ=0.5 reproduces the boom but settles near 900; θ≈0.83 fits the late level but not the boom. In every case the late population is birth-limited: starvation is zero after t=300.
- **A margin for founders only can't make the boom:** even with no wealth test for founders, t=85 reaches 287 (others θ=1) or 344 (others θ=0.83).

**The book's two runs of these rules disagree.** Animation III-2 and III-3 show one run (identical frames, different coloring); Fig III-2's evolution curves come "from animations III-2 and III-3" (p.61). Agents counted in its six frames (dark blobs; counts stable across three thresholds; frame 1 gives 384 of 400): **384 → 172 → 325 → 876 → 669 → 1,019**. Frame 2 is confined to the two peaks. Fig III-1 (and Animation III-1's 417–535-agent histograms) never exceed ≈575, so the animations are a different run.

| Our III-1 (5 seeds) | Lowest N before t=400 | Share then on sites of capacity ≥3 | Mean (range) t=300–1500 |
|---|---|---|---|
| Spread founders, θ=1 (book) | 126 at t≈94 | 0.99 | 358 (304–407) |
| Spread, θ=0.83 | 207 at t≈87 | 0.96 | 480 (401–548) |
| Spread, θ=0.75 | 262 at t≈81 | 0.92 | 651 (522–754) |
| Age-0 founders, θ=1 | 217 at t≈130 | 0.96 | 367 (314–410) |
| Age-0, θ=0.83 | 336 at t≈111 | 0.86 | 506 (426–574) |

**What this shows:**
- **The early dynamics depend on the run.** The animation run crashes to ≤172 agents on the peaks, as ours does under the book's rule with spread founder ages (126, 99% on the peaks), while Fig III-1's run climbs to 570. So Fig III-1's early boom isn't a robust feature of the book's model, and it carries little weight as evidence against the rule.
- **The long-run level is ours alone to miss.** The book's runs settle at ≈500 (Fig III-1) and ≈670–1,020 (the animation run); ours settles at ≈360. A lower threshold reaches either level (θ≈0.83 and θ≈0.75), but then the crash is shallower than the animation's (207 and 262 against ≤172).
- **Remaining question:** why the book's selected, long-run population breeds more than ours under the same written rule. Income, cost, contact, placement and timing don't account for it.

## What sets the long-run level (2026-10-22)

Diagnostics of III-1 after t=300 (book rule, spread founder ages, 5 seeds, 27,802 completed lives); nothing here changes the model.

**Ruled out:**
- **Absolute wealth.** Animation II-3's run (250 agents, G1, R[60,100], endowment 5–25) is the book's only absolute wealth record. Its late frame (bins of 27 to 270) holds 122, 37, 28, 25, 18, 7, 9, 2, 0, 2 agents, a mean of ≈52.5. Ours at t=500–1000 holds 106, 49, 32, 26, 16, 8, 10, 2, 1, 0, with means of 50–54. Accumulation rates match at that density.
- **Lifespan.** Maximum age doesn't drift: the mean of the living stays at 79–80 and agents die at 78–79. The 70–79 / 0–9 age-bin ratio is ≈0.7, within Animation III-1's 0.68–1.0. Drawing children's maximum age fresh instead of inheriting it changes nothing.

**The level is set by women's wealth cycle:**

| | Women | Men |
|---|---|---|
| Children per completed life | 1.90 (0/1/2/3: 6% / 6% / **81%** / 7%) | 1.92 (8% / 15% / 52% / 24%) |
| Fertile-age years, of which wealth-fertile | 30.1, **8.5** | 40.0, 21.9 |
| Net income while of fertile age | 1.44 per year | 1.45 |
| Wealth at fertility start | 1.25 × threshold (all ≥ 1) | 1.26 × |
| Age at first child; gap to the next | 18.4; 12.5 years | 24.0; 14.5 |

- A woman starts fertile life a quarter above her threshold. The first child costs half her endowment. The second needs it re-earned, which takes 12.5 years on average including the wait for a partner. A third would need another 37.5 sugar (≈26 years), past the end of her window, so nearly every woman stops at two.
- The population therefore settles where a woman's net income just fits two children into her window: ≈1.45 per year.
- Net income of evolved agents (metabolism 1, vision 5–6) by population: **N=250 +1.87, 350 +1.46, 500 +1.12, 700 +0.99, 1,000 +0.61.** 1.45 is reached at N≈350, our level.

**What the book's levels would require under the written rule:**
- **Fig III-1 (≈500):** about 30% more net income per agent at N=500 than our map and movement give (≈1.45 against 1.12), or much shorter waits for partners. Free contact gives 509 (Birth-rate decomposition, above).
- **The animation run (≈670–1,020):** even with no waiting, a woman must net ≈37.5 by about age 45, i.e. ≈1.0 per year from birth. Ours falls below that at N≈700. Near 1,000 agents it would take nearly all of the map's regrowth (2,069 units per period at most, ≈2,000 needed), where ours harvests ≈78%.
- **A shared cause with Chapter II is possible.** Fig II-5's metabolism-2 points are 18% low at t=500 (Chapter II record, open discrepancy 1). If the book read them at the asymptote rather than near t≈50, that gap and this one would both say that our harvest per agent falls off faster with density than the book's. At N≈250 we match (II-4's 224, II-3's wealth). This is consistent, not proven, and no movement detail tested so far produces it; "agents must move" was rejected in Chapter II.

## Calibrated reproduction variant (2026-10-22)

**Why.** The sex rule as the book states it doesn't reproduce the book's own population figures, and other replications confirm this is the published rule, not our code:
- **Kehoe's DCU thesis** (§7.3.5) implemented the rule formally; his population collapsed before t=2500 under every updating strategy, and he concluded it must be "clarified by the original developers".
- **MASON** (Bigbee, Cioffi-Revilla and Luke 2007) graded III-1, III-3 and III-5 as general matches. Its source uses our map (identical up to rotation) and our charging rule. Its child placement ignores occupancy, so births are never limited by space and overwritten agents keep acting off the grid; not a reading we can adopt.
- **Ascape** (Brookings) departs from the text: founders at random ages, children cost at most 5 sugar, and a child's fertility threshold is a fresh random draw.
- **Kremer-Herman and Gupta (2023)** default to exactly our reading.

**Readings probed first** (3 seeds; none adopted, none reproduces the figures together):
- **Founders at random ages:** fixes VI-2's crash, but worsens III-1 and VI-3.
- **A child's threshold redrawn at random:** no effect.
- **Ascape's cheap children:** III-1 goes extinct, or settles near 210.
- **Mating before metabolism:** negligible.
- **The current site never a destination:** III-3 dies out.
- **p.65 as a 10–40 fertility threshold with 50–100 endowments:** more growth, no crashes; III-5 is never extinct.

In III-1 the gap opens in the first generation. Our population matches at t=20 (464 against 470) but falls to 324 by t=85, while the book's rises to 570. Only 17–25% of fertile-age agents hold their endowment, so births run at ≈3.5 per period; no child starves.

**Protocol.** Two settings, each defaulting to the book's rule (`Config.fertility_threshold` = 1.0, `child_share` = 0.5).
- **Fitting:** each was fitted to one number only, III-1's steady population (500; mean over t=500–1500, 5 seeds).
- **Freezing:** the fitted values were frozen before any other run.
- **Validation:** each setting then ran unchanged on III-1's other rows, III-3, III-4, III-5, VI-2 and VI-3, as experiments `CAL-thr/…` and `CAL-share/…` with the same targets (`python -m replication.report --chapter CAL`).

| Setting | Grid (III-1 mean population) | Fitted |
|---|---|---|
| `fertility_threshold` | 0.5: 942, 0.6: 858, 0.7: 738, 0.8: 530, **0.83: 506**, 0.84: 476, 0.9: 423, 1.0: 367 | **0.83** |
| `child_share` | 0.3–0.4: ≈1650, 0.45: 1538, 0.49: 933, 0.495: 703, **0.4975: 496**, 0.499: 396, 0.5: 367 | **0.4975** |

`child_share` below 0.5 compounds across generations: a smaller gift lowers the child's endowment, and that endowment is the child's own fertility threshold. So the population is hypersensitive to it, which already counts against it as a hidden detail of the original.

**Validation** (the fitted III-1 population row is excluded; book = the book-faithful runs):

| Target | Book value | Book-faithful | `fertility_threshold` 0.83 | `child_share` 0.4975 |
|---|---|---|---|---|
| III-1 fluctuation (≤0.10) | 0.10 | 0.055 pass | 0.074 pass | 0.226 fail |
| III-1 vision / metabolism | 5.3 / 1.0 | pass / pass | 5.65 pass / 1.0 pass | 5.69 pass / 1.0 pass |
| III-3 period | 200 | 723 (3/5) fail | 315 fail | none found, fail |
| III-3 floor | 250 | 24 fail | 174 near | 51 fail |
| III-3 agents that ever lived (fn 10) | 12,500 | 2,593 fail | 8,739 near | 5,144 fail |
| III-4 period | 125 | 118 pass | 123 pass | 261 fail |
| III-4 range | 1000 | 144 fail | 304 near | 449 near |
| III-5 extinction | yes | 0/10 fail | 0/10 fail | 0/10 fail |
| VI-2 crash by t≈20 / extinction | 130 / yes | 289 / 0/10 | 295 / 0/10 | 291 / 0/10 |
| VI-3 minimum | 65 | 119 fail | 201 fail | 155 fail |
| VI-3 first peak | 1190 | 420 fail | 848 near | 678 fail |
| VI-3 floor / ceiling after t=250 | 700 / 1200 | 301 fail / 721 near | **705 pass** / 929 near | 547 near / 882 near |
| VI-3 period | 115 | 341 (2/5) fail | 194 fail | none found, fail |

**What this shows.**
- **`fertility_threshold` = 0.83 carries over partly.** Fitted only to III-1's level, it improves almost every out-of-sample reproduction row:
  - III-3's floor rises from 24 to 174 and its agent count from 2,593 to 8,739 (book 12,500);
  - III-4's swings double;
  - VI-3 recovers to the book's 700 floor, with a ceiling of 929 and a first peak of 848, where the faithful run levels off near 700.
- **What it still misses:**
  - the oscillation periods (III-3 315 against 200, VI-3 194 against 115);
  - III-5's extinction;
  - VI-2's crash timing, which happens before anyone can reproduce and so can't depend on this setting.
- **`child_share` doesn't carry over:** it is unstable and worse than the faithful rule on most rows.
- **Under spread founder ages** (the default since the Founder ages section above), `CAL-thr` keeps III-1 in band (478) but loses the out-of-sample gains: III-3's floor is 33 and its agents 3,690, III-4's range is 106, and VI-3 dies out in 2 of 5 seeds. The table above was produced with age-0 founders.
- **Reading:** a fertility test somewhat below the full birth endowment is consistent with the book's population levels across Chapters III and VI, but it isn't the whole missing piece. The timing results (periods, extinction, VI-2's early crash) point to something else as well, probably in the founders' setup. The variant stays a labelled departure from p.55; the book-faithful runs remain the reported results.

## Visual comparison

- **III-1** (colored by vision): high-vision agents take over, as in Animation III-2; but the population stays on the peaks instead of filling a diagonal band.
- **III-8**: each mountain trends to one color, with reversals (see 3).
- **III-9**: Blue gradually eradicates Red, one of the book's three patterns (Animation III-9).
- **III-11**: each tribe holds its own peak; same-tribe replacements appear scattered across the lowlands.
- **III-12**: no colliding waves; each block settles on its own peak.
- **III-15**: the soup sorts onto the two peaks and colors consolidate; the population stays ≈340 and doesn't spill into the lowlands.
