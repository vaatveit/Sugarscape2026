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


# --- Welfare movement (Task 3; Julia's spice_move scenarios, julia/bridge/scenarios.py) -----------------------------

def _movers(**kw):
    """test_parity's four far-apart agents (visions 1-3), with spice 30 and spice metabolism 2."""
    sites = ((2, 2), (12, 2), (2, 12), (12, 12))
    return [{"x": x, "y": y, "vision": v, "metabolism": m, "sugar": 10.0, "age": 0, "max_age": None, "spice": 30.0,
             "spice_metabolism": 2, **kw} for (x, y), v, m in zip(sites, (1, 2, 3, 3), (1, 2, 3, 4))]


POLLUTED = {"spice": "true", "pollution": "1.0,1.0", "diffusion_period": "1"}
WELFARE_CASES = {
    "myopic": ({"spice": "true"}, {}),
    "foresight": ({"spice": "true", "foresight": "0,10"}, {"foresight": 5}),
    "polluted": (POLLUTED, {}),
    "stopped": ({**POLLUTED, "pollution_start": "1", "pollution_stop": "3"}, {}),
}


@pytest.mark.parametrize("name", WELFARE_CASES)
def test_welfare_move_matches_python(exe, tmp_path, name):
    cfg, extra = WELFARE_CASES[name]
    agents = _movers(**extra)
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=4)
    assert gpu.returncode == 0, gpu.stderr
    assert compare_dumps(gpu, run_python(cfg, CAPACITY, agents, 4), pollution=True) == []


def test_cultural_preferences_move_matches_python(exe, tmp_path):
    capacity = np.zeros((21, 21), dtype=int)
    capacity[14, 5] = capacity[14, 15] = 4  # sugar east; through the mirror, spice at x = 6 on the same rows
    cfg = {"spice": "true", "tag_length": "3", "cultural_preferences": "true", "vision": "4,4"}
    common = {"vision": 4, "metabolism": 1, "sugar": 10.0, "age": 0, "max_age": None, "spice": 10.0,
              "spice_metabolism": 1}
    agents = [{"x": 10, "y": 5, "tags": "000", **common},   # f = 1: only sugar counts
              {"x": 10, "y": 15, "tags": "111", **common}]  # f = 0: only spice counts
    gpu = run_gpu(exe, tmp_path, cfg, capacity, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    assert {(a["x"], a["y"]) for a in gpu.agents} == {(14, 5), (6, 15)}
    assert compare_dumps(gpu, run_python(cfg, capacity, agents, 1)) == []


def test_welfare_zero_metabolism_matches_python(exe, tmp_path):
    cfg = {"spice": "true"}
    agents = _movers()[:2]
    agents[0].update(metabolism=0, spice_metabolism=0)  # every site's welfare is 1.0: it stays
    agents[1].update(spice_metabolism=0)                # only sugar counts
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=2)
    assert gpu.returncode == 0, gpu.stderr
    assert compare_dumps(gpu, run_python(cfg, CAPACITY, agents, 2)) == []
    assert (2, 2) in {(a["x"], a["y"]) for a in gpu.agents}


# --- Spice on the turns path (Task 4) -------------------------------------------------------------------------------

def _registry(exp_id, **overrides):
    from test_combat import registry_cfg

    return registry_cfg(exp_id, **overrides)


@pytest.mark.parametrize("exp_id, overrides", [("IV-6/notrade/v2", {}), ("IV-13/notrade/v3.5", {"replacement": "false"})],
                         ids=["IV-6-notrade-v2", "IV-13-notrade-v3.5"])
def test_turns_path_equals_fast_path_spice(exe, tmp_path, exp_id, overrides):
    # Replacement is left out of IV-13: place_newcomer's site race is decided by the GPU's timing (chapter3-part-b.md).
    from test_turns import FILES, _files

    cfg = _registry(exp_id, **overrides)
    fast = _files(exe, tmp_path / "fast", cfg, 20, 20)
    turns = _files(exe, tmp_path / "turns", cfg, 20, 20, "--force-turns")
    for f in FILES:
        assert turns[f] == fast[f], f"{exp_id}: {f} differs between the turns and the fast path"


def _child_cases():
    from test_sex import BOOK

    return {"endowment": BOOK, "capped": {**BOOK, "child_gift": "capped"}, "redraw": {**BOOK, "child_threshold": "redraw"},
            "down": {"mate_contact": "neighbors", "gift_rounding": "down"}}


@pytest.mark.parametrize("name", ["endowment", "capped", "redraw", "down"])
def test_child_spice_matches_python(exe, tmp_path, name):
    from test_sex import CFG as SEX_CFG, EMPTY as SEX_EMPTY, PAIR, _by_uid

    cfg = {**SEX_CFG, "spice": "true", **_child_cases()[name]}
    # Everyone burns no spice, so the order still can't matter; the parents' initial spice is 30.
    agents = [dict(a, spice=40.0, spice_metabolism=0, **({"initial_spice": 30.0} if a.get("sex") else {})) for a in PAIR]
    gpu = run_gpu(exe, tmp_path, cfg, SEX_EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, SEX_EMPTY, agents, 1)
    assert compare_dumps(gpu, py) == []
    g, p = _by_uid(gpu.agents), _by_uid(py.agents)
    child = len(agents)
    assert set(g) == set(p) and child in g
    for uid in p:
        assert g[uid]["spice"] == pytest.approx(p[uid]["spice"], abs=1e-9), (name, uid)
        if uid != child or name != "redraw":
            assert g[uid]["initial_spice"] == pytest.approx(p[uid]["initial_spice"], abs=1e-9), (name, uid)
    if name == "redraw":  # drawn from the endowment's range, spice_endowment being unset
        assert 50 <= g[child]["initial_spice"] <= 100 and g[child]["initial_spice"] == int(g[child]["initial_spice"])


@pytest.mark.parametrize("exp_id", ["IV-18", "VI-2"])
def test_serial_equivalence_spice(exe, tmp_path, exp_id):
    from conftest import run_exe
    from gpu import write_cfg
    from test_sex import _files

    cfg = _registry(exp_id)
    assert _files(exe, tmp_path / "waves", cfg, 20) == _files(exe, tmp_path / "serial", cfg, 20, "--serial-turns")
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg, steps="20"), "--check")
    assert result.returncode == 0, result.stderr


def test_init_spice_without_spice_refused(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, {}, EMPTY, _harvesters(), steps=1)
    assert dump.returncode == 2
    assert "line 2" in dump.stderr and "spice" in dump.stderr
