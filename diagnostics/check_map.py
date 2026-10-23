"""Check the capacity map (sugarscape/maps/sugar-map.txt) against Fig II-1 (p.22) site by site (README candidate C5).

Fig II-1 survives in the scan as a blurred grayscale halftone, one glyph per site, darker for more sugar. The grid's
pitch comes from the darkness profiles (FFT); its start and pitch on each axis are then registered to the map, chosen
to maximize the correlation between site darkness and capacity over a search of a full period either way. Four global
numbers can't manufacture local agreement, which is what the check measures. Each site is read as the map level whose
mean darkness is nearest. The script reports agreement overall, off terrace edges (where the blur mixes neighbors), on
the saddle between the mountains, and the count of sites at each level.

Needs p.22 rendered at scale 8 or so (render.py <pdf folder> <out> 8 gives pages/pb/p002.png); argv[1] overrides the
page image's path.
"""
import sys

import numpy as np
from PIL import Image

from _paths import ROOT, book_page

CROP = (120 / 864, 215 / 864, 450 / 864, 560 / 864)  # Fig II-1 on the page, as fractions of the page's width


def pitch(profile):
    p = profile - profile.mean()
    return len(p) / (np.argmax(np.abs(np.fft.rfft(p))[5:]) + 5)


def darkness(integral, cx, cy, half):
    """Mean darkness in a (2 half + 1)-pixel square around each (cy, cx), from the image's integral."""
    x0, x1 = np.round(cx).astype(int) - half, np.round(cx).astype(int) + half + 1
    y0, y1 = np.round(cy).astype(int) - half, np.round(cy).astype(int) + half + 1
    x0, y0 = np.meshgrid(x0, y0)
    x1, y1 = np.meshgrid(x1, y1)
    s = integral[y1, x1] - integral[y0, x1] - integral[y1, x0] + integral[y0, x0]
    return s / ((2 * half + 1) ** 2)


if __name__ == "__main__":
    page = Image.open(sys.argv[1] if len(sys.argv) > 1 else book_page("pb", "p002.png")).convert("L")
    w = page.size[0]
    fig = 255 - np.asarray(page.crop(tuple(int(f * w) for f in CROP)), float)
    h, wd = fig.shape
    integral = np.pad(fig.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    cap = np.loadtxt(ROOT / "sugarscape" / "maps" / "sugar-map.txt").astype(int)
    px = pitch(fig[int(0.07 * h):int(0.9 * h)].mean(axis=0))
    py = pitch(fig[:, int(0.07 * wd):int(0.94 * wd)].mean(axis=1))
    half = int(min(px, py) * 0.3)
    n = np.arange(50)
    # start in the middle of the figure, then alternate axes
    sx, sy = (wd - 50 * px) / 2, (h - 50 * py) / 2
    for _ in range(3):
        for axis in ("x", "y"):
            best = None
            p0, s0 = (px, sx) if axis == "x" else (py, sy)
            for p in np.linspace(0.97 * p0, 1.03 * p0, 31):
                for s in np.arange(s0 - p0, s0 + p0, 0.5):
                    cx, cy = (s + p * n, sy + py * n) if axis == "x" else (sx + px * n, s + p * n)
                    if min(cx[0], cy[0]) < half + 1 or cx[-1] > wd - half - 2 or cy[-1] > h - half - 2:
                        continue
                    r = np.corrcoef(darkness(integral, cx, cy, half).ravel(), cap.ravel())[0, 1]
                    if best is None or r > best[0]:
                        best = (r, p, s)
            if axis == "x":
                _, px, sx = best
            else:
                _, py, sy = best
    dark = darkness(integral, sx + px * n, sy + py * n, half)
    print(f"grid: {px:.2f} x {py:.2f} px per site, first site at ({sx:.1f}, {sy:.1f}); window {2 * half + 1} px; "
          f"darkness-capacity correlation {best[0]:.3f}")
    means = np.array([dark[cap == level].mean() for level in range(5)])
    read = np.argmin(np.abs(dark[..., None] - means), axis=-1)
    print(f"  mean darkness by level 0-4 {np.round(means, 1)}, spread {np.round([dark[cap == k].std() for k in range(5)], 1)}")
    padded = np.pad(cap, 1, mode="edge")
    edge = np.zeros_like(cap, bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            edge |= padded[1 + dy:51 + dy, 1 + dx:51 + dx] != cap
    agree = read == cap
    off = np.abs(read - cap)
    saddle = (slice(15, 35), slice(15, 35))
    print(f"  sites read as their map level: {agree.mean():.3f}; off terrace edges {agree[~edge].mean():.3f} of "
          f"{(~edge).sum()}, on edges {agree[edge].mean():.3f} of {edge.sum()}")
    print("  sites off by 0/1/2/3+ levels:", [int((off == k).sum()) for k in range(3)] + [int((off >= 3).sum())])
    print("  off by two or more (row, col, map, figure):",
          [(int(r), int(c), int(cap[r, c]), int(read[r, c])) for r, c in np.argwhere(off >= 2)][:20])
    print(f"  saddle (rows and columns 15-34): {agree[saddle].mean():.3f} agree; mean level map "
          f"{cap[saddle].mean():.2f}, figure {read[saddle].mean():.2f}")
    print("  sites at levels 0-4: map", [int((cap == k).sum()) for k in range(5)],
          "figure", [int((read == k).sum()) for k in range(5)])
