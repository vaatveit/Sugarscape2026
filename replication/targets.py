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
    """mean(metric over window a) / mean(metric over window b); nan if b's mean is 0 or nan."""

    def stat(series: Series) -> float:
        num, den = window_mean(metric, *a)(series), window_mean(metric, *b)(series)
        return math.nan if den == 0 or math.isnan(den) else num / den

    return stat


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



# --- Chapter III: regimes and outcomes ----------------------------------------------------


def _window(series: Series, metric: str, t0: int, t1: int) -> list[float]:
    return [v for v in _values(series, metric, t0, t1) if not math.isnan(v)]


def window_min(metric: str, t0: int, t1: int) -> Statistic:
    return lambda series: float(min(w)) if (w := _window(series, metric, t0, t1)) else math.nan


def window_max(metric: str, t0: int, t1: int) -> Statistic:
    return lambda series: float(max(w)) if (w := _window(series, metric, t0, t1)) else math.nan


def window_range(metric: str, t0: int, t1: int) -> Statistic:
    return lambda series: float(max(w) - min(w)) if (w := _window(series, metric, t0, t1)) else math.nan


def relative_std(metric: str, t0: int, t1: int) -> Statistic:
    """Standard deviation / mean over the window (nan when empty or the mean is 0)."""

    def stat(series: Series) -> float:
        w = _window(series, metric, t0, t1)
        if not w or np.mean(w) == 0:
            return math.nan
        return float(np.std(w) / np.mean(w))

    return stat


def dominant_period(metric: str, t0: int, t1: int) -> Statistic:
    """Lag of the first positive autocorrelation peak after the autocorrelation first turns
    negative; nan for flat, monotone, or too-short series (no oscillation)."""

    def stat(series: Series) -> float:
        x = np.asarray(_window(series, metric, t0, t1), dtype=float)
        if len(x) < 4:
            return math.nan
        x = x - x.mean()
        if not np.any(x):
            return math.nan
        n = len(x)
        ac = np.correlate(x, x, "full")[n - 1 :]
        ac = ac / ac[0]
        negative = np.nonzero(ac < 0)[0]
        if len(negative) == 0:
            return math.nan
        for j in range(int(negative[0]) + 1, n - 1):
            if ac[j] > 0 and ac[j] >= ac[j - 1] and ac[j] >= ac[j + 1]:
                return float(j)
        return math.nan

    return stat


def _row_at(series: Series, t: int) -> dict[str, float] | None:
    return next((row for row in series if row["t"] == t), None)


def extinct_by(t: int) -> Statistic:
    """1.0 if the population is 0 at t, else 0.0 (nan if t wasn't recorded)."""

    def stat(series: Series) -> float:
        row = _row_at(series, t)
        return math.nan if row is None else float(row["population"] == 0)

    return stat


def _side(blue: float, red: float) -> tuple[str, float] | None:
    total = blue + red
    if total == 0:
        return None
    return ("blue", blue / total) if blue >= red else ("red", red / total)


def tribal_outcome(t: int, kind: str, purity: float = 0.95) -> Statistic:
    """Indicator of a tribal pattern at t, from the SW/NE side counts (p.83, p.92 fn 32).

    "opposite": each side has a majority tribe with share >= purity, and they differ;
    "blue_both"/"red_both": both sides are majority that tribe with share >= purity;
    "three_patterns": one tribe extinct (the other alive), or "opposite";
    "pure_sides": every non-empty side has majority share >= purity, any colors (p.74 fn 22).
    """

    def stat(series: Series) -> float:
        row = _row_at(series, t)
        if row is None:
            return math.nan
        sw = _side(row["sw_blue"], row["sw_red"])
        ne = _side(row["ne_blue"], row["ne_red"])
        both = sw is not None and ne is not None and sw[1] >= purity and ne[1] >= purity
        if kind == "opposite":
            return float(both and sw[0] != ne[0])
        if kind in ("blue_both", "red_both"):
            colour = kind.split("_")[0]
            return float(both and sw[0] == ne[0] == colour)
        if kind == "three_patterns":
            one_left = (row["n_blue"] == 0) != (row["n_red"] == 0)
            return float(one_left or (both and sw[0] != ne[0]))
        if kind == "pure_sides":
            sides = [s for s in (sw, ne) if s is not None]
            return float(bool(sides) and all(share >= purity for _, share in sides))
        raise ValueError(f"unknown tribal outcome {kind!r}")

    return stat


def both_persist(t: int, min_share: float) -> Statistic:
    """1.0 if the smaller tribe holds at least min_share of tagged agents at t."""

    def stat(series: Series) -> float:
        row = _row_at(series, t)
        if row is None:
            return math.nan
        total = row["n_blue"] + row["n_red"]
        return float(total > 0 and min(row["n_blue"], row["n_red"]) / total >= min_share)

    return stat


def centroid_shift(metric: str, t0: int, t1: int) -> Statistic:
    """value(t1) - value(t0), e.g. how far a tribe's mean x + y moved."""
    return lambda series: value_at(metric, t1)(series) - value_at(metric, t0)(series)


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
    Target("II-6-measured", "wave reaches NE peak", None, 0.15, 1.0, value_at("ne_fraction", 200),
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


# --- Chapter III ---------------------------------------------------------------------------

TARGETS += [
    Target("III-1", "steady population", 500, 400, 600, window_mean("population", 500, 2500), "Fig III-1, p.58"),
    Target("III-1", "small fluctuations", 0.10, 0, 0.10, relative_std("population", 500, 2500), "p.57"),
    Target("III-1", "mean vision at t≈900", 5.3, 4.8, 5.8, window_mean("mean_vision", 850, 900), "Fig III-2, p.63"),
    Target("III-1", "mean metabolism, t=300–900", 1.0, 0.9, 1.15, window_mean("mean_metabolism", 300, 900),
           "Fig III-2, p.63"),
    Target("III-3", "oscillation period", 200, 150, 250, dominant_period("population", 300, 2500), "p.64"),
    Target("III-3", "population floor", 250, 200, 350, window_min("population", 300, 2500), "p.64"),
    Target("III-4", "oscillation period", 125, 100, 150, dominant_period("population", 300, 2500), "p.65"),
    Target("III-4", "oscillation range", 1000, 600, 1400, window_range("population", 1500, 2500), "Fig III-4, p.65"),
    Target("III-5", "extinction frequency", None, 0.5, 1.0, extinct_by(1500), "Fig III-5, p.66", proxy=True),
    Target("III-7", "Gini with inheritance", 0.743, 0.65, 0.85, window_mean("gini", 900, 1000), "p.67"),
    Target("III-7", "mean vision at t≈900", 4.3, 3.9, 4.7, window_mean("mean_vision", 850, 900), "Fig III-7, p.68"),
    Target("III-8", "each side culturally pure", None, 0.8, 1.0, tribal_outcome(3000, "pure_sides"), "p.74",
           proxy=True),
    Target("III-8", "best-friend closeness", 0.91, 0.8, 1.0, window_mean("best_friend_closeness", 2900, 3000),
           "Anim III-8, p.80"),
    Target("III-9", "one of the three patterns", None, 0.8, 1.0, tribal_outcome(1000, "three_patterns"), "p.83",
           proxy=True),
    Target("III-11", "both tribes persist", None, 0.8, 1.0, both_persist(1000, 0.2), "Anim III-11, p.86", proxy=True),
    Target("III-12", "Blue wave advances NE", None, 10, 60, centroid_shift("blue_xy", 0, 50), "Anim III-12, p.88",
           proxy=True),
    Target("III-12", "Red wave advances SW", None, -60, -10, centroid_shift("red_xy", 0, 50), "Anim III-12, p.88",
           proxy=True),
    Target("III-13", "combat suppresses Blue's wave", None, -5, 5, centroid_shift("blue_xy", 0, 50),
           "Anim III-13, p.89", proxy=True),
    Target("III-14", "no runaway hegemony", None, 0.5, 1.0, both_persist(1000, 0.1), "p.90", proxy=True),
    Target("III-15", "Red and Blue on opposite mountains", 0.45, 0.3, 0.5, tribal_outcome(1000, "opposite"),
           "p.92 fn 32"),
    Target("III-15", "Red dominates both", 0.25, 0.1, 0.4, tribal_outcome(1000, "red_both"), "p.92 fn 32"),
    Target("III-15", "Blue dominates both", 0.25, 0.1, 0.4, tribal_outcome(1000, "blue_both"), "p.92 fn 32"),
    Target("III-15", "extinction (small frequency)", None, 0, 0.15, extinct_by(1000), "p.92 fn 32"),
]
