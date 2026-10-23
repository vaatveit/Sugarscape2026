"""Reviewer probe: learning speed vs host death.
H0f0   : branch as is, disease_fee = 0 (no deaths from illness).
H3f1   : one immune bit per agent per cycle (fn 16), on a random active infection, fee 1.
H3f0   : same, fee 0.
H3TFf0 : H3, spec order (transmit, then respond), fee 0.
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
import time
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

import sugarscape.rules.disease as dz
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

ORIG_RESPONSE, ORIG_TRANSMIT = dz.immune_response, dz.transmit
_MODEL = {}


def h3_response(agent):
    if agent.diseases:
        d = agent.diseases[int(_MODEL["m"].rng.integers(len(agent.diseases)))]
        dz.immune_step(agent.immune, d)
    agent.diseases = [d for d in agent.diseases if not dz.is_immune(agent.immune, d)]


def tf(model, agent):
    ORIG_TRANSMIT(model, agent)
    h3_response(agent)


def install(variant):
    dz.immune_response, dz.transmit = ORIG_RESPONSE, ORIG_TRANSMIT
    if variant.startswith("H3TF"):
        dz.immune_response, dz.transmit = (lambda a: None), tf
    elif variant.startswith("H3"):
        dz.immune_response = h3_response


def run(args):
    exp_id, variant, seed, steps = args
    fee = 0.0 if variant.endswith("f0") else 1.0
    install(variant)
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed, disease_fee=fee))
        _MODEL["m"] = m
        rows = []
        for t in range(steps + 1):
            counts = [len(a.diseases) for a in m.agents]
            rows.append((t, np.mean(counts), np.std(counts), np.mean([c > 0 for c in counts]), len(m.agents),
                         len(m.infection_log)))
            m.step()
    finally:
        install("H0")
    return args, rows


if __name__ == "__main__":
    t0 = time.time()
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    variants = sys.argv[3].split(",") if len(sys.argv) > 3 else ["H0f0", "H3f1", "H3f0", "H3TFf0"]
    jobs = [(e, v, s, steps) for e in ("V-1", "V-2") for v in variants for s in (0, 1, 2)]
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 6) as pool:
        out = list(pool.map(run, jobs))
    lo = int(steps * 2 / 3)
    for e in ("V-1", "V-2"):
        for v in variants:
            rs = [r for (e_, v_, _, _), r in out if e_ == e and v_ == v]
            start = np.mean([r[0][1] for r in rs])
            late = np.array([[row[1:] for row in r[lo:steps + 1]] for r in rs]).mean(axis=(0, 1))
            print(f"{e} {v}: start avg {start:.2f} | t{lo}-{steps} avg {late[0]:.2f} sd {late[1]:.2f} "
                  f"sick {late[2]:.2f} pop {late[3]:.0f} new_inf/period {late[4]:.1f}")
            for r in rs:
                print("   avg:", " ".join(f"{r[t][1]:.2f}" for t in (0, 1, 2, 3, 5, 10, 20, 50, 100, 200, steps)),
                      "| pop:", " ".join(f"{r[t][4]:.0f}" for t in (0, 10, 50, 100, 200, steps)))
    print("book: V-1 clears; V-3 start 3.41 (sd 0.62), endemic avg 0.81-0.91, sd 0.98-1.03")
    print(f"elapsed {time.time() - t0:.0f}s")
