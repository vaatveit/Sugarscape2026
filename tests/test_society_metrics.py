import math

import pytest

from conftest import make_tagged
from experiments.run import run_experiment
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.stats import society_metrics

KEYS = {"n_blue", "n_red", "blue_fraction", "sw_blue", "sw_red", "ne_blue", "ne_red", "blue_xy", "red_xy",
        "blue_advance", "red_advance",
        "mean_children", "best_friend_closeness", "friend_closeness"}


def test_tribeless_population_gives_zero_counts_and_nan():  # Review Focus 3
    out = society_metrics(Model(Config(seed=2)))
    assert set(out) == KEYS
    assert out["n_blue"] == out["n_red"] == 0.0 and math.isnan(out["blue_fraction"]) and math.isnan(out["blue_xy"])
    assert math.isnan(out["best_friend_closeness"]) and out["mean_children"] == 0.0


def test_one_tribe_extinct():
    m = Model(Config(tag_length=11, initial_blocks=(("blue", 0, 0, 10, 10, 30),)))
    out = society_metrics(m)
    assert out["blue_fraction"] == 1.0 and out["n_red"] == 0.0 and math.isnan(out["red_xy"])
    assert out["sw_blue"] == 30.0 and out["ne_blue"] == 0.0


def test_empty_population():
    m = Model(Config(initial_population=0))
    assert all(v == 0.0 or math.isnan(v) for v in society_metrics(m).values())


def test_friend_closeness_uses_current_tags_of_living_friends():
    m = Model(Config(initial_population=0, tag_length=3))
    a = m.new_agent(0, 0, 1, 1, 10.0)
    a.tags = [0, 0, 0]
    near, far = make_tagged([0, 0, 0]), make_tagged([1, 1, 0])
    a.friends = [(near, 0), (far, 2)]
    out = society_metrics(m)
    assert out["best_friend_closeness"] == 1.0 and out["friend_closeness"] == pytest.approx((1.0 + 1 / 3) / 2)
    near.alive = False
    assert society_metrics(m)["best_friend_closeness"] == pytest.approx(1 / 3)


def test_values_are_plain_floats_and_runner_records_them(tmp_path):
    m = Model(Config(tag_length=11, initial_blocks=(("blue", 0, 0, 10, 10, 30), ("red", 30, 30, 10, 10, 30))))
    assert all(type(v) is float for v in society_metrics(m).values())
    row = run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path)[0][0]
    assert "blue_fraction" in row and "population" in row


def test_advance_is_toroidal_displacement():  # wrapping step counts as 1, not 49
    m = Model(Config(initial_population=0, tag_length=1))
    a = m.new_agent(0, 5, 1, 1, 10.0)
    a.tags = [0]
    m.move_agent(a, 49, 5)
    m.move_agent(a, 49, 6)
    assert (a.disp_x, a.disp_y) == (-1, 1)
    out = society_metrics(m)
    assert out["blue_advance"] == 0.0 and math.isnan(out["red_advance"])
