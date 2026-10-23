"""III-3 (fertility ends 10 years earlier): trajectory, floor, period, late level and women's lifetime births,
under founder ages spread/zero and threshold 0.83/1.0."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period, window_min
from sugarscape.model import Model

STEPS = 2500


def run(args):
    founders, theta, seed, exp_id = args
    m = Model(replace(EXPERIMENTS[exp_id].config, founder_ages=founders, fertility_threshold=theta, seed=seed))
    pop, vis, met, lives = [], [], [], {}
    for t in range(STEPS):
        pop.append(len(m.agents))
        if m.agents:
            vis.append(np.mean([a.vision for a in m.agents])); met.append(np.mean([a.metabolism for a in m.agents]))
        before = {a.id: len(a.children) for a in m.agents}
        for a in m.agents:
            if t >= 500 and a.id >= 400 and a.fertility_start <= a.age < a.fertility_end:
                d = lives.setdefault(a.id, dict(sex=a.sex, fa=0, inc=0.0, kids=0, ages=[]))
                d["fa"] += 1; d["inc"] += a.last_income
        m.step()
        for a in m.agents + m.dead_this_step:
            k = len(a.children) - before.get(a.id, len(a.children))
            if k > 0 and a.id in lives:
                lives[a.id]["kids"] += k; lives[a.id]["ages"] += [a.age] * k
        for a in m.dead_this_step:
            if a.id in lives:
                lives[a.id]["done"] = a.age >= a.max_age
        if not m.agents:
            pop += [0] * (STEPS - t - 1)
            break
    series = [{"t": t, "population": p} for t, p in enumerate(pop)]
    done = [d for d in lives.values() if d.get("done")]
    return dict(founders=founders, theta=theta, seed=seed, pop=pop, floor=window_min("population", 300, 2500)(series),
                period=dominant_period("population", 300, 2500)(series), vis=vis[-1] if vis else np.nan,
                met=met[-1] if met else np.nan, lives=done)


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-3"
    cases = [(f, th, s, exp_id) for f in ("uniform", "zero") for th in (0.83, 1.0) for s in range(5)]
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, cases))
    for f in ("uniform", "zero"):
        for th in (0.83, 1.0):
            rs = [r for r in res if r["founders"] == f and r["theta"] == th]
            print(f"== {exp_id} founders={f} theta={th}")
            for r in rs:
                p = r["pop"]
                late = np.mean(p[500:]) if p[-1] else 0
                print(f"  seed {r['seed']}: min<300 {min(p[:300])}@{int(np.argmin(p[:300]))} late mean {late:.0f} "
                      f"floor {r['floor']:.0f} period {r['period']} vis {r['vis']:.2f} met {r['met']:.2f} | "
                      + " ".join(str(p[t]) for t in range(0, STEPS, 100)))
            women = [d for r in rs for d in r["lives"] if d["sex"] == "F"]
            if women:
                c = Counter(min(d["kids"], 4) for d in women); n = len(women)
                print(f"  women (born-after-founders lives, t>=500): {n}, mean kids {np.mean([d['kids'] for d in women]):.2f}, "
                      f"0/1/2/3/4+ " + " ".join(f"{c[k]/n:.2f}" for k in range(5))
                      + f", fertile-age yrs {np.mean([d['fa'] for d in women]):.1f}, net income {sum(d['inc'] for d in women)/max(1,sum(d['fa'] for d in women)):.2f}")
