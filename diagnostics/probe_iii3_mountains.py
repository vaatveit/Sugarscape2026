"""III-3: does the society keep both mountains? Floor, period and level split by mountains held,
plus the founding crash and when a mountain empties."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period, window_min
from sugarscape.model import Model

STEPS = 2500


def run(args):
    exp_id, founders, theta, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, founder_ages=founders, fertility_threshold=theta, seed=seed))
    pop, ne, lost = [], [], None
    for t in range(STEPS):
        a = m.agents
        pop.append(len(a))
        k = sum(g.x >= 25 and g.y >= 25 for g in a)  # NE quadrant holds the NE mountain; SW the other
        sw = sum(g.x < 25 and g.y < 25 for g in a)
        ne.append((k, sw))
        if lost is None and a and (k == 0 or sw == 0) and t > 0:
            lost = t
        m.step()
    series = [{"t": t, "population": p} for t, p in enumerate(pop)]
    late = ne[-500:]
    both = all(min(x) > 0 for x in late)
    return dict(founders=founders, theta=theta, seed=seed, pop=pop, both=both, lost=lost,
                crash=min(pop[:300]), crash_t=int(np.argmin(pop[:300])),
                floor=window_min("population", 300, STEPS)(series), period=dominant_period("population", 300, STEPS)(series),
                level=float(np.mean(pop[500:])), mins=[min(x) for x in ne[:300:25]])


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-3"
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    cases = [(exp_id, f, th, s) for f, th in (("uniform", 0.83), ("zero", 0.83), ("uniform", 1.0), ("zero", 1.0)) for s in range(seeds)]
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, cases))
    for f, th in (("uniform", 0.83), ("zero", 0.83), ("uniform", 1.0), ("zero", 1.0)):
        rs = [r for r in res if r["founders"] == f and r["theta"] == th]
        print(f"== {exp_id} founders={f} theta={th}")
        for r in rs:
            state = "extinct" if r["pop"][-1] == 0 else ("both mountains" if r["both"] else "one mountain")
            print(f"  seed {r['seed']}: {state:14s} first mountain emptied t={r['lost']} crash {r['crash']}@{r['crash_t']} "
                  f"floor {r['floor']:.0f} period {r['period']} level {r['level']:.0f} | smaller mountain t=0..275: {r['mins']}")
        for state in ("both", "one"):
            sub = [r for r in rs if r["pop"][-1] and (r["both"] if state == "both" else not r["both"])]
            if sub:
                print(f"  {state}: {len(sub)} runs, level {np.mean([r['level'] for r in sub]):.0f}, floor {np.mean([r['floor'] for r in sub]):.0f}, "
                      f"period {np.nanmean([r['period'] for r in sub]):.0f} ({sum(np.isfinite(r['period']) for r in sub)}/{len(sub)})")
