import numpy as np
import pytest

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model


def test_random_placement_is_distinct_and_seeded():
    a, b = Model(Config(seed=7)), Model(Config(seed=7))
    pos = [(g.x, g.y) for g in a.agents]
    assert len(pos) == 400 == len(set(pos))
    assert pos == [(g.x, g.y) for g in b.agents]
    assert all(a.agent_at(g.x, g.y) is g for g in a.agents)


def test_genetics_within_ranges():
    m = Model(Config(seed=1))
    assert {g.vision for g in m.agents} <= set(range(1, 7))
    assert {g.metabolism for g in m.agents} <= set(range(1, 5))
    assert all(5 <= g.sugar <= 25 and g.sugar == g.initial_sugar for g in m.agents)


def test_block_placement_inside_block():
    m = Model(Config(placement="block", block=(0, 0, 20, 20), initial_population=300))
    assert all(g.x < 20 and g.y < 20 for g in m.agents)


def test_overfull_placement_raises():
    with pytest.raises(ValueError):
        Model(Config(placement="block", block=(0, 0, 10, 10), initial_population=101))


def test_random_empty_site_none_when_full():
    m = tiny_model(np.ones((3, 3), dtype=int))
    for x in range(3):
        for y in range(3):
            put_agent(m, x, y)
    assert m.random_empty_site() is None


def test_old_age_death_and_replacement_keep_population_constant():
    m = Model(Config(initial_population=50, max_age=(1, 1), replacement=True, seed=3))
    m.step()
    assert len(m.agents) == 50 and all(g.age == 0 for g in m.agents)
    assert m.deaths_this_step == 50


def test_kill_frees_site():
    m = tiny_model(np.ones((3, 3), dtype=int))
    g = put_agent(m, 1, 1)
    m.kill(g)
    assert m.agent_at(1, 1) is None and not g.alive and g not in m.agents


def test_move_agent_updates_occupancy():
    m = tiny_model(np.ones((3, 3), dtype=int))
    g = put_agent(m, 0, 0)
    m.move_agent(g, 2, 1)
    assert (g.x, g.y) == (2, 1) and m.agent_at(2, 1) is g and m.agent_at(0, 0) is None


def test_run_calls_observer_before_and_after_each_step():
    seen = []
    tiny_model(np.ones((3, 3), dtype=int)).run(3, observer=lambda m: seen.append(m.t))
    assert seen == [0, 1, 2, 3]


def test_step_regrows_sites_at_end_of_period():
    m = tiny_model(np.full((3, 3), 4))
    m.landscape.sugar[:] = 0
    m.step()
    assert m.landscape.sugar.max() == 1.0 and m.t == 1


@pytest.mark.parametrize("mode, expected", [("fractional", 0.25), ("pulse", 1.0)])
def test_model_uses_configured_winter_mode(mode, expected):
    m = tiny_model(np.full((3, 4), 4), seasons=(8, 50), winter_growback=mode)
    m.landscape.sugar[:] = 0
    m.step(); m.step()                   # t=0,1: north summer, south winter
    assert m.landscape.sugar[0, 0] == expected and m.landscape.sugar[0, 3] == 2.0


def test_chapter2_stream_unchanged_by_chapter3_fields():
    from experiments.run import run_seed
    s = run_seed("II-4", 0)
    assert (s[100]["population"], s[100]["mean_vision"], s[500]["gini"]) == (
        246.0, 3.6341463414634148, 0.3975282613501283)


def test_chapter3_stream_unchanged_by_chapter4_fields():
    from experiments.registry import EXPERIMENTS
    from sugarscape.stats import standard_metrics
    m = Model(EXPERIMENTS["III-1"].config)
    m.run(200)
    o = standard_metrics(m)
    assert (o["population"], o["mean_vision"], o["gini"]) == (374.0, 4.708556149732621, 0.16341810946378743)


def test_chapter4_stream_unchanged_by_chapter5_fields():
    from experiments.registry import EXPERIMENTS
    from sugarscape.stats import economic_metrics, standard_metrics
    m = Model(EXPERIMENTS["IV-3"].config)
    m.run(100)
    o, e = standard_metrics(m), economic_metrics(m)
    assert (o["population"], e["mean_spice"], o["gini"]) == (77.0, 95.68948135466673, 0.3796649448208389)
