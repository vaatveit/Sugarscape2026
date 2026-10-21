import math

import numpy as np
import pytest

from sugarscape.landscape import Landscape


def test_starts_full_with_no_pollution():  # p.21: level starts at capacity
    ls = Landscape(np.array([[4, 2], [0, 1]]))
    assert ls.sugar.tolist() == [[4.0, 2.0], [0.0, 1.0]]
    assert ls.pollution.sum() == 0.0
    assert (ls.width, ls.height) == (2, 2)


def test_wrap_is_toroidal():
    ls = Landscape(np.zeros((5, 4), dtype=int))
    assert ls.wrap(-1, 4) == (4, 0)
    assert ls.wrap(5, -1) == (0, 3)


def test_growback_caps_at_capacity():
    ls = Landscape(np.array([[4, 2]]))
    ls.sugar[:] = [[0.0, 1.5]]
    ls.growback(1.0)
    assert ls.sugar.tolist() == [[1.0, 2.0]]


def test_g_infinity_refills_immediately():
    ls = Landscape(np.array([[4, 3]]))
    ls.sugar[:] = 0
    ls.growback(math.inf)
    assert ls.sugar.tolist() == [[4.0, 3.0]]


def test_seasons_flip_every_gamma():
    ls = Landscape(np.zeros((2, 2), dtype=int))
    assert ls.is_summer_north(0, 50) and ls.is_summer_north(49, 50)
    assert not ls.is_summer_north(50, 50) and ls.is_summer_north(100, 50)


def test_winter_grows_alpha_every_beta_periods():
    cap = np.full((1, 2), 4)  # y=0 south, y=1 north
    ls = Landscape(cap)
    ls.sugar[:] = 0
    for t in range(8):  # t=0..7, north summer
        ls.seasonal_growback(t, alpha=1, beta=8, gamma=50, winter="pulse")
    assert ls.sugar[0, 1] == 4.0  # north: +1 per period, capped
    assert ls.sugar[0, 0] == 1.0  # south: +1 only at t=0


def test_diffusion_averages_von_neumann_neighbors_on_torus():
    ls = Landscape(np.zeros((3, 3), dtype=int))
    ls.pollution[1, 1] = 4.0
    ls.diffuse()
    assert ls.pollution[1, 1] == 0.0
    assert ls.pollution[0, 1] == ls.pollution[1, 0] == 1.0
    assert ls.pollution.sum() == pytest.approx(4.0)


def test_winter_fractional_grows_alpha_over_beta_each_period():  # design: fractional winter
    ls = Landscape(np.full((1, 2), 4))
    ls.sugar[:] = 0
    ls.seasonal_growback(0, alpha=1, beta=8, gamma=50)
    assert ls.sugar[0, 0] == 0.125 and ls.sugar[0, 1] == 1.0
