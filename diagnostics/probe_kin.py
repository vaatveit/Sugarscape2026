"""Who stands next to a fertile agent at its mating turn (III-1, t=300-1000), against the population mix."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
import sugarscape.model as model_mod
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex


def cls(a, o):
    kin = o in a.children or a in o.children or bool(set(map(id, a.parents)) & set(map(id, o.parents))) if hasattr(a, "parents") else (o in a.children or a in o.children)
    if o.sex == a.sex:
        return "same sex"
    if o.age < o.fertility_start:
        return "opp: too young"
    if o.age >= o.fertility_end:
        return "opp: too old"
    if not sex.is_fertile(o):
        return "opp: fertile age, short of wealth"
    return "opp: fertile (partner)"


def run(seed):
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed))
    c, kin, pop, turns = Counter(), Counter(), Counter(), 0
    orig = sex.mate

    def mate(model, agent):
        nonlocal turns
        if model.t >= 300 and sex.is_fertile(agent):
            turns += 1
            for o in model.neighbors_of(agent):
                k = cls(agent, o)
                c[k] += 1
                if o in agent.children or agent in o.children:
                    kin[k] += 1
        return orig(model, agent)
    model_mod.sex.mate = mate
    for t in range(1000):
        if t >= 300:
            for a in m.agents:
                pop["n"] += 1
                pop["fertile"] += sex.is_fertile(a)
        m.step()
    return c, kin, turns, pop


if __name__ == "__main__":
    with ProcessPoolExecutor(5) as pool:
        res = list(pool.map(run, range(5)))
    c = sum((r[0] for r in res), Counter()); kin = sum((r[1] for r in res), Counter())
    turns = sum(r[2] for r in res); pop = sum((r[3] for r in res), Counter())
    total = sum(c.values())
    print(f"fertile turns {turns}, neighbors per turn {total / turns:.2f}; population fertile share {pop['fertile'] / pop['n']:.3f}"
          f" -> random mixing would give an opposite-sex fertile neighbor with prob ~{0.5 * pop['fertile'] / pop['n']:.3f} per neighbor")
    for k in ("same sex", "opp: too young", "opp: too old", "opp: fertile age, short of wealth", "opp: fertile (partner)"):
        print(f"   {k:36s} {c[k] / total:.3f} of neighbors (parent or child of the agent: {kin[k] / max(c[k], 1):.2f})")
