import math

import pytest

from experiments.run import run_experiment
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.stats import disease_metrics


def test_disease_statistics():
    m = Model(Config(initial_population=0, disease_list=3))
    for i, ds in enumerate(([(1,)], [(1,), (0, 1)], [])):
        a = m.new_agent(i, 0, 1, 1, 10.0)
        a.diseases = list(ds)
    out = disease_metrics(m)
    assert out["mean_diseases"] == 1.0 and out["sd_diseases"] == pytest.approx((2 / 3) ** 0.5)
    assert out["fraction_sick"] == pytest.approx(2 / 3) and out["diseases_circulating"] == 2.0
    assert all(type(v) is float for v in out.values())


def test_empty_population_is_nan_not_error():  # Review Focus 5
    out = disease_metrics(Model(Config(initial_population=0)))
    assert math.isnan(out["mean_diseases"]) and math.isnan(out["fraction_sick"])
    assert out["new_infections"] == 0.0 and out["diseases_circulating"] == 0.0


def test_recorded_by_runner(tmp_path):
    row = run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path)[0][0]
    assert "mean_diseases" in row and "price_sd" in row
