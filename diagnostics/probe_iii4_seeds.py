"""Unmodified III-4 over many seeds: how many find the large cycle? Late range, peaks/troughs, period."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model

STEPS = 2500


def run(args):
    exp_id, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    pop = []
    for _ in range(STEPS):
        pop.append(len(m.agents)); m.step()
    return seed, np.array(pop, float)


def extremes(p, t0):
    s = np.convolve(p, np.ones(15) / 15, "same")
    pk = [t for t in range(t0, len(s) - 8) if s[t] == s[t - 40:t + 41].max() and s[t] - s[t - 40:t + 41].min() > 150]
    tr = [t for t in range(t0, len(s) - 8) if s[t] == s[t - 40:t + 41].min() and s[t - 40:t + 41].max() - s[t] > 150]
    return pk, tr


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-4"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(exp_id, s) for s in range(n)]))
    big = 0
    for s, p in res:
        rng = [p[a:a + 500].max() - p[a:a + 500].min() for a in range(0, 2500, 500)]
        per = dominant_period("population", 300, STEPS)([{"t": t, "population": v} for t, v in enumerate(p)])
        pk, tr = extremes(p, 1500)
        line = f"  seed {s:2d}: range per 500 periods " + " ".join(f"{r:5.0f}" for r in rng) + f" | period {per}"
        if p[1500:].max() - p[1500:].min() > 600:
            big += 1
            line += (f" | t>=1500 peaks {np.mean([p[t] for t in pk]):.0f} troughs {np.mean([p[t] for t in tr]):.0f} "
                     f"peak spacing {np.mean(np.diff(pk)) if len(pk) > 1 else float('nan'):.0f}")
        print(line)
    print(f"{exp_id}: {big}/{n} seeds hold the large cycle (range > 600 over t=1500-2500)")
