import math

import numpy as np
import pytest

from replication.report import evaluate, write_report
from replication.targets import (
    Target,
    ratio_of_windows,
    seasonal_amplitude,
    value_at,
    window_mean,
)

SERIES = [{"t": t, "population": 400 - t, "summer_north": float(t < 5)} for t in range(10)]


def test_window_mean_and_value_at():
    assert window_mean("population", 8, 9)(SERIES) == 391.5
    assert value_at("population", 0)(SERIES) == 400


def test_ratio_of_windows():
    assert ratio_of_windows("population", (8, 9), (0, 1))(SERIES) == 391.5 / 399.5


def test_seasonal_amplitude():
    s = [{"t": t, "x": 1.0 if t < 5 else 0.0, "summer_north": float(t < 5)} for t in range(10)]
    assert seasonal_amplitude("x", start=0, gamma=5, settle=0)(s) == 1.0


def test_seasonal_amplitude_skips_settling_periods():
    s = [{"t": t, "x": 1.0 if t % 5 >= 2 else 9.0, "summer_north": float(t < 5)} for t in range(10)]
    s = [dict(r, x=(r["x"] if r["summer_north"] else r["x"] - 1.0)) for r in s]
    assert seasonal_amplitude("x", start=0, gamma=5, settle=2)(s) == 1.0


def test_evaluate_statuses():
    t = Target("X", "pop", 395, 390, 400, value_at("population", 5), "test")
    assert evaluate(t, [SERIES]).status == "pass"
    t2 = Target("X", "pop", 380, 380, 390, value_at("population", 5), "test")
    assert evaluate(t2, [SERIES]).status == "near"  # 395 within 390 + 5
    t3 = Target("X", "pop", 300, 300, 310, value_at("population", 5), "test")
    assert evaluate(t3, [SERIES]).status == "fail"


def const(value):
    return [{"t": 0, "population": value}]


def test_near_margin_capped_at_a_quarter_of_the_bound():
    def status(low, high, value):
        return evaluate(Target("X", "pop", None, low, high, value_at("population", 0), "t"), [const(value)]).status

    assert status(0.15, 1.0, 0.05) == "fail"  # half-width margin 0.425 would reach below 0; 25% of 0.15 stops at 0.1125
    assert status(0.15, 1.0, 0.12) == "near"
    assert status(-60, -10, -4.65) == "fail"  # beyond the high bound: margin 25% of 10, not half of 50
    assert status(-60, -10, -8.0) == "near"
    assert status(0, 0.5, 0.55) == "near"  # 0.5 + min(0.25, 0.125)
    assert status(0, 0.5, 0.7) == "fail"
    assert status(0, 0.5, -0.01) == "fail"  # a bound of 0 leaves no margin below it
    assert status(328.5, 401.5, 299.4) == "near"  # wide relative room: the half-width margin (36.5) still applies


def test_evaluate_spread_across_seeds():
    other = [dict(r, population=r["population"] + 10) for r in SERIES]
    r = evaluate(Target("X", "pop", 400, 390, 410, value_at("population", 0), "t"), [SERIES, other])
    assert (r.observed_mean, r.observed_min, r.observed_max) == (405, 400, 410)


def test_all_nan_statistic_fails():
    s = [{"t": 0, "population": math.nan}]
    assert evaluate(Target("X", "pop", 1, 0, 2, value_at("population", 0), "t"), [s]).status == "fail"


def test_report_lists_every_target(tmp_path):
    t = Target("X", "pop", 395, 390, 400, value_at("population", 5), "test", proxy=True)
    write_report([evaluate(t, [SERIES])], tmp_path / "R.md")
    text = (tmp_path / "R.md").read_text(encoding="utf-8")
    assert "pop" in text and "pass" in text and "(proxy)" in text


def test_ratio_of_windows_nan_when_reference_extinct():  # Review Focus 1 at the report layer
    s = [{"t": 0, "population": 0.0}, {"t": 1, "population": 0.0}]
    assert math.isnan(ratio_of_windows("population", (1, 1), (0, 0))(s))


def test_nan_seed_downgrades_pass_and_is_counted():
    dead = [{"t": 5, "population": math.nan}]
    t = Target("X", "pop", 395, 390, 400, value_at("population", 5), "test")
    r = evaluate(t, [SERIES, dead])
    assert (r.status, r.n_valid, r.n_runs) == ("near", 1, 2)
    assert evaluate(t, [SERIES, dead, dead]).status == "fail"  # fewer than half valid


def test_report_shows_valid_seed_count(tmp_path):
    t = Target("X", "pop", 395, 390, 400, value_at("population", 5), "test")
    write_report([evaluate(t, [SERIES, [{"t": 5, "population": math.nan}]])], tmp_path / "R.md")
    assert "1/2" in (tmp_path / "R.md").read_text(encoding="utf-8")


from replication.targets import (  # noqa: E402  (Chapter III helpers)
    both_persist,
    centroid_shift,
    dominant_period,
    peak_spacing,
    extinct_by,
    relative_std,
    tribal_outcome,
    window_max,
    window_min,
    window_range,
)


def sine(period, n=2000, amp=300.0, base=600.0):
    return [{"t": t, "population": base + amp * math.sin(2 * math.pi * t / period)} for t in range(n)]


def test_dominant_period_finds_cycle():
    assert abs(dominant_period("population", 0, 1999)(sine(125)) - 125) <= 1
    assert abs(dominant_period("population", 0, 1999)(sine(200)) - 200) <= 1


def test_dominant_period_flat_or_extinct_is_nan():  # Review Focus 5
    flat = [{"t": t, "population": 0.0} for t in range(100)]
    assert math.isnan(dominant_period("population", 0, 99)(flat))
    rising = [{"t": t, "population": float(t)} for t in range(100)]
    assert math.isnan(dominant_period("population", 0, 99)(rising))
    assert math.isnan(dominant_period("population", 0, 99)([]))


def knots(points, n):
    """Piecewise-linear population through (t, value) points."""
    ts, vs = zip(*points)
    return [{"t": t, "population": float(v)} for t, v in zip(range(n), np.interp(range(n), ts, vs))]


def test_peak_spacing_finds_cycle():
    assert abs(peak_spacing("population", 0, 1999)(sine(125)) - 125) <= 1
    assert abs(peak_spacing("population", 0, 1999)(sine(200)) - 200) <= 1


def test_peak_spacing_is_the_median_interval():
    # symmetric peaks (rise and fall 50 periods each), so smoothing doesn't shift them
    s = knots([(0, 300), (50, 300), (100, 900), (150, 300), (200, 300), (250, 900), (300, 300), (400, 300),
               (450, 900), (500, 300), (550, 300), (600, 900), (650, 300), (700, 300)], 701)
    assert peak_spacing("population", 0, 700)(s) == pytest.approx(150, abs=1)  # intervals 150, 200, 150


def test_peak_spacing_ignores_a_peak_at_the_window_edge():
    s = knots([(0, 900), (50, 300), (100, 300), (150, 900), (200, 300), (350, 300), (400, 900), (450, 300),
               (460, 300)], 461)
    assert peak_spacing("population", 0, 460)(s) == pytest.approx(250, abs=1)  # counting t=0 would give ≈200


def test_peak_spacing_nan_without_oscillation():
    flat = [{"t": t, "population": 0.0} for t in range(100)]
    assert math.isnan(peak_spacing("population", 0, 99)(flat))
    rising = [{"t": t, "population": float(t)} for t in range(100)]
    assert math.isnan(peak_spacing("population", 0, 99)(rising))
    assert math.isnan(peak_spacing("population", 0, 99)([]))
    assert math.isnan(peak_spacing("population", 0, 1999)(sine(125, amp=15.0)))  # swings below 40 are noise


def test_window_extremes_and_relative_std():
    s = sine(100, n=400)
    assert window_min("population", 0, 399)(s) == pytest.approx(300, abs=1)
    assert window_max("population", 0, 399)(s) == pytest.approx(900, abs=1)
    assert window_range("population", 0, 399)(s) == pytest.approx(600, abs=1)
    assert relative_std("population", 0, 399)(s) == pytest.approx(300 / math.sqrt(2) / 600, rel=0.02)
    assert math.isnan(window_min("population", 500, 600)(s))


def outcome_row(sb, sr, nb, nr):
    return [{"t": 0, "sw_blue": sb, "sw_red": sr, "ne_blue": nb, "ne_red": nr, "n_blue": sb + nb, "n_red": sr + nr}]


def test_tribal_outcomes():
    assert tribal_outcome(0, "opposite")(outcome_row(100, 0, 0, 90)) == 1.0
    assert tribal_outcome(0, "opposite")(outcome_row(100, 0, 90, 0)) == 0.0
    assert tribal_outcome(0, "blue_both")(outcome_row(100, 2, 90, 0)) == 1.0
    assert tribal_outcome(0, "red_both")(outcome_row(100, 2, 90, 0)) == 0.0
    assert tribal_outcome(0, "three_patterns")(outcome_row(0, 50, 0, 40)) == 1.0
    assert tribal_outcome(0, "three_patterns")(outcome_row(60, 40, 50, 50)) == 0.0
    assert tribal_outcome(0, "pure_sides")(outcome_row(100, 0, 90, 0)) == 1.0
    assert tribal_outcome(0, "pure_sides")(outcome_row(60, 40, 90, 0)) == 0.0
    assert tribal_outcome(0, "opposite")(outcome_row(0, 0, 0, 0)) == 0.0  # extinct: no pattern


def test_both_persist_and_extinct_by():
    assert both_persist(0, 0.2)(outcome_row(30, 0, 0, 100)) == 1.0
    assert both_persist(0, 0.3)(outcome_row(30, 0, 0, 100)) == 0.0
    assert both_persist(0, 0.1)(outcome_row(0, 0, 0, 0)) == 0.0
    assert extinct_by(1)([{"t": 0, "population": 5.0}, {"t": 1, "population": 0.0}]) == 1.0
    assert extinct_by(1)([{"t": 0, "population": 5.0}, {"t": 1, "population": 2.0}]) == 0.0


def test_centroid_shift():
    s = [{"t": 0, "blue_xy": 20.0}, {"t": 50, "blue_xy": 35.0}]
    assert centroid_shift("blue_xy", 0, 50)(s) == 15.0


from replication.targets import combat_outcome, first_time_pure  # noqa: E402


def counts(rows, mixed=False):
    """Tribe counts per t; segregated (Blue SW, Red NE) unless mixed (half of each on each side)."""
    if mixed:
        return [{"t": t, "n_blue": b, "n_red": r, "sw_blue": b / 2, "sw_red": r / 2, "ne_blue": b / 2,
                 "ne_red": r / 2} for t, (b, r) in rows]
    return [{"t": t, "n_blue": b, "n_red": r, "sw_blue": b, "sw_red": 0.0, "ne_blue": 0.0, "ne_red": r}
            for t, (b, r) in rows]


def test_combat_outcome_recognises_frozen_coexistence():  # p.83 third pattern
    frozen = counts([(500, (2.0, 131.0)), (750, (2.0, 131.0)), (1000, (2.0, 131.0))])
    assert combat_outcome(750, 1000)(counts([(750, (2.0, 131.0)), (1000, (2.0, 131.0))], mixed=True)) == 1.0
    assert combat_outcome(750, 1000)(frozen) == 1.0
    churning = counts([(500, (40.0, 90.0)), (750, (30.0, 95.0)), (1000, (25.0, 99.0))], mixed=True)
    assert combat_outcome(750, 1000)(churning) == 0.0
    one_left = counts([(750, (5.0, 60.0)), (1000, (0.0, 140.0))])
    assert combat_outcome(750, 1000)(one_left) == 1.0


def test_first_time_pure():
    def row(t, sb, sr, nb, nr):
        return {"t": t, "sw_blue": sb, "sw_red": sr, "ne_blue": nb, "ne_red": nr}
    s = [row(0, 50, 50, 40, 40), row(10, 100, 0, 80, 1), row(20, 100, 0, 0, 81)]
    assert first_time_pure()(s) == 20.0
    assert math.isnan(first_time_pure()(s[:2]))


def test_baseline_target_is_a_paired_ratio():
    t = Target("X", "ratio", None, 0.9, 1.1, window_mean("population", 0, 0), "src", baseline="Y")
    runs = [[{"t": 0, "population": 10.0}], [{"t": 0, "population": 30.0}]]
    base = runs + [[{"t": 0, "population": 5.0}]]  # extra baseline seed is ignored
    r = evaluate(t, runs, base)
    assert (r.observed_mean, r.n_runs, r.status) == (1.0, 2, "pass")
    assert evaluate(t, runs, [[{"t": 0, "population": 0.0}]] * 2).status == "fail"  # nan per seed


def test_baseline_target_without_baseline_runs_is_an_error():  # final review: not a silent fail
    t = Target("X", "ratio", None, 0.9, 1.1, window_mean("population", 0, 0), "src", baseline="Y")
    with pytest.raises(ValueError, match="needs Y"):
        evaluate(t, [[{"t": 0, "population": 10.0}]])
