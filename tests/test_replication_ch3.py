import math

import pytest

from experiments.registry import EXPERIMENTS
from replication.report import evaluate, load_or_run
from replication.targets import TARGETS

CH3 = [t for t in TARGETS if t.experiment.startswith("III-")]
IDS = {"III-1", "III-3", "III-4", "III-5", "III-7", "III-8", "III-9", "III-11", "III-12", "III-13", "III-14", "III-15"}


def test_chapter3_experiments_registered():
    assert IDS <= set(EXPERIMENTS)


def test_every_chapter3_target_has_an_experiment():
    assert len(CH3) == 23
    assert all(t.experiment in EXPERIMENTS for t in CH3)


def test_chapter3_configs_follow_the_book():
    base = EXPERIMENTS["III-1"].config
    assert (base.sex, base.endowment, base.max_age) == (True, (50, 100), (60, 100))  # p.57
    small = EXPERIMENTS["III-3"].config  # p.64: fertility ends 10 years earlier
    assert (small.female_fertility_end, small.male_fertility_end) == ((30, 40), (40, 50))
    assert EXPERIMENTS["III-4"].config.endowment == (10, 40)  # p.65
    both = EXPERIMENTS["III-5"].config
    assert both.endowment == (10, 40) and both.female_fertility_end == (30, 40)
    assert EXPERIMENTS["III-7"].config.inheritance
    culture = EXPERIMENTS["III-8"].config
    assert (culture.tag_length, culture.culture, culture.sex) == (11, True, False)  # p.74
    war = EXPERIMENTS["III-9"].config
    assert war.combat_alpha == math.inf and war.initial_blocks == (
        ("blue", 0, 0, 20, 20, 270), ("red", 30, 30, 20, 20, 270))
    attrition = EXPERIMENTS["III-11"].config  # p.86
    assert (attrition.combat_alpha, attrition.max_age, attrition.replacement, attrition.replacement_same_tribe) == (
        2, (60, 100), True, True)
    assert sum(b[5] for b in attrition.initial_blocks) == 400
    assert EXPERIMENTS["III-12"].config.vision == (1, 10) and EXPERIMENTS["III-13"].config.combat_alpha == 2
    assert EXPERIMENTS["III-14"].config.culture and EXPERIMENTS["III-14"].config.combat_alpha == math.inf
    proto = EXPERIMENTS["III-15"].config
    assert (proto.sex, proto.culture, proto.initial_population) == (True, True, 100)


@pytest.mark.slow
@pytest.mark.parametrize("target", CH3, ids=lambda t: f"{t.experiment}:{t.name}")
def test_chapter3_target(target):
    result = evaluate(target, load_or_run(target.experiment))
    assert result.status == "pass", result
