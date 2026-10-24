# Phase 1 validation: Chapter II on the GPU

Date: 2026-10-23. GPU program at this commit, built with FLAME GPU's run-time checks on
(`FLAMEGPU_SEATBELTS=ON`). Python results from `C:\Projects\Sugarscape2026\results`, all current
(none stale). Every registered Chapter II experiment was run with its registered seed count: 25
experiments, 225 runs, all exiting 0. The full table is in `results-gpu/REPORT.md`, written by
`python -m bridge.gpu_report --chapter II`.

## Scoreboard

Chapter II has 49 targets. The design said 53; that was a miscount.

| | Pass | Near | Fail |
|---|---|---|---|
| Python | 37 | 9 | 3 |
| GPU | 36 | 10 | 3 |

The same 3 targets fail on both sides, and they are failures the Python project already records:
- II-6's wave reaches the NE peak (proxy). Python 0.049, GPU 0.046; band 0.15–1.
- II-6-measured, the same target. Python 0.013, GPU 0.010.
- II-7's low-vision agents hibernate (proxy). Python 0.222, GPU 0.236; band −0.15 to 0.15.

The 9 targets that are near for Python are also near for the GPU: II-4's mean vision and 8 of the
Fig II-5 points at t = 500.

## The one status change

**II-5/m3/v8, carrying capacity at t = 500: Python pass → GPU near.** The band starts at 252.
- Python's mean is 252.3, only 0.3 inside the band; its seeds range over 242–262.3.
- The GPU's mean is 251.5; its seeds range over 245.7–258.

The difference, −0.8 agents, is smaller than Python's seed spread and not significant (Welch t-test
on the 10 seeds a side). It is a mean that sits on the band's edge, falling either side by chance.
The same experiment's t ≈ 50 target passes on both sides.

## How close the two models are

For every one of the 49 targets, the GPU's mean lies inside the range of Python's seeds. The largest
gap, as a fraction of Python's seed range:

| Target | Python | GPU | Gap / Python range |
|---|---|---|---|
| II-4 mean neighbors | 0.797 | 0.855 | 0.68 |
| II-8 lower carrying capacity when polluted | 0.839 | 0.814 | 0.64 |
| II-5/m2/v2 carrying capacity at t ≈ 50 | 368.3 | 373.3 | 0.42 |
| II-5/m2/v3 carrying capacity at t ≈ 50 | 388.4 | 392.9 | 0.37 |
| II-4 mean vision at t = 500 | 3.791 | 3.884 | 0.34 |

All the other targets are within 0.25 of Python's range.

## Differences the parallel update makes

The design named where moving everyone at once can differ from Python's one-at-a-time order. Two of
those differences show in the results.

**Neighbors are counted after everyone has moved: +7%.** II-4's mean neighbors is 0.855 on the GPU
and 0.797 in Python. Python counts an agent's neighbors right after its own move, so agents that
move later and settle next to it are not counted. The GPU counts after all moves, so they are. Both
pass the book's band (0.75–1.05), and the GPU is closer to the book's 0.9.

**Carrying capacity runs about 1% higher, mostly early.** Over the Fig II-5 sweep and II-4:

| Read at | Targets | GPU higher in | Mean shift | Range | Significant alone (\|t\| > 2.1) |
|---|---|---|---|---|---|
| t = 500 | 19 | 11 | +0.5% | −0.4% to +1.9% | 0 |
| t ≈ 50 | 18 | 15 | +1.0% | −0.9% to +2.6% | 0 |

No single target differs significantly. But at t ≈ 50 the GPU is higher in 15 of 18 targets
(two-sided sign test, p ≈ 0.008), so a small systematic shift is likely. It does not move any status
except the edge case above. The cause has not been isolated. Candidates from the design's list:
- In round 1, agents see only the positions at the start of the period, where Python's later agents
  see earlier agents' moves.
- A site freed by a death becomes available only in the next period.

If later chapters, whose births are density-dependent, turn out sensitive to it, an ablation could
separate the two: for example, letting deaths free their sites within the period.

**Pollution.** II-8's ratio of carrying capacity polluted to unpolluted is 0.814 on the GPU against
0.839 in Python. Both pass the proxy band (0–0.9). Pollution values are float32 on the GPU, which is
the only place float32 cannot represent Chapter II's quantities exactly. That likely contributes,
along with the parallel update; this run does not separate the two.

## Conclusion

For Chapter II, the GPU model reproduces the Python model's results. Every target's GPU mean is
inside the Python seed range, the same targets fail for the same reasons, and the only status change
is a mean on a band edge. Two effects of parallel updating are measurable: neighbor counts (+7%) and
early carrying capacity (+1%). Both are well inside the book's bands.
