"""Diagnostic only: candidate readings that might block births at peak density, on III-5 and III-4.
  once  = own fertility tested once at the start of the agent's turn (p.56: "each fertile agent executes S";
          the loop checks the neighbor), then a child with every fertile opposite-sex neighbor that has room
  m12   = founders' metabolism 1-2 (proxy for metabolism variation surviving into the cycles)
Reports extinctions, troughs, late range, mean metabolism late, multiple births per birth-turn."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex
from sugarscape.rules.culture import cross_tags

STEPS = 1500


def mate_once(model, agent):
    """Rule S with the agent's own fertility checked once, before the loop (copy of sex.mate otherwise)."""
    rng = model.rng
    threshold, share = model.config.fertility_threshold, model.config.child_share
    children = []
    if not sex.is_fertile(agent, threshold):
        return children
    neighbors = model.neighbors_of(agent)
    for i in rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        if other.sex is None or other.sex == agent.sex or not sex.is_fertile(other, threshold):
            continue
        sites = list(dict.fromkeys(sex._empty_sites(model, agent) + sex._empty_sites(model, other)))
        if not sites:
            continue
        x, y = sites[int(rng.integers(len(sites)))]
        parents = (agent, other)
        vision = parents[int(rng.integers(2))].vision
        metabolism = parents[int(rng.integers(2))].metabolism
        max_age = parents[int(rng.integers(2))].max_age
        endowment = agent.initial_sugar * share + other.initial_sugar * share
        agent.sugar -= agent.initial_sugar * share
        other.sugar -= other.initial_sugar * share
        child = model.new_agent(x, y, vision, metabolism, endowment, max_age)
        model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
        if agent.tags is not None and other.tags is not None:
            child.tags = cross_tags(rng, agent.tags, other.tags)
        agent.children.append(child); other.children.append(child); children.append(child)
    return children


VARIANTS = {
    "default": {},
    "once": {"_once": True},
    "m12": {"metabolism": (1, 2)},
    "theta1": {"fertility_threshold": 1.0},
    "once+theta1": {"_once": True, "fertility_threshold": 1.0},
    "m12+theta1": {"metabolism": (1, 2), "fertility_threshold": 1.0},
    "once+m12": {"_once": True, "metabolism": (1, 2)},
}


def run(args):
    exp_id, name, seed = args
    extra = dict(VARIANTS[name]); once = extra.pop("_once", False)
    orig = sex.mate
    turns, multi = [0], [0]

    def counted(model, agent):
        kids = (mate_once if once else orig)(model, agent)
        if kids:
            turns[0] += 1; multi[0] += len(kids) > 1
        return kids
    sex.mate = counted
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed, **extra))
    pop, met = [], []
    for t in range(STEPS):
        pop.append(len(m.agents))
        if not m.agents:
            break
        if t % 100 == 0:
            met.append(np.mean([a.metabolism for a in m.agents]))
        m.step()
    sex.mate = orig
    p = np.array(pop + [0] * (STEPS - len(pop)), float)
    return exp_id, name, seed, p, met, multi[0] / max(1, turns[0])


if __name__ == "__main__":
    exp_id = sys.argv[1]
    names = sys.argv[2].split(",")
    seeds = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(exp_id, n, s) for n in names for s in range(seeds)]))
    for n in names:
        rs = [r for r in res if r[1] == n]
        ext = [int(np.argmax(r[3] == 0)) for r in rs if (r[3] == 0).any()]
        alive = [r for r in rs if not (r[3] == 0).any()]
        troughs = []
        for r in rs:
            p = r[3]; s9 = np.convolve(p, np.ones(9) / 9, "same")
            troughs += [int(p[t]) for t in range(150, len(p) - 60) if p[t] > 0 and s9[t] == s9[t - 50:t + 51].min() and s9[t - 50:t + 51].max() - s9[t] > 300]
        print(f"{exp_id} {n:12s}: extinct {len(ext)}/{len(rs)} (at t={sorted(ext)}) | troughs after t=150: "
              f"min {min(troughs) if troughs else '-'} median {int(np.median(troughs)) if troughs else '-'} | "
              f"late range (alive) {np.mean([r[3][1000:].max() - r[3][1000:].min() for r in alive]) if alive else float('nan'):.0f} | "
              f"metabolism t=0/200/500 {np.mean([r[4][0] for r in rs]):.2f}/{np.mean([r[4][2] for r in rs if len(r[4]) > 2]):.2f}/"
              f"{np.mean([r[4][5] for r in rs if len(r[4]) > 5]) if any(len(r[4]) > 5 for r in rs) else float('nan'):.2f} | "
              f"birth-turns with 2+ births {np.mean([r[5] for r in rs]):.3f}")
