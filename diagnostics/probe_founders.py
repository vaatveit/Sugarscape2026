"""Diagnostic: a wealth margin for founders only. Founders (ids < initial population) must hold
theta_f * endowment to be fertile; everyone born in the run keeps threshold theta_c (1.0 = book)."""
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
original = sex.is_fertile


def run(args):
    exp_id, tf, tc, seed = args
    cfg = EXPERIMENTS[exp_id].config
    n0 = cfg.initial_population

    def is_fertile(agent, threshold=1.0):
        th = tf if agent.id < n0 else tc
        return (agent.alive and agent.sex is not None and agent.fertility_start <= agent.age < agent.fertility_end
                and agent.sugar >= th * agent.initial_sugar)
    sex.is_fertile = is_fertile
    m = Model(replace(cfg, seed=seed))
    pops, births = [len(m.agents)], 0
    for t in range(STEPS):
        b = m.agents_ever
        m.step()
        births += (m.agents_ever - b) if t < 85 else 0
        pops.append(len(m.agents))
        if not m.agents or len(m.agents) > 2400:
            break
    pops += [pops[-1]] * (STEPS + 1 - len(pops))
    return args, (pops, births)


if __name__ == "__main__":
    exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-1"
    grid = [(tf, tc) for tc in (1.0, 0.83) for tf in (1.0, 0.75, 0.5, 0.25, 0.0)]
    with ProcessPoolExecutor(8) as pool:
        out = list(pool.map(run, [(exp_id, tf, tc, s) for tf, tc in grid for s in range(3)]))
    print(f"{exp_id} (3 seeds) book: t20=470 t85=570 t150~400 t240=415 late~500")
    for tf, tc in grid:
        rs = [v for (e, a, b, s), v in out if (a, b) == (tf, tc)]
        p = np.array([r[0] for r in rs], float)
        print(f"  founders {tf:<4} others {tc:<4} t20={p[:, 20].mean():5.0f} t85={p[:, 85].mean():5.0f} "
              f"t150={p[:, 150].mean():5.0f} t240={p[:, 240].mean():5.0f} late={p[:, 300:].mean():5.0f} "
              f"births<85={np.mean([r[1] for r in rs]):4.0f} extinct={np.mean(p[:, -1] == 0):.2f}")
