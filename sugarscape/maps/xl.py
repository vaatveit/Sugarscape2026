"""The xl map: `sugar-map.txt` redrawn at 10x the resolution (docs/xl.md; design 2026-10-24-xl, "The xl map").

`sugar-map-xl.txt` is this module's output and is never edited by hand. Other implementations load the file; this
code exists so the map can be rebuilt and audited. Rewrite it with `python -m sugarscape.maps.xl`.

Each terrace boundary is redrawn, not the map replaced by a formula: for each level, the signed distance to the
region's edge at the coarse cell centres is interpolated bilinearly to the fine centres, blurred with a Gaussian of
0.5 coarse cells, and thresholded at zero. Terraces nest. Every 10x10 block keeps its original value at its centre
and as its majority (tested).
"""

from pathlib import Path

import numpy as np

from sugarscape.maps import load_map

FACTOR = 10
SIGMA = 0.5  # coarse cells; 0.8 already moves terraces (design)
XL_MAP = "sugar-map-xl.txt"


def signed_distance(region: np.ndarray) -> np.ndarray:
    """Distance between coarse centres to the nearest cell on the other side: + inside the region, - outside."""
    w, h = region.shape
    xs, ys = np.meshgrid(np.arange(w), np.arange(h), indexing="ij")
    pts = np.stack([xs.ravel(), ys.ravel()], 1).astype(float)
    dist = np.hypot(pts[:, None, 0] - pts[None, :, 0], pts[:, None, 1] - pts[None, :, 1])
    m = region.ravel()
    d_out = np.where(~m[None, :], dist, np.inf).min(1)
    d_in = np.where(m[None, :], dist, np.inf).min(1)
    return np.where(m, d_out, -d_in).reshape(w, h)


def _axis(n: int, k: int):
    """Fine centres along one axis in coarse index units, clamped: (lower index, upper index, weight)."""
    f = (np.arange(n * k) + 0.5) / k - 0.5
    i0 = np.clip(np.floor(f).astype(int), 0, n - 1)
    t = np.where(f < 0, 0.0, np.where(f > n - 1, 1.0, f - np.floor(f)))
    return i0, np.clip(i0 + 1, 0, n - 1), t


def bilinear(field: np.ndarray, k: int) -> np.ndarray:
    """A cell-centred field sampled at the centres of a k-times finer grid; no wrapping (the map's edges don't match)."""
    (a0, a1, ta), (b0, b1, tb) = _axis(field.shape[0], k), _axis(field.shape[1], k)
    lo = field[a0][:, b0] * (1 - tb) + field[a0][:, b1] * tb
    hi = field[a1][:, b0] * (1 - tb) + field[a1][:, b1] * tb
    return lo * (1 - ta)[:, None] + hi * ta[:, None]


def gaussian_blur(f: np.ndarray, sigma: float) -> np.ndarray:
    """Separable Gaussian, sigma in fine cells, truncated at 3 sigma, normalised, edge-replicating padding."""
    r = int(3 * sigma)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    for axis in (0, 1):
        p = np.pad(f, [(r, r) if a == axis else (0, 0) for a in (0, 1)], mode="edge")
        f = sum(w * np.take(p, np.arange(i, i + f.shape[axis]), axis=axis) for i, w in enumerate(k))
    return f


def blurred_levels(capacity: np.ndarray, factor: int = FACTOR, sigma: float = SIGMA) -> list[np.ndarray]:
    """For each level 1..max, the blurred signed distance at the fine centres, before thresholding."""
    return [gaussian_blur(bilinear(signed_distance(capacity >= level), factor), sigma * factor)
            for level in range(1, int(capacity.max()) + 1)]


def upscale(capacity: np.ndarray, factor: int = FACTOR, sigma: float = SIGMA) -> np.ndarray:
    """The capacity map at `factor` times the resolution, as whole levels."""
    inside = np.ones((capacity.shape[0] * factor, capacity.shape[1] * factor), dtype=bool)
    fine = np.zeros(inside.shape, dtype=int)
    for level in blurred_levels(capacity, factor, sigma):
        inside &= level > 0  # a terrace lies within the one below it
        fine += inside
    return fine


def map_text(capacity: np.ndarray) -> str:
    """A map file's text for an [x, y] array: the inverse of `parse_map`, first line northernmost."""
    return "".join(" ".join(str(int(v)) for v in row) + "\n" for row in np.flipud(capacity.T))


def main() -> None:
    path = Path(__file__).with_name(XL_MAP)
    path.write_text(map_text(upscale(load_map("sugar-map.txt"))), encoding="utf-8", newline="\n")
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
