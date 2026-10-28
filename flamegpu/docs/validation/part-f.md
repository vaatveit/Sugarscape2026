# Part F: everything together (2026-10-28)

Part F of the [full-parity design](../superpowers/specs/2026-10-25-gpu-full-parity-design.md)
([plan](../superpowers/plans/2026-10-27-gpu-parity-part-f.md)):
- every experiment at regular size against Python;
- a sample of the xl registry against Python and Julia;
- the book targets;
- the speed tables.

Part E, the Schelling and Ring World models (VI-4 to VI-9), is skipped by the user's decision (2026-10-27: "I am not
interested in the Schelling and Ring World models"). `bridge.gpu_run` names them as skipped and runs nothing for them.

## What ran

All runs were on an RTX 4080 with nothing else on the GPU.

| Run | Program | Seeds | Jobs | Wall time |
|---|---|---|---|---|
| Regular size, all 135 experiments | `build\` (seatbelts on) | registered | 4 | 6 h 21 min |
| Timing, all 135 | `build-fast\` | seed 0 | 1 | 21 min |
| xl sample, 15 experiments | `build-fast\` | registered | 1 | 3 h 30 min |

**Commands,** from `flamegpu\`, into the main checkout's `flamegpu\` folders:
- **Regular:** `bridge.gpu_run TEST-tiny II III IV V VI VAR --jobs 4 --resume`, into `results-gpu`.
- **Timing:** the same ids with `--seeds 1 --jobs 1 --exe build-fast\bin\Release\sugarscape_gpu.exe`, into
  `results-gpu-fast`.
- **xl:** `bridge.gpu_run <ids> --xl --jobs 1 --exe build-fast\...`, into `results-gpu-xl`. Agreement and timing
  for xl both come from this one run. `test_fast_build_same_output` pins that the fast build writes the seatbelts
  build's bytes.

**Inputs:**
- **Python:** the main checkout's `results\` and `results-xl\`, every fingerprint current.
- **Julia:** `results-julia\`, and `results-julia-xl\` for the ten xl experiments Python has no results for.

**The xl sample** is the 17 experiments of the plan, less two:
- 7 are compared against Python: II-4, II-4-gini, II-6, II-7, II-8, IV-A3, VI-1.
- 10 are compared against Julia: III-1, III-7, III-8, III-9, III-11, IV-3, IV-6/trade/v6, VI-3, IV-A5, V-2.
- Combat III-9 and III-11 were left out, by the user's choice. They are projected at 16.5 h and 6.3 h, against an
  8 h budget. The projection is five xl periods of seed 0, scaled to the registered seeds and periods.
- The other 15 were projected at 1.4 h and took 3 h 30 min, because populations grow after the first periods.

## Agreement at regular size

Command: `bridge.agreement_report TEST-tiny II III IV V VI VAR --timing <results-gpu-fast> --julia <results-julia>`.
The rule is Julia's: a Welch test per experiment, metric and quarter, and Fisher's exact test on extinction, all
corrected together (Benjamini–Hochberg, q = 0.01). The report is [agreement-part-f.md](agreement-part-f.md).

**0 of 8,172 tested windows were flagged.**
- **Below p 0.01, unflagged:** 58 windows, where 8,172 tests with no difference give about 82.
  - 17 of them are VAR-c1c3fit/VI-3's, the same p-values as Part C's.
  - They are the design's turn semantics, reproduced by the semantics harness
    ([chapter4-part-c.md](chapter4-part-c.md)).
- **Untestable:** 238 windows had fewer than two seed values on a side. They are mostly windows after a population or
  a vision group died out.
- **Not run:** VI-4 to VI-9, skipped by decision.
- **Stale fingerprints:** none.

## Book targets

`bridge.gpu_report --chapter X` for II to VI, against the main checkout's `results\`. The five chapter reports and
every status change are in [targets-part-f.md](targets-part-f.md).

| Chapter | Python | GPU |
|---|---|---|
| II | 37 pass, 9 near, 3 fail | 37 pass, 9 near, 3 fail |
| III | 11 pass, 5 near, 9 fail | 14 pass, 5 near, 6 fail |
| IV | 28 pass, 9 near, 14 fail | 25 pass, 10 near, 16 fail |
| V | 2 pass, 0 near, 4 fail | 2 pass, 0 near, 4 fail |
| VI | 21 pass, 4 near, 13 fail | 4 pass, 5 near, 14 fail, 15 not run |

VI's 15 not run are VI-4 to VI-9.

**Fifteen statuses change.** Each was already met in Parts A to D, with the same GPU and Python values: the GPU is
deterministic per seed, and Part F changed nothing on their paths.
- **Seed-level p:** every change has p 0.055 or more, except VI-1's Gini at 5 seeds (0.021). With 20 seeds a side
  that one has p 0.59.
- **Direction:** six move toward the book and nine away. Each is noise near a band's edge, or which seeds of a
  bistable run survive (IV-14).

Chapter II now matches Python target for target. Phase 1's one change, II-5/m3/v8's carrying capacity (the GPU at
251.5 against a band from 252), is a pass on both sides: the GPU at 254.8, Python at 252.3.

## xl

### Against Python

[agreement-part-f-xl-python.md](agreement-part-f-xl-python.md): **0 of 436 tested windows flagged**, for the seven
experiments Python has at xl.

### Against Julia

[agreement-part-f-xl-julia.md](agreement-part-f-xl-julia.md): **6 of 523 tested windows flagged**, for the eight
experiments run. III-9 and III-11 are listed as not run.

**Julia's results had to be re-run first.**
- The first comparison flagged 234 windows, in all eight experiments.
- **The cause:** Julia's xl results for these ten dated from 2026-10-24, before Python's centred look (80f4630,
  2026-10-26). The GPU and Julia's current code both use the centred look.
- **Why the check missed it:** Python's fingerprint doesn't record the look rule, so the old results read as
  current. Julia's README said so; the plan's currency check went by fingerprint only.
- **The control:** against the seven experiments Julia re-ran after the change, the GPU flags 0 of 436 windows.
- **The re-run:** Julia re-ran all ten with its current code (2026-10-28, one job, GPU idle, 2 h 32 min).

**The six remaining flags** are small shifts in two experiments, each with the GPU above Julia:

| Experiment | Metric | Quarters | Shift |
|---|---|---|---|
| III-7 | moved | 1 | +1.0% |
| VI-3 | moved | 3, 4 | +0.5% |
| VI-3 | price_sd | 2 | +1.3% |
| VI-3 | sugar_traded | 3, 4 | +1.1% |

Populations agree (|t| ≤ 1.6). Per agent, the GPU's agents move slightly more often, and in VI-3 a little more sugar
changes hands per trade. Seed-to-seed spread shrinks with 40,000 to 150,000 agents, so a 1% shift is many seed SDs
at xl, where it would be noise at regular size.

**They are the design's turn semantics** (the three differences in the README, design section 8). The test was 60
seeds each of III-7 and VI-3 at regular size on four versions:
- the GPU (`build-fast\`);
- Python;
- Julia;
- the semantics harness: Python's rules with the GPU's turns (`bridge.semantics_harness --seeds 60`).

The pairings were scored by the same agreement rule, over 131 windows. The reports and commands are in
[part-f-60-seeds/](part-f-60-seeds/README.md).

| Pairing | Flagged | Which |
|---|---|---|
| Julia against Python | 0 | |
| Harness against Python | 4 | III-7: moved Q4 (+12%), mean_neighbors Q3–Q4 (−0.5% to −0.9%), on_peak_fraction Q2 |
| GPU against Python | 2 | III-7: mean_neighbors Q4 and on_peak_fraction Q2 |
| GPU against Julia | 2 | the same two |
| GPU against harness | 0 | |

Agents that changed site, per agent, in III-7's last quarter:

| Python | Julia | GPU | Harness |
|---|---|---|---|
| 0.0528 | 0.0536 | 0.0567 | 0.0599 |

In VI-3's first quarter, the harness and the GPU are both 0.9% above Python (t 1.8), and Julia 0.2% below.

- **III-7: shown directly.** The turns move more agents and leave fewer on the peaks.
  - The GPU's shift goes the same way and is bounded by the harness's: 0 flags against the harness.
  - The GPU's moves sit between Python's and the harness's, so against Python only two of the harness's four
    flags reach significance.
- **VI-3: consistent, not proven.** At regular size VI-3 flags nothing in any pairing. Its moves-per-agent lean is
  the harness's, and Part C's VAR-c1c3fit/VI-3 trade shift was the harness's too. Its extra sugar per trade is not
  resolved at regular size.
- **The direct test was not run:** a harness run of VI-3 at xl, about 5 h of Python for 5 seeds.

## Speed (development timings)

- **GPU:** steps per period, seed 0 of each experiment, alone on `build-fast\` (plan ruling F3).
- **Python and Julia:** their saved timings, means over their seeds, one job each.
- **Waves:** the turns' waves per period from the GPU's timing JSON. "none" means the experiment runs without the
  turns (Chapter II's movement rounds only).
- **Ratio:** a ratio below 1 means the GPU is faster.
- **Caveat:** where seed 0 dies out early the GPU row times a mostly empty world, so those rows are not like for
  like. Examples are IV-14, VI-1, VAR-inttrade/IV-17 and the VI-3 variants under 1 ms.

### Regular size, all 135

| Experiment | GPU ms | Waves | Python ms | Julia ms | GPU / Python | GPU / Julia |
|---|---|---|---|---|---|---|
| TEST-tiny | 1.02 | none | 0.251 | 0.00506 | 4.08 | 202 |
| II-1 | 0.45 | none | 3.25 | 0.0539 | 0.139 | 8.36 |
| II-4 | 0.82 | none | 2.89 | 0.0632 | 0.284 | 13.0 |
| II-5/m1/v1 | 0.671 | none | 3.15 | 0.0478 | 0.213 | 14.0 |
| II-5/m1/v2 | 0.793 | none | 4.00 | 0.0777 | 0.198 | 10.2 |
| II-5/m1/v3 | 0.858 | none | 4.83 | 0.108 | 0.178 | 7.94 |
| II-5/m1/v5.5 | 0.991 | none | 6.88 | 0.169 | 0.144 | 5.87 |
| II-5/m1/v10.5 | 1.15 | none | 11.6 | 0.272 | 0.0996 | 4.25 |
| II-5/m2/v1 | 0.645 | none | 2.27 | 0.0333 | 0.284 | 19.3 |
| II-5/m2/v2 | 0.747 | none | 2.99 | 0.0586 | 0.249 | 12.7 |
| II-5/m2/v3 | 0.857 | none | 3.58 | 0.075 | 0.239 | 11.4 |
| II-5/m2/v5.5 | 1.02 | none | 5.00 | 0.114 | 0.205 | 9.03 |
| II-5/m2/v10.5 | 1.24 | none | 8.03 | 0.172 | 0.154 | 7.18 |
| II-5/m3/v1 | 0.677 | none | 2.13 | 0.0237 | 0.318 | 28.6 |
| II-5/m3/v2 | 0.716 | none | 3.06 | 0.0411 | 0.234 | 17.4 |
| II-5/m3/v3 | 0.75 | none | 2.82 | 0.0561 | 0.266 | 13.4 |
| II-5/m3/v4.5 | 0.832 | none | 3.69 | 0.0772 | 0.226 | 10.8 |
| II-5/m3/v5.5 | 0.857 | none | 4.19 | 0.0898 | 0.205 | 9.55 |
| II-5/m3/v6.5 | 0.931 | none | 4.68 | 0.117 | 0.199 | 7.94 |
| II-5/m3/v8 | 1.02 | none | 5.43 | 0.121 | 0.189 | 8.45 |
| II-5/m3/v10.5 | 1.07 | none | 6.80 | 0.147 | 0.157 | 7.24 |
| II-4-gini | 0.978 | none | 3.13 | 0.0682 | 0.312 | 14.3 |
| II-6 | 0.912 | none | 3.27 | 0.0764 | 0.279 | 11.9 |
| II-6-measured | 0.932 | none | 2.54 | 0.06 | 0.367 | 15.5 |
| II-7 | 0.753 | none | 2.31 | 0.0516 | 0.327 | 14.6 |
| II-8 | 0.812 | none | 3.05 | 0.0609 | 0.266 | 13.3 |
| III-1 | 12.8 | 78.2 | 12.6 | 0.4 | 1.01 | 31.9 |
| III-3 | 8.72 | 50.7 | 6.96 | 0.203 | 1.25 | 42.9 |
| III-4 | 26.7 | 171 | 26.6 | 0.729 | 1.00 | 36.6 |
| III-5 | 20.5 | 128 | 23.7 | 0.663 | 0.864 | 30.9 |
| III-7 | 21.8 | 145 | 24.5 | 0.646 | 0.891 | 33.8 |
| III-8 | 4.77 | 32.2 | 4.12 | 0.0701 | 1.16 | 68.1 |
| III-9 | 23.5 | 83.9 | 8.23 | 0.131 | 2.86 | 179 |
| III-11 | 33.8 | 105 | 20.9 | 0.252 | 1.61 | 134 |
| III-12 | 0.982 | none | 5.86 | 0.149 | 0.168 | 6.60 |
| III-13 | 75.2 | 154 | 31.7 | 0.333 | 2.37 | 226 |
| III-14 | 3.10 | 6.25 | 0.78 | 0.00962 | 3.97 | 322 |
| III-15 | 19.6 | 121 | 17.1 | 0.434 | 1.14 | 45.2 |
| IV-3 | 2.38 | 5.14 | 1.78 | 0.118 | 1.33 | 20.1 |
| IV-6/trade/v1 | 2.57 | 4.44 | 1.95 | 0.0803 | 1.31 | 31.9 |
| IV-6/trade/v2 | 2.84 | 6.17 | 2.81 | 0.123 | 1.01 | 23.0 |
| IV-6/trade/v3 | 3.19 | 7.36 | 3.74 | 0.174 | 0.852 | 18.3 |
| IV-6/trade/v6 | 3.89 | 8.42 | 5.85 | 0.283 | 0.664 | 13.7 |
| IV-6/trade/v10 | 4.96 | 8.82 | 8.49 | 0.5 | 0.585 | 9.94 |
| IV-6/notrade/v1 | 0.618 | none | 0.874 | 0.042 | 0.707 | 14.7 |
| IV-6/notrade/v2 | 0.761 | none | 1.45 | 0.0725 | 0.523 | 10.5 |
| IV-6/notrade/v3 | 0.984 | none | 2.33 | 0.115 | 0.423 | 8.56 |
| IV-6/notrade/v6 | 1.76 | none | 4.43 | 0.228 | 0.397 | 7.70 |
| IV-6/notrade/v10 | 2.67 | none | 6.91 | 0.383 | 0.386 | 6.97 |
| IV-7 | 1.82 | 2.90 | 0.917 | 0.0337 | 1.98 | 54.0 |
| IV-9 | 3.12 | 6.38 | 4.04 | 0.192 | 0.772 | 16.3 |
| IV-12/a80 | 3.74 | 7.35 | 5.83 | 0.216 | 0.641 | 17.3 |
| IV-12/a300 | 3.86 | 7.88 | 5.92 | 0.221 | 0.652 | 17.4 |
| IV-12/a550 | 3.97 | 8.06 | 6.03 | 0.248 | 0.659 | 16.0 |
| IV-12/a980 | 3.96 | 8.23 | 5.96 | 0.231 | 0.665 | 17.2 |
| IV-13/trade/v1.5 | 4.75 | 8.45 | 11.1 | 0.368 | 0.427 | 12.9 |
| IV-13/trade/v3.5 | 5.96 | 10.3 | 16.4 | 0.69 | 0.363 | 8.63 |
| IV-13/trade/v5.5 | 6.99 | 11.2 | 28.8 | 0.711 | 0.243 | 9.83 |
| IV-13/trade/v10 | 10.1 | 12.0 | 41.2 | 1.02 | 0.244 | 9.85 |
| IV-13/trade/v14.5 | 12.7 | 12.9 | 47.9 | 1.29 | 0.265 | 9.84 |
| IV-13/notrade/v1.5 | 1.23 | none | 9.97 | 0.201 | 0.123 | 6.10 |
| IV-13/notrade/v3.5 | 2.19 | none | 14.8 | 0.359 | 0.148 | 6.10 |
| IV-13/notrade/v5.5 | 3.44 | none | 17.4 | 0.531 | 0.197 | 6.48 |
| IV-13/notrade/v10 | 6.45 | none | 22.7 | 0.813 | 0.284 | 7.93 |
| IV-13/notrade/v14.5 | 8.50 | none | 27.8 | 1.00 | 0.306 | 8.49 |
| IV-14 | 0.79 | 1.79 | 28.1 | 0.811 | 0.0281 | 0.975 |
| IV-15 | 7.58 | 19.2 | 4.00 | 0.125 | 1.90 | 60.6 |
| IV-17 | 44.7 | 160 | 16.3 | 1.40 | 2.75 | 32.0 |
| IV-A3 | 2.33 | 5.19 | 1.97 | 0.0722 | 1.18 | 32.3 |
| IV-18 | 12.6 | 69.7 | 14.4 | 0.196 | 0.874 | 64.5 |
| IV-A5 | 10.5 | 60.2 | 13.3 | 0.421 | 0.787 | 24.8 |
| V-1 | 2.04 | 7.90 | 3.45 | 0.0655 | 0.592 | 31.2 |
| V-2 | 2.13 | 8.15 | 3.64 | 0.0676 | 0.585 | 31.5 |
| VI-1 | 1.22 | 3.07 | 7.79 | 0.753 | 0.156 | 1.61 |
| VI-2 | 2.75 | 10.9 | 6.52 | 0.194 | 0.421 | 14.2 |
| VI-3 | 22.6 | 80.1 | 32.1 | 1.28 | 0.704 | 17.6 |
| VAR-book/III-1 | 3.44 | 18.0 | 6.27 | 0.163 | 0.549 | 21.2 |
| VAR-book/III-3 | 0.591 | 1.50 | 0.83 | 0.00616 | 0.712 | 96.0 |
| VAR-book/III-4 | 4.73 | 31.8 | 16.8 | 0.461 | 0.282 | 10.3 |
| VAR-book/III-5 | 4.14 | 24.9 | 14.8 | 0.416 | 0.28 | 9.93 |
| VAR-book/VI-2 | 1.56 | 3.69 | 1.90 | 0.08 | 0.825 | 19.6 |
| VAR-book/VI-3 | 0.831 | 1.72 | 10.5 | 0.247 | 0.0793 | 3.36 |
| VAR-share/III-1 | 3.49 | 18.2 | 9.65 | 0.269 | 0.361 | 13.0 |
| VAR-share/III-3 | 2.98 | 14.8 | 1.33 | 0.0174 | 2.24 | 171 |
| VAR-share/III-4 | 4.92 | 32.0 | 28.7 | 0.536 | 0.171 | 9.19 |
| VAR-share/III-5 | 4.23 | 24.2 | 20.1 | 0.559 | 0.211 | 7.56 |
| VAR-share/VI-2 | 2.10 | 5.99 | 1.93 | 0.0947 | 1.09 | 22.2 |
| VAR-share/VI-3 | 0.894 | 1.79 | 11.0 | 0.537 | 0.0812 | 1.67 |
| VAR-c1c3fit/III-1 | 12.1 | 74.4 | 11.4 | 0.44 | 1.06 | 27.6 |
| VAR-c1c3fit/III-3 | 8.33 | 49.5 | 5.73 | 0.235 | 1.45 | 35.5 |
| VAR-c1c3fit/III-4 | 24.6 | 157 | 22.9 | 0.845 | 1.07 | 29.1 |
| VAR-c1c3fit/III-5 | 17.3 | 109 | 19.0 | 0.646 | 0.911 | 26.9 |
| VAR-c1c3fit/VI-2 | 9.88 | 55.8 | 14.5 | 0.637 | 0.68 | 15.5 |
| VAR-c1c3fit/VI-3 | 23.7 | 82.5 | 32.2 | 1.39 | 0.737 | 17.1 |
| VAR-intgift/III-1 | 3.50 | 18.3 | 7.38 | 0.214 | 0.474 | 16.3 |
| VAR-intgift/III-3 | 0.598 | 1.47 | 1.08 | 0.0133 | 0.553 | 45.0 |
| VAR-intgift/III-4 | 4.93 | 33.5 | 35.5 | 0.506 | 0.139 | 9.75 |
| VAR-intgift/III-5 | 2.70 | 14.4 | 26.7 | 0.396 | 0.101 | 6.82 |
| VAR-intgift/VI-2 | 1.69 | 4.04 | 3.32 | 0.0822 | 0.508 | 20.5 |
| VAR-intgift/VI-3 | 0.857 | 1.74 | 18.8 | 0.416 | 0.0456 | 2.06 |
| VAR-intgiftc1/III-1 | 12.7 | 78.2 | 14.2 | 0.402 | 0.894 | 31.5 |
| VAR-intgiftc1/III-3 | 8.73 | 50.7 | 10.4 | 0.227 | 0.839 | 38.5 |
| VAR-intgiftc1/III-4 | 26.7 | 171 | 42.2 | 0.842 | 0.633 | 31.8 |
| VAR-intgiftc1/III-5 | 20.5 | 128 | 30.7 | 0.712 | 0.668 | 28.8 |
| VAR-intgiftc1/VI-2 | 2.76 | 10.9 | 6.91 | 0.195 | 0.4 | 14.1 |
| VAR-intgiftc1/VI-3 | 22.7 | 80.1 | 34.3 | 1.19 | 0.662 | 19.1 |
| VAR-fit83/III-1 | 3.65 | 19.1 | 10.7 | 0.212 | 0.34 | 17.2 |
| VAR-fit83/III-3 | 2.94 | 13.9 | 2.16 | 0.0598 | 1.36 | 49.2 |
| VAR-fit83/III-4 | 4.88 | 32.6 | 31.3 | 0.444 | 0.156 | 11.0 |
| VAR-fit83/III-5 | 4.18 | 24.8 | 28.5 | 0.408 | 0.147 | 10.2 |
| VAR-fit83/VI-2 | 2.23 | 7.08 | 5.62 | 0.0921 | 0.396 | 24.1 |
| VAR-fit83/VI-3 | 9.97 | 19.4 | 16.4 | 0.662 | 0.61 | 15.1 |
| VAR-inttrade/IV-3 | 2.12 | 5.04 | 2.13 | 0.0609 | 0.997 | 34.8 |
| VAR-inttrade/IV-6/trade/v1 | 2.09 | 4.53 | 2.01 | 0.059 | 1.04 | 35.4 |
| VAR-inttrade/IV-6/trade/v2 | 2.43 | 5.92 | 2.89 | 0.0981 | 0.84 | 24.8 |
| VAR-inttrade/IV-6/trade/v3 | 2.91 | 7.11 | 4.18 | 0.134 | 0.697 | 21.8 |
| VAR-inttrade/IV-6/trade/v6 | 3.56 | 8.13 | 6.84 | 0.218 | 0.52 | 16.3 |
| VAR-inttrade/IV-6/trade/v10 | 4.57 | 8.65 | 9.86 | 0.336 | 0.463 | 13.6 |
| VAR-inttrade/IV-7 | 1.57 | 2.84 | 0.829 | 0.0278 | 1.90 | 56.7 |
| VAR-inttrade/IV-9 | 2.95 | 6.14 | 4.00 | 0.149 | 0.739 | 19.8 |
| VAR-inttrade/IV-12/a80 | 3.46 | 6.90 | 6.01 | 0.199 | 0.575 | 17.4 |
| VAR-inttrade/IV-12/a300 | 3.50 | 7.61 | 6.15 | 0.19 | 0.569 | 18.4 |
| VAR-inttrade/IV-12/a550 | 3.43 | 7.75 | 6.08 | 0.205 | 0.564 | 16.7 |
| VAR-inttrade/IV-12/a980 | 3.39 | 7.95 | 6.36 | 0.191 | 0.533 | 17.7 |
| VAR-inttrade/IV-13/trade/v1.5 | 4.29 | 8.20 | 11.3 | 0.274 | 0.381 | 15.6 |
| VAR-inttrade/IV-13/trade/v3.5 | 5.51 | 10.1 | 13.9 | 0.409 | 0.397 | 13.5 |
| VAR-inttrade/IV-13/trade/v5.5 | 6.52 | 10.9 | 16.7 | 0.536 | 0.391 | 12.2 |
| VAR-inttrade/IV-13/trade/v10 | 9.50 | 11.9 | 22.5 | 0.801 | 0.422 | 11.9 |
| VAR-inttrade/IV-13/trade/v14.5 | 11.6 | 12.4 | 31.8 | 1.05 | 0.363 | 11.0 |
| VAR-inttrade/IV-14 | 8.86 | 37.2 | 18.2 | 0.452 | 0.486 | 19.6 |
| VAR-inttrade/IV-15 | 4.45 | 18.8 | 2.97 | 0.0773 | 1.50 | 57.5 |
| VAR-inttrade/IV-17 | 1.04 | 3.12 | 12.9 | 1.06 | 0.0801 | 0.98 |
| VAR-inttrade/IV-A3 | 2.07 | 4.46 | 2.03 | 0.0677 | 1.02 | 30.6 |
| VAR-inttrade/VI-1 | 1.47 | 3.51 | 8.50 | 0.344 | 0.173 | 4.27 |
| VAR-inttrade/VI-3 | 18.1 | 68.3 | 34.3 | 0.976 | 0.528 | 18.6 |

**Against Python, the GPU is faster in 108 of 135** (median ratio 0.51).
- **Where it wins:** experiments with few waves, such as II-1 (0.14) and IV-13/notrade/v1.5 (0.12).
- **Where it loses:** 27 experiments, most of them with many turn waves a period.
  - Examples: III-9 (84 waves, 2.9×), III-13 (154 waves, 2.4×), IV-17 (160 waves, 2.75×).
  - TEST-tiny has a 1 ms floor against Python's 0.25 ms.

**Against Julia, the GPU is slower in 133 of 135** (median ratio 16).
- A few hundred agents can't fill the GPU, so a period costs at least about 0.5 ms of kernel launches and
  synchronisation. II-1 takes 0.45 ms, where Julia takes 0.054 ms.
- Each wave adds launches: III-13's 154 waves cost 75 ms a period, against Julia's 0.33 ms.
- The two ties, IV-14 and VAR-inttrade/IV-17, are seed-0 die-outs.

### xl, the sample

Python's xl timings exist only for its seven experiments. All three programs ran with one job.

| Experiment | GPU ms | Waves | Python ms | Julia ms | GPU / Python | GPU / Julia |
|---|---|---|---|---|---|---|
| II-4 | 1.24 | none | 1,327 | 14.1 | 0.000933 | 0.0881 |
| II-4-gini | 1.55 | none | 1,671 | 12.6 | 0.000929 | 0.123 |
| II-6 | 1.34 | none | 2,072 | 17.1 | 0.000649 | 0.0787 |
| II-7 | 1.07 | none | 1,044 | 10.0 | 0.00102 | 0.106 |
| II-8 | 3.54 | none | 1,351 | 26.5 | 0.00262 | 0.133 |
| IV-A3 | 17.4 | 14.1 | 1,113 | 28.1 | 0.0157 | 0.62 |
| VI-1 | 597 | 1,262 | 16,440 | 323 | 0.0363 | 1.85 |
| III-1 | 302 | 1,400 | — | 110 | — | 2.76 |
| III-7 | 619 | 2,664 | — | 242 | — | 2.55 |
| III-8 | 10.9 | 67.5 | — | 37.4 | — | 0.292 |
| IV-3 | 12.9 | 13.9 | — | 10.3 | — | 1.24 |
| IV-6/trade/v6 | 17.3 | 17.3 | — | 34.6 | — | 0.499 |
| VI-3 | 450 | 1,279 | — | 320 | — | 1.40 |
| IV-A5 | 319 | 1,213 | — | 256 | — | 1.24 |
| V-2 | 6.12 | 17.3 | — | 32.1 | — | 0.191 |

**Against Python, the GPU is faster in all seven.**
- **Chapter II:** 380 to 1,540× faster. The GPU takes 1 to 3.5 ms a period for 40,000 agents, where Python takes 1
  to 2 s.
- **IV-A3:** 64× faster.
- **VI-1:** 28× faster: 0.60 s a period against 16.4 s.

**Against Julia, the GPU is faster in 9 of 15** (median ratio 0.50).
- **Where it wins:** experiments with few or no waves.
  - Chapter II without turns: 7.5 to 13× faster.
  - V-2: 5.2×.
  - III-8: 3.4×.
  - IV-6/trade/v6: 2.0×.
  - IV-A3: 1.6×.
- **Where it loses:** the five experiments with sex, and IV-3.
  - III-1: 2.8× slower.
  - III-7: 2.6× slower.
  - VI-1: 1.85× slower.
  - VI-3: 1.4× slower.
  - IV-A5: 1.24× slower.
  - IV-3: 1.24× slower.
- **Why sex is slow:** with tens of thousands of agents, sex's turns need 1,200 to 2,700 waves a period. Each wave
  is a round of launches, however few turns it holds.
- **IV-3** has 14 waves, but only 5,000 to 20,000 agents.

**The pattern:** the GPU wins where agents act together, and loses where the turns serialise into many waves. A
controlled timing run, on a quiet machine, is the user's to make.

## Julia as a reference

Julia stands in for Python only at xl, where Python has no results for those ten experiments. Julia agrees with
Python ([julia/README.md](../../../julia/README.md)):
- at regular size, 0 flags among 8,146 windows;
- at xl, 0 flags among 436 windows on the seven centred-look experiments.

## In short

- **Regular size:** the GPU agrees with Python everywhere it runs, 0 of 8,172 windows flagged. All 15 book-target
  status changes are noise.
- **xl against Python:** 0 of 436 flagged.
- **xl against Julia:** 6 of 523 flagged. They are small shifts in III-7 and VI-3, the design's own turn semantics,
  shown directly for III-7.
- **Not run:** the Schelling and Ring World models, skipped by decision.
