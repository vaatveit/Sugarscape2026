"""Diagnostic: p.56's "genetic makeup (metabolism, vision, maximum age, and so forth)" read to include fertility
ages. A child takes its fertility onset from a random parent and its fertility end from its same-sex parent
(fresh draws are our current call). Effect on III-1, III-3, III-4, III-5, and the spread of fertility ages late."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS = 1500


def run(args):
    exp_id, variant, seed = args
    orig = sex.mate
    if variant == "inherit":
        def mate(model, agent):
            kids = orig(model, agent)
            for k in kids:
                other = next(o for o in model.neighbors_of(agent) if k in o.children) if kids else None
                parents = (agent, other)
                k.fertility_start = parents[int(model.rng.integers(2))].fertility_start
                k.fertility_end = (agent if agent.sex == k.sex else other).fertility_end
            return kids
        sex.mate = mate
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    pop = []
    for _ in range(STEPS):
        pop.append(len(m.agents))
        if not m.agents:
            break
        m.step()
    sex.mate = orig
    w = [a.fertility_end for a in m.agents if a.sex == "F"]
    return exp_id, variant, seed, np.array(pop + [0] * (STEPS - len(pop)), float), (np.mean(w), np.std(w)) if w else (np.nan, np.nan)


def troughs(p):
    s9 = np.convolve(p, np.ones(9) / 9, "same")
    return [int(p[t]) for t in range(150, len(p) - 60) if p[t] > 0 and s9[t] == s9[t - 50:t + 51].min() and s9[t - 50:t + 51].max() - s9[t] > 300]


if __name__ == "__main__":
    cases = [(e, v, s) for e, n in (("III-1", 5), ("III-3", 5), ("III-4", 5), ("III-5", 10)) for v in ("default", "inherit") for s in range(n)]
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, cases))
    for e in ("III-1", "III-3", "III-4", "III-5"):
        for v in ("default", "inherit"):
            rs = [r for r in res if r[0] == e and r[1] == v]
            ps = [r[3] for r in rs]
            alive = [p for p in ps if not (p == 0).any()]
            tr = [x for p in ps for x in troughs(p)]
            print(f"{e} {v:8s}: extinct {sum((p == 0).any() for p in ps)}/{len(ps)} | mean t=300-1500 "
                  f"{np.mean([p[300:].mean() for p in alive]) if alive else float('nan'):.0f} | min t>=300 "
                  f"{np.mean([p[300:].min() for p in alive]) if alive else float('nan'):.0f} | range t=1000-1500 "
                  f"{np.mean([p[1000:].max() - p[1000:].min() for p in alive]) if alive else float('nan'):.0f} | troughs min/median "
                  f"{min(tr) if tr else '-'}/{int(np.median(tr)) if tr else '-'} | women's fertility end late {np.nanmean([r[4][0] for r in rs]):.1f} sd {np.nanmean([r[4][1] for r in rs]):.1f}")
