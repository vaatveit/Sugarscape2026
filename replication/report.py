"""Evaluate book targets against experiment results and write results/REPORT.md.

Usage: python -m replication.report [--chapter II] [--rerun] [--jobs J] [--out DIR]
"""

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from experiments.registry import EXPERIMENTS
from experiments.run import load_results, results_current, run_experiment
from replication.targets import TARGETS, Series, Target


@dataclass(frozen=True)
class Result:
    target: Target
    observed_mean: float
    observed_min: float
    observed_max: float
    status: str  # "pass" | "near" | "fail"
    n_valid: int = 0  # seeds whose statistic is a number
    n_runs: int = 0


def _per_seed(target: Target, runs: list[Series], baseline_runs: list[Series] | None) -> list[float]:
    """The target's statistic per seed; with a baseline, its ratio to the statistic on the baseline
    experiment's seed of the same index (seeds pair by index, the shorter list sets the count)."""
    if target.baseline is None:
        return [target.statistic(s) for s in runs]
    values = []
    for run, base in zip(runs, baseline_runs or []):
        num, den = target.statistic(run), target.statistic(base)
        values.append(math.nan if den == 0 or math.isnan(den) else num / den)
    return values


def evaluate(target: Target, runs: list[Series], baseline_runs: list[Series] | None = None) -> Result:
    """pass: mean within [low, high]; near: within the band widened by half its width each side.

    Seeds whose statistic is nan (e.g. extinct at the sampled time) cannot pass: any nan seed caps
    the status at "near", and fewer than half valid seeds is a "fail".
    """
    per_seed = _per_seed(target, runs, baseline_runs)
    values = [v for v in per_seed if not math.isnan(v)]
    n_valid, n_runs = len(values), len(per_seed)
    if n_valid == 0 or n_valid * 2 < n_runs:
        stats = (float(np.mean(values)), float(min(values)), float(max(values))) if values else (math.nan,) * 3
        return Result(target, *stats, "fail", n_valid, n_runs)
    mean = float(np.mean(values))
    half = (target.high - target.low) / 2
    if target.low <= mean <= target.high:
        status = "pass"
    elif target.low - half <= mean <= target.high + half:
        status = "near"
    else:
        status = "fail"
    if status == "pass" and n_valid < n_runs:
        status = "near"
    return Result(target, mean, float(min(values)), float(max(values)), status, n_valid, n_runs)


def _fmt(v: float | None) -> str:
    return "—" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.4g}"


def write_report(results: list[Result], path: Path) -> None:
    lines = [
        "# Replication report",
        "",
        f"{sum(r.status == 'pass' for r in results)} pass, "
        f"{sum(r.status == 'near' for r in results)} near, "
        f"{sum(r.status == 'fail' for r in results)} fail, of {len(results)} targets.",
        "",
        "| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for r in results:
        t = r.target
        name = f"{t.name} (proxy)" if t.proxy else t.name
        if t.baseline:
            name = f"{name} (vs {t.baseline})"
        observed = f"{_fmt(r.observed_mean)} [{_fmt(r.observed_min)}–{_fmt(r.observed_max)}]"
        lines.append(
            f"| {t.experiment} | {name} | {t.source} | {_fmt(t.book_value)} | "
            f"{_fmt(t.low)}–{_fmt(t.high)} | {observed} | {r.n_valid}/{r.n_runs} | {r.status} |"
        )
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_or_run(exp_id: str, out_dir: Path = Path("results"), jobs: int = 1, rerun: bool = False) -> list[Series]:
    """Saved results when they were produced by the experiment's current settings, else a fresh run."""
    if not rerun and results_current(exp_id, out_dir):
        return load_results(exp_id, out_dir)
    return run_experiment(exp_id, jobs=jobs, out_dir=out_dir)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--chapter", default=None, help="e.g. II: only that chapter's targets")
    parser.add_argument("--rerun", action="store_true")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--out", type=Path, default=Path("results"))
    args = parser.parse_args(argv)
    targets = [t for t in TARGETS if args.chapter is None or t.experiment.startswith(args.chapter + "-")]
    cache: dict[str, list[Series]] = {}
    results = []
    for t in targets:
        for exp_id in filter(None, (t.experiment, t.baseline)):
            if exp_id not in cache:
                cache[exp_id] = load_or_run(exp_id, args.out, args.jobs, args.rerun)
                print(f"{exp_id}: {len(cache[exp_id])} seeds", flush=True)
        results.append(evaluate(t, cache[t.experiment], cache[t.baseline] if t.baseline else None))
    write_report(results, args.out / "REPORT.md")
    print(f"wrote {args.out / 'REPORT.md'}")


if __name__ == "__main__":
    main()
