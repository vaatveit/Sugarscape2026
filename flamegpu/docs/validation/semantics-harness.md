# The GPU's turn semantics in Python (2026-10-25)

This is the measurement behind the [full-parity design](../superpowers/specs/2026-10-25-gpu-full-parity-design.md)
("What was measured" and section 8). `bridge/semantics_harness.py` runs Python's model with exactly what the GPU does
differently in runs without combat:
- Every agent's target is fixed at the start of the period by deferred acceptance, scored with the holdings at the
  start.
- Then every turn runs in Python's order.
- A child is never born on the target of an agent still to come.

That leaves the three differences of section 8: vacated sites aren't offered, children avoid pending targets, and
movement uses start-of-period holdings. Everything else is Python's code.

## What ran

The harness covered the 43 experiments without combat that have spice or interaction rules: III-1, -3, -4, -5, -7, all
of Chapter IV, V-1, V-2 and VI-1 to VI-3. That is 345 seeds over the registered steps, on seeds base + 1000 + k, a
stream of their own. The harness results were scored against Python's saved results in the main checkout's `results/`:

```bat
.venv\Scripts\python -m bridge.semantics_harness III-1 III-3 III-4 III-5 III-7 IV-3 IV-6 IV-7 IV-9 IV-12 IV-13 IV-14 IV-15 IV-17 IV-A3 IV-18 IV-A5 V-1 V-2 VI-1 VI-2 VI-3 --jobs 22
.venv\Scripts\python -m bridge.agreement_report <the same ids> --gpu results-harness --python C:\Projects\Sugarscape2026\results
```

The run took 297 s on 22 processes.

## Result

**0 of 2,835 tested windows were flagged** under the Julia agreement rule: a Welch test per (experiment, metric,
quarter), Fisher's exact test for extinction, and Benjamini–Hochberg at q = 0.01. 28 windows were untestable.
- 12 windows had p < 0.01, where 2,835 tests with no difference give about 28.
- The smallest p is 0.002 (IV-12/a80 mean vision, first quarter).
- All 12 are Chapter IV experiments with spice (IV-12, IV-6, IV-13, IV-15), and 10 of them fall in the first quarter.
  That is where trading holdings move furthest from the start-of-period ones (difference 3). None survives the
  correction.

The first run, made while the design was being written (scratch scripts), gave the same numbers.

So the hybrid (deferred-acceptance movement, then turns in order) is statistically indistinguishable from Python on
every affected experiment. That is why the GPU keeps deferred acceptance for movement, rather than paying for whole
turns in waves.
