"""How far back must births 'look'? For each lag tau, fit births(t) as a smooth function of N(t - tau) (binned means)
and report the share of variance explained, for the book's implied births (t=300-2400) and ours."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import csv, sys
import numpy as np
from invert_iii4 import book_curve, invert


def r2(b, n, tau, t0, t1):
    x, y = n[t0 - tau:t1 - tau], b[t0:t1]
    y = np.convolve(y, np.ones(9) / 9, "same")
    bins = np.quantile(x, np.linspace(0, 1, 13))
    idx = np.clip(np.digitize(x, bins[1:-1]), 0, 11)
    fit = np.array([y[idx == k].mean() for k in idx])
    return 1 - ((y - fit) ** 2).sum() / ((y - y.mean()) ** 2).sum()


n = book_curve(); b, _, _ = invert(n)
from _paths import ROOT
rows = list(csv.DictReader(open(ROOT / "results/ch-III/III-4/seed0.csv")))
ours = np.array([float(r["population"]) for r in rows]); bo, _, _ = invert(ours)
print("tau  book R2 (t=300-2400)  ours R2 (t=100-400, the cycles before damping)")
for tau in (0, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60):
    print(f"{tau:3d}  {r2(b, n, tau, 300, 2400):.2f}  {r2(bo, ours, tau, 100, 400):.2f}")


def curve(b, n, tau, t0, t1, edges):
    x, y = n[t0 - tau:t1 - tau], np.convolve(b, np.ones(9) / 9, "same")[t0:t1]
    return [(y[(x >= lo) & (x < hi)].mean() if ((x >= lo) & (x < hi)).any() else np.nan) for lo, hi in zip(edges, edges[1:])]


edges = [300, 500, 700, 900, 1100, 1300, 1500, 1700]
print("births per period by N 20 periods earlier:", " | ".join(f"{a}-{z}" for a, z in zip(edges, edges[1:])))
print("  book:", " | ".join(f"{v:5.1f}" for v in curve(b, n, 20, 300, 2400, edges)))
print("  ours:", " | ".join(f"{v:5.1f}" for v in curve(bo, ours, 20, 100, 400, edges)))
print("  ours, births per agent alive now:", " | ".join(f"{v:.3f}" for v in curve(bo / np.maximum(ours, 1), ours, 20, 100, 400, edges)))
print("  book, births per agent alive now:", " | ".join(f"{v:.3f}" for v in curve(b / np.maximum(n, 1), n, 20, 300, 2400, edges)))
