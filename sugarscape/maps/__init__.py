"""Resource capacity maps.

`sugar-map.txt` is the 50x50 map used by the NetLogo Sugarscape models (NetLogo/models,
Sample Models/Social Science/Economics/Sugarscape), matching Figure II-1 (p.21): two
terraced peaks of capacity 4 in the northeast and southwest.
"""

from importlib import resources

import numpy as np


def load_map(name: str) -> np.ndarray:
    """Load a capacity map as an int array indexed [x, y] (x east, y north).

    The file holds whitespace-separated integers, one line per row, first line northernmost.
    """
    return parse_map(resources.files(__package__).joinpath(name).read_text())


def parse_map(text: str) -> np.ndarray:
    """A map file's text as an int array indexed [x, y] (see `load_map`)."""
    rows = [[int(v) for v in line.split()] for line in text.splitlines() if line.strip()]
    grid = np.array(rows, dtype=int)  # grid[row, col], row 0 = north
    return np.flipud(grid).T.copy()  # -> [x, y] with y = 0 the southern row
