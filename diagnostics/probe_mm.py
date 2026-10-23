"""Must-move vs book movement: II-1 share still moving at t=80-100; III-1 neighbors, partner contact, level."""
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
from sugarscape.rules import sex


def run(args):
    kind, exp_id, seed = args
    mv.move = pm.make_move(kind)
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    if exp_id == "II-1":
        mvd = []
        for t in range(100):
            m.step()
            if t >= 80:
                mvd.append(np.mean([a.moved for a in m.agents]))
        return args, (np.mean(mvd),)
    nb, contact, pops = [], [], []
    for t in range(1000):
        m.step()
        pops.append(len(m.agents))
        if t >= 300:
            nb.append(np.mean([len(a.neighbors) for a in m.agents]))
            fert = [a for a in m.agents if sex.is_fertile(a)]
            if fert:
                contact.append(np.mean([any(o.sex != a.sex and sex.is_fertile(o) for o in m.neighbors_of(a)) for a in fert]))
    return args, (np.mean(nb), np.mean(contact), np.mean(pops[300:]))


if __name__ == "__main__":
    tasks = [(k, e, s) for k in ("book", "mustmove") for e in ("II-1", "III-1") for s in range(3)]
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, tasks))
    for k in ("book", "mustmove"):
        a = np.mean([v for (k_, e, s), v in out if (k_, e) == (k, "II-1")], axis=0)
        b = np.mean([v for (k_, e, s), v in out if (k_, e) == (k, "III-1")], axis=0)
        print(f"{k:8s} II-1 share moving t=80-100: {a[0]:.2f} | III-1 t>=300: neighbors {b[0]:.2f}, "
              f"fertile agents with a fertile partner adjacent at period end {b[1]:.3f}, level {b[2]:.0f}")
