"""III-1's first 40 periods: births, deaths, fertile stock, and income by metabolism."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
import sys
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

exp_id = sys.argv[1] if len(sys.argv) > 1 else "III-1"
T = 40
B, D, N, F, FA = (np.zeros((5, T)) for _ in range(5))
inc_by_m = {mm: [] for mm in range(1, 5)}
for s in range(5):
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=s))
    for t in range(T):
        N[s, t] = len(m.agents)
        F[s, t] = sum(sex.is_fertile(a) for a in m.agents)
        FA[s, t] = sum(1 for a in m.agents if a.fertility_start <= a.age < a.fertility_end)
        before = m.agents_ever
        m.step()
        B[s, t] = m.agents_ever - before
        D[s, t] = m.deaths_this_step
        if 5 <= t < 30:
            for a in m.agents:
                if a.age > 1:
                    inc_by_m[a.metabolism].append(a.last_income)
print("t   N     births deaths fertile fertile-age")
for t in range(T):
    print(f"{t:2d} {N[:, t].mean():6.1f} {B[:, t].mean():6.1f} {D[:, t].mean():6.1f} {F[:, t].mean():7.1f} {FA[:, t].mean():7.1f}")
print("net income t=5-30 by metabolism:", {k: round(float(np.mean(v)), 2) for k, v in inc_by_m.items()},
      "counts", {k: len(v) // 25 // 5 for k, v in inc_by_m.items()})
