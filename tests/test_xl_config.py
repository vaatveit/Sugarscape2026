from dataclasses import replace

import pytest

from experiments.registry import EXPERIMENTS
from experiments.run import fingerprint
from sugarscape.config import Config
from sugarscape.model import Model


@pytest.mark.parametrize("bad", [0, -1, 1.5, True])
def test_diffusion_passes_must_be_a_whole_number_at_least_1(bad):
    with pytest.raises(ValueError):
        Config(diffusion_passes=bad)


def test_n_passes_equal_n_single_diffusions():
    base = Config(initial_population=50, pollution=(1.0, 1.0), diffusion_period=1, seed=7)
    a, b = Model(replace(base, diffusion_passes=3)), Model(base)
    a.step()
    b.step()
    b.landscape.diffuse()
    b.landscape.diffuse()
    assert (a.landscape.pollution == b.landscape.pollution).all()


def test_default_passes_leave_every_fingerprint_alone():
    assert "diffusion_passes" not in repr(Config())
    assert not any("diffusion_passes" in fingerprint(i) for i in EXPERIMENTS)


# --- the xl transform -----------------------------------------------------------------------

import numpy as np  # noqa: E402

from sugarscape.maps import load_map  # noqa: E402
from sugarscape.xl import to_xl  # noqa: E402


def test_xl_follows_the_spec_table():
    cfg = Config(initial_population=400, vision=(1, 6), placement="block", block=(0, 0, 20, 19),
                 diffusion_period=2, pollution=(1.0, 1.0), metabolism=(1, 4), seed=3)
    xl = to_xl(cfg)
    assert (xl.width, xl.height, xl.sugar_map) == (500, 500, "sugar-map-xl.txt")
    assert xl.initial_population == 40_000 and xl.vision == (10, 60)
    assert xl.block == (0, 0, 200, 190) and xl.diffusion_passes == 100
    assert replace(xl, width=50, height=50, sugar_map="sugar-map.txt", initial_population=400, vision=(1, 6),
                   block=(0, 0, 20, 19), diffusion_passes=1) == cfg  # nothing else changed


def test_tribal_blocks_scale_coordinates_by_10_and_counts_by_100():
    xl = to_xl(EXPERIMENTS["III-12"].config)
    assert xl.initial_blocks == (("blue", 0, 0, 200, 200, 37_000), ("red", 300, 300, 200, 200, 37_000))


def test_xl_refuses_a_world_that_is_not_the_50x50_map():
    with pytest.raises(ValueError):
        to_xl(to_xl(Config()))


def test_every_registered_sugarscape_experiment_has_an_xl_config():
    for exp in EXPERIMENTS.values():
        if isinstance(exp.config, Config):
            to_xl(exp.config)  # Config validates itself (vision < half the grid, blocks inside it)


def test_xl_vision_draws_every_whole_number_in_range():
    m = Model(to_xl(Config(initial_population=20)))  # 2,000 founders
    visions = {a.vision for a in m.agents}
    assert min(visions) >= 10 and max(visions) <= 60 and any(v % 10 for v in visions)


@pytest.mark.parametrize("exp_id", ["II-4", "II-6", "III-12", "IV-A3"])
def test_xl_models_build(exp_id):
    cfg = to_xl(EXPERIMENTS[exp_id].config)
    m = Model(cfg)
    xl_map = load_map("sugar-map-xl.txt")
    assert np.array_equal(m.landscape.capacity, xl_map)
    if cfg.spice:
        assert np.array_equal(m.landscape.spice_capacity, xl_map[::-1, :])
    if exp_id == "II-6":
        assert all(a.x < 200 and a.y < 200 for a in m.agents) and len(m.agents) == 40_000
    if exp_id == "III-12":
        assert len(m.agents) == 74_000
