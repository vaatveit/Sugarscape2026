"""Absolute wealth in Animation II-3's run vs ours: histograms in the book's bins, mean, max."""
from _pin import pin
pin("B")  # defaults this diagnostic was written under; see _pin.py
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

BOOK = {30: [0, 12, 33, 31, 37, 30, 39, 39, 22, 7], 110: [40, 66, 30, 38, 27, 17, 20, 8, 2, 2],
        200: [81, 50, 39, 25, 24, 15, 10, 3, 2, 1], 270: [122, 37, 28, 25, 18, 7, 9, 2, 0, 2]}
for top, counts in BOOK.items():
    mids = np.linspace(top / 20, top - top / 20, 10)
    print(f"book frame (bins to {top}): mean ~{np.dot(mids, counts) / sum(counts):.1f}, n={sum(counts)}")
cfg = EXPERIMENTS["II-4-gini"].config
for s in range(3):
    m = Model(replace(cfg, seed=s))
    out = []
    for t in range(1, 1001):
        m.step()
        if t in (1, 25, 50, 100, 200, 500, 1000):
            w = np.array([a.sugar for a in m.agents])
            out.append(f"t{t}: n={len(w)} mean={w.mean():.1f} max={w.max():.0f} "
                       f"h270={np.histogram(w, bins=np.linspace(0, 270, 11))[0].tolist()}")
    print(f"seed {s}:"); print("  " + "\n  ".join(out))
