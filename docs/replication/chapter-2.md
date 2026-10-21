# Replication report

19 pass, 12 near, 0 fail, of 31 targets.

| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |
|---|---|---|---|---|---|---|---|
| II-1 | agents still moving (proxy) | Anim II-1, p.28 | — | 0–0.5 | 0 [0–0] | 5/5 | pass |
| II-4 | carrying capacity | Fig II-4, p.31 | 224 | 205–245 | 232.6 [221–243] | 10/10 | pass |
| II-4 | mean vision at t=500 | p.32 | 4.1 | 3.9–4.3 | 3.791 [3.695–3.97] | 10/10 | near |
| II-4 | mean metabolism at t=500 | p.32 | 1.8 | 1.6–2 | 1.852 [1.792–1.901] | 10/10 | pass |
| II-4 | mean neighbors | Anim II-5, p.41 | 0.9 | 0.75–1.05 | 0.7967 [0.7577–0.8436] | 10/10 | pass |
| II-4-gini | initial Gini | Anim II-4, p.38 | 0.23 | 0.2–0.26 | 0.2297 [0.2175–0.2462] | 10/10 | pass |
| II-4-gini | long-run Gini | Anim II-4, p.37 | 0.503 | 0.45–0.56 | 0.4781 [0.4687–0.4891] | 10/10 | pass |
| II-6 | wave reaches NE peak (proxy) | Anim II-6, p.43 | — | 0.15–1 | 0.04887 [0.03349–0.0625] | 5/5 | near |
| II-6-measured | wave reaches NE peak (proxy) | Anim II-6, p.43 | — | 0.15–1 | 0.01339 [0.006667–0.02649] | 5/5 | near |
| II-7 | high-vision agents migrate (proxy) | Anim II-7, p.45 | — | 0.3–1 | 0.5175 [0.4888–0.5488] | 5/5 | pass |
| II-7 | low-vision agents hibernate (proxy) | Anim II-7, p.45 | — | -0.15–0.15 | 0.2223 [0.1721–0.2644] | 5/5 | near |
| II-8 | peaks abandoned under pollution (proxy) | Anim II-8, p.48 | — | 0–0.6 | 0.5322 [0.4992–0.5597] | 5/5 | pass |
| II-8 | lower carrying capacity when polluted (proxy) | p.50 | — | 0–0.9 | 0.8388 [0.8221–0.861] | 5/5 | pass |
| II-5/m1/v1 | carrying capacity | Fig II-5, p.31 | 450 | 405–495 | 432.9 [423–441] | 10/10 | pass |
| II-5/m1/v2 | carrying capacity | Fig II-5, p.31 | 465 | 418.5–511.5 | 452.3 [443–459] | 10/10 | pass |
| II-5/m1/v3 | carrying capacity | Fig II-5, p.31 | 475 | 427.5–522.5 | 465.9 [457–473] | 10/10 | pass |
| II-5/m1/v5.5 | carrying capacity | Fig II-5, p.31 | 490 | 441–539 | 482.4 [476–489] | 10/10 | pass |
| II-5/m1/v10.5 | carrying capacity | Fig II-5, p.31 | 495 | 445.5–544.5 | 491.8 [486–497] | 10/10 | pass |
| II-5/m2/v1 | carrying capacity | Fig II-5, p.31 | 330 | 297–363 | 269.3 [254.8–280] | 10/10 | near |
| II-5/m2/v2 | carrying capacity | Fig II-5, p.31 | 365 | 328.5–401.5 | 299.4 [291–306.1] | 10/10 | near |
| II-5/m2/v3 | carrying capacity | Fig II-5, p.31 | 375 | 337.5–412.5 | 302.7 [290–310] | 10/10 | near |
| II-5/m2/v5.5 | carrying capacity | Fig II-5, p.31 | 390 | 351–429 | 313.5 [305–325] | 10/10 | near |
| II-5/m2/v10.5 | carrying capacity | Fig II-5, p.31 | 400 | 360–440 | 322.5 [310–336] | 10/10 | near |
| II-5/m3/v1 | carrying capacity | Fig II-5, p.31 | 225 | 202.5–247.5 | 191.7 [181–200.5] | 10/10 | near |
| II-5/m3/v2 | carrying capacity | Fig II-5, p.31 | 228 | 205.2–250.8 | 213.7 [196–231] | 10/10 | pass |
| II-5/m3/v3 | carrying capacity | Fig II-5, p.31 | 255 | 229.5–280.5 | 230.7 [216–245.5] | 10/10 | pass |
| II-5/m3/v4.5 | carrying capacity | Fig II-5, p.31 | 260 | 234–286 | 246 [235–260] | 10/10 | pass |
| II-5/m3/v5.5 | carrying capacity | Fig II-5, p.31 | 260 | 234–286 | 248.7 [236–263] | 10/10 | pass |
| II-5/m3/v6.5 | carrying capacity | Fig II-5, p.31 | 287 | 258.3–315.7 | 249.2 [238.5–263] | 10/10 | near |
| II-5/m3/v8 | carrying capacity | Fig II-5, p.31 | 280 | 252–308 | 252.3 [242–262.3] | 10/10 | pass |
| II-5/m3/v10.5 | carrying capacity | Fig II-5, p.31 | 287 | 258.3–315.7 | 253.6 [247.7–260.4] | 10/10 | near |

Run: `python -m replication.report --chapter II --rerun --jobs 8` on 2026-10-21 (branch feat/foundation-ch2, after the final-review fix pass).
Seeds per experiment as registered (5 or 10). Fast suite 83 passed; `pytest -m slow`: 19 passed, 12 failed (the 12 "near" rows).

## Evidence-based parameter choices

- **Initial endowment 25–50** for II-1, II-2/II-4, II-5, II-6, II-7, II-8 (the book states none; II-3/II-4-gini keeps its stated 5–25, and our initial Gini of 0.230 matches the book exactly).
  Of the ranges the book uses elsewhere, only 25–50 reproduces Fig II-4's population curve (flat at 400 until t≈7, ≈255 at t≈48, ≈241 at t≈95):
  RMS error 11 agents, against 49 for 5–25 and 57 for 50–100 (5 seeds each, digitized curve).
- **Winter growback is fractional** (α/β per period), per the design spec; `winter_growback="pulse"` (α every β-th period) remains available.
- **II-6** follows the text ("exactly as in animation II-2": 400 agents, 20×20 block). **II-6-measured** is a variant using the block counted from Animation II-6 frame 1: 20×19 with ≈284 agents.

## Open discrepancies

1. **Fig II-5 metabolism 2 (all five points) and three metabolism-3 points are 10–20% low at t=450–500. Leading hypothesis: the book's sweep was read near t≈50, not at the asymptote.**
   Our populations at t=45–60 match all 18 book points within ±5%:

   | Point | Book | Ours t=45–60 | Ours t=450–500 |
   |---|---|---|---|
   | m1 v1 / v2 / v3 / v5.5 / v10.5 | 450 / 465 / 475 / 490 / 495 | 435 / 454 / 467 / 483 / 492 | 433 / 452 / 466 / 482 / 492 |
   | m2 v1 / v2 / v3 / v5.5 / v10.5 | 330 / 365 / 375 / 390 / 400 | 341 / 368 / 388 / 398 / 395 | 269 / 299 / 303 / 314 / 322 |
   | m3 v1 / v2 / v3 / v4.5 | 225 / 228 / 255 / 260 | 219 / 237 / 249 / 262 | 192 / 214 / 231 / 246 |
   | m3 v5.5 / v6.5 / v8 / v10.5 | 260 / 287 / 280 / 287 | 267 / 271 / 275 / 281 | 249 / 249 / 252 / 254 |

   The metabolism-1 curve is flat, so it matches at any time; that explains why only the m2/m3 points miss. **Decided (user, 2026-10-21): carrying capacity is measured at t=500**, the book's asymptotic definition; these rows stay "near" as a documented discrepancy.
   Also tested and rejected: metabolism fixed at the mean, and a 0..2m spread.
2. **II-6 diagonal waves are not reproduced** by either variant (NE share at t=200: 0.049 for the text's 400 agents, 0.013 for the measured 284; band 0.15–1.0). The 400-agent block drains its interior and sends a few agents NE, but no coherent bands.
   Ruled out: the block layout, the endowment, and "agents must move" (which also breaks II-1's static end state).
   Reviewer's mechanism note: behind the frontier, regrown capacity-2 sites tie with fresh sites ahead, and the random direction order sends front agents backward as often as forward. Remaining suspects: the corridor capacities of the map, and the order of rules within a period.
3. **II-4 mean vision at t=500 is 3.79 (seeds 3.70–3.97) against the book's single-run 4.1.** Trajectory 3.50 → 3.69 (t=50) → 3.79; metabolism selection matches (1.85 vs 1.8). No modelling defect found.
4. **II-7 hibernation proxy 0.22 against the ≤0.15 band.** Low-vision agents (vision ≤ 2) swing with the seasons more than the band allows (0.18 under pulse winter, 0.22 under fractional). Migration by high-vision agents passes. The band is our own proxy; not widened.

## Visual comparison with the book's animations

- **II-1** (G∞): agents settle on terrace ridges and stop moving by t≈50 (moved = 0 at t=80–100), as in Animation II-1.
- **II-2/II-4** (G1): two colonies form, one per peak, with constant grazing; matches Animation II-2.
- **II-6**: the block expands into the book's frame-2 ring by t≈3–4, then fills a disk on the SW peak; see open discrepancy 2.
- **II-7** (S1,8,50): the population swings to whichever peak is in summer (NE at t=40 and 125, SW at t=75), with hibernators left behind; matches Animation II-7.
- **II-8** (P11 at t=50, D1 at t=100): agents abandon the polluted peaks for the hinterland, then return after diffusion; the book's re-colonized peaks look denser than ours.
