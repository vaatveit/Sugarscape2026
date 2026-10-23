"""III-4: what each mating turn of a wealth-fertile agent meets, along the first cycles (default config).
Counted at the turn (after the agent's own move): neighbors, fertile opposite-sex neighbors, and pairs blocked
for want of an empty site; births per turn. Also the age structure (share under fertility age)."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS, W = 400, 20


def run(seed):
    m = Model(replace(EXPERIMENTS["III-4"].config, seed=seed))
    th = m.config.fertility_threshold
    orig = sex.mate
    acc = np.zeros((STEPS, 7))  # turns, neighbors, partner turns, partners, blocked pairs, births, opposite-sex fertile-age nbrs

    def mate(model, agent):
        t = model.t
        if sex.is_fertile(agent, th):
            nb = model.neighbors_of(agent)
            partners = [o for o in nb if o.sex not in (None, agent.sex) and sex.is_fertile(o, th)]
            fa = [o for o in nb if o.sex not in (None, agent.sex) and o.fertility_start <= o.age < o.fertility_end]
            blocked = sum(1 for o in partners if not (sex._empty_sites(model, agent) + sex._empty_sites(model, o)))
            kids = orig(model, agent)
            acc[t] += (1, len(nb), bool(partners), len(partners), blocked, len(kids), len(fa))
            return kids
        return orig(model, agent)

    sex.mate = mate
    rows = []
    for t in range(STEPS):
        a = m.agents
        rows.append((len(a), np.mean([g.age < g.fertility_start for g in a]),
                     np.mean([g.fertility_start <= g.age < g.fertility_end for g in a])))
        m.step()
    sex.mate = orig
    return np.hstack([np.array(rows), acc])


if __name__ == "__main__":
    with ProcessPoolExecutor(5) as pool:
        r = np.mean(list(pool.map(run, range(5))), axis=0)
    print("  t     N  under-age  fertile-age | fertile turns  nbrs/turn  opp-sex fertile-age nbrs/turn  turns with a partner  "
          "blocked pairs  births  births per fertile turn")
    for t0 in range(0, STEPS, W):
        x = r[t0:t0 + W].mean(axis=0)
        n, young, fage, turns, nb, pt, p, bl, kids, fa = x
        print(f"{t0:4d} {n:5.0f} {young:9.2f} {fage:12.2f} | {turns:13.0f} {nb / max(turns, 1):10.2f} {fa / max(turns, 1):30.2f} "
              f"{pt / max(turns, 1):21.3f} {bl:14.1f} {kids:7.1f} {kids / max(turns, 1):10.3f}")
