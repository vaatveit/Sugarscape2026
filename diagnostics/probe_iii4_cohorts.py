"""III-4 memory channel: for each birth cohort (20-period windows), the share of its members who reach fertility
age holding their threshold, their wealth/threshold then, childhood net income, and lifetime children."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import ast
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

STEPS, W = 600, 20


def run(args):
    seed, extra = args
    m = Model(replace(EXPERIMENTS["III-4"].config, seed=seed, **extra))
    th = m.config.fertility_threshold
    born, child_inc, at_start, pop = {}, defaultdict(float), {}, []
    for t in range(STEPS):
        pop.append(len(m.agents))
        for a in m.agents:
            if a.id >= 400:
                born.setdefault(a.id, t)
                if a.age < a.fertility_start:
                    child_inc[a.id] += a.last_income
                elif a.age == a.fertility_start and a.id not in at_start:
                    at_start[a.id] = a.sugar / (th * a.initial_sugar)
        m.step()
    rows = defaultdict(list)
    for i, r in at_start.items():
        rows[born[i] // W].append((r, child_inc[i]))
    return pop, {k: v for k, v in rows.items()}


if __name__ == "__main__":
    extra = ast.literal_eval(sys.argv[1]) if len(sys.argv) > 1 else {}
    with ProcessPoolExecutor(5) as pool:
        res = list(pool.map(run, [(s, extra) for s in range(5)]))
    pop = np.mean([p for p, _ in res], axis=0)
    print(f"III-4 {extra}: cohort (birth window) | N at birth | members reaching fertility age | share holding threshold | wealth/threshold | childhood net income per year")
    for k in range(0, STEPS // W - 1):
        v = [x for _, rows in res for x in rows.get(k, [])]
        if v:
            r = np.array(v)
            print(f"  born t={k * W:3d}-{k * W + W:<3d} N {pop[k * W:(k + 1) * W].mean():5.0f} | {len(v) / 5:5.0f} | {np.mean(r[:, 0] >= 1):.2f} | {np.median(r[:, 0]):.2f} | {np.mean(r[:, 1]) / 13.5:+.2f}")
