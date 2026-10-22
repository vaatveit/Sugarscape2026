import pytest

from sugarscape.variants.schelling import SchellingConfig, SchellingModel, schelling_metrics


def world(w=5, h=5, **kw):
    return SchellingModel(SchellingConfig(width=w, height=h, population=0, **kw))


def test_like_share_is_von_neumann_and_excludes_self():  # p.166; Review Focus 1
    m = world()
    a = m.place(2, 2, "red", 0.5)
    m.place(2, 3, "red", 0.5)
    m.place(3, 2, "blue", 0.5)
    m.place(3, 3, "red", 0.5)  # diagonal: not a neighbor
    m.place(1, 1, "blue", 0.5)
    assert m.like_share(a, 2, 2) == 0.5
    assert m.like_share(a, 2, 1) == 0.0  # (2,1)'s neighbors: a itself (excluded) and blue (1,1)


def test_agent_without_neighbors_is_satisfied():  # our call; Review Focus 2
    m = world()
    a = m.place(0, 0, "red", 1.0)
    assert m.like_share(a, 0, 0) is None and m.satisfied(a)


def test_dissatisfied_agent_moves_to_a_random_acceptable_site():  # p.166: random, not nearest
    seen = set()
    for seed in range(20):
        m = world(7, 7, seed=seed)
        a = m.place(3, 3, "red", 1.0)
        for x, y in ((3, 4), (4, 3), (3, 2), (2, 3)):
            m.place(x, y, "blue", 0.0)
        m.step()
        assert (a.x, a.y) != (3, 3) and m.satisfied(a) and a.moved
        seen.add((a.x, a.y))
    assert len(seen) > 3


def test_no_acceptable_site_means_staying_put():  # Review Focus 2
    m = world(3, 3)
    a = m.place(1, 1, "red", 1.0)
    for x, y in ((0, 1), (2, 1), (1, 0), (1, 2), (2, 0), (0, 2), (2, 2)):
        m.place(x, y, "blue", 0.0)
    assert m.acceptable_sites(a) == []  # the one empty site, (0,0), has blue neighbors
    m.step()
    assert (a.x, a.y) == (1, 1) and not m.satisfied(a)


def test_equilibrium_at_25_percent():  # Animation VI-4
    m = SchellingModel(SchellingConfig(seed=0))
    start = schelling_metrics(m)
    assert start["population"] == 2000 and 900 <= start["n_red"] <= 1100
    m.run(60)
    end = schelling_metrics(m)
    assert end["fraction_satisfied"] == 1.0 and end["moved"] == 0.0
    assert end["like_fraction"] > start["like_fraction"]


def test_lifetimes_replace_the_departed():  # p.166 fn 11
    m = SchellingModel(SchellingConfig(width=10, height=10, population=60, max_age=(3, 5),
                                       preference=(0.25, 0.5), seed=1))
    m.run(12)
    assert len(m.agents) == 60 and all(m.agent_at(a.x, a.y) is a for a in m.agents)
    assert all(a.age < a.max_age and 0.25 <= a.preference <= 0.5 for a in m.agents)


@pytest.mark.parametrize("bad", [{"population": 2501}, {"preference": (0.5, 0.25)},
                                 {"preference": (0.0, 1.5)}, {"max_age": (0, 5)}, {"max_age": (9, 5)}])
def test_invalid_schelling_config(bad):
    with pytest.raises(ValueError):
        SchellingConfig(**bad)
