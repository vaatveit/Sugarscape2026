import numpy as np
import pytest

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.trade import bargain
from sugarscape.rules.welfare import mrs, welfare


def trader(m, x, y, sugar, spice, m1=1, m2=1, tags=None):
    a = put_agent(m, x, y, sugar=sugar)
    a.spice, a.metabolism, a.spice_metabolism = spice, m1, m2
    a.tags = tags
    return a


def market(**kw):
    return tiny_model(np.ones((5, 5), dtype=int), spice=True, trade=True, **kw)


def test_edgeworth_example_equal_metabolisms():  # Fig IV-2 endowments; metabolisms 1/1 are ours
    m = market()
    A = trader(m, 1, 1, 5.0, 8.0)
    B = trader(m, 1, 2, 15.0, 2.0)
    deals = bargain(m, A, B)
    assert len(deals) == 2 and all(d.spice == 1.0 and d.price < 1 for d in deals)
    assert A.spice == 6.0 and A.sugar == pytest.approx(9.2577, abs=1e-3)
    assert A.sugar + B.sugar == pytest.approx(20.0) and A.spice + B.spice == 10.0


def test_price_above_one_moves_p_spice_per_sugar():  # p.104
    m = market()
    A = trader(m, 1, 1, 2.0, 40.0)
    B = trader(m, 1, 2, 40.0, 10.0)
    d = bargain(m, A, B)[0]
    assert d.price == pytest.approx(5 ** 0.5) and d.sugar == 1.0 and d.spice == pytest.approx(d.price)


def test_no_trade_when_mrs_equal_or_degenerate():  # Review Focus 1
    m = market(tag_length=3, cultural_preferences=True, culture=True)
    A = trader(m, 1, 1, 10.0, 10.0, tags=[0, 1, 0])
    B = trader(m, 1, 2, 10.0, 10.0, tags=[0, 1, 0])
    assert bargain(m, A, B) == []
    C = trader(m, 1, 0, 10.0, 10.0, tags=[0, 0, 0])  # f = 1: MRS infinite
    assert bargain(m, A, C) == [] and A.sugar == 10.0
    D = trader(m, 2, 1, 0.0, 10.0, tags=[0, 1, 1])  # no sugar
    assert bargain(m, A, D) == []


def test_random_pairs_conserve_and_improve():  # Review Focus 2
    rng = np.random.default_rng(7)
    m = market()
    a = trader(m, 1, 1, 1.0, 1.0)
    b = trader(m, 1, 2, 1.0, 1.0)
    for _ in range(500):
        a.sugar, a.spice, b.sugar, b.spice = (float(v) for v in rng.uniform(1, 100, 4))
        a.metabolism, a.spice_metabolism, b.metabolism, b.spice_metabolism = (int(v) for v in rng.integers(1, 6, 4))
        totals = (a.sugar + b.sugar, a.spice + b.spice)
        before = (welfare(a, a.sugar, a.spice), welfare(b, b.sugar, b.spice))
        order = mrs(a) > mrs(b)
        deals = bargain(m, a, b)
        assert (a.sugar + b.sugar, a.spice + b.spice) == pytest.approx(totals)
        if deals:
            assert welfare(a, a.sugar, a.spice) > before[0] and welfare(b, b.sugar, b.spice) > before[1]
            assert (mrs(a) > mrs(b)) == order or mrs(a) == mrs(b)
        assert min(a.sugar, a.spice, b.sugar, b.spice) > 0


def test_trade_runs_in_the_turn_and_logs():
    m = Model(Config(spice=True, trade=True, initial_population=200, metabolism=(1, 5), vision=(1, 5),
                     endowment=(25, 50), seed=3))
    total = 0
    for _ in range(20):
        m.step()
        total += len(m.trade_log)
        assert all(d.sugar > 0 and d.spice > 0 and d.price > 0 for d in m.trade_log)
    assert total > 0
    assert all(a.sugar > 0 and a.spice > 0 for a in m.agents)


def test_no_trade_log_without_trade():
    m = Model(Config(spice=True, initial_population=50))
    m.step()
    assert m.trade_log == []
