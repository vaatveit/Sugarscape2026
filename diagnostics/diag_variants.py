"""Population trajectories under hypothesis variants (diagnostic only; no project files touched)."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys, math
import numpy as np
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules import sex
from sugarscape.rules.sex import is_fertile, _empty_sites, VON_NEUMANN
from sugarscape.rules.culture import cross_tags

ORIG_MATE = sex.mate

def mate_no_deduction(model, agent):
    rng = model.rng
    children = []
    neighbors = model.neighbors_of(agent)
    for i in rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        if other.sex is None or other.sex == agent.sex or not (is_fertile(agent) and is_fertile(other)):
            continue
        sites = list(dict.fromkeys(_empty_sites(model, agent) + _empty_sites(model, other)))
        if not sites:
            continue
        x, y = sites[int(rng.integers(len(sites)))]
        parents = (agent, other)
        vision = parents[int(rng.integers(2))].vision
        metabolism = parents[int(rng.integers(2))].metabolism
        max_age = parents[int(rng.integers(2))].max_age
        endowment = agent.initial_sugar / 2 + other.initial_sugar / 2
        # VARIANT: parents keep their sugar
        child = model.new_agent(x, y, vision, metabolism, endowment, max_age)
        model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
        agent.children.append(child); other.children.append(child); children.append(child)
    return children

def trajectory(cfg, steps, variant, sample):
    sex.mate = mate_no_deduction if variant == "nodeduct" else ORIG_MATE
    m = Model(cfg)
    if variant == "randage":
        for a in m.agents:
            a.age = int(m.rng.integers(0, int(a.max_age)))
    out = {}
    for t in range(steps + 1):
        if t in sample:
            ag = m.agents
            out[t] = (len(ag), round(float(np.mean([a.sugar for a in ag])), 1) if ag else 0,
                      round(float(np.mean([a.metabolism for a in ag])), 2) if ag else 0,
                      round(float(np.mean([len(a.neighbors) for a in ag])), 2) if ag else 0,
                      round(float(np.mean([a.sugar for a in ag])) and 0 or 0, 1))
        if t < steps:
            m.step()
    sex.mate = ORIG_MATE
    return out

if __name__ == "__main__":
    which, variant, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    steps = int(sys.argv[4]) if len(sys.argv) > 4 else 1000
    base = dict(sex=True, max_age=(60, 100), endowment=(50, 100), seed=seed)
    cfgs = {
        "III-1": Config(**base),
        "III-3": Config(**base, female_fertility_end=(30, 40), male_fertility_end=(40, 50)),
        "III-4": Config(**{**base, "endowment": (10, 40)}),
        "III-5": Config(**{**base, "endowment": (10, 40)}, female_fertility_end=(30, 40), male_fertility_end=(40, 50)),
        "III-7": Config(**base, inheritance=True),
    }
    sample = [0, 12, 25, 40, 50, 75, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000, 1250, 1500, 2000, 2500]
    out = trajectory(cfgs[which], steps, variant, set(sample))
    print(f"== {which} {variant} seed {seed}: (t: pop, mean_sugar, mean_metab, mean_neighbors)")
    print("  " + "  ".join(f"{t}:{v[0]}/{v[1]}/{v[2]}/{v[3]}" for t, v in sorted(out.items())))
