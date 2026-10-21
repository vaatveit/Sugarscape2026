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
