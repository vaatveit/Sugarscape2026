"""Demographic inversion: given a population curve N(t), the births it implies if every death is from old age
(max age uniform on 60..100; founders at ages U[0, max age)). Where births would be negative, the shortfall is
the minimum starvation (a lower bound: starved agents' later old-age deaths are still counted)."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import csv
import sys
import numpy as np
from PIL import Image

from _paths import book_page, ROOT
PAGE = book_page("pc", "p012.png")
AGES = np.arange(60, 101)


def book_curve():
    im = np.asarray(Image.open(PAGE).convert("L"), float)
    y1500, y500 = 298.3, 493.3            # pixel rows of 1500 and 500 agents (axis ticks)
    x0, per_px = 130.75, 1000 / 206.75    # t=0 column; periods per pixel
    ts, ns = [], []
    for x in range(134, 647):
        dark = np.nonzero(im[286:585, x] < 110)[0] + 286
        if len(dark):
            y = (dark.min() + dark.max()) / 2
            ts.append((x - x0) * per_px); ns.append(500 + (y500 - y) * 1000 / (y500 - y1500))
    t = np.arange(0, int(ts[-1]))
    return np.interp(t, ts, ns)


def invert(n, n0=None):
    T = len(n)
    n0 = n[0] if n0 is None else n0
    founder_deaths = np.array([n0 * np.mean([1 / a if t < a else 0 for a in AGES]) for t in range(T)])
    births, starve, old = np.zeros(T), np.zeros(T), np.zeros(T)
    for t in range(T - 1):
        d = founder_deaths[t] + sum(births[t - a] for a in AGES if t - a >= 0) / len(AGES)
        old[t] = d
        b = n[t + 1] - n[t] + d
        births[t], starve[t] = max(b, 0), max(-b, 0)
    return births, old, starve


def report(name, n, windows):
    b, d, s = invert(n)
    print(f"== {name}")
    for a, z in windows:
        print(f"  t={a}-{z}: N {n[a]:.0f} -> {n[z]:.0f}; implied births {b[a:z].mean():5.1f}/period, old-age deaths "
              f"{d[a:z].mean():5.1f}, minimum starvation {s[a:z].sum():6.0f} ({s[a:z].mean():.1f}/period)")
    print(f"  total minimum starvation {s.sum():.0f} of {b.sum() + n[0]:.0f} agents ever")


if __name__ == "__main__":
    n = book_curve()
    ext = [0] + [int(i) for i in np.nonzero((np.diff(np.sign(np.diff(np.convolve(n, np.ones(9) / 9, "same"))))) != 0)[0] + 1]
    print("book extremes (t, N):", [(int(i), int(n[i])) for i in ext if 20 < i < len(n) - 20][:24])
    report("Fig III-4 (book)", n, [(0, 75), (75, 148), (148, 217), (217, 285), (285, 354), (354, 421), (1000, 1500), (1500, len(n) - 1)])
    rows = list(csv.DictReader(open(ROOT / "results/ch-III/III-4/seed0.csv")))
    ours = np.array([float(r["population"]) for r in rows])
    report("our III-4 seed 0 (check: starvation is 0 after t~100 by count)", ours, [(0, 120), (120, 184), (184, 250), (250, 300), (1000, 1500)])
