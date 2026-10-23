"""Flow accounting for a sex run: births, deaths by cause, harvest, fertility bottleneck."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys, math
import numpy as np
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.sex import is_fertile

def run(cfg, steps, windows, label):
    m = Model(cfg)
    orig_die = m.die
    stats = {"starve": 0, "old": 0, "lost": 0.0, "births": 0}
    def die(agent, excluded_heirs=()):
        if agent.sugar <= 0:
            stats["starve"] += 1
        else:
            stats["old"] += 1
            stats["lost"] += agent.sugar
        orig_die(agent, excluded_heirs)
    m.die = die
    # movement.metabolize calls model.die -> our wrapper (attribute lookup on instance)
    acc = {}
    for t in range(steps):
        n0 = len(m.agents); ids0 = {a.id for a in m.agents}
        W0 = sum(a.sugar for a in m.agents)
        # fertility bottleneck, measured on state entering the period (neighbors from last period)
        agew = [a for a in m.agents if a.fertility_start <= a.age < a.fertility_end]
        wealthy = [a for a in agew if a.sugar >= a.initial_sugar]
        partnered = [a for a in wealthy if any(b.sex != a.sex and is_fertile(b) for b in a.neighbors)]
        s0 = dict(stats)
        m.step()
        births = sum(1 for a in m.agents if a.id not in ids0)
        W1 = sum(a.sugar for a in m.agents)
        met = sum(a.metabolism for a in m.agents)  # approx (dead excluded)
        lost = stats["lost"] - s0["lost"]
        harvest = W1 - W0 + met + lost  # births are transfers
        for lo, hi in windows:
            if lo <= t < hi:
                d = acc.setdefault((lo, hi), dict(n=0, pop=0, births=0, starve=0, old=0, lost=0.0, harvest=0.0, met=0.0,
                                                   agew=0, wealthy=0, partnered=0, moved=0, sugar=0.0, cap=np.zeros(5)))
                d["n"] += 1; d["pop"] += len(m.agents); d["births"] += births
                d["starve"] += stats["starve"] - s0["starve"]; d["old"] += stats["old"] - s0["old"]
                d["lost"] += lost; d["harvest"] += harvest; d["met"] += met
                d["agew"] += len(agew); d["wealthy"] += len(wealthy); d["partnered"] += len(partnered)
                d["moved"] += sum(a.moved for a in m.agents); d["sugar"] += sum(a.sugar for a in m.agents)
                for a in m.agents:
                    d["cap"][int(m.landscape.capacity[a.x, a.y])] += 1
    print(f"== {label}")
    for (lo, hi), d in sorted(acc.items()):
        n = d["n"]; pop = d["pop"] / n
        print(f" t={lo}-{hi}: pop {pop:.0f}  births/p {d['births']/n:.2f}  starve/p {d['starve']/n:.2f}  old/p {d['old']/n:.2f}"
              f"  lost@death/p {d['lost']/n:.0f}  harvest/p {d['harvest']/n:.0f}  metab/p {d['met']/n:.0f}"
              f"  harvest/agent {d['harvest']/d['pop']:.2f}  mean_sugar {d['sugar']/d['pop']:.1f}")
        print(f"    fertile-age {d['agew']/n:.0f}  of which wealthy {d['wealthy']/n:.0f} ({d['wealthy']/max(d['agew'],1):.0%})"
              f"  of which partnered {d['partnered']/n:.0f} ({d['partnered']/max(d['wealthy'],1):.0%})  moved frac {d['moved']/d['pop']:.2f}"
              f"  occupancy by capacity 0..4 {np.round(d['cap']/d['pop'],2).tolist()}")
    return m

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "III-1"
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    base = dict(sex=True, max_age=(60, 100), endowment=(50, 100), seed=seed)
    cfgs = {
        "III-1": Config(**base),
        "III-3": Config(**base, female_fertility_end=(30, 40), male_fertility_end=(40, 50)),
        "III-4": Config(**{**base, "endowment": (10, 40)}),
        "III-7": Config(**base, inheritance=True),
    }
    steps = int(sys.argv[3]) if len(sys.argv) > 3 else 600
    run(cfgs[which], steps, [(0, 12), (12, 60), (60, 100), (100, 200), (200, 400), (400, 600)], f"{which} seed {seed}")
