# Chapter III without combat on the GPU, against Python (2026-10-26)

Part A of the [full-parity design](../superpowers/specs/2026-10-25-gpu-full-parity-design.md): the ordered turns,
sex S with every option, inheritance I at old age, cultural tags and tribal blocks, culture K and friends.

## What ran

- **Experiments, on `build\`** (seatbelts on), registered seeds and steps:
  - III-1, -3, -4, -5, -7, -8, -12 and -15;
  - the reproduction variants VAR-book, VAR-share, VAR-c1c3fit, VAR-intgift, VAR-intgiftc1 and VAR-fit83 of III-1,
    -3, -4 and -5, 24 experiments.
- **Command:** `bridge.gpu_run <id> --jobs 4`. It took 4 h 33 min for all, with four runs sharing the GPU.
- **Python:** the saved results in the main checkout's `results/` (fingerprints current).
- **Not run:** III-9, -11, -13 and -14 (combat, Part B), and the variants of VI-2 and VI-3 (trade, Part C).

## Agreement

`python -m bridge.agreement_report III VAR-book VAR-share VAR-c1c3fit VAR-intgift VAR-intgiftc1 VAR-fit83`
(the Julia rule).

**0 of 1,601 tested windows were flagged.**
- 110 windows were untestable. Nearly all are `north_frac_low_vision` once reproduction has selected out every agent
  of vision 2 or less, as in Python and in the Julia port.
- 15 windows had p < 0.01, where 1,601 tests with no difference give about 16.
- VAR-intgiftc1 is today's default rule S, so its rows repeat III-1, -3, -4 and -5 exactly, on both sides.

**The one pattern among the low p values: III-12's Gini**, about 7% higher on the GPU in the last two quarters
(p 0.0011 and 0.0017). III-12 has tags but no interaction rule, so it runs the Chapter II path from two dense tribal
blocks. With 40 seeds a side (t = 151–200):

| | Gini | Population |
|---|---|---|
| Python, 40 seeds | 0.2758 | 364.4 |
| Python, its registered 5 seeds | 0.2666 (−3.4%) | 361.4 |
| GPU, 40 seeds | 0.2812 (+1.9%, t 2.1) | 370.2 (+1.6%) |
| Python with difference 1 (the semantics harness), 40 seeds | 0.2808 (+1.8%) | 369.5 (+1.4%) |

Most of the 7% was Python's registered seeds sitting low. The rest is the design's difference 1: sites vacated during
a period aren't offered to agents later in the order, which matters most in a crowded start. Python with that one
change reproduces the GPU.

## Book targets

`python -m bridge.gpu_report --chapter III` and `--chapter VAR`:
- **Chapter III:** Python 11 pass, 5 near, 9 fail; GPU 12 pass, 4 near, 5 fail, 4 not run (combat).
- Every status change is a per-seed statistic over 5 seeds (20 for III-15), with a seed-level p (Fisher for outcomes,
  Welch otherwise) of 0.055 or more:

| Target | Python → GPU | Python seeds | GPU seeds | Seed-level p |
|---|---|---|---|---|
| III-3 oscillation period | fail 393 → near 266 | 595, 407, 370, 336, 257 | 212, 268, 229, 307, 316 | 0.087 |
| III-3 agents that ever lived | near 9,934 → pass 11,660 | 10,092 … 11,685 | 9,804 … 13,728 | 0.19 |
| III-4 oscillation range | near 598 → pass 715 | 231 … 843 | 277 … 937 | 0.49 |
| III-7 mean vision at t ≈ 900 | fail 5.37 → near 5.00 | 5.01 … 5.68 | 4.73 … 5.26 | 0.055 |
| III-8 each side culturally pure | fail 0.4 → pass 0.8 | 2 of 5 | 4 of 5 | 0.52 |
| III-15 Red dominates both | near 0.45 → pass 0.40 | 9 of 20 | 8 of 20 | 1.0 |
| VAR-share/III-1 steady population | near 621 → pass 575 | 594 … 651 | 521 … 650 | 0.11 |
| VAR-share/III-4 oscillation period | near 160 → pass 115 | 114 … 338 | 110 … 123 | 0.37 |
| VAR-c1c3fit/III-3 agents that ever lived | near 9,061 → pass 11,150 | 5,552 … 12,742 | 9,772 … 12,532 | 0.23 |

The VAR-intgiftc1 changes repeat III-3's and III-4's (the same configuration). All the changes go the GPU's way, but
none is significant at the seed level, and the time-series test above flags nothing in these experiments.

## Speed (development timings)

Taken with four runs sharing the GPU, on the seatbelts build, and so uncontrolled. Stepping per period:

| Experiment | Waves per period | GPU ms | Python ms |
|---|---|---|---|
| III-1 | 77 | 113 | 12.6 |
| III-3 | 48 | 79 | 7.0 |
| III-4 | 164 | 228 | 26.6 |
| III-5 | 121 | 185 | 23.7 |
| III-7 | 156 | 217 | 24.5 |
| III-8 | 32 | 51 | 4.1 |
| III-12 (no turns) | 0 | 12.7 | 5.9 |
| III-15 | 135 | 222 | 17.1 |

- **The same on an idle GPU** with `build-fast`, 300 periods of seed 0:
  - III-1 took 8.0 ms a period with 52 waves;
  - III-8 took 3.9 ms with 31 waves;
  - about 0.13–0.15 ms a wave, against roughly 2 ms with four runs sharing the GPU.
- **At regular size** the turns' waves cost about as much as Python's whole period. The GPU's case is at xl, below.
  Part F times every experiment on an idle machine.
- **Waves.** III-4 and III-7 need the most, 156–164 a period, since rule S with partners in sight has the widest
  footprints.

## xl smoke run

III-1 at xl (`to_xl`: 500 × 500, 40,000 agents, look stride 10), seed 0, 20 periods on `build-fast`:
- exit 0, with 585 waves and 104 ms per period;
- 40,000 agents at the start, 37,596 at the end.

Python takes about 2.2 s a period here, so the GPU is about 21× faster.
