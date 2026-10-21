import math

import numpy as np
import pytest

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.stats import gini, histogram, lorenz, safe_mean, standard_metrics


def test_gini_known_values():
    assert gini([5, 5, 5, 5]) == 0.0
    assert gini([0, 0, 0, 1]) == pytest.approx(0.75)
    assert gini(np.arange(5, 26)) == pytest.approx(20 / 90, abs=0.02)  # U[5,25] ≈ 0.23 (p.37)


def test_lorenz_endpoints_and_convexity():
    x, y = lorenz([1, 2, 3, 4])
    assert (x[0], y[0], x[-1], y[-1]) == (0, 0, 1, 1)
    assert np.all(y <= x + 1e-12)


def test_histogram_has_requested_bins():
    counts, edges = histogram(list(range(100)), bins=10)
    assert len(counts) == 10 and len(edges) == 11 and counts.sum() == 100


def test_empty_population_gives_nan_not_error():
    assert math.isnan(gini([])) and math.isnan(safe_mean([]))
    m = tiny_model(np.ones((3, 3), dtype=int))
    out = standard_metrics(m)
    assert out["population"] == 0 and math.isnan(out["gini"])


def test_standard_metrics_keys():
    out = standard_metrics(Model(Config(seed=2)))
    assert set(out) == {
        "population", "mean_vision", "mean_metabolism", "mean_sugar", "gini",
        "mean_neighbors", "moved", "ne_fraction", "on_peak_fraction",
        "north_frac_high_vision", "north_frac_low_vision", "summer_north",
    }


def test_spatial_fractions():
    m = tiny_model(np.full((6, 6), 3))
    put_agent(m, 4, 4)  # NE quadrant
    put_agent(m, 1, 1)  # SW quadrant
    out = standard_metrics(m)
    assert out["ne_fraction"] == 0.5 and out["on_peak_fraction"] == 1.0
    assert math.isnan(out["summer_north"])  # no seasons configured
