"""Combat C_alpha and C_inf in the turn (pp.82-83; spec 2026-10-25-gpu-full-parity, sections 2 and 4; Part B).

Exact comparisons with Python use scenes the order and the draws cannot change: every agent but the attacker has
vision 0 and metabolism 0 on a site of capacity 0, so its own turn changes nothing.
"""

import numpy as np
import pytest

from gpu import compare_dumps, read_rows, run_gpu
from reference import python_metric_rows, run_python

BLUE, RED = "0", "1"
COMBAT = {"tag_length": "1"}


def _still(x, y, tags, sugar, **kw):
    return {"x": x, "y": y, "vision": 0, "metabolism": 0, "sugar": float(sugar), "tags": tags, **kw}


def _attacker(**kw):
    return {"x": 5, "y": 5, "vision": 2, "metabolism": 1, "sugar": 20.0, "tags": RED, **kw}


def _world(*sites):
    capacity = np.zeros((20, 20), dtype=int)
    for (x, y), c in sites:
        capacity[x, y] = c
    return capacity


ATTACK = _world(((5, 7), 3))


def _both(exe, tmp_path, alpha, capacity, agents, steps=1, cfg=None, pollution=False):
    cfg = {**COMBAT, "combat_alpha": alpha, **(cfg or {})}
    gpu = run_gpu(exe, tmp_path, cfg, capacity, agents, steps=steps)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, capacity, agents, steps)
    assert compare_dumps(gpu, py, pollution=pollution) == []
    return gpu


def _at(dump, x, y):
    return [a for a in dump.agents if (a["x"], a["y"]) == (x, y)]


@pytest.mark.parametrize("alpha", ["2", "inf"])
def test_attack_matches_python(exe, tmp_path, alpha):
    # V's site rewards min(alpha, 5); the empty site at (5,7) rewards 3. Alpha 2 goes there; C_inf kills V.
    gpu = _both(exe, tmp_path, alpha, ATTACK, [_attacker(), _still(6, 5, BLUE, 5)])
    if alpha == "2":
        assert len(gpu.agents) == 2 and _at(gpu, 5, 7)[0]["sugar"] == pytest.approx(22.0)
    else:
        assert len(gpu.agents) == 1 and _at(gpu, 6, 5)[0]["sugar"] == pytest.approx(24.0)


def test_retaliation_blocks_attack(exe, tmp_path):
    # R (blue, 100) is in A's vision of V's site and would be bigger than A after the attack: A goes to (5,7).
    gpu = _both(exe, tmp_path, "inf", ATTACK, [_attacker(), _still(6, 5, BLUE, 5), _still(8, 5, BLUE, 100)])
    assert len(gpu.agents) == 3 and _at(gpu, 5, 7)


def test_no_safe_site_stays(exe, tmp_path):
    # Four richer blues around A: no candidate but A's own site, and that one is vulnerable. A stays and harvests.
    guards = [_still(x, y, BLUE, 100) for x, y in ((6, 5), (4, 5), (5, 6), (5, 4))]
    gpu = _both(exe, tmp_path, "inf", _world(((5, 5), 2)), [_attacker(vision=1), *guards])
    assert _at(gpu, 5, 5)[0]["sugar"] == pytest.approx(21.0)


def test_same_tribe_not_attacked(exe, tmp_path):
    gpu = _both(exe, tmp_path, "inf", ATTACK, [_attacker(), _still(6, 5, RED, 5)])
    assert len(gpu.agents) == 2 and _at(gpu, 5, 7)


def test_richer_not_attacked(exe, tmp_path):
    gpu = _both(exe, tmp_path, "inf", ATTACK, [_attacker(), _still(6, 5, BLUE, 30)])
    assert len(gpu.agents) == 2 and _at(gpu, 5, 7)


def test_equal_reward_nearer_wins(exe, tmp_path):
    # Equal rewards at distances 2 and 1: the nearer, whatever the period's direction order.
    world = _world(((7, 5), 4), ((5, 6), 4))
    for seed in range(10):
        (tmp_path / str(seed)).mkdir()
        gpu = _both(exe, tmp_path / str(seed), "inf", world, [_attacker(vision=3)], cfg={"seed": str(seed)})
        assert _at(gpu, 5, 6), seed


def test_combat_harvest_unpolluted(exe, tmp_path):
    # Python's combat_move harvests without production pollution; consumption (beta 0 here) adds none either.
    _both(exe, tmp_path, "2", ATTACK, [_attacker(), _still(6, 5, BLUE, 5)], cfg={"pollution": "1,0"}, pollution=True)


def test_victim_counted_once(exe, tmp_path):
    agents = [_attacker(), _still(6, 5, BLUE, 5)]
    cfg = {**COMBAT, "combat_alpha": "inf"}
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, cfg, ATTACK, agents, steps=1, extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    g = read_rows(out)[-1]
    p = python_metric_rows(cfg, ATTACK, agents, 1)[-1]
    for key in ("population", "agents_ever"):
        assert g[key] == p[key], (key, g[key], p[key])
    assert g["population"] == 1
