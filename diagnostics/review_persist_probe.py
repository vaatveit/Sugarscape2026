"""Reviewer probe: reading P = contracted diseases stay in the agent's set for life; each period every
unmatched one gets one flip; 'active' (fee, transmission, sick) = currently unmatched; an immune
agent does not contract (nothing added); transmission offers a random ACTIVE disease.
P     : initial gift goes through the same contraction check (immune ones not added).
Pall  : initial gift of 10 is added whole (p.147 'given copies of'), matched ones simply inert.
H0    : branch as is.
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
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


def p_response(agent):
    for d in agent.diseases:
        dz.immune_step(agent.immune, d)  # matched: no-op; unmatched: one flip


def p_transmit(model, agent):
    act = active(agent)
    if not act:
        return
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        d = act[int(model.rng.integers(len(act)))]
        if other.immune is not None and dz.infect(other, d):  # original infect: not if immune or carried
            model.infection_log.append((agent, other))


def all_infect(agent, disease):
    if disease in agent.diseases:
        return False
    agent.diseases.append(disease)
    return True


def install(variant):
    dz.infect, dz.immune_response, dz.transmit, Agent.sugar_burn = ORIG
    if variant in ("P", "Pall"):
        dz.immune_response, dz.transmit = p_response, p_transmit
        Agent.sugar_burn = property(lambda a: a.metabolism + a.disease_fee * len(active(a)))


def run(args):
    exp_id, variant, seed, steps = args
    install(variant)
    try:
        if variant == "Pall":
            dz.infect = all_infect
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        dz.infect = ORIG[0]
        rows = []
        for t in range(steps + 1):
            counts = [len(active(a)) for a in m.agents]
            carried = [len(a.diseases) for a in m.agents]
            rows.append((t, np.mean(counts), np.std(counts), np.mean([c > 0 for c in counts]), len(m.agents),
                         len(m.infection_log), np.mean(carried)))
            m.step()
    finally:
        install("H0")
    return args, rows


if __name__ == "__main__":
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    variants = sys.argv[3].split(",") if len(sys.argv) > 3 else ["P", "Pall"]
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
                  f"sick {late[2]:.2f} pop {late[3]:.0f} new_inf/period {late[4]:.1f} carried {late[5]:.1f}")
            for r in rs:
                print("   avg:", " ".join(f"{r[t][1]:.2f}" for t in (0, 1, 2, 3, 5, 10, 20, 50, 100, 200, steps)),
                      "| sd:", " ".join(f"{r[t][2]:.2f}" for t in (0, 10, 50, 100, 200, steps)),
                      "| pop:", " ".join(f"{r[t][4]:.0f}" for t in (0, 10, 50, 100, 200, steps)))
    print("book: V-1 clears; V-3 start 3.41 (sd 0.62), endemic avg 0.81-0.91, sd 0.98-1.03")
