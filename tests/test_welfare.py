import math

import numpy as np
import pytest

from conftest import make_tagged, put_agent, tiny_model
from sugarscape.rules.movement import metabolize, move
from sugarscape.rules.welfare import mrs, welfare


def agent_with(m1, m2, sugar=0.0, spice=0.0, tags=None):
    a = make_tagged(tags or [0])
    a.metabolism, a.spice_metabolism, a.sugar, a.spice = m1, m2, sugar, spice
    return a


def test_appendix_c_preferences_depend_on_wealth():  # App. C, p.189
    a = agent_with(1, 1)
    assert welfare(a, 20 + 3, 50 + 3) > welfare(a, 20 + 2, 50 + 5)  # 23*53 > 22*55
    assert welfare(a, 150 + 3, 250 + 3) < welfare(a, 150 + 2, 250 + 5)  # 153*253 < 152*255


def test_welfare_weights_by_metabolism():  # p.97
    assert welfare(agent_with(3, 1), 16, 1) == pytest.approx(16 ** 0.75 * 1 ** 0.25)


def test_negative_holdings_count_as_zero():
    assert welfare(agent_with(1, 1), -5, 10) == 0.0


def test_mrs_matches_times_to_starvation():  # eq. 3, p.102
    assert mrs(agent_with(2, 1, sugar=10, spice=5)) == pytest.approx((5 / 1) / (10 / 2))


def test_cultural_welfare_extremes():  # eq. 5, p.124
    allzero = agent_with(1, 1, 10, 10, tags=[0, 0, 0])  # f = 1: values sugar only
    assert welfare(allzero, 5, 100, cultural=True) == pytest.approx(5.0)
    assert mrs(allzero, cultural=True) == math.inf  # would give any spice for sugar
    mixed = agent_with(1, 1, 10, 10, tags=[0, 1, 1])  # f = 1/3
    assert mrs(mixed, cultural=True) == pytest.approx((10 / (2 / 3)) / (10 / (1 / 3)))
    assert mrs(mixed) == pytest.approx(1.0)  # non-cultural form ignores tags


def test_moves_toward_scarce_commodity():
    cap = np.zeros((9, 9), dtype=int)
    spice = np.zeros((9, 9), dtype=int)
    cap[4, 6] = 4
    spice[6, 4] = 2  # 4 sugar north vs 2 spice east
    m = tiny_model(cap, spice=True, vision=(1, 3))
    m.landscape.set_spice(spice)
    g = put_agent(m, 4, 4, vision=3)
    g.sugar, g.spice, g.metabolism, g.spice_metabolism = 50.0, 2.0, 1, 1
    move(m, g)
    assert (g.x, g.y) == (6, 4) and g.spice == 4.0 and m.landscape.spice[6, 4] == 0.0


def test_dies_of_spice_starvation():  # p.97
    m = tiny_model(np.ones((5, 5), dtype=int), spice=True)
    g = put_agent(m, 2, 2, sugar=100.0)
    g.spice, g.spice_metabolism = 1.0, 2
    metabolize(m, g)
    assert not g.alive


@pytest.mark.parametrize("phi, expected", [(0, (3, 4)), (5, (4, 3))])
def test_foresight_shifts_choice(phi, expected):  # eq. 6, p.129
    # m1=1, m2=3, holdings (20, 20); north site: 4 sugar, east site: 1 spice.
    # Myopic: W(24,20)=20.93 > W(20,21)=20.75 -> north.  phi=5 acts as (15,5): W(19,5)=6.98 < W(15,6)=7.55 -> east.
    cap = np.zeros((9, 9), dtype=int)
    spice = np.zeros((9, 9), dtype=int)
    cap[3, 4] = 4
    spice[4, 3] = 1
    m = tiny_model(cap, spice=True, foresight=(0, 10))
    m.landscape.set_spice(spice)
    g = put_agent(m, 3, 3)
    g.sugar, g.spice, g.metabolism, g.spice_metabolism, g.foresight = 20.0, 20.0, 1, 3, phi
    move(m, g)
    assert (g.x, g.y) == expected


def test_pollution_stops():
    m = tiny_model(np.ones((5, 5), dtype=int), pollution=(1.0, 1.0), pollution_start=0, pollution_stop=5)
    m.t = 5
    g = put_agent(m, 2, 2)
    move(m, g)
    metabolize(m, g)
    assert m.landscape.pollution.sum() == 0.0


def test_spawned_agents_get_spice_and_foresight():
    from sugarscape.config import Config
    from sugarscape.model import Model
    m = Model(Config(spice=True, foresight=(0, 10), initial_population=50, endowment=(25, 50)))
    assert all(25 <= a.spice == a.initial_spice <= 50 and 1 <= a.spice_metabolism <= 5 for a in m.agents)
    assert all(0 <= a.foresight <= 10 for a in m.agents)


def test_pollution_devalues_the_site_not_the_agent():  # p.47: score is the site's sugar / (1 + pollution)
    # A well-off agent should still take a rich, mildly polluted site over an empty clean one:
    # W(50 + 4/2, 50) > W(50, 50). Dividing the agent's whole welfare by 1 + p would reverse this.
    cap = np.zeros((7, 7), dtype=int)
    cap[3, 4] = 4
    m = tiny_model(cap, spice=True, pollution=(1.0, 1.0))
    m.landscape.set_spice(np.zeros((7, 7), dtype=int))
    m.landscape.pollution[3, 4] = 1.0
    g = put_agent(m, 3, 3)
    g.sugar, g.spice, g.metabolism, g.spice_metabolism = 50.0, 50.0, 1, 1
    move(m, g)
    assert (g.x, g.y) == (3, 4)
