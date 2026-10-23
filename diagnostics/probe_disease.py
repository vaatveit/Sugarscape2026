"""Probe Chapter V readings: H0 current (immune -> disease dropped; clear same period);
H1 carriers (diseases stay in the agent's list; only non-immune ones count, cost, and learn;
any carried disease can be passed on); H2 current but cleared on the next period's check."""
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


def h1_infect(agent, disease):
    if disease in agent.diseases:
        return False
    agent.diseases.append(disease)  # carried even when immune
    return not dz.is_immune(agent.immune, disease)


def h1_response(agent):
    for d in agent.diseases:
        dz.immune_step(agent.immune, d)  # matched diseases: no-op


def h1_transmit(model, agent):
    if not agent.diseases:
        return
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        d = agent.diseases[int(model.rng.integers(len(agent.diseases)))]
        if other.immune is not None and h1_infect(other, d):
            model.infection_log.append((agent, other))


def h2_response(agent):
    keep = []
    for d in agent.diseases:
        if dz.is_immune(agent.immune, d):
            continue  # cleared at the check, a period after the last flip
        dz.immune_step(agent.immune, d)
        keep.append(d)
    agent.diseases = keep


def h3_first(agent):
    """One flip per period in total, on the oldest active infection."""
    if agent.diseases and dz.immune_step(agent.immune, agent.diseases[0]):
        agent.diseases.pop(0)
    agent.diseases = [d for d in agent.diseases if not dz.is_immune(agent.immune, d)]


_RNG = np.random.default_rng(12345)


def h3_random(agent):
    """One flip per period in total, on a randomly chosen active infection."""
    if agent.diseases:
        d = agent.diseases[int(_RNG.integers(len(agent.diseases)))]
        dz.immune_step(agent.immune, d)
    agent.diseases = [d for d in agent.diseases if not dz.is_immune(agent.immune, d)]


def install(variant):
    dz.infect, dz.immune_response, dz.transmit, Agent.sugar_burn = ORIG
    if variant == "H1":
        dz.infect, dz.immune_response, dz.transmit = h1_infect, h1_response, h1_transmit
        Agent.sugar_burn = property(lambda a: a.metabolism + a.disease_fee * len(active(a)))
    elif variant == "H2":
        dz.immune_response = h2_response
    elif variant == "H3first":
        dz.immune_response = h3_first
    elif variant == "H3random":
        dz.immune_response = h3_random


def run(args):
    exp_id, variant, seed = args
    install(variant)
    try:
        m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed))
        rows = []
        for t in range(301):
            counts = [len(active(a)) for a in m.agents]
            rows.append((t, np.mean(counts), np.std(counts), np.mean([c > 0 for c in counts]), len(m.agents)))
            m.step()
    finally:
        install("H0")
    return args, rows


if __name__ == "__main__":
    jobs = [(e, v, s) for e in ("V-1", "V-2") for v in ("H0", "H3first", "H3random") for s in (0, 1, 2)]
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 8) as pool:
        out = list(pool.map(run, jobs))
    for e in ("V-1", "V-2"):
        for v in ("H0", "H3first", "H3random"):
            rs = [r for (e_, v_, _), r in out if e_ == e and v_ == v]
            start = np.mean([r[0][1] for r in rs])
            late = np.array([[row[1:] for row in r[200:301]] for r in rs]).mean(axis=(0, 1))
            print(f"{e} {v}: start avg {start:.2f} | t200-300 avg diseases {late[0]:.2f} sd {late[1]:.2f} "
                  f"sick {late[2]:.2f} pop {late[3]:.0f}")
    print("book: V-1 clears; V-3 start 3.41, endemic avg 0.81-0.91, sd 0.98-1.03")
