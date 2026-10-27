# Chapter V on the GPU, against Python (2026-10-27)

Part D of the [full-parity design](../superpowers/specs/2026-10-25-gpu-full-parity-design.md): immune systems, the
master disease list, disease E (transmission, then the immune response), the disease fee wherever Python burns sugar,
and `disease_metrics` ([plan](../superpowers/plans/2026-10-27-gpu-parity-part-d.md)). The part also fixed the four
minors Part C deferred. After it, every field of Python's `Config` runs on the GPU.

## What ran

- **Experiments, on `build\`** (seatbelts on), registered seeds and steps:
  - V-1 and V-2, 10 seeds of 500 periods;
  - VI-1 and VAR-inttrade/VI-1, 5 seeds of 500 periods.
- **Command:** `bridge.gpu_run <id> --jobs 4` for each id, 3 min 40 s in all.
- **Python:** the saved results in the main checkout's `results\` (fingerprints current).

## Agreement

`python -m bridge.agreement_report V-1 V-2 VI-1 VAR-inttrade/VI-1 --python <main checkout>\results` (the Julia rule;
[agreement-part-d.md](agreement-part-d.md)).

**0 of 432 tested windows were flagged, and none had p < 0.01.** 10 windows were untestable (fewer than two seed values
on a side): the north fractions of VI-1's vision groups after they die out, in both VI-1 runs.

## Book targets

`python -m bridge.gpu_report --chapter V`, then `--chapter VI`, both with `--python <main checkout>\results`.

- **Chapter V:** 6 targets, the same status on both sides: 2 pass, 4 fail.
  - The fails are Python's own. In V-2 disease doesn't stay endemic: the average number of diseases falls to about
    0.01 on both sides (Python 0.018, the GPU 0.013), where the book's Animation V-3 settles at 0.86.
  - V-1's "no disease left circulating" fails on both sides by a similar margin (on average 1 disease still
    circulating for Python, 0.7 for the GPU).
- **Chapter VI:** VI-1's 15 targets. VI-2 and VI-3 were Part C's runs, and VI-4 to VI-9 are the Schelling and Ring
  World models (Parts E and F).
  - Every VI-1 status is the same on both sides but one: the Gini of total wealth (t = 40–50) is a pass for Python
    (0.277) and near for the GPU (0.337), against a band of 0.20–0.30.
  - **That change is the five seeds, not the GPU.** At the registered 5 seeds a side the seed-level p is 0.021. With
    20 seeds a side the means are 0.316 (Python) and 0.321 (the GPU), p 0.59: Python's five registered seeds sit low,
    and both sides' means lie just above the band.
  - VI-1's four disease targets fail on both sides with 0: its society loses every disease, as V-2 nearly does.

## Speed

Each experiment's seed 0 alone on `build\` (seatbelts on), with `--timing`, against Python's saved per-period time:

| Experiment | Path | Waves per period | GPU ms, alone | GPU ms, `--jobs 4` | Python ms |
|---|---|---|---|---|---|
| V-1 | turns (E) | 7.9 | 4.4 | 26.8 | 3.5 |
| V-2 | turns (E) | 8.1 | 4.6 | 27.2 | 3.6 |
| VI-1 | turns (S, K, T, L, E) | 3.1 | 2.9 | 60.9 | 7.8 |
| VAR-inttrade/VI-1 | turns (S, K, T, L, E) | 3.5 | 3.3 | 60.2 | 8.5 |

- The `--jobs 4` column is the agreement report's: four runs shared the GPU, so it is several times the time alone.
- VI-1's seed 0 dies out (200 agents at the start, none at the end), so its time alone averages many empty periods.

At regular size a few hundred agents can't fill the GPU. Speed is Part F's work.

## xl smoke runs

At xl (`to_xl`: 500 × 500, look stride 10), seed 0, 5 periods on `build-fast\`:
- **V-2:** 40,000 agents (39,874 after 5 periods), exit 0, 19.6 waves and 11.0 ms a period.
- **VI-1:** 20,000 agents (18,818 after 5 periods), exit 0, 178.8 waves and 116.4 ms a period.

Every buffer fits, the store's disease rows included.

## Found on the way

- **Two agents can want one site under welfare.** The plan's fee test assumed its four far-apart agents never meet.
  Under spice, two of them reach for the same site at t = 2, and the turn order decides. The test now steps Python in
  the GPU's order.
- **The fee in movement needed its own test.** Unordered, the welfare case gave the same moves with or without the
  fee. `test_fee_steers_welfare_movement` puts one agent between a sugar site and a spice site, where two diseases
  flip its choice. It and the ordered welfare case both failed with the fee left out of `propose`.
- **Part C's minors.** The loan book now holds its full capacity: `on_death` and the ledger's re-originations are built
  in a staging list, not past the book's end. A starving agent's heirs are counted only if it lends, so a non-lender
  with 33 children dies cleanly; a lender with more than 32 still exits 5. The owed loop skips a loan without a lender
  row, and `k_fix_loans` names `PROVISIONAL_PARENT`.
