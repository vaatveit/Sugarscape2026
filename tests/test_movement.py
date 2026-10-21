import numpy as np

from conftest import put_agent, tiny_model
from sugarscape.rules.movement import metabolize, move


def line_model(levels, vision, **overrides):
    """Sugar row at y=1 starting at x=0; zero padding so west/south scans never wrap onto it."""
    n = len(levels) + 2 * vision + 2
    cap = np.zeros((n, n), dtype=int)
    cap[: len(levels), 1] = levels
    return tiny_model(cap, vision=(1, vision), **overrides)


def test_moves_to_max_sugar_within_vision():
    m = line_model([0, 1, 3, 2], vision=3)
    g = put_agent(m, 0, 1, vision=3)
    move(m, g)
    assert (g.x, g.y) == (2, 1) and g.sugar == 13.0 and g.moved
    assert m.landscape.sugar[2, 1] == 0.0


def test_cannot_see_beyond_vision():
    m = line_model([0, 1, 0, 0, 4], vision=2)
    g = put_agent(m, 0, 1, vision=2)
    move(m, g)
    assert g.x == 1


def test_no_diagonal_vision():
    cap = np.zeros((8, 8), dtype=int)
    cap[1, 1] = 4
    cap[0, 3] = 1
    m = tiny_model(cap, vision=(1, 3))
    g = put_agent(m, 0, 0, vision=3)
    move(m, g)
    assert (g.x, g.y) == (0, 3)


def test_skips_occupied_sites():
    m = line_model([0, 4, 2], vision=2)
    put_agent(m, 1, 1)
    g = put_agent(m, 0, 1, vision=2)
    move(m, g)
    assert g.x == 2


def test_nearest_wins_ties():
    m = line_model([0, 0, 3, 0, 3], vision=4)
    g = put_agent(m, 0, 1, vision=4)
    move(m, g)
    assert g.x == 2


def test_equal_distance_ties_are_random_direction():
    seen = set()
    for seed in range(20):
        cap = np.zeros((7, 7), dtype=int)
        cap[4, 3] = cap[2, 3] = 2
        m = tiny_model(cap, vision=(1, 1), seed=seed)
        g = put_agent(m, 3, 3)
        move(m, g)
        seen.add(g.x)
    assert seen == {2, 4}


def test_stays_when_current_site_is_best():
    m = line_model([4, 3], vision=1)
    g = put_agent(m, 0, 1)
    move(m, g)
    assert g.x == 0 and not g.moved and g.sugar == 14.0


def test_vision_wraps_around_torus():
    cap = np.zeros((6, 6), dtype=int)
    cap[5, 1] = 3  # one step west of x=0
    m = tiny_model(cap, vision=(1, 2))
    g = put_agent(m, 0, 1, vision=2)
    move(m, g)
    assert g.x == 5


def test_starves_at_zero():
    m = line_model([0, 0], vision=1)
    g = put_agent(m, 0, 1, metabolism=2, sugar=2.0)
    move(m, g)
    metabolize(m, g)
    assert not g.alive and m.agent_at(0, 1) is None


def test_survives_with_positive_wealth():
    m = line_model([0, 0], vision=1)
    g = put_agent(m, 0, 1, metabolism=2, sugar=2.5)
    metabolize(m, g)
    assert g.alive and g.sugar == 0.5


def test_pollution_formation_and_avoidance():
    m = line_model([2, 3, 0], vision=1, pollution=(1.0, 1.0))
    m.landscape.pollution[1, 1] = 2.0  # score 3/3 = 1 < 2/1 at the current site
    g = put_agent(m, 0, 1, metabolism=1)
    move(m, g)
    metabolize(m, g)
    assert g.x == 0 and m.landscape.pollution[0, 1] == 2.0 + 1.0  # alpha*2 + beta*1


def test_no_pollution_before_start():
    m = line_model([2, 3, 0], vision=1, pollution=(1.0, 1.0), pollution_start=50)
    g = put_agent(m, 0, 1)
    move(m, g)
    metabolize(m, g)
    assert m.landscape.pollution.sum() == 0.0
