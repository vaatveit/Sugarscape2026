"""Why do agents die after t=50 in the IV-3 configuration? Cause, holdings, and whether the lacking
good was visible from the agent's final position."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys
from collections import Counter
from sugarscape.config import Config
from sugarscape.model import Model
from experiments.registry import NEO
from sugarscape.rules import movement

cfg = Config(**NEO, seed=0)
m = Model(cfg)
orig_die = m.die
records = []


def visible(agent, layer):
    ls = m.landscape
    total = 0.0
    for dx, dy in movement.VON_NEUMANN:
        for d in range(1, agent.vision + 1):
            x, y = ls.wrap(agent.x + dx * d, agent.y + dy * d)
            total += layer[x, y]
    return total


def die(agent, excluded_heirs=()):
    cause = "sugar" if agent.sugar <= 0 else ("spice" if agent.spice <= 0 else "other")
    records.append(dict(t=m.t, cause=cause, m1=agent.metabolism, m2=agent.spice_metabolism, v=agent.vision,
                        sugar=round(agent.sugar, 1), spice=round(agent.spice, 1),
                        vis_sugar=visible(agent, m.landscape.sugar), vis_spice=visible(agent, m.landscape.spice),
                        cap_s=m.landscape.capacity[agent.x, agent.y], cap_p=m.landscape.spice_capacity[agent.x, agent.y]))
    orig_die(agent, excluded_heirs)


m.die = die
m.run(500)
print("population at 500:", len(m.agents))
early = [r for r in records if r["t"] < 50]
late = [r for r in records if r["t"] >= 50]
print("deaths <50:", len(early), Counter(r["cause"] for r in early))
print("deaths >=50:", len(late), Counter(r["cause"] for r in late))
print("late deaths: total metabolism m1+m2 distribution:", sorted(Counter(r["m1"] + r["m2"] for r in late).items()))
print("survivors: total metabolism distribution:", sorted(Counter(a.metabolism + a.spice_metabolism for a in m.agents).items()))
print("survivors: (m1,m2) :", sorted(Counter((a.metabolism, a.spice_metabolism) for a in m.agents).items()))
print("late deaths where the lacking good was visible (>0 within vision) at death:")
n_vis = 0
for r in late:
    lacking_visible = r["vis_sugar"] if r["cause"] == "sugar" else r["vis_spice"]
    if lacking_visible > 0:
        n_vis += 1
print(f"  {n_vis} of {len(late)}")
for r in late[:15]:
    print("  ", r)
