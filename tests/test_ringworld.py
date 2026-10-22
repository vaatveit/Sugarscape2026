import pytest

from sugarscape.variants.ringworld import RingConfig, RingModel, groups, ring_metrics


def ring(**kw):
    return RingModel(RingConfig(**{"population": 0, "initial_sugar": (0, 0), "vision": (1, 1), **kw}))


def test_choose_site_looks_counterclockwise_only():  # p.172
    m = ring(sites=20)
    m.sugar[[1, 3, 7, 8, 9]] = (4, 4, 4, 4, 2)  # 1 and 3 are behind the agent
    assert m.choose_site(m.place(5, vision=4)) == 7  # 6..9 in view; nearest maximum


def test_search_wraps_and_skips_occupied():  # Review Focus 3
    m = ring(sites=10)
    m.sugar[[0, 1]] = (3, 4)
    a = m.place(8, vision=3)
    m.place(1, vision=3)
    assert m.choose_site(a) == 0  # 9, 0, 1 in view; 1 is taken


def test_full_view_means_staying():  # p.175; Review Focus 4
    m = ring(sites=10, initial_sugar=(4, 4))
    back = m.place(0, vision=3)
    for p in (1, 2, 3):
        m.place(p, vision=3)
    assert m.choose_site(back) is None
    m.step()
    assert len({a.position for a in m.agents}) == 4  # one agent per site, whatever the order


def test_pair_leapfrogs_and_stays_together():  # p.175 analysis
    m = RingModel(RingConfig(population=2, vision=(10, 10), initial_sugar=(4, 4), placement="block", seed=5))
    travelled = 0
    for _ in range(50):
        m.step()
        a, b = m.agents
        assert (a.position - b.position) % 150 in (1, 149)
        travelled += a.advanced + b.advanced
    assert travelled >= 2 * 95


def test_groups_span_the_seam_and_respect_gap():  # Review Focus 3
    m = ring(sites=20)
    for p in (18, 19, 0, 2, 6, 10, 11):
        m.place(p, vision=5)
    assert sorted(len(g) for g in groups(m, gap=1)) == [1, 2, 4]
    assert sorted(len(g) for g in groups(m, gap=0)) == [1, 1, 2, 3]
    whole = ring(sites=6)
    for p in (0, 2, 4):
        whole.place(p, vision=2)
    assert [len(g) for g in groups(whole, gap=1)] == [3]


def test_ring_metrics():
    m = ring(sites=20)
    for p, v in ((0, 5), (1, 1), (2, 5), (10, 5)):
        m.place(p, vision=v)
    out = ring_metrics(m)
    assert out["n_groups"] == 1.0 and out["largest_group"] == 3.0 and out["mean_group_size"] == 2.0
    assert out["clustered_fraction"] == 0.75 and out["within_vision_bound"] == 0.0  # 3 > vision 1


def test_block_placement_is_one_group():  # Animation VI-9 start
    m = RingModel(RingConfig(placement="block", seed=4))
    assert [len(g) for g in groups(m, gap=0)] == [40] and 15 <= min(a.vision for a in m.agents)


def test_megagroup_of_nearsighted_agents_breaks_up():  # p.175
    m = RingModel(RingConfig(sites=60, population=12, vision=(3, 4), placement="block", seed=2))
    m.run(50)
    assert ring_metrics(m)["largest_group"] < 12


@pytest.mark.parametrize("bad", [{"population": 151}, {"vision": (0, 5)}, {"vision": (20, 150)},
                                 {"initial_sugar": (0, 5)}, {"placement": "spiral"}])
def test_invalid_ring_config(bad):
    with pytest.raises(ValueError):
        RingConfig(**bad)
