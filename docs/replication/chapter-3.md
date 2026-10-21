# Replication report

8 pass, 5 near, 10 fail, of 23 targets.

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
| III-8 | best-friend closeness | Anim III-8, p.80 | 0.91 | 0.8–1 | 0.9819 [0.9791–0.9857] | 5/5 | pass |
| III-9 | one of the three patterns (proxy) | p.83 | — | 0.8–1 | 0.6 [0–1] | 10/10 | fail |
| III-11 | both tribes persist (proxy) | Anim III-11, p.86 | — | 0.8–1 | 1 [1–1] | 5/5 | pass |
| III-12 | Blue wave advances NE (proxy) | Anim III-12, p.88 | — | 10–60 | 8.734 [8.457–9.063] | 5/5 | near |
| III-12 | Red wave advances SW (proxy) | Anim III-12, p.88 | — | -60–-10 | -6.318 [-7.384–-5.578] | 5/5 | near |
| III-13 | combat suppresses Blue's wave (proxy) | Anim III-13, p.89 | — | -5–5 | 10.61 [9.47–11.95] | 5/5 | fail |
| III-14 | no runaway hegemony (proxy) | p.90 | — | 0.5–1 | 0.5 [0–1] | 10/10 | pass |
| III-15 | Red and Blue on opposite mountains | p.92 fn 32 | 0.45 | 0.3–0.5 | 0.15 [0–1] | 20/20 | fail |
| III-15 | Red dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0 [0–0] | 20/20 | near |
| III-15 | Blue dominates both | p.92 fn 32 | 0.25 | 0.1–0.4 | 0 [0–0] | 20/20 | near |
| III-15 | extinction (small frequency) | p.92 fn 32 | — | 0–0.15 | 0 [0–0] | 20/20 | pass |

Run: `python -m replication.report --chapter III --jobs 8` on 2026-10-21 (branch feat/chapter-3). Seeds as registered (5, 10, or 20).
Chapter II regression run on the same branch: 19 pass / 12 near / 0 fail, every row identical to docs/replication/chapter-2.md.

## Choices made from evidence or by necessity

- **Combat blocks** measured from frame 1 of Animations III-9 and III-12: Blue 20×20 at the SW corner, Red 20×20 at the NE corner, ≈270 agents each (III-9/14) and ≈370 each (III-12/13). III-11 uses 200 each ("fix the population at 400", p.86).
- **Proto-history** starts with 100 agents ("small, low density"); the book gives no number.
- **Endowments**: 50–100 for the sex runs (p.57), 10–40 where p.65 lowers "the sugar necessary for reproduction"; 25–50 (the Chapter II finding) for the culture and combat runs.

## What matches

- Evolution under S (Fig III-2): mean vision 5.6 at t≈900 (book 5.3), metabolism falls to 1.0 (book 1.0).
- Population stability under default S: relative fluctuation 5.5% (book "less than 10 percent").
- Large-oscillation period: 118 (book ≈125).
- Best-friend closeness 0.98 (book 0.91), same-tribe war of attrition persists (III-11), combat with assimilation avoids runaway hegemony in half the runs (III-14), no proto-history extinctions.

## Open discrepancies (investigated, unresolved)

The failures cluster into three groups that look like shared causes, not ten separate defects.

1. **Population dynamics are too damped and too low.** Steady population ≈369 vs ≈500 (III-1); small-oscillation run nearly dies out (floor 24 vs ≈250) with period ≈720 vs ≈200 (III-3); large-oscillation run swings ≈144 vs ≈1000 around a high mean (III-4); the combined run never goes extinct (III-5). Animation III-2 shows the book's population spilling into a diagonal band across the lowlands; ours stays on the peaks.
   Investigated: (a) starting ages — random initial ages make it worse; (b) evolution — our vision/metabolism evolve as fast or faster than the book's; (c) the population is birth-limited, not food-limited (immortal metabolism-1 runs hold ≈490 agents); (d) Moore instead of von Neumann mating neighbors — only +6%. Lead: interactions happen less often than in the book (Chapter II's mean neighbors 0.78 vs 0.9), but that gap alone looks too small.
2. **Inheritance barely raises inequality** (III-7 Gini 0.33 vs 0.743) **or slows selection** (vision 5.29 vs ≈4.3). Deaths are 99% old age, parents leave ≈180 sugar to ≈2 living children; but fertile agents spend any surplus on children, so wealth stays compressed (max ≈850, mean ≈100). Inheritance mostly funds extra births (old-age deaths triple).
3. **Culture converges too slowly.** III-8: only 2 of 5 runs have both mountains ≥95% one color at t=3000 (book: all Blue by ≈2700 in its run); sides reach 95–98% and then flip back (e.g. NE 0.95 Blue at t=2000, 0.33 at t=3000), so tag positions have not locked. III-15 rarely reaches a pure pattern by t=1000 (opposite mountains 15% vs ≈45%; single-color dominance 0% vs ≈25% each).
4. **Waves (III-12) are not reproduced** — the same failure as II-6 — **and combat does not suppress movement in III-13** (Blue advances 10.6 vs 8.7 without combat). Since our no-combat waves don't form, the comparison isn't meaningful yet.
5. **III-9 one-of-three-patterns 60% vs ≥80%**: four runs still have mixed sides at t=1000; the book gives no time for its outcomes.

## Visual comparison

- **III-1** (colored by vision): high-vision agents take over, as in Animation III-2; but the population stays on the peaks instead of filling a diagonal band.
- **III-8**: each mountain trends to one color, with reversals (see 3).
- **III-9**: Blue gradually eradicates Red, one of the book's three patterns (Animation III-9).
- **III-11**: each tribe holds its own peak; same-tribe replacements appear scattered across the lowlands.
- **III-12**: no colliding waves; each block settles on its own peak.
- **III-15**: the soup sorts onto the two peaks and colors consolidate; the population stays ≈340 and doesn't spill into the lowlands.
