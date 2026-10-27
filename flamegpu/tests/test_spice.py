"""Spice, the second commodity (Chapter IV, p.96; plan 2026-10-26-gpu-parity-part-c, Tasks 2-4)."""

import numpy as np
import pytest

from gpu import compare_dumps, period_orders, read_rows, run_gpu
from reference import python_metric_rows, run_python, run_python_in_order
from test_metrics_parity import _compare
from test_parity import CAPACITY

SPICE = {"spice": "true", "vision": "0,0"}  # vision 0: movement can't matter (welfare movement is Task 3's)
EMPTY = np.zeros((20, 20), dtype=int)


def _harvesters(**kw):
    """test_parity's four far-apart agents, standing still, with spice."""
    sites = ((2, 2), (12, 2), (2, 12), (12, 12))
    return [{"x": x, "y": y, "vision": 0, "metabolism": m, "sugar": 10.0, "age": 0, "max_age": None, "spice": 30.0,
             "spice_metabolism": sm, **kw} for (x, y), m, sm in zip(sites, (1, 2, 3, 4), (1, 2, 3, 1))]


def test_spice_map_mirrors_sugar(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, {"spice": "true"}, steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    land = dump.landscape
    for (x, y), site in land.items():
        assert site["spice_capacity"] == land[(49 - x, y)]["capacity"], (x, y)
        assert site["spice"] == site["spice_capacity"], (x, y)


def test_spice_harvest_matches_python(exe, tmp_path):
    agents = _harvesters()
    gpu = run_gpu(exe, tmp_path, SPICE, CAPACITY, agents, steps=5)
    assert gpu.returncode == 0, gpu.stderr
    assert compare_dumps(gpu, run_python(SPICE, CAPACITY, agents, 5)) == []


def test_spice_growback_seasonal(exe, tmp_path):
    cfg = {**SPICE, "seasons": "2,4"}
    agents = _harvesters()
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=6)
    assert gpu.returncode == 0, gpu.stderr
    assert compare_dumps(gpu, run_python(cfg, CAPACITY, agents, 6)) == []


def _starving_pair():
    # S starves of spice with plenty of sugar; N, its neighbour, burns nothing.
    return [{"x": 5, "y": 5, "vision": 0, "metabolism": 1, "sugar": 50.0, "age": 0, "max_age": 90, "spice": 2.0,
             "spice_metabolism": 3},
            {"x": 6, "y": 5, "vision": 0, "metabolism": 0, "sugar": 10.0, "age": 0, "max_age": 90, "spice": 30.0,
             "spice_metabolism": 0}]


def test_spice_starvation_matches_python(exe, tmp_path):
    seen = set()
    for seed in range(10):
        cfg = {**SPICE, "seed": str(seed)}
        tmp = tmp_path / str(seed)
        orders = period_orders(exe, tmp / "order", cfg, EMPTY, _starving_pair(), 1)
        gpu = run_gpu(exe, tmp, cfg, EMPTY, _starving_pair(), steps=1)
        assert gpu.returncode == 0, gpu.stderr
        py = run_python_in_order(cfg, EMPTY, _starving_pair(), orders)
        assert compare_dumps(gpu, py) == [], seed
        assert len(gpu.agents) == len(py.agents) == 1
        assert gpu.agents[0]["neighbors"] == py.agents[0]["neighbors"], seed
        seen.add(gpu.agents[0]["neighbors"])
    assert seen == {0, 1}  # N's turn came first in some seeds, second in others


def test_spice_starvation_replaced(exe, tmp_path):
    out = tmp_path / "metrics.csv"
    cfg = {**SPICE, "replacement": "true", "max_age": "60,100"}
    dump = run_gpu(exe, tmp_path, cfg, EMPTY, _starving_pair(), steps=3, extra_args=("--check", "--out", out))
    assert dump.returncode == 0, dump.stderr
    assert [row["population"] for row in read_rows(out)] == [2, 2, 2, 2]


RANGES = {"spice": "true", "spice_endowment": "7,9", "spice_metabolism": "2,3"}


def _assert_spice_draws(agents, foresight):
    assert agents
    for a in agents:
        assert 7 <= a["spice"] <= 9 and a["initial_spice"] == a["spice"]
        assert 2 <= a["spice_metabolism"] <= 3
        assert (0 <= a["foresight"] <= 10) if foresight else a["foresight"] == 0
    if foresight:
        assert len({a["foresight"] for a in agents}) > 5


@pytest.mark.parametrize("foresight", ["", "0,10"], ids=["myopic", "foresight"])
def test_founders_draw_spice(exe, tmp_path, foresight):
    dump = run_gpu(exe, tmp_path, {**RANGES, "foresight": foresight}, steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == 400
    _assert_spice_draws(dump.agents, bool(foresight))


def test_newcomers_draw_spice(exe, tmp_path):
    cfg = {**RANGES, "foresight": "0,10", "replacement": "true", "max_age": "1,1"}
    dump = run_gpu(exe, tmp_path, cfg, steps=3)
    assert dump.returncode == 0, dump.stderr
    assert all(a["uid"] >= 400 for a in dump.agents)  # every founder has died: these are newcomers
    _assert_spice_draws(dump.agents, True)


def test_spice_metrics_match_python(exe, tmp_path):
    out = tmp_path / "metrics.csv"
    agents = _harvesters(foresight=3)
    dump = run_gpu(exe, tmp_path, SPICE, CAPACITY, agents, steps=1, extra_args=("--out", out))
    assert dump.returncode == 0, dump.stderr
    gpu = read_rows(out)
    py = python_metric_rows(SPICE, CAPACITY, agents, steps=1)
    for g, p in zip(gpu, py):
        assert _compare(g, p) == [], g["t"]


def test_init_spice_without_spice_refused(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, {}, EMPTY, _harvesters(), steps=1)
    assert dump.returncode == 2
    assert "line 2" in dump.stderr and "spice" in dump.stderr
