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

## xxl

xxl is a Julia-only rule set for the 500 × 500 world that uses the room instead of hiding it: round vision, a speed
trait with a travel cost, memory and word of mouth, an interaction radius, seasons that vary with latitude, a
generated landscape (plus combat under them), and four survival switches: a metabolism cap, viable founder
placement, a free step and young founders. Each is a separate switch with a book setting, so its effect is
measured alone. It is not the book, has no Python counterpart, and leaves every regular and xl run, fingerprint and
random stream unchanged. The rules are defined in [docs/xxl.md](../docs/xxl.md).

```bat
julia --project=julia julia/run.jl XXL --jobs 1
julia --project=julia julia/run.jl II-4 --xxl --jobs 1
julia --project=julia julia/xxl_report.jl [prefix]
```

The first runs the 16 `XXL-…` experiments (5 seeds each; a family such as `XXL-speed` runs only its members), the
second the xxl version of any registered sugarscape experiment. Results go to `results-julia-xxl/` (git-ignored), in
the xl layout plus nine added metric columns; a folder is named by its id with `/` replaced by `_`. The report reads
those folders and the base experiments' `results-julia-xl/` runs, and prints each metric's mean and seed spread at
t = 50, 100, 200 and over the last 100 periods, xxl beside xl, with the stepping time per period of both.

`--xxl` runs the defaults, which stage 1 of the revised design chose with the scorecard: the first rules (`XXL_V1`,
which the `XXL-…` experiments keep) with the generated map, viable founder placement, a free step of 1.5 and a
travel cost of 0.2. The scorecard scores one rule set on II-4, IV-A3 and VI-1 over 20 seeds, against their xl runs,
with 15 pass/fail checks of survival, sex, culture, trade, credit and disease:

```bat
julia --project=julia julia/xxl_scorecard.jl --jobs 10
julia --project=julia julia/xxl_scorecard.jl --rules v1 --set free_step=1.5 --jobs 10
julia --project=julia julia/xxl_scorecard.jl --first-seed 20 --jobs 10
```

The first scores the defaults on seeds 0–19, the second the first rules with one change, the third the defaults on
seeds 20–39. The report goes to `results-julia-xxl/scorecard-<label>-s<first>-<seeds>.md`, beside the runs. The
checks, the tuning and its results are in [docs/xxl.md](../docs/xxl.md) ("Stage 1: the scorecard and survival").

Wall time for 20 seeds with `--jobs 10` on the i7-13700K's 24 threads (machine load not recorded): 2,196 s
(37 minutes) for the defaults on seeds 20–39, which included running the xl reference for that seed range (583 s
of it). The xl reference runs once per seed range and is reused after that: the defaults on seeds 0–19, reusing it,
took 1,753 s (29 minutes), and the 15 tuning scorecards that reused it took 1,373–2,209 s. VI-1 dominates, at
1,126–1,731 s of each.

The extinction test asks whether VI-1 under a rule set has under a 5% chance of going extinct in 2,000 periods. It runs
only VI-1, with the standard columns and no scorecard ones, and reports the upper 95% limit on that chance:

```bat
julia --project=julia julia/xxl_extinction.jl --jobs 10
julia --project=julia julia/xxl_extinction.jl --rules v1 --seeds 20 --periods 500 --jobs 10
julia --project=julia julia/xxl_extinction.jl --report-only
```

The first runs the defaults over seeds 20–79 (`--seeds 60 --first-seed 20 --periods 2000`, the defaults of those
options); the second a shorter trial of the first rules; the third rewrites the report from the seeds finished, running
nothing. Seeds go to `results-julia-xxl/extinction-<label>-s<first>-<seeds>-p<periods>/` and the report beside them as
`.md`; `--label` defaults to the `--rules` value. Each seed's CSV is written when it ends and the progress line shows
the pace and the hours left, so a stopped or crashed run resumes by running the same command: it runs only the seeds
without a whole CSV, and refuses a folder made under other rules, code or periods (choose another `--label`). The code
is checked by a checksum of every `.jl` file under `julia/src`, so any edit there, even a comment, means a stopped run
must restart under a new `--label`; `--report-only` rebuilds the report from the CSVs all the same, with a warning
when only the code differs. A `FAIL` verdict is a result, so the exit code is still 0.

Estimated time for the 60 seeds with `--jobs 10`: about 8–10 hours or more (an estimate: about 1.68 s per period per
seed at the reference pace, metrics included, and more in the later periods, when the population is largest). The
first finished seeds give the real figure.

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

- **Centred look, seven experiments (II-4, II-4-gini, II-6, II-7, II-8, IV-A3, VI-1), both sides with one job:
  Julia agrees with Python, 0 flags among 436 tested windows and 7 extinction tests** (2026-10-27). At the end, II-4
  has 23,838 agents in Python and 23,828 in Julia, and IV-A3 has 3,212 and 3,253. The smallest p, II-6's early
  Gini (0.5% lower in Julia), is sampling noise by 50 Julia seeds.
- **The earlier uniform look** also agreed on the same seven, with 0 flags.
- **The fingerprint names the look** (since 48a56cb, 2026-10-28): every xl fingerprint starts with `look: centred`,
  so results made with an older look read as stale in the report. The 17 Julia results on record as centred-look
  runs were re-stamped with the new line: the seven above, and ten re-run with the centred look on 2026-10-28 (one
  job) as the GPU port's xl reference, III-1, III-7, III-8, III-9, III-11, IV-3, IV-6/trade/v6, VI-3, IV-A5 and
  V-2. Python's seven xl results are being re-run (started 2026-10-28) to carry the line; until each finishes, the
  report lists it as stale.
- **The whole registry** ran in Julia at xl with the uniform look: all 135 experiments at their registered seeds,
  without a failure. The other 118 of `results-julia-xl/` are still those uniform-look runs, and read as stale until
  they are re-run.
- **VI-1 at xl does not go extinct on either side**, unlike 3 of 5 regular seeds: at t = 500 Python has 82,049
  agents on average and Julia 89,367, a gap of 0.45 of Python's SD across seeds. The larger world sustains the
  society; [docs/validation.md](docs/validation.md) has the numbers.

### Speed

| Workload | Python s/period | Julia s/period | Speedup |
|---|---|---|---|
| II-4 regular (400 → 236 agents) | 0.0131 (4 jobs) | 0.000091 (10 jobs) | about 144× |
| II-4 xl (40,000 → about 23,830 agents) | 1.33 (1 job) | 0.014 (1 job) | about 94× |
| IV-A3 xl (20,000 → about 3,230 agents) | 1.11 (1 job) | 0.028 (1 job) | about 40× |
| VI-1 xl (20,000 → about 85,000 agents) | 16.44 (1 job) | 0.323 (1 job) | about 51× |

Seconds of stepping per period, averaged over seeds and periods. Each report adds a row for every experiment timed
on both sides. Over the 135 regular experiments, both with one job, the median speedup is 36×. Over the seven
centred-look xl experiments, also one job each, it is 94× ([docs/validation.md](docs/validation.md)).

Julia alone, a selection of the xl registry (seconds of stepping per period; agents at start and end, mean over
seeds). Over the results in `results-julia-xl/` now, the median experiment takes 68 ms per period, and the whole
registry took about 50 hours of stepping, summed over seeds. All rows but III-15 are centred-look runs with one job
(2026-10-26 to 28); III-15 used the uniform look and ran with 10 jobs sharing the processor, as did the other 118
experiments not listed.

| Experiment | Agents | Periods | Julia s/period |
|---|---|---|---|
| II-4 | 40,000 → 23,828 | 500 | 0.014 |
| II-8 | 40,000 → 19,104 | 200 | 0.027 |
| III-1 | 40,000 → 66,259 | 2,500 | 0.110 |
| III-9 | 54,000 → 303 | 1,000 | 0.031 |
| III-15 | 10,000 → 67,695 | 6,000 | 0.307 |
| IV-3 | 20,000 → 5,971 | 1,000 | 0.010 |
| IV-A3 | 20,000 → 3,253 | 300 | 0.028 |
| IV-A5 | 40,000 → 72,839 | 500 | 0.256 |
| V-2 | 40,000 → 22,926 | 500 | 0.032 |
| VI-1 | 20,000 → 89,367 | 500 | 0.323 |
| VI-3 | 50,000 → 94,342 | 1,000 | 0.320 |

At regular size the median Julia experiment steps in about 0.1–0.5 ms per period.

All timings so far are development timings on a shared i7-13700K (8 performance and 8 efficiency cores): other
sessions were running, so they can be off by up to about 2× either way. The headline numbers will come from
quiet-machine runs.
