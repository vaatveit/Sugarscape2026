"""III-1, t=0..100: births and deaths by cause, and who starves (age, generation, metabolism, sugar at birth)."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
from collections import Counter
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

for seed in range(3):
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed))
    founders = {id(a) for a in m.agents}
    c = Counter(); starve_age = []; starve_m = Counter(); fert_rich = []
    for t in range(100):
        ids = m._next_id
        m.step()
        born = m._next_id - ids
        for d in m.dead_this_step:
            cause = "old" if d.age >= d.max_age else "starve"
            gen = "founder" if id(d) in founders else "child"
            c[(t // 20, cause, gen)] += 1
            if cause == "starve" and gen == "child":
                starve_age.append(d.age); starve_m[d.metabolism] += 1
        c[(t // 20, "born", "")] += born
        if t % 20 == 19:
            fa = [a for a in m.agents if a.sex and a.fertility_start <= a.age < a.fertility_end]
            fert_rich.append((t + 1, len(m.agents), len(fa), sum(a.sugar >= a.initial_sugar for a in fa)))
    print("seed", seed, "pop/fertile-age/fertile-and-rich at t=20,40,..:", fert_rich)
    for w in range(5):
        print(f"  t{w*20}-{w*20+19}: born {c[(w,'born','')]:4d} | starve founder {c[(w,'starve','founder')]:3d} child {c[(w,'starve','child')]:3d} | old founder {c[(w,'old','founder')]:3d} child {c[(w,'old','child')]:3d}")
    if starve_age:
        print("  child starvation: median age", int(np.median(starve_age)), "share age<5:", round(np.mean(np.array(starve_age) < 5), 2), "by metabolism", dict(sorted(starve_m.items())))
