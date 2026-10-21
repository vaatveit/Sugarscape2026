import math

from sugarscape.agent import Agent


def test_agent_tribe_from_tag_majority():  # p.73-74 examples
    a = Agent(0, 0, 0, 1, 1, 1.0, 1.0, math.inf, tags=[int(c) for c in "01010001010"])
    b = Agent(1, 0, 0, 1, 1, 1.0, 1.0, math.inf, tags=[int(c) for c in "01001110101"])
    assert (a.tribe, b.tribe) == ("blue", "red")
    assert Agent(2, 0, 0, 1, 1, 1.0, 1.0, math.inf).tribe is None


def test_new_fields_default_to_off():
    a = Agent(0, 0, 0, 1, 1, 1.0, 1.0, math.inf)
    assert a.sex is None and a.children == [] and a.friends == [] and a.tags is None
    assert a.fertility_start > a.fertility_end  # never fertile by default
