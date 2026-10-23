"""III-4 (endowments 10-40): births, old-age deaths, starvation, metabolism, harvest vs burn, fertile share, by 20-period window."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import ast
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules.sex import is_fertile

STEPS = 600
W = 20


def run(args):
    seed, extra = args
    m = Model(replace(EXPERIMENTS["III-4"].config, seed=seed, **extra))
    th = m.config.fertility_threshold
    rows = []
    for t in range(STEPS):
        a = m.agents
        n = len(a)
        fa = [g for g in a if g.fertility_start <= g.age < g.fertility_end]
        fert = sum(is_fertile(g, th) for g in fa)
        ids = m._next_id
        m.step()
        born = m._next_id - ids
        old = sum(d.age >= d.max_age for d in m.dead_this_step)
        starve = len(m.dead_this_step) - old
        newborn_starve = sum(d.age < 15 for d in m.dead_this_step if d.age < d.max_age)
        inc = np.mean([g.last_income for g in m.agents]) if m.agents else 0
        met = np.mean([g.metabolism for g in m.agents]) if m.agents else 0
        wealth = np.mean([g.sugar for g in m.agents]) if m.agents else 0
        rows.append((n, born, old, starve, newborn_starve, len(fa), fert, inc, met, wealth))
    return np.array(rows, dtype=float)


if __name__ == "__main__":
    extra = ast.literal_eval(sys.argv[1]) if len(sys.argv) > 1 else {}
    with ProcessPoolExecutor(5) as pool:
        res = np.mean(list(pool.map(run, [(s, extra) for s in range(5)])), axis=0)
    print(f"III-4 {extra}: per period, mean of 5 seeds")
    print("   t     N  births  old-age  starved (<15y)  fertile-age  wealth-fertile  harvest  metabolism  wealth")
    for t0 in range(0, STEPS, W):
        r = res[t0:t0 + W].mean(axis=0)
        print(f"{t0:4d} {r[0]:5.0f} {r[1]:7.1f} {r[2]:8.1f} {r[3]:8.1f} ({r[4]:4.1f}) {r[5]:11.0f} {r[6]:12.0f} {r[7]:9.2f} {r[8]:10.2f} {r[9]:8.1f}")
