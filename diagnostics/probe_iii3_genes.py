"""III-3 at theta 0.83: late level against the genotypes that the founding bottleneck leaves (max age, vision)."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

STEPS = 2000


def run(args):
    founders, seed, exp_id = args
    m = Model(replace(EXPERIMENTS[exp_id].config, founder_ages=founders, seed=seed))
    rows = []
    for t in range(STEPS):
        if t % 100 == 0 or t == STEPS - 1:
            a = m.agents
            rows.append((t, len(a), np.mean([g.max_age for g in a]) if a else np.nan,
                         np.mean([g.vision for g in a]) if a else np.nan,
                         np.mean([g.metabolism for g in a]) if a else np.nan,
                         np.mean([g.initial_sugar for g in a]) if a else np.nan))
        m.step()
        if not m.agents:
            break
    late = [r for r in rows if r[0] >= 1000]
    return founders, seed, rows, late


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-3"
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(f, s, exp_id) for f in ("uniform", "zero") for s in range(seeds)]))
    pts = []
    for f, s, rows, late in res:
        if not late or late[-1][1] == 0:
            print(f"{f:7s} seed {s}: extinct by t={rows[-1][0]}")
            continue
        n, ma, v, mt, age = (np.mean([r[k] for r in late]) for k in (1, 2, 3, 4, 5))
        pts.append((n, ma, v, age))
        early = rows[3]  # t=300
        print(f"{f:7s} seed {s}: t>=1000 N {n:5.0f} max age {ma:5.1f} vision {v:4.2f} metab {mt:4.2f} endowment {age:5.1f}"
              f" | at t=300: N {early[1]} max age {early[2]:.1f} vision {early[3]:.2f} endowment {early[5]:.1f}")
    p = np.array(pts)
    print("corr(N, max age) %.2f  corr(N, vision) %.2f  corr(N, endowment) %.2f" % (
        np.corrcoef(p[:, 0], p[:, 1])[0, 1], np.corrcoef(p[:, 0], p[:, 2])[0, 1], np.corrcoef(p[:, 0], p[:, 3])[0, 1]))
