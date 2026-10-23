"""Fit C1+C3's fertility threshold (README next step: C1 with cheaper children at a lower fitted threshold).

The protocol of the 0.83 default (Chapter III record, "Calibrated reproduction variant"): fitted to one number only,
III-1's steady population (target 500: the mean over t=500-2500, the registry's 5 seeds), and frozen in
candidates.FITTED before any other run. candidates.py then validates the frozen value as variant C1+C3fit on every
population figure. Diagnostic only: nothing here changes the model.

Usage: fit_c1c3.py [theta,...] [jobs]    (default grid 1.0, 0.9, ..., 0.5)
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from candidates import make_mate
from experiments.registry import EXPERIMENTS
from experiments.run import sugarscape_metrics
from replication.targets import TARGETS
from sugarscape.model import Model
from sugarscape.rules import sex

STEADY = next(t for t in TARGETS if t.experiment == "III-1" and t.name == "steady population")


def run(args):
    theta, k = args
    sex.mate = make_mate("vision", "ascape", "redraw")  # C1+C3; worker processes are reused: set it every time
    exp = EXPERIMENTS["III-1"]
    model = Model(replace(exp.config, fertility_threshold=theta, seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return theta, k, STEADY.statistic(series)


if __name__ == "__main__":
    grid = [float(x) for x in sys.argv[1].split(",")] if len(sys.argv) > 1 else [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    seeds = EXPERIMENTS["III-1"].seeds
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, [(theta, k) for theta in grid for k in range(seeds)]))
    print(f"C1+C3, III-1 steady population (target {STEADY.book_value:g}, band {STEADY.low:g}-{STEADY.high:g}), "
          f"{seeds} seeds")
    for theta in grid:
        values = [v for th, _, v in done if th == theta]
        print(f"  theta {theta:g}: {np.nanmean(values):.0f}  (seeds: {', '.join(f'{v:.0f}' for v in values)})")
