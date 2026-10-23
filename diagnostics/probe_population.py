"""Probe the Chapter III population gap: founder ages, founder thresholds, child's recorded endowment.

Each variant runs III-1 (endowment 50-100) and III-4 (endowment 10-40) for 1000 periods.
Nothing in the project is changed; variants are applied by patching a model instance.
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import itertools
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS = 1000


def build(exp_id, seed, ages, threshold, child):
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    rng = np.random.default_rng(10_000 + seed)
    lo, hi = m.config.endowment
    for a in m.agents:
        if ages == "spread":
            a.age = int(rng.integers(0, int(a.max_age)))
        if threshold == "independent":
            a.initial_sugar = float(rng.integers(lo, hi, endpoint=True))
    if child == "one-parent":
        original = ORIGINAL_MATE

        def mate(model, agent):
            kids = original(model, agent)
            for k in kids:
                k.initial_sugar = k.initial_sugar / 2  # recorded as one parent's contribution
            return kids

        sex.mate = mate
    return m


ORIGINAL_MATE = sex.mate


def run(args):
    exp_id, seed, ages, threshold, child = args
    try:
        m = build(exp_id, seed, ages, threshold, child)
        pops = [len(m.agents)]
        for _ in range(STEPS):
            m.step()
            pops.append(len(m.agents))
    finally:
        sex.mate = ORIGINAL_MATE  # worker processes are reused: never leak the patch
    return args, pops


def summarize(exp_id, runs):
    p = np.array(runs, dtype=float)
    if exp_id == "III-1":
        book = {20: 470, 85: 570, 240: 415, 330: 545}
        pts = {t: p[:, t].mean() for t in book}
        late = p[:, 500:].mean()
        rms = np.sqrt(np.mean([(pts[t] - b) ** 2 for t, b in book.items()] + [(late - 500) ** 2]))
        return f"t20 {pts[20]:.0f}/470 t85 {pts[85]:.0f}/570 t240 {pts[240]:.0f}/415 t330 {pts[330]:.0f}/545 late {late:.0f}/500 | rms {rms:.0f}"
    peak = p[:, :150].max(axis=1).mean(); tpeak = p[:, :150].argmax(axis=1).mean()
    trough = p[:, 100:220].min(axis=1).mean()
    rng_late = (p[:, 500:].max(axis=1) - p[:, 500:].min(axis=1)).mean()
    per = np.nanmean([dominant_period("population", 300, STEPS)([{"t": t, "population": v} for t, v in enumerate(r)]) for r in runs])
    return (f"peak {peak:.0f}@{tpeak:.0f}/1554@71 trough {trough:.0f}/343 late range {rng_late:.0f}/~1000 "
            f"period {per:.0f}/125-136")


if __name__ == "__main__":
    seeds = (0, 1, 2)
    variants = list(itertools.product(("age0", "spread"), ("equal", "independent"), ("sum", "one-parent")))
    jobs = [(e, s, *v) for e in ("III-1", "III-4") for v in variants for s in seeds]
    results = {}
    with ProcessPoolExecutor(max_workers=int(sys.argv[1]) if len(sys.argv) > 1 else 8) as pool:
        for args, pops in pool.map(run, jobs):
            results.setdefault((args[0], args[2:]), []).append(pops)
    for exp_id in ("III-1", "III-4"):
        print(exp_id)
        for v in variants:
            print(f"  ages={v[0]:6s} threshold={v[1]:11s} child={v[2]:10s} | {summarize(exp_id, results[(exp_id, v)])}")
