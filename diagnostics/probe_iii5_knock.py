"""III-5 kick: settle to t=600, cull at random to K, follow AFTER periods. Extinctions, trough depths, and the
rebound's first peak and trough. argv: K, seeds, 'global' for free contact."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

T_KNOCK, AFTER = 600, 900


def run(args):
    k, seed, glob = args
    m = Model(replace(EXPERIMENTS["III-5"].config, seed=seed))
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
    rng = np.random.default_rng(seed + 99)
    pop = []
    for t in range(T_KNOCK + AFTER):
        if t == T_KNOCK:
            for a in [m.agents[int(i)] for i in rng.permutation(len(m.agents))[: max(0, len(m.agents) - k)]]:
                m.kill(a)
        pop.append(len(m.agents))
        if not m.agents:
            break
        m.step()
    p = np.array(pop + [0] * (T_KNOCK + AFTER - len(pop)), float)[T_KNOCK:]
    return seed, p


if __name__ == "__main__":
    k = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    glob = len(sys.argv) > 3 and sys.argv[3] == "global"
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(k, s, glob) for s in range(seeds)]))
    ext = 0
    for s, p in res:
        pk = int(np.argmax(p[:150])); tr = pk + int(np.argmin(p[pk:pk + 200]))
        dead = int(np.argmax(p == 0)) if (p == 0).any() else None
        ext += dead is not None
        s9 = np.convolve(p, np.ones(9) / 9, "same")
        troughs = [int(s9[t]) for t in range(60, len(p) - 60) if s9[t] == s9[t - 50:t + 51].min() and s9[t - 50:t + 51].max() - s9[t] > 300]
        print(f"  seed {s}: rebound peak {p[pk]:.0f}@+{pk}, first trough {p[tr]:.0f}@+{tr} | later troughs {troughs[1:6]} | "
              + (f"EXTINCT at +{dead}" if dead is not None else f"alive, min after +300 {p[300:].min():.0f}"))
    print(f"III-5 cull to {k}{' global contact' if glob else ''}: {ext}/{len(res)} extinct within {AFTER} periods")
