"""Does the torus wrap contaminate the x+y centroid and anti-diagonal side metrics? (diagnostic only)"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys, math
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from dataclasses import replace

cap = Model(EXPERIMENTS["III-12"].config).landscape.capacity
W = 50
pts = np.argwhere(cap == 4)
sw_peak = pts[pts.sum(1) < W].mean(0); ne_peak = pts[pts.sum(1) >= W].mean(0)
print("capacity-4 centroids: SW", np.round(sw_peak, 1), "NE", np.round(ne_peak, 1))

def tdist(a, b):
    d = np.abs(np.asarray(a) - np.asarray(b)); d = np.minimum(d, W - d); return float(np.hypot(*d))

def side_peak(a):
    return "SW" if tdist((a.x, a.y), sw_peak) <= tdist((a.x, a.y), ne_peak) else "NE"

def side_diag(a):
    return "SW" if a.x + a.y < W else "NE"

def unwrapped(v, v0):
    return ((v - v0 + W // 2) % W) - W // 2

for exp_id in ("III-12", "III-13"):
    exp = EXPERIMENTS[exp_id]
    for k in range(2):
        m = Model(replace(exp.config, seed=exp.config.seed + k))
        start = {a.id: (a.x, a.y) for a in m.agents}
        blue0 = np.mean([a.x + a.y for a in m.agents if a.tribe == "blue"])
        red0 = np.mean([a.x + a.y for a in m.agents if a.tribe == "red"])
        for _ in range(50):
            m.step()
        blues = [a for a in m.agents if a.tribe == "blue"]; reds = [a for a in m.agents if a.tribe == "red"]
        raw_b = np.mean([a.x + a.y for a in blues]) - blue0
        raw_r = np.mean([a.x + a.y for a in reds]) - red0
        unw_b = np.mean([unwrapped(a.x, start[a.id][0]) + unwrapped(a.y, start[a.id][1]) for a in blues])
        unw_r = np.mean([unwrapped(a.x, start[a.id][0]) + unwrapped(a.y, start[a.id][1]) for a in reds])
        wrapped_b = sum(1 for a in blues if a.x >= 40 or a.y >= 40)
        wrapped_r = sum(1 for a in reds if a.x < 10 or a.y < 10)
        print(f"{exp_id} seed{k} t=50: blue shift raw {raw_b:+.1f} vs unwrapped displacement {unw_b:+.1f} "
              f"(blues alive {len(blues)}, of which across the wrap {wrapped_b}); red raw {raw_r:+.1f} vs unwrapped {unw_r:+.1f} "
              f"(reds {len(reds)}, across the wrap {wrapped_r})")

for exp_id, T in (("III-9", 1000), ("III-15", 1000)):
    exp = EXPERIMENTS[exp_id]
    seeds = range(exp.seeds) if exp_id == "III-9" else range(8)
    for k in seeds:
        m = Model(replace(exp.config, seed=exp.config.seed + k))
        traj = []
        for t in range(T + 1):
            if exp_id == "III-9" and t in (100, 250, 500, 750, 1000):
                nb = sum(a.tribe == "blue" for a in m.agents); nr = len(m.agents) - nb
                traj.append((t, nb, nr))
            if t < T:
                m.step()
        def shares(side_fn):
            out = {}
            for s in ("SW", "NE"):
                g = [a for a in m.agents if side_fn(a) == s]
                nb = sum(a.tribe == "blue" for a in g)
                out[s] = (len(g), round(nb / len(g), 3) if g else None)
            return out
        print(f"{exp_id} seed{k} t={T}: pop {len(m.agents)}  anti-diagonal sides {shares(side_diag)}  nearest-peak sides {shares(side_peak)}"
              + (f"  traj(t,nb,nr) {traj}" if traj else ""))
