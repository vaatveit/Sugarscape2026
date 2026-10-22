import numpy as np

from sugarscape.config import Config
from sugarscape.landscape import Landscape
from sugarscape.model import Model


def test_spice_peaks_northwest_and_southeast():  # Fig IV-1
    m = Model(Config(spice=True, initial_population=0))
    xs, ys = np.nonzero(m.landscape.spice_capacity == 4)
    nw = (xs < 25) & (ys >= 25)
    se = (xs >= 25) & (ys < 25)
    assert nw.any() and se.any() and (nw | se).all()
    assert m.landscape.spice.tolist() == m.landscape.spice_capacity.astype(float).tolist()


def test_no_spice_layer_without_spice():
    m = Model(Config(initial_population=0))
    assert m.landscape.spice_capacity.sum() == 0 and m.landscape.spice.sum() == 0


def test_spice_grows_back_like_sugar():
    ls = Landscape(np.array([[4, 2]]), spice_capacity=np.array([[3, 1]]))
    ls.spice[:] = 0
    ls.growback(1.0)
    assert ls.spice.tolist() == [[1.0, 1.0]]


def test_spice_seasons_follow_sugar():
    ls = Landscape(np.full((1, 2), 4), spice_capacity=np.full((1, 2), 4))
    ls.sugar[:] = 0
    ls.spice[:] = 0
    ls.seasonal_growback(0, alpha=1, beta=8, gamma=50)
    assert ls.spice.tolist() == ls.sugar.tolist()


def test_spice_inherited():
    from conftest import put_agent, tiny_model
    m = tiny_model(np.ones((5, 5), dtype=int), spice=True, inheritance=True)
    p = put_agent(m, 0, 0, sugar=10.0)
    p.spice = 30.0
    k = put_agent(m, 2, 2)
    k.spice = 5.0
    p.children = [k]
    m.die(p)
    assert k.spice == 35.0


def test_replacements_carry_spice():
    m = Model(Config(spice=True, initial_population=30, max_age=(1, 1), replacement=True, endowment=(25, 50)))
    m.step()
    assert len(m.agents) == 30
    assert all(25 <= a.spice <= 50 and 1 <= a.spice_metabolism <= 5 for a in m.agents)
