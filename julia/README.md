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
travel cost of 0.2, plus stage 4's disease list (3 diseases of length 9–10, 1 offered to each founder). The scorecard scores one rule set on II-4, IV-A3 and VI-1 over 20 seeds, against their xl runs,
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
without a whole CSV, and refuses a folder made under other rules, options, code or periods (choose another
`--label`). The code is checked by a checksum of every `.jl` file under `julia/src`, so any edit there, even a comment,
means a stopped run must restart under a new `--label`; `--report-only` rebuilds the report from the CSVs all the same,
with a warning when only the code differs. A `FAIL` verdict is a result, so the exit code is still 0.

The credit study's options change the world the seeds run in, each off by default: `--no-credit` (VI-1 with no loans),
`--inheritance` (rule I: a dead agent's wealth, and a dead lender's loans, pass to its heirs), `--claims-outlive-lender` (they stand instead, repaid into
nowhere), `--credit-reach K` (scales the income a borrower is credited with, 1 by default; it must be above 0) and
`--lender-limit` (a lender lends at most half its wealth, in all, within a period). All but the first two need credit
and `--claims-outlive-lender` refuses `--inheritance`; options the rules refuse are a usage error (exit 2). The options
are in the folder's fingerprint and named in the report, so a run under some is a different run: give it its own
`--label`, and `--report-only` the same options. A run without them writes the fingerprint it always did.

```bat
julia --project=julia julia/xxl_extinction.jl --label reach2 --credit-reach 2 --lender-limit --jobs 10
```

To pause a run, for instance to free the machine's memory, create a file named `stop` in its folder:

```bat
type nul > results-julia-xxl\extinction-defaults-s20-60-p2000\stop
```

Every worker saves its seed at the end of the period it is in and exits, no waiting seed starts, and the run ends without
a report. Running the same command again deletes the file and carries on, and `--jobs` may differ, so a run can shrink or
grow to fit the machine. Each seed also saves every 100 periods, keeping only the latest save (`seed<k>.ckpt`, gone once
the seed's CSV is written), so a crash or a kill costs a seed at most 100 periods. A resumed seed's CSV is byte-identical
to an unbroken run's: the save holds the whole model, its random stream included, and the rows so far. A save at t = 800,
with 73,574 agents living, was 79 MiB and took about 1.4 s, some 0.5% of the time between saves; reading it back took
about 3 s. With `--jobs 10` that is about 800 MiB of disk at any one time.

Each save is checked when read. One cut short or damaged can't be used, so that seed starts again, with a message; one
that is whole but made under other rules, code, periods or Julia is refused before anything runs, and kept: delete it to
start that seed again. Its code check is the run's own, so a save does not survive an edit under `julia/src` either.

Estimated time for the 60 seeds with `--jobs 10`: about 8–10 hours or more (an estimate: about 1.68 s per period per
seed at the reference pace, metrics included, and more in the later periods, when the population is largest). The
first finished seeds give the real figure.

The loan trace asks what the X8 scorecard check measures: it follows every loan of VI-1 from the day it is made to its
repayment or its void by a death, and writes the report that answers the X8 investigation's four questions (who dies,
whether a loan is riskier than the parties' ages explain, what it costs in sugar, whether credit does its job). It
adds nothing to an ordinary run: the tracer is off unless the trace script sets it, and then it draws no random numbers
and changes no loan or agent, so a traced seed's CSV is byte-identical to the untraced run's.

```bat
julia --project=julia julia/xxl_loan_trace.jl --jobs 5
julia --project=julia julia/xxl_loan_trace.jl --label term5 --term 5 --seeds 5 --periods 500
julia --project=julia julia/xxl_loan_trace.jl --world book --seeds 20 --periods 500
julia --project=julia julia/xxl_loan_trace.jl --label term5 --term 5 --seeds 5 --periods 500 --report-only
julia --project=julia julia/xxl_loan_trace.jl --compare loans-defaults-s20-10-p2000,loans-term5-s20-5-p500 --periods 500
```

The first runs the xxl defaults over seeds 20–29 for 2,000 periods (`--world defaults --seeds 10 --first-seed 20
--periods 2000 --jobs 5`, the defaults of those options). `--world` is `defaults`, `xl` (the xl VI-1, no xxl rules) or
`book` (the registry's 50 × 50 VI-1); `--term D` changes the loan term with the rate at 10, `--no-credit` turns credit
off and `--inheritance` (rule I) passes a dead agent's wealth, and a dead lender's loans, to its heirs; `--credit-reach K` scales the income a borrower is
credited with and `--lender-limit` caps a lender at half its wealth within a period (as in the extinction test, and both
need credit). The fourth rewrites a report from the seeds finished, running nothing. Seeds go to `results-julia-xxl/loans-<label>-s<first>-<seeds>-p<periods>/` (a CSV, a timing file and
`.tally.csv`, `.census.csv` and `.loans.csv` per seed) and the report beside them as `.md`; `--label` defaults to the
world's name. `--compare BASE,A,B,…` tabulates folders of `--out`, a row each, over the seeds finished in all of them and
their first `--periods` periods, into `loans-compare.md`: so the main run's seeds 20–24 cut to 500 periods can be the
baseline of the 500-period probes. Its loan figures are by whole window (t = 1–100, 101–500 and 501–end), so for any cut
up to 500 they cover t = 1–500.

Traced runs have no stop file and no checkpoints: a traced seed can't be paused, because a resume would lose the
tracer's state and give wrong tallies with no warning. A stop costs the seeds then running, each of which starts again
from period 0 (an hour or more at 2,000 periods); finished seeds are kept. A seed counts as done only with its CSV and all
three trace files, the CSV being written last, so running the same command again reruns exactly the seeds that were not
done, clearing their leftovers first, and refuses a folder made under another world, term, inheritance, credit reach,
lender limit, code or periods (choose another `--label`). The code is checked by the same checksum of `julia/src` as the extinction test's, so make no
edit there while a long run is going. With `--jobs 5` expect about 2 GB for each worker.

The credit comparison sets finished runs side by side, seed by seed, to see what credit adds. It reads the CSVs of run
folders (the extinction test's or the loan trace's) and runs nothing, so it can be used while a long run is going: a seed
counts only when its CSV is whole, and checkpoints, temporary files and trace files are ignored.

```bat
julia --project=julia julia/xxl_credit_compare.jl --on loans-defaults-s20-10-p2000 --off loans-nocredit-s20-5-p500 --label smoke
julia --project=julia julia/xxl_credit_compare.jl --on extinction-defaults-s20-60-p2000 --off extinction-nocredit-s20-60-p2000 --runs extinction-reach2-s20-60-p2000 --label reach2
```

`--on` and `--off` are folders of `--out` (default `results-julia-xxl`) made with credit and without it; each of `--runs`
(comma-separated) is set against both. Each pair is compared over the seeds both have finished and the periods both
reach (a shorter run cuts the longer). The report, `credit-compare-<label>.md` in `--out` (`--label` defaults to
`credit`), has a table per pair with a row for the trough and one for each window of periods (1–100, 101–200, 201–300,
301–500, 501–1000, 1001–1500, 1501–2000) of the mean population, the births and the births per head. Each is the ratio of
the run's mean to the base's, with a 95% interval from 10,000 resamples of the seeds (a random stream of its own, so
a rerun gives the same figures), where that lies against 1 and against 0.95–1.05, the range of the seeds' own ratios and
how many seeds fell below the base. A seed extinct before a window is left out of it, and a line says how many. The
lag rows give how many periods the run trails the base in recovering, at t = 100, 150 and 200. Each of `--runs` also
gets the share of the lift from off to on that it keeps, for the trough and for the births in periods 1–100.

### The viewer

A live browser view of one xxl VI-1 run (details in docs/xxl.md, "Viewer"). It needs one default and one interactive
thread, so give `--threads=2,1` (plain `--threads=2` gives the same on this Julia, but say it in full):

```bat
julia --project=julia --threads=2,1 julia/xxl_viewer.jl [--port 8766]
```

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
