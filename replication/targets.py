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
