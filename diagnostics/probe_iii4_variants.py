"""Diagnostic only: which change gives III-4 the book's swings (first peak 1551@75, trough 346@148, later
peaks ~1550 / troughs 400-650, period ~134)? Reports the first peak/trough, late range, period, starvation
share and the births-per-period range (20-period means) after t=300."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS = 1500
VARIANTS = {
    "default (spread, 0.83)": {},
    "theta 1.0 (VAR-book)": {"fertility_threshold": 1.0},
    "theta 0.5": {"fertility_threshold": 0.5},
    "age-0 founders": {"founder_ages": "zero"},
    "max age fixed at 80": {"max_age": (80, 80)},
    "global contact": {"_global": True},
    "child at nearest empty site": {"_place": "near"},
    "child at nearest empty site, global contact": {"_place": "near", "_global": True},
    "child at nearest empty site, theta 1.0": {"_place": "near", "fertility_threshold": 1.0},
}


def nearest_empty(model, agent, rmax=12):
    """Empty sites at the smallest Manhattan distance from the agent (ring search)."""
    for r in range(1, rmax + 1):
        ring = [model.landscape.wrap(agent.x + dx, agent.y + s * (r - abs(dx)))
                for dx in range(-r, r + 1) for s in ((1, -1) if r - abs(dx) else (1,))]
        empty = [p for p in ring if model.agent_at(*p) is None]
        if empty:
            return empty
    return []


def run(args):
    name, seed = args
    extra = dict(VARIANTS[name])
    glob = extra.pop("_global", False)
    place = extra.pop("_place", None)
    if place == "near":
        orig_empty = sex._empty_sites
        sex._empty_sites = lambda model, agent: orig_empty(model, agent) or nearest_empty(model, agent)
    m = Model(replace(EXPERIMENTS["III-4"].config, seed=seed, **extra))
    th = m.config.fertility_threshold
    if glob:
        base, cache = Model.neighbors_of, {}

        def nbrs(agent):
            if not sex.is_fertile(agent, th):
                return base(m, agent)
            if cache.get("t") != m.t:
                cache["t"], cache["pool"] = m.t, [o for o in m.agents if sex.is_fertile(o, th)]
            pool = [o for o in cache["pool"] if o.sex not in (None, agent.sex)]
            idx = m.rng.permutation(len(pool))[:8]
            return [pool[int(i)] for i in idx if pool[int(i)].alive][:4]
        m.neighbors_of = nbrs
    pop, births, starved, old = [], [], [], []
    for _ in range(STEPS):
        pop.append(len(m.agents))
        ids = m._next_id
        m.step()
        births.append(m._next_id - ids)
        o = sum(d.age >= d.max_age for d in m.dead_this_step)
        old.append(o); starved.append(len(m.dead_this_step) - o)
        if not m.agents:
            break
    n = len(pop)
    pad = lambda x: np.array(x + [0] * (STEPS - n), float)
    return name, seed, pad(pop), pad(births), pad(starved), pad(old)


if __name__ == "__main__":
    names = sys.argv[1:] or list(VARIANTS)
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(nm, s) for nm in names for s in range(3)]))
    print("book: first peak 1551@75, trough 346@148, late range ~900-1000, period ~134")
    for nm in names:
        print(f"== {nm}")
        for _, s, p, b, st, od in [r for r in res if r[0] == nm]:
            if p[-1] == 0:
                print(f"  seed {s}: extinct"); continue
            pk = int(np.argmax(p[:300])); tr = pk + int(np.argmin(p[pk:pk + 200]))
            bw = b[300:].reshape(-1, 20).mean(axis=1)
            per = dominant_period("population", 300, STEPS)([{"t": t, "population": v} for t, v in enumerate(p)])
            print(f"  seed {s}: first peak {p[pk]:.0f}@{pk} trough {p[tr]:.0f}@{tr} | range t=1000-1500 {p[1000:].max() - p[1000:].min():.0f} "
                  f"(mean {p[1000:].mean():.0f}) period {per} | starved share t>=300 {st[300:].sum() / max(1, st[300:].sum() + od[300:].sum()):.2f} "
                  f"| births/period t>=300: {bw.min():.1f}-{bw.max():.1f}")
