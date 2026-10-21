"""Evaluate book targets against experiment results and write results/REPORT.md.

Usage: python -m replication.report [--chapter II] [--rerun] [--jobs J] [--out DIR]
"""

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from experiments.registry import EXPERIMENTS
from experiments.run import load_results, run_experiment
from replication.targets import TARGETS, Series, Target


@dataclass(frozen=True)
class Result:
    target: Target
    observed_mean: float
    observed_min: float
    observed_max: float
    status: str  # "pass" | "near" | "fail"


def evaluate(target: Target, runs: list[Series]) -> Result:
    """pass: mean within [low, high]; near: within the band widened by half its width each side."""
    values = [v for v in (target.statistic(s) for s in runs) if not math.isnan(v)]
    if not values:
        return Result(target, math.nan, math.nan, math.nan, "fail")
    mean = float(np.mean(values))
    half = (target.high - target.low) / 2
    if target.low <= mean <= target.high:
        status = "pass"
    elif target.low - half <= mean <= target.high + half:
        status = "near"
    else:
        status = "fail"
    return Result(target, mean, float(min(values)), float(max(values)), status)


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
        "| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Status |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in results:
        t = r.target
        name = f"{t.name} (proxy)" if t.proxy else t.name
        observed = f"{_fmt(r.observed_mean)} [{_fmt(r.observed_min)}–{_fmt(r.observed_max)}]"
        lines.append(
            f"| {t.experiment} | {name} | {t.source} | {_fmt(t.book_value)} | "
            f"{_fmt(t.low)}–{_fmt(t.high)} | {observed} | {r.status} |"
        )
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_or_run(exp_id: str, out_dir: Path = Path("results"), jobs: int = 1, rerun: bool = False) -> list[Series]:
    """Saved results when every seed's CSV exists, else a fresh run."""
    if not rerun:
        runs = load_results(exp_id, out_dir)
        if len(runs) >= EXPERIMENTS[exp_id].seeds:
            return runs
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
        if t.experiment not in cache:
            cache[t.experiment] = load_or_run(t.experiment, args.out, args.jobs, args.rerun)
            print(f"{t.experiment}: {len(cache[t.experiment])} seeds", flush=True)
        results.append(evaluate(t, cache[t.experiment]))
    write_report(results, args.out / "REPORT.md")
    print(f"wrote {args.out / 'REPORT.md'}")


if __name__ == "__main__":
    main()
