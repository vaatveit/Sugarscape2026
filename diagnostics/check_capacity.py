"""Fig II-5's carrying capacities under the food-limit settings of probe_falls.py (README next step, 2026-10-23): a
setting that makes Chapter III's peaks outgrow their food would also have to keep Chapter II's carrying capacities,
which match the book at t≈50 today. Each Fig II-5 point at vision 3 (and m1/m2/m3), 3 seeds: mean population over
t=45-60 and t=450-500. Diagnostic only.

Usage: check_capacity.py [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # the docstring's ≈ may be printed
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from experiments.registry import EXPERIMENTS
from replication.targets import FIG_II_5_BOOK
from sugarscape.model import Model

SETTINGS = {"G1 (book)": {}, "growback 0.75": {"growback_rate": 0.75}, "growback 0.5": {"growback_rate": 0.5},
            "lowland": "lowland"}
POINTS = ("m1/v3", "m2/v3", "m3/v3")
SEEDS = 3


def run(args):
    name, point, k = args
    exp = EXPERIMENTS[f"II-5/{point}"]
    setting = SETTINGS[name]
    m = Model(replace(exp.config, seed=exp.config.seed + k, **(setting if isinstance(setting, dict) else {})))
    if setting == "lowland":
        low = m.landscape.capacity == 1
        m.landscape.capacity[low] = 0
        m.landscape.sugar[low] = 0.0
    pop = []
    for _ in range(501):
        pop.append(len(m.agents))
        m.step()
    pop = np.array(pop)
    return name, point, pop[45:61].mean(), pop[450:501].mean()


if __name__ == "__main__":
    jobs = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    with ProcessPoolExecutor(jobs) as pool:
        res = list(pool.map(run, [(s, p, k) for s in SETTINGS for p in POINTS for k in range(SEEDS)]))
    print(f"Fig II-5 carrying capacity, {SEEDS} seeds: mean population t=45-60 / t=450-500")
    print("| Setting | " + " | ".join(f"{p} (book {FIG_II_5_BOOK[int(p[1])]['3']})" for p in POINTS) + " |")
    print("|---|" + "---|" * len(POINTS))
    for s in SETTINGS:
        cells = []
        for p in POINTS:
            r = [(a, b) for ss, pp, a, b in res if ss == s and pp == p]
            cells.append(f"{np.mean([a for a, _ in r]):.0f} / {np.mean([b for _, b in r]):.0f}")
        print(f"| {s} | " + " | ".join(cells) + " |")
