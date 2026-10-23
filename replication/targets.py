"""Book target values, each with a pass band and the per-seed statistic that measures it.

Bands are starting tolerances. Widen one only with recorded seed-spread evidence, never to
make a target pass (design anti-goal).
"""

import math
from collections.abc import Callable
from dataclasses import dataclass, replace

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
    # When set, each seed's value is the statistic divided by the same statistic on this
    # experiment's seed of the same index (the book's comparative claims, Chapter VI).
    baseline: str | None = None


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
    negative; nan for flat, monotone, or too-short series (no oscillation). Superseded by
    peak_spacing for the period targets (2026-10-23)."""

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


def peak_spacing(metric: str, t0: int, t1: int, smooth: int = 41, swing: float = 40) -> Statistic:
    """Median interval between successive peaks of the series smoothed by a `smooth`-period moving average.

    A zigzag filter finds the peaks: a peak counts once the smoothed series falls `swing` below it, and a
    trough once it rises `swing` above it, so smaller wiggles are noise. The first swing only sets the
    direction, so a window that opens on a peak doesn't count it. nan with fewer than two peaks.
    Replaces dominant_period for the period targets: on irregular series the first autocorrelation peak
    jumps between harmonics (201-1,701 on III-3, Chapter III record).
    """

    def stat(series: Series) -> float:
        x = np.asarray(_window(series, metric, t0, t1), dtype=float)
        if len(x) < smooth:
            return math.nan
        y = np.convolve(x, np.ones(smooth) / smooth, "valid")
        peaks, direction, hi, lo = [], 0, 0, 0
        for i, v in enumerate(y):
            if v > y[hi]:
                hi = i
            if v < y[lo]:
                lo = i
            if direction >= 0 and v <= y[hi] - swing:  # a fall: the high was a peak (unless still undecided)
                if direction > 0:
                    peaks.append(hi)
                direction, lo = -1, i
            elif direction <= 0 and v >= y[lo] + swing:  # a rise: start looking for the next peak
                direction, hi = 1, i
        return float(np.median(np.diff(peaks))) if len(peaks) >= 2 else math.nan

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


def combat_outcome(t0: int, t1: int) -> Statistic:
    """1.0 if C_inf ended in one of the book's three patterns (p.83): one tribe eradicated; Red and
    Blue on opposite mountains; or small colonies coexisting, read as both tribes alive with
    unchanged counts over [t0, t1] (a frozen absorbing state)."""

    def stat(series: Series) -> float:
        rows = [r for r in series if t0 <= r["t"] <= t1]
        if not rows or rows[-1]["t"] != t1:
            return math.nan
        last = rows[-1]
        if (last["n_blue"] == 0) != (last["n_red"] == 0):
            return 1.0
        if tribal_outcome(t1, "opposite")(series) == 1.0:
            return 1.0
        both_alive = last["n_blue"] > 0 and last["n_red"] > 0
        frozen = all((r["n_blue"], r["n_red"]) == (last["n_blue"], last["n_red"]) for r in rows)
        return float(both_alive and frozen)

    return stat


def first_time_pure(purity: float = 1.0) -> Statistic:
    """First recorded t at which every non-empty side is culturally pure (p.74: "all agents Blue
    after some 2700 time periods"); nan if it never happens."""

    def stat(series: Series) -> float:
        for row in series:
            if tribal_outcome(int(row["t"]), "pure_sides", purity)([row]) == 1.0:
                return float(row["t"])
        return math.nan

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
# The same points read early (t=45-60), where our populations match the book's: the sweep may have been read near
# t≈50 rather than at the asymptote (Chapter II record). Counted beside the t=500 rows (decision 2026-10-23).
TARGETS += [
    Target(f"II-5/m{m}/v{v}", "carrying capacity at t≈50", cc, 0.9 * cc, 1.1 * cc,
           window_mean("population", 45, 60), "Fig II-5, p.31")
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
    Target("III-3", "oscillation period", 200, 150, 250, peak_spacing("population", 300, 2500), "p.64"),
    Target("III-3", "population floor", 250, 200, 350, window_min("population", 300, 2500), "p.64"),
    Target("III-3", "agents that ever lived", 12500, 10000, 15000, value_at("agents_ever", 2500), "p.64 fn 10"),
    Target("III-4", "oscillation period", 125, 100, 150, peak_spacing("population", 300, 2500), "p.65"),
    Target("III-4", "oscillation range", 1000, 600, 1400, window_range("population", 1500, 2500), "Fig III-4, p.65"),
    Target("III-5", "extinction frequency", None, 0.5, 1.0, extinct_by(1500), "Fig III-5, p.66", proxy=True),
    Target("III-7", "Gini with inheritance", 0.743, 0.65, 0.85, window_mean("gini", 900, 1000), "p.67"),
    Target("III-7", "mean vision at t≈900", 4.3, 3.9, 4.7, window_mean("mean_vision", 850, 900), "Fig III-7, p.68"),
    Target("III-8", "each side culturally pure", None, 0.8, 1.0, tribal_outcome(6000, "pure_sides"), "p.74",
           proxy=True),
    Target("III-8", "time until every side is pure", 2700, 1350, 5400, first_time_pure(), "p.74"),
    Target("III-8", "best-friend closeness", 0.91, 0.8, 1.0, window_mean("best_friend_closeness", 2900, 3000),
           "Anim III-8, p.80"),
    Target("III-9", "one of the three patterns", None, 0.8, 1.0, combat_outcome(750, 1000), "p.83",
           proxy=True),
    Target("III-11", "both tribes persist", None, 0.8, 1.0, both_persist(1000, 0.2), "Anim III-11, p.86", proxy=True),
    Target("III-12", "Blue wave advances NE", None, 10, 60, centroid_shift("blue_advance", 0, 50), "Anim III-12, p.88",
           proxy=True),
    Target("III-12", "Red wave advances SW", None, -60, -10, centroid_shift("red_advance", 0, 50), "Anim III-12, p.88",
           proxy=True),
    Target("III-13", "combat suppresses Blue's wave", None, -5, 5, centroid_shift("blue_advance", 0, 50),
           "Anim III-13, p.89", proxy=True),
    Target("III-14", "no runaway hegemony", None, 0.5, 1.0, both_persist(1000, 0.1), "p.90", proxy=True),
    Target("III-15", "Red and Blue on opposite mountains", 0.45, 0.3, 0.5, tribal_outcome(6000, "opposite"),
           "p.92 fn 32"),
    Target("III-15", "Red dominates both", 0.25, 0.1, 0.4, tribal_outcome(6000, "red_both"), "p.92 fn 32"),
    Target("III-15", "Blue dominates both", 0.25, 0.1, 0.4, tribal_outcome(6000, "blue_both"), "p.92 fn 32"),
    Target("III-15", "extinction (small frequency)", None, 0, 0.15, extinct_by(6000), "p.92 fn 32"),
]


# --- Chapter IV ----------------------------------------------------------------------------

TARGETS += [
    Target("IV-3", "mean price (ln p)", 0.0, -0.1, 0.1, window_mean("mean_log_price", 500, 1000), "Fig IV-3, p.109"),
    Target("IV-3", "price dispersion at t≈1000", 0.05, 0, 0.1, window_mean("price_sd", 900, 1000), "Fig IV-5, p.110"),
    Target("IV-3", "trades per period", 150, 100, 200, window_mean("trades", 1, 1000), "p.109"),
]
FIG_IV_6 = {"trade": {1: 100, 2: 128, 3: 158, 6: 173, 10: 185}, "notrade": {1: 82, 2: 90, 3: 120, 6: 157, 10: 177}}
TARGETS += [
    Target(f"IV-6/{kind}/v{v}", "carrying capacity", cc, 0.9 * cc, 1.1 * cc,
           window_mean("population", 450, 500), "Fig IV-6, p.112")
    for kind, points in FIG_IV_6.items() for v, cc in points.items()
]
TARGETS += [  # read early, as for Fig II-5 above (decision 2026-10-23)
    Target(f"IV-6/{kind}/v{v}", "carrying capacity at t≈50", cc, 0.9 * cc, 1.1 * cc,
           window_mean("population", 45, 60), "Fig IV-6, p.112")
    for kind, points in FIG_IV_6.items() for v, cc in points.items()
]
TARGETS += [
    Target("IV-7", "mean price, vision 1 (ln p)", 0.0, -0.15, 0.15, window_mean("mean_log_price", 1, 1000), "p.117"),
    Target("IV-7", "dispersion stays high", 0.3, 0.2, 0.45, window_mean("price_sd", 800, 1000), "Fig IV-8, p.118"),
    Target("IV-9", "dispersion with vision 1-15", 0.03, 0, 0.08, window_mean("price_sd", 800, 1000), "Fig IV-9, p.119"),
    Target("IV-12/a80", "dispersion, lifespan 60-100", 0.5, 0.4, 0.6, window_mean("price_sd", 200, 1000),
           "Figs IV-10, IV-12"),
    Target("IV-12/a300", "dispersion, lifespan 280-320", 0.3, 0.22, 0.38, window_mean("price_sd", 800, 1000),
           "Fig IV-12"),
    Target("IV-12/a550", "dispersion, lifespan 530-570", 0.2, 0.12, 0.28, window_mean("price_sd", 800, 1000),
           "Fig IV-12"),
    Target("IV-12/a980", "dispersion, lifespan 960-1000", 0.15, 0.08, 0.22, window_mean("price_sd", 800, 1000),
           "Figs IV-11, IV-12"),
]
FIG_IV_13 = {"trade": {1.5: 0.41, 3.5: 0.42, 5.5: 0.44, 10: 0.37, 14.5: 0.38},
             "notrade": {1.5: 0.43, 3.5: 0.39, 5.5: 0.34, 10: 0.33, 14.5: 0.31}}
TARGETS += [
    Target(f"IV-13/{kind}/v{v:g}", f"Gini {'with' if kind == 'trade' else 'without'} trade", g, g - 0.05, g + 0.05,
           window_mean("gini", 300, 500), "Fig IV-13, p.123")
    for kind, points in FIG_IV_13.items() for v, g in points.items()
]
TARGETS += [
    Target("IV-14", "dispersion with S", 0.37, 0.28, 0.48, window_mean("price_sd", 300, 1000), "Fig IV-14, p.124"),
    Target("IV-15", "dispersion, cultural preferences", 0.45, 0.3, 0.6, window_mean("price_sd", 500, 1000),
           "Fig IV-16, p.126"),
    Target("IV-15", "trades per period", 1000, 500, 1500, window_mean("trades", 1, 1000), "p.125"),
    Target("IV-17", "dispersion with S and K", 0.45, 0.35, 0.55, window_mean("price_sd", 400, 1000),
           "Fig IV-17, p.127"),
    Target("IV-A3", "price before pollution (ln p)", 0.0, -0.2, 0.2, window_mean("mean_log_price", 50, 100),
           "Anim IV-3, p.128"),
    Target("IV-A3", "sugar price spike", 3.5, 2, 6, window_max("mean_price", 140, 200), "Anim IV-3", proxy=True),
    Target("IV-A3", "recovery by t≈300 (ln p)", 0.0, -0.25, 0.25, window_mean("mean_log_price", 280, 300),
           "Anim IV-3, p.129"),
    Target("IV-18", "long-run mean foresight", 4.9, 4.25, 5.5, window_mean("mean_foresight", 400, 1000),
           "Fig IV-18, p.130"),
    Target("IV-A5", "active loans", 187, 50, 400, window_mean("n_loans", 200, 500), "Anim IV-5, p.134", proxy=True),
    Target("IV-A5", "agents both lending and borrowing", 21, 5, 100, window_mean("n_both", 200, 500), "Anim IV-5",
           proxy=True),
    Target("IV-A5", "hierarchy levels", 5, 3, 8, window_max("credit_depth", 200, 500), "p.133", proxy=True),
]


# --- Chapter V -----------------------------------------------------------------------------

TARGETS += [
    Target("V-1", "society rids itself of disease", 0.0, 0, 0.01, window_mean("fraction_sick", 450, 500),
           "Anim V-1, p.147"),
    Target("V-1", "no disease left circulating", 0.0, 0, 0.5, value_at("diseases_circulating", 500), "p.147"),
    Target("V-2", "endemic infection persists", None, 0.2, 0.8, window_mean("fraction_sick", 300, 500),
           "Anim V-2, p.150", proxy=True),
    Target("V-2", "average diseases at start", 3.41, 2.5, 4.5, value_at("mean_diseases", 0), "Anim V-3, p.151"),
    Target("V-2", "endemic average diseases", 0.86, 0.6, 1.1, window_mean("mean_diseases", 300, 500),
           "Anim V-3, p.151"),
    Target("V-2", "spread of diseases per agent", 1.0, 0.8, 1.2, window_mean("sd_diseases", 300, 500),
           "Anim V-3, p.151"),
]


# --- Chapter VI ----------------------------------------------------------------------------
# VI-1 values are read from Animation VI-1's panels (frame times estimated from their axes).
# Bands: ±20% of a reading, ±0.1 for shares, ±50% for credit counts (one run, small numbers).

TARGETS += [
    Target("VI-1", "population at t≈50", 155, 125, 185, window_mean("population", 45, 50), "Anim VI-1 fr. 6"),
    Target("VI-1", "Gini of total wealth", 0.246, 0.20, 0.30, window_mean("gini", 40, 50), "Anim VI-1 fr. 5"),
    Target("VI-1", "average neighbors", 0.7, 0.56, 0.84, window_mean("mean_neighbors", 1, 50), "Anim VI-1 fr. 2"),
    Target("VI-1", "average fertility", 1.3, 1.04, 1.56, window_mean("mean_children", 50, 60), "Anim VI-1 fr. 8"),
    Target("VI-1", "best-friend closeness", 0.86, 0.76, 0.96, window_mean("best_friend_closeness", 50, 70),
           "Anim VI-1 fr. 10"),
    Target("VI-1", "friend closeness", 0.79, 0.69, 0.89, window_mean("friend_closeness", 50, 70), "Anim VI-1 fr. 10"),
    Target("VI-1", "mean price (ln p)", 0.0, -0.2, 0.2, window_mean("mean_log_price", 1, 95), "Anim VI-1 fr. 11"),
    Target("VI-1", "price dispersion", 0.35, 0.28, 0.42, window_mean("price_sd", 1, 95), "Anim VI-1 fr. 12"),
    Target("VI-1", "trades per period", 125, 100, 150, window_mean("trades", 25, 95), "Anim VI-1 fr. 13"),
    Target("VI-1", "active loans", 215, 108, 322, window_mean("n_loans", 100, 120), "Anim VI-1 fr. 15-16"),
    Target("VI-1", "agents both lending and borrowing", 37, 18, 56, window_mean("n_both", 100, 120),
           "Anim VI-1 fr. 15-16"),
    Target("VI-1", "infected fraction dips", 0.6, 0.5, 0.7, window_min("fraction_sick", 50, 100), "Anim VI-1 fr. 17"),
    Target("VI-1", "infected fraction recovers", 0.85, 0.75, 0.95, window_mean("fraction_sick", 110, 120),
           "Anim VI-1 fr. 17"),
    Target("VI-1", "average diseases", 2.26, 1.81, 2.71, window_mean("mean_diseases", 115, 125), "Anim VI-1 fr. 18"),
    Target("VI-1", "spread of diseases per agent", 1.47, 1.18, 1.76, window_mean("sd_diseases", 115, 125),
           "Anim VI-1 fr. 18"),
]
# p.159: VI-2 and VI-3 differ only in trade, so paired seeds start from the identical society.
TARGETS += [
    Target("VI-2", "crash by t≈20", 130, 104, 156, window_mean("population", 18, 22), "Anim VI-2, p.160"),
    Target("VI-2", "extinction frequency", None, 0.5, 1.0, extinct_by(200), "Anim VI-2, p.159", proxy=True),
    Target("VI-3", "early decline as without trade", 1.0, 0.8, 1.25, window_mean("population", 0, 75), "p.159",
           baseline="VI-2"),
    Target("VI-3", "near-extinction minimum", 65, 52, 78, window_min("population", 40, 120), "Anim VI-3, p.161"),
    Target("VI-3", "first peak", 1190, 952, 1428, window_max("population", 150, 300), "Anim VI-3, p.161"),
    Target("VI-3", "oscillation floor", 700, 560, 840, window_min("population", 250, 1000), "p.159"),
    Target("VI-3", "oscillation ceiling", 1200, 960, 1440, window_max("population", 250, 1000), "Anim VI-3, p.161"),
    Target("VI-3", "oscillation period", 115, 92, 138, peak_spacing("population", 200, 1000), "p.159"),
]
TARGETS += [
    Target("VI-4", "equilibrium: nobody moves", 0.0, 0, 0, window_mean("moved", 400, 500), "p.166"),
    Target("VI-4", "more segregated than the start", None, 1.05, 2.0,
           ratio_of_windows("like_fraction", (500, 500), (0, 0)), "Anim VI-4, p.166", proxy=True),
    Target("VI-5", "never settles", None, 1, 2000, window_mean("moved", 400, 500), "p.166", proxy=True),
    Target("VI-5", "segregation comparable", None, 0.9, 1.1, window_mean("like_fraction", 300, 500), "p.166",
           proxy=True, baseline="VI-4"),
    Target("VI-6", "far higher segregation", None, 1.2, 2.0, window_mean("like_fraction", 300, 500), "p.170",
           proxy=True, baseline="VI-5"),
    Target("VI-7", "high segregation endures", None, 0.9, 1.1, window_mean("like_fraction", 300, 500), "p.170",
           proxy=True, baseline="VI-6"),
]
TARGETS += [
    Target("VI-8", "agents cluster into groups", None, 2, 20,
           ratio_of_windows("mean_group_size", (400, 500), (0, 0)), "p.172", proxy=True),
    Target("VI-8", "slow agents are absorbed", None, 0.8, 1.0, window_mean("clustered_fraction", 400, 500), "p.172",
           proxy=True),
    Target("VI-8", "groups outpace loners", None, 1.5, 40, window_mean("speed_ratio", 1, 500), "p.172", proxy=True),
    Target("VI-8", "groups of comparable size", None, 0, 0.5, window_mean("group_size_cv", 400, 500), "p.172",
           proxy=True),
    Target("VI-8", "size bounded by the most nearsighted", None, 0.9, 1.0,
           window_mean("within_vision_bound", 100, 500), "p.175", proxy=True),
    Target("VI-9", "megagroup breaks up", None, 2, 30, window_mean("largest_group", 200, 500), "p.174", proxy=True),
    Target("VI-9", "into several groups", None, 2, 20, window_mean("n_groups", 200, 500), "p.174", proxy=True),
    Target("VI-9", "like-sized cliques", None, 0, 0.5, window_mean("group_size_cv", 200, 500), "p.174", proxy=True),
    Target("VI-9", "size bounded by the most nearsighted", None, 0.9, 1.0,
           window_mean("within_vision_bound", 100, 500), "p.175", proxy=True),
]


# --- Reproduction-rule variants ------------------------------------------------------------
# The same targets, run on each variant (experiments.registry.VARIANTS): VAR-book is p.55 as written.
# III-1's steady population is the quantity the default threshold, VAR-share and VAR-c1c3fit were fitted to.
_VAR_NAMES = ("book", "share", "c1c3fit")
_VAR_FIGURES = ("III-1", "III-3", "III-4", "III-5", "VI-2", "VI-3")
TARGETS += [
    replace(t, experiment=f"VAR-{name}/{t.experiment}", baseline=f"VAR-{name}/{t.baseline}" if t.baseline else None)
    for name in _VAR_NAMES for t in list(TARGETS) if t.experiment in _VAR_FIGURES
]
