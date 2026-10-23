"""Where does regrowth go unharvested? N evolved agents (m=1, vision 5-6, immortal, rich), t=100-300."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
import numpy as np
from sugarscape.config import Config
from sugarscape.model import Model

for n in (350, 500, 700):
    m = Model(Config(initial_population=n, vision=(5, 6), metabolism=(1, 1), endowment=(1000, 1000), seed=1))
    cap = m.landscape.capacity
    full = np.zeros(5); occ = np.zeros(5); harv = np.zeros(5); moved = []; stay_level = []
    T = 0
    for t in range(300):
        before = m.landscape.sugar.copy()
        m.step()
        if t >= 100:
            T += 1
            for c in range(5):
                full[c] += np.mean(m.landscape.sugar[cap == c] >= c) if c else 0
            for a in m.agents:
                occ[cap[a.x, a.y]] += 1
                harv[cap[a.x, a.y]] += a.last_income + 1
            moved.append(np.mean([a.moved for a in m.agents]))
    counts = [int((cap == c).sum()) for c in range(5)]
    print(f"N={n}: harvest/agent {harv.sum() / T / n:.2f}; agents moving each period {np.mean(moved):.2f}")
    for c in range(1, 5):
        print(f"   capacity {c}: {counts[c]:4d} sites, share full at period end {full[c] / T:.2f}, "
              f"agents there {occ[c] / T:6.1f}, harvest per agent there {harv[c] / max(occ[c], 1):.2f}")
    print(f"   regrowth wasted at full sites ~ {sum(full[c] / T * counts[c] for c in range(1, 5)):.0f} of 2069 units/period")
