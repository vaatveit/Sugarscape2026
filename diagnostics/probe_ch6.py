"""Probe the indecomposability gap (VI-2/VI-3).

H1: fertility needs both goods (sugar >= initial sugar AND spice >= initial spice).
H2: founders start at a spread of ages, U[0, max_age).
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

import sugarscape.rules.sex as sex
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model

ORIG = sex.is_fertile


def both_goods(agent, threshold=1.0) -> bool:  # threshold: is_fertile's signature since 2026-10-22
    return ORIG(agent, threshold) and agent.spice >= threshold * agent.initial_spice


def run(args):
    exp_id, h1, h2, seed, steps = args
    sex.is_fertile = both_goods if h1 else ORIG
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        if h2:
            rng = np.random.default_rng(10_000 + seed)
            for a in m.agents:
                a.age = int(rng.integers(0, int(a.max_age)))
        pops = [len(m.agents)]
        births = []
        for _ in range(steps):
            n_before, ids = len(m.agents), m._next_id
            m.step()
            pops.append(len(m.agents))
            births.append(m._next_id - ids)
    finally:
        sex.is_fertile = ORIG
    return args, pops, births


def main(jobs):
    variants = [(False, False), (True, False), (False, True), (True, True)]
    tasks = [(e, h1, h2, s, 200 if e == "VI-2" else 1000) for e in ("VI-2", "VI-3") for h1, h2 in variants for s in range(5)]
    with ProcessPoolExecutor(jobs) as pool:
        out = list(pool.map(run, tasks))
    T = [5, 10, 20, 40, 60, 100, 150, 200]
    for e in ("VI-2", "VI-3"):
        for h1, h2 in variants:
            rs = [(p, b) for (e_, a, c, _, _), p, b in out if (e_, a, c) == (e, h1, h2)]
            pops = np.array([p for p, _ in rs])
            label = f"{e} both_goods={h1!s:5} spread_ages={h2!s:5}"
            line = " ".join(f"t{t}={pops[:, t].mean():.0f}" for t in T)
            extra = f" births1-3={np.mean([sum(b[:3]) for _, b in rs]):.0f} extinct@200={np.mean(pops[:, 200] == 0):.1f}"
            if e == "VI-3":
                series = [[{"t": t, "population": float(v)} for t, v in enumerate(p)] for p in pops]
                per = [dominant_period("population", 200, 1000)(s) for s in series]
                extra += (f" | min40-120={pops[:, 40:121].min(1).mean():.0f} peak150-300={pops[:, 150:301].max(1).mean():.0f}"
                          f" floor250+={pops[:, 250:].min(1).mean():.0f} ceil250+={pops[:, 250:].max(1).mean():.0f}"
                          f" period={np.nanmean(per):.0f} ({np.sum(~np.isnan(per))}/5)")
            print(label, line, extra, flush=True)
    print("book VI-2: t5=450 t10=290 t20=130 t40=90 t60=50 t100=15 t150=0 extinct")
    print("book VI-3: min≈65 peak≈1190 floor≈700 ceil≈1200-1250 period≈115")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 8)
