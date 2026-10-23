"""III-3 founding transient: births, old-age deaths and starvation per period, t=0-50 and 50-200, by founder ages."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model


def run(args):
    founders, seed = args
    m = Model(replace(EXPERIMENTS["III-3"].config, founder_ages=founders, seed=seed))
    rows = []
    for t in range(200):
        n0, ids = len(m.agents), m._next_id
        m.step()
        born = m._next_id - ids
        old = sum(a.age >= a.max_age for a in m.dead_this_step)
        rows.append((born, old, len(m.dead_this_step) - old))
    return founders, np.array(rows)


if __name__ == "__main__":
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(f, s) for f in ("uniform", "zero") for s in range(5)]))
    for f in ("uniform", "zero"):
        r = np.mean([x for g, x in res if g == f], axis=0)
        for a, b in ((0, 50), (50, 200)):
            w = r[a:b]
            print(f"{f:7s} t={a}-{b}: births {w[:,0].mean():.2f}/period, old-age deaths {w[:,1].mean():.2f}, starvation {w[:,2].mean():.2f}")
