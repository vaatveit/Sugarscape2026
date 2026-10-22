from dataclasses import replace

import pytest

from experiments.registry import EXPERIMENTS
from replication.report import evaluate, load_or_run
from replication.targets import TARGETS
from sugarscape.variants.ringworld import RingConfig
from sugarscape.variants.schelling import SchellingConfig

CH6 = [t for t in TARGETS if t.experiment.startswith("VI-")]
IDS = {f"VI-{k}" for k in range(1, 10)}


def test_chapter6_experiments_registered():
    assert IDS <= set(EXPERIMENTS)


def test_every_chapter6_target_has_an_experiment():
    assert len(CH6) == 38
    assert all(t.experiment in EXPERIMENTS for t in CH6)
    assert all(t.baseline in EXPERIMENTS for t in CH6 if t.baseline)


def test_all_rules_society_follows_the_book():  # Animation VI-1, pp.154-157
    c = EXPERIMENTS["VI-1"].config
    assert c.initial_population == 200 and c.spice and c.trade and c.sex and c.culture and c.tag_length == 11
    assert c.credit == (10, 10.0) and (c.disease_list, c.diseases_per_agent) == (25, 10)
    assert not c.inheritance and not c.cultural_preferences


def test_indecomposability_runs_differ_only_in_trade():  # p.159
    vi2, vi3 = EXPERIMENTS["VI-2"].config, EXPERIMENTS["VI-3"].config
    assert (vi3.initial_population, vi3.vision, vi3.metabolism, vi3.max_age) == (500, (1, 5), (1, 5), (60, 100))
    assert vi3.sex and vi3.spice and not vi2.trade
    assert replace(vi2, trade=True) == vi3


def test_schelling_runs_follow_the_book():  # pp.166-170
    configs = [EXPERIMENTS[f"VI-{k}"].config for k in (4, 5, 6, 7)]
    assert all(isinstance(c, SchellingConfig) for c in configs)
    assert all((c.width, c.height, c.population) == (50, 50, 2000) for c in configs)
    assert [c.preference for c in configs] == [(0.25, 0.25), (0.25, 0.25), (0.5, 0.5), (0.25, 0.5)]
    assert [c.max_age for c in configs] == [None, (80, 100), (80, 100), (80, 100)]


def test_ring_world_runs_follow_the_book():  # pp.172-174
    configs = [EXPERIMENTS[f"VI-{k}"].config for k in (8, 9)]
    assert all(isinstance(c, RingConfig) for c in configs)
    assert all((c.sites, c.population, c.vision, c.capacity) == (150, 40, (15, 30), 4) for c in configs)
    assert [c.placement for c in configs] == ["random", "block"]


@pytest.mark.slow
@pytest.mark.parametrize("target", CH6, ids=lambda t: f"{t.experiment}:{t.name}")
def test_chapter6_target(target):
    base = load_or_run(target.baseline) if target.baseline else None
    result = evaluate(target, load_or_run(target.experiment), base)
    assert result.status == "pass", result
