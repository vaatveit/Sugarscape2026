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


@pytest.mark.parametrize("bad", [
    {"seasons": (8, 0)}, {"seasons": (0, 50)}, {"diffusion_period": 0}, {"growback_rate": -1.0},
    {"initial_population": -1}, {"pollution": (-1.0, 1.0)},
    {"placement": "block", "block": (0, 0, 60, 60)}, {"placement": "block", "block": (0, 0, 0, 5)},
    {"winter_growback": "sometimes"},
])
def test_invalid_values_rejected_early(bad):
    with pytest.raises(ValueError):
        Config(**bad)


def test_winter_growback_defaults_to_fractional():  # design: "winter growback is fractional"
    assert Config().winter_growback == "fractional"


def test_chapter3_defaults_are_off():
    c = Config()
    assert not (c.sex or c.inheritance or c.culture) and c.combat_alpha is None and c.tag_length == 0


@pytest.mark.parametrize("bad", [
    {"tag_length": 10}, {"tag_length": -1}, {"culture": True}, {"combat_alpha": 2.0},
    {"tag_length": 11, "combat_alpha": -1.0}, {"female_fertility_end": (50, 40)},
    {"tag_length": 11, "initial_blocks": (("green", 0, 0, 5, 5, 10),)},
    {"tag_length": 11, "initial_blocks": (("blue", 0, 0, 5, 5, 26),)},
    {"tag_length": 11, "initial_blocks": (("blue", 48, 0, 5, 5, 10),)},
    {"initial_blocks": (("blue", 0, 0, 5, 5, 10),)},
    {"replacement_same_tribe": True, "max_age": (60, 100)},
])
def test_chapter3_invalid_values_rejected(bad):
    with pytest.raises(ValueError):
        Config(**bad)


@pytest.mark.parametrize("bad", [
    {"trade": True}, {"foresight": (0, 10)}, {"cultural_preferences": True, "spice": True},
    {"spice": True, "tag_length": 11, "combat_alpha": 2.0}, {"spice": True, "credit": (10, 10.0), "sex": True},
    {"credit": (10, 10.0)}, {"sex": True, "credit": (0, 10.0)}, {"sex": True, "credit": (10, -1.0)},
    {"spice": True, "spice_metabolism": (5, 1)}, {"spice": True, "foresight": (10, 0)},
    {"pollution": (1.0, 1.0), "pollution_start": 100, "pollution_stop": 100},
])
def test_chapter4_invalid_values_rejected(bad):
    with pytest.raises(ValueError):
        Config(**bad)


def test_credit_with_combat_rejected():  # combat doesn't record income, so nobody could borrow
    with pytest.raises(ValueError):
        Config(sex=True, credit=(10, 10.0), tag_length=11, combat_alpha=2.0)


@pytest.mark.parametrize("bad", [
    {"disease_list": 3, "diseases_per_agent": 4}, {"disease_list": 5, "disease_length": (1, 50)},
    {"disease_list": 5, "disease_length": (0, 4)}, {"disease_list": 5, "disease_fee": -1.0},
    {"disease_list": 5, "disease_length": (6, 3)}, {"disease_list": -1}, {"disease_list": 5, "diseases_per_agent": -1},
])
def test_chapter5_invalid_values_rejected(bad):  # Review Focus 1
    with pytest.raises(ValueError):
        Config(**bad)
