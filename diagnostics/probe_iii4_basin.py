"""Basin of III-4's large cycle: cull the settled society (t=600) at random to K agents and see which runs lock
into a sustained large cycle (range > 600 over the last 300 periods of 1,500 after the cull). Also characterize
locked runs: peaks, troughs and peak spacing over that window, plus mean max age, vision, endowment."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

T_KNOCK, AFTER = 600, 1500


GLOBAL = False


def run(args):
    k, seed = args
    m = Model(replace(EXPERIMENTS["III-4"].config, seed=seed))
    if GLOBAL:
        from sugarscape.rules import sex
        th, base, cache = m.config.fertility_threshold, Model.neighbors_of, {}

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
            victims = [m.agents[int(i)] for i in rng.permutation(len(m.agents))[: max(0, len(m.agents) - k)]]
            for a in victims:
                m.kill(a)
        pop.append(len(m.agents)); m.step()
    p = np.array(pop, float)[T_KNOCK:]
    genes = (np.mean([a.max_age for a in m.agents]), np.mean([a.vision for a in m.agents]), np.mean([a.initial_sugar for a in m.agents]))
    return k, seed, p, genes


def run_g(args):
    global GLOBAL
    GLOBAL = True
    return run(args)


def extremes(p, t0):
    s = np.convolve(p, np.ones(15) / 15, "same")
    pk = [t for t in range(t0, len(s) - 41) if s[t] == s[t - 40:t + 41].max() and s[t] - s[t - 40:t + 41].min() > 150]
    tr = [t for t in range(t0, len(s) - 41) if s[t] == s[t - 40:t + 41].min() and s[t - 40:t + 41].max() - s[t] > 150]
    return pk, tr


if __name__ == "__main__":
    ks = [int(x) for x in sys.argv[1].split(",")] if len(sys.argv) > 1 else [300, 400, 600, 800]
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    GLOBAL = len(sys.argv) > 3 and sys.argv[3] == "global"
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run_g if GLOBAL else run, [(k, s) for k in ks for s in range(seeds)]))
    for k in ks:
        rs = [r for r in res if r[0] == k]
        locked = [r for r in rs if r[2][-300:].max() - r[2][-300:].min() > 600]
        print(f"cull to {k}: {len(locked)}/{len(rs)} locked into the large cycle; first trough after the rebound "
              f"{np.mean([r[2][50:250].min() for r in rs]):.0f} (locked {np.mean([r[2][50:250].min() for r in locked]) if locked else float('nan'):.0f})")
        for _, s, p, g in locked:
            pk, tr = extremes(p, 900)
            print(f"   seed {s}: last 600 periods peaks {np.mean([p[t] for t in pk]):.0f} troughs {np.mean([p[t] for t in tr]):.0f} "
                  f"peak spacing {np.mean(np.diff(pk)):.0f} | max age {g[0]:.0f} vision {g[1]:.2f} endowment {g[2]:.1f}")
        un = [r for r in rs if r not in locked]
        if un:
            print(f"   not locked: max age {np.mean([r[3][0] for r in un]):.0f} vision {np.mean([r[3][1] for r in un]):.2f} endowment {np.mean([r[3][2] for r in un]):.1f}")
