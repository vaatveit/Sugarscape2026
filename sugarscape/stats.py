"""Population statistics: inequality (pp.36-38), distributions, and per-period metrics."""

import math
from collections.abc import Sequence

import numpy as np

from sugarscape.rules.culture import closeness


def safe_mean(values: Sequence[float]) -> float:
    values = list(values)
    return float(np.mean(values)) if values else math.nan


def gini(values: Sequence[float]) -> float:
    """Gini ratio sum|xi - xj| / (2 n^2 mean); nan for an empty or zero-wealth population."""
    x = np.sort(np.asarray(values, dtype=float))
    n = len(x)
    if n == 0 or x.sum() == 0:
        return math.nan
    ranks = np.arange(1, n + 1)
    return float(2.0 * np.sum(ranks * x) / (n * x.sum()) - (n + 1) / n)


def lorenz(values: Sequence[float]) -> tuple[np.ndarray, np.ndarray]:
    """Population share vs. wealth share held by the poorest, both from 0 to 1 (p.37)."""
    x = np.sort(np.asarray(values, dtype=float))
    n = len(x)
    pop = np.arange(n + 1) / n
    wealth = np.concatenate([[0.0], np.cumsum(x)]) / x.sum()
    return pop, wealth


def histogram(values: Sequence[float], bins: int = 10) -> tuple[np.ndarray, np.ndarray]:
    return np.histogram(np.asarray(values, dtype=float), bins=bins)


def _fraction(flags: list[bool]) -> float:
    return sum(bool(f) for f in flags) / len(flags) if flags else math.nan


def standard_metrics(model) -> dict[str, float]:
    """Everything the Chapter II experiments record each period."""
    agents = model.agents
    cfg = model.config
    ls = model.landscape
    half_w, half_h = cfg.width // 2, cfg.height // 2
    high = [a for a in agents if a.vision >= 5]
    low = [a for a in agents if a.vision <= 2]
    if cfg.seasons is not None:
        summer_north = 1.0 if ls.is_summer_north(model.t, cfg.seasons[1]) else 0.0
    else:
        summer_north = math.nan
    return {
        "population": float(len(agents)),
        "mean_vision": safe_mean(a.vision for a in agents),
        "mean_metabolism": safe_mean(a.metabolism for a in agents),
        "mean_sugar": safe_mean(a.sugar for a in agents),
        "gini": gini([a.sugar for a in agents]),
        "mean_neighbors": safe_mean(len(a.neighbors) for a in agents),
        "moved": float(sum(a.moved for a in agents)),
        "ne_fraction": _fraction([a.x >= half_w and a.y >= half_h for a in agents]),
        "on_peak_fraction": _fraction([ls.capacity[a.x, a.y] >= 3 for a in agents]),
        "north_frac_high_vision": _fraction([a.y >= half_h for a in high]),
        "north_frac_low_vision": _fraction([a.y >= half_h for a in low]),
        "summer_north": summer_north,
    }


def society_metrics(model) -> dict[str, float]:
    """Chapter III measurements: tribes (p.73), genealogy (p.68), and friends (p.79).

    Sides of the anti-diagonal stand in for the two mountains: SW when x + y < width.
    """
    agents = model.agents
    width = model.config.width
    blue = [a for a in agents if a.tribe == "blue"]
    red = [a for a in agents if a.tribe == "red"]
    tagged = len(blue) + len(red)

    def side(group, sw: bool) -> float:
        return float(sum((a.x + a.y < width) == sw for a in group))

    best, mean_close = [], []
    for a in agents:
        friends = [f for f, _ in a.friends if f.alive and f.tags is not None]
        if a.tags is None or not friends:
            continue
        scores = [closeness(a.tags, f.tags) for f in friends]
        best.append(max(scores))
        mean_close.append(sum(scores) / len(scores))
    return {
        "n_blue": float(len(blue)),
        "n_red": float(len(red)),
        "blue_fraction": len(blue) / tagged if tagged else math.nan,
        "sw_blue": side(blue, True),
        "sw_red": side(red, True),
        "ne_blue": side(blue, False),
        "ne_red": side(red, False),
        "blue_xy": safe_mean(a.x + a.y for a in blue),
        "red_xy": safe_mean(a.x + a.y for a in red),
        # Mean NE-ward travel since birth (disp_x + disp_y), immune to wrapping across the edges.
        "blue_advance": safe_mean(a.disp_x + a.disp_y for a in blue),
        "red_advance": safe_mean(a.disp_x + a.disp_y for a in red),
        "mean_children": safe_mean(len(a.children) for a in agents) if agents else 0.0,
        "best_friend_closeness": safe_mean(best),
        "friend_closeness": safe_mean(mean_close),
    }
