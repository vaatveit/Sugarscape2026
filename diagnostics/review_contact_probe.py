"""Reviewer probe: is contact density the bottleneck? Branch semantics (drop on match), spec order
(transmit, then respond) so a d-bit disease gets d offers, and a larger contact set for E only:
MOORE  : the 8 surrounding sites.
VISION : every agent visible along the four lattice directions within the agent's vision.
VN     : von Neumann (control, spec order).
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
MOORE = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx, dy) != (0, 0)]


def contacts(model, agent, kind):
    if kind == "MOORE":
        found = (model.agent_at(agent.x + dx, agent.y + dy) for dx, dy in MOORE)
        return [a for a in found if a is not None]
    if kind == "VISION":
        out = []
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for k in range(1, agent.vision + 1):
                a = model.agent_at(agent.x + dx * k, agent.y + dy * k)
                if a is not None:
                    out.append(a)
        return out
    return model.neighbors_of(agent)


def make_transmit(kind):
    def transmit(model, agent):
        if agent.diseases:
            nbrs = contacts(model, agent, kind)
            for i in model.rng.permutation(len(nbrs)):
                other = nbrs[int(i)]
                d = agent.diseases[int(model.rng.integers(len(agent.diseases)))]
                if other.immune is not None and dz.infect(other, d):
                    model.infection_log.append((agent, other))
        ORIG_RESPONSE(agent)
    return transmit


def install(variant):
    dz.immune_response, dz.transmit = ORIG_RESPONSE, ORIG_TRANSMIT
    if variant != "H0":
        dz.immune_response = lambda a: None
        dz.transmit = make_transmit(variant)


def run(args):
    exp_id, variant, seed, steps = args
    install(variant)
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        rows = []
        for t in range(steps + 1):
            counts = [len(a.diseases) for a in m.agents]
            rows.append((t, np.mean(counts), np.std(counts), np.mean([c > 0 for c in counts]), len(m.agents),
                         len(m.infection_log), np.mean([len(contacts(m, a, variant)) for a in m.agents])))
            m.step()
    finally:
        install("H0")
    return args, rows


if __name__ == "__main__":
    t0 = time.time()
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    variants = sys.argv[3].split(",") if len(sys.argv) > 3 else ["VN", "MOORE", "VISION"]
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
                  f"sick {late[2]:.2f} pop {late[3]:.0f} new_inf/period {late[4]:.1f} contacts {late[5]:.2f}")
            for r in rs:
                print("   avg:", " ".join(f"{r[t][1]:.2f}" for t in (0, 1, 2, 3, 5, 10, 20, 50, 100, 200, steps)),
                      "| sd:", " ".join(f"{r[t][2]:.2f}" for t in (0, 10, 50, 100, 200, steps)),
                      "| pop:", " ".join(f"{r[t][4]:.0f}" for t in (0, 10, 50, 100, 200, steps)))
    print("book: V-1 clears; V-3 start 3.41 (sd 0.62), endemic avg 0.81-0.91, sd 0.98-1.03")
    print(f"elapsed {time.time() - t0:.0f}s")
