"""Config.look_stride: agents look at one random site in each stretch of look_stride sites along each lattice line
(docs/xl.md, "Looking").

xl sets 10, so an agent checks as many sites per look as in the regular run, over the same distance, and can still
land on any site.
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


def test_one_distance_from_each_stretch_each_uniform():
    m = stride_model(stride=5, vision=15, size=40)
    looks = [look_distances(m, 15) for _ in range(3000)]
    assert all(len(d) == 3 and 1 <= d[0] <= 5 and 6 <= d[1] <= 10 and 11 <= d[2] <= 15 for d in looks)
    counts = Counter(d[1] for d in looks)
    assert set(counts) == {6, 7, 8, 9, 10} and min(counts.values()) > 3000 / 5 * 0.8


def test_movement_looks_at_one_site_per_stretch_in_each_direction():
    m = stride_model()
    g = put_agent(m, 10, 10, vision=4)
    seen = Counter()
    for _ in range(LOOKS):
        sites = candidate_sites(m, g)
        dists = [d for _, _, d in sites]
        assert len(sites) == 1 + 4 * 2 and dists.count(0) == 1
        assert sum(d in (1, 2) for d in dists) == 4 and sum(d in (3, 4) for d in dists) == 4
        seen.update(dists)
    assert set(seen) == {0, 1, 2, 3, 4}


def test_partners_in_sight_one_site_per_stretch():
    m = stride_model()
    g = put_agent(m, 10, 10, vision=4)
    near, far = put_agent(m, 11, 10), put_agent(m, 12, 10)  # the same stretch of the same line
    outcomes = Counter(tuple(a.id for a in in_sight(m, g)) for _ in range(LOOKS))
    assert set(outcomes) == {(near.id,), (far.id,)}


def test_combat_looks_at_one_site_per_stretch():
    m = stride_model(combat_alpha=2.0, tag_length=3)
    g = put_agent(m, 10, 10, vision=4)
    seen = Counter()
    for _ in range(LOOKS):
        dists = [c[2] for c in combat_candidates(m, g)]
        assert len(dists) == 1 + 4 * 2
        seen.update(dists)
    assert set(seen) == {0, 1, 2, 3, 4}


BLUE, RED = [0, 0, 0], [1, 1, 1]  # tribe by tag majority (p.73)


def test_retaliation_is_looked_for_one_site_per_stretch():
    m = stride_model(combat_alpha=2.0, tag_length=3)
    g = put_agent(m, 10, 10, vision=4, sugar=1.0)
    g.tags = BLUE
    rival = put_agent(m, 13, 10, sugar=50.0)  # distance 1 from the site (12, 10): seen in about half the looks
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
