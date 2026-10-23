"""Probe readings of the sex rule against every reproduction figure (III-1, III-3, III-4, III-5, VI-2, VI-3).

founders: "age0" (current) | "spread" (Ascape: age U[0, max_age))
cost:     "book" (each parent gives half its initial endowment, p.55) | "ascape" (each gives min(5, holding))
thresh:   "gift" (child's fertility threshold = what it received) | "redraw" (Ascape: a fresh endowment draw)
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
from sugarscape.rules.culture import cross_tags

ORIG_MATE = sex.mate


def make_mate(cost: str, thresh: str):
    def mate(model, agent):
        rng = model.rng
        cfg = model.config
        children = []
        neighbors = model.neighbors_of(agent)
        for i in rng.permutation(len(neighbors)):
            other = neighbors[int(i)]
            if other.sex is None or other.sex == agent.sex or not (sex.is_fertile(agent) and sex.is_fertile(other)):
                continue
            sites = list(dict.fromkeys(sex._empty_sites(model, agent) + sex._empty_sites(model, other)))
            if not sites:
                continue
            x, y = sites[int(rng.integers(len(sites)))]
            parents = (agent, other)
            vision = parents[int(rng.integers(2))].vision
            metabolism = parents[int(rng.integers(2))].metabolism
            max_age = parents[int(rng.integers(2))].max_age
            if cost == "book":
                gifts = [p.initial_sugar / 2 for p in parents]
            else:
                gifts = [min(5.0, max(p.sugar, 0.0)) for p in parents]
            for p, g in zip(parents, gifts):
                p.sugar -= g
            child = model.new_agent(x, y, vision, metabolism, sum(gifts), max_age)
            if thresh == "redraw":
                child.initial_sugar = float(rng.integers(cfg.endowment[0], cfg.endowment[1], endpoint=True))
            model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
            if agent.tags is not None and other.tags is not None:
                child.tags = cross_tags(rng, agent.tags, other.tags)
            if cfg.spice:
                if cost == "book":
                    sg = [p.initial_spice / 2 for p in parents]
                else:
                    sg = [min(5.0, max(p.spice, 0.0)) for p in parents]
                for p, g in zip(parents, sg):
                    p.spice -= g
                child.spice = child.initial_spice = sum(sg)
                if thresh == "redraw":
                    lo, hi = cfg.spice_endowment or cfg.endowment
                    child.initial_spice = float(rng.integers(lo, hi, endpoint=True))
                child.spice_metabolism = parents[int(rng.integers(2))].spice_metabolism
                child.foresight = parents[int(rng.integers(2))].foresight
            agent.children.append(child)
            other.children.append(child)
            children.append(child)
        return children

    return mate


STEPS = {"III-1": 1000, "III-3": 1000, "III-4": 600, "III-5": 1000, "VI-2": 200, "VI-3": 1000}
VARIANTS = [("age0", "book", "gift"), ("spread", "book", "gift"), ("age0", "book", "redraw"),
            ("age0", "ascape", "redraw"), ("spread", "ascape", "redraw"), ("spread", "book", "redraw")]
CAP = 3000


def run(args):
    exp_id, variant, seed = args
    founders, cost, thresh = variant
    sex.mate = ORIG_MATE if (cost, thresh) == ("book", "gift") else make_mate(cost, thresh)
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        if founders == "spread":
            rng = np.random.default_rng(10_000 + seed)
            for a in m.agents:
                a.age = int(rng.integers(0, int(a.max_age)))
        pops = [len(m.agents)]
        for _ in range(STEPS[exp_id]):
            m.step()
            pops.append(len(m.agents))
            if len(m.agents) > CAP:  # runaway: stop early, record as full
                pops += [len(m.agents)] * (STEPS[exp_id] + 1 - len(pops))
                break
    finally:
        sex.mate = ORIG_MATE
    return args, pops


def period(p, t0, t1):
    return dominant_period("population", t0, t1)([{"t": t, "population": float(v)} for t, v in enumerate(p)])


def summary(exp_id, ps):
    a = np.array(ps, dtype=float)
    if exp_id == "III-1":
        return " ".join(f"t{t}={a[:, t].mean():.0f}" for t in (20, 85, 240, 330)) + f" late={a[:, 500:].mean():.0f}"
    if exp_id == "III-3":
        return f"floor300+={a[:, 300:].min(1).mean():.0f} mean={a[:, 300:].mean():.0f} period={np.nanmean([period(p, 300, 1000) for p in ps]):.0f}"
    if exp_id == "III-4":
        pk = a[:, :151].max(1); tk = a[:, :151].argmax(1)
        return (f"peak={pk.mean():.0f}@{tk.mean():.0f} trough={np.mean([p[int(t):].min() for p, t in zip(a, tk)]):.0f}"
                f" range300+={np.mean(a[:, 300:].max(1) - a[:, 300:].min(1)):.0f} period={np.nanmean([period(p, 100, 600) for p in ps]):.0f}")
    if exp_id == "III-5":
        return f"extinct@1000={np.mean(a[:, -1] == 0):.2f} t200={a[:, 200].mean():.0f}"
    if exp_id == "VI-2":
        return " ".join(f"t{t}={a[:, t].mean():.0f}" for t in (10, 20, 40, 60, 100)) + f" extinct@200={np.mean(a[:, 200] == 0):.2f}"
    return (f"min40-120={a[:, 40:121].min(1).mean():.0f} peak150-300={a[:, 150:301].max(1).mean():.0f}"
            f" floor250+={a[:, 250:].min(1).mean():.0f} ceil250+={a[:, 250:].max(1).mean():.0f}"
            f" period={np.nanmean([period(p, 200, 1000) for p in ps]):.0f}")


BOOK = {"III-1": "t20=470 t85=570 t240=415 t330=545 late=500",
        "III-3": "floor~250 period~200", "III-4": "peak=1554@71 trough=343 range~1000 period~125",
        "III-5": "extinct", "VI-2": "t10=290 t20=130 t40=90 t60=50 t100=15 extinct",
        "VI-3": "min~65 peak~1190 floor~700 ceil~1200 period~115"}

if __name__ == "__main__":
    tasks = [(e, v, s) for e in STEPS for v in VARIANTS for s in range(3)]
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 8) as pool:
        out = list(pool.map(run, tasks))
    for e in STEPS:
        print(f"{e}  book: {BOOK[e]}")
        for v in VARIANTS:
            ps = [p for (e_, v_, _), p in out if e_ == e and v_ == v]
            print(f"   {v[0]:6s} {v[1]:6s} {v[2]:6s} | {summary(e, ps)}", flush=True)
