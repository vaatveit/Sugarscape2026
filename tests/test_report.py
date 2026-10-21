import math

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
