import math

import numpy as np

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.combat import combat_move


def combat_model(alpha=math.inf):
    return tiny_model(np.zeros((12, 12), dtype=int), tag_length=1, combat_alpha=alpha, vision=(1, 4))


def tribe_agent(m, x, y, tag, sugar, vision=4):
    a = put_agent(m, x, y, vision=vision, sugar=sugar)
    a.tags = [tag]
    return a


def test_attacks_smaller_enemy_and_takes_wealth():  # p.83
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 20.0)
    r = tribe_agent(m, 3, 1, 1, 8.0)
    combat_move(m, a)
    assert (a.x, a.y) == (3, 1) and a.sugar == 28.0 and not r.alive


def test_reward_capped_at_alpha():
    m = combat_model(alpha=2.0)
    a = tribe_agent(m, 1, 1, 0, 20.0)
    r = tribe_agent(m, 3, 1, 1, 8.0)
    combat_move(m, a)
    assert a.sugar == 22.0 and not r.alive


def test_never_attacks_own_tribe_or_wealthier():
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 20.0)
    tribe_agent(m, 2, 1, 0, 1.0)
    tribe_agent(m, 1, 2, 1, 25.0)
    m.landscape.sugar[4, 1] = 1.0  # empty site out of the rich Red's sight lines
    combat_move(m, a)
    assert (a.x, a.y) == (4, 1)


def test_retaliation_blocks_attack():  # p.82
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 20.0)
    r = tribe_agent(m, 3, 1, 1, 8.0)
    tribe_agent(m, 5, 1, 1, 30.0)  # bigger Red within vision of the target: 30 > 28
    combat_move(m, a)
    assert r.alive and (a.x, a.y) != (3, 1)


def test_stays_when_nothing_is_safe():
    m = combat_model()
    a = tribe_agent(m, 1, 1, 0, 2.0)
    for x, y in ((1, 3), (3, 1), (1, 11), (11, 1)):
        tribe_agent(m, x, y, 1, 50.0)
    combat_move(m, a)
    assert (a.x, a.y) == (1, 1)


def test_dead_victim_never_acts():  # Review Focus 2
    m = Model(Config(tag_length=11, combat_alpha=math.inf, endowment=(25, 50), seed=0,
                     initial_blocks=(("blue", 0, 0, 20, 20, 270), ("red", 30, 30, 20, 20, 270))))
    for _ in range(30):
        m.step()
        assert all(a.alive and m.agent_at(a.x, a.y) is a for a in m.agents)
        assert len({(a.x, a.y) for a in m.agents}) == len(m.agents)


def test_culture_runs_in_the_turn():
    m = Model(Config(tag_length=11, culture=True, initial_population=400, seed=0))
    before = [list(a.tags) for a in m.agents]
    m.run(5)
    assert any(a.tags != b for a, b in zip(m.agents, before))
    assert any(a.friends for a in m.agents)
