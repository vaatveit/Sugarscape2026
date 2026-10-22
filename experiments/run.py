"""Run registered experiments over several seeds; write one CSV per seed plus a summary plot.

Usage: python -m experiments.run <id-or-prefix> [--seeds N] [--jobs J] [--out DIR]
A prefix such as "II-5" runs every id of the form "II-5/...".
"""

import argparse
import csv
import math
import warnings
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
from pathlib import Path

import numpy as np
from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.stats import disease_metrics, economic_metrics, society_metrics, standard_metrics
from sugarscape.variants.ringworld import RingConfig, RingModel, ring_metrics
from sugarscape.variants.schelling import SchellingConfig, SchellingModel, schelling_metrics

Series = list[dict[str, float]]
PLOTTED = ("population", "gini", "mean_vision", "mean_metabolism")


def sugarscape_metrics(m: Model) -> dict[str, float]:
    return {**standard_metrics(m), **society_metrics(m), **economic_metrics(m), **disease_metrics(m)}


# Each kind of config: the model it builds, the metrics recorded each period, and the plotted ones.
KINDS = {
    Config: (Model, sugarscape_metrics, PLOTTED),
    SchellingConfig: (SchellingModel, schelling_metrics, ("like_fraction", "fraction_satisfied", "moved", "population")),
    RingConfig: (RingModel, ring_metrics, ("mean_group_size", "largest_group", "clustered_fraction", "speed_ratio")),
}


def result_dir(exp_id: str, out_dir: Path) -> Path:
    return Path(out_dir) / exp_id.replace("/", "_")


def fingerprint(exp_id: str) -> str:
    """The settings that produced an experiment's results (rules, Config, steps).

    Covers settings, not code: after a model change, re-run with --rerun.
    """
    exp = EXPERIMENTS[exp_id]
    return f"{exp.rules}\nsteps={exp.steps}\n{exp.config!r}\n"


def results_current(exp_id: str, out_dir: Path = Path("results")) -> bool:
    """True when saved results exist for every seed and match the experiment's current settings."""
    folder = result_dir(exp_id, out_dir)
    fp = folder / "fingerprint.txt"
    if not fp.exists() or fp.read_text(encoding="utf-8") != fingerprint(exp_id):
        return False
    return len(list(folder.glob("seed*.csv"))) >= EXPERIMENTS[exp_id].seeds


def run_seed(exp_id: str, seed_index: int) -> Series:
    exp = EXPERIMENTS[exp_id]
    make_model, metrics, _ = KINDS[type(exp.config)]
    model = make_model(replace(exp.config, seed=exp.config.seed + seed_index))
    series: Series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **metrics(m)}))
    return series


def run_experiment(
    exp_id: str, seeds: int | None = None, jobs: int = 1, out_dir: Path = Path("results")
) -> list[Series]:
    n = seeds if seeds is not None else EXPERIMENTS[exp_id].seeds
    if jobs > 1:
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            runs = list(pool.map(run_seed, [exp_id] * n, range(n)))
    else:
        runs = [run_seed(exp_id, k) for k in range(n)]
    folder = result_dir(exp_id, out_dir)
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("seed*.csv"):
        old.unlink()
    for k, series in enumerate(runs):
        _write_csv(folder / f"seed{k}.csv", series)
    (folder / "fingerprint.txt").write_text(fingerprint(exp_id), encoding="utf-8")
    _plot(exp_id, runs, folder / "summary.png")
    return runs


def load_results(exp_id: str, out_dir: Path = Path("results")) -> list[Series]:
    folder = result_dir(exp_id, out_dir)
    files = sorted(folder.glob("seed*.csv"), key=lambda p: int(p.stem[4:]))
    return [_read_csv(p) for p in files]


def matching_ids(arg: str, ids) -> list[str]:
    ids = list(ids)
    if arg in ids:
        return [arg]
    return [i for i in ids if i.startswith(arg + "/")]


def _write_csv(path: Path, series: Series) -> None:
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(series[0]))
        writer.writeheader()
        for row in series:
            writer.writerow({k: repr(v) for k, v in row.items()})


def _parse(text: str) -> float:
    # math.nan is a single object, so rows read back compare equal to freshly computed ones.
    return math.nan if text == "nan" else (int(text) if text.lstrip("-").isdigit() else float(text))


def _read_csv(path: Path) -> Series:
    with path.open(newline="") as f:
        return [{k: _parse(v) for k, v in row.items()} for row in csv.DictReader(f)]


def _plot(exp_id: str, runs: list[Series], path: Path) -> None:
    exp = EXPERIMENTS[exp_id]
    fig = Figure(figsize=(10, 7))
    for i, metric in enumerate(KINDS[type(exp.config)][2]):
        ax = fig.add_subplot(2, 2, i + 1)
        for series in runs:
            ax.plot([r["t"] for r in series], [r[metric] for r in series], color="0.75", lw=0.8)
        with warnings.catch_warnings():  # periods where every seed is nan plot as gaps
            warnings.simplefilter("ignore", RuntimeWarning)
            mean = np.nanmean([[r[metric] for r in s] for s in runs], axis=0)
        ax.plot([r["t"] for r in runs[0]], mean, color="C0", lw=1.6)
        ax.set_title(metric)
        ax.set_xlabel("t")
    fig.suptitle(f"{exp.id}: {exp.title}  {exp.rules}  ({len(runs)} seeds)")
    fig.tight_layout()
    fig.savefig(path, dpi=90)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("id")
    parser.add_argument("--seeds", type=int, default=None)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--out", type=Path, default=Path("results"))
    args = parser.parse_args(argv)
    ids = matching_ids(args.id, EXPERIMENTS)
    if not ids:
        parser.error(f"no experiment matches {args.id!r}")
    for exp_id in ids:
        runs = run_experiment(exp_id, args.seeds, args.jobs, args.out)
        print(f"{exp_id}: {len(runs)} seeds -> {result_dir(exp_id, args.out)}")


if __name__ == "__main__":
    main()
