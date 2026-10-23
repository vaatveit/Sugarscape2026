"""Late III-1: women's lifetime births and the wealth cycle; and net income vs density for evolved agents."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules import sex


def life(seed):
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed))
    track = {}  # id -> dict
    for t in range(1500):
        for a in m.agents:
            if a.id >= 400 and t >= 300:
                d = track.setdefault(a.id, dict(sex=a.sex, born=t, fa=0, fert=0, inc=0.0, first=None,
                                                births_age=[], e=a.initial_sugar, at_start=None, m=a.metabolism))
                if a.fertility_start <= a.age < a.fertility_end:
                    d["fa"] += 1
                    d["inc"] += a.last_income
                    if sex.is_fertile(a):
                        d["fert"] += 1
                if a.age == a.fertility_start:
                    d["at_start"] = a.sugar / a.initial_sugar
        before = {a.id: len(a.children) for a in m.agents}
        m.step()
        for a in m.agents + m.dead_this_step:
            if a.id in track and len(a.children) > before.get(a.id, 0):
                track[a.id]["births_age"] += [a.age] * (len(a.children) - before.get(a.id, 0))
        for a in m.dead_this_step:
            if a.id in track:
                track[a.id]["done"] = a.age >= a.max_age
    return [d for d in track.values() if d.get("done") and d["born"] >= 300]


def income(args):
    n, seed = args
    m = Model(Config(initial_population=n, vision=(5, 6), metabolism=(1, 1), endowment=(1000, 1000), seed=seed))
    net = []
    for t in range(200):
        m.step()
        if t >= 50:
            net.append(np.mean([a.last_income for a in m.agents]))
    return n, np.mean(net)


if __name__ == "__main__":
    with ProcessPoolExecutor(8) as pool:
        lives = [d for ds in pool.map(life, range(5)) for d in ds]
        inc = list(pool.map(income, [(n, s) for n in (250, 350, 500, 700, 1000) for s in range(2)]))
    for sx in ("F", "M"):
        ds = [d for d in lives if d["sex"] == sx]
        kids = Counter(min(len(d["births_age"]), 4) for d in ds)
        n = len(ds)
        print(f"{sx}: {n} completed lives | mean children {np.mean([len(d['births_age']) for d in ds]):.2f} | "
              f"0/1/2/3/4+: " + " ".join(f"{kids[k] / n:.2f}" for k in range(5)))
        print(f"   fertile-age years {np.mean([d['fa'] for d in ds]):.1f}, of which wealth-fertile "
              f"{np.mean([d['fert'] for d in ds]):.1f}; net income while fertile-age {np.sum([d['inc'] for d in ds]) / max(1, np.sum([d['fa'] for d in ds])):.2f}/yr")
        st = [d["at_start"] for d in ds if d["at_start"] is not None]
        print(f"   wealth/threshold at fertility start: mean {np.mean(st):.2f}, share >=1: {np.mean(np.array(st) >= 1):.2f}")
        ages = [d["births_age"] for d in ds if d["births_age"]]
        first = [a[0] for a in ages]
        gaps = [b - a for x in ages for a, b in zip(x, x[1:])]
        print(f"   age at first child {np.mean(first):.1f}; gap between children {np.mean(gaps) if gaps else float('nan'):.1f}")
        for mm in (1, 2):
            sub = [d for d in ds if d["m"] == mm]
            if sub:
                print(f"   metabolism {mm}: {len(sub)} lives, mean children {np.mean([len(d['births_age']) for d in sub]):.2f}")
    print("Evolved agents (m=1, vision 5-6, immortal, rich): mean net income per agent, t=50-200")
    for n in (250, 350, 500, 700, 1000):
        print(f"   N={n}: {np.mean([v for k, v in inc if k == n]):+.2f}")
