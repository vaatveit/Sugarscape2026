"""Verify the reviewer's claims: (1) Ch IV 'carrying capacity' scales with starting population;
(2) sensitivity of IV-14 / IV-18 survival to the both-goods fertility test."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

ORIGINAL = sex.is_fertile


def sugar_only_fertile(agent, threshold=1.0):  # threshold: is_fertile's signature since 2026-10-22
    return (agent.alive and agent.sex is not None and agent.fertility_start <= agent.age < agent.fertility_end
            and agent.sugar >= threshold * agent.initial_sugar)


def capacity(args):
    trade, n0, seed = args
    cfg = replace(EXPERIMENTS["IV-6/trade/v3"].config, trade=trade, initial_population=n0, seed=seed)
    m = Model(cfg)
    m.run(500)
    return args, len(m.agents)


def fertility(args):
    exp_id, variant, seed = args
    sex.is_fertile = sugar_only_fertile if variant == "sugar-only" else ORIGINAL
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        alive_at = {}
        for t in range(1, 501):
            m.step()
            if t in (100, 500):
                alive_at[t] = len(m.agents)
    finally:
        sex.is_fertile = ORIGINAL
    return args, alive_at


if __name__ == "__main__":
    jobs = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    with ProcessPoolExecutor(jobs) as pool:
        cap = list(pool.map(capacity, [(tr, n, s) for tr in (True, False) for n in (100, 200, 400, 800) for s in (0, 1, 2)]))
        fert = list(pool.map(fertility, [(e, v, s) for e in ("IV-14", "IV-18") for v in ("both", "sugar-only")
                                          for s in range(5)]))
    print("capacity (vision 1-5, metab 1-5, t=500): survivors and survivors/n0")
    for tr in (True, False):
        for n in (100, 200, 400, 800):
            vals = [p for (t_, n_, _), p in cap if t_ == tr and n_ == n]
            mean = sum(vals) / len(vals)
            print(f"  trade={tr!s:5} n0={n:4}: {mean:6.1f}  ratio {mean / n:.2f}")
    print("fertility sensitivity: seeds surviving to t=500 (population at t=500 per seed)")
    for e in ("IV-14", "IV-18"):
        for v in ("both", "sugar-only"):
            rows = [a for (e_, v_, _), a in fert if e_ == e and v_ == v]
            alive = sum(1 for a in rows if a[500] > 0)
            print(f"  {e} {v:10}: {alive}/5 survive; t=500 pops {[a[500] for a in rows]}")
