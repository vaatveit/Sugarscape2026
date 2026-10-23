"""Decompose III-1's birth rate under the current defaults (spread founder ages, book rule S).

Per period: population, births, deaths (old age / starvation), agents of fertile age, how many of
those pass the wealth test, the mating turns taken by fertile agents and why each one failed, and
the fertile agents still unmated at the end of the period (Little's law gives their mean wait).
"""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py

import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

import sugarscape.model as model_mod
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS = 1000
WINDOWS = [(0, 20), (20, 85), (85, 200), (200, 500), (500, 1000)]


def fertile_age(a):
    return a.sex is not None and a.fertility_start <= a.age < a.fertility_end


def run(args):
    exp_id, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    rows = []
    cur = defaultdict(float)
    original = sex.mate

    def mate(model, agent):
        if fertile_age(agent):
            cur["turns_age"] += 1
            if sex.is_fertile(agent):
                cur["turns_fertile"] += 1
                nbrs = model.neighbors_of(agent)
                opp = [o for o in nbrs if o.sex is not None and o.sex != agent.sex]
                opp_age = [o for o in opp if fertile_age(o)]
                opp_f = [o for o in opp if sex.is_fertile(o)]
                cur["nbrs"] += len(nbrs)
                cur["has_opp"] += bool(opp)
                cur["has_opp_age"] += bool(opp_age)
                cur["has_opp_fertile"] += bool(opp_f)
                if opp_f and not any(sex._empty_sites(model, agent) + sex._empty_sites(model, o) for o in opp_f):
                    cur["no_site"] += 1
            else:
                cur["gap"] += agent.initial_sugar - agent.sugar
        kids = original(model, agent)
        cur["births"] += len(kids)
        return kids

    model_mod.sex.mate = mate
    try:
        for t in range(STEPS):
            cur.clear()
            n0 = len(m.agents)
            age = [a for a in m.agents if fertile_age(a)]
            cur["n"] = n0
            cur["n_age"] = len(age)
            cur["n_fertile_start"] = sum(sex.is_fertile(a) for a in age)
            cur["income_age"] = float(np.mean([a.last_income for a in age])) if age else np.nan
            cur["wealth_age"] = float(np.mean([a.sugar for a in age])) if age else np.nan
            cur["thresh_age"] = float(np.mean([a.initial_sugar for a in age])) if age else np.nan
            # Unmated fertile agents at the end of the agent loop: measure them by wrapping aging.
            m.step()
            old = sum(1 for a in m.dead_this_step if a.age >= a.max_age)
            cur["deaths_old"] = old
            cur["deaths_starve"] = len(m.dead_this_step) - old
            rows.append(dict(cur))
            if not m.agents:
                break
    finally:
        model_mod.sex.mate = original
    return args, rows


def fertile_end_probe(args):
    """Fertile agents left at the end of each period (before aging), for the waiting-time estimate."""
    exp_id, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    out = []
    step = Model.step

    for t in range(STEPS):
        # The agent loop runs inside step; record the stock just before aging by re-implementing nothing:
        # use the stock at the start of the next period minus newly aged-in agents is messy, so take the
        # stock at period start (mating happens during the loop, so this is the pool that carried over).
        out.append(sum(sex.is_fertile(a) for a in m.agents))
        step(m)
        if not m.agents:
            break
    return args, out


def summarize(rows, key, lo, hi, per="period"):
    xs = [r.get(key, 0.0) for r in rows[lo:hi]]
    return np.mean(xs) if xs else np.nan


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-1"
    seeds = range(5)
    with ProcessPoolExecutor(5) as pool:
        out = list(pool.map(run, [(exp_id, s) for s in seeds]))
    keys = ["n", "births", "deaths_old", "deaths_starve", "n_age", "n_fertile_start", "turns_age",
            "turns_fertile", "has_opp", "has_opp_age", "has_opp_fertile", "no_site", "nbrs",
            "income_age", "wealth_age", "thresh_age", "gap"]
    print(f"{exp_id}: means per period over 5 seeds")
    print("window      " + " ".join(f"{k[:12]:>12s}" for k in keys))
    for lo, hi in WINDOWS:
        vals = []
        for k in keys:
            per_seed = [summarize(rows, k, lo, hi) for _, rows in out if len(rows) > lo]
            vals.append(np.nanmean(per_seed) if per_seed else np.nan)
        print(f"{lo:4d}-{hi:<5d}  " + " ".join(f"{v:12.2f}" for v in vals))
    # Derived: share of fertile-age agents passing the wealth test; fertile turns with a fertile partner.
    print()
    for lo, hi in WINDOWS:
        tot = defaultdict(float)
        for _, rows in out:
            for r in rows[lo:hi]:
                for k, v in r.items():
                    tot[k] += v
        if not tot["n"]:
            continue
        print(f"{lo:4d}-{hi:<5d} wealth-ok share of fertile-age {tot['n_fertile_start'] / max(tot['n_age'], 1):.2f} | "
              f"fertile turns w/ fertile opp-sex nbr {tot['has_opp_fertile'] / max(tot['turns_fertile'], 1):.2f} | "
              f"w/ any opp-sex nbr {tot['has_opp'] / max(tot['turns_fertile'], 1):.2f} | "
              f"nbrs/fertile turn {tot['nbrs'] / max(tot['turns_fertile'], 1):.2f} | "
              f"no-site share {tot['no_site'] / max(tot['has_opp_fertile'], 1):.2f} | "
              f"mean wait (fertile stock / 2 births) {tot['n_fertile_start'] / max(2 * tot['births'], 1):.1f} | "
              f"wealth gap of sterile fertile-age {tot['gap'] / max(tot['turns_age'] - tot['turns_fertile'], 1):.1f}")
