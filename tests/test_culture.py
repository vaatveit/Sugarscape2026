import numpy as np
import pytest

from conftest import make_tagged, put_agent, tiny_model
from sugarscape.rules.culture import closeness, cross_tags, hamming, random_tags, transmit, tribe, update_friends


def test_tribe_majority():
    assert tribe([0, 0, 1]) == "blue" and tribe([1, 1, 0]) == "red"


def test_random_tags_respects_tribe():
    rng = np.random.default_rng(0)
    assert all(tribe(random_tags(rng, 11, "red")) == "red" for _ in range(50))
    assert all(tribe(random_tags(rng, 11, "blue")) == "blue" for _ in range(50))
    assert len(random_tags(rng, 11)) == 11


def test_cross_tags_copies_agreement():  # p.78 Table III-2
    child = cross_tags(np.random.default_rng(0), [0, 1, 0, 1], [0, 1, 1, 0])
    assert child[:2] == [0, 1]
    seen = {tuple(cross_tags(np.random.default_rng(s), [0, 1, 0, 1], [0, 1, 1, 0])[2:]) for s in range(40)}
    assert len(seen) == 4  # coin flips at disagreeing positions


def test_hamming_and_closeness():
    assert hamming([0, 1, 1], [1, 1, 0]) == 2 and closeness([0, 1, 1], [1, 1, 0]) == pytest.approx(1 / 3)


def test_transmit_flips_neighbor_toward_agent():  # p.73
    m = tiny_model(np.ones((5, 5), dtype=int), tag_length=1)
    a = put_agent(m, 2, 2)
    b = put_agent(m, 2, 3)
    a.tags, b.tags = [0], [1]
    transmit(m, a)
    assert b.tags == [0] and a.tags == [0]  # flippee changes, flipper doesn't


def test_transmit_one_position_per_neighbor():
    m = tiny_model(np.ones((5, 5), dtype=int), tag_length=11)
    a = put_agent(m, 2, 2)
    b = put_agent(m, 2, 3)
    a.tags, b.tags = [0] * 11, [1] * 11
    transmit(m, a)
    assert sum(b.tags) == 10


def test_friends_keep_five_closest_and_drop_dead():  # p.79-80; Review Focus 2
    me = make_tagged([0] * 11)
    others = [make_tagged([1] * k + [0] * (11 - k)) for k in (5, 4, 3, 2, 1, 0)]
    update_friends(me, others)
    assert sorted(d for _, d in me.friends) == [0, 1, 2, 3, 4]
    others[5].alive = False
    update_friends(me, [])
    assert sorted(d for _, d in me.friends) == [1, 2, 3, 4]


def test_friends_not_duplicated_or_self():
    me = make_tagged([0] * 3)
    f = make_tagged([0, 0, 1])
    update_friends(me, [f, f, me])
    assert [x for x, _ in me.friends] == [f]
