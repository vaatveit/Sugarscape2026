import math

import pytest

from experiments.registry import EXPERIMENTS
from replication.report import evaluate, load_or_run
from replication.targets import TARGETS

CH2 = [t for t in TARGETS if t.experiment.startswith("II-")]


def test_chapter2_experiments_registered():
    ids = {i for i in EXPERIMENTS if i.startswith("II-")}
    assert {"II-1", "II-4", "II-4-gini", "II-6", "II-6-measured", "II-7", "II-8"} <= ids
    assert len([i for i in ids if i.startswith("II-5/")]) == 18


def test_every_chapter2_target_has_an_experiment():
    assert len(CH2) == 12 + 18 + 18 + 1  # plan's 12, each Fig II-5 point at t=500 and at t≈50, II-6-measured's wave
    assert all(t.experiment in EXPERIMENTS for t in CH2)


def test_chapter2_configs_follow_the_book():
    assert EXPERIMENTS["II-1"].config.growback_rate == math.inf
    gini = EXPERIMENTS["II-4-gini"].config
    assert (gini.initial_population, gini.max_age, gini.replacement) == (250, (60, 100), True)
    assert EXPERIMENTS["II-7"].config.seasons == (8, 50)
    p = EXPERIMENTS["II-8"].config
    assert (p.pollution, p.pollution_start, p.diffusion_period, p.diffusion_start) == ((1.0, 1.0), 50, 1, 100)
    assert EXPERIMENTS["II-5/m3/v10.5"].config.vision == (1, 20)


def test_chapter2_endowments_and_block_follow_the_evidence():
    # 25-50 reproduces Fig II-4's population curve; II-3/II-4 states 5-25 explicitly (p.33).
    for exp_id in ("II-1", "II-4", "II-5/m2/v3", "II-6", "II-6-measured", "II-7", "II-8"):
        assert EXPERIMENTS[exp_id].config.endowment == (25, 50), exp_id
    assert EXPERIMENTS["II-4-gini"].config.endowment == (5, 25)
    text = EXPERIMENTS["II-6"].config  # p.42: "in all other respects ... exactly as in II-2" (400)
    assert (text.block, text.initial_population, text.vision) == ((0, 0, 20, 20), 400, (1, 10))
    measured = EXPERIMENTS["II-6-measured"].config  # Animation II-6 frame 1, blob count
    assert (measured.block, measured.initial_population) == ((0, 0, 20, 19), 284)


@pytest.mark.slow
@pytest.mark.parametrize("target", CH2, ids=lambda t: f"{t.experiment}:{t.name}")
def test_chapter2_target(target):
    result = evaluate(target, load_or_run(target.experiment))
    assert result.status == "pass", result
