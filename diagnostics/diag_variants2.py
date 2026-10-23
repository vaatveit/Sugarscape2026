"""Sensitivity of the S equilibrium to small unstated details (diagnostic only)."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys
import numpy as np
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules import sex
from sugarscape.rules.sex import _empty_sites
from sugarscape.rules.culture import cross_tags

MOORE = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
FLAGS = set()

def is_fertile(agent):
    end_ok = agent.age <= agent.fertility_end if "incl" in FLAGS else agent.age < agent.fertility_end
    return agent.alive and agent.sex is not None and agent.fertility_start <= agent.age and end_ok and agent.sugar >= agent.initial_sugar

def mate(model, agent):
    rng = model.rng
    children = []
    if "moore" in FLAGS:
        neighbors = [b for b in (model.agent_at(agent.x + dx, agent.y + dy) for dx, dy in MOORE) if b is not None]
    else:
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
        agent.sugar -= agent.initial_sugar / 2
        other.sugar -= other.initial_sugar / 2
        child = model.new_agent(x, y, vision, metabolism, endowment, max_age)
        model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
        agent.children.append(child); other.children.append(child); children.append(child)
    return children

sex.mate = mate

if __name__ == "__main__":
    which, flags, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    FLAGS.update(f for f in flags.split("+") if f and f != "base")
    steps = int(sys.argv[4]) if len(sys.argv) > 4 else 1000
    base = dict(sex=True, max_age=(60, 100), endowment=(50, 100), seed=seed)
    cfgs = {
        "III-1": Config(**base),
        "III-3": Config(**base, female_fertility_end=(30, 40), male_fertility_end=(40, 50)),
        "III-4": Config(**{**base, "endowment": (10, 40)}),
    }
    m = Model(cfgs[which])
    pops = []
    for t in range(steps + 1):
        pops.append(len(m.agents))
        if t < steps:
            m.step()
    p = np.array(pops, dtype=float)
    print(f"== {which} [{flags}] seed {seed}: pop at 50/100/200/300/500/750/1000 = "
          + "/".join(str(int(p[t])) for t in (50, 100, 200, 300, 500, 750, 1000) if t < len(p))
          + f"; mean(500..{steps}) {p[500:].mean():.0f}  min(300..) {p[300:].min():.0f}  max(300..) {p[300:].max():.0f}")
