"""III-1 sugar budget in windows: harvest, metabolism, gifts to children, wealth lost at death."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

W = [(0, 20), (20, 85), (85, 200), (300, 1000)]
acc = {w: np.zeros(7) for w in W}
for s in range(3):
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=s))
    for t in range(1000):
        n = len(m.agents)
        burn = sum(a.metabolism for a in m.agents)
        mean_m = burn / max(n, 1)
        before = m.agents_ever
        m.step()
        births = m.agents_ever - before
        harvest = sum(a.last_income + a.metabolism for a in m.agents if a.age > 0) + sum(
            max(a.last_income + a.metabolism, 0) for a in m.dead_this_step)
        lost = sum(max(a.sugar, 0) for a in m.dead_this_step)
        gifts = sum(a.initial_sugar for a in m.agents if a.age == 1 and a.id >= 400)
        for w in W:
            if w[0] <= t < w[1]:
                acc[w] += [n, harvest, burn, gifts, lost, births, mean_m]
print("window   N     harvest  metab  gifts  lost@death  births  mean_metab   (per period, 3 seeds)")
for w in W:
    a = acc[w] / ((w[1] - w[0]) * 3)
    print(f"{w[0]:4d}-{w[1]:<5d}" + " ".join(f"{v:8.1f}" for v in a))
