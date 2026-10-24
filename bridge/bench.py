"""Scaling benchmark: II-4's rules on the 50x50 map tiled K x K at the book's density, GPU against Python.

Usage: python -m bridge.bench [--tiles 1,2,5,10,25,50] [--steps 500] [--timing-steps 200]
                              [--python-tiles 1,2,4] [--python-steps 50] [--out results-gpu]
Writes <out>/bench.csv and <out>/bench.png. The GPU runs use the seatbelts-off build (build-fast).
"""

import argparse
import csv
import json
import math
import subprocess
import time
from dataclasses import replace
from pathlib import Path

import numpy as np
from matplotlib.figure import Figure

from bridge.config_cfg import config_to_cfg
from bridge.paths import FAST_EXE, subprocess_env
from experiments.registry import EXPERIMENTS
from experiments.run import _read_csv
from replication.targets import window_mean
from sugarscape.maps import load_map
from sugarscape.model import Model

COLUMNS = ("engine", "tile", "cells", "agents_initial", "steps", "step_seconds_mean", "population_per_tile_450_500")
EXPERIMENT = "II-4"


def _gpu(exe: Path, folder: Path, k: int, steps: int, timing_steps: int) -> dict:
    folder.mkdir(parents=True, exist_ok=True)
    cfg = EXPERIMENTS[EXPERIMENT].config
    env = subprocess_env()

    def run(name: str, n: int, *extra) -> None:
        path = folder / f"{name}.cfg"
        path.write_text(config_to_cfg(cfg, steps=n, seed=cfg.seed), encoding="utf-8")
        result = subprocess.run([str(exe), "--config", str(path), "--tile", str(k), *map(str, extra)],
                                capture_output=True, text=True, env=env)
        if result.returncode != 0:
            raise RuntimeError(f"tile {k} {name}: exit {result.returncode}: {result.stderr.strip()}")

    # Timing without metrics, so per-period copies of the agents do not count; then a run for the population check.
    run("timing", timing_steps, "--timing", folder / "timing.json")
    timing = json.loads((folder / "timing.json").read_text())
    run("population", steps, "--out", folder / "metrics.csv", "--metrics-every", 50)
    population = window_mean("population", 450, 500)(_read_csv(folder / "metrics.csv"))
    return {"engine": "gpu", "tile": k, "cells": timing["cells"], "agents_initial": timing["agents_initial"],
            "steps": timing["steps"], "step_seconds_mean": timing["step_seconds_mean"],
            "population_per_tile_450_500": population / (k * k)}


def _python(k: int, steps: int) -> dict:
    base = EXPERIMENTS[EXPERIMENT].config
    cfg = replace(base, width=base.width * k, height=base.height * k, initial_population=base.initial_population * k * k)
    model = Model(cfg, capacity=np.tile(load_map(base.sugar_map), (k, k)))
    start = time.perf_counter()
    for _ in range(steps):
        model.step()
    seconds = (time.perf_counter() - start) / steps
    return {"engine": "python", "tile": k, "cells": cfg.width * cfg.height, "agents_initial": cfg.initial_population,
            "steps": steps, "step_seconds_mean": seconds, "population_per_tile_450_500": math.nan}


def _plot(rows: list[dict], path: Path) -> None:
    fig = Figure(figsize=(11, 4.5))
    ax = fig.add_subplot(1, 2, 1)
    for engine, color in (("gpu", "C0"), ("python", "C1")):
        pts = sorted((r["agents_initial"], r["step_seconds_mean"]) for r in rows if r["engine"] == engine)
        if pts:
            ax.plot(*zip(*pts), "o-", color=color, label=engine.upper() if engine == "gpu" else "Python")
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("initial agents")
    ax.set_ylabel("seconds per period")
    ax.set_title("Step time, II-4 rules on a tiled sugarscape")
    ax.legend()
    ax2 = fig.add_subplot(1, 2, 2)
    gpu = sorted((r["tile"], r["population_per_tile_450_500"]) for r in rows if r["engine"] == "gpu")
    if gpu:
        ax2.plot(*zip(*gpu), "o-", color="C0")
    ax2.axhspan(205, 245, color="0.9", label="II-4 band (205–245)")
    ax2.set_xscale("log")
    ax2.set_xlabel("tiles per side (K)")
    ax2.set_ylabel("population per 50x50 tile, t = 450–500")
    ax2.set_title("Carrying capacity per tile")
    ax2.legend()
    fig.tight_layout()
    fig.savefig(path, dpi=110)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tiles", default="1,2,5,10,25,50")
    parser.add_argument("--steps", type=int, default=500)
    parser.add_argument("--timing-steps", type=int, default=200)
    parser.add_argument("--python-tiles", default="1,2,4")
    parser.add_argument("--python-steps", type=int, default=50)
    parser.add_argument("--out", type=Path, default=Path("results-gpu"))
    parser.add_argument("--exe", type=Path, default=FAST_EXE)
    args = parser.parse_args(argv)
    rows = []
    for k in (int(v) for v in args.tiles.split(",") if v):
        rows.append(_gpu(args.exe, args.out / "bench" / f"tile{k}", k, args.steps, args.timing_steps))
        print(f"gpu tile {k}: {rows[-1]['step_seconds_mean'] * 1e3:.2f} ms/period, "
              f"{rows[-1]['population_per_tile_450_500']:.1f} per tile", flush=True)
    for k in (int(v) for v in args.python_tiles.split(",") if v):
        rows.append(_python(k, args.python_steps))
        print(f"python tile {k}: {rows[-1]['step_seconds_mean'] * 1e3:.2f} ms/period", flush=True)
    args.out.mkdir(parents=True, exist_ok=True)
    with (args.out / "bench.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    _plot(rows, args.out / "bench.png")
    print(f"wrote {args.out / 'bench.csv'} and {args.out / 'bench.png'}")


if __name__ == "__main__":
    main()
