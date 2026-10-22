"""Helpers for building small, hand-specified models in tests."""

import math

from sugarscape.agent import Agent
from sugarscape.config import Config
from sugarscape.model import Model


def tiny_model(capacity, **overrides) -> Model:
    """Model on an explicit capacity grid with no initial agents."""
    base = dict(width=capacity.shape[0], height=capacity.shape[1], initial_population=0, vision=(1, 1))
    base.update(overrides)
    return Model(Config(**base), capacity=capacity)


def put_agent(model, x, y, vision=1, metabolism=1, sugar=10.0, max_age=math.inf) -> Agent:
    return model.new_agent(x, y, vision, metabolism, sugar, max_age)


_tagged_ids = iter(range(10_000, 10**9))


def make_tagged(tags) -> Agent:
    """A free-standing agent (not on any grid) with the given cultural tags."""
    return Agent(next(_tagged_ids), 0, 0, 1, 1, 10.0, 10.0, math.inf, tags=list(tags))


def couple(m, sugar=60.0):
    f = put_agent(m, 2, 2, sugar=sugar)
    f.sex, f.fertility_start, f.fertility_end, f.initial_sugar = "F", 12, 40, 60.0
    h = put_agent(m, 2, 3, sugar=sugar)
    h.sex, h.fertility_start, h.fertility_end, h.initial_sugar = "M", 12, 50, 60.0
    f.age = h.age = 20
    return f, h
