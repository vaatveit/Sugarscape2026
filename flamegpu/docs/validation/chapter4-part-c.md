# Chapter IV on the GPU, against Python (2026-10-27)

Part C of the [full-parity design](../superpowers/specs/2026-10-25-gpu-full-parity-design.md): spice, welfare movement
with foresight and cultural preferences, trade T with `trade_rounding`, credit L, `pollution_stop` and
`economic_metrics` ([plan](../superpowers/plans/2026-10-26-gpu-parity-part-c.md)).

## What ran

- **Experiments, on `build\`** (seatbelts on), registered seeds and steps: the 69 ids of Part C:
  - all of Chapter IV (34);
  - VI-2 and VI-3;
  - the six reproduction variants of each (`VAR-book`, `-share`, `-c1c3fit`, `-intgift`, `-intgiftc1`, `-fit83`);
  - `VAR-inttrade` on every experiment that trades, but VI-1 (21).
- **Command:** `bridge.gpu_run <id> --jobs 4` for each id, 73 min in all. A build of `build-fast\` shared the machine for
  part of it, so every timing below is uncontrolled.
- **Python:** the saved results in the main checkout's `results\` (fingerprints current).

## Agreement

`python -m bridge.agreement_report <the 69 ids> --python <main checkout>\results` (the Julia rule;
[agreement-part-c.md](agreement-part-c.md)).

**0 of 4,709 tested windows were flagged.** 118 windows were untestable (fewer than two seed values on a side): mostly
the fractions of a vision group that has died out (38), and windows after a population died out. 37 windows had
p < 0.01, where 4,709 tests with no difference give about 47. One experiment holds 17 of them; it and one other show a
shift that is the design's own differences (section 8), not the GPU's:
- **VAR-c1c3fit/VI-3** (17 windows below 0.01): the GPU's mean sugar and spice run about 8% above Python's, with more
  children per agent and fewer agents ever.
  - The semantics harness (Python's own rules with the GPU's turn semantics, 5 seeds) shows the same shift: mean
    sugar 30.13 and mean spice 30.46 in the third quarter, against Python's 27.87 and 28.18 and the GPU's 30.24 and
    30.67.
  - The GPU against the harness: 76 windows, none below p 0.01.
  - The original harness study (`semantics-harness.md`) did not include the reproduction variants.
- **VAR-inttrade/IV-15** (a cluster that grew with seeds): with 30 seeds a side, the third quarter's mean price is
  1.015 on the GPU against Python's 1.191 (p 0.0006; still unflagged among 196 windows).
  - The harness, 30 seeds, gives 1.032 (p 0.0039 against Python).
  - The GPU against the harness: 124 windows, none below p 0.01.

Difference 3 (movement scores sites with the holdings of the start of the period) is the likely cause in both:
it is the only one that spice brings, and both runs move many holdings within a period (cheap children; trade in whole
units with cultural preferences).

## Book targets

`python -m bridge.gpu_report --chapter IV`, then `--chapter VI` and `--chapter VAR`. Each status change, with its
seed-level p (Welch's t-test, or Fisher's exact test for outcomes):

| Target | Python | GPU | p |
|---|---|---|---|
| IV-6/trade/v2 carrying capacity at t≈50 | pass, 136.7 | near, 143.3 | 0.25 |
| IV-6/notrade/v2 carrying capacity at t≈50 | pass, 97.6 | near, 100.2 | 0.60 |
| IV-14 dispersion with S | pass, 0.378 | fail, 0.334 (2 seeds survive) | 0.37 |
| IV-18 long-run mean foresight | near, 5.60 | fail, 5.85 | 0.82 |
| VI-3 first peak (and VAR-intgiftc1/VI-3, the same settings) | near, 831 | fail, 636 | 0.33 |
| VI-3 oscillation floor (and VAR-intgiftc1/VI-3) | pass, 678 | near, 508 | 0.37 |
| VI-3 oscillation ceiling (and VAR-intgiftc1/VI-3) | pass, 960 | near, 859 | 0.51 |
| VAR-book/VI-2 extinction frequency | fail, 0.2 | near, 0.4 | 0.63 |
| VAR-share/VI-2 extinction frequency | near, 0.4 | fail, 0.2 | 0.63 |
| VAR-intgift/VI-2 extinction frequency | pass, 0.5 | fail, 0.3 | 0.65 |
| VAR-c1c3fit/VI-3 oscillation period | fail, 171.5 | near, 148.8 | 0.48 |
| VAR-fit83/VI-3 near-extinction minimum | fail, 36.4 | near, 49.8 | 0.38 |
| VAR-fit83/VI-3 oscillation ceiling | fail, 534 | near, 907 | 0.17 |
| VAR-inttrade/IV-6/trade/v1 carrying capacity | near, 80.2 | fail, 77.8 | 0.47 |
| VAR-inttrade/IV-6/trade/v2 carrying capacity at t≈50 | pass, 140.6 | near, 144.7 | 0.49 |
| VAR-inttrade/IV-9 dispersion with vision 1–15 | pass, 0.074 | near, 0.097 | 0.40 |
| VAR-inttrade/IV-12/a300 dispersion | near, 0.438 | fail, 0.478 | 0.0033 |
| VAR-inttrade/IV-15 dispersion | near, 0.228 | fail, 0.168 | 0.0033 |
| VAR-inttrade/IV-17 dispersion with S and K | near, 0.460 | fail, 0.016 (1 seed survives) | — |
| VAR-inttrade/VI-3 first peak | near, 838 | fail, 710 | 0.36 |
| VAR-inttrade/VI-3 oscillation ceiling | near, 957 | pass, 998 | 0.41 |

- **Most are noise near a band's edge.** With 5 or 10 seeds, p is between 0.17 and 0.82.
- **Extinction decides several.** IV-14, IV-17 and VI-2's variants are bistable: each seed dies out or grows. In
  VAR-inttrade/IV-17, 2 of 5 Python seeds die out against 5 of 5 GPU seeds (Fisher p 0.17); in IV-17 it is 3 of 5
  against 1 of 5. The dispersion targets then rest on the one or two seeds that survive.
- **The two with p ≈ 0.003 were rerun with 30 seeds a side.**
  - VAR-inttrade/IV-12/a300's dispersion: Python 0.449, GPU 0.459, p 0.08. The 5-seed gap was chance.
  - VAR-inttrade/IV-15's dispersion: Python 0.219, GPU 0.187, p 0.015. This is the mean-price shift above, which the
    harness reproduces.

## Waves and speed (development timings)

Stepping per period, seed means from the timing JSON, uncontrolled:

| Experiment | Path | Waves per period | GPU ms | Python ms |
|---|---|---|---|---|
| IV-3 | turns (T) | 5.1 | 23.6 | 1.8 |
| IV-6/trade/v6 | turns (T) | 8.2 | 32.3 | 5.9 |
| IV-6/notrade/v6 | fast path | — | 14.6 | 4.4 |
| IV-12/a300 | turns (T, R) | 8.0 | 32.9 | 5.9 |
| IV-13/trade/v5.5 | turns (T, R) | 11.1 | 52.7 | 28.8 |
| IV-14 | turns (S, T) | 28.8 | 41.8 | 28.1 |
| IV-15 | turns (K, T) | 19.3 | 53.2 | 4.0 |
| IV-17 | turns (S, K, T) | 122.9 | 265.6 | 16.3 |
| IV-A3 | turns (T, P, D) | 4.7 | 22.4 | 2.0 |
| IV-18 | turns (S) | 29.1 | 38.4 | 14.4 |
| IV-A5 | turns (S, L) | 66.9 | 108.2 | 13.3 |
| VI-2 | turns (S) | 28.3 | 54.3 | 6.5 |
| VI-3 | turns (S, T) | 74.0 | 147.3 | 32.1 |

At regular size the GPU is 1.5–16 times slower than Python: a few hundred agents can't fill the GPU, and each wave
costs a few kernel launches. Credit adds one device thread's pass over the book after the turns and at the end of the
period. Speed is Part F's work.

## xl smoke runs

At xl (`to_xl`: 500 × 500, look stride 10), seed 0, 5 periods on `build-fast\`:
- **IV-3:** 20,000 agents, exit 0, 15 waves and 29 ms a period.
- **IV-A3:** 20,000 agents, exit 0, 15 waves and 27 ms a period.
- **IV-A5:** 40,000 agents (42,275 after 5 periods), exit 0, 507 waves and 117 ms a period.

Every buffer fits, the loan book's included.

## Found on the way

- **Host-only maths in device code.** MSVC's `std::isinf` and `std::isfinite` are host templates. Device code that
  calls them compiles, with nvcc warning #20011, and returns garbage: the GPU's MRS came out infinite, so nobody
  traded. `welfare.h` tests infinity by comparison, and the build log is now checked for these warnings.
- **A parent can end a period with spice ≤ 0.** Fertility tests sugar only (p.55), so in Python a parent may give a
  child more spice than it holds, and live until its next turn's metabolism (seen in IV-18 at t = 14). `--check`
  doesn't require positive spice.
