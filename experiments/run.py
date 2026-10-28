"""Run registered experiments over several seeds; write one CSV per seed plus a summary plot.

Usage: python -m experiments.run <id-or-prefix> [--seeds N] [--jobs J] [--out DIR] [--xl]
A prefix such as "II-5" runs every id of the form "II-5/...". --xl runs the 500x500 version (docs/xl.md) into
results-xl/. Each run also writes timing.csv and machine.txt.
"""

import argparse
import csv
import hashlib
import math
import platform
import sys
import time
import warnings
from concurrent.futures import ProcessPoolExecutor
from dataclasses import fields, replace
from importlib import resources
from pathlib import Path

import numpy as np
from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.maps.xl import XL_MAP
from sugarscape.model import Model
from sugarscape.stats import disease_metrics, economic_metrics, society_metrics, standard_metrics
from sugarscape.variants.ringworld import RingConfig, RingModel, ring_metrics
from sugarscape.variants.schelling import SchellingConfig, SchellingModel, schelling_metrics
from sugarscape.xl import to_xl

Series = list[dict[str, float]]
# Per-seed wall-clock time, in seconds (docs/xl.md, "Timing"): building the model, the model's own steps, and the
# runner's metrics collection, which the model doesn't do.
TIMING_COLUMNS = ("seed", "periods", "setup_s", "stepping_s", "metrics_s", "agents_start", "agents_end")
XL_OUT = Path("results-xl")  # xl results never mix with the regular results/
# 2026-10-26: xl looks are centred on each stride (docs/xl.md, "Looking"), so xl results made before are stale. It
# leads the xl fingerprint, where the GPU port wrote it before Python did, so the GPU's xl results stay current.
XL_LOOK = "look: centred\n"
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


def experiment_config(exp_id: str, xl: bool = False):
    """An experiment's registered config, or its xl version (docs/xl.md); xl is for the sugarscape world only."""
    cfg = EXPERIMENTS[exp_id].config
    if not xl:
        return cfg
    if not isinstance(cfg, Config):
        raise ValueError(f"xl applies to sugarscape experiments, not {type(cfg).__name__} ({exp_id})")
    return to_xl(cfg)


def fingerprint(exp_id: str, xl: bool = False) -> str:
    """The settings that produced an experiment's results (rules, Config, steps; for xl, also the look rule and the
    map's checksum).

    Covers settings, not code: after a model change, re-run with --rerun.
    """
    exp = EXPERIMENTS[exp_id]
    cfg = experiment_config(exp_id, xl)
    # Config fields left out of repr (rule S's labelled departures) count only when they leave their defaults.
    hidden = "".join(f"{f.name}={getattr(cfg, f.name)!r}\n" for f in fields(cfg)
                     if not f.repr and getattr(cfg, f.name) != f.default)
    text = f"{exp.rules}\nsteps={exp.steps}\n{cfg!r}\n{hidden}"
    if xl:  # the map file is data the config only names, so a regenerated map makes xl results stale
        data = resources.files("sugarscape.maps").joinpath(XL_MAP).read_bytes()
        text = XL_LOOK + text + f"xl map sha256={hashlib.sha256(data).hexdigest()}\n"
    return text


def default_out(xl: bool) -> Path:
    return XL_OUT if xl else Path("results")


def results_current(exp_id: str, out_dir: Path | None = None, xl: bool = False) -> bool:
    """True when saved results exist for every seed and match the experiment's current settings."""
    folder = result_dir(exp_id, out_dir if out_dir is not None else default_out(xl))
    fp = folder / "fingerprint.txt"
    if not fp.exists() or fp.read_text(encoding="utf-8") != fingerprint(exp_id, xl):
        return False
    return len(list(folder.glob("seed*.csv"))) >= EXPERIMENTS[exp_id].seeds


def timed_seed(exp_id: str, seed_index: int, xl: bool = False) -> tuple[Series, dict]:
    """Run k of an experiment (or its xl version), as `Model.run` would, timing setup, stepping and metrics."""
    exp = EXPERIMENTS[exp_id]
    cfg = experiment_config(exp_id, xl)
    make_model, metrics, _ = KINDS[type(cfg)]
    clock = time.perf_counter
    start = clock()
    model = make_model(replace(cfg, seed=cfg.seed + seed_index))
    setup = clock() - start
    agents_start = len(model.agents)
    series: Series = []
    stepping = measuring = 0.0
    for period in range(exp.steps + 1):
        if period:
            start = clock()
            model.step()
            stepping += clock() - start
        start = clock()
        series.append({"t": model.t, **metrics(model)})
        measuring += clock() - start
    timing = {"seed": seed_index, "periods": exp.steps, "setup_s": setup, "stepping_s": stepping,
              "metrics_s": measuring, "agents_start": agents_start, "agents_end": len(model.agents)}
    return series, timing


def run_seed(exp_id: str, seed_index: int, xl: bool = False) -> Series:
    return timed_seed(exp_id, seed_index, xl)[0]


def run_experiment(
    exp_id: str, seeds: int | None = None, jobs: int = 1, out_dir: Path | None = None, xl: bool = False
) -> list[Series]:
    """Run and save every seed; out_dir defaults to results/, or results-xl/ for xl."""
    experiment_config(exp_id, xl)  # refuse xl for other worlds before starting any work
    n = seeds if seeds is not None else EXPERIMENTS[exp_id].seeds
    if out_dir is None:
        out_dir = default_out(xl)
    if jobs > 1:
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            results = list(pool.map(timed_seed, [exp_id] * n, range(n), [xl] * n))
    else:
        results = [timed_seed(exp_id, k, xl) for k in range(n)]
    runs = [series for series, _ in results]
    folder = result_dir(exp_id, out_dir)
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("seed*.csv"):
        old.unlink()
    for k, series in enumerate(runs):
        _write_csv(folder / f"seed{k}.csv", series)
    (folder / "fingerprint.txt").write_text(fingerprint(exp_id, xl), encoding="utf-8")
    _write_csv(folder / "timing.csv", [timing for _, timing in results])
    _write_machine_note(folder / "machine.txt", jobs)
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


def _write_machine_note(path: Path, jobs: int) -> None:
    """Where and how the timings were taken."""
    lines = [f"python = {sys.version.split()[0]}", f"numpy = {np.__version__}", f"platform = {platform.platform()}",
             f"processor = {platform.processor() or 'unknown'}", f"jobs = {jobs}"]
    if jobs > 1:
        lines.append(f"note = timings taken with --jobs {jobs} share the processor")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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
    parser.add_argument("--out", type=Path, default=None, help="default: results/, or results-xl/ with --xl")
    parser.add_argument("--xl", action="store_true", help="run the 500x500 xl version (docs/xl.md)")
    args = parser.parse_args(argv)
    ids = matching_ids(args.id, EXPERIMENTS)
    if not ids:
        parser.error(f"no experiment matches {args.id!r}")
    out = args.out if args.out is not None else default_out(args.xl)
    for exp_id in ids:
        try:
            experiment_config(exp_id, args.xl)
        except ValueError as e:
            parser.error(str(e))
    for exp_id in ids:
        runs = run_experiment(exp_id, args.seeds, args.jobs, out, xl=args.xl)
        print(f"{exp_id}: {len(runs)} seeds -> {result_dir(exp_id, out)}")


if __name__ == "__main__":
    main()
