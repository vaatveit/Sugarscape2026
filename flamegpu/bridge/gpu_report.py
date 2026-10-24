"""Score GPU and Python results against the same book targets and write <gpu dir>/REPORT.md.

Usage: python -m bridge.gpu_report [--chapter II] [--gpu DIR] [--python DIR]
Python results are read from the Python project's results/ folder and never re-run.
"""

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

from bridge.gpu_run import GPU_FINGERPRINT
from bridge.paths import SUGARSCAPE_ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import fingerprint, load_results, result_dir, results_current
from replication.report import Result, _fmt, evaluate
from replication.targets import TARGETS, Target


@dataclass
class Comparison:
    target: Target
    gpu: Result | None
    py: Result | None
    py_stale: bool
    gpu_stale: bool = False


def gpu_current(exp_id: str, gpu_dir: Path) -> bool:
    """GPU results match the experiment's current settings and hold every registered seed (as results_current)."""
    folder = result_dir(exp_id, gpu_dir)
    fp = folder / "fingerprint.txt"
    if not fp.exists() or fp.read_text(encoding="utf-8") != GPU_FINGERPRINT + fingerprint(exp_id):
        return False
    return len(list(folder.glob("seed*.csv"))) >= EXPERIMENTS[exp_id].seeds


def _load(exp_id: str, folder: Path, cache: dict) -> list | None:
    key = (exp_id, str(folder))
    if key not in cache:
        has_runs = result_dir(exp_id, folder).is_dir() and any(result_dir(exp_id, folder).glob("seed*.csv"))
        cache[key] = load_results(exp_id, folder) if has_runs else None
    return cache[key]


def _score(target: Target, folder: Path, cache: dict) -> Result | None:
    runs = _load(target.experiment, folder, cache)
    if runs is None:
        return None
    baseline = None
    if target.baseline:
        baseline = _load(target.baseline, folder, cache)
        if baseline is None:
            return None
    return evaluate(target, runs, baseline)


def compare(targets, gpu_dir: Path, py_dir: Path) -> list[Comparison]:
    cache: dict = {}
    rows = []
    for t in targets:
        py = _score(t, Path(py_dir), cache)
        stale = py is not None and not results_current(t.experiment, Path(py_dir))
        gpu = _score(t, Path(gpu_dir), cache)
        gpu_stale = gpu is not None and not gpu_current(t.experiment, Path(gpu_dir))
        rows.append(Comparison(t, gpu, py, stale, gpu_stale))
    return rows


def _observed(r: Result | None) -> str:
    if r is None:
        return "not run"
    return f"{_fmt(r.observed_mean)} [{_fmt(r.observed_min)}–{_fmt(r.observed_max)}]"


def _counts(results: list[Result | None]) -> str:
    present = [r for r in results if r is not None]
    parts = [f"{sum(r.status == s for r in present)} {s}" for s in ("pass", "near", "fail")]
    return ", ".join(parts) + f", {len(results) - len(present)} not run"


def write_comparison(rows: list[Comparison], path: Path) -> None:
    lines = [
        "# GPU vs Python replication report",
        "",
        f"Python: {_counts([r.py for r in rows])}.  ",
        f"GPU: {_counts([r.gpu for r in rows])}.",
        "",
        "| Experiment | Target | Book | Band | Python mean [min–max] | Python | GPU mean [min–max] | GPU | GPU − Python |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        t = r.target
        name = f"{t.name} (proxy)" if t.proxy else t.name
        py_status = "—" if r.py is None else r.py.status + (" (stale)" if r.py_stale else "")
        gpu_status = "—" if r.gpu is None else r.gpu.status + (" (stale)" if r.gpu_stale else "")
        diff = math.nan if r.py is None or r.gpu is None else r.gpu.observed_mean - r.py.observed_mean
        lines.append(f"| {t.experiment} | {name} | {t.source} {_fmt(t.book_value)} | {_fmt(t.low)}–{_fmt(t.high)} | "
                     f"{_observed(r.py)} | {py_status} | {_observed(r.gpu)} | {gpu_status} | {_fmt(diff)} |")
    changes = [r for r in rows if r.py is not None and r.gpu is not None and r.py.status != r.gpu.status]
    lines += ["", "## Status changes", ""]
    lines += [f"- {r.target.experiment} {r.target.name}: Python {r.py.status} → GPU {r.gpu.status} "
              f"(Python {_fmt(r.py.observed_mean)}, GPU {_fmt(r.gpu.observed_mean)}, band "
              f"{_fmt(r.target.low)}–{_fmt(r.target.high)})" for r in changes] or ["None."]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--chapter", default="II", help="e.g. II: only that chapter's targets")
    parser.add_argument("--gpu", type=Path, default=Path("results-gpu"))
    parser.add_argument("--python", type=Path, default=SUGARSCAPE_ROOT / "results")
    args = parser.parse_args(argv)
    targets = [t for t in TARGETS if t.experiment.startswith(args.chapter + "-")]
    rows = compare(targets, args.gpu, args.python)
    write_comparison(rows, args.gpu / "REPORT.md")
    print(f"wrote {args.gpu / 'REPORT.md'}: {len(rows)} targets; Python {_counts([r.py for r in rows])}; "
          f"GPU {_counts([r.gpu for r in rows])}")


if __name__ == "__main__":
    main()
