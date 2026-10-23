"""Count agents (dark blobs) in each panel of a 3x2 animation plate. Args: png, threshold, min_size."""
import sys
from collections import deque
import numpy as np
from PIL import Image

img = np.asarray(Image.open(sys.argv[1]).convert("L"), int)
thr, min_size = int(sys.argv[2]), int(sys.argv[3])
BOXES = [(148, 232, 448, 522), (455, 232, 752, 522), (148, 545, 448, 838),
         (455, 545, 752, 838), (148, 858, 448, 1150), (455, 858, 752, 1150)]


def blobs(mask):
    seen = np.zeros_like(mask, bool)
    sizes = []
    h, w = mask.shape
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not seen[y, x]:
                q, n = deque([(y, x)]), 0
                seen[y, x] = True
                while q:
                    cy, cx = q.popleft()
                    n += 1
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                sizes.append(n)
    return np.array(sizes)


DX, DY = (int(v) for v in (sys.argv[4] if len(sys.argv) > 4 else "0,0").split(","))
BOXES = [(a + DX, b + DY, c + DX, d + DY) for a, b, c, d in BOXES]
for k, (x0, y0, x1, y1) in enumerate(BOXES, 1):
    sub = img[y0:y1, x0:x1].copy()
    sub[:28, :28] = 255  # panel number badge
    s = blobs(sub < thr)
    big = s[s >= min_size]
    # merged blobs (adjacent agents touching) count as several: estimate by size / median single size
    med = np.median(big) if len(big) else 1
    est = int(np.sum(np.maximum(1, np.round(big / med))))
    print(f"panel {k}: blobs {len(big):4d}  median size {med:4.0f}  est. agents {est}")
