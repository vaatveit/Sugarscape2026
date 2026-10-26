# Sugarscape in Julia

A Julia port of the Python sugarscape model in this repository, every rule of Chapters II–VI of Epstein and
Axtell's *Growing Artificial Societies*. It runs every sugarscape experiment of the registry, at regular size and at
the 500 × 500 xl size of [docs/xl.md](../docs/xl.md), and writes results in the Python runner's layout. The point is
to compare implementations of one model, for fidelity and for speed. The design is in
[docs/superpowers/specs/2026-10-24-julia-design.md](../docs/superpowers/specs/2026-10-24-julia-design.md), and the
running record of every comparison is [docs/validation.md](docs/validation.md).

The Python model is the specification. "The same model" means the same statistics across seeds, not identical runs:
Julia uses its own random number generator.

## Prerequisites

- Julia 1.13 (tested with 1.13.2, installed with juliaup). The model uses the standard library only. JuliaFormatter
  lives in its own environment, `tools/`, and is needed only to format.
- For the tests that compare with Python, and for the comparison report: the repository's Python environment
  (`.venv`, Python 3.14 with numpy).

## Tests

From the repository root:

```bat
julia --project=julia -e "using Pkg; Pkg.test()"
```

`Pkg.test(test_args=["trade"])` runs only the test files whose names contain `trade`. The Python side, from
`julia/`:

```bat
..\.venv\Scripts\python -m pytest -q
```

What the tests check, besides each rule's own cases (one Julia test set per deterministic test in `tests/`):

- **Cross-language scenarios** (`test/fixtures/scenarios.toml`): 21 small states whose outcome cannot depend on the
  agents' order or on random draws (Python refuses any that does), with the end state the Python model reached:
  movement, growback, seasons, pollution and diffusion, starvation, old age, combat, inheritance, credit, and rule T
  applied directly to 45 fixed pairs. Julia must match to 1e-12.
- **Lockstep** (`test/fixtures/lockstep.toml`): Python runs with every random choice recorded (the acting order,
  each agent's direction order, and the order it trades with its neighbours), and Julia, fed those choices through
  a scripted RNG, must reproduce the trajectory exactly, period by period. Nine cases cover rules M, C (both α), T,
  growback, seasons, pollution and diffusion, and spice movement with foresight.
- `registry.toml` and both fixture files are generated from Python, and a Python test fails when any of them is out
  of date: `python -m bridge.export_registry`, `python -m bridge.scenarios`, `python -m bridge.lockstep`.

## Running

```bat
julia --project=julia julia/run.jl II-4 --jobs 8
julia --project=julia julia/run.jl II-4 --xl --jobs 5
```

The arguments are those of `python -m experiments.run`: an id or a sweep prefix (`II-5` runs every `II-5/...`),
`--seeds N`, `--jobs J`, `--out DIR`, `--xl`, and `--note TEXT`, which is copied into `machine.txt` (for example
"quiet machine"). Results go to `results-julia/` or `results-julia-xl/`: one folder per experiment, with
`seed{k}.csv` (the Python runner's 46 columns, readable by `experiments.run._read_csv`), `timing.csv`
(docs/xl.md, "Timing"), `machine.txt`, and `fingerprint.txt` (`julia` plus the Python fingerprint).

Each seed runs single-threaded. `--jobs J` runs seeds in J worker processes, one seed at a time each. Julia compiles
on first use, so each worker first runs the experiment's own path for 2 untimed periods, and `machine.txt` records
how long that took (`warm_up_s`). The timed setup then covers building the model, as docs/xl.md defines it.

## Comparing with Python

```bat
cd julia
..\.venv\Scripts\python -m bridge.report
..\.venv\Scripts\python -m bridge.report --xl
```

The report reads the Python results in this checkout (`results/`, `results-xl/`; `SUGARSCAPE_RESULTS_ROOT`
overrides where) and Julia's, runs nothing, and writes `REPORT.md` into the Julia results folder:

- **Agreement.** For every experiment, every metric and each quarter of the run, each seed's mean over the window;
  a Welch t-test between the two sides' seed values; and extinction (seeds with no agents at the end) by Fisher's
  exact test. All p-values of one report are corrected together (Benjamini–Hochberg, q = 0.01), and a test that
  survives is a flag. A window with fewer than two values on a side is listed as untestable.
- **Book targets** (regular size): both sides scored against `replication/targets.py`, every status that differs,
  and each change's seed-level p (the target's per-seed values, Julia against Python).
- **Speed**: setup, seconds per period, metrics time and agents, the Python ÷ Julia speedup, and each side's
  `machine.txt` jobs and note.
- **Inputs**: which results are missing, stale by fingerprint, incomplete or untimed on either side.

## How the Julia version differs from Python

None of these changes a distribution; the lockstep tests show the rules match period by period.

- **Random numbers.** `Random.Xoshiro`, seeded with the registered seed plus k, so no run matches Python's run of
  the same seed.
- **Uniform choices made differently.** Placement samples sites by a partial Fisher–Yates shuffle; a direction order
  is one of the 24 orders drawn uniformly; an empty site for a newcomer is found by rejection sampling (falling back
  to a scan when the lattice is nearly full).
- **Storage.** Living agents are kept in no particular order (each period draws a fresh one). Cultural tags and
  immune systems are bit fields, so `tag_length` above 63 or `immune_length` above 64 is refused; the registry
  uses 11 and 50. Diseases are interned by their bit string and length, so equal strings are one disease, as
  Python's equal tuples are.
- **Work skipped without changing a result.** Combat checks a site for retaliation only when it would replace the
  best safe site so far (Python checks every candidate, then picks the same one). Welfare scoring computes the
  agent's part once per move, bit-identical to scoring each site afresh (tested).
- **Sums.** Python's `sum()` of floats is compensated (Neumaier); Julia's is not. It matters only for bit-identity,
  in the credit rule's sum of a borrower's debts.

## Results

### Regular size

All 134 sugarscape experiments of the registry, registered seeds (2026-10-24). The report's verdict rule asks for no
flags *and* no book-target status changes, so `REPORT.md` reads "does not agree" while the 37 changes below stand;
the evidence that each is sampling noise is in [docs/validation.md](docs/validation.md), for you to accept or not.

- **0 flags among 8,146 tested windows and 134 extinction tests**, under one correction.
- **Book targets:** Python 139 pass, 56 near, 120 fail; Julia 136 pass, 65 near, 114 fail. 37 statuses changed.
  All but one have a seed-level p above 0.05, and one could not be computed. The ones below 0.05 or pointing one
  way (III-8, III-9, IV-6, IV-18, VI-1) were followed up with 50 to 200 seeds on each side, lockstep replays, and decision parity on a
  mid-run state; each turned out to be sampling noise, typically Python's registered seeds sitting on one side of
  its own long-run mean. Details: [docs/validation.md](docs/validation.md).

### xl

xl follows main's current definition, including the look of docs/xl.md ("Looking"), which changed twice during
the port: the look stride (commit 0b6b937), then the centred look (80f4630, 2026-10-26).

- **Centred look, II-4 and IV-A3 (10 seeds each): Julia agrees with Python, 0 flags.** At the end, II-4 has 23,838
  agents in Python and 23,828 in Julia; IV-A3 3,212 and 3,253.
- **Earlier uniform look, seven experiments (II-4, II-4-gini, II-6, II-7, II-8, IV-A3, VI-1): Julia agreed with
  Python, 0 flags among 436 tested windows and 7 extinction tests.** II-4-gini, II-6, II-7, II-8 and VI-1 still
  have uniform-look results on both sides; the fingerprint doesn't record the look, so the report can't tell.
- **The whole registry** ran in Julia at xl with the uniform look: all 135 experiments at their registered seeds,
  without a failure.
- **VI-1 at xl does not go extinct on either side**, unlike 3 of 5 regular seeds: at t = 500 Python has 83,623
  agents on average and Julia 86,415. The larger world sustains the society; [docs/validation.md](docs/validation.md)
  has the numbers.

### Speed

| Workload | Python s/period | Julia s/period | Speedup |
|---|---|---|---|
| II-4 regular (400 → 236 agents) | 0.0131 (4 jobs) | 0.000091 (10 jobs) | about 144× |
| II-4 xl (40,000 → about 23,830 agents) | 3.24 (10 jobs) | 0.043 (10 jobs) | about 75× |
| IV-A3 xl (20,000 → about 3,230 agents) | 1.11 (1 job) | 0.028 (1 job) | about 40× |
| VI-1 xl, uniform look (20,000 → about 85,000 agents) | 15.45 (1 job) | 0.230 (1 job) | about 67× |

Seconds of stepping per period, averaged over seeds and periods. Each report adds a row for every experiment timed
on both sides; over the 135 regular experiments, both with one job, the median speedup is 36×
([docs/validation.md](docs/validation.md)).

Julia alone, a selection of the xl registry (seconds of stepping per period; agents at start and end, mean over
seeds). The median xl experiment takes 72 ms per period; the whole registry took 51 hours of stepping, summed over
seeds. II-4 and IV-A3 are centred-look runs (2026-10-26, 10 jobs and 1 job); the rest used the uniform look. VI-1 was
re-run with one job after the single-thread speed-ups; the others ran with 5 to 10 jobs sharing the processor.

| Experiment | Agents | Periods | Julia s/period |
|---|---|---|---|
| II-4 | 40,000 → 23,828 | 500 | 0.043 |
| II-8 | 40,000 → 18,606 | 200 | 0.032 |
| III-1 | 40,000 → 64,377 | 2,500 | 0.159 |
| III-9 | 54,000 → 21,290 | 1,000 | 0.079 |
| III-15 | 10,000 → 67,695 | 6,000 | 0.307 |
| IV-3 | 20,000 → 4,732 | 1,000 | 0.012 |
| IV-A3 | 20,000 → 3,253 | 300 | 0.028 |
| IV-A5 | 40,000 → 72,532 | 500 | 0.579 |
| V-2 | 40,000 → 22,401 | 500 | 0.029 |
| VI-1 | 20,000 → 86,415 | 500 | 0.230 |
| VI-3 | 50,000 → 93,710 | 1,000 | 0.369 |

At regular size the median Julia experiment steps in about 0.1–0.5 ms per period.

All timings so far are development timings on a shared i7-13700K (8 performance and 8 efficiency cores): other
sessions were running, so they can be off by up to about 2× either way. The headline numbers will come from
quiet-machine runs.
