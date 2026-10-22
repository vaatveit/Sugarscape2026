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
