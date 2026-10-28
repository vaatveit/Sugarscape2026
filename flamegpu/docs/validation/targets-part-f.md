# Part F: book targets, GPU against Python

Every experiment at regular size on `build\` (seatbelts on), registered seeds and steps, run with
`bridge.gpu_run TEST-tiny II III IV V VI VAR --jobs 4 --resume` into the main checkout's `results-gpu`, then scored with
`bridge.gpu_report --chapter X --gpu <main checkout>\flamegpu\results-gpu --python <main checkout>\results` for II to VI.

| Chapter | Python | GPU |
|---|---|---|
| II | 37 pass, 9 near, 3 fail | 37 pass, 9 near, 3 fail |
| III | 11 pass, 5 near, 9 fail | 14 pass, 5 near, 6 fail |
| IV | 28 pass, 9 near, 14 fail | 25 pass, 10 near, 16 fail |
| V | 2 pass, 0 near, 4 fail | 2 pass, 0 near, 4 fail |
| VI | 21 pass, 4 near, 13 fail | 4 pass, 5 near, 14 fail, 15 not run |

VI's 15 not run are VI-4 to VI-9, the Schelling and Ring World models, skipped by the user's decision (2026-10-27:
"I am not interested in the Schelling and Ring World models"). Of the 23 VI targets both sides ran, Python has 4 pass
more than the GPU and the GPU 4 more near or fail: the four status changes below.

## Status changes

Fifteen, every one already met in an earlier part with the same GPU and Python values: the GPU is deterministic per
seed, and Part F changed nothing on these paths. Each p is the seed-level test that part ran (Welch's t-test, or
Fisher's exact test for outcomes), at the registered seeds unless noted.

| Target | Python | GPU | Seed-level p | Where |
|---|---|---|---|---|
| III-3 oscillation period | fail, 393 | near, 266 | 0.087 | [Part A](chapter3-part-a.md) |
| III-3 agents that ever lived | near, 9,934 | pass, 11,660 | 0.19 | Part A |
| III-4 oscillation range | near, 598 | pass, 715 | 0.49 | Part A |
| III-7 mean vision at t ≈ 900 | fail, 5.37 | near, 5.00 | 0.055 | Part A |
| III-8 each side culturally pure | fail, 2 of 5 | pass, 4 of 5 | 0.52 | Part A |
| III-14 no runaway hegemony | pass, 5 of 10 | near, 4 of 10 | 1.0 | [Part B](chapter3-part-b.md) |
| III-15 Red dominates both | near, 9 of 20 | pass, 8 of 20 | 1.0 | Part A |
| IV-6/trade/v2 carrying capacity at t≈50 | pass, 136.7 | near, 143.3 | 0.25 | [Part C](chapter4-part-c.md) |
| IV-6/notrade/v2 carrying capacity at t≈50 | pass, 97.6 | near, 100.2 | 0.60 | Part C |
| IV-14 dispersion with S | pass, 0.378 | fail, 0.334 (2 seeds survive) | 0.37 | Part C |
| IV-18 long-run mean foresight | near, 5.60 | fail, 5.85 | 0.82 | Part C |
| VI-1 Gini of total wealth | pass, 0.277 | near, 0.337 | 0.021; 0.59 at 20 seeds a side (0.316 against 0.321) | [Part D](chapter5-part-d.md) |
| VI-3 first peak | near, 831 | fail, 636 | 0.33 | Part C |
| VI-3 oscillation floor | pass, 678 | near, 508 | 0.37 | Part C |
| VI-3 oscillation ceiling | pass, 960 | near, 859 | 0.51 | Part C |

- **No change is the GPU's.** Every seed-level p is 0.055 or more, except VI-1's Gini at 5 seeds (0.021), which 20
  seeds a side resolve (p 0.59): Python's five registered seeds sit low.
- **They go both ways.** Six move toward the book (Chapter III's, but III-14), nine away (III-14, IV's and VI's), each
  by noise near a band's edge or by which seeds of a bistable run survive (IV-14).
- The time-series rule flags none of these experiments ([agreement-part-f.md](agreement-part-f.md): 0 of 8,172
  windows).

The five chapter reports follow as `gpu_report` wrote them.

## Chapter II

Python: 37 pass, 9 near, 3 fail, 0 not run.  
GPU: 37 pass, 9 near, 3 fail, 0 not run.

| Experiment | Target | Book | Band | Python mean [min–max] | Python | GPU mean [min–max] | GPU | GPU − Python |
|---|---|---|---|---|---|---|---|---|
| II-1 | agents still moving (proxy) | Anim II-1, p.28 — | 0–0.5 | 0 [0–0] | pass | 0 [0–0] | pass | 0 |
| II-4 | carrying capacity | Fig II-4, p.31 224 | 205–245 | 232.6 [221–243] | pass | 237 [226–252.2] | pass | 4.382 |
| II-4 | mean vision at t=500 | p.32 4.1 | 3.9–4.3 | 3.791 [3.695–3.97] | near | 3.89 [3.824–4.026] | near | 0.09893 |
| II-4 | mean metabolism at t=500 | p.32 1.8 | 1.6–2 | 1.852 [1.792–1.901] | pass | 1.872 [1.786–2.022] | pass | 0.0194 |
| II-4 | mean neighbors | Anim II-5, p.41 0.9 | 0.75–1.05 | 0.7967 [0.7577–0.8436] | pass | 0.817 [0.788–0.8429] | pass | 0.02025 |
| II-4-gini | initial Gini | Anim II-4, p.38 0.23 | 0.2–0.26 | 0.2297 [0.2175–0.2462] | pass | 0.232 [0.2205–0.2456] | pass | 0.002386 |
| II-4-gini | long-run Gini | Anim II-4, p.37 0.503 | 0.45–0.56 | 0.4772 [0.4685–0.4822] | pass | 0.4836 [0.4764–0.4915] | pass | 0.006406 |
| II-6 | wave reaches NE peak (proxy) | Anim II-6, p.43 — | 0.15–1 | 0.04887 [0.03349–0.0625] | fail | 0.05537 [0.04813–0.06316] | fail | 0.006499 |
| II-6-measured | wave reaches NE peak (proxy) | Anim II-6, p.43 — | 0.15–1 | 0.01339 [0.006667–0.02649] | fail | 0.01219 [0–0.02069] | fail | -0.0012 |
| II-7 | high-vision agents migrate (proxy) | Anim II-7, p.45 — | 0.3–1 | 0.5175 [0.4888–0.5488] | pass | 0.5202 [0.4856–0.5612] | pass | 0.002703 |
| II-7 | low-vision agents hibernate (proxy) | Anim II-7, p.45 — | -0.15–0.15 | 0.2223 [0.1721–0.2644] | fail | 0.2348 [0.1989–0.2969] | fail | 0.01248 |
| II-8 | peaks abandoned under pollution (proxy) | Anim II-8, p.48 — | 0–0.6 | 0.5322 [0.4992–0.5597] | pass | 0.5212 [0.4914–0.5333] | pass | -0.01097 |
| II-8 | lower carrying capacity when polluted (proxy) | p.50 — | 0–0.9 | 0.8388 [0.8221–0.861] | pass | 0.8171 [0.767–0.8595] | pass | -0.02166 |
| II-5/m1/v1 | carrying capacity | Fig II-5, p.31 450 | 405–495 | 432.9 [423–441] | pass | 432.4 [424–441] | pass | -0.5 |
| II-5/m1/v2 | carrying capacity | Fig II-5, p.31 465 | 418.5–511.5 | 452.3 [443–459] | pass | 450.7 [439–457] | pass | -1.6 |
| II-5/m1/v3 | carrying capacity | Fig II-5, p.31 475 | 427.5–522.5 | 465.9 [457–473] | pass | 466.1 [457–474] | pass | 0.2 |
| II-5/m1/v5.5 | carrying capacity | Fig II-5, p.31 490 | 441–539 | 482.4 [476–489] | pass | 482.7 [477–487] | pass | 0.3 |
| II-5/m1/v10.5 | carrying capacity | Fig II-5, p.31 495 | 445.5–544.5 | 491.8 [486–497] | pass | 492 [488–495] | pass | 0.2 |
| II-5/m2/v1 | carrying capacity | Fig II-5, p.31 330 | 297–363 | 269.3 [254.8–280] | near | 273.8 [252.1–289] | near | 4.529 |
| II-5/m2/v2 | carrying capacity | Fig II-5, p.31 365 | 328.5–401.5 | 299.4 [291–306.1] | near | 303.5 [280.1–314.2] | near | 4.114 |
| II-5/m2/v3 | carrying capacity | Fig II-5, p.31 375 | 337.5–412.5 | 302.7 [290–310] | near | 308.6 [287–320.8] | near | 5.831 |
| II-5/m2/v5.5 | carrying capacity | Fig II-5, p.31 390 | 351–429 | 313.5 [305–325] | near | 316.4 [290–333] | near | 2.9 |
| II-5/m2/v10.5 | carrying capacity | Fig II-5, p.31 400 | 360–440 | 322.5 [310–336] | near | 328 [305–344] | near | 5.5 |
| II-5/m3/v1 | carrying capacity | Fig II-5, p.31 225 | 202.5–247.5 | 191.7 [181–200.5] | near | 195.4 [179.5–204.9] | near | 3.745 |
| II-5/m3/v2 | carrying capacity | Fig II-5, p.31 228 | 205.2–250.8 | 213.7 [196–231] | pass | 215.9 [198–229.3] | pass | 2.176 |
| II-5/m3/v3 | carrying capacity | Fig II-5, p.31 255 | 229.5–280.5 | 230.7 [216–245.5] | pass | 234.3 [213–251] | pass | 3.533 |
| II-5/m3/v4.5 | carrying capacity | Fig II-5, p.31 260 | 234–286 | 246 [235–260] | pass | 246.2 [229–259.8] | pass | 0.1118 |
| II-5/m3/v5.5 | carrying capacity | Fig II-5, p.31 260 | 234–286 | 248.7 [236–263] | pass | 251.6 [237–264] | pass | 2.916 |
| II-5/m3/v6.5 | carrying capacity | Fig II-5, p.31 287 | 258.3–315.7 | 249.2 [238.5–263] | near | 253.3 [240–263] | near | 4.139 |
| II-5/m3/v8 | carrying capacity | Fig II-5, p.31 280 | 252–308 | 252.3 [242–262.3] | pass | 254.8 [246–266] | pass | 2.547 |
| II-5/m3/v10.5 | carrying capacity | Fig II-5, p.31 287 | 258.3–315.7 | 253.6 [247.7–260.4] | near | 255.9 [249.9–265] | near | 2.216 |
| II-5/m1/v1 | carrying capacity at t≈50 | Fig II-5, p.31 450 | 405–495 | 434.9 [425.2–443] | pass | 434.9 [426.4–441.9] | pass | 0.03125 |
| II-5/m1/v2 | carrying capacity at t≈50 | Fig II-5, p.31 465 | 418.5–511.5 | 453.9 [445.2–460.6] | pass | 452.3 [441.4–458.6] | pass | -1.606 |
| II-5/m1/v3 | carrying capacity at t≈50 | Fig II-5, p.31 475 | 427.5–522.5 | 467 [458.2–473.6] | pass | 467.2 [458.1–474.7] | pass | 0.15 |
| II-5/m1/v5.5 | carrying capacity at t≈50 | Fig II-5, p.31 490 | 441–539 | 483 [476.6–489.4] | pass | 483.2 [477.7–487.4] | pass | 0.25 |
| II-5/m1/v10.5 | carrying capacity at t≈50 | Fig II-5, p.31 495 | 445.5–544.5 | 492.1 [486.6–497.3] | pass | 492.2 [488.2–495.1] | pass | 0.1125 |
| II-5/m2/v1 | carrying capacity at t≈50 | Fig II-5, p.31 330 | 297–363 | 341.4 [324.9–353.3] | pass | 345.7 [324.9–359.5] | pass | 4.325 |
| II-5/m2/v2 | carrying capacity at t≈50 | Fig II-5, p.31 365 | 328.5–401.5 | 368.3 [362.4–374.4] | pass | 372.3 [349–389.1] | pass | 3.969 |
| II-5/m2/v3 | carrying capacity at t≈50 | Fig II-5, p.31 375 | 337.5–412.5 | 388.4 [381.9–394.2] | pass | 393.9 [373.8–408.6] | pass | 5.538 |
| II-5/m2/v5.5 | carrying capacity at t≈50 | Fig II-5, p.31 390 | 351–429 | 398.2 [387.6–405.9] | pass | 405.2 [391.4–415.6] | pass | 7 |
| II-5/m2/v10.5 | carrying capacity at t≈50 | Fig II-5, p.31 400 | 360–440 | 395.1 [380.9–405.8] | pass | 398.4 [387.2–411.7] | pass | 3.4 |
| II-5/m3/v1 | carrying capacity at t≈50 | Fig II-5, p.31 225 | 202.5–247.5 | 218.7 [204.9–232.9] | pass | 222.8 [203.2–239.8] | pass | 4.088 |
| II-5/m3/v2 | carrying capacity at t≈50 | Fig II-5, p.31 228 | 205.2–250.8 | 236.7 [222.2–252.3] | pass | 239.3 [216.6–255.6] | pass | 2.638 |
| II-5/m3/v3 | carrying capacity at t≈50 | Fig II-5, p.31 255 | 229.5–280.5 | 248.6 [233.2–269.4] | pass | 252.9 [222.7–273] | pass | 4.306 |
| II-5/m3/v4.5 | carrying capacity at t≈50 | Fig II-5, p.31 260 | 234–286 | 262.5 [245.9–277.9] | pass | 266 [238.2–284.2] | pass | 3.488 |
| II-5/m3/v5.5 | carrying capacity at t≈50 | Fig II-5, p.31 260 | 234–286 | 267.3 [253.8–284.6] | pass | 271.6 [244.3–285.9] | pass | 4.25 |
| II-5/m3/v6.5 | carrying capacity at t≈50 | Fig II-5, p.31 287 | 258.3–315.7 | 271.2 [257.7–287.7] | pass | 275.4 [246.1–293.4] | pass | 4.113 |
| II-5/m3/v8 | carrying capacity at t≈50 | Fig II-5, p.31 280 | 252–308 | 274.9 [261.1–290.7] | pass | 280.8 [255.2–300.1] | pass | 5.819 |
| II-5/m3/v10.5 | carrying capacity at t≈50 | Fig II-5, p.31 287 | 258.3–315.7 | 280.6 [264.4–297.2] | pass | 285 [261.8–304.4] | pass | 4.431 |

### Status changes

None.

## Chapter III

Python: 11 pass, 5 near, 9 fail, 0 not run.  
GPU: 14 pass, 5 near, 6 fail, 0 not run.

| Experiment | Target | Book | Band | Python mean [min–max] | Python | GPU mean [min–max] | GPU | GPU − Python |
|---|---|---|---|---|---|---|---|---|
| III-1 | steady population | Fig III-1, p.58 500 | 400–600 | 554.8 [508.6–608.9] | pass | 560.8 [468.8–642] | pass | 6.004 |
| III-1 | small fluctuations | p.57 0.1 | 0–0.1 | 0.1099 [0.08494–0.1329] | near | 0.1062 [0.08174–0.1225] | near | -0.003712 |
| III-1 | mean vision at t≈900 | Fig III-2, p.63 5.3 | 4.8–5.8 | 5.57 [5.342–5.809] | pass | 5.648 [5.477–5.977] | pass | 0.07829 |
| III-1 | mean metabolism, t=300–900 | Fig III-2, p.63 1 | 0.9–1.15 | 1 [1–1] | pass | 1 [1–1] | pass | 2.8e-05 |
| III-3 | oscillation period | p.64 200 | 150–250 | 392.9 [257–595] | fail | 266.1 [211.5–315.5] | near | -126.8 |
| III-3 | population floor | p.64 250 | 200–350 | 201 [102–286] | pass | 265.6 [245–281] | pass | 64.6 |
| III-3 | agents that ever lived | p.64 fn 10 1.25e+04 | 1e+04–1.5e+04 | 9934 [6203–1.168e+04] | near | 1.166e+04 [9804–1.373e+04] | pass | 1727 |
| III-4 | oscillation period | p.65 125 | 100–150 | 104 [97–112.5] | pass | 111 [106–114] | pass | 7 |
| III-4 | oscillation range | Fig III-4, p.65 1000 | 600–1400 | 598.4 [231–843] | near | 714.6 [277–937] | pass | 116.2 |
| III-5 | extinction frequency (proxy) | Fig III-5, p.66 — | 0.5–1 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| III-7 | Gini with inheritance | p.67 0.743 | 0.65–0.85 | 0.3116 [0.2764–0.3589] | fail | 0.2936 [0.2801–0.3244] | fail | -0.01795 |
| III-7 | mean vision at t≈900 | Fig III-7, p.68 4.3 | 3.9–4.7 | 5.368 [5.006–5.681] | fail | 4.997 [4.726–5.258] | near | -0.3707 |
| III-8 | each side culturally pure (proxy) | p.74 — | 0.8–1 | 0.4 [0–1] | fail | 0.8 [0–1] | pass | 0.4 |
| III-8 | time until every side is pure | p.74 2700 | 1350–5400 | — [—–—] | fail | — [—–—] | fail | — |
| III-8 | best-friend closeness | Anim III-8, p.80 0.91 | 0.8–1 | 0.9819 [0.9791–0.9857] | pass | 0.978 [0.9688–0.9876] | pass | -0.003897 |
| III-9 | one of the three patterns (proxy) | p.83 — | 0.8–1 | 1 [1–1] | pass | 1 [1–1] | pass | 0 |
| III-11 | both tribes persist (proxy) | Anim III-11, p.86 — | 0.8–1 | 1 [1–1] | pass | 1 [1–1] | pass | 0 |
| III-12 | Blue wave advances NE (proxy) | Anim III-12, p.88 — | 10–60 | 8.122 [7.918–8.245] | near | 8.151 [7.921–8.353] | near | 0.0294 |
| III-12 | Red wave advances SW (proxy) | Anim III-12, p.88 — | -60–-10 | -4.652 [-5.752–-3.575] | fail | -4.63 [-5.444–-3.328] | fail | 0.02129 |
| III-13 | combat suppresses Blue's wave (proxy) | Anim III-13, p.89 — | -5–5 | 9.62 [9.024–10.73] | fail | 9.703 [8.693–10.81] | fail | 0.08288 |
| III-14 | no runaway hegemony (proxy) | p.90 — | 0.5–1 | 0.5 [0–1] | pass | 0.4 [0–1] | near | -0.1 |
| III-15 | Red and Blue on opposite mountains | p.92 fn 32 0.45 | 0.3–0.5 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| III-15 | Red dominates both | p.92 fn 32 0.25 | 0.1–0.4 | 0.45 [0–1] | near | 0.4 [0–1] | pass | -0.05 |
| III-15 | Blue dominates both | p.92 fn 32 0.25 | 0.1–0.4 | 0.4 [0–1] | pass | 0.35 [0–1] | pass | -0.05 |
| III-15 | extinction (small frequency) | p.92 fn 32 — | 0–0.15 | 0.05 [0–1] | pass | 0 [0–0] | pass | -0.05 |

### Status changes

- III-3 oscillation period: Python fail → GPU near (Python 392.9, GPU 266.1, band 150–250)
- III-3 agents that ever lived: Python near → GPU pass (Python 9934, GPU 1.166e+04, band 1e+04–1.5e+04)
- III-4 oscillation range: Python near → GPU pass (Python 598.4, GPU 714.6, band 600–1400)
- III-7 mean vision at t≈900: Python fail → GPU near (Python 5.368, GPU 4.997, band 3.9–4.7)
- III-8 each side culturally pure: Python fail → GPU pass (Python 0.4, GPU 0.8, band 0.8–1)
- III-14 no runaway hegemony: Python pass → GPU near (Python 0.5, GPU 0.4, band 0.5–1)
- III-15 Red dominates both: Python near → GPU pass (Python 0.45, GPU 0.4, band 0.1–0.4)

## Chapter IV

Python: 28 pass, 9 near, 14 fail, 0 not run.  
GPU: 25 pass, 10 near, 16 fail, 0 not run.

| Experiment | Target | Book | Band | Python mean [min–max] | Python | GPU mean [min–max] | GPU | GPU − Python |
|---|---|---|---|---|---|---|---|---|
| IV-3 | mean price (ln p) | Fig IV-3, p.109 0 | -0.1–0.1 | 0.005596 [-0.04266–0.1004] | pass | -0.004754 [-0.02984–0.03873] | pass | -0.01035 |
| IV-3 | price dispersion at t≈1000 | Fig IV-5, p.110 0.05 | 0–0.1 | 0.04685 [0.02442–0.08003] | pass | 0.03355 [0.01258–0.053] | pass | -0.01329 |
| IV-3 | trades per period | p.109 150 | 100–200 | 34.09 [23.97–55.06] | fail | 29.25 [20.76–37.69] | fail | -4.84 |
| IV-6/trade/v1 | carrying capacity | Fig IV-6, p.112 100 | 90–110 | 78.94 [62–87.37] | fail | 76.34 [64.08–84.08] | fail | -2.602 |
| IV-6/trade/v2 | carrying capacity | Fig IV-6, p.112 128 | 115.2–140.8 | 97.02 [81.16–128.2] | fail | 99.78 [84–110] | fail | 2.769 |
| IV-6/trade/v3 | carrying capacity | Fig IV-6, p.112 158 | 142.2–173.8 | 116.2 [103–141.8] | fail | 118.3 [100–132] | fail | 2.118 |
| IV-6/trade/v6 | carrying capacity | Fig IV-6, p.112 173 | 155.7–190.3 | 133.2 [120–161.4] | fail | 136.8 [119–151.2] | fail | 3.529 |
| IV-6/trade/v10 | carrying capacity | Fig IV-6, p.112 185 | 166.5–203.5 | 140.5 [126–169] | fail | 143.2 [126–156] | fail | 2.737 |
| IV-6/notrade/v1 | carrying capacity | Fig IV-6, p.112 82 | 73.8–90.2 | 60.34 [50–68.2] | fail | 57.94 [47–71] | fail | -2.402 |
| IV-6/notrade/v2 | carrying capacity | Fig IV-6, p.112 90 | 81–99 | 76.47 [65–93] | near | 74.67 [58.67–85.31] | near | -1.796 |
| IV-6/notrade/v3 | carrying capacity | Fig IV-6, p.112 120 | 108–132 | 95.09 [75–111] | fail | 94.47 [81.76–107] | fail | -0.6176 |
| IV-6/notrade/v6 | carrying capacity | Fig IV-6, p.112 157 | 141.3–172.7 | 119.5 [106.3–139] | fail | 120.9 [104.9–137.1] | fail | 1.365 |
| IV-6/notrade/v10 | carrying capacity | Fig IV-6, p.112 177 | 159.3–194.7 | 127.1 [113.7–146.3] | fail | 129.5 [111–140] | fail | 2.482 |
| IV-6/trade/v1 | carrying capacity at t≈50 | Fig IV-6, p.112 100 | 90–110 | 118.7 [100.5–127.9] | near | 116.3 [101.4–132.7] | near | -2.413 |
| IV-6/trade/v2 | carrying capacity at t≈50 | Fig IV-6, p.112 128 | 115.2–140.8 | 136.7 [120.2–175.2] | pass | 143.3 [129.9–151.8] | near | 6.588 |
| IV-6/trade/v3 | carrying capacity at t≈50 | Fig IV-6, p.112 158 | 142.2–173.8 | 161.2 [136.5–192.7] | pass | 165.8 [152–178] | pass | 4.625 |
| IV-6/trade/v6 | carrying capacity at t≈50 | Fig IV-6, p.112 173 | 155.7–190.3 | 174.5 [158.1–198.9] | pass | 180.7 [165.3–192.6] | pass | 6.169 |
| IV-6/trade/v10 | carrying capacity at t≈50 | Fig IV-6, p.112 185 | 166.5–203.5 | 180 [166.2–204.8] | pass | 186.2 [171.4–201.1] | pass | 6.212 |
| IV-6/notrade/v1 | carrying capacity at t≈50 | Fig IV-6, p.112 82 | 73.8–90.2 | 81.74 [71.25–90.19] | pass | 81.46 [70.38–92.56] | pass | -0.2812 |
| IV-6/notrade/v2 | carrying capacity at t≈50 | Fig IV-6, p.112 90 | 81–99 | 97.64 [82.12–116.3] | pass | 100.2 [83–122.2] | near | 2.537 |
| IV-6/notrade/v3 | carrying capacity at t≈50 | Fig IV-6, p.112 120 | 108–132 | 122.9 [102.6–144.4] | pass | 126.8 [112.6–143.5] | pass | 3.875 |
| IV-6/notrade/v6 | carrying capacity at t≈50 | Fig IV-6, p.112 157 | 141.3–172.7 | 152.8 [136.1–177.2] | pass | 156.5 [142.3–169.9] | pass | 3.706 |
| IV-6/notrade/v10 | carrying capacity at t≈50 | Fig IV-6, p.112 177 | 159.3–194.7 | 164 [142.1–193.8] | pass | 167.8 [151.9–183.5] | pass | 3.838 |
| IV-7 | mean price, vision 1 (ln p) | p.117 0 | -0.15–0.15 | -0.03075 [-0.2105–0.0844] | pass | -0.1092 [-0.188–-0.03175] | pass | -0.07846 |
| IV-7 | dispersion stays high | Fig IV-8, p.118 0.3 | 0.2–0.45 | 0.1553 [0.1133–0.1733] | near | 0.1691 [0.1498–0.208] | near | 0.01376 |
| IV-9 | dispersion with vision 1-15 | Fig IV-9, p.119 0.03 | 0–0.08 | 0.01402 [0.009624–0.01882] | pass | 0.01318 [0.007918–0.01641] | pass | -0.000845 |
| IV-12/a80 | dispersion, lifespan 60-100 | Figs IV-10, IV-12 0.5 | 0.4–0.6 | 0.454 [0.4351–0.4707] | pass | 0.448 [0.4412–0.4611] | pass | -0.005957 |
| IV-12/a300 | dispersion, lifespan 280-320 | Fig IV-12 0.3 | 0.22–0.38 | 0.2984 [0.2743–0.3285] | pass | 0.2957 [0.271–0.3084] | pass | -0.00266 |
| IV-12/a550 | dispersion, lifespan 530-570 | Fig IV-12 0.2 | 0.12–0.28 | 0.2183 [0.2002–0.239] | pass | 0.2072 [0.1952–0.2127] | pass | -0.01106 |
| IV-12/a980 | dispersion, lifespan 960-1000 | Figs IV-11, IV-12 0.15 | 0.08–0.22 | 0.1098 [0.09138–0.1271] | pass | 0.1076 [0.07672–0.1257] | pass | -0.002125 |
| IV-13/trade/v1.5 | Gini with trade | Fig IV-13, p.123 0.41 | 0.36–0.46 | 0.358 [0.352–0.3649] | near | 0.3555 [0.35–0.3654] | near | -0.002511 |
| IV-13/trade/v3.5 | Gini with trade | Fig IV-13, p.123 0.42 | 0.37–0.47 | 0.3617 [0.348–0.3667] | near | 0.3627 [0.355–0.3702] | near | 0.0009806 |
| IV-13/trade/v5.5 | Gini with trade | Fig IV-13, p.123 0.44 | 0.39–0.49 | 0.3677 [0.3605–0.3761] | near | 0.3639 [0.3565–0.3719] | near | -0.003746 |
| IV-13/trade/v10 | Gini with trade | Fig IV-13, p.123 0.37 | 0.32–0.42 | 0.3687 [0.3638–0.3784] | pass | 0.3695 [0.3659–0.3732] | pass | 0.0007785 |
| IV-13/trade/v14.5 | Gini with trade | Fig IV-13, p.123 0.38 | 0.33–0.43 | 0.3704 [0.3638–0.375] | pass | 0.3719 [0.3653–0.3786] | pass | 0.001524 |
| IV-13/notrade/v1.5 | Gini without trade | Fig IV-13, p.123 0.43 | 0.38–0.48 | 0.2996 [0.2896–0.3033] | fail | 0.2974 [0.2941–0.2994] | fail | -0.002184 |
| IV-13/notrade/v3.5 | Gini without trade | Fig IV-13, p.123 0.39 | 0.34–0.44 | 0.31 [0.3049–0.3177] | near | 0.3098 [0.305–0.316] | near | -0.000199 |
| IV-13/notrade/v5.5 | Gini without trade | Fig IV-13, p.123 0.34 | 0.29–0.39 | 0.3207 [0.3169–0.3274] | pass | 0.3194 [0.3112–0.3257] | pass | -0.001336 |
| IV-13/notrade/v10 | Gini without trade | Fig IV-13, p.123 0.33 | 0.28–0.38 | 0.3261 [0.3191–0.3362] | pass | 0.3271 [0.3211–0.3383] | pass | 0.001084 |
| IV-13/notrade/v14.5 | Gini without trade | Fig IV-13, p.123 0.31 | 0.26–0.36 | 0.3335 [0.3218–0.3436] | pass | 0.3278 [0.3215–0.3353] | pass | -0.005703 |
| IV-14 | dispersion with S | Fig IV-14, p.124 0.37 | 0.28–0.48 | 0.3775 [0.284–0.5379] | pass | 0.3342 [0.325–0.3434] | fail | -0.04332 |
| IV-15 | dispersion, cultural preferences | Fig IV-16, p.126 0.45 | 0.3–0.6 | 0.1832 [0.1432–0.2285] | fail | 0.1842 [0.173–0.1921] | fail | 0.001062 |
| IV-15 | trades per period | p.125 1000 | 500–1500 | 266.8 [145.2–354.7] | fail | 275.5 [236.4–352.7] | fail | 8.695 |
| IV-17 | dispersion with S and K | Fig IV-17, p.127 0.45 | 0.35–0.55 | 0.2705 [0.1061–0.3905] | near | 0.3471 [0.3122–0.3955] | near | 0.07661 |
| IV-A3 | price before pollution (ln p) | Anim IV-3, p.128 0 | -0.2–0.2 | 0.02095 [-0.06898–0.1112] | pass | 0.01516 [-0.08709–0.09367] | pass | -0.005783 |
| IV-A3 | sugar price spike (proxy) | Anim IV-3 3.5 | 2–6 | 2.332 [1.782–2.887] | pass | 2.207 [1.58–3.639] | pass | -0.1255 |
| IV-A3 | recovery by t≈300 (ln p) | Anim IV-3, p.129 0 | -0.25–0.25 | 0.5952 [0.04745–0.9893] | fail | 0.5799 [0.1036–1.023] | fail | -0.01525 |
| IV-18 | long-run mean foresight | Fig IV-18, p.130 4.9 | 4.25–5.5 | 5.595 [4.321–6.241] | near | 5.848 [5.026–6.67] | fail | 0.2523 |
| IV-A5 | active loans (proxy) | Anim IV-5, p.134 187 | 50–400 | 136.6 [120.2–151] | pass | 132.2 [113.4–148.4] | pass | -4.412 |
| IV-A5 | agents both lending and borrowing (proxy) | Anim IV-5 21 | 5–100 | 22.14 [19.8–24.61] | pass | 21.34 [17.26–24.58] | pass | -0.7934 |
| IV-A5 | hierarchy levels (proxy) | p.133 5 | 3–8 | 6.6 [6–8] | pass | 6.2 [5–7] | pass | -0.4 |

### Status changes

- IV-6/trade/v2 carrying capacity at t≈50: Python pass → GPU near (Python 136.7, GPU 143.3, band 115.2–140.8)
- IV-6/notrade/v2 carrying capacity at t≈50: Python pass → GPU near (Python 97.64, GPU 100.2, band 81–99)
- IV-14 dispersion with S: Python pass → GPU fail (Python 0.3775, GPU 0.3342, band 0.28–0.48)
- IV-18 long-run mean foresight: Python near → GPU fail (Python 5.595, GPU 5.848, band 4.25–5.5)

## Chapter V

Python: 2 pass, 0 near, 4 fail, 0 not run.  
GPU: 2 pass, 0 near, 4 fail, 0 not run.

| Experiment | Target | Book | Band | Python mean [min–max] | Python | GPU mean [min–max] | GPU | GPU − Python |
|---|---|---|---|---|---|---|---|---|
| V-1 | society rids itself of disease | Anim V-1, p.147 0 | 0–0.01 | 0.005618 [0–0.02127] | pass | 0.001842 [0–0.008707] | pass | -0.003776 |
| V-1 | no disease left circulating | p.147 0 | 0–0.5 | 1 [0–4] | fail | 0.7 [0–3] | fail | -0.3 |
| V-2 | endemic infection persists (proxy) | Anim V-2, p.150 — | 0.2–0.8 | 0.009562 [0–0.01791] | fail | 0.007065 [0–0.01686] | fail | -0.002498 |
| V-2 | average diseases at start | Anim V-3, p.151 3.41 | 2.5–4.5 | 4.378 [3.518–5.728] | pass | 3.946 [2.515–4.758] | pass | -0.4317 |
| V-2 | endemic average diseases | Anim V-3, p.151 0.86 | 0.6–1.1 | 0.01753 [0–0.03117] | fail | 0.01309 [0–0.0305] | fail | -0.004437 |
| V-2 | spread of diseases per agent | Anim V-3, p.151 1 | 0.8–1.2 | 0.1695 [0–0.238] | fail | 0.1449 [0–0.2383] | fail | -0.02465 |

### Status changes

None.

## Chapter VI

VI-4 to VI-9 (Schelling and Ring World) are skipped by decision, hence not run on the GPU.

Python: 21 pass, 4 near, 13 fail, 0 not run.  
GPU: 4 pass, 5 near, 14 fail, 15 not run.

| Experiment | Target | Book | Band | Python mean [min–max] | Python | GPU mean [min–max] | GPU | GPU − Python |
|---|---|---|---|---|---|---|---|---|
| VI-1 | population at t≈50 | Anim VI-1 fr. 6 155 | 125–185 | 39.67 [31.67–43.33] | fail | 39.4 [28.33–50.5] | fail | -0.2667 |
| VI-1 | Gini of total wealth | Anim VI-1 fr. 5 0.246 | 0.2–0.3 | 0.2767 [0.2328–0.3066] | pass | 0.3372 [0.2789–0.3688] | near | 0.06053 |
| VI-1 | average neighbors | Anim VI-1 fr. 2 0.7 | 0.56–0.84 | 0.3505 [0.3177–0.3864] | fail | 0.3812 [0.3586–0.3967] | fail | 0.03062 |
| VI-1 | average fertility | Anim VI-1 fr. 8 1.3 | 1.04–1.56 | 0.4158 [0.2597–0.5584] | fail | 0.5065 [0.1742–0.9303] | fail | 0.09068 |
| VI-1 | best-friend closeness | Anim VI-1 fr. 10 0.86 | 0.76–0.96 | 0.7495 [0.7084–0.7908] | near | 0.7271 [0.6943–0.7672] | near | -0.02241 |
| VI-1 | friend closeness | Anim VI-1 fr. 10 0.79 | 0.69–0.89 | 0.6435 [0.6027–0.6794] | near | 0.6234 [0.6155–0.6322] | near | -0.02005 |
| VI-1 | mean price (ln p) | Anim VI-1 fr. 11 0 | -0.2–0.2 | -0.02647 [-0.1514–0.06529] | pass | 0.02573 [-0.08497–0.1613] | pass | 0.0522 |
| VI-1 | price dispersion | Anim VI-1 fr. 12 0.35 | 0.28–0.42 | 0.3516 [0.3178–0.3898] | pass | 0.3459 [0.3057–0.4292] | pass | -0.005712 |
| VI-1 | trades per period | Anim VI-1 fr. 13 125 | 100–150 | 15.63 [11.45–19.76] | fail | 14.41 [6.93–26.06] | fail | -1.22 |
| VI-1 | active loans | Anim VI-1 fr. 15-16 215 | 108–322 | 1.152 [0–3.714] | fail | 4.543 [0–21.43] | fail | 3.39 |
| VI-1 | agents both lending and borrowing | Anim VI-1 fr. 15-16 37 | 18–56 | 0.1333 [0–0.4762] | fail | 0.8762 [0–4.381] | fail | 0.7429 |
| VI-1 | infected fraction dips | Anim VI-1 fr. 17 0.6 | 0.5–0.7 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| VI-1 | infected fraction recovers | Anim VI-1 fr. 17 0.85 | 0.75–0.95 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| VI-1 | average diseases | Anim VI-1 fr. 18 2.26 | 1.81–2.71 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| VI-1 | spread of diseases per agent | Anim VI-1 fr. 18 1.47 | 1.18–1.76 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| VI-2 | crash by t≈20 | Anim VI-2, p.160 130 | 104–156 | 217.3 [182.4–245.6] | fail | 223.9 [211.8–241.2] | fail | 6.66 |
| VI-2 | extinction frequency (proxy) | Anim VI-2, p.159 — | 0.5–1 | 0 [0–0] | fail | 0 [0–0] | fail | 0 |
| VI-3 | early decline as without trade | p.159 1 | 0.8–1.25 | 1.114 [1.011–1.224] | pass | 1.145 [1.121–1.156] | pass | 0.03085 |
| VI-3 | near-extinction minimum | Anim VI-3, p.161 65 | 52–78 | 66.2 [29–82] | pass | 72 [52–90] | pass | 5.8 |
| VI-3 | first peak | Anim VI-3, p.161 1190 | 952–1428 | 831.2 [321–985] | near | 636.2 [304–1023] | fail | -195 |
| VI-3 | oscillation floor | p.159 700 | 560–840 | 678.2 [177–832] | pass | 508.4 [238–866] | near | -169.8 |
| VI-3 | oscillation ceiling | Anim VI-3, p.161 1200 | 960–1440 | 960 [821–1021] | pass | 859.4 [327–1051] | near | -100.6 |
| VI-3 | oscillation period | p.159 115 | 92–138 | 221 [165.5–274.5] | fail | 222.2 [190–235] | fail | 1.2 |
| VI-4 | equilibrium: nobody moves | p.166 0 | 0–0 | 0 [0–0] | pass | not run | — | — |
| VI-4 | more segregated than the start (proxy) | Anim VI-4, p.166 — | 1.05–2 | 1.249 [1.213–1.291] | pass | not run | — | — |
| VI-5 | never settles (proxy) | p.166 — | 1–2000 | 3.333 [3.02–3.574] | pass | not run | — | — |
| VI-5 | segregation comparable (proxy) | p.166 — | 0.9–1.1 | 1.199 [1.157–1.232] | near | not run | — | — |
| VI-6 | far higher segregation (proxy) | p.170 — | 1.2–2 | 1.253 [1.238–1.266] | pass | not run | — | — |
| VI-7 | high segregation endures (proxy) | p.170 — | 0.9–1.1 | 0.9763 [0.9646–0.9872] | pass | not run | — | — |
| VI-8 | agents cluster into groups (proxy) | p.172 — | 2–20 | 3.12 [2.255–4.005] | pass | not run | — | — |
| VI-8 | slow agents are absorbed (proxy) | p.172 — | 0.8–1 | 0.9547 [0.9418–0.9668] | pass | not run | — | — |
| VI-8 | groups outpace loners (proxy) | p.172 — | 1.5–40 | 6.267 [5.902–6.764] | pass | not run | — | — |
| VI-8 | groups of comparable size (proxy) | p.172 — | 0–0.5 | 0.3646 [0.288–0.4894] | pass | not run | — | — |
| VI-8 | size bounded by the most nearsighted (proxy) | p.175 — | 0.9–1 | 1 [1–1] | pass | not run | — | — |
| VI-9 | megagroup breaks up (proxy) | p.174 — | 2–30 | 10.21 [9.774–10.67] | pass | not run | — | — |
| VI-9 | into several groups (proxy) | p.174 — | 2–20 | 5.676 [5.226–6.09] | pass | not run | — | — |
| VI-9 | like-sized cliques (proxy) | p.174 — | 0–0.5 | 0.4 [0.3318–0.4851] | pass | not run | — | — |
| VI-9 | size bounded by the most nearsighted (proxy) | p.175 — | 0.9–1 | 1 [1–1] | pass | not run | — | — |

### Status changes

- VI-1 Gini of total wealth: Python pass → GPU near (Python 0.2767, GPU 0.3372, band 0.2–0.3)
- VI-3 first peak: Python near → GPU fail (Python 831.2, GPU 636.2, band 952–1428)
- VI-3 oscillation floor: Python pass → GPU near (Python 678.2, GPU 508.4, band 560–840)
- VI-3 oscillation ceiling: Python pass → GPU near (Python 960, GPU 859.4, band 960–1440)
