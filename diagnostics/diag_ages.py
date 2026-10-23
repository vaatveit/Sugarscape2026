"""III-1 with uniform founder ages and threshold 0.83: births, deaths by cause, and why fertile-age agents don't breed."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
from collections import Counter
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules.sex import is_fertile

for seed in range(2):
    m = Model(replace(EXPERIMENTS["III-1"].config, seed=seed, fertility_threshold=0.83))
    rng = np.random.default_rng(10_000 + seed)
    for a in m.agents:
        a.age = int(rng.integers(0, int(a.max_age)))
    c = Counter(); snap = []
    for t in range(100):
        ids = m.agents_ever
        m.step()
        c[(t // 10, "born")] += m.agents_ever - ids
        for d in m.dead_this_step:
            c[(t // 10, "old" if d.age >= d.max_age else "starve")] += 1
        if t % 10 == 9:
            fa = [a for a in m.agents if a.sex and a.fertility_start <= a.age < a.fertility_end]
            rich = [a for a in fa if is_fertile(a, 0.83)]
            # rich agents with a rich opposite-sex neighbor
            paired = [a for a in rich if any(n.sex and n.sex != a.sex and is_fertile(n, 0.83) for n in m.neighbors_of(a))]
            nbrs = np.mean([len(m.neighbors_of(a)) for a in m.agents])
            snap.append((t + 1, len(m.agents), len(fa), len(rich), len(paired), round(nbrs, 2),
                         round(float(np.mean([a.sugar for a in fa])), 1), round(float(np.mean([0.83 * a.initial_sugar for a in fa])), 1)))
    print("seed", seed)
    for w in range(10):
        print(f"  t{w*10:3d}-{w*10+9:3d}: born {c[(w,'born')]:3d}  old {c[(w,'old')]:3d}  starve {c[(w,'starve')]:3d}")
    print("  (t, pop, fertile-age, rich, rich-with-rich-mate-adjacent, mean neighbors, mean sugar of fertile-age, mean requirement):")
    for s in snap: print("   ", s)
