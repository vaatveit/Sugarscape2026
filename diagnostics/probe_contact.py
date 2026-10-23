"""Diagnostic only: how far III-1's births are limited by contact vs wealth.

Contact modes widen who counts as a mating neighbor (sex.mate calls model.neighbors_of; III-1 runs no
other neighbor rule): "book" = von Neumann; "r2" = every agent within Chebyshev radius 2 (24 sites);
"global" = up to 4 random fertile opposite-sex agents anywhere (contact is free). Thresholds: the book's
1.0 and the calibrated 0.83.
"""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

STEPS = 1000


def run(args):
    exp_id, mode, thr, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed, fertility_threshold=thr))
    base = Model.neighbors_of
    if mode == "r2":
        def nbrs(agent):
            out = []
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    if dx or dy:
                        o = m.agent_at(agent.x + dx, agent.y + dy)
                        if o is not None:
                            out.append(o)
            return out
        m.neighbors_of = nbrs
    elif mode == "global":
        def nbrs(agent):
            if not sex.is_fertile(agent, thr):
                return base(m, agent)
            pool = [o for o in m.agents if o.sex not in (None, agent.sex) and sex.is_fertile(o, thr)]
            idx = m.rng.permutation(len(pool))[:4]
            return [pool[int(i)] for i in idx]
        m.neighbors_of = nbrs
    pops, births = [len(m.agents)], []
    for _ in range(STEPS):
        b = m.agents_ever
        m.step()
        births.append(m.agents_ever - b)
        pops.append(len(m.agents))
        if not m.agents or len(m.agents) > 2400:
            break
    pops += [pops[-1]] * (STEPS + 1 - len(pops))
    births += [0] * (STEPS - len(births))
    return args, (pops, births)


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-1"
    variants = [(mo, th) for th in (1.0, 0.83) for mo in ("book", "r2", "global")]
    tasks = [(exp_id, mo, th, s) for mo, th in variants for s in range(3)]
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, tasks))
    print(f"{exp_id} (3 seeds)  book Fig III-1: t20=470 t85=570 t240=415 late(300-1000)~500")
    for mo, th in variants:
        rs = [r for (e, m_, t_, s), r in out if (m_, t_) == (mo, th)]
        p = np.array([r[0] for r in rs], float)
        b = np.array([r[1] for r in rs], float)
        print(f"  {mo:6s} thr={th:<4} t20={p[:, 20].mean():5.0f} t85={p[:, 85].mean():5.0f} t240={p[:, 240].mean():5.0f} "
              f"late={p[:, 300:].mean():5.0f} births/period t2-20={b[:, 2:20].mean():4.1f} t20-85={b[:, 20:85].mean():4.1f} "
              f"late={b[:, 300:].mean():4.1f}")
