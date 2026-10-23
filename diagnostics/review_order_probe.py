"""Reviewer probe: does the order of E within a turn explain V-2?
H0  = branch as is: immune_response, then transmit.
TF  = design spec s.2.4 order: transmit, then immune response for self.
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

import sugarscape.rules.disease as dz
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

ORIG_RESPONSE, ORIG_TRANSMIT = dz.immune_response, dz.transmit


def tf_transmit_then_respond(model, agent):
    ORIG_TRANSMIT(model, agent)
    ORIG_RESPONSE(agent)


def install(variant):
    dz.immune_response, dz.transmit = ORIG_RESPONSE, ORIG_TRANSMIT
    if variant == "TF":
        dz.immune_response = lambda agent: None
        dz.transmit = tf_transmit_then_respond


def run(args):
    exp_id, variant, seed, steps = args
    install(variant)
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
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
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    variants = sys.argv[3].split(",") if len(sys.argv) > 3 else ["H0", "TF"]
    jobs = [(e, v, s, steps) for e in ("V-1", "V-2") for v in variants for s in (0, 1, 2)]
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 6) as pool:
        out = list(pool.map(run, jobs))
    lo = int(steps * 2 / 3)
    for e in ("V-1", "V-2"):
        for v in variants:
            rs = [r for (e_, v_, _, _), r in out if e_ == e and v_ == v]
            start = np.mean([r[0][1] for r in rs])
            late = np.array([[row[1:] for row in r[lo:steps + 1]] for r in rs]).mean(axis=(0, 1))
            print(f"{e} {v}: start avg {start:.2f} | t{lo}-{steps} avg diseases {late[0]:.2f} sd {late[1]:.2f} "
                  f"sick {late[2]:.2f} pop {late[3]:.0f} new_inf/period {late[4]:.1f}")
            for r in rs:
                print("   trajectory avg:", " ".join(f"{r[t][1]:.2f}" for t in (0, 1, 2, 3, 5, 10, 20, 50, 100, 200, steps)))
    print("book: V-1 clears; V-3 start 3.41, endemic avg 0.81-0.91, sd 0.98-1.03")
