"""The per-period metrics CSV: columns, rows, and agreement with Python's formulas on dumped states."""

import math

import numpy as np
import pytest

from gpu import read_rows, run_gpu
from bridge.paths import SUGARSCAPE_ROOT  # noqa: F401  (puts the Python project on sys.path)
from experiments.run import _read_csv
from replication.targets import window_mean
from sugarscape.stats import gini, safe_mean

HEADER = ["t", "population", "mean_vision", "mean_metabolism", "mean_sugar", "gini", "mean_neighbors", "moved",
          "ne_fraction", "on_peak_fraction", "north_frac_high_vision", "north_frac_low_vision", "summer_north"]


def _run(exe, tmp_path, cfg=None, steps=10, extra=(), **kwargs):
    out = tmp_path / "metrics.csv"
    dump = run_gpu(exe, tmp_path, cfg, steps=steps, extra_args=("--out", out, *extra), **kwargs)
    assert dump.returncode == 0, dump.stderr
    return dump, out


def test_columns_and_rows(exe, tmp_path):
    _, out = _run(exe, tmp_path)
    assert out.read_text().splitlines()[0].split(",") == HEADER
    assert [r["t"] for r in read_rows(out)] == list(range(11))


def test_metrics_every(exe, tmp_path):
    _, out = _run(exe, tmp_path, steps=12, extra=("--metrics-every", "5"))
    assert [r["t"] for r in read_rows(out)] == [0, 5, 10]


def _fraction(flags):
    flags = list(flags)
    return sum(flags) / len(flags) if flags else math.nan


def _expected(dump, t, width=50, height=50, gamma=None):
    agents = dump.agents
    high = [a for a in agents if a["vision"] >= 5]
    low = [a for a in agents if a["vision"] <= 2]
    return {
        "population": float(len(agents)),
        "mean_vision": safe_mean(a["vision"] for a in agents),
        "mean_metabolism": safe_mean(a["metabolism"] for a in agents),
        "mean_sugar": safe_mean(a["sugar"] for a in agents),
        "gini": gini([a["sugar"] for a in agents]),
        "mean_neighbors": safe_mean(a["neighbors"] for a in agents),
        "moved": float(sum(a["moved"] for a in agents)),
        "ne_fraction": _fraction(a["x"] >= width // 2 and a["y"] >= height // 2 for a in agents),
        "on_peak_fraction": _fraction(dump.landscape[(a["x"], a["y"])]["capacity"] >= 3 for a in agents),
        "north_frac_high_vision": _fraction(a["y"] >= height // 2 for a in high),
        "north_frac_low_vision": _fraction(a["y"] >= height // 2 for a in low),
        "summer_north": math.nan if gamma is None else (1.0 if t % (2 * gamma) < gamma else 0.0),
    }


def _same(a, b):
    return (math.isnan(a) and math.isnan(b)) or math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-12)


@pytest.mark.parametrize("t", [0, 7])
@pytest.mark.parametrize("name,cfg,gamma", [("II-4", {}, None), ("II-7", {"seasons": "8,50"}, 50)])
def test_metrics_match_dump(exe, tmp_path, name, cfg, gamma, t):
    dump, out = _run(exe, tmp_path, cfg, steps=10, dump_at=t)
    row = next(r for r in read_rows(out) if r["t"] == t)
    for column, value in _expected(dump, t, gamma=gamma).items():
        assert _same(float(row[column]), value), (column, row[column], value)


def test_extinction_rows_are_nan(exe, tmp_path):
    cfg = {"metabolism": "4,4", "endowment": "1,1"}
    _, out = _run(exe, tmp_path, cfg, steps=5, capacity=np.zeros((50, 50), dtype=int))
    rows = [r for r in read_rows(out) if r["t"] >= 1]
    assert len(rows) == 5
    for row in rows:
        assert row["population"] == 0 and row["moved"] == 0
        for column in HEADER[2:]:
            if column != "moved":
                assert math.isnan(row[column]), (row["t"], column, row[column])


def test_csv_reads_back(exe, tmp_path):
    _, out = _run(exe, tmp_path)
    series = _read_csv(out)
    assert all(isinstance(v, (int, float)) for row in series for v in row.values())
    assert math.isfinite(window_mean("population", 0, 10)(series))


def test_csv_same_with_and_without_timing(exe, tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    _, plain = _run(exe, tmp_path / "a", steps=15)
    _, timed = _run(exe, tmp_path / "b", steps=15, extra=("--timing", tmp_path / "b" / "t.json"))
    assert plain.read_bytes() == timed.read_bytes()


def test_metrics_after_extinction(exe, tmp_path):
    # A sugarless world: everyone starves in period 1 (endowment 1, metabolism 1, no replacement); rows continue
    # with population 0.
    _, out = _run(exe, tmp_path, {"endowment": "1,1", "metabolism": "1,1"}, steps=4,
                  capacity=np.zeros((50, 50), dtype=int))
    rows = read_rows(out)
    assert [r["t"] for r in rows] == list(range(5))
    assert rows[-1]["population"] == 0 and math.isnan(rows[-1]["mean_vision"]) and math.isnan(rows[-1]["gini"])
