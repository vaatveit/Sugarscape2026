"""Diagnostics only (nothing here is a candidate rule).

income: harvest and net income per agent for N immortal, non-breeding agents with III-1 genetics,
        endowed so richly that none starve (t=1-85).
growback: III-1 with the book's rule S but a higher regrowth rate alpha (how much more income the
        early boom needs).
cost:   III-1 with a threshold theta*e and a cost of k*e per parent; the child's sugar is the gifts, but
        its recorded endowment (its own threshold base) is the parents' mean e, so cheap births don't
        compound across generations. theta=1, k=0.5 is the book. Also counts multiple births per turn
        (fn 3: "occasionally"; fertile agents "rarely possess enough wealth" for two).
"""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
import sugarscape.model as model_mod
from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules import sex
from sugarscape.rules.sex import _empty_sites

STEPS = 1000
BASE = EXPERIMENTS["III-1"].config


def income(args):
    n, seed = args
    m = Model(Config(initial_population=n, vision=BASE.vision, metabolism=BASE.metabolism,
                     endowment=(1000, 1000), seed=seed))
    h, net, pos = [], [], []
    for t in range(85):
        m.step()
        h.append(np.mean([a.last_income + a.metabolism for a in m.agents]))
        net.append(np.mean([a.last_income for a in m.agents]))
        pos.append(np.mean([a.last_income > 0 for a in m.agents]))
    return args, (np.mean(h), np.mean(net), np.mean(pos))


def make_mate(theta, k, stats):
    def fertile(a):
        return (a.alive and a.sex is not None and a.fertility_start <= a.age < a.fertility_end
                and a.sugar >= theta * a.initial_sugar)

    def mate(model, agent):
        rng, kids = model.rng, []
        nbrs = model.neighbors_of(agent)
        for i in rng.permutation(len(nbrs)):
            other = nbrs[int(i)]
            if other.sex is None or other.sex == agent.sex or not (fertile(agent) and fertile(other)):
                continue
            sites = list(dict.fromkeys(_empty_sites(model, agent) + _empty_sites(model, other)))
            if not sites:
                continue
            x, y = sites[int(rng.integers(len(sites)))]
            p = (agent, other)
            vision, metabolism, max_age = (p[int(rng.integers(2))].vision, p[int(rng.integers(2))].metabolism,
                                           p[int(rng.integers(2))].max_age)
            gift = k * agent.initial_sugar + k * other.initial_sugar
            agent.sugar -= k * agent.initial_sugar
            other.sugar -= k * other.initial_sugar
            child = model.new_agent(x, y, vision, metabolism, gift, max_age)
            child.initial_sugar = (agent.initial_sugar + other.initial_sugar) / 2
            model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
            agent.children.append(child)
            other.children.append(child)
            kids.append(child)
        if kids:
            stats[0] += 1
            stats[1] += len(kids) > 1
        return kids
    return mate


def curve(args):
    kind, a, b, seed = args
    stats = [0, 0]
    if kind == "growback":
        m = Model(replace(BASE, seed=seed, growback_rate=a))
    else:
        m = Model(replace(BASE, seed=seed))
        model_mod.sex.mate = make_mate(a, b, stats)
    pops, births = [len(m.agents)], 0
    for t in range(STEPS):
        before = m.agents_ever
        m.step()
        if t < 85:
            births += m.agents_ever - before
        pops.append(len(m.agents))
        if not m.agents or len(m.agents) > 2400:
            break
    pops += [pops[-1]] * (STEPS + 1 - len(pops))
    return args, (pops, births, stats)


if __name__ == "__main__":
    with ProcessPoolExecutor(8) as pool:
        inc = list(pool.map(income, [(n, s) for n in (200, 300, 400, 500, 600) for s in range(3)]))
        cur_tasks = ([("growback", a, None, s) for a in (1.0, 1.5, 2.0, 3.0) for s in range(3)]
                     + [("cost", th, k, s) for th in (1.0, 0.75, 0.5) for k in (0.5, 0.25, 0.1) for s in range(3)])
        cur = list(pool.map(curve, cur_tasks))
    print("Income for N immortal non-breeding agents with III-1 genetics, t=1-85 (3 seeds)")
    for n in (200, 300, 400, 500, 600):
        r = np.array([v for (n_, _), v in inc if n_ == n])
        print(f"  N={n}: harvest/agent {r[:, 0].mean():.2f}  net/agent {r[:, 1].mean():+.2f}  "
              f"share with positive net {r[:, 2].mean():.2f}  total harvest {n * r[:, 0].mean():.0f}")
    print("\nBook Fig III-1: t20=470 t85=570 t240=415 late(300-1000)~500; births t<85 ~555")
    keys = [("growback", a, None) for a in (1.0, 1.5, 2.0, 3.0)] + [
        ("cost", th, k) for th in (1.0, 0.75, 0.5) for k in (0.5, 0.25, 0.1)]
    for key in keys:
        rs = [v for (kd, a, b, s), v in cur if (kd, a, b) == key]
        p = np.array([r[0] for r in rs], float)
        tw = sum(r[2][1] for r in rs) / max(sum(r[2][0] for r in rs), 1)
        label = f"alpha={key[1]}" if key[0] == "growback" else f"theta={key[1]} k={key[2]}"
        extra = "" if key[0] == "growback" else f"  turns with 2+ births {tw:.0%}"
        print(f"  {key[0]:8s} {label:18s} t20={p[:, 20].mean():5.0f} t85={p[:, 85].mean():5.0f} "
              f"t240={p[:, 240].mean():5.0f} late={p[:, 300:].mean():5.0f} births<85={np.mean([r[1] for r in rs]):4.0f}{extra}")
