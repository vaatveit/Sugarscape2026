"""Rule I at old age (spec 2026-10-25-gpu-full-parity, section 4; Part A, Task 6).

Nobody moves (every capacity 0, vision 0). Parents reach their maximum age at the end of period 1; their positive
sugar goes in equal shares to their living children not dying in the same period, as Python's Model.die gives it.
"""

import math

import numpy as np

from gpu import run_gpu
from reference import run_python

EMPTY = np.zeros((20, 20), dtype=int)
CFG = {"sex": "true", "inheritance": "true", "max_age": "60,100"}


def _agent(x, y, sugar, max_age, **kw):
    return {"x": x, "y": y, "vision": 0, "metabolism": 1, "sugar": sugar, "age": 30, "max_age": max_age, **kw}


def _compare(gpu, py):
    g = {a["uid"]: a for a in gpu.agents}
    p = {a["uid"]: a for a in py.agents}
    assert set(g) == set(p)
    return {uid: (g[uid]["sugar"], p[uid]["sugar"]) for uid in p}


def test_inheritance_matches_python(exe, tmp_path):
    # Parent 0 dies of old age with 50 sugar after metabolism; children 1 and 2 get 25 each; child 3 dies too.
    agents = [_agent(2, 2, 51.0, 31),
              _agent(6, 2, 10.0, 90, parent_a=0), _agent(10, 2, 10.0, 90, parent_a=0), _agent(14, 2, 10.0, 31, parent_a=0)]
    gpu = run_gpu(exe, tmp_path, CFG, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    sugar = _compare(gpu, run_python(CFG, EMPTY, agents, 1))
    assert set(sugar) == {1, 2}
    for uid, (g, p) in sugar.items():
        assert math.isclose(g, p, abs_tol=1e-9) and math.isclose(p, 34.0), (uid, g, p)


def test_two_parents_die_together(exe, tmp_path):
    # Both parents die in period 1; the child gets both shares, added in the parents' creation order.
    agents = [_agent(2, 2, 10.3, 31), _agent(6, 2, 7.7, 31), _agent(10, 2, 0.1 + 1.0, 90, parent_a=1, parent_b=0)]
    gpu = run_gpu(exe, tmp_path, CFG, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    sugar = _compare(gpu, run_python(CFG, EMPTY, agents, 1))
    assert sugar[2][0] == sugar[2][1], sugar


def test_inheritance_serial_equivalence_and_check(exe, tmp_path):
    # III-7's rules with short lives, so parents die with children alive: waves equal serial mode, and --check holds.
    from test_sex import _files

    cfg = {"sex": "true", "inheritance": "true", "max_age": "30,40", "endowment": "50,100", "placement": "block",
           "block": "0,0,20,20", "initial_population": "400"}
    assert _files(exe, tmp_path / "w", cfg, 40) == _files(exe, tmp_path / "s", cfg, 40, "--serial-turns")
    assert _files(exe, tmp_path / "c", cfg, 40, "--check") == _files(exe, tmp_path / "w2", cfg, 40)


def test_no_inheritance_flag(exe, tmp_path):
    agents = [_agent(2, 2, 51.0, 31), _agent(6, 2, 10.0, 90, parent_a=0)]
    cfg = {**CFG, "inheritance": "false"}
    gpu = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    sugar = _compare(gpu, run_python(cfg, EMPTY, agents, 1))
    assert sugar == {1: (9.0, 9.0)}


def _compare_spice(gpu, py):
    g = {a["uid"]: a for a in gpu.agents}
    p = {a["uid"]: a for a in py.agents}
    assert set(g) == set(p)
    return {uid: (g[uid]["spice"], p[uid]["spice"]) for uid in p}


def test_old_age_inheritance_spice(exe, tmp_path):
    # test_inheritance_matches_python with spice (Part C, Task 4): the parent's 60 spice goes 30 to each living child.
    cfg = {**CFG, "spice": "true"}
    spice = {"spice": 10.0, "spice_metabolism": 1}
    agents = [_agent(2, 2, 51.0, 31, spice=61.0, spice_metabolism=1),
              _agent(6, 2, 10.0, 90, parent_a=0, **spice), _agent(10, 2, 10.0, 90, parent_a=0, **spice),
              _agent(14, 2, 10.0, 31, parent_a=0, **spice)]
    gpu = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, EMPTY, agents, 1)
    for uid, (g, p) in _compare(gpu, py).items():
        assert math.isclose(g, p, abs_tol=1e-9), (uid, g, p)
    shares = _compare_spice(gpu, py)
    assert set(shares) == {1, 2}
    for uid, (g, p) in shares.items():
        assert math.isclose(g, p, abs_tol=1e-9) and math.isclose(p, 39.0), (uid, g, p)


def test_starved_heirs_get_spice(exe, tmp_path):
    # A parent starving of sugar in its turn leaves 30 spice: 15 to each child (Python Model.die at starvation). Rule I
    # with spice runs one turn per wave (plan ruling R1).
    import json

    cfg = {"inheritance": "true", "spice": "true", "max_age": "60,100"}
    still = {"metabolism": 0, "spice": 10.0, "spice_metabolism": 0}
    agents = [_agent(2, 2, 1.0, 90, metabolism=2, spice=30.0, spice_metabolism=0),
              _agent(10, 10, 10.0, 90, parent_a=0, **still), _agent(15, 15, 10.0, 90, parent_a=0, **still)]
    timing = tmp_path / "timing.json"
    gpu = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=1, extra_args=("--timing", timing))
    assert gpu.returncode == 0, gpu.stderr
    shares = _compare_spice(gpu, run_python(cfg, EMPTY, agents, 1))
    assert set(shares) == {1, 2}
    for uid, (g, p) in shares.items():
        assert math.isclose(g, p, abs_tol=1e-9) and math.isclose(p, 25.0), (uid, g, p)
    t = json.loads(timing.read_text())
    assert t["waves_mean"] == t["agents_start"]


def test_inheritance_without_sex_matches_python(exe, tmp_path):
    # Rule I needs no rule S: children given by --init inherit as in Python, though no sex or culture is on.
    agents = [_agent(2, 2, 51.0, 31), _agent(6, 2, 10.0, 90, parent_a=0), _agent(10, 2, 10.0, 90, parent_a=0)]
    cfg = {"inheritance": "true", "max_age": "60,100"}
    gpu = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    sugar = _compare(gpu, run_python(cfg, EMPTY, agents, 1))
    assert set(sugar) == {1, 2}
    for uid, (g, p) in sugar.items():
        assert math.isclose(g, p, abs_tol=1e-9) and math.isclose(p, 34.0), (uid, g, p)
