"""Diagnostic only (not a reading of the book): lower the high-density ceiling while leaving the peaks alone, by
zeroing every capacity-1 site. Does a steeper income-density curve alone give the book's III-5 extinction,
III-4 swings, III-3 floor, and what does it do to III-1's level?"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

STEPS = 1500


def run(args):
    exp_id, variant, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    if variant == "no-cap1":
        low = m.landscape.capacity == 1
        m.landscape.capacity[low] = 0
        m.landscape.sugar[low] = 0.0
    pop = []
    for _ in range(STEPS):
        pop.append(len(m.agents))
        if not m.agents:
            break
        m.step()
    return exp_id, variant, seed, np.array(pop + [0] * (STEPS - len(pop)), float)


def troughs(p):
    s9 = np.convolve(p, np.ones(9) / 9, "same")
    return [int(p[t]) for t in range(150, len(p) - 60) if p[t] > 0 and s9[t] == s9[t - 50:t + 51].min() and s9[t - 50:t + 51].max() - s9[t] > 300]


if __name__ == "__main__":
    cases = [(e, v, s) for e, n in (("III-1", 5), ("III-3", 5), ("III-4", 5), ("III-5", 10)) for v in ("default", "no-cap1") for s in range(n)]
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, cases))
    for e in ("III-1", "III-3", "III-4", "III-5"):
        for v in ("default", "no-cap1"):
            ps = [r[3] for r in res if r[0] == e and r[1] == v]
            ext = sum((p == 0).any() for p in ps)
            alive = [p for p in ps if not (p == 0).any()]
            tr = [x for p in ps for x in troughs(p)]
            print(f"{e} {v:8s}: extinct {ext}/{len(ps)} | mean t=300-1500 {np.mean([p[300:].mean() for p in alive]) if alive else float('nan'):.0f} | "
                  f"min t>=300 {np.mean([p[300:].min() for p in alive]) if alive else float('nan'):.0f} | "
                  f"range t=1000-1500 {np.mean([p[1000:].max() - p[1000:].min() for p in alive]) if alive else float('nan'):.0f} | "
                  f"first peak {np.mean([p[:300].max() for p in ps]):.0f}@{np.mean([np.argmax(p[:300]) for p in ps]):.0f} | "
                  f"troughs min/median {min(tr) if tr else '-'}/{int(np.median(tr)) if tr else '-'}")
