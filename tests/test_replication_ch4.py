import pytest

from experiments.registry import EXPERIMENTS
from replication.report import evaluate, load_or_run
from replication.targets import TARGETS

CH4 = [t for t in TARGETS if t.experiment.startswith("IV-")]
SINGLE = {"IV-3", "IV-7", "IV-9", "IV-14", "IV-15", "IV-17", "IV-A3", "IV-18", "IV-A5"}


def test_chapter4_experiments_registered():
    ids = {i for i in EXPERIMENTS if i.startswith("IV-")}
    assert SINGLE <= ids
    assert len([i for i in ids if i.startswith("IV-6/")]) == 10
    assert len([i for i in ids if i.startswith("IV-12/")]) == 4
    assert len([i for i in ids if i.startswith("IV-13/")]) == 10


def test_every_chapter4_target_has_an_experiment():
    assert len(CH4) == 41 + 10  # plus each Fig IV-6 point read at t≈50
    assert all(t.experiment in EXPERIMENTS for t in CH4)


def test_chapter4_configs_follow_the_book():
    neo = EXPERIMENTS["IV-3"].config  # p.108
    assert (neo.initial_population, neo.metabolism, neo.spice_metabolism, neo.vision, neo.endowment) == (
        200, (1, 5), (1, 5), (1, 5), (25, 50))
    assert neo.spice and neo.trade and neo.max_age is None
    s = EXPERIMENTS["IV-14"].config  # p.123
    assert (s.female_fertility_end, s.male_fertility_end, s.max_age) == ((35, 45), (45, 55), (60, 100))
    p = EXPERIMENTS["IV-A3"].config  # p.127-128
    assert (p.pollution_start, p.pollution_stop, p.diffusion_start, p.diffusion_period) == (100, 150, 150, 1)
    c = EXPERIMENTS["IV-A5"].config
    assert c.credit == (10, 10.0) and not c.spice and c.sex
    assert EXPERIMENTS["IV-13/trade/v14.5"].config.vision == (5, 24)
    assert not EXPERIMENTS["IV-6/notrade/v3"].config.trade and EXPERIMENTS["IV-6/trade/v3"].config.trade
    assert EXPERIMENTS["IV-12/a980"].config.max_age == (960, 1000)
    assert EXPERIMENTS["IV-15"].config.cultural_preferences and EXPERIMENTS["IV-18"].config.foresight == (0, 10)


@pytest.mark.slow
@pytest.mark.parametrize("target", CH4, ids=lambda t: f"{t.experiment}:{t.name}")
def test_chapter4_target(target):
    result = evaluate(target, load_or_run(target.experiment))
    assert result.status == "pass", result
