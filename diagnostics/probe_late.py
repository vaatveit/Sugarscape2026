"""Diagnostic: is the late III-1 population birth-limited or food-limited? Threshold theta for all
(cost = book's half endowment, compounding as in the book via Config.fertility_threshold)."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model


def run(args):
    th, seed = args
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed, fertility_threshold=th))
    pops, starve, old, births, met, vis, wealth_d = [], 0, 0, 0, [], [], []
    for t in range(1000):
        b = m.agents_ever
        m.step()
        if t >= 300:
            o = sum(1 for a in m.dead_this_step if a.age >= a.max_age)
            old += o
            starve += m.deaths_this_step - o
            births += m.agents_ever - b
            wealth_d += [a.sugar for a in m.dead_this_step if a.age >= a.max_age]
            if t % 50 == 0:
                met.append(np.mean([a.metabolism for a in m.agents]))
                vis.append(np.mean([a.vision for a in m.agents]))
        pops.append(len(m.agents))
        if len(m.agents) > 2400:
            break
    k = 700
    return args, (np.mean(pops[150:160]), np.mean(pops[300:]), births / k, old / k, starve / k,
                  np.mean(met), np.mean(vis), np.mean(wealth_d) if wealth_d else np.nan)


if __name__ == "__main__":
    ths = (1.0, 0.83, 0.75, 0.5)
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, [(th, s) for th in ths for s in range(3)]))
    print("III-1, t=300-1000 per period (3 seeds); book late ~500, t150 ~400, vision 5.3, metabolism 1.0")
    for th in ths:
        r = np.array([v for (t_, s), v in out if t_ == th])
        print(f"  theta={th:<4} t150={r[:, 0].mean():5.0f} late N={r[:, 1].mean():5.0f} births={r[:, 2].mean():5.2f} "
              f"old-age deaths={r[:, 3].mean():5.2f} starvation={r[:, 4].mean():5.2f} metab={r[:, 5].mean():.2f} "
              f"vision={r[:, 6].mean():.2f} wealth at old-age death={r[:, 7].mean():.0f}")
