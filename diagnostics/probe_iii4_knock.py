"""Perturbation: run III-4 to t=600 (evolved, settled), cull at random to K agents, and watch the rebound.
Births per period by population 20 periods earlier, compared with the book's response curve; and whether a
sustained cycle follows. Variants via argv (Config overrides, or '_global' for free contact)."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import ast
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

T_KNOCK, STEPS, K = 600, 2100, 400
EDGES = [300, 500, 700, 900, 1100, 1300, 1500, 1700]
BOOK = [32.2, 32.2, 27.0, 18.8, 12.7, 7.5, 6.6]


def run(args):
    seed, extra = args
    extra = dict(extra)
    glob = extra.pop("_global", False)
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
    pop, births, fert, partner = [], [], [], []
    rng = np.random.default_rng(seed + 99)
    for t in range(STEPS):
        if t == T_KNOCK:
            ma = np.array([a.max_age for a in m.agents]); stats = (ma.mean(), ma.std())
            victims = rng.permutation(len(m.agents))[: max(0, len(m.agents) - K)]
            for a in [m.agents[int(i)] for i in victims]:
                m.kill(a)
        pop.append(len(m.agents))
        ids = m._next_id
        m.step()
        births.append(m._next_id - ids)
    return np.array(pop, float), np.array(births, float), stats


if __name__ == "__main__":
    extra = ast.literal_eval(sys.argv[1]) if len(sys.argv) > 1 else {}
    with ProcessPoolExecutor(5) as pool:
        res = list(pool.map(run, [(s, extra) for s in range(5)]))
    print(f"III-4 {extra}: cull to {K} at t={T_KNOCK}")
    for p, b, st in res:
        after = p[T_KNOCK:]
        pk = int(np.argmax(after[:150])); tr = pk + int(np.argmin(after[pk:pk + 150]))
        print(f"  max age at cull {st[0]:.0f} sd {st[1]:.0f} | before {p[T_KNOCK - 100:T_KNOCK].mean():.0f} | rebound peak {after[pk]:.0f} at +{pk}, next trough {after[tr]:.0f} at +{tr} | "
              f"range +300..+600 {after[300:].max() - after[300:].min():.0f} | births/period +0..20 {b[T_KNOCK:T_KNOCK + 20].mean():.1f}, "
              f"+20..40 {b[T_KNOCK + 20:T_KNOCK + 40].mean():.1f}, max 20-period mean {max(b[T_KNOCK + i:T_KNOCK + i + 20].mean() for i in range(0, 100, 5)):.1f}")
    print("  range in 300-period windows after the cull (each seed):")
    for p, _, _ in res:
        print("   ", " ".join(f"{p[T_KNOCK + a:T_KNOCK + a + 300].max() - p[T_KNOCK + a:T_KNOCK + a + 300].min():5.0f}" for a in range(0, 1500, 300)))
    P = np.concatenate([p[T_KNOCK - 20 + 20:T_KNOCK + 200] for p, _, _ in res]); Plag = np.concatenate([p[T_KNOCK - 20:T_KNOCK + 180] for p, _, _ in res])
    B = np.concatenate([np.convolve(b, np.ones(9) / 9, "same")[T_KNOCK:T_KNOCK + 200] for _, b, _ in res])
    row = []
    for lo, hi in zip(EDGES, EDGES[1:]):
        sel = (Plag >= lo) & (Plag < hi)
        row.append(f"{B[sel].mean():5.1f}" if sel.sum() > 10 else "  -  ")
    print("  births by N 20 periods earlier (rebound, t=+0..+200):", " | ".join(f"{a}-{z}" for a, z in zip(EDGES, EDGES[1:])))
    print("  ours:", " | ".join(row))
    print("  book:", " | ".join(f"{v:5.1f}" for v in BOOK))
