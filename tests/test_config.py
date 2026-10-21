import dataclasses

import pytest

from sugarscape.config import Config


def test_defaults_match_chapter_two():
    c = Config()
    assert (c.width, c.height, c.initial_population) == (50, 50, 400)
    assert c.vision == (1, 6) and c.metabolism == (1, 4)


@pytest.mark.parametrize("field", ["vision", "metabolism", "endowment", "max_age"])
def test_inverted_range_rejected(field):
    with pytest.raises(ValueError):
        Config(**{field: (5, 2)})


def test_vision_that_wraps_rejected():
    with pytest.raises(ValueError):
        Config(vision=(1, 25))  # 25 * 2 >= 50
    Config(vision=(1, 20))  # Fig II-5 uses up to 20


def test_replacement_requires_max_age():
    with pytest.raises(ValueError):
        Config(replacement=True)


def test_unknown_placement_rejected():
    with pytest.raises(ValueError):
        Config(placement="ring")


def test_config_is_frozen():
    with pytest.raises(dataclasses.FrozenInstanceError):
        Config().seed = 3
