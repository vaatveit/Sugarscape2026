# Replication report

11 pass, 2 near, 12 fail, of 25 targets.

| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |
|---|---|---|---|---|---|---|---|
| III-1 | steady population | Fig III-1, p.58 | 500 | 400–600 | 478.3 [442.4–523.5] | 5/5 | pass |
| III-1 | small fluctuations | p.57 | 0.1 | 0–0.1 | 0.065 [0.05515–0.07192] | 5/5 | pass |
| III-1 | mean vision at t≈900 | Fig III-2, p.63 | 5.3 | 4.8–5.8 | 5.636 [5.526–5.774] | 5/5 | pass |
| III-1 | mean metabolism, t=300–900 | Fig III-2, p.63 | 1 | 0.9–1.15 | 1.001 [1–1.004] | 5/5 | pass |
| III-3 | oscillation period | p.64 | 200 | 150–250 | 411.5 [181–617] | 3/5 | fail |
| III-3 | population floor | p.64 | 250 | 200–350 | 32.8 [0–85] | 5/5 | fail |
| III-3 | agents that ever lived | p.64 fn 10 | 1.25e+04 | 1e+04–1.5e+04 | 3690 [518–6347] | 5/5 | fail |
| III-4 | oscillation period | p.65 | 125 | 100–150 | 131.7 [117.5–160.5] | 5/5 | pass |
| III-4 | oscillation range | Fig III-4, p.65 | 1000 | 600–1400 | 106.2 [82–121] | 5/5 | fail |
| III-5 | extinction frequency (proxy) | Fig III-5, p.66 | — | 0.5–1 | 0 [0–0] | 10/10 | fail |
| III-7 | Gini with inheritance | p.67 | 0.743 | 0.65–0.85 | 0.31 [0.2969–0.3345] | 5/5 | fail |
| III-7 | mean vision at t≈900 | Fig III-7, p.68 | 4.3 | 3.9–4.7 | 5.194 [4.577–5.544] | 5/5 | fail |
| III-8 | each side culturally pure (proxy) | p.74 | — | 0.8–1 | 0.4 [0–1] | 5/5 | fail |
| III-8 | time until every side is pure | p.74 | 2700 | 1350–5400 | — [—–—] | 0/5 | fail |
| III-8 | best-friend closeness | Anim III-8, p.80 | 0.91 | 0.8–1 | 0.9819 [0.9791–0.9857] | 5/5 | pass |
| III-9 | one of the three patterns (proxy) | p.83 | — | 0.8–1 | 1 [1–1] | 10/10 | pass |
| III-11 | both tribes persist (proxy) | Anim III-11, p.86 | — | 0.8–1 | 1 [1–1] | 5/5 | pass |
| III-12 | Blue wave advances NE (proxy) | Anim III-12, p.88 | — | 10–60 | 8.122 [7.918–8.245] | 5/5 | near |
| III-12 | Red wave advances SW (proxy) | Anim III-12, p.88 | — | -60–-10 | -4.652 [-5.752–-3.575] | 5/5 | fail |
| III-13 | combat suppresses Blue's wave (proxy) | Anim III-13, p.89 | — | -5–5 | 9.62 [9.024–10.73] | 5/5 | fail |
| III-14 | no runaway hegemony (proxy) | p.90 | — | 0.5–1 | 0.5 [0–1] | 10/10 | pass |
| III-15 | Red and Blue on opposite mountains | p.92 fn 32 | 0.45 | 0.3–0.5 | 0 [0–0] | 20/20 | fail |
| III-15 | Red dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0.2 [0–1] | 20/20 | pass |
| III-15 | Blue dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0.5 [0–1] | 20/20 | near |
| III-15 | extinction (small frequency) | p.92 fn 32 | — | 0–0.15 | 0.1 [0–1] | 20/20 | pass |

Run: `python -m replication.report --chapter III --jobs 8` on 2026-10-21 (branch feat/chapter-3, after the final-review fix pass). Seeds as registered (5, 10, or 20).
Fast suite 144 passed; `pytest -m slow tests/test_replication_ch3.py`: 11 passed, 13 failed (the near + fail rows).
Re-run 2026-10-22 (branch feat/repro-calibration) after the calibration settings changed every fingerprint: every row identical, plus the new III-3 row for footnote 10.
Re-run 2026-10-22 (branch feat/founder-ages) after founders with finite lives began at ages U[0, max age) (user decision; see the Chapter III record): the table above. Changed rows are listed under Founder ages.
Chapter II regression run on the same branch: 19 pass / 12 near / 0 fail, every row identical to docs/replication/chapter-2.md.
Re-run 2026-10-22 (branch feat/threshold-default) after the default fertility threshold became 0.83 (user decision; see "Default fertility threshold" below): the table above.
Re-run 2026-10-23 (main) after two reporting decisions (user, 2026-10-23). Near now means within the smaller of half the band's width and a quarter of the nearer bound's magnitude, so III-12's Red wave and III-13 fall from near to fail. The period targets now use `peak_spacing`: the median interval between peaks of a 41-period moving average, counting swings of at least 40 (the method of "III-3's floor and period", below), instead of the first autocorrelation peak. III-3's period is 412 (was 438, still a fail) and III-4's 132 (was 116, still a pass). Every other observed value is identical.

## Choices made from evidence or by necessity

- **Fertility threshold 0.83 of the birth endowment (user decision, 2026-10-22).** p.55 requires the whole endowment (1.0). The default 0.83 is a fitted departure, fitted to Fig III-1's steady population alone (Calibrated reproduction variant, below). The book's rule runs unchanged as `VAR-book/<id>`.
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
   Ruled out: random initial ages (worse); Moore mating neighbors (+2–6%); fertility end inclusive (no change); evolution speed (ours is as fast or faster); food supply (Chapter II metabolism-1 capacities match within 2%). Sensitivity: removing the parents' cost fills the lattice (≈2000); a threshold of half the endowment gives ≈950 (III-1). Neither is the book's rule. **III-3 sits on a knife-edge**: small changes (Moore + inclusive end) move its floor from 46 to 179, so its miss carries little diagnostic weight. (Explained 2026-10-22: the knife-edge is whether both mountains survive the founding crash; see "III-3's floor and period" below.)
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

## Movement and harvest at high density (2026-10-22)

Can a movement or harvest detail raise income at high density enough to lift the level? Diagnostics only; nothing here changes the model.

**Where regrowth goes unharvested** (evolved agents: metabolism 1, vision 5–6, immortal, rich; t=100–300):

| N | Harvest per agent | Agents on capacity 3–4 sites, harvest each | Capacity-2 sites full at period end | Agents on capacity-2 sites, harvest each |
|---|---|---|---|---|
| 350 | 2.45 | 296, 2.64 | 96% | 28, 2.00 |
| 500 | 2.12 | 334, 2.34 | 84% | 122, 2.00 |
| 700 | 1.98 | 361, 2.17 | 64% | 279, 2.00 |

- **The peaks are grazed bare and the lowlands go unharvested.** The 782 peak sites regrow at most 782 units per period, and the agents on them harvest nearly all of it.
- **Greedy movement caps the average.** Agents go to the richest site they see, so they crowd the peaks until a peak site is worth about what a full capacity-2 site offers (2). Average harvest can't rise much above 2 + (782 − 2k)/N, where k is the number of agents on the peaks: ≈2.2–2.3 at N=500, against our 2.12.

**The text pins rule M except for the agent's own site** (p.25; App. B: "considering only unoccupied positions, find the nearest position producing maximum welfare"). Variants, 3 seeds:

| Movement | Harvest per agent at N=350 / 500 / 700 | Fig II-5 m2 v2, v5.5 at t≈50 / t=500 (book 365, 390) | m3 v3 at t≈50 / t=500 (255) | II-4 at t=500 (224) | III-1 level (≈500) |
|---|---|---|---|---|---|
| Nearest richest, own site at distance 0 (current) | 2.45 / 2.13 / 1.99 | 369, 399 / 304, 314 | 257 / 236 | 228 | 352 |
| Own site excluded ("must move") | 2.48 / 2.20 / 2.06 | 409, 413 / 320, 331 | 273 / 248 | 240 | 357 |
| A random one of the richest, ignoring "nearest" | 2.62 / 2.32 / 2.07 | 417, 434 / 323, 333 | 279 / 248 | 245 | 452 |

**Findings:**
- **No movement detail the text allows raises high-density income enough.** "Must move" adds ≈3% income and nothing to the level, and Chapter II already rejected it (II-1's static end state).
- **Ignoring "nearest" is the only variant that helps.** It adds 9% income at N=500 and lifts III-1 to 452, which shows how sensitive the level is to income. But it contradicts p.25's "select the nearest one". It also breaks Fig II-5's matches at t≈50 (+12–14%) and puts II-4 at the band's edge.
- **Chapter II's metabolism-2 gap doesn't share this cause.** Every variant leaves the t=500 metabolism-2 points 15–20% low, so the shared-cause idea in "What sets the long-run level" above finds no support from movement.
- **What remains is contact.** In our model women need ≈1.45 net income per year largely because each child waits ≈8 periods for an adjacent fertile partner. Free contact alone gives 509. Our mean neighbor count in Chapter II is 0.80 (band pass, but below the book's 0.9 in all 10 seeds), so local spacing is the next place to look.

## How agents end up next to each other (2026-10-22)

Diagnostics only; nothing here changes the model.

**Chapter II spacing.** Our statistic is the book's: the mean length of each agent's post-move von Neumann neighbor list (pp.39–41, fn 29). Animation II-5 prints "Average neighbors: 0.9" (standard deviation 0.8–0.9) in all six frames. Ours in II-4's run (5 seeds):

| Movement | t=1–5 | 5–20 | 20–60 | 60–150 | 150–500 | II-1 still moving at t=80–100 |
|---|---|---|---|---|---|---|
| Own site at distance 0, wins ties (current) | 0.77 | 0.85 | 0.83 | 0.80 | 0.79 | 0.00 |
| Own site excluded ("must move") | 0.80 | 0.89 | 0.91 | 0.89 | 0.88 | 0.98 |
| Random one of the richest, ignoring "nearest" | 0.88 | 1.00 | 0.97 | 0.96 | 0.97 | — |

- **"Must move" reproduces the book's spacing at every stage, but p.28 rules it out.** On a ridge "no point on the level 3 sugar terrace is an improvement … So you stick on the ridge": the own site counts and wins ties. Under must-move, 98% of II-1's agents are still moving at t=80–100.
- **The 0.80 vs 0.9 gap stays open** (the target passes its band). It doesn't matter for III-1: must-move leaves III-1's neighbors at 1.24 (against 1.23), the share of fertile agents with a fertile partner adjacent unchanged (1.4% against 1.5%), and the level at 357 (against 352).

**Who stands next to a fertile agent at its mating turn** (III-1, t=300–1000, 5 seeds, 265,840 turns, 1.21 neighbors per turn):

| Neighbor | Share | Of which the agent's parent or child |
|---|---|---|
| Same sex | 52% | 3% |
| Opposite sex, too young | 8% | 5% |
| Opposite sex, past fertility | 20% | 3% |
| Opposite sex, fertile age, short of wealth | 14% | 3% |
| Opposite sex, fertile (a partner) | 5.2% | 2% |

- **Kin don't crowd out partners:** only 2–5% of neighbors are parents or children.
- **Partners are met by near-random mixing.** 91% of agents move each period, so a fertile agent gets ≈1.2 fresh neighbors per period. Each is an eligible partner with probability ≈0.10 (half the population's 20% fertile share), giving a wait of ≈1/(1.2 × 0.10) ≈ 8 periods, as measured. The snapshot's 5.2% is below random mixing's 10.1% only because adjacent fertile pairs mate at once.
- **So spacing can't shorten the wait** without many more neighbors per agent. The level responds weakly even then: Moore neighbors +2–6%, radius 2 (24 sites) 417, unrestricted contact 509.

**Where this leaves the long-run level.** Within the written rules, none of income (movement, harvest, map), contact (spacing, kin, neighborhood), placement, timing, lifespan or cost raises it to the book's ≈500. Only departures do: unrestricted contact, a fertility threshold near 0.83 of the endowment (the `CAL-thr` variant), or ignoring "nearest" in M (452).

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

## Default fertility threshold (2026-10-22)

**Decision (user, 2026-10-22):** the fitted threshold becomes the default, `Config.fertility_threshold` = 0.83 (formerly the `CAL-thr` variant). It applies wherever rule S or credit runs: Chapters III, IV and VI.
- **The book's rule is kept as a variant.** `VAR-book/<id>` runs p.55 as written (threshold 1.0) on III-1, III-3, III-4, III-5, VI-2 and VI-3, and `VAR-share/<id>` runs the fitted child share at p.55's threshold, both with the same targets (`python -m replication.report --chapter VAR`). The `CAL-` experiments are gone.
- **`VAR-book` reproduces the previous book-faithful rows exactly** (III-1 359.8, III-3 floor 18.4, VI-3 first peak 271.8), so the variant is the old default with the same random streams.
- **Unit tests of p.55's arithmetic** (credit amounts, the infertile cases) now set threshold 1.0 explicitly. The III-1 stream pin was re-recorded.

**What changed** (5 seeds unless stated; previous = book's threshold, spread founder ages):

| Row | Previous | Now |
|---|---|---|
| III-1 steady population (book ≈500) | 360 near | **478 pass** |
| III-3 floor / agents that ever lived / period | 18 / 1,613 / 493 | 33 / 3,690 / 438, still fail |
| III-4 range (book ≈1000) | 120 | 106, fail |
| III-5 extinction | 0/10 | 0/10, fail |
| III-15 extinction (book: rare) | 6/20 fail | **2/20 pass** |
| III-15 Blue dominates both (book ≈25%) | 10% pass | 50% near |
| IV-14 / IV-17 / IV-18 extinct | 5/5 / 5/5 / 5/5 | **0/5** / 4/5 / 5/5 |
| IV-14 dispersion with S (book 0.37) | no survivors, fail | **0.39 pass** |
| VI-1 extinct | 4/5 | 5/5 |
| VI-2 crash at t≈20 (book 130) / extinct | 212 / 2/10 | 213 / 1/10 |
| VI-3 extinct / floor / ceiling (book ≈700 / ≈1200) | 2/5 / 153 / 358 | 2/5 / 204 / 534 |

**Totals:** III 10/4/11 → 11/4/10 (pass/near/fail); IV 18/8/15 → 19/8/14; VI 17/5/16 → 17/5/16; II and V unchanged.
**Reading:** the level rows the threshold was fitted to now pass, and two extinction problems ease (III-15, IV-14). The dynamics rows (III-3's floor and period, III-4's swings, III-5's extinction, VI-3's waves) remain far from the book, as the earlier diagnostics predicted.

## III-3's floor and period (2026-10-22)

Diagnostics of III-3 (fertility ends 10 years earlier) under the defaults (θ=0.83, spread founder ages); nothing here changes the model. 10 seeds per case unless stated.

**The book's run** (Fig III-3, read from the plot): it starts near 405, rises to ≈450 by t≈50, and dips to ≈250 at t≈190. It then cycles regularly, with peaks of ≈415–465 at t≈340, 548, 754, 960, 1175, 1405, 1627, 1833, 2151 and 2397 (≈225 apart). Troughs are ≈240–330 and the mean ≈365.

**Our low floor is a lost mountain.** The founding crash takes each mountain down to 10–50 agents by t≈150. Below ≈30–40 agents a mountain dies out (see below), and nobody re-founds it. A society on one mountain holds about half as many agents as one on both:

| Founder ages, θ | Both mountains | One mountain | Extinct | Level t≥500 (both / one) | Floor t≥300 (both / one) |
|---|---|---|---|---|---|
| Spread, 0.83 (default) | 0 | 7 | 3 | — / 156 | — / 72 |
| Age 0, 0.83 | 9 | 1 | 0 | 300 / 164 | 185 / 89 |
| Spread, 1.0 (`VAR-book`) | 0 | 2 | 8 | — / 100 | — / 46 |
| Age 0, 1.0 | 1 | 4 | 5 | 214 / 88 | 127 / 38 |

- **Genetics don't account for the split.** Late mean vision (4.5–6.0), maximum age (61–93) and birth endowment (70–81) overlap between one- and two-mountain runs.
- **The number of mountains held does.** The one age-0 run that lost a mountain settles where spread-founder runs do (164 against 156).
- **The book's run must have kept both:** its floor (≈250) is above anything one of our mountains holds.

**Why a thinned mountain dies out** (per mountain quadrant, t=50–1000, 16 runs of both founder settings):

| Agents on the mountain | Births per agent per period | Fertile agents with a fertile partner adjacent | Fertile-age agents holding enough sugar |
|---|---|---|---|
| under 10 | 0 | 0% | 98% |
| 10–20 | 0.008 | 1.2% | 91% |
| 20–40 | 0.011 | 2.3% | 83% |
| 40–160 | 0.013 | 2.1–2.5% | 59–74% |
| 160–240 | 0.012 | 1.9% | 52% |

- **Below ≈30–40 agents, births fall short of deaths** (≈1/80 per agent per period). Nearly every fertile-age agent holds enough sugar, but partners stop meeting: an Allee effect from contact limited to von Neumann neighbors.
- **An emptied mountain is never re-founded.** In these runs 10 of 32 mountains emptied and none returned to 10 agents. Children are born next to a parent, and an agent moving greedily within vision 6 can't see the other mountain across the valley.

**Why the founding crash is so deep.**
- **Spread founders:** in the first 50 periods they average 2.2 births per period against 4.6 old-age deaths and 1.2 starvations.
- **The book's rise to ≈450 by t≈50** needs ≈6–7 births per period against those deaths. This is Fig III-1's early-birth deficit (Birth-rate decomposition, above: ≈6.5 needed, ≈2.5 achieved), here with fertile windows 10 years shorter.
- **Age-0 founders reproduce the book's shape** (400 → ≈520 by t≈50 → ≈140 at t≈150), because they all come of age together, but overshoot both ways.

**Given both mountains, the cycle runs near the book's period at about half its amplitude.** Age-0 founders, the 9 runs that kept both mountains; peaks and troughs from a 41-period moving average, swings of at least 40:

| | Book | Ours |
|---|---|---|
| Mean level | ≈365 | ≈300 |
| Peaks | ≈450 | ≈350 (300–376) |
| Troughs | ≈280 (240–330) | ≈255 (213–286) |
| Peak-to-peak | ≈225, regular | median 206–286 in 5 of 9 runs; 330–670 in the rest, where small swings blur into noise |

- **The registered period statistic is unreliable on series this irregular.** The first autocorrelation peak gives 201–699 for one-mountain runs and 207–1701 for two-mountain ones.
- **The low peaks are the long-run level's shortfall** (What sets the long-run level, above), with the shorter window.

**Reading:**
- **Floor:** III-3's floor misses because the founding crash, an instance of the open early-birth problem, empties a mountain that our rules can't re-found. A founding phase that keeps both mountains would likely bring it near the book; age-0 founders give 185 against a band of 200–350.
- **Period:** it misses mainly because a one-mountain society barely oscillates. A two-mountain society already cycles near the book's period, though with half the swing.
- Nothing here points to a cause separate from the early birth rate and the long-run level.

## III-4's swings (2026-10-22)

Diagnostics of III-4 (endowments 10–40) under the defaults; nothing here changes the model. 5 seeds for counts, 3 for variants.

**The book's run** (Fig III-4, digitized from the page image at ≈5 periods per pixel):
- **First cycle:** ≈415 at t=0, a peak of ≈1,550 at t≈75, a trough of ≈380 at t≈145.
- **Later cycles:** peaks stay at ≈1,540–1,560 throughout. Troughs rise 380, 410, 435, 470, 500, 520, 570 … ≈590 by t≈1,450.
- **Period:** 143 at first, shortening to 124 (mean ≈130). Rises and falls each take ≈65–70 periods.

**Ours:**
- The population dips to ≈310 at t≈25 as high-metabolism founders starve, then booms to ≈1,410 at t≈120.
- It falls only to ≈915, and by t≈400 it holds at ≈1,170 with swings of ≈±50.
- Mean metabolism is 1.00 from t≈120, and nobody starves after t≈100: every death is from old age.

**The book's swings need no starvation.** Inverting the book's curve, assuming every death is from old age:
- Maximum ages are uniform on 60–100, and the 415 founders start at spread ages.
- Births are the population's change plus old-age deaths. Any shortfall below zero must be starvation, which gives a lower bound.

| Book phase | Implied births per period | Old-age deaths per period | Minimum starvation |
|---|---|---|---|
| Falls (t=75–148, 217–285, 354–421) | 6.3–8.1 | 21–25 | 4–73 per fall |
| Rises (t=148–217, 285–354) | 23.5–25.3 | 6.6–8.8 | 0 |
| t=1,000–2,500 (average) | 17.8 | 17.9 | ≈0 |

- **The method checks out on our own run:** it finds 2 starvations over t=1,000–1,500, against a direct count of 0.
- **The book's cycle is a demographic echo.** Each boom's births die of old age about one lifetime later, during the next fall, and each fall's few births leave the following rise with few deaths. Over the run that implies ≈45,000 agents ever lived (ours ≈38,000).
- **Births must depend on the cycle's phase, not on current density.** At the same population of ≈1,000 the book has ≈24 births per period on the way up and ≈7 on the way down. Per agent that is ≈0.024 against ≈0.007 (×3.6). Ours swings 0.016 against 0.010 (×1.7) in the first cycle and then damps.

**Ours has no memory to sustain the echo:**
- **Every cohort comes of age fertile.** Of agents born at any phase after t≈20, 97–100% reach fertile age holding their threshold (85–87% for those born at t=0–20), at 1.15–2.0 times it. Childhood net income never turns negative: +0.18 per year for those born at the peak, +0.5–1.0 for those born in troughs. The same holds at threshold 1.0.
- **Crowding can't drain wealth on our map, even at the book's peak.** Net income per agent for evolved agents (metabolism 1, immortal) is +0.64 at N=1,000, +0.40 at 1,200, +0.21 at 1,400, +0.08 at 1,600, −0.03 at 1,800 and −0.08 at 2,000. It reaches zero near N≈1,700, and at most 8% of agents lose sugar in a period.
- **So our births respond to current density alone.** They fall at the peak (wealth after a birth, partners, space) and recover as soon as the population thins. That damps the cycle.

**What limits births at our peak** (per period, t≈100–140):
- 268–295 wealth-fertile agents take a mating turn, with ≈3.3 of 4 neighbor sites occupied.
- 8–10% of those turns find a fertile partner adjacent, giving 10–16 births.
- Another 13–14 pairs fail because neither parent has an empty site next to it.

**Variants** (diagnostic only; book: peak ≈1,550 at t≈75, trough ≈380, late range ≈900–1,000):

| Variant | First peak | Next trough | Range t=1,000–1,500 | Births per period after t=300 |
|---|---|---|---|---|
| Default (spread founders, θ=0.83) | 1,397–1,428 at t≈120 | 893–928 | 79–95 | 12–20 |
| θ=1.0 (`VAR-book`) | 1,302–1,387 | 810–904 | 99–225 | 9–22 |
| θ=0.5 | 1,574–1,589 at t≈110 | 1,027–1,104 | 171–322 | 12–21 |
| Age-0 founders | 1,353–1,404 | 928–1,004 | 92–148 | 11–21 |
| Every maximum age 80 | 1,375–1,438 | 876–916 | 126–444 | 9–24 |
| Global contact (up to 4 random fertile partners) | 1,546–1,578 at t≈90 | 795–857 | 172–233 | 8–27 |
| Child at the nearest empty site when none is adjacent | 1,388–1,441 | 849–952 | 106–206 | 10–22 |
| … with θ=1.0 / with global contact | 1,317–1,561 | 713–915 | 99–248 | 4–31 |

- **No variant sustains the swings.** The late ranges stay at 79–444 against ≈900–1,000, and every next trough stays at 713–1,104 against ≈380.
- **The first peak can be reached.** Global contact matches its height and nearly its timing (≈1,560 at t≈90). θ=0.5 matches its height. The early boom is the same early-birth problem as Figs III-1 and III-3.
- **Freeing space doesn't help:** with blocked pairs unblocked, the wealth test brakes births at the peak instead.

**Reading:**
- The book's swings are an old-age echo that needs births to stay low for a whole fall, ≈70 periods, after the population has started thinning: a memory of about a quarter-cycle.
- Our rules give births no such memory. Children born at the peak still come of age fertile, and on our map net income stays positive up to N≈1,700. The cycle damps within three swings.
- What carries the memory in the original is unknown. It would have to make births depend on conditions about 30 periods earlier, which none of the readings tested here does. (Answered in the next section: our rules carry the same memory; the difference lies in reaching the cycle.)

## Where III-4's birth memory comes from (2026-10-22)

Diagnostics only; nothing here changes the model. The question: what makes the book's births depend on the cycle's phase rather than on current density?

**The memory is the delay to fertility, and ours has it too.**
- Fit births as a function of the population τ periods earlier. The book's implied births (t=300–2,400) fit best at τ=20–25 (R² 0.93, against 0.15 at τ=0). Ours over the damped cycles (t=100–400) fit best at τ=15–20 (R² 0.82).
- That lag is the delay from birth to first fertility (12–15 years) plus the time to earn the threshold.

**Our response curve is the book's.** Run III-4 to t=600, cull the settled, evolved society at random to 400, and measure births during the rebound (5 seeds):

| Population 20 periods earlier | 300–500 | 500–700 | 700–900 | 900–1,100 | 1,100–1,300 | 1,300–1,500 | 1,500–1,700 |
|---|---|---|---|---|---|---|---|
| Book's implied births per period | 32.2 | 32.2 | 27.0 | 18.8 | 12.7 | 7.5 | 6.6 |
| Ours, von Neumann contact | 23.4 | 30.3 | 25.4 | 17.4 | 12.3 | 7.4 | 6.4 |
| Ours, global contact | 33.1 | 33.7 | 27.9 | 20.2 | 14.8 | 9.2 | 5.9 |

- **The rebound reproduces the book's first cycle:** a peak of 1,485–1,517 at +72–77 (book ≈1,550 at t≈75), then a trough of 680–780 (book ≈380).
- **Only the lowest bin falls short** under the book's contact rule (23 against 32). That is the low-density partner shortage behind III-3's lost mountains (III-3's floor and period, above).

**Our rules hold the book's cycle, but rarely reach it.** Runs "lock in" when they keep a range above 600 in the last 300 of 1,500 periods after the cull:

| Start | Locked into the large cycle | Otherwise |
|---|---|---|
| Ordinary III-4 runs (20 seeds, 2,500 periods) | 0 of 20 | range ≈65–160 after t≈1,000 |
| Culled to 300 / 400 / 600 / 800, von Neumann contact | 1 of 45 (range rising 635 → 982) | first trough 749–993, then decay |
| Culled to 400, global contact | 4 of 10 | decay to ≈100–150 |
| Ordinary start, global contact (3 seeds, 1,500 periods) | 0 of 3 | range 172–233 |

- **A locked cycle has the book's shape.** With global contact: peaks 1,540–1,625, troughs 659–756, peak spacing 118–131. The book's late cycle: peaks 1,540–1,560, troughs 530–590, period 124–143. The locked runs carry longer maximum ages (80–94, against 77 in the runs that settled).
- **The model is bistable:** a quiet equilibrium near 1,170 and a large cycle, with the founding boom deciding which one a run lands on.

**Why our founding boom misses the cycle.**
- **The book's boom is fast and compact.** Its population climbs from the start (≈415 → ≈1,550 by t≈75, ≈20 births per period on average).
- **Ours is slow and smeared.** Its unselected founders (mean metabolism 2.5, endowments 10–40) first lose ≈100 agents to starvation. Births run 5.9, 7.9, 14.2, 22.2 per period in successive 20-period windows, so the peak comes late (≈1,410 at t≈120).
- **A smeared boom gives a smeared death echo.** The first trough is only ≈915, and the cycle decays.
- **An evolved society culled to 400 booms like the book's founders** (peak at +75). Even so, it locks in only when low-density births are book-like (global contact).

**Reading:**
- **Nothing is missing from rule S.** The book's birth memory is the ordinary delay to fertility, which our rules contain, and the response to density matches the book's except at the lowest densities.
- **Two shortfalls keep our runs off the book's cycle:** births at low density about a quarter short (von Neumann contact), which makes the cycle hard to reach and hold; and a founding boom too slow to start it.
- **Both are the early, low-density birth problem** already recorded for Fig III-1's boom and III-3's founding crash.

## III-5's extinction (2026-10-22)

Diagnostics of III-5 (endowments 10–40, fertility ending 10 years earlier) under the defaults; nothing here changes the model. 10 seeds unless stated.

**The book's run** (Fig III-5, digitized; 4.6 periods and 5.3 agents per pixel):
- **Surges:** ≈405 at t=0, then peaks of ≈1,280 at t≈65, ≈1,440 at t≈298 and ≈1,375 at t≈508.
- **Troughs:** broad and nearly empty, ≈47 at t≈186 and ≈57 at t≈400, each lasting some 40–60 periods.
- **Extinction:** at t≈610. In our previous notes this was ≈550.
- **Extinction follows from troughs that deep.** At ≈50 agents our own rules can't restart a mountain: below 30–40 agents births fall short of deaths (III-3's floor and period, above).

**Ours never gets near that.** Peaks are 1,180–1,470 and troughs 220–970, and no run dies out in 1,500 periods. The one growing cycle (seed 9) deepens its troughs 850 → 596 → 426 → 222 by t≈1,100.

**What the book's troughs require.**
- **A trough of ≈50 caps the births of the 60 periods before it at about 50**, ≤1 per period, unless children starve. Children that young can't die of old age, so this needs no lifespan assumption.
- **Inverting the curve** with old-age deaths only gives 1.5–2.1 births per period through each fall (t≈70–190 and 297–409), with at least 52–91 starvations per fall.
- **Women's shorter windows make this possible.** With fertility ending at 30–40, a boom's women age out within ≈40 periods of the peak. If births are blocked for those 40 periods, almost no one is left to breed when the population thins.
- **The same block is consistent with III-4.** There women stay fertile 10 years longer, births resume during the fall (≈6–8 per period), and the troughs stop near 380.

**Ours keeps breeding through the falls** (per fall, t up to 1,500):

| | First half of a fall | Second half |
|---|---|---|
| Births per period | 3–13 (most runs 8–11) | 2–18 |
| Fertile-age women | 86–182 | — |
| … holding their threshold | 29–52% | — |
| … net income per year | +0.19 to +0.37 | — |
| Births in the 60 periods before the trough | — | 133–1,003 (book ≲50) |

- **Fit by the population 20 periods earlier**, the book's III-5 births fall to 3.9 and 1.5 per period in the 1,100–1,300 and 1,300–1,500 bins. Ours stay at 7–9.

**What doesn't produce it:**
- **A compact boom.** Cull the settled society (t=600) to 400. It rebounds to 1,320–1,660 by +57–107, but the first troughs are 369–698 and none of 10 runs dies out. Global contact gives the same: troughs 503–698, 0 of 10 extinct. Unlike III-4, reaching a big swing isn't enough.
- **A brake on current density.** Block every birth while the population exceeds 1,000 or 1,200: it clamps there (late range 20–490), and none dies out.
- **So any brake that reads only current density can't make the troughs**, including lack of room for the baby (13–14 blocked pairs per period at III-4's peaks). The block has to outlast the crowding.

**Reading:**
- **The book's extinction needs births shut off for decades after each peak.** Wealth is the natural carrier: agents leaving the peak far below their threshold, needing more than ≈40 periods to re-earn it.
- **Our agents leave the peak with income in hand.** At the book's peak densities our net income stays positive (break-even near N≈1,700; III-4's swings, above), so a third to a half of fertile-age women keep qualifying.
- **One reading fits the first fall but is unproven.** The book's first boom (≈405 → 1,280 by t≈65) happens before selection, while founders' metabolisms are still high, and unselected agents run a deficit at high density (III-1: −0.44 per period at N=500). Our boom comes after selection (metabolism 1.0 by t≈100–120, peak at t≈140), so it never drains wealth.
- **Later falls are unexplained.** They would need slower selection or a lower break-even in the original than ours. What blocks the original's births at peak density remains open (see the next section).

## What might stop births at peak density (2026-10-22)

Diagnostics only; nothing here changes the model. The target: a state, set by crowding, that keeps births near zero for ≈40 periods after a peak, long enough for a boom's women to age out of fertility (III-5's extinction, above). Each candidate ran on III-5 (10 seeds, 1,500 periods), some also on III-1, III-3 and III-4 (5 seeds). The book's III-5 dies out by t≈610, with troughs of ≈50.

**What the text leaves open.**
- **p.56** has "each fertile agent" execute S, whose loop tests only the neighbor ("If the neighbor is fertile …; Repeat for all neighbors"). Read literally, an agent's own fertility is tested once per turn.
- **Appendix B** states the step as "both agents are fertile", our reading. The parenthetical on p.56 ("agents, if fertile, rarely possess enough wealth to have multiple children in a single period") also suggests wealth is re-checked.
- **p.56** lists the child's "genetic makeup (metabolism, vision, maximum age, and so forth)". Our children draw fresh fertility ages, which is our call.

**Candidates** (III-5; default: 0 of 10 extinct, troughs 222 minimum, 767 median):

| Candidate | Extinct | Troughs (min / median) | Notes |
|---|---|---|---|
| Own fertility tested once per turn (literal p.56) | 0/10 | 375 / 732 | Birth turns with 2+ births rise from 1.8% to 5.4% |
| Founders' metabolism 1–2 (variation into the cycles) | 0/10 | 512 / 757 | Metabolism-2 agents are still gone by t=200 |
| Threshold 1.0 (p.55) | 0/10 | 414 / 723 | |
| Once per turn + threshold 1.0 | 0/10 | 467 / 722 | |
| Metabolism 1–2 + threshold 1.0 | 0/10 | 273 / 717 | |
| Once per turn + metabolism 1–2 | 0/10 | 304 / 777 | |
| Fertility ages inherited (onset from a random parent, end from the same-sex parent) | 0/10 | 729 / 839 | Women's fertility end drifts to 39.4 ± 0.5; III-1 rises to 583, swings shrink |
| Every capacity-1 site set to 0 (map ceiling lowered) | 0/10 | 384 / 796 | III-1 485, III-4 mean 1,167 (default 1,173) |

**Findings:**
- **None of these stops births at the peak.** Every run survives, and the troughs stay 4–17 times the book's ≈50.
- **Our peaks aren't food-limited.** Removing 522 of the 2,069 productive sites leaves the III-4 and III-1 levels within 1%. Agents on capacity-1 sites just break even. The population is regulated by births on the richer sites, so a lower food ceiling doesn't drain wealth.
- **Inherited fertility ages push the other way.** Selection lengthens fertile windows, raising levels and damping swings.
- **A brake on current density can't work either**: no births above a cap, or lack of room for the baby (III-5's extinction, above). The block must persist after crowding ends.

**Where this leaves it:**
- **The book's falls need a lasting fertility deficit** in the cohort that comes of age during and after a peak. Ours comes of age at 1.15–1.35 times its threshold even when born at the peak (III-4's swings, above).
- **No reading of p.55–57 or Appendix B tested here creates one.** The early-birth and low-density shortfalls (Figs III-1, III-3, III-4) point the same way: the original's births respond more steeply to density than ours, high when sparse and near zero when crowded.
- **What produces that remains unknown.** The candidates above, and the earlier ones (contact, placement, timing, cost, threshold, founders, income), are ruled out as single causes.

## The book's single runs as frequencies (2026-10-23)

The book shows one run of each population figure, so a band around that run's value can't separate "our model never
does this" from "our model does it in some runs". [diagnostics/frequencies.py](../../diagnostics/frequencies.py) counts
how often a run shows the book's behavior over 30 seeds (the registry's seeds 0–29), under the default threshold and
p.55's. Founders at spread ages; nothing here changes the model.

| Figure | Book's behavior | Default (θ=0.83) | p.55 (θ=1.0) |
|---|---|---|---|
| III-3 | both mountains held through the last 500 periods | 3/30 | 0/30 |
| III-3 | floor after t=300 in the book's band (≥200) | 0/30 | 0/30 |
| III-4 | the large cycle (range > 600 over t=1500–2500) | 0/30 | 2/30 |
| III-5 | extinct by t=1500 | 0/30 | 0/30 |
| III-5 | a trough below 100 after t=150 (the book's ≈50) | 0/30 | 0/30 |
| VI-2 | extinct by t=200 | 1/30 | **15/30** |
| VI-2 | crash at t=20 within the band (≤156) | 0/30 | 0/30 |
| VI-3 | survives to t=1000 | 23/30 | 12/30 |
| VI-3 | floor and ceiling after t=250 in the book's bands (≥560, ≥960) | 4/30 | 0/30 |

- **VI-2's extinction is a coin flip under the book's rule** (15 of 30 seeds; the registered 10 seeds give 1 under
  the default). The fitted threshold, not the rule, is what keeps our non-trading society alive. Its crash is still
  slower than the book's in every seed.
- **III-4's large cycle does occur under p.55's rule**, in 2 of 30 ordinary runs, which supports the bistability
  found above: the book's run may be one draw from a basin our runs reach rarely.
- **The book's VI-3 waves appear in 4 of 30 default runs,** never under p.55's rule.
- **III-5's extinction and deep troughs never occur** in 60 runs, and III-3's floor is never in the book's band. These
  are the results least likely to be one unlucky draw of our model.

## Candidate departures from rule S (2026-10-23)

The README's untested candidates, run as labelled departures by [diagnostics/candidates.py](../../diagnostics/candidates.py)
and scored with the replication targets of every population figure. Each uses p.55's test (θ=1.0) and spread founder
ages; 5 seeds each, the cached columns cut to the same 5. Nothing here changes the model.

- **C1, mate search within vision:** partners are agents in sight along the four lattice directions (rule M's lookout),
  not only the four neighbors. The child still goes next to a parent.
- **C2, gift from current wealth:** each parent gives half its current sugar (Kehoe's prose reading), and the child's
  threshold is a fresh draw from the founders' range, so children born poor come of age below threshold.
- **C3, Ascape's package:** each parent gives at most 5 sugar, and the child's threshold is a fresh draw.

| Target | Book | p.55 (`VAR-book`) | Default (θ=0.83) | C1 | C2 | C3 | C1+C2 | C1+C3 |
|---|---|---|---|---|---|---|---|---|
| III-1 steady population | 500 | 360 near | 478 pass | **420 pass** | 375 near | 220 fail | 445 pass | 314 near |
| III-1 small fluctuations | ≤0.10 | 0.059 | 0.065 | 0.087 | 0.059 | 0.21 fail | 0.061 | 0.18 fail |
| III-3 floor | 250 | 18 | 33 | **163 near** | 0 | 0 | 136 | 8 |
| III-3 agents that ever lived | 12,500 | 1,610 | 3,690 | **8,400 near** | 479 | 490 | 8,110 near | 1,380 |
| III-3 period | 200 | 495 (2/5) | 412 (3/5) | 554 | — | — | 352 | 597 (1/5) |
| III-4 period | 125 | 136 pass | 132 pass | 115 pass | 172 near | 124 pass | 130 pass | 112 pass |
| III-4 range | 1,000 | 120 | 106 | 321 | 149 | **969 pass** | 216 | **615 pass** |
| III-5 extinct by t=1500 | yes | 0/5 | 0/5 | 0/5 | 0/5 | **1/5** | 0/5 | 0/5 |
| VI-2 crash at t≈20 | 130 | 209 | 209 | 216 | 213 | 209 | 214 | 221 |
| VI-2 extinct by t=200 | yes | 2/5 | 1/5 | 0/5 | **4/5 pass** | **4/5 pass** | 2/5 | 0/5 |
| VI-3 minimum | 65 | 27 | 36 | **64 pass** | 12 | 10 | **74 pass** | 109 |
| VI-3 first peak | 1,190 | 272 | 308 | 639 | 19 | 5 | 516 | 529 |
| VI-3 floor / ceiling after t=250 | 700 / 1,200 | 153 / 358 | 204 / 534 | **453 / 860 near** | 14 / 202 | 0 / 0 | 370 / 743 | 426 / 557 |
| VI-3 period | 115 | 322 (2/5) | 241 (2/5) | 274 | — | — | 246 (3/5) | 171 (4/5) |

Unmarked cells fail. All variants keep III-1's evolution rows (vision, metabolism) in band.

**Findings:**
- **C1 is the only candidate that improves the population figures broadly without a fitted value.** Wider contact lifts
  the low-density births behind III-1's level, III-3's lost mountain (floor 163, agents ever lived 8,400) and VI-3's
  recovery (minimum 64, floor and ceiling near). It leaves III-4's swings small and III-5 and VI-2 alive: it is a
  remedy for the early, low-density shortfall, not for the missing post-peak block.
- **C3 (cheap children) is the only candidate that gives III-4 the book's swings** (range 969 at period 124) and the
  only one where III-5 dies out (1 of 5). It also kills VI-2 like the book (4 of 5). But it sinks III-1 to 220 with large
  fluctuations and empties III-3 and VI-3. MASON's flat fertility threshold of 25 does the same for III-4 (below).
- **C2 kills too much:** VI-2 dies like the book, but III-3 and VI-3 die too.
- **The two effects combine only partly.** C1+C3 keeps III-4's swings (615) and lifts III-1 to 314, but VI-3 and III-3
  stay far off. No variant reproduces the book's crash speed in VI-2 (≈130 at t=20, ≈210 in all of ours), which happens
  before anyone can reproduce.
- **Reading:** the book's figures look like a model whose births are cheap *and* easy to arrange: easy when sparse (C1)
  and cheap enough to boom and bust (C3). No single reading of the text gives both, and the fitted threshold (0.83) is
  a weaker stand-in for C1's effect on the level.

## MASON's own runs (2026-10-23)

MASON's Sugarscape (Bigbee, Cioffi-Revilla and Luke 2007) built from its project archive and run headless on its own
configs for Figs III-1, III-3, III-4 and III-5, 10 seeds each
([diagnostics/mason/](../../diagnostics/mason/README.md); scored by
[mason_compare.py](../../diagnostics/mason_compare.py)). Its child placement ignores occupancy, and its III-4/III-5 configs
read p.65 as a flat fertility threshold (25 and 10 sugar) with endowments of 50–100.

| Target | Book | MASON | Ours, p.55 (`VAR-book`) | Ours, default |
|---|---|---|---|---|
| III-1 steady population | ≈500 | 348 near | 360 near | 478 pass |
| III-1 fluctuations / vision / metabolism | ≤0.10 / 5.3 / 1.0 | 0.063 / 5.47 / 1.00, pass | 0.059 / 5.68 / 1.00, pass | 0.065 / 5.64 / 1.00, pass |
| III-1 at t=20 / t=85 | 470 / 570 | 472 / 362 | 356 / 136 | 398 / 208 |
| III-3 floor | ≈250 | 32 (5 of 10 extinct) | 18 | 33 |
| III-3 period | ≈200 | 752 (6/10) | 495 (2/5) | 412 (3/5) |
| III-4 range / period | ≈1,000 / ≈125 | **657 pass** / 239 | 120 / 136 pass | 106 / 132 pass |
| III-5 extinct by t=1500 | yes | 0 of 10 | 0 of 10 | 0 of 10 |

- **MASON's model doesn't reproduce the book's population figures either,** quantitatively scored on its own configs. Its
  III-1 crashes after the founding boom and settles at 348, against our 360 under the same written rule. Two
  independent implementations of the text land in the same place.
- **Its large III-4 swings come from its cheaper reading of p.65,** at about twice the book's period. With C3 above, this
  is the second sign that the book's III-4 needs reproduction cheaper than the endowment rule.
- **MASON's printed vision and metabolism are wrong:** children are counted but never added to the set the statistics
  average over. Our driver records on-grid values instead.

## C1 with cheap children at a fitted threshold (2026-10-23)

C1 (mates within vision) and C3 (each parent gives at most 5 sugar; the child's threshold is a fresh draw) together,
with the fertility threshold lowered and fitted under the protocol of the 0.83 default.
- **Fitting:** to one number only, III-1's steady population (500; its target's statistic, the mean over t=500–2500), 5
  seeds ([fit_c1c3.py](../../diagnostics/fit_c1c3.py)). The grid: θ=1.0 314, 0.9 361, 0.8 425, 0.78 439, 0.76 467, 0.75 481,
  **0.74 495**, 0.73 510, 0.7 582, 0.6 757, 0.5 822.
- **Freezing:** θ=0.74 was frozen in `candidates.FITTED` before any other run.
- **Validation:** on every other population row, as variant C1+C3fit of
  [candidates.py](../../diagnostics/candidates.py), 5 seeds
  ([output](../../diagnostics/output/candidates_fit.txt)).

| Target | Book | p.55 (`VAR-book`) | Default (θ=0.83) | C1 | C1+C3 | **C1+C3fit (θ=0.74)** |
|---|---|---|---|---|---|---|
| III-1 steady population (fitted) | 500 | 360 near | 478 pass | 420 pass | 314 near | 495 pass |
| III-1 small fluctuations | ≤0.10 | 0.059 pass | 0.065 pass | 0.087 pass | 0.18 fail | 0.062 pass |
| III-1 mean vision / metabolism | 5.3 / 1.0 | pass / pass | pass / pass | pass / pass | pass / pass | 5.94 near / pass |
| III-3 period | 200 | 495 (2/5) | 412 (3/5) | 554 | 597 (1/5) | **144 near** |
| III-3 floor | 250 | 18 | 33 | 163 near | 8 | 95 fail |
| III-3 agents that ever lived | 12,500 | 1,610 | 3,690 | 8,400 near | 1,380 | **9,060 near** |
| III-4 period / range | 125 / 1,000 | 136 pass / 120 | 132 pass / 106 | 115 pass / 321 | 112 pass / 615 pass | **107 pass / 866 pass** |
| III-5 extinct by t=1500 | yes | 0/5 | 0/5 | 0/5 | 0/5 | 0/5 |
| VI-2 crash at t≈20 / extinct by t=200 | 130 / yes | 209 / 2 of 5 | 209 / 1 of 5 | 216 / 0 | 221 / 0 | 228 / 0 |
| VI-3 minimum | 65 | 27 | 36 | 64 pass | 109 | 198 fail |
| VI-3 first peak | 1,190 | 272 | 308 | 639 | 529 | **879 near** |
| VI-3 floor / ceiling after t=250 | 700 / 1,200 | 153 / 358 | 204 / 534 | 453 / 860 near | 426 near / 557 | **731 pass / 904 near** |
| VI-3 period | 115 | 322 (2/5) | 241 (2/5) | 274 | 171 (4/5) | 172 |

Unmarked cells fail.

**Findings:**
- **The best out-of-sample record of any setting so far.** Fitted only to III-1's level, it also gives:
  - III-4's swings at the book's period (range 866);
  - VI-3's floor (731) with its first peak and ceiling near;
  - III-3's period (144) and agents ever lived (9,060) near.
- **What it still misses is the dying:** III-3's floor (95), III-5's extinction, VI-2's extinction (none of 5, where
  the default loses 1) and VI-3's near-extinction (its minimum of 198 is far above the book's 65). The society booms and
  busts like the book's, but never comes close to dying.
- **Reading:** easy contact plus cheap children reproduce the book's oscillations; the book's extinctions need something
  more, or rarer luck than five seeds show. It remains a labelled departure from p.55 and p.56: nothing here changes
  the default.

## Ascape's own runs (2026-10-23)

Ascape 5.6.1's Sugarscape sex model (Brookings), run headless from its release jar on Figs III-1, III-3, III-4 and
III-5, 10 seeds each ([diagnostics/ascape/](../../diagnostics/ascape/README.md); scored by
[ascape_compare.py](../../diagnostics/ascape_compare.py)). Our driver runs Ascape's rules and agent code unchanged and
sets only the stated endowments and fertility ages, on Ascape's generated landscape (300 founders) and on the book's
map (400). Read from its source, Ascape departs from the text in these ways:
- **Children:** each parent gives at most 5 sugar, but a bug keeps only the second gift.
- **Fertility threshold:** each child's is a fresh draw from the founders' range.
- **Founders** start at random ages.
- **Movement** takes the most sugar in sight with no preference for the nearest site.

| Target | Book | Ascape, own landscape | Ascape, book map | Ours, p.55 (`VAR-book`) | Ours, default |
|---|---|---|---|---|---|
| III-1 steady population | ≈500 | 268 fail | 227 fail | 360 near | 478 pass |
| III-1 fluctuations | ≤0.10 | 0.13 fail | 0.15 fail (1 of 10 extinct) | 0.059 pass | 0.065 pass |
| III-3 floor | ≈250 | 0 (10 of 10 extinct) | 0 (10 of 10 extinct) | 18 | 33 |
| III-4 period | ≈125 | **126 pass** | **127 pass** | 136 pass | 132 pass |
| III-4 range | ≈1,000 | 556 near | **672 pass** | 120 | 106 |
| III-5 extinct by t=1500 | yes | 0 of 10 | 0 of 10 | 0 of 10 | 0 of 10 |

- **Ascape reproduces Fig III-4's cycle in every seed:** period 124–128, range 444–807. It is the only implementation
  with both the book's period and most of its swing. MASON's swings come at twice the period, and ours have the period
  without the swings.
- **It misses III-1, III-3 and III-5 further than we do.** III-1 crashes after the founding generation (164 at t=85)
  and settles at 230–270. III-3 dies out in every run. III-5 swings by about 1,050 but never dies out.
- **The landscape and the founder count barely matter;** the rule code makes the difference. This confirms C3's
  reading: cheap children make III-4's cycle, and nothing tested here makes every figure.

## Rule-by-rule sweeps (C4, 2026-10-23)

README candidate C4 (every agent moves and eats, then every agent runs its other rules), run by
[candidates2.py](../../diagnostics/candidates2.py) under the defaults, 5 seeds.

| Target | Book | Default | C4 |
|---|---|---|---|
| III-1 steady population | 500 | 478 pass | 435 pass |
| III-3 floor / agents ever lived | 250 / 12,500 | 33 / 3,690 | 33 / 3,160 |
| III-4 period / range | 125 / 1,000 | 132 / 106 | 144 / 282 |
| III-5 extinct by t=1500 | yes | 0 of 5 | 0 of 5 |
| III-12 Blue / Red advance | 10–60 / −60 to −10 | 8.1 / −4.7 | 7.8 / −4.2 |
| III-13 Blue's advance under combat | −5 to 5 | 9.6 | 9.4 |

Sweeps widen III-4's swings somewhat and leave everything else where it was. VI-3 does worse under them (Chapter VI
record).

## Visual comparison

- **III-1** (colored by vision): high-vision agents take over, as in Animation III-2; but the population stays on the peaks instead of filling a diagonal band.
- **III-8**: each mountain trends to one color, with reversals (see 3).
- **III-9**: Blue gradually eradicates Red, one of the book's three patterns (Animation III-9).
- **III-11**: each tribe holds its own peak; same-tribe replacements appear scattered across the lowlands.
- **III-12**: no colliding waves; each block settles on its own peak.
- **III-15**: the soup sorts onto the two peaks and colors consolidate; the population stays ≈340 and doesn't spill into the lowlands.
