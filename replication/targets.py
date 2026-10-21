"""Book target values, each with a pass band and the per-seed statistic that measures it.

Bands are starting tolerances. Widen one only with recorded seed-spread evidence, never to
make a target pass (design anti-goal).
"""

import math
from collections.abc import Callable
from dataclasses import dataclass

import numpy as np

Series = list[dict[str, float]]
Statistic = Callable[[Series], float]


@dataclass(frozen=True)
class Target:
    experiment: str
    name: str  # e.g. "carrying capacity"
    book_value: float | None  # None for proxies of qualitative results
    low: float  # pass band
    high: float
    statistic: Statistic  # per-seed value
    source: str  # e.g. "Fig II-4, p.31"
    proxy: bool = False  # True when measuring a qualitative claim


def _values(series: Series, metric: str, t0: float = -math.inf, t1: float = math.inf) -> list[float]:
    return [row[metric] for row in series if t0 <= row["t"] <= t1]


def _nanmean(values: list[float]) -> float:
    values = [v for v in values if not math.isnan(v)]
    return float(np.mean(values)) if values else math.nan


def window_mean(metric: str, t0: int, t1: int) -> Statistic:
    """Mean of `metric` over periods t0..t1 inclusive."""
    return lambda series: _nanmean(_values(series, metric, t0, t1))


def value_at(metric: str, t: int) -> Statistic:
    return lambda series: _nanmean(_values(series, metric, t, t))


def ratio_of_windows(metric: str, a: tuple[int, int], b: tuple[int, int]) -> Statistic:
    """mean(metric over window a) / mean(metric over window b)."""
    return lambda series: window_mean(metric, *a)(series) / window_mean(metric, *b)(series)


def seasonal_amplitude(metric: str, start: int, gamma: int, settle: int) -> Statistic:
    """Mean of `metric` in northern summer minus in northern winter, over t >= start.

    Skips the first `settle` periods after each season flip (flips fall on multiples of gamma).
    """

    def stat(series: Series) -> float:
        rows = [r for r in series if r["t"] >= start and r["t"] % gamma >= settle]
        summer = [r[metric] for r in rows if r["summer_north"] == 1.0]
        winter = [r[metric] for r in rows if r["summer_north"] == 0.0]
        return _nanmean(summer) - _nanmean(winter)

    return stat


TARGETS: list[Target] = []


# --- Chapter II ---------------------------------------------------------------------------

TARGETS += [
    Target("II-1", "agents still moving", None, 0, 0.5, window_mean("moved", 80, 100),
           "Anim II-1, p.28", proxy=True),
    Target("II-4", "carrying capacity", 224, 205, 245, window_mean("population", 450, 500),
           "Fig II-4, p.31"),
    Target("II-4", "mean vision at t=500", 4.1, 3.9, 4.3, value_at("mean_vision", 500), "p.32"),
    Target("II-4", "mean metabolism at t=500", 1.8, 1.6, 2.0, value_at("mean_metabolism", 500), "p.32"),
    Target("II-4", "mean neighbors", 0.9, 0.75, 1.05, window_mean("mean_neighbors", 100, 500),
           "Anim II-5, p.41"),
    Target("II-4-gini", "initial Gini", 0.230, 0.20, 0.26, value_at("gini", 0), "Anim II-4, p.38"),
    Target("II-4-gini", "long-run Gini", 0.503, 0.45, 0.56, window_mean("gini", 300, 500),
           "Anim II-4, p.37"),
    Target("II-6", "wave reaches NE peak", None, 0.15, 1.0, value_at("ne_fraction", 200),
           "Anim II-6, p.43", proxy=True),
    Target("II-7", "high-vision agents migrate", None, 0.3, 1.0,
           seasonal_amplitude("north_frac_high_vision", 100, 50, 10), "Anim II-7, p.45", proxy=True),
    Target("II-7", "low-vision agents hibernate", None, -0.15, 0.15,
           seasonal_amplitude("north_frac_low_vision", 100, 50, 10), "Anim II-7, p.45", proxy=True),
    Target("II-8", "peaks abandoned under pollution", None, 0, 0.6,
           ratio_of_windows("on_peak_fraction", (90, 100), (40, 50)), "Anim II-8, p.48", proxy=True),
    Target("II-8", "lower carrying capacity when polluted", None, 0, 0.9,
           ratio_of_windows("population", (95, 100), (45, 50)), "p.50", proxy=True),
]

# Fig II-5 (p.31): carrying capacity by mean metabolism and mean vision, band ±10%.
FIG_II_5_BOOK = {
    1: {"1": 450, "2": 465, "3": 475, "5.5": 490, "10.5": 495},
    2: {"1": 330, "2": 365, "3": 375, "5.5": 390, "10.5": 400},
    3: {"1": 225, "2": 228, "3": 255, "4.5": 260, "5.5": 260, "6.5": 287, "8": 280, "10.5": 287},
}
TARGETS += [
    Target(f"II-5/m{m}/v{v}", "carrying capacity", cc, 0.9 * cc, 1.1 * cc,
           window_mean("population", 450, 500), "Fig II-5, p.31")
    for m, points in FIG_II_5_BOOK.items()
    for v, cc in points.items()
]
