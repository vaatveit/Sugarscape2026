"""III-3 cycle shape: peak-to-peak intervals, peak/trough levels, early transient, by founder ages (theta 0.83)."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model

STEPS = 2500


def run(args):
    founders, seed, extra = args
    m = Model(replace(EXPERIMENTS["III-3"].config, founder_ages=founders, seed=seed, **extra))
    pop, ne, births = [], [], []
    for t in range(STEPS):
        pop.append(len(m.agents))
        ne.append(min(sum(g.x >= 25 and g.y >= 25 for g in m.agents), sum(g.x < 25 and g.y < 25 for g in m.agents)))
        m.step()
    return founders, seed, np.array(pop), np.array(ne), np.array(births, dtype=float)


def turning_points(x, smooth=41, min_swing=40):
    """Zigzag on a centred moving average: alternate extremes, each reversal at least min_swing."""
    h = smooth // 2
    s = np.array([x[max(0, i - h): i + h + 1].mean() for i in range(len(x))])
    pts, ext = [], 0
    direction = 1 if s[50] >= s[0] else -1
    for i in range(1, len(s)):
        if direction == 1 and s[i] > s[ext] or direction == -1 and s[i] < s[ext]:
            ext = i
        if direction == 1 and s[i] < s[ext] - min_swing:
            pts.append(("peak", ext, s[ext])); direction, ext = -1, i
        elif direction == -1 and s[i] > s[ext] + min_swing:
            pts.append(("trough", ext, s[ext])); direction, ext = 1, i
    return pts


if __name__ == "__main__":
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(f, s, {}) for f in ("zero", "uniform") for s in range(seeds)]))
    for f, s, pop, ne, births in res:
        if pop[-1] == 0:
            print(f"{f:7s} seed {s}: extinct"); continue
        both = ne[-500:].min() > 0
        tp = [p for p in turning_points(pop) if p[1] >= 250]
        peaks = [p[1] for p in tp if p[0] == "peak"]; troughs = [p for p in tp if p[0] == "trough"]
        iv = np.diff(peaks)
        print(f"{f:7s} seed {s}: {'both' if both else 'one '} | t=0,25,50,100,150,200: {pop[[0,25,50,100,150,200]].tolist()} | "
              f"peaks {len(peaks)} interval median {np.median(iv) if len(iv) else np.nan:.0f} (IQR {np.percentile(iv,25) if len(iv) else 0:.0f}-{np.percentile(iv,75) if len(iv) else 0:.0f}) "
              f"peak level {np.mean([p[2] for p in tp if p[0]=='peak']) if peaks else np.nan:.0f} trough level {np.mean([p[2] for p in troughs]) if troughs else np.nan:.0f} "
              f"| autocorr period {dominant_period('population', 300, STEPS)([{'t': t, 'population': v} for t, v in enumerate(pop)])}")
