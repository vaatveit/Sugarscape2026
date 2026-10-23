"""Reviewer probe: one-turn relay. A given disease is appended whether or not the receiver is immune;
the receiver's next immune response removes matched ones (and flips unmatched ones); transmission
comes BEFORE the immune response (spec s.2.4) and picks among everything carried, so an immune
agent can pass a disease on once before dropping it. Fee counts active (unmatched) diseases only.
RELAYa : an agent transmits whenever it carries anything.
RELAYb : an agent transmits only when at least one carried disease is active.
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
from sugarscape.agent import Agent
from sugarscape.model import Model

ORIG = (dz.infect, dz.immune_response, dz.transmit, Agent.sugar_burn)


def active(agent):
    return [d for d in agent.diseases if not dz.is_immune(agent.immune, d)]


def relay_infect(agent, disease):
    if disease in agent.diseases:
        return False
    agent.diseases.append(disease)
    return not dz.is_immune(agent.immune, disease)


def make_transmit(need_active):
    def transmit(model, agent):
        if not agent.diseases or (need_active and not active(agent)):
            return
        neighbors = model.neighbors_of(agent)
        for i in model.rng.permutation(len(neighbors)):
            other = neighbors[int(i)]
            d = agent.diseases[int(model.rng.integers(len(agent.diseases)))]
            if other.immune is not None and relay_infect(other, d):
                model.infection_log.append((agent, other))
        ORIG[1](agent)  # then the immune response (original: flip unmatched, drop matched)
    return transmit


def install(variant):
    dz.infect, dz.immune_response, dz.transmit, Agent.sugar_burn = ORIG
    if variant.startswith("RELAY"):
        dz.immune_response = lambda a: None
        dz.transmit = make_transmit(need_active=variant.endswith("b"))
        Agent.sugar_burn = property(lambda a: a.metabolism + a.disease_fee * len(active(a)))


def run(args):
    exp_id, variant, seed, steps = args
    install(variant)
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        rows = []
        for t in range(steps + 1):
            counts = [len(active(a)) for a in m.agents]
            rows.append((t, np.mean(counts), np.std(counts), np.mean([c > 0 for c in counts]), len(m.agents),
                         len(m.infection_log)))
            m.step()
    finally:
        install("H0")
    return args, rows


if __name__ == "__main__":
    t0 = time.time()
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    variants = sys.argv[3].split(",") if len(sys.argv) > 3 else ["RELAYa", "RELAYb"]
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
                      "| sd:", " ".join(f"{r[t][2]:.2f}" for t in (0, 10, 50, 100, 200, steps)),
                      "| pop:", " ".join(f"{r[t][4]:.0f}" for t in (0, 10, 50, 100, 200, steps)))
    print("book: V-1 clears; V-3 start 3.41 (sd 0.62), endemic avg 0.81-0.91, sd 0.98-1.03")
    print(f"elapsed {time.time() - t0:.0f}s")
