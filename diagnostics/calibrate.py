"""Fit one reproduction setting to Fig III-1's steady population (≈500), and nothing else.

Usage: calibrate.py <setting> <v1,v2,...> [jobs]   setting: fertility_threshold | child_share
Score: mean population over t=500..1500, 5 seeds, III-1's configuration otherwise unchanged.
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

STEPS, T0, CAP = 1500, 500, 2400


def run(args):
    setting, value, seed = args
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed, **{setting: value}))
    pops = []
    for _ in range(STEPS):
        m.step()
        pops.append(len(m.agents))
        if len(m.agents) > CAP:
            return args, float("inf")
    return args, float(np.mean(pops[T0 - 1:]))


if __name__ == "__main__":
    setting, values = sys.argv[1], [float(v) for v in sys.argv[2].split(",")]
    tasks = [(setting, v, s) for v in values for s in range(5)]
    with ProcessPoolExecutor(int(sys.argv[3]) if len(sys.argv) > 3 else 8) as pool:
        out = list(pool.map(run, tasks))
    for v in values:
        means = [r for (_, v_, _), r in out if v_ == v]
        print(f"{setting}={v:<6} III-1 mean pop t500-1500: {np.mean(means):8.1f}  seeds {[round(x) for x in means]}", flush=True)
