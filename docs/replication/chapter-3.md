# Replication report

11 pass, 4 near, 9 fail, of 24 targets.

| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |
|---|---|---|---|---|---|---|---|
| III-1 | steady population | Fig III-1, p.58 | 500 | 400–600 | 368.9 [360.4–376] | 5/5 | near |
| III-1 | small fluctuations | p.57 | 0.1 | 0–0.1 | 0.05514 [0.04277–0.07192] | 5/5 | pass |
| III-1 | mean vision at t≈900 | Fig III-2, p.63 | 5.3 | 4.8–5.8 | 5.606 [5.248–5.944] | 5/5 | pass |
| III-1 | mean metabolism, t=300–900 | Fig III-2, p.63 | 1 | 0.9–1.15 | 1 [1–1] | 5/5 | pass |
| III-3 | oscillation period | p.64 | 200 | 150–250 | 722.7 [428–1028] | 3/5 | fail |
| III-3 | population floor | p.64 | 250 | 200–350 | 24.2 [0–59] | 5/5 | fail |
| III-4 | oscillation period | p.65 | 125 | 100–150 | 118.2 [115–123] | 5/5 | pass |
| III-4 | oscillation range | Fig III-4, p.65 | 1000 | 600–1400 | 143.8 [104–259] | 5/5 | fail |
| III-5 | extinction frequency (proxy) | Fig III-5, p.66 | — | 0.5–1 | 0 [0–0] | 10/10 | fail |
| III-7 | Gini with inheritance | p.67 | 0.743 | 0.65–0.85 | 0.3301 [0.3006–0.3601] | 5/5 | fail |
| III-7 | mean vision at t≈900 | Fig III-7, p.68 | 4.3 | 3.9–4.7 | 5.292 [5.088–5.398] | 5/5 | fail |
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
| III-15 | Red dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0.3 [0–1] | 20/20 | pass |
| III-15 | Blue dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0.3 [0–1] | 20/20 | pass |
| III-15 | extinction (small frequency) | p.92 fn 32 | — | 0–0.15 | 0 [0–0] | 20/20 | pass |

Run: `python -m replication.report --chapter III --jobs 8` on 2026-10-21 (branch feat/chapter-3, after the final-review fix pass). Seeds as registered (5, 10, or 20).
Fast suite 144 passed; `pytest -m slow tests/test_replication_ch3.py`: 11 passed, 13 failed (the near + fail rows).
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

## Visual comparison

- **III-1** (colored by vision): high-vision agents take over, as in Animation III-2; but the population stays on the peaks instead of filling a diagonal band.
- **III-8**: each mountain trends to one color, with reversals (see 3).
- **III-9**: Blue gradually eradicates Red, one of the book's three patterns (Animation III-9).
- **III-11**: each tribe holds its own peak; same-tribe replacements appear scattered across the lowlands.
- **III-12**: no colliding waves; each block settles on its own peak.
- **III-15**: the soup sorts onto the two peaks and colors consolidate; the population stays ≈340 and doesn't spill into the lowlands.
