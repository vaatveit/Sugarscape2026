"""Fig III-5: digitize, invert (old-age deaths only), and compare births-vs-lagged-N with our III-5 runs."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import csv, sys
import numpy as np
from PIL import Image
from invert_iii4 import invert

from _paths import book_page, ROOT
PAGE = book_page("pc", "p013.png")


def book_curve():
    im = np.asarray(Image.open(PAGE).convert("L"), float)
    y0, per_unit = 585.0, 285.0 / 1500       # pixel row of 0 agents; pixels per agent
    x0, per_px = 186.0, 500 / 107.6           # t=0 column; periods per pixel
    ts, ns = [0.0], [405.0]
    for x in range(189, 330):
        dark = np.nonzero(im[290:583, x] < 110)[0] + 290
        if len(dark):
            ts.append((x - x0) * per_px); ns.append(max(0.0, (y0 - (dark.min() + dark.max()) / 2) / per_unit))
    t = np.arange(0, int(ts[-1]))
    return np.interp(t, ts, ns)


EDGES = [0, 100, 300, 500, 700, 900, 1100, 1300, 1500]


def curve(b, n, tau, t0, t1):
    x, y = n[t0 - tau:t1 - tau], np.convolve(b, np.ones(9) / 9, "same")[t0:t1]
    return [(f"{y[(x >= lo) & (x < hi)].mean():5.1f}" if ((x >= lo) & (x < hi)).sum() > 5 else "  -  ") for lo, hi in zip(EDGES, EDGES[1:])]


n = book_curve(); b, d, s = invert(n)
print("book III-5 extremes:", [(t, int(n[t])) for t in range(10, len(n) - 10) if n[t] == n[t - 10:t + 11].max() or n[t] == n[t - 10:t + 11].min()][:20])
for a, z in ((0, 70), (70, 190), (190, 297), (297, 409), (409, 508), (508, min(600, len(n) - 1))):
    print(f"  t={a}-{z}: N {n[a]:.0f}->{n[z]:.0f} implied births {b[a:z].mean():5.1f}/period, old-age deaths {d[a:z].mean():5.1f}, min starvation {s[a:z].sum():.0f}")
print("births by N 20 periods earlier:", " | ".join(f"{a}-{z}" for a, z in zip(EDGES, EDGES[1:])))
print("  book:", " | ".join(curve(b, n, 20, 100, len(n) - 30)))
for seed in (4, 7, 9):
    rows = list(csv.DictReader(open(ROOT / f"results/ch-III/III-5/seed{seed}.csv")))
    o = np.array([float(r["population"]) for r in rows]); bo, _, _ = invert(o)
    print(f"  ours seed {seed} (t=300-1500):", " | ".join(curve(bo, o, 20, 300, 1500)), f"| min N after 300: {o[300:].min():.0f}")
