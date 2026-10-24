"""The GPU model against the Python model on states where sequential and parallel updating must agree.

Every site's capacity is distinct, so no two candidate sites tie; agents are farther apart than any two can
see, so Python's random order cannot matter.
"""

import numpy as np
import pytest

from gpu import compare_dumps, run_gpu
from reference import run_python

CAPACITY = (np.random.default_rng(1).permutation(400) + 2).reshape(20, 20)


def _agents(visions=(1, 2, 3, 3), metabolisms=(1, 2, 3, 4), sugar=10.0, max_age=None):
    sites = ((2, 2), (12, 2), (2, 12), (12, 12))
    return [{"x": x, "y": y, "vision": v, "metabolism": m, "sugar": sugar, "age": 0, "max_age": max_age}
            for (x, y), v, m in zip(sites, visions, metabolisms)]


CASES = {
    "g1_move": ({}, _agents(), 3),
    "g_inf": ({"growback_rate": "inf"}, _agents(), 5),
    "wrap_max_vision": ({"growback_rate": "inf", "vision": "1,9"},
                        [{"x": 0, "y": 19, "vision": 9, "metabolism": 2, "sugar": 10.0, "age": 0, "max_age": None}], 3),
    "starvation": ({}, _agents(metabolisms=(500, 500, 500, 500), sugar=1.0), 2),
    "max_age_death": ({"max_age": "2,2"}, _agents(max_age=2), 3),
    "seasons_fractional": ({"seasons": "4,3", "winter_growback": "fractional"}, _agents(), 7),
    "seasons_pulse": ({"seasons": "4,3", "winter_growback": "pulse"}, _agents(), 7),
    "pollution": ({"pollution": "1.0,1.0", "pollution_start": "1", "pollution_stop": "3"}, _agents(), 5),
    "pollution_diffusion": ({"pollution": "1.0,1.0", "diffusion_period": "2", "diffusion_start": "1"}, _agents(), 6),
}


@pytest.mark.parametrize("name", CASES)
def test_matches_python(exe, tmp_path, name):
    cfg, agents, steps = CASES[name]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, steps)
    # The scenario must not depend on Python's random order, or the comparison means nothing.
    for seed in ("1", "2"):
        assert compare_dumps(run_python({**cfg, "seed": seed}, CAPACITY, agents, steps), py, pollution=True) == []
    assert compare_dumps(gpu, py, pollution="pollution" in cfg) == []


def test_conflict_one_winner(exe, tmp_path):
    capacity = np.zeros((10, 10), dtype=int)
    capacity[5, 5] = 9
    agents = [{"x": x, "y": 5, "vision": 2, "metabolism": 1, "sugar": 10.0} for x in (3, 7)]
    dump = run_gpu(exe, tmp_path, {"vision": "1,2"}, capacity, agents, steps=1)
    assert dump.returncode == 0, dump.stderr
    on_peak = [a for a in dump.agents if (a["x"], a["y"]) == (5, 5)]
    assert len(on_peak) == 1
    assert on_peak[0]["sugar"] == pytest.approx(18.0)
    other = [a for a in dump.agents if (a["x"], a["y"]) != (5, 5)]
    assert len(other) == 1 and (other[0]["x"], other[0]["y"]) in ((3, 5), (7, 5))
    assert other[0]["sugar"] == pytest.approx(9.0)
    assert sum(site["occupied"] for site in dump.landscape.values()) == 2


def test_full_lattice_everyone_stays(exe, tmp_path):
    capacity = np.full((10, 10), 3, dtype=int)
    dump = run_gpu(exe, tmp_path, {"initial_population": "100", "vision": "1,4"}, capacity, steps=1)
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == 100
    assert all(a["moved"] == 0 for a in dump.agents)
    assert all(site["sugar"] == pytest.approx(1.0) for site in dump.landscape.values())


def test_block_placement(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, {"placement": "block", "block": "0,0,20,20"}, steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == 400
    assert len({(a["x"], a["y"]) for a in dump.agents}) == 400
    assert all(a["x"] < 20 and a["y"] < 20 for a in dump.agents)


GINI_CFG = {"initial_population": "250", "max_age": "60,100", "replacement": "true", "endowment": "5,25"}


def test_founder_ages_uniform(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, GINI_CFG, steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    assert all(0 <= a["age"] < a["max_age"] for a in dump.agents)
    assert any(a["age"] > 0 for a in dump.agents)


def test_founder_ages_zero(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, {**GINI_CFG, "founder_ages": "zero"}, steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    assert all(a["age"] == 0 for a in dump.agents)
