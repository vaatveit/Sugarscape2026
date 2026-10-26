"""Combat C_alpha and C_inf in the turn (pp.82-83; spec 2026-10-25-gpu-full-parity, sections 2 and 4; Part B).

Exact comparisons with Python use scenes the order and the draws cannot change: every agent but the attacker has
vision 0 and metabolism 0 on a site of capacity 0, so its own turn changes nothing.
"""

import json

import numpy as np
import pytest

from bridge.config_cfg import config_to_cfg
from conftest import run_exe
from experiments.registry import EXPERIMENTS
from gpu import compare_dumps, read_rows, run_gpu, write_cfg
from reference import python_metric_rows, run_python
from test_sex import _files

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
    gpu = run_gpu(exe, tmp_path, cfg, ATTACK, agents, steps=1, extra_args=("--out", out, "--check"))
    assert gpu.returncode == 0, gpu.stderr
    g = read_rows(out)[-1]
    p = python_metric_rows(cfg, ATTACK, agents, 1)[-1]
    for key in ("population", "agents_ever"):
        assert g[key] == p[key], (key, g[key], p[key])
    assert g["population"] == 1


# --- Task 3: combat turns in waves ---------------------------------------------------------------------------


def registry_cfg(exp_id: str, **overrides: str) -> dict:
    """A registered experiment's run.cfg as write_cfg overrides (the map, steps and seed left to the test)."""
    text = config_to_cfg(EXPERIMENTS[exp_id].config, steps=1, seed=0)
    cfg = dict(line.split(" = ", 1) for line in text.splitlines())
    for key in ("map", "steps", "seed"):
        cfg.pop(key)
    return {**cfg, **overrides}


COMBAT_CASES = {
    "III-9": registry_cfg("III-9"),
    "III-11": registry_cfg("III-11"),
    "III-13": registry_cfg("III-13"),
    "stride5": registry_cfg("III-9", vision="5,10", look_stride="5"),
}


@pytest.mark.parametrize("name", COMBAT_CASES)
def test_serial_equivalence_combat(exe, tmp_path, name):
    waves = _files(exe, tmp_path / "waves", COMBAT_CASES[name], 20)
    assert waves == _files(exe, tmp_path / "serial", COMBAT_CASES[name], 20, "--serial-turns")


@pytest.mark.parametrize("name", ["III-9", "III-13", "stride5"])
def test_combat_check(exe, tmp_path, name):
    # --check looks up every site a turn touches in its own footprint (store.h, touch()): exit 3 on a miss.
    result = run_exe(exe, "--config", write_cfg(tmp_path, **COMBAT_CASES[name], steps="20"), "--check")
    assert result.returncode == 0, result.stderr


def test_combat_waves_concurrent(exe, tmp_path):
    timing = tmp_path / "timing.json"
    result = run_exe(exe, "--config", write_cfg(tmp_path, **COMBAT_CASES["III-9"], steps="3"), "--timing", timing)
    assert result.returncode == 0, result.stderr
    t = json.loads(timing.read_text())
    assert 1 < t["waves_mean"] < t["agents_start"] / 2, t


# --- Task 4: combat with culture K and sex S; newborn victims -------------------------------------------------

SEX_COMBAT = {"sex": "true", "max_age": "60,100", "endowment": "50,100"}
# The equivalence cases leave replacement out: with dozens of newcomers a period, place_newcomer's CAS race between two
# newcomers drawing the same site is decided by the GPU's timing (a placement issue older than combat, ledgered in
# Part B). The --check runs keep it, newborn victims' newcomers included.
COMBAT_CASES.update({
    "III-14": registry_cfg("III-14"),
    "sex_neighbors": registry_cfg("III-9", **SEX_COMBAT, mate_contact="neighbors"),
    "sex_vision": registry_cfg("III-9", **SEX_COMBAT, mate_contact="vision"),
})


@pytest.mark.parametrize("name", ["III-14", "sex_neighbors", "sex_vision"])
def test_combat_with_rules_check(exe, tmp_path, name):
    cfg = {**COMBAT_CASES[name], **({"replacement": "true"} if name.startswith("sex") else {})}
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg, steps="20"), "--check")
    assert result.returncode == 0, result.stderr


def test_killed_friend_dropped(exe, tmp_path):
    # A kills V in period 1; X, far away, holds V as a friend. Whether X's turn came before the kill or after, X has
    # dropped V by the end of period 2, as in Python.
    agents = [_attacker(sugar=50.0, vision=1), _still(6, 5, BLUE, 5), _still(15, 15, BLUE, 50, friends="1:0")]
    cfg = {**COMBAT, "combat_alpha": "inf", "culture": "true"}
    gpu = run_gpu(exe, tmp_path, cfg, _world(), agents, steps=2)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, _world(), agents, 2)
    assert {a["uid"]: a["friends"] for a in gpu.agents} == {a["uid"]: a["friends"] for a in py.agents}
    assert [a["friends"] for a in gpu.agents if a["uid"] == 2] == [""]


def _newborn_scene():
    # F and M (blue) mate in their turns: (5,6) is the only empty site next to either, the rest blocked by richer blues.
    # A (red, vision 3) sees (5,6) from (5,9): before the child exists every reward is 0 and A stays; after, the child
    # (sugar 25 + 25) is the best reward and safe (the blockers' 120 < 100 + 50), so A kills it.
    parent = {"vision": 0, "metabolism": 0, "sugar": 60.0, "age": 20, "initial_sugar": 50.0, "fertility_start": 12,
              "tags": BLUE}
    return ([{"x": 5, "y": 5, "sex": "F", "fertility_end": 50, **parent},
             {"x": 6, "y": 5, "sex": "M", "fertility_end": 60, **parent}] +
            [_still(x, y, BLUE, 120) for x, y in ((4, 5), (5, 4), (7, 5), (6, 6), (6, 4))] +
            [{"x": 5, "y": 9, "vision": 3, "metabolism": 0, "sugar": 100.0, "tags": RED}])


NEWBORN_CFG = {**COMBAT, "combat_alpha": "inf", "sex": "true", "mate_contact": "neighbors", "replacement": "true",
               "max_age": "60,100"}


def _newborn_outcome(agents, ever):
    """'killed' or 'survived', checking what each outcome must show (8 founders)."""
    attacker = [a for a in agents if a["tags"] == RED and a["metabolism"] == 0]  # newcomers draw metabolism 1-4
    killed = (attacker[0]["x"], attacker[0]["y"]) == (5, 6)
    child = [a for a in agents if (a["x"], a["y"]) == (5, 6) and a["tags"] == BLUE]
    if killed:
        assert not child and len(agents) == 9 and ever == 10, (agents, ever)  # the newcomer replaced the child
        return "killed"
    assert (attacker[0]["x"], attacker[0]["y"]) == (5, 9) and len(child) == 1 and len(agents) == 9 and ever == 9
    return "survived"


def test_newborn_victim(exe, tmp_path):
    gpu_outcomes, py_outcomes = set(), set()
    for seed in range(20):
        d = tmp_path / str(seed)
        d.mkdir()
        cfg = {**NEWBORN_CFG, "seed": str(seed)}
        out = d / "metrics.csv"
        gpu = run_gpu(exe, d, cfg, _world(), _newborn_scene(), steps=1, extra_args=("--out", out, "--check"))
        assert gpu.returncode == 0, gpu.stderr
        gpu_outcomes.add(_newborn_outcome(gpu.agents, read_rows(out)[-1]["agents_ever"]))
        py = run_python(cfg, _world(), _newborn_scene(), 1)
        py_ever = python_metric_rows(cfg, _world(), _newborn_scene(), 1)[-1]["agents_ever"]
        py_outcomes.add(_newborn_outcome(py.agents, py_ever))
    assert gpu_outcomes == py_outcomes == {"killed", "survived"}


def test_births_carry_defaults(exe, tmp_path):
    # Every agent made this period (age 0: newcomers and children) holds the model's defaults in what its birth does
    # not set. FLAME GPU rc.5 writes new agents' defaults unaligned (CUDAScatter::broadcastInit_async), so in an
    # odd-sized output the last agents got the next variable's default or uninitialised memory; every output now sets
    # every variable. Combat with sex and replacement makes many births a period.
    for t in range(1, 7):
        d = tmp_path / str(t)
        _files(exe, d, {**COMBAT_CASES["sex_vision"], "replacement": "true"}, t)
        for a in read_rows(d / "agents.csv"):
            if a["age"] != 0:
                continue
            assert (a["neighbors"], a["moved"], a["n_friends"], a["friends"], a["disp_x"], a["disp_y"]) == \
                (0, 0, 0, "", 0, 0), (t, a)
            assert (a["parent_a"] is None) == (a["parent_b"] is None), (t, a)  # a newcomer has neither
