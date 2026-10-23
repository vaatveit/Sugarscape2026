"""Compare our III-1 trajectories with the animation run (Anim III-2/III-3 frames: 384, 172, 325, 876,
669, 1019 agents; frame 2 confined to the two peaks)."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model


def run(args):
    ages, th, seed = args
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed, founder_ages=ages, fertility_threshold=th))
    cap = m.landscape.capacity if hasattr(m.landscape, "capacity") else None
    pops, peak_share = [len(m.agents)], []
    for t in range(1500):
        m.step()
        pops.append(len(m.agents))
        peak_share.append(np.mean([cap[a.x, a.y] >= 3 for a in m.agents]) if m.agents else np.nan)
    p = np.array(pops)
    tmin = int(np.argmin(p[:400]))
    return args, (p[tmin], tmin, peak_share[tmin - 1] if tmin else np.nan, p[300:].mean(), p[300:].max(),
                  p[300:].min())


if __name__ == "__main__":
    grid = [(a, th) for a in ("uniform", "zero") for th in (1.0, 0.83, 0.75)]
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, [(a, th, s) for a, th in grid for s in range(5)]))
    print("Animation run: 384 -> 172 (on the peaks) -> 325 -> 876 -> 669 -> 1019; Fig III-1 run: 400-575")
    for a, th in grid:
        r = np.array([v for (a_, t_, s), v in out if (a_, t_) == (a, th)], float)
        print(f"  founders {a:7s} theta={th:<4}: min N {r[:, 0].mean():4.0f} at t={r[:, 1].mean():4.0f} "
              f"(share on capacity>=3 sites {r[:, 2].mean():.2f}) | t=300-1500 mean {r[:, 3].mean():4.0f} "
              f"range {r[:, 5].mean():4.0f}-{r[:, 4].mean():4.0f}")
