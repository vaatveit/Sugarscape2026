# Combat on the GPU, against Python (2026-10-26)

Part B of the [full-parity design](../superpowers/specs/2026-10-25-gpu-full-parity-design.md): combat C_α and C_∞ and
same-tribe replacement, with every rule they combine with (culture K and friends, sex S, inheritance I).

## What ran

- **Experiments, on `build\`** (seatbelts on), registered seeds and steps: III-9 (10 seeds), III-11 (5), III-13 (5) and
  III-14 (10).
- **Command:** `bridge.gpu_run <id> --jobs 4`, 15 min for all four. Another application was using the GPU throughout,
  so every timing below is uncontrolled.
- **Python:** the saved results in the main checkout's `results/` (fingerprints current).

## Agreement

`python -m bridge.agreement_report III-9 III-11 III-13 III-14 --python <main checkout>\results` (the Julia rule;
[agreement-part-b.md](agreement-part-b.md)).

**0 of 348 tested windows were flagged.** One window had p < 0.01 (III-13's population in the first quarter,
p 0.0095), where 348 tests with no difference give about 3.5. Combat has none of the design's differences from
Python (section 8): its turns run whole, in the period's order.

## Book targets

`python -m bridge.gpu_report --chapter III`:

| Target | Python | GPU |
|---|---|---|
| III-9 one of the three patterns | pass, 1.0 | pass, 1.0 |
| III-11 both tribes persist | pass, 1.0 | pass, 1.0 |
| III-13 combat suppresses Blue's wave | fail, 9.62 | fail, 9.70 (difference p 0.083) |
| III-14 no runaway hegemony | pass, 0.5 | near, 0.4 |

The one status change, III-14, is whether both tribes persist: 5 of 10 Python seeds against 4 of 10 GPU seeds, a
seed-level p of 1.0 (Fisher). III-13 fails on both sides alike.

## Waves and speed (development timings)

Stepping per period, with another application on the GPU:

| Experiment | Waves per period (seed 0, 20 periods) | GPU ms | Python ms |
|---|---|---|---|
| III-9 | 144 | 156 | 8.2 |
| III-11 | — | 212 | 21.0 |
| III-13 | 289 | 397 | 31.7 |
| III-14 | — | 24 | 0.8 |

- Combat schedules whole turns, so it needs more waves than Part A's rules. At regular size the GPU is 10–30 times
  slower than Python here.
- III-14's population collapses to a few agents, on both sides, so its periods are short.
- Combat with inheritance (no registered experiment) runs one turn per wave.

## xl smoke run

At xl (`to_xl`: 500 × 500, look stride 10), seed 0, 5 periods on `build\`:
- **III-9:** 54,000 agents, exit 0, 7,480 waves and 5.9 s a period.
- **III-13:** 74,000 agents, exit 0, 18,381 waves and 29 s a period.

The footprint buffers fit. The waves are about twice the design's estimate (3,678 for III-9 at t = 0), because the
footprints are conservative: every sight-line site and every retaliation line is listed, occupied or not. Speed at xl
is Part F's work.

## Found on the way

- **FLAME GPU rc.5 writes new agents' defaults unaligned.** `CUDAScatter::broadcastInit_async` lays the defaults out
  without the 8-byte alignment `CUDAAgent::mapNewRuntimeVariables_async` uses. In an odd-sized agent output, the
  last agents got the next variable's default, or uninitialised memory, in every variable their birth left unset.
  - Combat with sex made it visible: newcomers with `neighbors` of 4,294,967,295, and bytes that changed from run to
    run.
  - Every agent output now sets every citizen variable (`rules.cuh`, `init_citizen_out`).
  - Chapter II's goldens and every Part A test are unchanged by the fix.
- **Newcomer placement can differ from run to run.** Newcomers claim random empty sites at once. When two draw the
  same site in the same try, the GPU's timing decides which keeps it. With a handful of newcomers a period this is
  rare. With dozens (combat with sex and replacement, and xl runs with replacement), a seed's bytes can differ between
  runs, though distributions don't.
  - The race predates Part B.
  - A deterministic placement would move Chapter II's newcomers, and so change the goldens the design protects. It is
    left for a decision.
