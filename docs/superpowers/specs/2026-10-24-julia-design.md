# Sugarscape in Julia — Design

Date: 2026-10-24. Builds on [the project design](2026-10-21-sugarscape-design.md) and
[the xl design](2026-10-24-xl-design.md); the workload contract is [docs/xl.md](../../xl.md).

## Intent

The xl workload exists to compare implementations of one model: the Python model (the baseline), the FLAME GPU 2
port in `flamegpu/`, and a Julia implementation. This project is the Julia implementation **and the comparison of it
against Python**, for fidelity (is it the same model?) and for speed (how much faster is it, per core?).

"The same model" means **the same statistics across seeds**, not identical runs (user decision). Julia uses its own
random number generator; it does not reproduce numpy's draws.

## Goals

- A Julia port of the sugarscape model, every rule of Chapters II–VI, in `julia/`. It runs **every `Config`
  experiment in `experiments/registry.py`** (user decision): Chapters II–VI and the VAR- variants, 134 experiments,
  at regular size and at xl size (docs/xl.md).
- A Julia runner that writes results in the Python runner's format: `seed{k}.csv` per seed with the same metric
  columns, `timing.csv` (docs/xl.md, "Timing"), `machine.txt`, `fingerprint.txt`.
- **The comparison itself** (user decision), as a report:
  1. *Regular size, all 134 experiments:* book-target statuses on both sides, and statistical agreement of every
     metric (rule below).
  2. *xl size:* statistical agreement on the three experiments Python runs at xl: **II-4, VI-1 and IV-A3** (user
     decision). Julia runs the whole registry at xl; only these three have a Python side.
  3. *Speed:* setup, stepping and metrics time, Julia against Python, **one core per seed on each side** (user
     decision), at regular and xl size.
- A written account of the results, like the GPU port's validation page: what agrees, what doesn't and why, and
  the speed table.

## Non-goals

- **Run-for-run identity with Python.** No numpy-compatible random streams.
- **Multi-threading a single run.** Wanted later, lower priority (user decision). Nothing in the design should
  prevent it: keep the landscape rules (growback, diffusion) as whole-array operations that could later be split
  across threads.
- Schelling, Ring World, and the viewer. They stay Python-only; Schelling and Ring World have no xl.
- Making the Python model faster. It is the baseline.
- Scoring xl runs against the book's targets (the targets are absolute numbers for a 50×50 world; xl design).
- **Running Python experiments** (user decision). The user generates every Python result in separate sessions:
  the regular registry re-run with timings (the saved `results/` predate the runner's timing and have no
  `timing.csv`), and II-4, VI-1 and IV-A3 at xl. This project concentrates on the Julia runs and only reads Python
  results. The report says plainly which Python results are missing, stale or untimed, and works with whatever is
  there.
- **Controlled timing** (user decision). Timings during development are taken as they come, on a shared machine.
  When all the implementations are finished, the user does quiet-machine runs for the headline numbers; the Julia
  runner and the report need nothing special for that beyond what is below.
- Python xl runs beyond II-4, VI-1 and IV-A3, for now. The user may add more later; the report handles any
  experiment that has results on both sides.

## Anti-goals

- **No change to any Python result.** The Python model, registry, configs, random streams and fingerprints stay as
  they are. The Julia work only reads them (and runs Python experiments that are missing or stale).
- **Julia is not faster because it does less.** Every rule, every "our call" reading, and every metric is ported.
  A shortcut that changes behaviour (for example, a different tie-break, or skipping a scan step) is a bug even if
  the statistics happen to agree.
- **No tuning to make the comparison pass.** A flagged difference is fixed as a bug in Julia or explained in
  writing. It is never hidden by widening the rule.
- **No hand-copied registry.** The 134 experiments are defined once, in Python.

## Constraints

- Julia 1.13.2 (juliaup, `release` channel) on Windows 11, i7-13700K (24 threads). Python 3.14.3, numpy 2.5.4.
- The machine is shared: other sessions run Python xl jobs and FLAME GPU tests. The i7-13700K has 8 performance
  and 8 efficiency cores, so development timings can be off by up to about 2× either way; they are labelled, not
  trusted for headline numbers.
- The model package uses the Julia standard library only (Random, Statistics, Printf, TOML, SHA, Distributed,
  Test). Small, so a reader can audit it, and nothing to install beyond Julia.
- Conventions from the user's `julia-pro` skill (my call to adopt them for this code): BlueStyle formatting with
  JuliaFormatter (a developer tool in its own environment, not a dependency of the package), `Project.toml` changed
  only through Pkg, and type stability checked (`@code_warntype`) on the hot paths: movement scans, the step loop,
  diffusion.

## Decisions taken with the user

| Question | Decision |
|---|---|
| What makes the Julia model "the same"? | Matching statistics across seeds |
| Which experiments? | Every sugarscape (`Config`) experiment in the registry |
| Does this project build the comparison? | Yes |
| Python xl runs | II-4 (running), VI-1, IV-A3; several days of machine time is fine |
| Who runs Python | The user, in separate sessions, including the regular registry re-run with timings |
| Speed comparison | One core per seed on each side first; threads within a run later |
| Timing conditions | Uncontrolled during development; the user does quiet-machine runs at the end |
| Agreement rule | As below, accepted as proposed |

## The model in Julia

**Semantics are the Python model's.** The rules, their order within a period, the scan orders, tie-breaks and every
"our call" reading in `sugarscape/` are the specification. The builder ports from the Python source; this document
does not restate the rules. In particular:
- Agents act one at a time, in a fresh uniformly random order each period. Each agent runs its whole rule sequence
  (move or combat, metabolize, then mate, culture, trade, credit and disease, as enabled) before the next one starts,
  and sees the effects of earlier agents. The end of the period is aging, old-age death, loan settlement,
  replacement, growback (or seasons), then diffusion (`Model.step`).
- Every random choice is uniform over the same set as in Python: integer draws from inclusive ranges, permutations
  of neighbours and directions, sampling without replacement for initial placement and initial diseases.
- Configuration validation is the same as `Config.__post_init__`; an invalid config is refused, never silently
  adjusted.

**Free to differ** (none of these change a distribution):
- The random number generator and the order in which draws are taken.
- The order of agents in internal lists. Each period draws a fresh random order, so storage order does not matter.
  Where an internal order does affect an outcome (the order loans are settled in, or the batch of agents dying of
  old age), keep Python's order (creation order) unless doing so is costly, and record any change.
- How a uniform choice is made. For example, replacement may pick an empty site by rejection sampling instead of
  listing all 250,000 sites, as long as the choice stays uniform over the empty sites.
- Data layout. For example, cultural tags or immune strings as bit fields, diseases interned by value, and the grid
  as references to agents. Two diseases with equal bit strings must count as the same disease, as Python's tuple
  equality does (`infect`, `diseases_circulating`).

**Configuration and the registry.** Python stays the single source of truth. A Python exporter writes
`julia/registry.toml`, which is generated and committed. For each `Config` experiment it holds the id, title, rules,
steps, seeds, every `Config` field (a field whose value is `None` is left out), and the text of its regular
fingerprint. For checking only, it also holds the xl configuration and xl fingerprint that `to_xl` produces. A
Python test fails when the file is out of date with the registry. Julia implements `to_xl` itself from docs/xl.md.
A Julia test checks it against the exported xl configs, and Julia computes the xl map's SHA-256 itself for the xl
fingerprint. TOML can express everything a Config holds, including `inf`.

**Maps.** Julia reads `sugarscape/maps/sugar-map.txt` and `sugar-map-xl.txt` directly, with the orientation in
docs/xl.md. Spice is the sugar map mirrored east–west.

## The Julia runner

A command mirroring `python -m experiments.run`:

```
julia --project=julia julia/run.jl <id-or-prefix> [--seeds N] [--jobs J] [--out DIR] [--xl]
```

- The id matching is the same as `experiments.run.matching_ids`. Seed k runs with the registered seed plus k.
- Results go to `results-julia/`, or `results-julia-xl/` with `--xl`, in the Python layout: one folder per
  experiment, with `/` replaced by `_`. Both folders are ignored by git, like `results/`.
- **`seed{k}.csv`** has the same columns, in the same order, as the Python runner's: `t`, then the standard,
  society, economic and disease metrics. Every metric is computed from the same definitions as `sugarscape/stats.py`.
  Values are written so that `experiments.run._read_csv` reads them back: `t` as an integer, `nan` and `inf` spelled
  that way, and floats in a form Python's `float()` parses.
- **`timing.csv`** has the columns `seed, periods, setup_s, stepping_s, metrics_s, agents_start, agents_end`, with
  the meanings in docs/xl.md.
- **`machine.txt`** records the Julia version, platform, processor, jobs and threads per process, with the same
  "timings taken with --jobs J share the processor" note as Python's when J > 1. An optional `--note TEXT` is copied
  into it, so a quiet-machine run can say so (my call; Python's runner has no way to know what other sessions do
  either).
- **`fingerprint.txt`** is `julia\n` followed by the Python fingerprint text for that experiment (regular or xl), as
  the GPU bridge does with `gpu-phase1\n`.
- **One core per seed.** The model runs single-threaded. `--jobs J` runs seeds in J separate worker processes, one
  seed at a time each, so garbage collection in one seed never pauses another.
- **Warm-up (my call).** Julia compiles on first use, which would load several seconds into the first seed's
  timing, far more than Python's 0.06 s import warm-up. So each worker first runs the experiment's regular-size
  configuration for 2 untimed periods. `machine.txt` says so and records how long the warm-up took. The timed setup
  then covers building the model, as docs/xl.md defines it.

## The comparison

The tooling is Python, in `julia/bridge/` (my call, mirroring `flamegpu/bridge/`). It runs from `julia/` as
`python -m bridge.<tool>`, with a `paths.py` that puts the repository root on `sys.path`. It reuses
`experiments.run` (loading results, fingerprints), `replication.targets` and `replication.report.evaluate`. It adds
no new Python dependency. The Welch test's p-value comes from a small Student-t CDF written here and tested against
known values (no scipy).

**Inputs.** Python results from `results/` and `results-xl/`, and Julia results from `results-julia/` and
`results-julia-xl/`. The report never runs anything. It compares what is there and lists each experiment whose
results are missing, stale by fingerprint, or untimed on either side. The Julia side is stale when its
`fingerprint.txt` is not `julia\n` plus the current Python fingerprint.

**Book targets (regular only).** Both sides are scored with `replication.report.evaluate` against
`replication.targets.TARGETS`. The report lists every target whose pass/near/fail status differs between Python and
Julia, as `flamegpu/bridge/gpu_report.py` does.

**Statistical agreement (the rule, accepted by the user).**
- *Which metrics:* every metric column, except one that is all NaN, or constant, on both sides for that experiment.
- *Per-seed summaries:* the periods 0..steps are cut into four equal windows. A seed's value for a window is its
  mean of the metric over that window, ignoring NaN. A seed with no number in a window is left out of that test.
- *Too few values (my call):* a window with fewer than two seed values on either side, which happens after
  extinctions (VI-1 died out in 3 of 5 Python seeds; VI-2, III-5 and their variants are about extinction), is not
  tested and not flagged. The report lists it as untestable. Extinction itself is tested instead: for each
  experiment, the number of seeds with no agents at the last period, Julia against Python, by Fisher's exact test,
  with its p-value in the same Benjamini–Hochberg correction.
- *Test:* for each (experiment, metric, window), a Welch t-test between Julia's and Python's seed values. The
  p-values of all tests in one report are corrected together with Benjamini–Hochberg at q = 0.01, and a test that
  survives is **flagged**. Every flag is reported with the difference of means, in the metric's units and in units
  of Python's seed standard deviation. A window whose values are identical on both sides is not a difference; a
  window that is constant on each side but different between them is always flagged.
- *Seeds:* Julia runs the registered number of seeds, the same as Python.
- *Verdict:* Julia agrees with Python when nothing is flagged and no target status changes. Each flag or status
  change is either fixed as a bug in Julia or explained in the write-up, the way the GPU page explains its +7%
  mean neighbours.

**Speed.** From each side's `timing.csv`, per experiment: mean setup seconds, stepping seconds per period, metrics
seconds per period, agents at start and end, and the Julia/Python ratio of stepping per period. One table for
regular size (all experiments, plus a summary such as the median ratio) and one for xl (the three experiments).
Every row carries its `machine.txt` jobs and note, and the table says that development timings are uncontrolled.
An experiment whose Python side has no `timing.csv` shows Julia only. The full Julia xl registry (below) adds a
Julia-only xl speed table.

**Output.** `results-julia/REPORT.md` for regular size and `results-julia-xl/REPORT.md` for xl, written by
`python -m bridge.report [--xl]`. The write-up goes in `julia/README.md`, with the method and the results, as
`flamegpu/README.md` does for the GPU.

## Testing

- **Rule-level unit tests in Julia** (`julia/test/`, Test stdlib) for every rule family: movement and harvest,
  metabolism and death, growback and seasons, pollution and diffusion, replacement, sex and inheritance, culture
  and friends, combat, trade and welfare, credit, disease, the metrics, config validation, map loading and
  orientation, and `to_xl`. The Python test files under `tests/` are the checklist. Each deterministic assertion
  there gets a Julia counterpart; assertions that depend on numpy's stream are restated as properties.
- **Cross-language scenarios.** Small states built so that the agents' order and the random draws cannot change
  the result, as in `flamegpu/tests/test_parity.py`: distinct capacities, agents farther apart than anyone sees,
  one possible partner. A Python script in `julia/bridge/` runs each scenario through the Python model and writes
  the expected state to committed TOML fixtures. The Julia tests compare against those fixtures and need no Python
  at test time. Cover movement, combat, trade, credit, inheritance, pollution and diffusion, and seasons, plus
  anything else where a scenario can be made order-free.
- **Runner and output.** Julia writes CSVs that `experiments.run._read_csv` reads back, with the same columns in the
  same order (a Python test in `julia/bridge/tests`, run against a tiny Julia run).
- **Bridge tests** (pytest) for the exporter staying current, the Welch p-value and Benjamini–Hochberg against known
  values, the metric-eligibility rule, and the report on fabricated result folders.
- The repository's own Python test suite stays green.

## Order of work (suggested)

1. Exporter and `registry.toml`; the Julia package skeleton, config and validation, maps, `to_xl`.
2. The model, Chapter II rules first, then III, IV, V. Each chapter is checked against Python results with the
   agreement rule on its experiments before the next one starts, so differences are found while the code is fresh.
3. The runner and its outputs; the report.
4. Full regular comparison, the xl comparison of II-4, VI-1 and IV-A3, speed tables, write-up.
5. **The full Julia xl registry (my call: last, and not a gate).** It is about 100× the regular agent-periods
   (III-8 and III-15 run 6000 periods; the VAR- reproduction runs 1500–2500), and competes for the machine with the
   Python xl runs. It runs after the comparison and write-up, as a background job. It feeds only the Julia-only xl
   speed table and a sanity check that every experiment runs at xl.

## Left to the builder

- Data structures and file layout inside `julia/src`, as long as the semantics above hold and the hot paths are
  type-stable.
- How worker processes are started (Distributed or separate `julia` processes), and the exact warm-up mechanics,
  within the rules above.
- How many jobs to use for the Julia runs, given what else is running on the machine.
- Keeping VI-2 and VI-3's paired seeds meaningful: p.159 starts both runs from the identical society, and the VI-3
  target divides by VI-2 seed by seed. In Julia, as in Python, the trade setting must not change any draw made
  while building the model.
- The exact formatting of REPORT.md.
