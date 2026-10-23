"""Mean post-move neighbors (book's network statistic) over time in II-4's run (Animation II-5: 0.9 in all
six frames, sd 0.8-0.9), for movement variants (see probe_moves.py)."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
import probe_moves as pm
import sugarscape.rules.movement as mv
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

WIN = [(1, 5), (5, 20), (20, 60), (60, 150), (150, 500)]


def run(args):
    kind, seed = args
    mv.move = pm.make_move(kind)
    m = Model(replace(EXPERIMENTS["II-4"].config, seed=seed))
    rec = {w: [] for w in WIN}
    for t in range(500):
        m.step()
        nb = [len(a.neighbors) for a in m.agents]
        for w in WIN:
            if w[0] <= t < w[1]:
                rec[w].append((np.mean(nb), np.std(nb), len(nb)))
    return args, {w: np.mean(v, axis=0) for w, v in rec.items()}


if __name__ == "__main__":
    kinds = ("book", "mustmove", "anydist")
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, [(k, s) for k in kinds for s in range(5)]))
    for k in kinds:
        print(k)
        for w in WIN:
            r = np.mean([v[w] for (k_, s), v in out if k_ == k], axis=0)
            print(f"   t={w[0]:3d}-{w[1]:<4d} mean neighbors {r[0]:.2f}  sd {r[1]:.2f}  N {r[2]:.0f}")
