"""The book's single-run population figures as frequencies: over many seeds, how often does a run show the book's
behavior? Under epoch C's threshold (0.83) and p.55's (1.0), and optionally the VAR-c1c3fit, VAR-intgift and
VAR-intgiftc1 variants (the last is the default since 2026-10-23), founders at spread ages. Seeds are the registry's
(base + k), so the first 5-10 are the registered runs.

  III-3  keeps both mountains (each quadrant occupied through the last 500 periods); floor t>=300 in the book's band
  III-4  holds the large cycle (range > 600 over t=1500-2500)
  III-5  dies out by t=1500; a trough below 100 after t=150 (the book's ≈50)
  VI-2   dies out by t=200; crash at t=20 within the band's top (≤156)
  VI-3   survives to t=1000; floor and ceiling after t=250 in the book's bands (≥560, ≥960)

Usage: frequencies.py [seeds] [jobs] [setting,...]    settings: default book c1c3fit intgift intgiftc1
                                                       (default: default,book)
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from experiments.registry import EXPERIMENTS, VARIANTS
from sugarscape.model import Model

STEPS = {"III-3": 2500, "III-4": 2500, "III-5": 1500, "VI-2": 200, "VI-3": 1000}
# "default" is epoch C's (threshold 0.83, now VAR-fit83); "intgiftc1" is the default since 2026-10-23.
SETTINGS = {"default": {"fertility_threshold": 0.83}, "book": {"fertility_threshold": 1.0}, "c1c3fit": VARIANTS["c1c3fit"],
            "intgift": VARIANTS["intgift"], "intgiftc1": VARIANTS["intgiftc1"]}


def run(args):
    exp_id, setting, k = args
    base = EXPERIMENTS[exp_id].config
    m = Model(replace(base, **SETTINGS[setting], seed=base.seed + k))
    pop, both = [], True
    for t in range(STEPS[exp_id]):
        agents = m.agents
        pop.append(len(agents))
        if exp_id == "III-3" and t >= STEPS[exp_id] - 500:
            ne = sum(a.x >= 25 and a.y >= 25 for a in agents)
            sw = sum(a.x < 25 and a.y < 25 for a in agents)
            both = both and ne > 0 and sw > 0
        if not agents:
            break
        m.step()
    pop += [0] * (STEPS[exp_id] - len(pop))
    return exp_id, setting, k, np.array(pop), both


def outcomes(exp_id, p, both):
    if exp_id == "III-3":
        return {"both mountains": both and p[-1] > 0, "floor in band (>=200)": p[300:].min() >= 200}
    if exp_id == "III-4":
        return {"large cycle (range > 600)": p[1500:].max() - p[1500:].min() > 600}
    if exp_id == "III-5":
        return {"extinct by 1500": p[-1] == 0, "trough < 100 after t=150": p[150:].min() < 100}
    if exp_id == "VI-2":
        return {"extinct by 200": p[-1] == 0, "crash at t=20 <= 156": p[20] <= 156}
    return {"survives": p[-1] > 0, "waves in band (floor >=560, ceiling >=960)": p[-1] > 0 and p[250:].min() >= 560 and p[250:].max() >= 960}


if __name__ == "__main__":
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    names = sys.argv[3].split(",") if len(sys.argv) > 3 else ["default", "book"]
    cases = [(e, s, k) for e in STEPS for s in names for k in range(seeds)]
    with ProcessPoolExecutor(jobs) as pool:
        res = list(pool.map(run, cases))
    print(f"{seeds} seeds per cell; share of runs showing the book's behavior")
    print("| Figure | Book's behavior | " + " | ".join(names) + " |")
    print("|---|---|" + "---|" * len(names))
    for e in STEPS:
        for outcome in outcomes(e, np.ones(STEPS[e]), True):
            cells = []
            for name in names:
                hits = [outcomes(e, p, b)[outcome] for ee, s, k, p, b in res if ee == e and s == name]
                cells.append(f"{sum(hits)}/{len(hits)}")
            print(f"| {e} | {outcome} | " + " | ".join(cells) + " |")
