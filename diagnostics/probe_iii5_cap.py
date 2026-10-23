"""Diagnostic only: III-5 (and III-4) with every birth blocked while the population exceeds CAP. Does a birth
shut-off at high density alone give the book's near-zero troughs and extinction?"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS = 1500


def run(args):
    exp_id, cap, seed = args
    orig = sex.mate
    sex.mate = lambda model, agent: [] if len(model.agents) > cap else orig(model, agent)
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    pop = []
    for _ in range(STEPS):
        pop.append(len(m.agents))
        if not m.agents:
            break
        m.step()
    sex.mate = orig
    return exp_id, cap, seed, np.array(pop + [0] * (STEPS - len(pop)), float)


if __name__ == "__main__":
    exp_id = sys.argv[1]
    caps = [int(c) for c in sys.argv[2].split(",")]
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(exp_id, c, s) for c in caps for s in range(10)]))
    for c in caps:
        rs = [r for r in res if r[1] == c]
        print(f"{exp_id}, no births above {c}:")
        for _, _, s, p in rs:
            s9 = np.convolve(p, np.ones(9) / 9, "same")
            pk = [int(p[t]) for t in range(30, len(p) - 30) if s9[t] == s9[t - 30:t + 31].max() and s9[t] - s9[t - 30:t + 31].min() > 300]
            tr = [int(p[t]) for t in range(30, len(p) - 30) if s9[t] == s9[t - 30:t + 31].min() and s9[t - 30:t + 31].max() - s9[t] > 300]
            dead = int(np.argmax(p == 0)) if (p == 0).any() else None
            print(f"  seed {s}: peaks {pk[:5]} troughs {tr[:5]} " + (f"EXTINCT at t={dead}" if dead else f"alive, range t=1000-1500 {p[1000:].max() - p[1000:].min():.0f}"))
        print(f"  {sum((r[3] == 0).any() for r in rs)}/10 extinct")
