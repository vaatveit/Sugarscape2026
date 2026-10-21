import math

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
