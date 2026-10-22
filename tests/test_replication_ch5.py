import pytest

from experiments.registry import EXPERIMENTS
from replication.report import evaluate, load_or_run
from replication.targets import TARGETS

CH5 = [t for t in TARGETS if t.experiment.startswith("V-")]


def test_chapter5_experiments_registered():
    assert {"V-1", "V-2"} <= set(EXPERIMENTS)


def test_every_chapter5_target_has_an_experiment():
    assert len(CH5) == 6
    assert all(t.experiment in EXPERIMENTS for t in CH5)


def test_chapter5_configs_follow_the_book():  # p.147
    small, large = EXPERIMENTS["V-1"].config, EXPERIMENTS["V-2"].config
    assert (small.disease_list, small.diseases_per_agent) == (10, 4)
    assert (large.disease_list, large.diseases_per_agent) == (25, 10)
    for c in (small, large):  # "as in Chapter II"
        assert (c.immune_length, c.disease_length, c.disease_fee) == (50, (1, 10), 1.0)
        assert (c.initial_population, c.vision, c.metabolism, c.max_age) == (400, (1, 6), (1, 4), None)
        assert not (c.spice or c.sex)


@pytest.mark.slow
@pytest.mark.parametrize("target", CH5, ids=lambda t: f"{t.experiment}:{t.name}")
def test_chapter5_target(target):
    result = evaluate(target, load_or_run(target.experiment))
    assert result.status == "pass", result
