import numpy as np

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model


def test_inheritance_splits_wealth_among_living_children():  # p.67
    m = tiny_model(np.ones((5, 5), dtype=int), inheritance=True)
    p = put_agent(m, 0, 0, sugar=30.0)
    kids = [put_agent(m, 2, y) for y in (0, 1, 2)]
    p.children = kids
    m.kill(kids[2])
    m.die(p)
    assert [k.sugar for k in kids[:2]] == [25.0, 25.0] and not p.alive


def test_no_inheritance_when_off():
    m = tiny_model(np.ones((5, 5), dtype=int))
    p = put_agent(m, 0, 0, sugar=30.0)
    k = put_agent(m, 2, 2)
    p.children = [k]
    m.die(p)
    assert k.sugar == 10.0


def test_negative_wealth_is_not_inherited():
    m = tiny_model(np.ones((5, 5), dtype=int), inheritance=True)
    p = put_agent(m, 0, 0, sugar=-2.0)
    k = put_agent(m, 2, 2)
    p.children = [k]
    m.die(p)
    assert k.sugar == 10.0


def test_same_batch_deaths_do_not_inherit():  # Review Focus 2
    m = tiny_model(np.zeros((5, 5), dtype=int), inheritance=True)  # no harvest: sugar only falls by 1
    p = put_agent(m, 0, 0, sugar=40.0, max_age=1)
    k = put_agent(m, 2, 2, max_age=1)
    q = put_agent(m, 4, 4)
    p.children = [k, q]
    m.step()
    assert not k.alive and q.sugar == 9.0 + 39.0  # q gets all of p's 39; k died in the same batch


def test_blocks_are_tagged_by_tribe():
    m = Model(Config(tag_length=11, initial_blocks=(("blue", 0, 0, 20, 20, 270), ("red", 30, 30, 20, 20, 270))))
    assert len(m.agents) == 540
    assert all(a.tribe == ("blue" if a.x < 20 else "red") for a in m.agents)


def test_same_tribe_replacement():  # p.86
    m = Model(Config(tag_length=11, max_age=(1, 1), replacement=True, replacement_same_tribe=True,
                     initial_blocks=(("red", 30, 30, 20, 20, 50),)))
    m.step()
    assert len(m.agents) == 50 and all(a.tribe == "red" and a.age == 0 for a in m.agents)
    assert m.deaths_this_step == 50 and len(m.dead_this_step) == 50


def test_random_agents_get_tags_and_sex_only_when_enabled():
    plain = Model(Config(initial_population=20))
    assert all(a.tags is None and a.sex is None for a in plain.agents)
    rich = Model(Config(initial_population=20, tag_length=11, sex=True))
    assert all(len(a.tags) == 11 and a.sex in ("F", "M") for a in rich.agents)
    f = [a for a in rich.agents if a.sex == "F"]
    assert all(12 <= a.fertility_start <= 15 and 40 <= a.fertility_end <= 50 for a in f)
