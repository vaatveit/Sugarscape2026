"""Config.look_stride: along each lattice line, agents look at one random site for each whole stride of vision,
centred on that stride: stretch k is seen at distance s*k + (U{0..s-1} - U{0..s-1}) (docs/xl.md, "Looking").

xl sets 10, so an agent checks as many sites per look as in the regular run, as far away on average as the regular
sites they stand for, and can still land on any site.
"""

from collections import Counter

import numpy as np
import pytest

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.combat import combat_candidates, vulnerable
from sugarscape.rules.movement import candidate_sites, look_distances
from sugarscape.rules.sex import in_sight
from sugarscape.xl import to_xl

LOOKS = 400


@pytest.mark.parametrize("bad", [0, -1, 1.5, True])
def test_look_stride_must_be_a_whole_number_at_least_1(bad):
    with pytest.raises(ValueError):
        Config(look_stride=bad)


def test_vision_bounds_must_be_multiples_of_the_stride():
    with pytest.raises(ValueError):
        Config(width=100, height=100, vision=(5, 20), look_stride=10)
    Config(width=100, height=100, vision=(10, 40), look_stride=10)


def test_vision_plus_the_look_reach_must_stay_under_half_the_grid():
    # The farthest look is vision + stride - 1 sites away; opposite scans must not reach the same site.
    with pytest.raises(ValueError):
        Config(width=21, height=21, vision=(2, 10), look_stride=2)  # reaches 11
    Config(width=21, height=21, vision=(2, 8), look_stride=2)  # reaches 9


def test_default_stride_leaves_repr_alone():
    assert "look_stride" not in repr(Config())


def test_vision_is_drawn_in_whole_strides():
    m = Model(Config(vision=(5, 20), look_stride=5, initial_population=200))
    assert {a.vision for a in m.agents} == {5, 10, 15, 20}


def stride_model(stride=2, vision=4, size=20, **overrides):
    return tiny_model(np.zeros((size, size), dtype=int), vision=(stride, vision), look_stride=stride, **overrides)


def test_stride_1_looks_at_every_site_without_drawing():
    m = tiny_model(np.zeros((20, 20), dtype=int), vision=(1, 4))
    before = m.rng.bit_generator.state
    assert list(look_distances(m, 4)) == [1, 2, 3, 4]
    assert m.rng.bit_generator.state == before  # regular random streams are unchanged


def test_a_stretch_is_seen_at_a_triangular_distance_centred_on_its_stride():
    # Where a random site of the regular cell one stride away lies from a random site of one's own cell.
    s, n = 5, 10000
    m = stride_model(stride=s, vision=s, size=40)
    counts = Counter(d for _ in range(n) for d in look_distances(m, s))
    assert set(counts) == set(range(1, 2 * s))
    for d in range(1, 2 * s):
        expected = n * (s - abs(d - s)) / s**2
        assert abs(counts[d] - expected) < 5 * expected**0.5, d


def test_distances_are_distinct_sorted_and_cover_every_stretch():
    s, vision = 5, 15
    m = stride_model(stride=s, vision=vision, size=40)
    means = []
    for _ in range(3000):
        d = look_distances(m, vision)
        assert d == sorted(set(d)) and 1 <= d[0] and d[-1] <= vision + s - 1 and len(d) <= vision // s
        assert all(any(s * k - (s - 1) <= x <= s * k + (s - 1) for x in d) for k in (1, 2, 3))
        if len(d) == 3:
            means.append(d)
    assert [round(sum(x[i] for x in means) / len(means)) for i in range(3)] == [5, 10, 15]


def test_movement_looks_at_a_site_per_stretch_in_each_direction():
    m = stride_model()
    g = put_agent(m, 10, 10, vision=4)
    seen = Counter()
    for _ in range(LOOKS):
        sites = candidate_sites(m, g)
        dists = [d for _, _, d in sites]
        assert 1 + 4 <= len(sites) <= 1 + 4 * 2 and dists.count(0) == 1
        assert sum(d in (1, 2, 3) for d in dists) >= 4 and sum(d in (3, 4, 5) for d in dists) >= 4
        seen.update(dists)
    assert set(seen) == {0, 1, 2, 3, 4, 5}


def test_partners_in_sight_one_site_per_stretch():
    m = stride_model(stride=2, vision=2)
    g = put_agent(m, 10, 10, vision=2)
    near, far = put_agent(m, 11, 10), put_agent(m, 12, 10)  # the one stretch of the line: seen at 1, 2 or 3
    outcomes = Counter(tuple(a.id for a in in_sight(m, g)) for _ in range(LOOKS))
    assert set(outcomes) == {(near.id,), (far.id,), ()}


def test_partners_in_sight_come_nearest_first_across_directions():
    m = stride_model()
    g = put_agent(m, 10, 10, vision=4)
    east, north = put_agent(m, 13, 10), put_agent(m, 10, 12)  # east is listed first among equals; north is nearer
    both = [found for found in (in_sight(m, g) for _ in range(LOOKS)) if len(found) == 2]
    assert both and all(found == [north, east] for found in both)


def test_combat_looks_at_a_site_per_stretch():
    m = stride_model(combat_alpha=2.0, tag_length=3)
    g = put_agent(m, 10, 10, vision=4)
    seen = Counter()
    for _ in range(LOOKS):
        dists = [c[2] for c in combat_candidates(m, g)]
        assert 1 + 4 <= len(dists) <= 1 + 4 * 2
        seen.update(dists)
    assert set(seen) == {0, 1, 2, 3, 4, 5}


BLUE, RED = [0, 0, 0], [1, 1, 1]  # tribe by tag majority (p.73)


def test_retaliation_is_looked_for_one_site_per_stretch():
    m = stride_model(combat_alpha=2.0, tag_length=3)
    g = put_agent(m, 10, 10, vision=4, sugar=1.0)
    g.tags = BLUE
    rival = put_agent(m, 13, 10, sugar=50.0)  # distance 1 from the site (12, 10): seen in about a quarter of looks
    rival.tags = RED
    outcomes = Counter(vulnerable(m, g, 12, 10, 0.0, None) for _ in range(LOOKS))
    assert set(outcomes) == {True, False}


def test_xl_agents_are_not_held_to_a_coarse_grid():
    # A fixed stride kept every agent on the sites sharing its x mod 10 and y mod 10: 100 separate sub-worlds.
    m = Model(to_xl(Config(initial_population=20, seed=1)))  # 2,000 founders
    start = {a.id: (a.x % 10, a.y % 10) for a in m.agents}
    for _ in range(10):
        m.step()
    kept = sum(start[a.id] == (a.x % 10, a.y % 10) for a in m.agents)
    assert kept < 0.2 * len(m.agents)
