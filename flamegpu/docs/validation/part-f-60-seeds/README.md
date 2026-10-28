# Part F: 60 seeds of III-7 and VI-3, four programs

The evidence for [part-f.md](../part-f.md)'s explanation of the six xl flags against Julia. Each program ran 60 seeds
of III-7 and VI-3 at regular size, and every pair was scored by the agreement rule (2026-10-28).

| File | Scored (`--gpu`) | Against | Flagged of 131 |
|---|---|---|---|
| [julia-vs-python.md](julia-vs-python.md) | Julia | Python | 0 |
| [harness-vs-python.md](harness-vs-python.md) | the semantics harness | Python | 4 |
| [gpu-vs-python.md](gpu-vs-python.md) | GPU | Python | 2 |
| [gpu-vs-julia.md](gpu-vs-julia.md) | GPU | Julia | 2 |
| [gpu-vs-harness.md](gpu-vs-harness.md) | GPU | the semantics harness | 0 |

Each report's title reads "GPU against Python" (or Julia), whichever program sits in each place. Where the harness or
Julia sits in a place that expects another program's fingerprint, the report lists both experiments as stale. That
listing is expected here: the seeds are complete and current.

## Commands

From `flamegpu\`, each into its own folder:

```bat
.venv\Scripts\python -m bridge.gpu_run III-7 VI-3 --seeds 60 --jobs 4 --exe build-fast\bin\Release\sugarscape_gpu.exe --out DIR\gpu
.venv\Scripts\python -m bridge.semantics_harness III-7 VI-3 --seeds 60 --jobs 8 --out DIR\harness
```

From the repository root:

```bat
python -m experiments.run III-7 --seeds 60 --jobs 6 --out DIR\python
julia --project=julia julia/run.jl III-7 --seeds 60 --jobs 4 --out DIR\julia
```

The same two commands run VI-3. Then score each pair:

```bat
.venv\Scripts\python -m bridge.agreement_report III-7 VI-3 --gpu DIR\gpu --python DIR\harness --out gpu-vs-harness.md
.venv\Scripts\python -m bridge.agreement_report III-7 VI-3 --gpu DIR\gpu --reference julia --julia DIR\julia --out gpu-vs-julia.md
```

The other three pairs are scored the same way.
