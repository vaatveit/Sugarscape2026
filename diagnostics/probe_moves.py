"""Movement variants (diagnostic): harvest per evolved agent at fixed N, Fig II-5 m2 points, II-4, III-1.
book    = nearest of the richest visible sites, own site at distance 0 (current model)
anydist = a random one of the richest visible sites, ignoring distance (spreads agents)
mustmove= own site excluded unless nothing else is visible
"""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
import sugarscape.rules.movement as mv
from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model

ORIG = mv.move


def make_move(kind):
    if kind == "book":
        return ORIG

    def move(model, agent):
        cands = mv.candidate_sites(model, agent)
        if kind == "mustmove" and len(cands) > 1:
            cands = cands[1:]
        scores = [mv.site_score(model, x, y) for x, y, _ in cands]
        best = max(scores)
        tops = [c for c, s in zip(cands, scores) if s == best]
        if kind == "mustmove":
            dmin = min(d for _, _, d in tops)
            tops = [c for c in tops if c[2] == dmin][:1]
        x, y, _ = tops[int(model.rng.integers(len(tops)))]
        agent.moved = (x, y) != (agent.x, agent.y)
        model.move_agent(agent, x, y)
        ls = model.landscape
        agent.last_income = float(ls.sugar[x, y])
        agent.sugar += ls.sugar[x, y]
        ls.sugar[x, y] = 0.0
    return move


def task(args):
    kind, what, seed = args
    mv.move = make_move(kind)
    if what.startswith("N="):
        n = int(what[2:])
        m = Model(Config(initial_population=n, vision=(5, 6), metabolism=(1, 1), endowment=(1000, 1000), seed=seed))
        h = []
        for t in range(200):
            m.step()
            if t >= 50:
                h.append(np.mean([a.last_income + 1 for a in m.agents]))
        return args, np.mean(h)
    exp = EXPERIMENTS[what]
    m = Model(replace(exp.config, seed=seed))
    pops = []
    for t in range(1000 if what == "III-1" else 500):
        m.step()
        pops.append(len(m.agents))
    if what == "III-1":
        return args, np.mean(pops[300:])
    return args, (np.mean(pops[44:60]), pops[-1])


if __name__ == "__main__":
    kinds = ("book", "anydist", "mustmove")
    whats = ["N=350", "N=500", "N=700", "II-5/m2/v2", "II-5/m2/v5.5", "II-5/m3/v3", "II-4", "III-1"]
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(task, [(k, w, s) for k in kinds for w in whats for s in range(3)]))
    book = {"II-5/m2/v2": 365, "II-5/m2/v5.5": 390, "II-5/m3/v3": 255, "II-4": 224, "III-1": 500}
    for k in kinds:
        print(k)
        for w in whats:
            vals = [v for (k_, w_, s), v in out if (k_, w_) == (k, w)]
            if w.startswith("N="):
                print(f"   {w}: harvest per evolved agent {np.mean(vals):.2f}")
            elif w == "III-1":
                print(f"   III-1 mean t=300-1000: {np.mean(vals):.0f} (book ~500)")
            else:
                a = np.array(vals)
                print(f"   {w}: t=45-60 {a[:, 0].mean():.0f}, t=500 {a[:, 1].mean():.0f} (book {book[w]})")
