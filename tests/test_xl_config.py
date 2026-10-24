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
