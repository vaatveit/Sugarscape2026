import numpy as np

from conftest import couple, put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.sex import is_fertile, mate


def test_child_born_with_half_of_each_initial_endowment():  # p.55
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True)
    f, h = couple(m)
    kids = mate(m, f)
    assert len(kids) == 1 and kids[0].sugar == kids[0].initial_sugar == 60.0
    assert f.sugar == h.sugar == 30.0 and kids[0] in f.children and kids[0] in h.children
    k = kids[0]
    assert abs(k.x - f.x) + abs(k.y - f.y) == 1 or abs(k.x - h.x) + abs(k.y - h.y) == 1
    assert m.agent_at(k.x, k.y) is k and k in m.agents


def test_fertility_window():
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True)
    f, _ = couple(m)
    assert is_fertile(f)
    f.age = 11
    assert not is_fertile(f)
    f.age = 40
    assert not is_fertile(f)  # childbearing ends at fertility_end


def test_infertile_cases():
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True)
    f, h = couple(m, sugar=59.0)
    assert mate(m, f) == []  # wealth below initial endowment
    f.sugar = h.sugar = 60.0
    h.sex = "F"
    assert mate(m, f) == []  # same sex
    h.sex, h.age = "M", 50
    assert mate(m, f) == []  # too old


def test_no_room_no_child_no_cost():  # Review Focus 1
    m = tiny_model(np.ones((3, 3), dtype=int), sex=True)
    f, h = couple(m)
    for x in range(3):
        for y in range(3):
            if m.agent_at(x, y) is None:
                put_agent(m, x, y)
    assert mate(m, f) == [] and f.sugar == 60.0


def test_child_genes_come_from_parents():  # Table III-1, p.78
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True, tag_length=3)
    f, h = couple(m)
    f.vision, f.metabolism, h.vision, h.metabolism = 1, 4, 3, 2
    f.tags, h.tags = [0, 0, 1], [0, 0, 0]
    child = mate(m, f)[0]
    assert child.vision in (1, 3) and child.metabolism in (4, 2) and child.tags[:2] == [0, 0]
    assert child.age == 0 and child.sex in ("F", "M") and child.max_age in (f.max_age, h.max_age)


def test_mates_with_every_viable_neighbor():  # p.56
    m = tiny_model(np.ones((7, 7), dtype=int), sex=True)
    f, h = couple(m, sugar=200.0)
    h2 = put_agent(m, 1, 2, sugar=200.0)
    h2.sex, h2.fertility_start, h2.fertility_end, h2.initial_sugar, h2.age = "M", 12, 50, 60.0, 20
    assert len(mate(m, f)) == 2 and f.sugar == 200.0 - 60.0


def test_mating_near_full_lattice_runs():  # Review Focus 4
    m = Model(Config(initial_population=2400, sex=True, endowment=(50, 100), max_age=(60, 100), seed=1))
    for _ in range(3):
        m.step()
    assert len(m.agents) <= 2500


def test_fertility_needs_only_the_sugar_endowment():  # p.55 names sugar only (user decision)
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True, spice=True, foresight=(0, 10))
    f, h = couple(m)
    for a, phi in ((f, 2), (h, 2)):
        a.initial_spice, a.spice, a.spice_metabolism, a.foresight = 40.0, 10.0, 1, phi
    assert is_fertile(f) and is_fertile(h)  # spice below its endowment doesn't matter
    child = mate(m, f)[0]
    assert child.spice == child.initial_spice == 40.0  # each parent still gives half its initial spice
    assert f.spice == h.spice == 10.0 - 20.0
    assert child.spice_metabolism == 1 and child.foresight == 2


def test_sugar_only_children_have_no_spice():
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True)
    f, h = couple(m)
    child = mate(m, f)[0]
    assert child.spice == 0.0 and child.spice_metabolism == 0
