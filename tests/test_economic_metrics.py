import math

import pytest

from experiments.run import run_experiment
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.credit import Loan
from sugarscape.rules.trade import Exchange
from sugarscape.stats import economic_metrics, standard_metrics

KEYS = {"mean_spice", "trades", "mean_price", "mean_log_price", "price_sd", "sugar_traded", "spice_traded",
        "mean_foresight", "n_loans", "n_lenders", "n_borrowers", "n_both", "credit_depth"}


def test_no_trades_gives_nan():  # Review Focus 3
    out = economic_metrics(Model(Config(seed=1)))
    assert set(out) == KEYS
    assert out["trades"] == 0.0 and math.isnan(out["mean_price"]) and math.isnan(out["price_sd"])
    assert math.isnan(out["mean_log_price"]) and out["credit_depth"] == 0.0


def test_price_statistics():
    m = Model(Config(initial_population=0, spice=True))
    m.trade_log = [Exchange(2.0, 1.0, 2.0, None, None), Exchange(0.5, 2.0, 1.0, None, None)]
    out = economic_metrics(m)
    assert out["mean_price"] == pytest.approx(1.0) and out["mean_log_price"] == pytest.approx(0.0)
    assert out["price_sd"] == pytest.approx(math.log(2)) and out["trades"] == 2.0
    assert (out["sugar_traded"], out["spice_traded"]) == (3.0, 3.0)
    m.trade_log = m.trade_log[:1]
    assert economic_metrics(m)["price_sd"] == 0.0


def test_credit_structure():
    m = Model(Config(initial_population=0, sex=True, credit=(10, 10.0)))
    a, b, c = (m.new_agent(i, 0, 1, 1, 10.0) for i in range(3))
    m.loans = [Loan(a, b, 1.0, 2.0, 10), Loan(b, c, 1.0, 2.0, 10)]
    out = economic_metrics(m)
    assert (out["n_loans"], out["n_lenders"], out["n_borrowers"], out["n_both"], out["credit_depth"]) == (2, 2, 2, 1, 2)


def test_credit_depth_survives_cycles():
    m = Model(Config(initial_population=0, sex=True, credit=(10, 10.0)))
    a, b = (m.new_agent(i, 0, 1, 1, 10.0) for i in range(2))
    m.loans = [Loan(a, b, 1.0, 2.0, 10), Loan(b, a, 1.0, 2.0, 10)]
    assert economic_metrics(m)["credit_depth"] >= 1.0


def test_gini_uses_total_wealth():
    m = Model(Config(initial_population=0, spice=True))
    a = m.new_agent(0, 0, 1, 1, 10.0)
    a.spice = 0.0
    b = m.new_agent(1, 0, 1, 1, 0.0001)
    b.spice = 10.0
    assert standard_metrics(m)["gini"] == pytest.approx(0.0, abs=1e-4)


def test_values_are_plain_floats_and_recorded(tmp_path):
    m = Model(Config(spice=True, trade=True, foresight=(0, 10), initial_population=100, seed=1))
    m.step()
    assert all(type(v) is float for v in economic_metrics(m).values())
    row = run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path)[0][0]
    assert "price_sd" in row and "blue_fraction" in row and "population" in row
