"""Does maximum age evolve downward in III-1? Mean max age of the living, mean age at death, births,
and the 70-79 / 0-9 age-bin ratio (book Animation III-1: 0.68-1.0; U[60,100] predicts 0.625).
Diagnostic 'fresh': children draw max age from U[60,100] instead of inheriting it."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
import sugarscape.model as model_mod
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

WIN = [(0, 100), (100, 300), (300, 600), (600, 1000), (1000, 1500)]


def run(args):
    exp_id, mode, seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
    if mode == "fresh":
        base_new = m.new_agent

        def new_agent(x, y, vision, metabolism, sugar, max_age=float("inf")):
            a = base_new(x, y, vision, metabolism, sugar, max_age)
            if m.t > 0 or a.id >= m.config.initial_population:
                a.max_age = m._draw(m.config.max_age)
            return a
        m.new_agent = new_agent
    rec = {w: [] for w in WIN}
    for t in range(1500):
        b = m.agents_ever
        m.step()
        ages = np.array([a.age for a in m.agents])
        h = np.histogram(ages, bins=range(0, 101, 10))[0]
        row = (len(m.agents), np.mean([a.max_age for a in m.agents]),
               np.mean([a.age for a in m.dead_this_step]) if m.dead_this_step else np.nan,
               m.agents_ever - b, h[7] / max(h[0], 1))
        for w in WIN:
            if w[0] <= t < w[1]:
                rec[w].append(row)
    return args, {w: np.nanmean(np.array(v, float), axis=0) for w, v in rec.items()}


if __name__ == "__main__":
    exps = sys.argv[1:] or ["III-1"]
    tasks = [(e, mode, s) for e in exps for mode in ("book", "fresh") for s in range(5)]
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, tasks))
    for e in exps:
        for mode in ("book", "fresh"):
            print(f"{e} max age {'inherited (book)' if mode == 'book' else 'drawn fresh (diagnostic)'}")
            for w in WIN:
                r = np.nanmean([v[w] for (e_, m_, s), v in out if (e_, m_) == (e, mode)], axis=0)
                print(f"  t={w[0]:4d}-{w[1]:<5d} N={r[0]:5.0f} mean max age={r[1]:5.1f} mean age at death={r[2]:5.1f} "
                      f"births={r[3]:5.2f} ratio 70-79/0-9={r[4]:.2f}")
